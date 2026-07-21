<# 
.SYNOPSIS
Creates Hudu Magic Dash tiles from ConnectWise Manage service tickets.

.DESCRIPTION
This is a self-contained community script. It uses direct REST calls for Hudu and
ConnectWise Manage so partners can run it without installing PowerShell modules.

V1 supports ConnectWise Manage tickets. The internal function names intentionally
leave room for future PSA providers to use the same renderer and Hudu client.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$HuduBaseUrl = $env:HUDU_BASE_URL,
    [string]$HuduApiKey = $env:HUDU_API_KEY,

    [ValidateSet('ConnectWise')]
    [string]$Provider = 'ConnectWise',

    [string]$ConnectWiseServer = $env:CW_SERVER,
    [string]$ConnectWiseCompanyId = $env:CW_COMPANY_ID,
    [string]$ConnectWisePublicKey = $env:CW_PUBLIC_KEY,
    [string]$ConnectWisePrivateKey = $env:CW_PRIVATE_KEY,
    [string]$ConnectWiseClientId = $env:CW_CLIENT_ID,
    [string]$ConnectWiseTicketUrlTemplate = $env:CW_TICKET_URL_TEMPLATE,

    [string]$TicketConditions = $env:CW_TICKET_CONDITIONS,
    [string[]]$BoardNames = @(),
    [string[]]$TicketFields = @(),
    [string[]]$TicketColumnWidths = @(),
    [string]$CompanyName,
    [string]$CompanyDetailsLayoutName = 'Company Details',

    [int]$ConnectWisePageSize = 1000,
    [int]$HuduPageSize = 100,
    [int]$MaxTicketsPerCompany = 25,
    [int]$WarningOverdueThreshold = 1,
    [int]$DangerOverdueThreshold = 2,

    [switch]$UseHuduAssetConfig,
    [switch]$InteractiveSetup,
    [switch]$DryRun,
    [switch]$TestConnectionOnly,
    [switch]$EnableWriteBack
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:DryRunMode = [bool]$DryRun
$script:RunSummary = [ordered]@{
    StartedAt        = Get-Date
    Provider         = $Provider
    HuduCompanies    = 0
    ProviderCompanies = 0
    MatchedCompanies = 0
    SkippedCompanies = 0
    TilesUpdated     = 0
    DryRunTiles      = 0
    TicketsFound     = 0
    ConfigurationLinks = 0
    Errors           = [System.Collections.Generic.List[string]]::new()
    Warnings         = [System.Collections.Generic.List[string]]::new()
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('s')
    $line = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Warning' {
            $script:RunSummary.Warnings.Add($Message) | Out-Null
            Write-Warning $Message
        }
        'Error' {
            $script:RunSummary.Errors.Add($Message) | Out-Null
            Write-Error $Message
        }
        'Success' { Write-Host $line -ForegroundColor Green }
        'Debug' { Write-Verbose $line }
        default { Write-Host $line }
    }
}

function Get-ObjectProperty {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        $property = $InputObject.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($property) {
            return $property.Value
        }

        return $null
    }
}

function Get-FirstPropertyValue {
    param(
        [object]$InputObject,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $value = Get-ObjectProperty -InputObject $InputObject -Name $name
        if ($null -ne $value -and "$value" -ne '') {
            return $value
        }
    }

    return $null
}

function ConvertTo-BooleanValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [bool]) {
        return $Value
    }

    switch -Regex ("$Value".Trim()) {
        '^(true|yes|y|1|enabled|checked)$' { return $true }
        '^(false|no|n|0|disabled|unchecked)$' { return $false }
        default { return $null }
    }
}

function ConvertTo-NormalizedName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    return ($Name.ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Resolve-TicketFields {
    param([string[]]$Fields)

    $defaultFields = @('Ticket', 'Summary', 'Status', 'Priority', 'Owner', 'Due', 'Configurations')
    $allowedFields = @('Ticket', 'Summary', 'Board', 'Status', 'Priority', 'Owner', 'Age', 'Due', 'Configurations')

    if (($null -eq $Fields -or @($Fields).Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($env:CW_TICKET_FIELDS)) {
        $Fields = @($env:CW_TICKET_FIELDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    if ($null -eq $Fields -or @($Fields).Count -eq 0) {
        $Fields = $defaultFields
    }

    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($field in $Fields) {
        $match = $allowedFields | Where-Object { $_ -eq $field } | Select-Object -First 1
        if (-not $match) {
            throw "Unsupported ticket field '$field'. Allowed fields: $($allowedFields -join ', ')."
        }
        if (-not $resolved.Contains($match)) {
            $resolved.Add($match) | Out-Null
        }
    }

    if (-not $resolved.Contains('Ticket')) {
        $resolved.Insert(0, 'Ticket')
    }
    if (-not $resolved.Contains('Summary')) {
        $resolved.Insert([math]::Min(1, $resolved.Count), 'Summary')
    }

    return @($resolved)
}

function Test-TicketFieldEnabled {
    param(
        [object]$Config,
        [string]$Field
    )

    return @($Config.TicketFields) -contains $Field
}

function Resolve-TicketColumnWidths {
    param([string[]]$Widths)

    $defaults = [ordered]@{
        Ticket         = '74px'
        Summary        = 'auto'
        Board          = '110px'
        Status         = '95px'
        Priority       = '125px'
        Owner          = '130px'
        Age            = '55px'
        Due            = '90px'
        Configurations = '160px'
    }

    if (($null -eq $Widths -or @($Widths).Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($env:CW_TICKET_COLUMN_WIDTHS)) {
        $Widths = @($env:CW_TICKET_COLUMN_WIDTHS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $resolved = [ordered]@{}
    foreach ($key in $defaults.Keys) {
        $resolved[$key] = $defaults[$key]
    }

    $widthEntries = @($Widths | ForEach-Object {
        $_ -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    })

    foreach ($entry in $widthEntries) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $parts = $entry -split '=', 2
        if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "Invalid column width '$entry'. Use Field=Width, for example Summary=360px."
        }

        $field = ($defaults.Keys | Where-Object { $_ -eq $parts[0].Trim() } | Select-Object -First 1)
        if (-not $field) {
            throw "Unsupported column width field '$($parts[0])'. Allowed fields: $($defaults.Keys -join ', ')."
        }

        $width = $parts[1].Trim()
        if ($width -notmatch '^(auto|[0-9]+(\.[0-9]+)?(px|%|rem|em|ch))$') {
            throw "Unsupported width '$width' for '$field'. Use auto, px, %, rem, em, or ch."
        }

        $resolved[$field] = $width
    }

    return [PSCustomObject]$resolved
}

function ConvertTo-HtmlText {
    param([object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode("$Value")
}

function Join-UrlPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return ('{0}/{1}' -f $BaseUrl.TrimEnd('/'), $Path.TrimStart('/'))
}

function ConvertTo-QueryString {
    param([hashtable]$Query)

    if ($null -eq $Query -or $Query.Count -eq 0) {
        return ''
    }

    $pairs = foreach ($key in $Query.Keys) {
        $value = $Query[$key]
        if ($null -eq $value -or "$value" -eq '') {
            continue
        }

        '{0}={1}' -f [System.Uri]::EscapeDataString("$key"), [System.Uri]::EscapeDataString("$value")
    }

    if (@($pairs).Count -eq 0) {
        return ''
    }

    return '?' + ($pairs -join '&')
}

function Get-CollectionFromResponse {
    param(
        [object]$Response,
        [string[]]$PropertyNames
    )

    if ($null -eq $Response) {
        return @()
    }

    if ($Response -is [array]) {
        return @($Response)
    }

    foreach ($propertyName in $PropertyNames) {
        $value = Get-ObjectProperty -InputObject $Response -Name $propertyName
        if ($null -ne $value) {
            return @($value)
        }
    }

    return @($Response)
}

function ConvertFrom-SecureStringToPlainText {
    param([securestring]$SecureString)

    if ($null -eq $SecureString) {
        return $null
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Read-ConfigValue {
    param(
        [string]$CurrentValue,
        [string]$Prompt,
        [switch]$Secret
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue
    }

    if (-not $InteractiveSetup) {
        return $CurrentValue
    }

    if ($Secret) {
        return ConvertFrom-SecureStringToPlainText -SecureString (Read-Host -Prompt $Prompt -AsSecureString)
    }

    return Read-Host -Prompt $Prompt
}

function Resolve-RuntimeConfig {
    $config = [ordered]@{
        HuduBaseUrl                  = (Read-ConfigValue -CurrentValue $HuduBaseUrl -Prompt 'Hudu base URL, for example https://yourcompany.huducloud.com')
        HuduApiKey                   = (Read-ConfigValue -CurrentValue $HuduApiKey -Prompt 'Hudu API key' -Secret)
        Provider                     = $Provider
        ConnectWiseServer            = (Read-ConfigValue -CurrentValue $ConnectWiseServer -Prompt 'ConnectWise API server, for example api-na.myconnectwise.net')
        ConnectWiseCompanyId         = (Read-ConfigValue -CurrentValue $ConnectWiseCompanyId -Prompt 'ConnectWise company ID used at login')
        ConnectWisePublicKey         = (Read-ConfigValue -CurrentValue $ConnectWisePublicKey -Prompt 'ConnectWise public API key')
        ConnectWisePrivateKey        = (Read-ConfigValue -CurrentValue $ConnectWisePrivateKey -Prompt 'ConnectWise private API key' -Secret)
        ConnectWiseClientId          = (Read-ConfigValue -CurrentValue $ConnectWiseClientId -Prompt 'ConnectWise developer clientId')
        ConnectWiseTicketUrlTemplate = $ConnectWiseTicketUrlTemplate
        TicketConditions             = $TicketConditions
        BoardNames                   = @($BoardNames)
        TicketFields                 = Resolve-TicketFields -Fields $TicketFields
        TicketColumnWidths           = Resolve-TicketColumnWidths -Widths $TicketColumnWidths
    }

    if (@($config.BoardNames).Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($env:CW_BOARD_NAMES)) {
        $config.BoardNames = @($env:CW_BOARD_NAMES -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    if ([string]::IsNullOrWhiteSpace($config.TicketConditions)) {
        $config.TicketConditions = 'closedFlag = False'
    }

    foreach ($requiredName in @('HuduBaseUrl', 'HuduApiKey', 'ConnectWiseServer', 'ConnectWiseCompanyId', 'ConnectWisePublicKey', 'ConnectWisePrivateKey', 'ConnectWiseClientId')) {
        if ([string]::IsNullOrWhiteSpace($config[$requiredName])) {
            throw "Missing required setting '$requiredName'. Supply it as a parameter, environment variable, or run with -InteractiveSetup."
        }
    }

    $config.HuduBaseUrl = $config.HuduBaseUrl.TrimEnd('/')
    $config.ConnectWiseServer = $config.ConnectWiseServer.TrimEnd('/')

    return [PSCustomObject]$config
}

function Invoke-HuduApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$Query,
        [object]$Body,
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $uri = Join-UrlPath -BaseUrl $Config.HuduBaseUrl -Path $Path
    $uri = $uri + (ConvertTo-QueryString -Query $Query)
    $headers = @{
        'x-api-key' = $Config.HuduApiKey
        'Accept'    = 'application/json'
    }

    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $invokeParams.ContentType = 'application/json'
        $invokeParams.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }

    return Invoke-RestMethod @invokeParams
}

function Get-HuduPagedCollection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$CollectionPropertyNames,
        [hashtable]$BaseQuery = @{},

        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $page = 1

    while ($true) {
        $query = @{}
        foreach ($key in $BaseQuery.Keys) {
            $query[$key] = $BaseQuery[$key]
        }
        $query.page = $page
        $query.page_size = $HuduPageSize

        $response = Invoke-HuduApi -Method 'GET' -Path $Path -Query $query -Config $Config
        $pageItems = @(Get-CollectionFromResponse -Response $response -PropertyNames $CollectionPropertyNames)
        foreach ($item in $pageItems) {
            $items.Add($item) | Out-Null
        }

        if ($pageItems.Count -lt $HuduPageSize) {
            break
        }

        $page++
    }

    return @($items)
}

function Test-HuduConnection {
    param([object]$Config)

    Write-Log -Message 'Testing Hudu API connection.'
    $null = Invoke-HuduApi -Method 'GET' -Path '/api/v1/companies' -Query @{ page = 1; page_size = 1 } -Config $Config
    Write-Log -Message 'Hudu API connection succeeded.' -Level Success
}

function Get-HuduCompaniesForDash {
    param([object]$Config)

    $companies = @(Get-HuduPagedCollection -Path '/api/v1/companies' -CollectionPropertyNames @('companies') -Config $Config)

    if (-not [string]::IsNullOrWhiteSpace($CompanyName)) {
        $companies = @($companies | Where-Object {
            $name = Get-FirstPropertyValue -InputObject $_ -Names @('name', 'company_name')
            $name -eq $CompanyName
        })
    }

    $script:RunSummary.HuduCompanies = $companies.Count
    return $companies
}

function Get-HuduAssetLayouts {
    param([object]$Config)

    return @(Get-HuduPagedCollection -Path '/api/v1/asset_layouts' -CollectionPropertyNames @('asset_layouts', 'layouts') -Config $Config)
}

function Get-HuduAssetsByLayoutId {
    param(
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [object]$LayoutId
    )

    return @(Get-HuduPagedCollection -Path '/api/v1/assets' -CollectionPropertyNames @('assets') -BaseQuery @{ asset_layout_id = $LayoutId } -Config $Config)
}

function Get-HuduCompanyDetailsConfig {
    param([object]$Config)

    $configByCompanyId = @{}
    $configByCompanyName = @{}

    if (-not $UseHuduAssetConfig) {
        return [PSCustomObject]@{
            ByCompanyId   = $configByCompanyId
            ByCompanyName = $configByCompanyName
        }
    }

    Write-Log -Message "Loading optional Hudu asset configuration from '$CompanyDetailsLayoutName' assets."
    $layouts = @(Get-HuduAssetLayouts -Config $Config | Where-Object {
        (Get-FirstPropertyValue -InputObject $_ -Names @('name')) -eq $CompanyDetailsLayoutName
    })

    if ($layouts.Count -ne 1) {
        Write-Log -Level Warning -Message "Expected exactly one '$CompanyDetailsLayoutName' asset layout but found $($layouts.Count). Continuing without asset field configuration."
        return [PSCustomObject]@{
            ByCompanyId   = $configByCompanyId
            ByCompanyName = $configByCompanyName
        }
    }

    $layoutId = Get-FirstPropertyValue -InputObject $layouts[0] -Names @('id')
    $assets = @(Get-HuduAssetsByLayoutId -Config $Config -LayoutId $layoutId)

    foreach ($asset in $assets) {
        $companyId = Get-FirstPropertyValue -InputObject $asset -Names @('company_id', 'companyId')
        $companyName = Get-FirstPropertyValue -InputObject $asset -Names @('company_name', 'companyName')
        $fields = @(Get-ObjectProperty -InputObject $asset -Name 'fields')

        $serviceConfig = [ordered]@{}
        foreach ($field in $fields) {
            $label = Get-FirstPropertyValue -InputObject $field -Names @('label', 'name')
            if ([string]::IsNullOrWhiteSpace($label) -or $label -notlike 'CW Manage:*') {
                continue
            }

            $fieldName = ($label -replace '^CW Manage:', '').Trim()
            $value = Get-FirstPropertyValue -InputObject $field -Names @('value', 'field_value')
            $serviceConfig[$fieldName] = $value
        }

        if ($serviceConfig.Count -eq 0) {
            continue
        }

        $configObject = [PSCustomObject]@{
            CompanyId   = $companyId
            CompanyName = $companyName
            Fields      = [PSCustomObject]$serviceConfig
        }

        if ($companyId) {
            $configByCompanyId["$companyId"] = $configObject
        }
        if ($companyName) {
            $configByCompanyName[(ConvertTo-NormalizedName -Name $companyName)] = $configObject
        }
    }

    Write-Log -Message "Loaded optional asset configuration for $($configByCompanyId.Count + $configByCompanyName.Count) company lookup keys."
    return [PSCustomObject]@{
        ByCompanyId   = $configByCompanyId
        ByCompanyName = $configByCompanyName
    }
}

function Get-HuduAssetUrl {
    param(
        [object]$Config,
        [object]$Asset
    )

    $slug = Get-FirstPropertyValue -InputObject $Asset -Names @('slug')
    if ($slug) {
        return '{0}/a/{1}' -f $Config.HuduBaseUrl.TrimEnd('/'), $slug
    }

    $id = Get-FirstPropertyValue -InputObject $Asset -Names @('id')
    if ($id) {
        return '{0}/assets/{1}' -f $Config.HuduBaseUrl.TrimEnd('/'), $id
    }

    return ''
}

function Get-HuduConfigurationAssetLookup {
    param(
        [object]$Config,
        [object]$HuduCompanyId
    )

    $lookup = [PSCustomObject]@{
        ByConnectWiseId = @{}
        ByName          = @{}
    }

    if (-not (Test-TicketFieldEnabled -Config $Config -Field 'Configurations') -or -not $HuduCompanyId) {
        return $lookup
    }

    $assets = @(Get-HuduPagedCollection -Path '/api/v1/assets' -CollectionPropertyNames @('assets') -BaseQuery @{ company_id = $HuduCompanyId } -Config $Config)

    foreach ($asset in $assets) {
        $assetName = Get-FirstPropertyValue -InputObject $asset -Names @('name')
        $assetUrl = Get-HuduAssetUrl -Config $Config -Asset $asset
        if ($assetName) {
            $lookup.ByName[(ConvertTo-NormalizedName -Name $assetName)] = [PSCustomObject]@{
                Name = $assetName
                Url  = $assetUrl
            }
        }

        $integrations = @(Get-ObjectProperty -InputObject $asset -Name 'integrations')
        foreach ($integration in $integrations) {
            $name = Get-FirstPropertyValue -InputObject $integration -Names @('integrator_name', 'name', 'slug')
            if ($name -and $name -notmatch '(?i)(connectwise|cw manage|cw psa)') {
                continue
            }

            $syncId = Get-FirstPropertyValue -InputObject $integration -Names @('sync_id', 'syncId', 'external_id', 'externalId', 'id')
            if ($syncId) {
                $lookup.ByConnectWiseId["$syncId"] = [PSCustomObject]@{
                    Name = $assetName
                    Url  = $assetUrl
                }
            }
        }

        foreach ($field in @(Get-ObjectProperty -InputObject $asset -Name 'fields')) {
            $label = Get-FirstPropertyValue -InputObject $field -Names @('label', 'name')
            if ([string]::IsNullOrWhiteSpace($label) -or $label -notmatch '(?i)(connectwise|cw|configuration).*(id|sync)') {
                continue
            }

            $value = Get-FirstPropertyValue -InputObject $field -Names @('value', 'field_value')
            if ($value) {
                $lookup.ByConnectWiseId["$value"] = [PSCustomObject]@{
                    Name = $assetName
                    Url  = $assetUrl
                }
            }
        }
    }

    return $lookup
}

function Set-HuduMagicDashTile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [string]$CompanyName,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Icon = '',
        [string]$Content = '',
        [string]$ContentLink = '',
        [string]$Shade = 'success'
    )

    $body = [ordered]@{
        title        = $Title
        company_name = $CompanyName
        message      = $Message
        shade        = $Shade
    }

    if (-not [string]::IsNullOrWhiteSpace($Icon)) {
        $body.icon = $Icon
    }

    if (-not [string]::IsNullOrWhiteSpace($Content)) {
        $body.content = $Content
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ContentLink)) {
        $body.content_link = $ContentLink
    }

    if ($script:DryRunMode -or $WhatIfPreference) {
        $script:RunSummary.DryRunTiles++
        Write-Log -Message "Dry run: would update Magic Dash '$Title' for '$CompanyName' with message '$Message'."
        return [PSCustomObject]@{
            dry_run = $true
            body    = $body
        }
    }

    if ($PSCmdlet.ShouldProcess("$CompanyName / $Title", 'Update Hudu Magic Dash')) {
        $response = Invoke-HuduApi -Method 'POST' -Path '/api/v1/magic_dash' -Body $body -Config $Config
        $script:RunSummary.TilesUpdated++
        return $response
    }
}

function Get-ConnectWiseBaseUrl {
    param([string]$Server)

    $base = $Server.TrimEnd('/')
    if ($base -notmatch '^https?://') {
        $base = "https://$base"
    }

    if ($base -notmatch '/v4_6_release/apis/3\.0$') {
        $base = "$base/v4_6_release/apis/3.0"
    }

    return $base
}

function Get-ConnectWiseHeaders {
    param([object]$Config)

    $authString = '{0}+{1}:{2}' -f $Config.ConnectWiseCompanyId, $Config.ConnectWisePublicKey, $Config.ConnectWisePrivateKey
    $encodedAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authString))

    return @{
        Authorization      = "Basic $encodedAuth"
        clientId           = $Config.ConnectWiseClientId
        'Cache-Control'    = 'no-cache'
        ConnectionMethod   = 'Key'
        Accept             = 'application/vnd.connectwise.com+json; version=2023.1'
        'Content-Type'     = 'application/json'
    }
}

function Invoke-ConnectWiseApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$Query,
        [object]$Body,

        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $baseUrl = Get-ConnectWiseBaseUrl -Server $Config.ConnectWiseServer
    $uri = Join-UrlPath -BaseUrl $baseUrl -Path $Path
    $uri = $uri + (ConvertTo-QueryString -Query $Query)

    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = (Get-ConnectWiseHeaders -Config $Config)
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $invokeParams.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
        $invokeParams.ContentType = 'application/json'
    }

    return Invoke-RestMethod @invokeParams
}

function Get-ConnectWisePagedCollection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$BaseQuery = @{},

        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $page = 1

    while ($true) {
        $query = @{}
        foreach ($key in $BaseQuery.Keys) {
            $query[$key] = $BaseQuery[$key]
        }
        $query.page = $page
        $query.pageSize = $ConnectWisePageSize

        $response = Invoke-ConnectWiseApi -Method 'GET' -Path $Path -Query $query -Config $Config
        $pageItems = @(Get-CollectionFromResponse -Response $response -PropertyNames @())
        foreach ($item in $pageItems) {
            $items.Add($item) | Out-Null
        }

        if ($pageItems.Count -lt $ConnectWisePageSize) {
            break
        }

        $page++
    }

    return @($items)
}

function Test-ConnectWiseConnection {
    param([object]$Config)

    Write-Log -Message 'Testing ConnectWise API connection.'
    $null = Invoke-ConnectWiseApi -Method 'GET' -Path '/system/info' -Config $Config
    Write-Log -Message 'ConnectWise API connection succeeded.' -Level Success
}

function Get-ProviderConnection {
    param([object]$Config)

    switch ($Config.Provider) {
        'ConnectWise' {
            return [PSCustomObject]@{
                Provider = 'ConnectWise'
                BaseUrl  = (Get-ConnectWiseBaseUrl -Server $Config.ConnectWiseServer)
            }
        }
        default {
            throw "Provider '$($Config.Provider)' is not implemented."
        }
    }
}

function Test-ProviderConnection {
    param([object]$Config)

    switch ($Config.Provider) {
        'ConnectWise' { Test-ConnectWiseConnection -Config $Config }
        default { throw "Provider '$($Config.Provider)' is not implemented." }
    }
}

function Get-ProviderCompanies {
    param([object]$Config)

    switch ($Config.Provider) {
        'ConnectWise' {
            $companies = @(Get-ConnectWisePagedCollection -Path '/company/companies' -Config $Config)
            $script:RunSummary.ProviderCompanies = $companies.Count
            return $companies
        }
        default {
            throw "Provider '$($Config.Provider)' is not implemented."
        }
    }
}

function Join-ConnectWiseConditions {
    param([string[]]$Conditions)

    $cleanConditions = @($Conditions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($cleanConditions.Count -eq 0) {
        return ''
    }

    if ($cleanConditions.Count -eq 1) {
        return $cleanConditions[0]
    }

    return (($cleanConditions | ForEach-Object { "($_)" }) -join ' AND ')
}

function New-BoardCondition {
    param([string[]]$Names)

    $cleanNames = @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($cleanNames.Count -eq 0) {
        return ''
    }

    $boardConditions = foreach ($name in $cleanNames) {
        'board/name="{0}"' -f ($name.Replace('"', '\"'))
    }

    if (@($boardConditions).Count -eq 1) {
        return $boardConditions[0]
    }

    return '(' + ($boardConditions -join ' OR ') + ')'
}

function Get-ConfigFieldValue {
    param(
        [object]$AssetConfig,
        [string]$FieldName
    )

    if ($null -eq $AssetConfig) {
        return $null
    }

    $fields = Get-ObjectProperty -InputObject $AssetConfig -Name 'Fields'
    if ($null -eq $fields) {
        return $null
    }

    return Get-ObjectProperty -InputObject $fields -Name $FieldName
}

function Get-BoardNamesForCompany {
    param(
        [object]$GlobalConfig,
        [object]$AssetConfig
    )

    $assetBoardNames = Get-ConfigFieldValue -AssetConfig $AssetConfig -FieldName 'BoardNames'
    if (-not [string]::IsNullOrWhiteSpace($assetBoardNames)) {
        return @($assetBoardNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    return @($GlobalConfig.BoardNames)
}

function Get-TicketConditionsForCompany {
    param(
        [object]$GlobalConfig,
        [object]$AssetConfig,
        [object]$ProviderCompanyId
    )

    $conditions = [System.Collections.Generic.List[string]]::new()
    $assetConditions = Get-ConfigFieldValue -AssetConfig $AssetConfig -FieldName 'TicketConditions'

    if (-not [string]::IsNullOrWhiteSpace($assetConditions)) {
        $conditions.Add($assetConditions) | Out-Null
    }
    elseif (-not [string]::IsNullOrWhiteSpace($GlobalConfig.TicketConditions)) {
        $conditions.Add($GlobalConfig.TicketConditions) | Out-Null
    }

    $boards = Get-BoardNamesForCompany -GlobalConfig $GlobalConfig -AssetConfig $AssetConfig
    $boardCondition = New-BoardCondition -Names $boards
    if (-not [string]::IsNullOrWhiteSpace($boardCondition)) {
        $conditions.Add($boardCondition) | Out-Null
    }

    if ($ProviderCompanyId) {
        $conditions.Add(('company/id = {0}' -f $ProviderCompanyId)) | Out-Null
    }

    return Join-ConnectWiseConditions -Conditions @($conditions)
}

function Get-ConnectWiseTicketUrl {
    param(
        [object]$Config,
        [object]$Ticket
    )

    $id = Get-FirstPropertyValue -InputObject $Ticket -Names @('id')
    $number = Get-FirstPropertyValue -InputObject $Ticket -Names @('ticketNumber', 'id')

    if (-not [string]::IsNullOrWhiteSpace($Config.ConnectWiseTicketUrlTemplate)) {
        return $Config.ConnectWiseTicketUrlTemplate.Replace('{id}', "$id").Replace('{number}', "$number")
    }

    if ($id) {
        $server = $Config.ConnectWiseServer.TrimEnd('/')
        if ($server -notmatch '^https?://') {
            $server = "https://$server"
        }
        $server = $server -replace '/v4_6_release/apis/3\.0$', ''
        return '{0}/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid={1}' -f $server, $id
    }

    return ''
}

function Get-ConnectWiseTicketConfigurations {
    param(
        [object]$Config,
        [object]$TicketId
    )

    if (-not $TicketId) {
        return @()
    }

    try {
        return @(Get-ConnectWisePagedCollection -Path "/service/tickets/$TicketId/configurations" -Config $Config)
    }
    catch {
        Write-Log -Level Warning -Message "Could not load configurations for ConnectWise ticket '$TicketId': $($_.Exception.Message)"
        return @()
    }
}

function ConvertTo-NormalizedTicketConfiguration {
    param(
        [object]$Configuration,
        [object]$HuduConfigurationLookup
    )

    $configId = Get-FirstPropertyValue -InputObject $Configuration -Names @('id', 'configId', 'configurationId')
    $info = Get-ObjectProperty -InputObject $Configuration -Name '_info'
    $configName = Get-FirstPropertyValue -InputObject $Configuration -Names @('name', 'identifier', 'deviceIdentifier')
    if ($null -eq $configName) {
        $configName = Get-FirstPropertyValue -InputObject $info -Names @('name')
    }
    $huduAsset = $null

    if ($configId -and $HuduConfigurationLookup.ByConnectWiseId.ContainsKey("$configId")) {
        $huduAsset = $HuduConfigurationLookup.ByConnectWiseId["$configId"]
    }
    elseif ($configName -and $HuduConfigurationLookup.ByName.ContainsKey((ConvertTo-NormalizedName -Name $configName))) {
        $huduAsset = $HuduConfigurationLookup.ByName[(ConvertTo-NormalizedName -Name $configName)]
    }

    $url = ''
    if ($huduAsset) {
        $url = Get-FirstPropertyValue -InputObject $huduAsset -Names @('Url')
        $script:RunSummary.ConfigurationLinks++
    }

    return [PSCustomObject]@{
        Id        = $configId
        Name      = $configName
        HuduUrl   = $url
        HuduAsset = $huduAsset
        Raw       = $Configuration
    }
}

function ConvertTo-NormalizedTicket {
    param(
        [object]$Ticket,
        [object]$Config
    )

    $company = Get-ObjectProperty -InputObject $Ticket -Name 'company'
    $board = Get-ObjectProperty -InputObject $Ticket -Name 'board'
    $status = Get-ObjectProperty -InputObject $Ticket -Name 'status'
    $priority = Get-ObjectProperty -InputObject $Ticket -Name 'priority'
    $owner = Get-ObjectProperty -InputObject $Ticket -Name 'owner'

    $requiredDateRaw = Get-FirstPropertyValue -InputObject $Ticket -Names @('requiredDate', 'dateResplan')
    $requiredDate = $null
    if ($requiredDateRaw) {
        $parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse("$requiredDateRaw", [ref]$parsedDate)) {
            $requiredDate = $parsedDate
        }
    }

    $enteredDateRaw = Get-FirstPropertyValue -InputObject $Ticket -Names @('dateEntered')
    $enteredDate = $null
    if ($enteredDateRaw) {
        $parsedEntered = [datetime]::MinValue
        if ([datetime]::TryParse("$enteredDateRaw", [ref]$parsedEntered)) {
            $enteredDate = $parsedEntered
        }
    }

    $closedFlag = ConvertTo-BooleanValue -Value (Get-FirstPropertyValue -InputObject $Ticket -Names @('closedFlag'))
    $isInSla = ConvertTo-BooleanValue -Value (Get-FirstPropertyValue -InputObject $Ticket -Names @('isInSla'))
    $isOverdue = $false

    if ($null -ne $requiredDate -and $requiredDate -lt (Get-Date) -and $closedFlag -ne $true) {
        $isOverdue = $true
    }

    if ($null -ne $isInSla -and $isInSla -eq $false -and $closedFlag -ne $true) {
        $isOverdue = $true
    }

    $info = Get-ObjectProperty -InputObject $Ticket -Name '_info'
    $lastUpdated = Get-FirstPropertyValue -InputObject $Ticket -Names @('lastUpdated')
    if ($null -eq $lastUpdated) {
        $lastUpdated = Get-FirstPropertyValue -InputObject $info -Names @('lastUpdated')
    }

    return [PSCustomObject]@{
        Provider       = 'ConnectWise'
        Id             = Get-FirstPropertyValue -InputObject $Ticket -Names @('id')
        Number         = Get-FirstPropertyValue -InputObject $Ticket -Names @('ticketNumber', 'id')
        Summary        = Get-FirstPropertyValue -InputObject $Ticket -Names @('summary')
        CompanyId      = Get-FirstPropertyValue -InputObject $company -Names @('id')
        CompanyName    = Get-FirstPropertyValue -InputObject $company -Names @('name', 'identifier')
        Board          = Get-FirstPropertyValue -InputObject $board -Names @('name')
        Status         = Get-FirstPropertyValue -InputObject $status -Names @('name')
        Priority       = Get-FirstPropertyValue -InputObject $priority -Names @('name')
        Owner          = Get-FirstPropertyValue -InputObject $owner -Names @('name', 'identifier')
        Resources      = Get-FirstPropertyValue -InputObject $Ticket -Names @('resources')
        EnteredDate    = $enteredDate
        RequiredDate   = $requiredDate
        LastUpdated    = $lastUpdated
        Closed         = $closedFlag
        IsInSla        = $isInSla
        IsOverdue      = $isOverdue
        Url            = Get-ConnectWiseTicketUrl -Config $Config -Ticket $Ticket
        Configurations = @()
        RawTicket      = $Ticket
    }
}

function Get-ProviderTickets {
    param(
        [object]$Config,
        [object]$ProviderCompanyId,
        [object]$AssetConfig
    )

    switch ($Config.Provider) {
        'ConnectWise' {
            $conditions = Get-TicketConditionsForCompany -GlobalConfig $Config -AssetConfig $AssetConfig -ProviderCompanyId $ProviderCompanyId
            $query = @{
                conditions = $conditions
                orderBy    = 'dateEntered desc'
            }

            $rawTickets = @(Get-ConnectWisePagedCollection -Path '/service/tickets' -BaseQuery $query -Config $Config)
            $tickets = @($rawTickets | ForEach-Object { ConvertTo-NormalizedTicket -Ticket $_ -Config $Config })
            $script:RunSummary.TicketsFound += $tickets.Count
            return $tickets
        }
        default {
            throw "Provider '$($Config.Provider)' is not implemented."
        }
    }
}

function New-ProviderTicket {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [object]$Config,
        [hashtable]$TicketBody
    )

    if (-not $EnableWriteBack) {
        throw 'Write-back is disabled. Re-run with -EnableWriteBack to allow ticket creation.'
    }

    if ($script:DryRunMode -or $WhatIfPreference) {
        Write-Log -Message 'Dry run: would create provider ticket.'
        return [PSCustomObject]@{ dry_run = $true; body = $TicketBody }
    }

    switch ($Config.Provider) {
        'ConnectWise' {
            if ($PSCmdlet.ShouldProcess('ConnectWise service ticket', 'Create ticket')) {
                return Invoke-ConnectWiseApi -Method 'POST' -Path '/service/tickets' -Body $TicketBody -Config $Config
            }
        }
        default {
            throw "Provider '$($Config.Provider)' is not implemented."
        }
    }
}

function Update-ProviderTicket {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [object]$TicketId,
        [object[]]$PatchOperations
    )

    if (-not $EnableWriteBack) {
        throw 'Write-back is disabled. Re-run with -EnableWriteBack to allow ticket updates.'
    }

    if ($script:DryRunMode -or $WhatIfPreference) {
        Write-Log -Message "Dry run: would update provider ticket '$TicketId'."
        return [PSCustomObject]@{ dry_run = $true; ticket_id = $TicketId; operations = $PatchOperations }
    }

    switch ($Config.Provider) {
        'ConnectWise' {
            if ($PSCmdlet.ShouldProcess("ConnectWise service ticket $TicketId", 'Patch ticket')) {
                return Invoke-ConnectWiseApi -Method 'PATCH' -Path "/service/tickets/$TicketId" -Body $PatchOperations -Config $Config
            }
        }
        default {
            throw "Provider '$($Config.Provider)' is not implemented."
        }
    }
}

function Get-HuduIntegrationProviderId {
    param([object]$Company)

    $integrations = @(Get-ObjectProperty -InputObject $Company -Name 'integrations')
    foreach ($integration in $integrations) {
        $name = Get-FirstPropertyValue -InputObject $integration -Names @('integrator_name', 'name', 'slug')
        if ([string]::IsNullOrWhiteSpace($name) -or $name -notmatch '(?i)(connectwise|cw manage|cw psa)') {
            continue
        }

        $syncId = Get-FirstPropertyValue -InputObject $integration -Names @('sync_id', 'syncId', 'external_id', 'externalId', 'id')
        if ($syncId) {
            return "$syncId"
        }
    }

    return $null
}

function Get-CompanyMappings {
    param(
        [object[]]$HuduCompanies,
        [object[]]$ProviderCompanies,
        [object]$AssetConfigLookup
    )

    $providerById = @{}
    $providerByName = @{}

    foreach ($providerCompany in $ProviderCompanies) {
        $providerId = Get-FirstPropertyValue -InputObject $providerCompany -Names @('id')
        $providerName = Get-FirstPropertyValue -InputObject $providerCompany -Names @('name', 'identifier')
        if ($providerId) {
            $providerById["$providerId"] = $providerCompany
        }
        if ($providerName) {
            $providerByName[(ConvertTo-NormalizedName -Name $providerName)] = $providerCompany
        }
    }

    $mappings = [System.Collections.Generic.List[object]]::new()

    foreach ($huduCompany in $HuduCompanies) {
        $huduCompanyId = Get-FirstPropertyValue -InputObject $huduCompany -Names @('id')
        $huduCompanyName = Get-FirstPropertyValue -InputObject $huduCompany -Names @('name', 'company_name')
        $assetConfig = $null

        if ($huduCompanyId -and $AssetConfigLookup.ByCompanyId.ContainsKey("$huduCompanyId")) {
            $assetConfig = $AssetConfigLookup.ByCompanyId["$huduCompanyId"]
        }
        elseif ($huduCompanyName -and $AssetConfigLookup.ByCompanyName.ContainsKey((ConvertTo-NormalizedName -Name $huduCompanyName))) {
            $assetConfig = $AssetConfigLookup.ByCompanyName[(ConvertTo-NormalizedName -Name $huduCompanyName)]
        }

        $enabled = ConvertTo-BooleanValue -Value (Get-ConfigFieldValue -AssetConfig $assetConfig -FieldName 'ENABLED')
        if ($null -ne $enabled -and $enabled -eq $false) {
            $script:RunSummary.SkippedCompanies++
            Write-Log -Level Debug -Message "Skipping '$huduCompanyName' because CW Manage:ENABLED is false."
            continue
        }

        $matchSource = $null
        $providerCompany = $null
        $integrationId = Get-HuduIntegrationProviderId -Company $huduCompany
        if ($integrationId -and $providerById.ContainsKey("$integrationId")) {
            $providerCompany = $providerById["$integrationId"]
            $matchSource = 'Hudu integration sync id'
        }

        if ($null -eq $providerCompany) {
            $assetCompanyId = Get-ConfigFieldValue -AssetConfig $assetConfig -FieldName 'CompanyId'
            if ($assetCompanyId -and $providerById.ContainsKey("$assetCompanyId")) {
                $providerCompany = $providerById["$assetCompanyId"]
                $matchSource = 'Company Details asset field'
            }
        }

        if ($null -eq $providerCompany -and $huduCompanyName) {
            $normalizedName = ConvertTo-NormalizedName -Name $huduCompanyName
            if ($providerByName.ContainsKey($normalizedName)) {
                $providerCompany = $providerByName[$normalizedName]
                $matchSource = 'normalized company name'
            }
        }

        if ($null -eq $providerCompany) {
            $script:RunSummary.SkippedCompanies++
            Write-Log -Level Warning -Message "No ConnectWise company match found for Hudu company '$huduCompanyName'."
            continue
        }

        $mappings.Add([PSCustomObject]@{
            HuduCompany      = $huduCompany
            ProviderCompany  = $providerCompany
            AssetConfig      = $assetConfig
            MatchSource      = $matchSource
            HuduCompanyName  = $huduCompanyName
            ProviderCompanyId = Get-FirstPropertyValue -InputObject $providerCompany -Names @('id')
            ProviderCompanyName = Get-FirstPropertyValue -InputObject $providerCompany -Names @('name', 'identifier')
        }) | Out-Null
    }

    $script:RunSummary.MatchedCompanies = $mappings.Count
    return @($mappings)
}

function Get-TicketAgeText {
    param([object]$Ticket)

    $enteredDate = Get-ObjectProperty -InputObject $Ticket -Name 'EnteredDate'
    if ($null -eq $enteredDate) {
        return ''
    }

    $age = New-TimeSpan -Start $enteredDate -End (Get-Date)
    if ($age.TotalDays -ge 1) {
        return '{0:n0}d' -f [math]::Floor($age.TotalDays)
    }

    return '{0:n0}h' -f [math]::Max(0, [math]::Floor($age.TotalHours))
}

function Format-DateForDash {
    param([object]$DateValue)

    if ($null -eq $DateValue) {
        return '-'
    }

    try {
        return ([datetime]$DateValue).ToString('yyyy-MM-dd')
    }
    catch {
        return "$DateValue"
    }
}

function Format-DashValue {
    param(
        [object]$Value,
        [int]$MaxLength = 0
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
        return '-'
    }

    $text = "$Value".Trim()
    if ($MaxLength -gt 0 -and $text.Length -gt $MaxLength) {
        $text = $text.Substring(0, [math]::Max(0, $MaxLength - 1)).TrimEnd() + '...'
    }

    return $text
}

function Get-MagicDashStatus {
    param([object[]]$Tickets)

    $ticketCount = @($Tickets).Count
    $overdueCount = @($Tickets | Where-Object { $_.IsOverdue }).Count

    if ($ticketCount -eq 0) {
        return [PSCustomObject]@{
            Message = 'No Open Tickets'
            Shade   = 'success'
        }
    }

    if ($overdueCount -ge $DangerOverdueThreshold) {
        return [PSCustomObject]@{
            Message = "$overdueCount / $ticketCount Tickets Overdue"
            Shade   = 'danger'
        }
    }

    if ($overdueCount -ge $WarningOverdueThreshold) {
        return [PSCustomObject]@{
            Message = "$overdueCount / $ticketCount Tickets Overdue"
            Shade   = 'warning'
        }
    }

    return [PSCustomObject]@{
        Message = "$ticketCount Open Tickets"
        Shade   = 'success'
    }
}

function New-TicketLinkHtml {
    param([object]$Ticket)

    $number = ConvertTo-HtmlText -Value (Format-DashValue -Value (Get-ObjectProperty -InputObject $Ticket -Name 'Number'))
    $url = Get-ObjectProperty -InputObject $Ticket -Name 'Url'

    if (-not [string]::IsNullOrWhiteSpace($url)) {
        return '<a target="_blank" href="{0}">{1}</a>' -f (ConvertTo-HtmlText -Value $url), $number
    }

    return $number
}

function New-ConfigurationLinksHtml {
    param([object[]]$Configurations)

    $configs = @($Configurations | Where-Object { $_ })
    if ($configs.Count -eq 0) {
        return '-'
    }

    $links = foreach ($config in $configs | Select-Object -First 3) {
        $fullName = Format-DashValue -Value (Get-FirstPropertyValue -InputObject $config -Names @('Name', 'Id'))
        $displayName = Format-DashValue -Value $fullName -MaxLength 32
        $title = ConvertTo-HtmlText -Value $fullName
        $url = Get-FirstPropertyValue -InputObject $config -Names @('HuduUrl')
        if (-not [string]::IsNullOrWhiteSpace($url)) {
            '<a target="_blank" title="{0}" href="{1}">{2}</a>' -f $title, (ConvertTo-HtmlText -Value $url), (ConvertTo-HtmlText -Value $displayName)
        }
        else {
            '<span title="{0}">{1}</span>' -f $title, (ConvertTo-HtmlText -Value $displayName)
        }
    }

    if ($configs.Count -gt 3) {
        $links += ('+{0} more' -f ($configs.Count - 3))
    }

    return $links -join '<br />'
}

function Get-TicketFieldValueHtml {
    param(
        [object]$Ticket,
        [string]$Field
    )

    switch ($Field) {
        'Ticket' { return New-TicketLinkHtml -Ticket $Ticket }
        'Summary' { return ConvertTo-HtmlText -Value (Format-DashValue -Value $Ticket.Summary -MaxLength 110) }
        'Board' { return ConvertTo-HtmlText -Value (Format-DashValue -Value $Ticket.Board -MaxLength 28) }
        'Status' { return ConvertTo-HtmlText -Value (Format-DashValue -Value $Ticket.Status -MaxLength 28) }
        'Priority' { return ConvertTo-HtmlText -Value (Format-DashValue -Value $Ticket.Priority -MaxLength 28) }
        'Owner' { return ConvertTo-HtmlText -Value (Format-DashValue -Value (Get-FirstPropertyValue -InputObject $Ticket -Names @('Owner', 'Resources')) -MaxLength 30) }
        'Age' { return ConvertTo-HtmlText -Value (Format-DashValue -Value (Get-TicketAgeText -Ticket $Ticket)) }
        'Due' { return ConvertTo-HtmlText -Value (Format-DateForDash -DateValue $Ticket.RequiredDate) }
        'Configurations' { return New-ConfigurationLinksHtml -Configurations $Ticket.Configurations }
        default { return '-' }
    }
}

function Get-TicketColumnCss {
    param([object]$Config)

    $rules = foreach ($field in @($Config.TicketFields)) {
        $width = Get-ObjectProperty -InputObject $Config.TicketColumnWidths -Name $field
        if ([string]::IsNullOrWhiteSpace($width) -or $width -eq 'auto') {
            continue
        }

        '.psa-ticket-dash .{0}-col{{width:{1}}}' -f $field.ToLowerInvariant(), $width
    }

    return @($rules) -join ''
}

function New-TicketMagicDashContent {
    param(
        [object[]]$Tickets,
        [object]$AssetConfig,
        [object]$Config
    )

    $note = Get-ConfigFieldValue -AssetConfig $AssetConfig -FieldName 'NOTE'
    $portalUrl = Get-ConfigFieldValue -AssetConfig $AssetConfig -FieldName 'URL'
    $orderedTickets = @($Tickets | Sort-Object @{ Expression = 'IsOverdue'; Descending = $true }, @{ Expression = 'RequiredDate'; Ascending = $true }, @{ Expression = 'EnteredDate'; Ascending = $true } | Select-Object -First $MaxTicketsPerCompany)

    $html = [System.Text.StringBuilder]::new()
    $columnCss = Get-TicketColumnCss -Config $Config
    $null = $html.AppendLine(('<style>.psa-ticket-dash{{font-size:13px;overflow-x:auto}}.psa-ticket-dash__meta{{margin:0 0 10px 0;color:#4b5563}}.psa-ticket-dash__link{{font-weight:600}}.psa-ticket-dash table{{width:100%;border-collapse:collapse;background:#fff}}.psa-ticket-dash th{{font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:#6b7280;text-align:left;border-bottom:1px solid #e5e7eb;padding:8px 10px;white-space:nowrap}}.psa-ticket-dash td{{border-bottom:1px solid #f1f5f9;padding:9px 10px;vertical-align:top;line-height:1.35}}.psa-ticket-dash tr.overdue td{{background:#fff7ed}}.psa-ticket-dash .summary-col{{min-width:220px}}.psa-ticket-dash .configurations-col{{white-space:normal;overflow-wrap:anywhere;word-break:break-word}}.psa-ticket-dash td:last-child{{white-space:normal;overflow-wrap:anywhere;word-break:break-word}}{0}.psa-ticket-dash .empty{{padding:12px;background:#f8fafc;border:1px solid #e5e7eb;border-radius:6px}}</style>' -f $columnCss))
    $null = $html.AppendLine('<div class="psa-ticket-dash">')

    if (-not [string]::IsNullOrWhiteSpace($note)) {
        $null = $html.AppendLine(('<p class="psa-ticket-dash__meta">{0}</p>' -f (ConvertTo-HtmlText -Value $note)))
    }

    if (-not [string]::IsNullOrWhiteSpace($portalUrl)) {
        $null = $html.AppendLine(('<p class="psa-ticket-dash__meta"><a class="psa-ticket-dash__link" target="_blank" href="{0}">Open ConnectWise company view</a></p>' -f (ConvertTo-HtmlText -Value $portalUrl)))
    }

    if (@($Tickets).Count -eq 0) {
        $null = $html.AppendLine('<p class="empty">No open ConnectWise tickets found for this company.</p>')
        $null = $html.AppendLine('</div>')
        return $html.ToString()
    }

    $null = $html.AppendLine('<table>')
    $headerCells = foreach ($field in @($Config.TicketFields)) {
        $className = ('{0}-col' -f $field.ToLowerInvariant())
        '<th class="{0}">{1}</th>' -f $className, (ConvertTo-HtmlText -Value $field)
    }
    $null = $html.AppendLine(('<thead><tr>{0}</tr></thead>' -f ($headerCells -join '')))
    $null = $html.AppendLine('<tbody>')

    foreach ($ticket in $orderedTickets) {
        $rowClass = if ($ticket.IsOverdue) { ' class="overdue"' } else { '' }
        $cells = foreach ($field in @($Config.TicketFields)) {
            Get-TicketFieldValueHtml -Ticket $ticket -Field $field
        }
        $null = $html.AppendLine(('<tr{0}><td>{1}</td></tr>' -f $rowClass, ($cells -join '</td><td>')))
    }

    $null = $html.AppendLine('</tbody></table>')

    if (@($Tickets).Count -gt $orderedTickets.Count) {
        $null = $html.AppendLine(('<p class="muted">Showing {0} of {1} tickets.</p>' -f $orderedTickets.Count, @($Tickets).Count))
    }

    $null = $html.AppendLine('</div>')
    return $html.ToString()
}

function Invoke-MagicDashRun {
    param([object]$Config)

    $connection = Get-ProviderConnection -Config $Config
    Write-Log -Message "Using $($connection.Provider) provider at $($connection.BaseUrl)."

    Test-HuduConnection -Config $Config
    Test-ProviderConnection -Config $Config

    if ($TestConnectionOnly) {
        Write-Log -Message 'Connection tests completed. Exiting because -TestConnectionOnly was supplied.' -Level Success
        return
    }

    if ($EnableWriteBack) {
        Write-Log -Level Warning -Message 'Write-back helpers are enabled, but the main Magic Dash run does not create or update tickets.'
    }

    $huduCompanies = @(Get-HuduCompaniesForDash -Config $Config)
    Write-Log -Message "Loaded $($huduCompanies.Count) Hudu companies."

    $assetConfigLookup = Get-HuduCompanyDetailsConfig -Config $Config
    $providerCompanies = @(Get-ProviderCompanies -Config $Config)
    Write-Log -Message "Loaded $($providerCompanies.Count) ConnectWise companies."

    $mappings = @(Get-CompanyMappings -HuduCompanies $huduCompanies -ProviderCompanies $providerCompanies -AssetConfigLookup $assetConfigLookup)
    Write-Log -Message "Matched $($mappings.Count) Hudu companies to ConnectWise companies."

    foreach ($mapping in $mappings) {
        $huduCompanyName = $mapping.HuduCompanyName
        $providerCompanyId = $mapping.ProviderCompanyId

        try {
            Write-Log -Message "Processing '$huduCompanyName' using ConnectWise company '$($mapping.ProviderCompanyName)' via $($mapping.MatchSource)."
            $tickets = @(Get-ProviderTickets -Config $Config -ProviderCompanyId $providerCompanyId -AssetConfig $mapping.AssetConfig)
            if (Test-TicketFieldEnabled -Config $Config -Field 'Configurations') {
                $huduCompanyId = Get-FirstPropertyValue -InputObject $mapping.HuduCompany -Names @('id')
                $configurationLookup = Get-HuduConfigurationAssetLookup -Config $Config -HuduCompanyId $huduCompanyId
                foreach ($ticket in $tickets) {
                    $ticketConfigurations = @(Get-ConnectWiseTicketConfigurations -Config $Config -TicketId $ticket.Id)
                    $normalizedConfigurations = @($ticketConfigurations | ForEach-Object {
                        ConvertTo-NormalizedTicketConfiguration -Configuration $_ -HuduConfigurationLookup $configurationLookup
                    })
                    $ticket.Configurations = $normalizedConfigurations
                }
            }
            $status = Get-MagicDashStatus -Tickets $tickets
            $content = New-TicketMagicDashContent -Tickets $tickets -AssetConfig $mapping.AssetConfig -Config $Config

            $null = Set-HuduMagicDashTile -Config $Config `
                -CompanyName $huduCompanyName `
                -Title 'ConnectWise - Open Tickets' `
                -Message $status.Message `
                -Content $content `
                -Shade $status.Shade

            Write-Log -Message "Completed '$huduCompanyName': $($status.Message)." -Level Success
        }
        catch {
            $script:RunSummary.Errors.Add("Failed '$huduCompanyName': $($_.Exception.Message)") | Out-Null
            Write-Warning "Failed '$huduCompanyName': $($_.Exception.Message)"
        }
    }
}

try {
    $config = Resolve-RuntimeConfig
    Invoke-MagicDashRun -Config $config
}
finally {
    $script:RunSummary.FinishedAt = Get-Date
    $script:RunSummary.DurationSeconds = [math]::Round((New-TimeSpan -Start $script:RunSummary.StartedAt -End $script:RunSummary.FinishedAt).TotalSeconds, 2)
    Write-Host ''
    Write-Host 'Run summary:'
    [PSCustomObject]$script:RunSummary | Format-List
}
