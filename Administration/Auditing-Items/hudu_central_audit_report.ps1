#Requires -Version 7.0
# =============================================================================
# HUDU CENTRAL AUDIT KB REPORT
# =============================================================================
# HUMAN INSTRUCTIONS: See Hudu_Central_Audit_Report_Instructions.txt (same folder).
# =============================================================================
# PURPOSE:
# Build a single source-of-truth Hudu KB article with global and per-company
# inventory counts. This script uses Azure Key Vault secrets for Hudu auth.
# Data collection is read-only (GET). The only write is create/update of one KB
# article by title — it does not delete records or mutate companies, assets, etc.
#
# QUICK SETUP:
# 1) Set the Key Vault and secret names in the CONFIGURATION section below.
# 2) Set $CentralReportArticleName to the exact KB article title (default: Central Audit Report).
# 3) Run the script. It will create/update one central KB article each run.
#
# REQUIRED KEY VAULT SECRETS (create in Azure Key Vault > Secrets):
# - Hudu API key (e.g. secret name AUDITAPI)
# - Hudu base URL / domain (e.g. AUDITURL) — any common format is normalized
#
# See Hudu_Central_Audit_Report_Instructions.txt in this folder for full steps.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$VerifyEndpoints,
    [ValidateRange(1, 5000)]
    [int]$PageSize = 200,
    [ValidateRange(10, 600)]
    [int]$ApiTimeoutSec = 120,
    [ValidateRange(100000, 5000000)]
    [int]$MaxHtmlCharacters = 900000,
    <#
        Full: all tables (largest HTML; may hit Hudu render limits on very large instances).
        Compact: global summary, company grand totals, assets by layout (global), assets by company — omits heavy per-company grids.
        Executive: global summary + errors only (smallest payload; use if /kba/.../renders returns 500).
    #>
    [ValidateSet("Full", "Compact", "Executive")]
    [string]$ReportDetailLevel = "Executive"
)

# -----------------------------------------------------------------------------
# CONFIGURATION - EDIT THESE VALUES
# -----------------------------------------------------------------------------
$AzVault_Name = "hudu-pshell-learning"

# Secret name that stores Hudu API key
$AzVault_HuduApiKeySecretName = "AUDITAPI"

# Secret name that stores Hudu base domain
$AzVault_HuduBaseDomainSecretName = "AUDITURL"

# Exact KB article title to create or update
$CentralReportArticleName = "Central Audit Report"

# Folder selection is always left to Hudu defaults; never force folder_id.

# -----------------------------------------------------------------------------
# SCRIPT STATE
# -----------------------------------------------------------------------------
$script:HuduAPIKey = $null
$script:HuduBaseDomain = $null
$script:BaseApiUrl = $null
$script:Headers = $null
$script:ApiInfo = $null
$script:SectionErrors = @()

function Get-RetryAfterSeconds {
    param([object]$ErrorRecord)
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($null -eq $resp) { return $null }
        $hdr = $resp.Headers["Retry-After"]
        if ([string]::IsNullOrWhiteSpace([string]$hdr)) { return $null }

        $retryRaw = [string]$hdr
        $seconds = 0
        if ([int]::TryParse($retryRaw, [ref]$seconds)) {
            return [Math]::Max(1, $seconds)
        }

        $when = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse($retryRaw, [ref]$when)) {
            $delta = [int][Math]::Ceiling(($when.ToUniversalTime() - [datetimeoffset]::UtcNow).TotalSeconds)
            return [Math]::Max(1, $delta)
        }
    } catch {}
    return $null
}

function Add-SectionError {
    param([string]$Section, [string]$Message)
    $script:SectionErrors += [PSCustomObject]@{
        ErrorName = $Section
        Reason = $Message
    }
}

function Clear-SensitiveData {
    $script:HuduAPIKey = $null
    $script:HuduBaseDomain = $null
    $script:BaseApiUrl = $null
    $script:Headers = $null
    $script:ApiInfo = $null
    $AzVault_Name = $null
    $AzVault_HuduApiKeySecretName = $null
    $AzVault_HuduBaseDomainSecretName = $null
    [System.GC]::Collect()
}

function Ensure-AzModules {
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Install-Module Az.Accounts -Scope CurrentUser -Force -AllowClobber
    }
    if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        Install-Module Az.KeyVault -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.KeyVault -ErrorAction Stop
}

function Normalize-HuduBaseDomain {
    param([Parameter(Mandatory = $true)][string]$DomainInput)

    $raw = $DomainInput.Trim().Trim("'`"")
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Hudu base domain is empty."
    }

    if ($raw.StartsWith("//")) {
        $raw = "https:$raw"
    } elseif (-not ($raw -match "^[a-zA-Z][a-zA-Z0-9+\-.]*://")) {
        $raw = "https://$raw"
    }

    try {
        $uri = [Uri]$raw
    } catch {
        throw "Invalid Hudu base domain format: '$DomainInput'"
    }

    if (-not $uri.Host) {
        throw "Invalid Hudu base domain format: '$DomainInput'"
    }

    $builder = [System.UriBuilder]::new($uri.Scheme, $uri.Host, $uri.Port)
    $builder.Path = ""
    $builder.Query = ""
    $builder.Fragment = ""

    return $builder.Uri.AbsoluteUri.TrimEnd("/")
}

function Initialize-HuduConnection {
    $maxAttempts = 3
    $attempt = 0
    $validated = $false

    Write-Host "Validating Hudu credentials..."
    do {
        $attempt++
        Write-Host "Attempt $attempt of $maxAttempts..."
        try {
            $script:HuduAPIKey = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $AzVault_HuduApiKeySecretName -AsPlainText -ErrorAction Stop
            $domainRaw = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $AzVault_HuduBaseDomainSecretName -AsPlainText -ErrorAction Stop

            if ([string]::IsNullOrWhiteSpace($script:HuduAPIKey) -or [string]::IsNullOrWhiteSpace($domainRaw)) {
                throw "Empty credentials retrieved from Key Vault"
            }

            $script:HuduBaseDomain = Normalize-HuduBaseDomain -DomainInput $domainRaw
            $script:BaseApiUrl = "$script:HuduBaseDomain/api/v1"
            $script:Headers = @{
                "x-api-key"    = $script:HuduAPIKey
                "Accept"       = "application/json"
                "Content-Type" = "application/json"
            }

            $script:ApiInfo = Invoke-RestMethod -Uri "$script:BaseApiUrl/api_info" -Method GET -Headers @{ "x-api-key" = $script:HuduAPIKey } -ErrorAction Stop
            $validated = $true
            Write-Host "  ✓ Credentials validated successfully"
        } catch {
            Write-Warning "  ✗ Credential validation failed: $_"
            if ($attempt -lt $maxAttempts) {
                Start-Sleep -Seconds 3
            } else {
                throw "Credential validation failed after $maxAttempts attempts."
            }
        }
    } while (-not $validated -and $attempt -lt $maxAttempts)
}

function Invoke-HuduApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [object]$Body = $null,
        [int]$MaxRetries = 4
    )

    $uri = "$script:BaseApiUrl$Endpoint"
    $attempt = 0
    do {
        $attempt++
        try {
            $params = @{
                Method      = $Method
                Uri         = $uri
                Headers     = $script:Headers
                TimeoutSec  = $ApiTimeoutSec
                ErrorAction = "Stop"
            }
            if ($null -ne $Body) {
                $params.Body = ($Body | ConvertTo-Json -Depth 20)
            }
            return Invoke-RestMethod @params
        } catch {
            $statusCode = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $retryable = ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600))
            if ($retryable -and $attempt -lt $MaxRetries) {
                $retryAfter = Get-RetryAfterSeconds -ErrorRecord $_
                $baseSleep = if ($null -ne $retryAfter) { $retryAfter } else { [Math]::Pow(2, $attempt) }
                $jitter = Get-Random -Minimum 0 -Maximum 2
                $sleep = [Math]::Min(60, [int]($baseSleep + $jitter))
                Write-Host "Retryable API error ($statusCode). Retrying in $sleep second(s)..."
                Start-Sleep -Seconds $sleep
            } else {
                throw
            }
        }
    } while ($attempt -lt $MaxRetries)
}

function Get-ArticleUpdatedUtc {
    param([object]$Article)
    if ($null -eq $Article) { return $null }
    try {
        $prop = $Article.PSObject.Properties["updated_at"]
        if (-not $prop -or $null -eq $prop.Value) { return $null }
        $raw = $prop.Value.ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return [datetime]::Parse($raw, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    } catch {
        return $null
    }
}

function Get-ArticleById {
    param([Parameter(Mandatory = $true)][int]$Id)
    $resp = Invoke-HuduApi -Method "GET" -Endpoint "/articles/$Id"
    if ($resp.article) { return $resp.article }
    return $resp
}

function Resolve-CentralReportArticleTarget {
    param(
        [array]$Articles,
        [Parameter(Mandatory = $true)][string]$ArticleTitle
    )

    $sameName = @($Articles | Where-Object { $_.name -eq $ArticleTitle })
    if ($sameName.Count -eq 0) {
        return [PSCustomObject]@{ Action = "Create"; Target = $null }
    }

    $candidates = @()
    $hydrateFailures = @()
    foreach ($a in $sameName) {
        $row = $a
        if ($sameName.Count -gt 1 -or ($null -eq (Get-ArticleUpdatedUtc -Article $a))) {
            try {
                $row = Get-ArticleById -Id ([int]$a.id)
            } catch {
                $row = $a
                $hydrateFailures += [int]$a.id
            }
        }
        $candidates += $row
    }

    if ($sameName.Count -gt 1 -and $hydrateFailures.Count -gt 0) {
        throw "Cannot reliably resolve duplicate central report articles because details could not be loaded for article ID(s): $($hydrateFailures -join ', '). Resolve duplicates or retry."
    }

    $sorted = @(
        $candidates | Sort-Object `
            @{ Expression = { $d = Get-ArticleUpdatedUtc -Article $_; if ($null -eq $d) { [datetime]::MinValue } else { $d } }; Descending = $true },
            @{ Expression = { [int]$_.id }; Descending = $true }
    )
    $chosen = $sorted[0]

    if ($sameName.Count -gt 1) {
        $when = Get-ArticleUpdatedUtc -Article $chosen
        $whenText = if ($null -ne $when) { $when.ToString("u") } else { "unknown" }
        $others = ($sorted | Select-Object -Skip 1 | ForEach-Object { $_.id }) -join ", "
        Add-SectionError -Section "Central report article" -Message "Multiple KB articles titled '$ArticleTitle' exist ($($sameName.Count)). Updating article ID $($chosen.id) (latest updated_at: $whenText; tie-break: higher id). Other IDs: $others. Consolidate or rename duplicates in Hudu."
    }

    return [PSCustomObject]@{ Action = "Update"; Target = $chosen }
}

function Get-PaginatedCollection {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [string]$CollectionProperty = "",
        [int]$PageSize = 200,
        [switch]$DisablePaging
    )

    if ($DisablePaging) {
        $singleResponse = Invoke-HuduApi -Method "GET" -Endpoint $Endpoint
        if ([string]::IsNullOrWhiteSpace($CollectionProperty)) {
            if ($singleResponse -is [array]) { return $singleResponse }
            return @($singleResponse)
        }
        $singleProp = $singleResponse.PSObject.Properties[$CollectionProperty]
        if ($singleProp) { return @($singleProp.Value) }
        if ($singleResponse -is [array]) { return $singleResponse }
        return @()
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $page = 1
    $pageFingerprints = @{}
    $maxPages = 10000
    while ($true) {
        if ($page -gt $maxPages) {
            throw "Pagination safety stop reached at page $maxPages for endpoint '$Endpoint'."
        }
        $joinChar = if ($Endpoint.Contains("?")) { "&" } else { "?" }
        try {
            $response = Invoke-HuduApi -Method "GET" -Endpoint "$Endpoint${joinChar}page=$page&page_size=$PageSize"
        } catch {
            # Some Hudu endpoints do not support page/page_size query parameters.
            if ($page -eq 1 -and "$_" -match "page.+not a valid|page_size.+not a valid|not a valid.+parameter") {
                $response = Invoke-HuduApi -Method "GET" -Endpoint $Endpoint
            } else {
                throw
            }
        }

        $current = @()
        if ([string]::IsNullOrWhiteSpace($CollectionProperty)) {
            if ($response -is [array]) { $current = $response } else { $current = @($response) }
        } else {
            $prop = $response.PSObject.Properties[$CollectionProperty]
            if ($prop) {
                $current = @($prop.Value)
            } elseif ($response -is [array]) {
                $current = $response
            } else {
                $current = @()
            }
        }

        if (-not $current -or $current.Count -eq 0) { break }

        $sampleParts = @($current.Count)
        for ($i = 0; $i -lt [Math]::Min(3, $current.Count); $i++) {
            $row = $current[$i]
            $rowId = $null
            if ($row.PSObject.Properties["id"]) { $rowId = $row.id }
            elseif ($row.PSObject.Properties["company_id"]) { $rowId = $row.company_id }
            $sampleParts += "$rowId"
        }
        $fingerprint = ($sampleParts -join "|")
        if ($pageFingerprints.ContainsKey($fingerprint)) {
            throw "Pagination appears non-advancing for endpoint '$Endpoint' (page parameter may be ignored by API)."
        }
        $pageFingerprints[$fingerprint] = $true

        foreach ($item in $current) {
            [void]$items.Add($item)
        }
        $page++
    }

    return @($items)
}

function Get-EntityData {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [string]$CollectionProperty = "",
        [string]$CompanyProperty = "company_id",
        [switch]$HasArchived,
        [switch]$DisablePaging
    )

    try {
        $rows = Get-PaginatedCollection -Endpoint $Endpoint -CollectionProperty $CollectionProperty -PageSize $PageSize -DisablePaging:$DisablePaging
    } catch {
        Add-SectionError -Section $Name -Message "$_"
        return [PSCustomObject]@{
            Name = $Name; Rows = @(); CompanyProperty = $CompanyProperty; HasArchived = $HasArchived.IsPresent; Success = $false
        }
    }

    return [PSCustomObject]@{
        Name = $Name
        Rows = $rows
        CompanyProperty = $CompanyProperty
        HasArchived = $HasArchived.IsPresent
        Success = $true
    }
}

function Invoke-HuduReportEndpointVerification {
    Write-Host "Verifying Hudu API endpoints used by this report (same calls as data collection)..."
    $checks = @(
        @{ Name = "Companies"; Endpoint = "/companies"; CollectionProperty = "companies"; DisablePaging = $false },
        @{ Name = "Asset layouts"; Endpoint = "/asset_layouts"; CollectionProperty = "asset_layouts"; DisablePaging = $false },
        @{ Name = "Articles"; Endpoint = "/articles"; CollectionProperty = "articles"; DisablePaging = $false },
        @{ Name = "Assets"; Endpoint = "/assets"; CollectionProperty = "assets"; DisablePaging = $false },
        @{ Name = "Asset passwords"; Endpoint = "/asset_passwords"; CollectionProperty = "asset_passwords"; DisablePaging = $false },
        @{ Name = "Folders"; Endpoint = "/folders"; CollectionProperty = "folders"; DisablePaging = $false },
        @{ Name = "Password folders"; Endpoint = "/password_folders"; CollectionProperty = "password_folders"; DisablePaging = $false },
        @{ Name = "Networks"; Endpoint = "/networks"; CollectionProperty = ""; DisablePaging = $true },
        @{ Name = "IP addresses"; Endpoint = "/ip_addresses"; CollectionProperty = ""; DisablePaging = $true },
        @{ Name = "Websites"; Endpoint = "/websites"; CollectionProperty = ""; DisablePaging = $true },
        @{ Name = "Procedures"; Endpoint = "/procedures"; CollectionProperty = "procedures"; DisablePaging = $false },
        @{ Name = "Expirations"; Endpoint = "/expirations"; CollectionProperty = ""; DisablePaging = $false },
        @{ Name = "VLANs"; Endpoint = "/vlans"; CollectionProperty = ""; DisablePaging = $true },
        @{ Name = "VLAN zones"; Endpoint = "/vlan_zones"; CollectionProperty = ""; DisablePaging = $true },
        @{ Name = "Rack storages"; Endpoint = "/rack_storages"; CollectionProperty = ""; DisablePaging = $true },
        @{ Name = "Rack storage items"; Endpoint = "/rack_storage_items"; CollectionProperty = ""; DisablePaging = $true }
    )

    $fail = 0
    foreach ($c in $checks) {
        try {
            $rows = Get-PaginatedCollection -Endpoint $c.Endpoint -CollectionProperty $c.CollectionProperty -PageSize $PageSize -DisablePaging:$c.DisablePaging
            $n = if ($null -eq $rows) { 0 } else { @($rows).Count }
            Write-Host ("  [OK] {0,-22} {1,6} row(s)  {2}" -f $c.Name, $n, $c.Endpoint)
        } catch {
            $fail++
            Write-Warning ("  [FAIL] {0} {1}: {2}" -f $c.Name, $c.Endpoint, $_)
        }
    }

    Write-Host "Endpoint verification finished. Failures: $fail"
    return $fail
}

function Test-HuduRowArchived {
    param([object]$Row)
    if ($null -eq $Row) { return $false }
    $archProp = $Row.PSObject.Properties["archived"]
    if ($archProp -and $archProp.Value) { return $true }
    $discProp = $Row.PSObject.Properties["discarded_at"]
    if ($discProp -and -not [string]::IsNullOrWhiteSpace([string]$discProp.Value)) { return $true }
    return $false
}

function Get-CountObject {
    param([array]$Rows, [bool]$HasArchived)
    if (-not $Rows) { $Rows = @() }
    if (-not $HasArchived) {
        return [PSCustomObject]@{
            Active = $Rows.Count
            Archived = 0
            Total = $Rows.Count
        }
    }

    $active = ($Rows | Where-Object { -not (Test-HuduRowArchived $_) }).Count
    $archived = ($Rows | Where-Object { Test-HuduRowArchived $_ }).Count
    return [PSCustomObject]@{
        Active = $active
        Archived = $archived
        Total = ($active + $archived)
    }
}

function Build-CompanyCountTableRows {
    param(
        [array]$Companies,
        [array]$Rows,
        [string]$CompanyProperty = "company_id",
        [ValidateSet("aac", "total")]
        [string]$Mode = "aac",
        [hashtable]$CompanyIndex = @{}
    )

    $dash = [char]0x2014
    $out = @()
    foreach ($company in ($Companies | Sort-Object name)) {
        $bucketKey = [string]$company.id
        $companyItems = @()
        if ($CompanyIndex.ContainsKey($bucketKey)) {
            $companyItems = @($CompanyIndex[$bucketKey])
        }
        if ($Mode -eq "total") {
            $c = Get-CountObject -Rows $companyItems -HasArchived:$false
            $out += [PSCustomObject]@{
                CompanyId = $company.id
                CompanyName = $company.name
                Active = $dash
                Archived = $dash
                Total = $c.Total
            }
        } else {
            $c = Get-CountObject -Rows $companyItems -HasArchived:$true
            $out += [PSCustomObject]@{
                CompanyId = $company.id
                CompanyName = $company.name
                Active = $c.Active
                Archived = $c.Archived
                Total = $c.Total
            }
        }
    }
    return $out
}

function Get-AuditEntityMeta {
    param(
        [hashtable]$Entities,
        [string]$Key
    )
    if (-not $Entities.ContainsKey($Key)) {
        return [PSCustomObject]@{ Rows = @(); CompanyProperty = "company_id"; HasArchived = $false }
    }
    return $Entities[$Key]
}

function To-HtmlTable {
    param(
        [array]$Rows,
        [array]$Columns
    )

    if (-not $Rows -or $Rows.Count -eq 0) { return "<p><em>No data.</em></p>" }
    if (-not $Columns -or $Columns.Count -eq 0) { return ($Rows | ConvertTo-Html -Fragment) }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<table><thead><tr>')
    foreach ($col in $Columns) {
        $safeLabel = [System.Net.WebUtility]::HtmlEncode([string]$col.Label)
        [void]$sb.Append("<th scope=`"col`"><strong>$safeLabel</strong></th>")
    }
    [void]$sb.Append('</tr></thead><tbody>')

    foreach ($row in $Rows) {
        [void]$sb.Append('<tr>')
        foreach ($col in $Columns) {
            $value = ""
            $prop = $row.PSObject.Properties[$col.Name]
            if ($prop) {
                $value = "$($prop.Value)"
            }
            $safe = [System.Net.WebUtility]::HtmlEncode($value)
            [void]$sb.Append("<td>$safe</td>")
        }
        [void]$sb.Append('</tr>')
    }

    [void]$sb.Append('</tbody></table>')
    return $sb.ToString()
}

function Resolve-CentralArticleName {
    param([array]$ExistingArticles)
    if (-not [string]::IsNullOrWhiteSpace($CentralReportArticleName)) { return $CentralReportArticleName }

    Write-Host ""
    Write-Host "No central report name configured."
    Write-Host "Example name: Global Audit Report"
    $name = Read-Host "Enter the exact central KB article name to use"
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Central article name is required."
    }
    return $name.Trim()
}

function New-GroupedIndex {
    param(
        [array]$Rows,
        [string]$PropertyName
    )
    $index = @{}
    if (-not $Rows -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return $index
    }
    foreach ($row in $Rows) {
        $prop = $row.PSObject.Properties[$PropertyName]
        if (-not $prop) { continue }
        $key = [string]$prop.Value
        if (-not $index.ContainsKey($key)) {
            $index[$key] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$index[$key].Add($row)
    }
    return $index
}

function Get-EffectiveReportPayload {
    param(
        [array]$Companies,
        [hashtable]$Entities,
        [array]$AssetLayouts,
        [ValidateSet("Full", "Compact", "Executive")]
        [string]$PreferredLevel
    )
    $order = @("Full", "Compact", "Executive")
    $start = [Array]::IndexOf($order, $PreferredLevel)
    if ($start -lt 0) { $start = 0 }

    for ($i = $start; $i -lt $order.Count; $i++) {
        $level = $order[$i]
        $html = Build-ReportHtml -Companies $Companies -Entities $Entities -AssetLayouts $AssetLayouts -ReportDetailLevel $level
        if ($html.Length -le $MaxHtmlCharacters) {
            if ($level -ne $PreferredLevel) {
                Add-SectionError -Section "Report size guard" -Message "HTML length exceeded limit ($MaxHtmlCharacters). Auto-downgraded from $PreferredLevel to $level."
                $html = Build-ReportHtml -Companies $Companies -Entities $Entities -AssetLayouts $AssetLayouts -ReportDetailLevel $level
            }
            return [PSCustomObject]@{ Html = $html; Level = $level }
        }
    }

    $htmlExec = Build-ReportHtml -Companies $Companies -Entities $Entities -AssetLayouts $AssetLayouts -ReportDetailLevel "Executive"
    Add-SectionError -Section "Report size guard" -Message "HTML still exceeded limit after fallback sequence; forcing Executive payload."
    $htmlExec = Build-ReportHtml -Companies $Companies -Entities $Entities -AssetLayouts $AssetLayouts -ReportDetailLevel "Executive"
    return [PSCustomObject]@{ Html = $htmlExec; Level = "Executive" }
}

function Build-ReportHtml {
    param(
        [array]$Companies,
        [hashtable]$Entities,
        [array]$AssetLayouts,
        [ValidateSet("Full", "Compact", "Executive")]
        [string]$ReportDetailLevel = "Full"
    )

    $generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"

    $execSpecs = @(
        @{ Key = "companies"; Label = "Total Companies" },
        @{ Key = "assets"; Label = "Total Assets" },
        @{ Key = "asset_layouts"; Label = "Total Asset Layouts" },
        @{ Key = "articles"; Label = "Total KB Articles" },
        @{ Key = "asset_passwords"; Label = "Total Asset Passwords" },
        @{ Key = "expirations"; Label = "Total Expirations" },
        @{ Key = "folders"; Label = "Total Folders" },
        @{ Key = "password_folders"; Label = "Total Password Folders" },
        @{ Key = "procedures"; Label = "Total Procedures" },
        @{ Key = "networks"; Label = "Total Networks" },
        @{ Key = "websites"; Label = "Total Websites" },
        @{ Key = "ip_addresses"; Label = "Total IP Addresses" },
        @{ Key = "rack_storages"; Label = "Total Rack Storages" },
        @{ Key = "rack_storage_items"; Label = "Total Rack Storage Items" },
        @{ Key = "vlans"; Label = "Total VLANs" },
        @{ Key = "vlan_zones"; Label = "Total VLAN Zones" }
    )

    $globalRows = @()
    foreach ($s in $execSpecs) {
        $meta = Get-AuditEntityMeta -Entities $Entities -Key $s.Key
        $counts = Get-CountObject -Rows @($meta.Rows) -HasArchived:([bool]$meta.HasArchived)
        $globalRows += [PSCustomObject]@{
            Resource = $s.Label
            Active = $counts.Active
            Archived = $counts.Archived
            Total = $counts.Total
        }
    }

    $errorTable = To-HtmlTable -Rows $script:SectionErrors -Columns @(
        [PSCustomObject]@{ Name = "ErrorName"; Label = "Error" },
        [PSCustomObject]@{ Name = "Reason"; Label = "Reason" }
    )
    $globalTable = To-HtmlTable -Rows $globalRows -Columns @(
        [PSCustomObject]@{ Name = "Resource"; Label = "Resource" },
        [PSCustomObject]@{ Name = "Active"; Label = "Active" },
        [PSCustomObject]@{ Name = "Archived"; Label = "Archived" },
        [PSCustomObject]@{ Name = "Total"; Label = "Total" }
    )

    if ($ReportDetailLevel -eq "Executive") {
        $style = @"
<style>
.hudu-audit-report {
  font-family: "Segoe UI", Arial, Helvetica, sans-serif;
  font-size: 13px;
  color: #1f2937;
  background: #ffffff;
  text-align: left;
}
.hudu-audit-report h1 {
  color: #0b3a8f;
  border-bottom: 2px solid #dbe7ff;
  padding-bottom: 6px;
  margin-bottom: 10px;
  text-decoration: none;
  font-size: calc(2rem + 16px);
  line-height: 1.25;
  text-align: left;
}
.hudu-audit-report .report-meta {
  font-size: calc(1em + 4px);
  line-height: 1.55;
  text-align: left;
}
.hudu-audit-report h2 {
  margin-top: 26px;
  margin-bottom: 10px;
  color: #0f3c78;
  border-left: 4px solid #1d4ed8;
  padding-left: 8px;
  text-align: left;
}
.hudu-audit-report p { margin: 6px 0 12px 0; text-align: left; }
.hudu-audit-report table { border-collapse: collapse; width: 100%; table-layout: fixed; margin: 0 0 24px 0; font-size: 15px; }
.hudu-audit-report th, .hudu-audit-report td {
  border: 1px solid #d9d9d9;
  padding: 6px 8px;
  text-align: left;
  vertical-align: top;
  line-height: 1.35;
  overflow-wrap: anywhere;
}
.hudu-audit-report th { background: #eef4ff; color: #0f3c78; font-weight: 700; }
.hudu-audit-report tr:nth-child(even) td { background: #fafcff; }
</style>
"@
        return @"
$style
<div class="hudu-audit-report">
<h1>Hudu Central Audit Report</h1>
<div class="report-meta">
<p><strong>Generated:</strong> $generated<br>
<strong>Hudu Domain:</strong> $script:HuduBaseDomain<br>
<strong>API Version:</strong> $($script:ApiInfo.version)<br>
<strong>Report detail level:</strong> Executive (per-company tables omitted to reduce article size and avoid render timeouts)</p>
</div>

<h2>Executive Global Summary</h2>
<p>Global counts for each resource type (Active / Archived / Total where the API exposes archive or discard fields).</p>
$globalTable

<p><em>Run the script with <code>-ReportDetailLevel Compact</code> for company-level totals and asset summaries, or <code>-ReportDetailLevel Full</code> for all tables.</em></p>

<h2>Data Retrieval Errors</h2>
<p>API retrieval failures, pagination issues, and central-article ambiguity notes are listed below.</p>
$errorTable
</div>
"@
    }

    $bdSpecs = @(
        @{ Key = "assets"; Label = "Total Assets"; Mode = "aac" },
        @{ Key = "articles"; Label = "Total KB Articles"; Mode = "aac" },
        @{ Key = "asset_passwords"; Label = "Total Asset Passwords"; Mode = "aac" },
        @{ Key = "expirations"; Label = "Total Expirations"; Mode = "aac" },
        @{ Key = "networks"; Label = "Total Networks"; Mode = "total" },
        @{ Key = "websites"; Label = "Total Websites"; Mode = "total" },
        @{ Key = "ip_addresses"; Label = "Total IP Addresses"; Mode = "total" },
        @{ Key = "rack_storages"; Label = "Total Rack Storages"; Mode = "total" },
        @{ Key = "rack_storage_items"; Label = "Total Rack Storage Items"; Mode = "total" },
        @{ Key = "procedures"; Label = "Total Procedures"; Mode = "aac" },
        @{ Key = "folders"; Label = "Total Folders"; Mode = "total" },
        @{ Key = "password_folders"; Label = "Total Password Folders"; Mode = "total" }
    )

    $companyResourceRows = [System.Collections.Generic.List[object]]::new()
    $companyTotals = [System.Collections.Generic.List[object]]::new()
    $entityCompanyIndexes = @{}
    foreach ($spec in $bdSpecs) {
        $metaForIndex = Get-AuditEntityMeta -Entities $Entities -Key $spec.Key
        $entityCompanyIndexes[$spec.Key] = New-GroupedIndex -Rows @($metaForIndex.Rows) -PropertyName $metaForIndex.CompanyProperty
    }
    foreach ($company in ($Companies | Sort-Object name)) {
        $sumArchived = 0
        $sumTotalAll = 0
        foreach ($spec in $bdSpecs) {
            $meta = Get-AuditEntityMeta -Entities $Entities -Key $spec.Key
            $companyItems = @()
            $companyKey = [string]$company.id
            if ($entityCompanyIndexes[$spec.Key].ContainsKey($companyKey)) {
                $companyItems = @($entityCompanyIndexes[$spec.Key][$companyKey])
            }
            if ($spec.Mode -eq "total") {
                $c = Get-CountObject -Rows $companyItems -HasArchived:$false
                if ($ReportDetailLevel -eq "Full") {
                    [void]$companyResourceRows.Add([PSCustomObject]@{
                        CompanyId = $company.id
                        CompanyName = $company.name
                        Resource = $spec.Label
                        Active = [char]0x2014
                        Archived = [char]0x2014
                        Total = $c.Total
                    })
                }
                $sumTotalAll += $c.Total
            } else {
                $c = Get-CountObject -Rows $companyItems -HasArchived:([bool]$meta.HasArchived)
                if ($ReportDetailLevel -eq "Full") {
                    [void]$companyResourceRows.Add([PSCustomObject]@{
                        CompanyId = $company.id
                        CompanyName = $company.name
                        Resource = $spec.Label
                        Active = $c.Active
                        Archived = $c.Archived
                        Total = $c.Total
                    })
                }
                $sumArchived += $c.Archived
                $sumTotalAll += $c.Total
            }
        }
        if ($ReportDetailLevel -eq "Full") {
            [void]$companyResourceRows.Add([PSCustomObject]@{
                CompanyId = $company.id
                CompanyName = $company.name
                Resource = "Total archived items (summed from active/archived resources above)"
                Active = [char]0x2014
                Archived = $sumArchived
                Total = [char]0x2014
            })
            [void]$companyResourceRows.Add([PSCustomObject]@{
                CompanyId = $company.id
                CompanyName = $company.name
                Resource = "Grand total items (all resources above)"
                Active = [char]0x2014
                Archived = [char]0x2014
                Total = $sumTotalAll
            })
        }
        [void]$companyTotals.Add([PSCustomObject]@{
            CompanyId = $company.id
            CompanyName = $company.name
            ResourceTotal = $sumTotalAll
        })
    }

    $assets = @()
    $am = Get-AuditEntityMeta -Entities $Entities -Key "assets"
    if ($am.Rows) { $assets = @($am.Rows) }

    $assetsByLayout = @()
    foreach ($layout in ($AssetLayouts | Sort-Object name)) {
        $layoutRows = @($assets | Where-Object { $_.asset_layout_id -eq $layout.id })
        $c = Get-CountObject -Rows $layoutRows -HasArchived:$true
        $assetsByLayout += [PSCustomObject]@{
            AssetLayoutId = $layout.id
            AssetLayoutName = $layout.name
            Active = $c.Active
            Archived = $c.Archived
            Total = $c.Total
        }
    }

    $assetsByCompany = [System.Collections.Generic.List[object]]::new()
    $assetsByCompanyIndex = New-GroupedIndex -Rows $assets -PropertyName "company_id"
    foreach ($company in ($Companies | Sort-Object name)) {
        $companyAssets = @()
        $companyKey = [string]$company.id
        if ($assetsByCompanyIndex.ContainsKey($companyKey)) {
            $companyAssets = @($assetsByCompanyIndex[$companyKey])
        }
        $c = Get-CountObject -Rows $companyAssets -HasArchived:$true
        [void]$assetsByCompany.Add([PSCustomObject]@{
            CompanyId = $company.id
            CompanyName = $company.name
            Active = $c.Active
            Archived = $c.Archived
            Total = $c.Total
        })
    }

    $layoutPerCompany = [System.Collections.Generic.List[object]]::new()
    if ($ReportDetailLevel -eq "Full") {
        $assetsByCompanyLayoutIndex = @{}
        foreach ($asset in $assets) {
            $k = "{0}|{1}" -f [string]$asset.company_id, [string]$asset.asset_layout_id
            if (-not $assetsByCompanyLayoutIndex.ContainsKey($k)) {
                $assetsByCompanyLayoutIndex[$k] = [System.Collections.Generic.List[object]]::new()
            }
            [void]$assetsByCompanyLayoutIndex[$k].Add($asset)
        }
        foreach ($company in ($Companies | Sort-Object name)) {
            foreach ($layout in ($AssetLayouts | Sort-Object name)) {
                $k = "{0}|{1}" -f [string]$company.id, [string]$layout.id
                $subset = @()
                if ($assetsByCompanyLayoutIndex.ContainsKey($k)) {
                    $subset = @($assetsByCompanyLayoutIndex[$k])
                }
                if ($subset.Count -eq 0) { continue }
                $c = Get-CountObject -Rows $subset -HasArchived:$true
                [void]$layoutPerCompany.Add([PSCustomObject]@{
                    CompanyId = $company.id
                    CompanyName = $company.name
                    AssetLayoutId = $layout.id
                    AssetLayoutName = $layout.name
                    Active = $c.Active
                    Archived = $c.Archived
                    Total = $c.Total
                })
            }
        }
    }

    $companyTotalsTable = To-HtmlTable -Rows $companyTotals -Columns @(
        [PSCustomObject]@{ Name = "CompanyId"; Label = "Company ID" },
        [PSCustomObject]@{ Name = "CompanyName"; Label = "Company Name" },
        [PSCustomObject]@{ Name = "ResourceTotal"; Label = "Grand total (same as breakdown)" }
    )
    $companyResourceTable = ""
    if ($ReportDetailLevel -eq "Full" -and $companyResourceRows.Count -gt 0) {
        $companyResourceTable = To-HtmlTable -Rows $companyResourceRows -Columns @(
            [PSCustomObject]@{ Name = "CompanyId"; Label = "Company ID" },
            [PSCustomObject]@{ Name = "CompanyName"; Label = "Company Name" },
            [PSCustomObject]@{ Name = "Resource"; Label = "Resource" },
            [PSCustomObject]@{ Name = "Active"; Label = "Active" },
            [PSCustomObject]@{ Name = "Archived"; Label = "Archived" },
            [PSCustomObject]@{ Name = "Total"; Label = "Total" }
        )
    }
    $layoutTable = To-HtmlTable -Rows $assetsByLayout -Columns @(
        [PSCustomObject]@{ Name = "AssetLayoutId"; Label = "Asset Layout ID" },
        [PSCustomObject]@{ Name = "AssetLayoutName"; Label = "Asset Layout Name" },
        [PSCustomObject]@{ Name = "Active"; Label = "Active" },
        [PSCustomObject]@{ Name = "Archived"; Label = "Archived" },
        [PSCustomObject]@{ Name = "Total"; Label = "Total" }
    )
    $assetsCompanyTable = To-HtmlTable -Rows $assetsByCompany -Columns @(
        [PSCustomObject]@{ Name = "CompanyId"; Label = "Company ID" },
        [PSCustomObject]@{ Name = "CompanyName"; Label = "Company Name" },
        [PSCustomObject]@{ Name = "Active"; Label = "Active" },
        [PSCustomObject]@{ Name = "Archived"; Label = "Archived" },
        [PSCustomObject]@{ Name = "Total"; Label = "Total" }
    )
    $layoutCompanyTable = ""
    if ($ReportDetailLevel -eq "Full" -and $layoutPerCompany.Count -gt 0) {
        $layoutCompanyTable = To-HtmlTable -Rows $layoutPerCompany -Columns @(
            [PSCustomObject]@{ Name = "CompanyId"; Label = "Company ID" },
            [PSCustomObject]@{ Name = "CompanyName"; Label = "Company Name" },
            [PSCustomObject]@{ Name = "AssetLayoutId"; Label = "Asset Layout ID" },
            [PSCustomObject]@{ Name = "AssetLayoutName"; Label = "Asset Layout Name" },
            [PSCustomObject]@{ Name = "Active"; Label = "Active" },
            [PSCustomObject]@{ Name = "Archived"; Label = "Archived" },
            [PSCustomObject]@{ Name = "Total"; Label = "Total" }
        )
    }

    $companyCols5 = @(
        [PSCustomObject]@{ Name = "CompanyId"; Label = "Company ID" },
        [PSCustomObject]@{ Name = "CompanyName"; Label = "Company Name" },
        [PSCustomObject]@{ Name = "Active"; Label = "Active" },
        [PSCustomObject]@{ Name = "Archived"; Label = "Archived" },
        [PSCustomObject]@{ Name = "Total"; Label = "Total" }
    )

    $networksCompanyTable = ""
    $ipCompanyTable = ""
    $passwordsCompanyTable = ""
    $proceduresCompanyTable = ""
    $rackStoragesCompanyTable = ""
    $rackItemsCompanyTable = ""
    $vlansCompanyTable = ""
    $vlanZonesCompanyTable = ""
    if ($ReportDetailLevel -eq "Full") {
        $mNet = Get-AuditEntityMeta -Entities $Entities -Key "networks"
        $networksCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mNet.Rows) -CompanyProperty $mNet.CompanyProperty -Mode aac -CompanyIndex (New-GroupedIndex -Rows @($mNet.Rows) -PropertyName $mNet.CompanyProperty)) -Columns $companyCols5

        $mIp = Get-AuditEntityMeta -Entities $Entities -Key "ip_addresses"
        $ipCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mIp.Rows) -CompanyProperty $mIp.CompanyProperty -Mode total -CompanyIndex (New-GroupedIndex -Rows @($mIp.Rows) -PropertyName $mIp.CompanyProperty)) -Columns $companyCols5

        $mPw = Get-AuditEntityMeta -Entities $Entities -Key "asset_passwords"
        $passwordsCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mPw.Rows) -CompanyProperty $mPw.CompanyProperty -Mode aac -CompanyIndex (New-GroupedIndex -Rows @($mPw.Rows) -PropertyName $mPw.CompanyProperty)) -Columns $companyCols5

        $mProc = Get-AuditEntityMeta -Entities $Entities -Key "procedures"
        $proceduresCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mProc.Rows) -CompanyProperty $mProc.CompanyProperty -Mode aac -CompanyIndex (New-GroupedIndex -Rows @($mProc.Rows) -PropertyName $mProc.CompanyProperty)) -Columns $companyCols5

        $mRack = Get-AuditEntityMeta -Entities $Entities -Key "rack_storages"
        $rackStoragesCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mRack.Rows) -CompanyProperty $mRack.CompanyProperty -Mode total -CompanyIndex (New-GroupedIndex -Rows @($mRack.Rows) -PropertyName $mRack.CompanyProperty)) -Columns $companyCols5

        $mRackItem = Get-AuditEntityMeta -Entities $Entities -Key "rack_storage_items"
        $rackItemsCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mRackItem.Rows) -CompanyProperty $mRackItem.CompanyProperty -Mode total -CompanyIndex (New-GroupedIndex -Rows @($mRackItem.Rows) -PropertyName $mRackItem.CompanyProperty)) -Columns $companyCols5

        $mVlan = Get-AuditEntityMeta -Entities $Entities -Key "vlans"
        $vlansCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mVlan.Rows) -CompanyProperty $mVlan.CompanyProperty -Mode aac -CompanyIndex (New-GroupedIndex -Rows @($mVlan.Rows) -PropertyName $mVlan.CompanyProperty)) -Columns $companyCols5

        $mVz = Get-AuditEntityMeta -Entities $Entities -Key "vlan_zones"
        $vlanZonesCompanyTable = To-HtmlTable -Rows (Build-CompanyCountTableRows -Companies $Companies -Rows @($mVz.Rows) -CompanyProperty $mVz.CompanyProperty -Mode aac -CompanyIndex (New-GroupedIndex -Rows @($mVz.Rows) -PropertyName $mVz.CompanyProperty)) -Columns $companyCols5
    }

    $companyResourceBreakdownHtml = ""
    if ($ReportDetailLevel -eq "Full") {
        $companyResourceBreakdownHtml = @"

<h3>Company Resource Breakdown</h3>
<p>Every company includes all listed resource types. Em dash (—) means the column does not apply for that row. Passwords are asset-linked records from <code>/asset_passwords</code>.</p>
$companyResourceTable
"@
    }

    $fullOnlyAfterAssetsHtml = ""
    if ($ReportDetailLevel -eq "Full") {
        $fullOnlyAfterAssetsHtml = @"

<h2>Assets by Layout per Company</h2>
$layoutCompanyTable

<h2>Networks by Company</h2>
<p>Source: <code>GET /networks</code>. Rows grouped by <code>company_id</code>. Active/archived uses <code>archived</code> or <code>discarded_at</code> when present.</p>
$networksCompanyTable

<h2>IP Addresses by Company</h2>
<p>Source: <code>GET /ip_addresses</code> (single response; no <code>page</code> in API). Totals only in Active/Archived columns (—); see <code>Total</code>.</p>
$ipCompanyTable

<h2>Passwords by Company</h2>
<p>Source: <code>GET /asset_passwords</code> (paginated). Asset-linked passwords per <code>company_id</code>.</p>
$passwordsCompanyTable

<h2>Processes (Procedures) by Company</h2>
<p>Source: <code>GET /procedures</code> (paginated). Procedures with a <code>company_id</code> (excludes global templates with no company).</p>
$proceduresCompanyTable

<h2>Rack Storages by Company</h2>
<p>Source: <code>GET /rack_storages</code>. Totals per <code>company_id</code>.</p>
$rackStoragesCompanyTable

<h2>Rack Storage Items by Company</h2>
<p>Source: <code>GET /rack_storage_items</code>. Totals per <code>company_id</code>.</p>
$rackItemsCompanyTable

<h2>VLANs by Company</h2>
<p>Source: <code>GET /vlans</code>. Active/archived per <code>company_id</code> where the API exposes archive fields.</p>
$vlansCompanyTable

<h2>VLAN Zones by Company</h2>
<p>Source: <code>GET /vlan_zones</code>. Active/archived per <code>company_id</code> where the API exposes archive fields.</p>
$vlanZonesCompanyTable
"@
    }

    $compactNoteHtml = ""
    if ($ReportDetailLevel -eq "Compact") {
        $compactNoteHtml = @"

<p><em>Compact report: per-company resource breakdown, assets by layout per company, and network/IP/password/procedure/rack/VLAN tables are omitted to reduce article size. Use <code>-ReportDetailLevel Full</code> for the complete audit.</em></p>
"@
    }

    $style = @"
<style>
.hudu-audit-report {
  font-family: "Segoe UI", Arial, Helvetica, sans-serif;
  font-size: 13px;
  color: #1f2937;
  background: #ffffff;
  text-align: left;
}
.hudu-audit-report h1 {
  color: #0b3a8f;
  border-bottom: 2px solid #dbe7ff;
  padding-bottom: 6px;
  margin-bottom: 10px;
  text-decoration: none;
  font-size: calc(2rem + 16px);
  line-height: 1.25;
  text-align: left;
}
.hudu-audit-report .report-meta {
  font-size: calc(1em + 4px);
  line-height: 1.55;
  text-align: left;
}
.hudu-audit-report h2 {
  margin-top: 26px;
  margin-bottom: 10px;
  color: #0f3c78;
  border-left: 4px solid #1d4ed8;
  padding-left: 8px;
  text-align: left;
}
.hudu-audit-report h3 { margin-top: 18px; margin-bottom: 8px; color: #334155; text-align: left; }
.hudu-audit-report p { margin: 6px 0 12px 0; text-align: left; }
.hudu-audit-report table { border-collapse: collapse; width: 100%; table-layout: fixed; margin: 0 0 24px 0; font-size: 15px; }
.hudu-audit-report th, .hudu-audit-report td {
  border: 1px solid #d9d9d9;
  padding: 6px 8px;
  text-align: left;
  vertical-align: top;
  line-height: 1.35;
  overflow-wrap: anywhere;
}
.hudu-audit-report th { background: #eef4ff; color: #0f3c78; font-weight: 700; }
.hudu-audit-report th strong { font-weight: 700; }
.hudu-audit-report tr:nth-child(even) td { background: #fafcff; }
</style>
"@

    $companyTotalsIntro = if ($ReportDetailLevel -eq "Full") {
        "<p>Grand total per company matches the sum of all rows in the Company Resource Breakdown for that company (including zeros).</p>"
    } else {
        "<p>Grand total per company uses the same resource rollups as the full audit; per-resource rows are omitted in Compact mode.</p>"
    }

    return @"
$style
<div class="hudu-audit-report">
<h1>Hudu Central Audit Report</h1>
<div class="report-meta">
<p><strong>Generated:</strong> $generated<br>
<strong>Hudu Domain:</strong> $script:HuduBaseDomain<br>
<strong>API Version:</strong> $($script:ApiInfo.version)<br>
<strong>Report detail level:</strong> $ReportDetailLevel</p>
</div>

<h2>Executive Global Summary</h2>
<p>Global counts for each resource type (Active / Archived / Total where the API exposes archive or discard fields).</p>
$globalTable
$compactNoteHtml

<h2>Per-Company Master Summary</h2>
<h3>Company totals</h3>
$companyTotalsIntro
$companyTotalsTable
$companyResourceBreakdownHtml

<h2>Assets by Layout (Global)</h2>
$layoutTable

<h2>Assets by Company</h2>
$assetsCompanyTable
$fullOnlyAfterAssetsHtml

<h2>Data Retrieval Errors</h2>
<p>API retrieval failures, pagination issues, and central-article ambiguity notes are listed below.</p>
$errorTable
</div>
"@
}

function Start-HuduCentralAuditReport {
    try {
        Ensure-AzModules

        if (-not (Get-AzContext)) {
            Connect-AzAccount | Out-Null
        }

        Initialize-HuduConnection

        if ($VerifyEndpoints) {
            $failed = Invoke-HuduReportEndpointVerification
            if ($failed -gt 0) {
                throw "Endpoint verification failed for $failed endpoint(s). See warnings above."
            }
            Write-Host "All report endpoints returned successfully."
            return
        }

        Write-Host "Collecting Hudu data..."
        $companies = @()
        $companiesLoaded = $false
        try {
            $companies = @(Get-PaginatedCollection -Endpoint "/companies" -CollectionProperty "companies" -PageSize $PageSize)
            $companiesLoaded = $true
        } catch {
            Add-SectionError -Section "Companies" -Message "$_"
        }

        $assetLayouts = @()
        $assetLayoutsLoaded = $false
        try {
            $assetLayouts = @(Get-PaginatedCollection -Endpoint "/asset_layouts" -CollectionProperty "asset_layouts" -PageSize $PageSize)
            $assetLayoutsLoaded = $true
        } catch {
            Add-SectionError -Section "Asset layouts" -Message "$_"
        }

        $articles = @()
        $articlesLoaded = $false
        try {
            $articles = @(Get-PaginatedCollection -Endpoint "/articles" -CollectionProperty "articles" -PageSize $PageSize)
            $articlesLoaded = $true
        } catch {
            Add-SectionError -Section "Articles (list)" -Message "$_"
        }

        $entities = @{}
        $entities["assets"] = Get-EntityData -Name "Assets" -Endpoint "/assets" -CollectionProperty "assets" -CompanyProperty "company_id" -HasArchived
        $entities["asset_passwords"] = Get-EntityData -Name "AssetPasswords" -Endpoint "/asset_passwords" -CollectionProperty "asset_passwords" -CompanyProperty "company_id" -HasArchived
        $entities["folders"] = Get-EntityData -Name "KbFolders" -Endpoint "/folders" -CollectionProperty "folders" -CompanyProperty "company_id"
        $entities["password_folders"] = Get-EntityData -Name "PasswordFolders" -Endpoint "/password_folders" -CollectionProperty "password_folders" -CompanyProperty "company_id"
        $entities["articles"] = [PSCustomObject]@{
            Name = "KbArticles"
            Rows = $articles
            CompanyProperty = "company_id"
            HasArchived = $true
        }
        $entities["asset_layouts"] = [PSCustomObject]@{ Name = "AssetLayouts"; Rows = $assetLayouts; CompanyProperty = "company_id"; HasArchived = $false }
        $entities["companies"] = [PSCustomObject]@{ Name = "Companies"; Rows = $companies; CompanyProperty = "id"; HasArchived = $true }
        $entities["networks"] = Get-EntityData -Name "Networks" -Endpoint "/networks" -CollectionProperty "" -CompanyProperty "company_id" -HasArchived -DisablePaging
        $entities["ip_addresses"] = Get-EntityData -Name "IpAddresses" -Endpoint "/ip_addresses" -CollectionProperty "" -CompanyProperty "company_id" -DisablePaging
        # GET /websites returns a JSON array (Swagger); use single fetch like /networks — paging can repeat the same page and trip the non-advancing guard.
        $entities["websites"] = Get-EntityData -Name "Websites" -Endpoint "/websites" -CollectionProperty "" -CompanyProperty "company_id" -HasArchived -DisablePaging
        $entities["procedures"] = Get-EntityData -Name "Procedures" -Endpoint "/procedures" -CollectionProperty "procedures" -CompanyProperty "company_id" -HasArchived
        $entities["expirations"] = Get-EntityData -Name "Expirations" -Endpoint "/expirations" -CollectionProperty "" -CompanyProperty "company_id" -HasArchived
        $entities["vlans"] = Get-EntityData -Name "Vlans" -Endpoint "/vlans" -CollectionProperty "" -CompanyProperty "company_id" -HasArchived -DisablePaging
        $entities["vlan_zones"] = Get-EntityData -Name "VlanZones" -Endpoint "/vlan_zones" -CollectionProperty "" -CompanyProperty "company_id" -HasArchived -DisablePaging
        $entities["rack_storages"] = Get-EntityData -Name "RackStorages" -Endpoint "/rack_storages" -CollectionProperty "" -CompanyProperty "company_id" -DisablePaging
        $entities["rack_storage_items"] = Get-EntityData -Name "RackStorageItems" -Endpoint "/rack_storage_items" -CollectionProperty "" -CompanyProperty "company_id" -DisablePaging

        $criticalFailures = [System.Collections.Generic.List[string]]::new()
        if (-not $companiesLoaded) { [void]$criticalFailures.Add("Companies") }
        if (-not $assetLayoutsLoaded) { [void]$criticalFailures.Add("Asset layouts") }
        if (-not $articlesLoaded) { [void]$criticalFailures.Add("Articles (list)") }
        foreach ($criticalKey in @("assets", "asset_passwords", "expirations", "websites", "procedures")) {
            if (-not $entities[$criticalKey].Success) {
                [void]$criticalFailures.Add($criticalKey)
            }
        }
        if ($criticalFailures.Count -gt 0) {
            throw "Critical data retrieval failed; refusing to publish partial report. Failed sections: $($criticalFailures -join ', ')"
        }

        $articleName = Resolve-CentralArticleName -ExistingArticles $articles
        $targetPlan = Resolve-CentralReportArticleTarget -Articles $articles -ArticleTitle $articleName

        $payload = Get-EffectiveReportPayload -Companies $companies -Entities $entities -AssetLayouts $assetLayouts -PreferredLevel $ReportDetailLevel
        $html = $payload.Html
        $effectiveLevel = $payload.Level

        if ($DryRun) {
            Write-Host "Dry run complete. Article title: '$articleName'"
            Write-Host "Effective report detail level: $effectiveLevel"
            if ($targetPlan.Action -eq "Update") {
                Write-Host "Would update existing article ID $($targetPlan.Target.id)."
            } else {
                Write-Host "Would create a new central article."
            }
        } else {
            $levels = @("Full", "Compact", "Executive")
            $startLevelIndex = [Array]::IndexOf($levels, $effectiveLevel)
            if ($startLevelIndex -lt 0) { $startLevelIndex = 0 }
            $published = $false
            $lastPublishError = $null

            if ($targetPlan.Action -eq "Update") {
                for ($li = $startLevelIndex; $li -lt $levels.Count; $li++) {
                    $level = $levels[$li]
                    if ($li -eq $startLevelIndex) {
                        $publishHtml = $html
                    } else {
                        Add-SectionError -Section "Publish fallback" -Message "Retrying update using $level detail due to previous publish failure."
                        $publishHtml = (Build-ReportHtml -Companies $companies -Entities $entities -AssetLayouts $assetLayouts -ReportDetailLevel $level)
                    }
                    $body = @{
                        article = @{
                            name = $articleName
                            content = $publishHtml
                        }
                    }
                    try {
                        Invoke-HuduApi -Method "PUT" -Endpoint "/articles/$($targetPlan.Target.id)" -Body $body | Out-Null
                        Write-Host "Updated central KB article: '$articleName' (ID: $($targetPlan.Target.id), level: $level)"
                        $published = $true
                        break
                    } catch {
                        $lastPublishError = $_
                        $statusCode = $null
                        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                            $statusCode = [int]$_.Exception.Response.StatusCode
                        }
                        if ($statusCode -ne 500 -or $li -eq ($levels.Count - 1)) {
                            throw
                        }
                    }
                }
            } else {
                for ($li = $startLevelIndex; $li -lt $levels.Count; $li++) {
                    $level = $levels[$li]
                    if ($li -eq $startLevelIndex) {
                        $publishHtml = $html
                    } else {
                        Add-SectionError -Section "Publish fallback" -Message "Retrying create using $level detail due to previous publish failure."
                        $publishHtml = (Build-ReportHtml -Companies $companies -Entities $entities -AssetLayouts $assetLayouts -ReportDetailLevel $level)
                    }
                    $articleBody = @{
                        article = @{
                            name = $articleName
                            content = $publishHtml
                            enable_sharing = $false
                        }
                    }
                    try {
                        $created = Invoke-HuduApi -Method "POST" -Endpoint "/articles" -Body $articleBody
                        if ($created.article) {
                            Write-Host "Created central KB article: '$articleName' (ID: $($created.article.id), level: $level)"
                        } else {
                            Write-Host "Created central KB article: '$articleName' (level: $level)"
                        }
                        $published = $true
                        break
                    } catch {
                        $lastPublishError = $_
                        $statusCode = $null
                        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                            $statusCode = [int]$_.Exception.Response.StatusCode
                        }
                        if ($statusCode -ne 500 -or $li -eq ($levels.Count - 1)) {
                            throw
                        }
                    }
                }
            }
            if (-not $published -and $lastPublishError) { throw $lastPublishError }
        }
    }
    catch {
        Write-Error "Script failed: $_"
        throw
    }
    finally {
        # Silent credential cleanup
        Clear-SensitiveData
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-HuduCentralAuditReport
}

