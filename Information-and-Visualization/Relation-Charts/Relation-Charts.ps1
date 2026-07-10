
# Creates one relation graph per selected company. Company-owned assets and
# articles are used as the starting scope, and any relation touching those
# objects is included. Related objects from other companies are kept on the graph
# as external nodes so cross-company relationships remain visible.

# By default this writes local Mermaid and HTML files. Add -PublishArticles to
# create or update one Hudu article per company.

[string]$ArticleNamePrefix = "Relation Map - "
[string]$RelationMapGeneratorVersion = "Mermaid hardened v2"
[string]$Direction = 'LR' # 'TB', 'TD', 'BT', 'RL', 'LR'
[int]$EdgeStrokeWidth = 3
[int]$ExternalRelationThreshold = 25
[int]$MaxExternalRelations = 150
[int]$MaxRelationMapNodes = 350
[int]$LargeMapSectionThreshold = 40
[int]$MinConnectedSectionSize = 5
[bool]$OptimizeLayoutOrdering = $true
[string]$MapBackgroundColor = '#f7f9fc'
[string]$InCompanyNodeColor = '#e9f5ff'
[string]$OutsideCompanyNodeColor = '#fff4e5'
[string]$OutputDirectory = $(Join-Path $(resolve-path .\).Path 'output')
[string[]]$ScopeObjectTypes = @('Asset', 'Article', 'AssetPassword', 'Procedure', 'Website', 'Company', 'Network', 'RackStorage')

[string]$HuduBaseURL = $HuduBaseURL ?? $(read-host "please enter hudu base url")
[string]$HuduAPIKey = $HuduAPIKey ?? $(read-host "please enter hudu api key");  clear-host;

[bool]$IncludeGlobalArticles = $true
[bool]$PublishArticles = $true
[bool]$IncludeArchivedAssets = $true
[bool]$OnlyIncludeExternalRelationsWhenSparse = $true
[bool]$GroupLargeMapsByConnectedSection = $true
[bool]$EmbedAssetPasswordsInAssetNodes = $true
[bool]$HideEmbeddedAssetPasswordRelationNodes = $true
[int]$MaxEmbeddedAssetPasswords = 8
[string]$AzVault_HuduSecretName = "HuduAPIKeySecretName"                 # Name of your secret in AZure Keystore for your Hudu API key
[string]$AzVault_Name           = "MyVaultName"                          # Name of your Azure Keyvault
[bool]$UseAZVault = $false
Set-StrictMode -Version 3.0
$script:RelateMapListCache = @{}

if ($true -eq $UseAZVault) {
  foreach ($module in @('Az.KeyVault')) {if (Get-Module -ListAvailable -Name $module) { Write-Host "Importing module, $module..."; Import-Module $module } else {Write-Host "Installing and importing module $module..."; Install-Module $module -Force -AllowClobber; Import-Module $module }}
  if (-not (Get-AzContext)) { Connect-AzAccount };
  $HuduAPIKey = "$(Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AzVault_HuduSecretName" -AsPlainText)"
}

function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSversion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Version
    Write-Host "Required PowerShell version: $RequiredPSversion" -ForegroundColor Blue

    if ($currentPSVersion -lt $RequiredPSversion) {
        Write-Host "PowerShell $RequiredPSversion or higher is required. You have $currentPSVersion." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
    }
}
function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
        [bool]$use_hudu_fork = $true
        )

    if ($true -eq $use_hudu_fork) {
        if (-not $(Test-Path $HAPImodulePath)) {
            $dst = Split-Path -Path (Split-Path -Path $HAPImodulePath -Parent) -Parent
            Write-Host "Using Lastest Master Branch of Hudu Fork for HuduAPI"
            $zip = "$env:TEMP\huduapi.zip"
            Invoke-WebRequest -Uri "https://github.com/Hudu-Technologies-Inc/HuduAPI/archive/refs/heads/master.zip" -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force 
            $extracted = Join-Path $env:TEMP "HuduAPI-master" 
            if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
            Move-Item -Path $extracted -Destination $dst 
            Remove-Item $zip -Force
        }
    } else {
        Write-Host "Assuming PSGallery Module if not already locally cloned at $HAPImodulePath"
    }

    if (Test-Path $HAPImodulePath) {
        Import-Module $HAPImodulePath -Force
        Write-Host "Module imported from $HAPImodulePath"
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'3.0.0') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 3.0.0 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}

function Set-HuduInstance {
    param(
        [string]$HuduBaseURL,
        [string]$HuduAPIKey
    )
    $HuduBaseURL = $HuduBaseURL ?? 
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}
function Get-HuduVersionCompatible {
    param (
        [string]$requiredVersion = "2.43.1",
        $DisallowedVersions = @(([version]"2.37.0"))
    )
    $RequiredHuduVersion = $([version]$requiredVersion)
    Write-Host "Required Hudu version: $requiredversion" -ForegroundColor Blue
    try {
        $HuduAppInfo = Get-HuduAppInfo
        $CurrentHuduVersion = $HuduAppInfo.version

        if ([version]$CurrentHuduVersion -lt [version]$RequiredHuduVersion) {
            Write-Host "This script requires at least version $RequiredHuduVersion and cannot run with version $CurrentHuduVersion. Please update your version of Hudu." -ForegroundColor Red
            exit 1
        }
    } catch {
        write-host "error encountered when checking hudu version for $(Get-HuduBaseURL) - $_"
    }
    Write-Host "Hudu Version $CurrentHuduVersion is compatible"  -ForegroundColor Green
}

function Get-NormalizedHuduObject {
    param([object]$Object)

    if ($null -eq $Object) { return $null }

    foreach ($wrapperName in @('asset', 'article', 'company', 'website', 'password', 'asset_password', 'procedure', 'network', 'vlan', 'vlan_zone', 'ip_address', 'rack_storage', 'upload')) {
        if ($Object.PSObject.Properties.Name -contains $wrapperName -and $null -ne $Object.$wrapperName) {
            $wrappedValue = $Object.$wrapperName
            if ($wrappedValue -is [System.Collections.IDictionary] -or $wrappedValue -is [pscustomobject]) {
                return $wrappedValue
            }
        }
    }

    return $Object
}

function Get-HuduPropertyValue {
    param(
        [object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $Object) { return $DefaultValue }
    if ($Object.PSObject.Properties.Name -notcontains $Name) { return $DefaultValue }
    return $Object.$Name
}

function Get-HuduPropertyValues {
    param(
        [object]$Object,
        [string[]]$Names
    )

    $values = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Object) { return @() }

    foreach ($name in $Names) {
        $value = Get-HuduPropertyValue -Object $Object -Name $name
        if ($null -eq $value) { continue }

        if ($value -is [string]) {
            foreach ($part in @($value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                $values.Add($part)
            }
        } elseif ($value -is [System.Collections.IEnumerable]) {
            foreach ($item in $value) {
                if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
                    $values.Add($item)
                }
            }
        } else {
            $values.Add($value)
        }
    }

    return @($values)
}

function Test-HuduObjectReferencesId {
    param(
        [object]$Object,
        [Parameter(Mandatory)][object]$Id,
        [string[]]$IdPropertyNames,
        [string]$RequiredType,
        [string[]]$TypePropertyNames = @()
    )

    if ($null -eq $Object -or $null -eq $Id) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($RequiredType) -and $TypePropertyNames.Count -gt 0) {
        $typeValues = @(Get-HuduPropertyValues -Object $Object -Names $TypePropertyNames)
        if ($typeValues.Count -gt 0 -and -not @($typeValues | Where-Object { "$_" -ieq $RequiredType })) {
            return $false
        }
    }

    foreach ($value in @(Get-HuduPropertyValues -Object $Object -Names $IdPropertyNames)) {
        if ("$value" -eq "$Id") { return $true }
    }

    return $false
}

function Test-HuduObjectReferencesName {
    param(
        [object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [string[]]$NamePropertyNames
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $false }

    foreach ($value in @(Get-HuduPropertyValues -Object $Object -Names $NamePropertyNames)) {
        if ("$value" -ieq $Name) { return $true }
    }

    return $false
}

function Get-CompanyPasswordsForRelateMap {
    param([Parameter(Mandatory)][object]$Company)

    if (-not (Get-Command -Name Get-HuduPasswords -ErrorAction SilentlyContinue)) { return @() }

    try {
        return @(Get-HuduPasswords -CompanyId $Company.id | ForEach-Object { Get-NormalizedHuduObject -Object $_ })
    } catch {
        Write-Warning "Could not load passwords for company $($Company.name): $($_.Exception.Message)"
        return @()
    }
}

function Get-HuduRelationTypeConfig {
    param([Parameter(Mandatory)][string]$Type)

    $configs = @{
        Asset         = @{ Command = 'Get-HuduAssets'; CompanyScoped = $true }
        Article       = @{ Command = 'Get-HuduArticles'; CompanyScoped = $true }
        AssetPassword = @{ Command = 'Get-HuduPasswords'; CompanyScoped = $true }
        Password      = @{ Command = 'Get-HuduPasswords'; CompanyScoped = $true }
        Procedure     = @{ Command = 'Get-HuduProcedures'; CompanyScoped = $true }
        Website       = @{ Command = 'Get-HuduWebsites'; CompanyScoped = $false; FilterAllByCompany = $true }
        Company       = @{ Command = 'Get-HuduCompanies'; CompanyScoped = $false }
        Network       = @{ Command = 'Get-HuduNetworks'; CompanyScoped = $true }
        Vlan          = @{ Command = 'Get-HuduVLANs'; CompanyScoped = $true }
        VlanZone      = @{ Command = 'Get-HuduVLANZones'; CompanyScoped = $true }
        IpAddress     = @{ Command = 'Get-HuduIPAddresses'; CompanyScoped = $true }
        RackStorage   = @{ Command = 'Get-HuduRackStorages'; CompanyScoped = $true }
        Upload        = @{ Command = 'Get-HuduUploads'; CompanyScoped = $false }
    }

    foreach ($key in $configs.Keys) {
        if ($key -ieq $Type) { return $configs[$key] }
    }

    return $null
}

function Get-HuduObjectsForRelationScope {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][object]$Company
    )

    if ($Type -ieq 'Company') {
        return @($Company)
    }

    $config = Get-HuduRelationTypeConfig -Type $Type
    if (-not $config) { return @() }
    if (-not (Get-Command -Name $config.Command -ErrorAction SilentlyContinue)) { return @() }

    try {
        $companyScoped = $config.ContainsKey('CompanyScoped') -and $config.CompanyScoped
        $filterAllByCompany = $config.ContainsKey('FilterAllByCompany') -and $config.FilterAllByCompany

        if ($companyScoped) {
            return @(& $config.Command -CompanyId $Company.id | ForEach-Object { Get-NormalizedHuduObject -Object $_ })
        }

        if ($filterAllByCompany) {
            if (-not $script:RelateMapListCache.ContainsKey($Type)) {
                $script:RelateMapListCache[$Type] = @(& $config.Command | ForEach-Object { Get-NormalizedHuduObject -Object $_ })
            }

            return @($script:RelateMapListCache[$Type] | Where-Object {
                (Get-HuduPropertyValue -Object $_ -Name 'company_id') -eq $Company.id
            })
        }
    } catch {
        Write-Warning "Could not load $Type objects for company $($Company.name): $($_.Exception.Message)"
    }

    return @()
}

function Get-ObjectKey {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][object]$Id
    )

    return "$($Type.ToLowerInvariant())|$Id"
}

function New-RelationTypeScopeSet {
    param([string[]]$Types)

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($type in @($Types)) {
        if ([string]::IsNullOrWhiteSpace($type)) { continue }

        $cleanType = $type.Trim()
        $null = $set.Add($cleanType)

        switch ($cleanType) {
            'AssetPassword' { $null = $set.Add('Password') }
            'Password' { $null = $set.Add('AssetPassword') }
        }
    }

    return $set
}

function ConvertTo-MermaidId {
    param(
        [Parameter(Mandatory)][string]$Value
    )

    $safe = $Value -replace '[^A-Za-z0-9_]', '_'
    if ($safe -match '^[0-9]') { $safe = "N_$safe" }
    return $safe
}

function ConvertTo-MermaidLabel {
    param([string]$Value)

    if ($null -eq $Value) { return '' }

    $label = [System.Net.WebUtility]::HtmlEncode($Value)
    $label = $label -replace '&lt;br/&gt;', '<br/>'
    $label = $label -replace '"', '&quot;'
    return $label
}

function ConvertTo-HtmlText {
    param([string]$Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function ConvertTo-AbsoluteHuduUrl {
    param(
        [string]$Url,
        [string]$BaseUrl
    )

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }

    $cleanUrl = $Url.Trim()
    if ($cleanUrl -match '^https?://') { return $cleanUrl }
    if ($cleanUrl -match '^//') { return "https:$cleanUrl" }

    $cleanBaseUrl = $BaseUrl
    if ([string]::IsNullOrWhiteSpace($cleanBaseUrl)) {
        $cleanBaseUrl = try { Get-HuduBaseURL } catch { $null }
    }

    if (-not [string]::IsNullOrWhiteSpace($cleanBaseUrl)) {
        $cleanBaseUrl = $cleanBaseUrl.Trim().TrimEnd('/')
        if ($cleanBaseUrl -notmatch '^https?://') {
            $cleanBaseUrl = "https://$cleanBaseUrl"
        }

        if ($cleanUrl.StartsWith('/')) {
            return "$cleanBaseUrl$cleanUrl"
        }

        if ($cleanUrl -match '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/|$)') {
            return "https://$cleanUrl"
        }

        return "$cleanBaseUrl/$($cleanUrl.TrimStart('/'))"
    }

    if ($cleanUrl -match '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/|$)') {
        return "https://$cleanUrl"
    }

    return $cleanUrl
}

function ConvertTo-MermaidQuotedText {
    param([string]$Value)

    if ($null -eq $Value) { return '' }
    return (($Value -replace '\\', '\\') -replace '"', '\"')
}

function Get-HuduObjectName {
    param([object]$Object)

    if ($null -eq $Object) { return $null }

    foreach ($propertyName in @('name', 'title', 'hostname', 'url', 'domain', 'slug', 'address', 'ip')) {
        $value = Get-HuduPropertyValue -Object $Object -Name $propertyName
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    return $null
}

function Get-HuduObjectUrl {
    param(
        [object]$Object,
        [string]$BaseUrl
    )

    foreach ($propertyName in @('url', 'html_url', 'record_url')) {
        $url = [string](Get-HuduPropertyValue -Object $Object -Name $propertyName)
        if ([string]::IsNullOrWhiteSpace($url)) { continue }

        return ConvertTo-AbsoluteHuduUrl -Url $url -BaseUrl $BaseUrl
    }

    return $null
}

function New-NodeRecord {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][object]$Id,
        [object]$Object,
        [string]$AssetLayoutName,
        [string]$CompanyName,
        [int]$ScopeCompanyId,
        [array]$EmbeddedPasswords = @()
    )

    $object = Get-NormalizedHuduObject -Object $Object
    $objectName = Get-HuduObjectName -Object $object
    if ([string]::IsNullOrWhiteSpace($objectName)) {
        $objectName = "$Type $Id"
    }

    $objectCompanyId = $null
    $rawCompanyId = Get-HuduPropertyValue -Object $object -Name 'company_id'
    if ($null -ne $rawCompanyId) {
        $objectCompanyId = [int]$rawCompanyId
    }

    $category = switch -Regex ($Type) {
        '^Asset$' {
            if ([string]::IsNullOrWhiteSpace($AssetLayoutName)) { 'Asset: Unknown Layout' } else { "Asset: $AssetLayoutName" }
            break
        }
        '^Article$' { 'Article'; break }
        '^Procedure$' { 'Procedure / Process'; break }
        default { $Type; break }
    }

    $scope = if ($null -ne $objectCompanyId -and $objectCompanyId -ne $ScopeCompanyId) {
        'External'
    } elseif ($null -eq $objectCompanyId -and $Type -ieq 'Article') {
        'Global'
    } else {
        'Scoped'
    }

    [PSCustomObject]@{
        Key           = Get-ObjectKey -Type $Type -Id $Id
        MermaidId     = ConvertTo-MermaidId -Value "$(Get-ObjectKey -Type $Type -Id $Id)"
        Type          = $Type
        Id            = $Id
        Name          = $objectName
        Category      = $category
        Scope         = $scope
        CompanyId     = $objectCompanyId
        CompanyName   = $CompanyName
        AssetLayout   = $AssetLayoutName
        EmbeddedPasswords = @($EmbeddedPasswords)
        Object        = $object
    }
}

function Resolve-RelationEndpointNode {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][object]$Id,
        [Parameter(Mandatory)][hashtable]$ObjectByKey,
        [Parameter(Mandatory)][hashtable]$LayoutById,
        [Parameter(Mandatory)][hashtable]$CompanyById,
        [Parameter(Mandatory)][int]$ScopeCompanyId
    )

    $key = Get-ObjectKey -Type $Type -Id $Id
    $object = $null
    $layoutName = $null
    $companyName = $null

    if ($ObjectByKey.ContainsKey($key)) {
        $object = $ObjectByKey[$key]
    } else {
        $config = Get-HuduRelationTypeConfig -Type $Type
        if ($config -and (Get-Command -Name $config.Command -ErrorAction SilentlyContinue)) {
            try {
                $object = Get-NormalizedHuduObject -Object (& $config.Command -Id ([int]$Id))
                if ($object) { $ObjectByKey[$key] = $object }
            } catch {
                Write-Warning "Could not resolve external $Type $Id : $($_.Exception.Message)"
            }
        }
    }

    if ($Type -ieq 'Asset') {
        $assetLayoutId = Get-HuduPropertyValue -Object $object -Name 'asset_layout_id'
        if ($null -ne $assetLayoutId -and $LayoutById.ContainsKey([string]$assetLayoutId)) {
            $layoutName = $LayoutById[[string]$assetLayoutId].name
        }
    }

    $companyId = Get-HuduPropertyValue -Object $object -Name 'company_id'
    if ($null -ne $companyId) {
        if ($CompanyById.ContainsKey([string]$companyId)) {
            $companyName = $CompanyById[[string]$companyId].name
        } else {
            $companyName = "Company $companyId"
        }
    }

    return New-NodeRecord `
        -Type $Type `
        -Id $Id `
        -Object $object `
        -AssetLayoutName $layoutName `
        -CompanyName $companyName `
        -ScopeCompanyId $ScopeCompanyId
}

function Get-RelationMapConnectedSections {
    param(
        [array]$Nodes,
        [array]$Relations,
        [int]$MinSectionSize = 1
    )

    $nodeByKey = @{}
    $adjacency = @{}
    foreach ($node in $Nodes) {
        $nodeByKey[$node.Key] = $node
        $adjacency[$node.Key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    foreach ($relation in $Relations) {
        $fromKey = Get-ObjectKey -Type $relation.fromable_type -Id $relation.fromable_id
        $toKey = Get-ObjectKey -Type $relation.toable_type -Id $relation.toable_id
        if (-not $adjacency.ContainsKey($fromKey) -or -not $adjacency.ContainsKey($toKey)) { continue }

        $null = $adjacency[$fromKey].Add($toKey)
        $null = $adjacency[$toKey].Add($fromKey)
    }

    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $components = [System.Collections.Generic.List[object]]::new()

    foreach ($startNode in @($Nodes | Sort-Object Scope, Category, Name, Id)) {
        if ($visited.Contains($startNode.Key)) { continue }

        $stack = [System.Collections.Generic.Stack[string]]::new()
        $componentKeys = [System.Collections.Generic.List[string]]::new()
        $stack.Push($startNode.Key)
        $null = $visited.Add($startNode.Key)

        while ($stack.Count -gt 0) {
            $currentKey = $stack.Pop()
            $componentKeys.Add($currentKey)

            foreach ($neighborKey in @($adjacency[$currentKey] | Sort-Object)) {
                if ($visited.Contains($neighborKey)) { continue }

                $null = $visited.Add($neighborKey)
                $stack.Push($neighborKey)
            }
        }

        $componentNames = foreach ($key in $componentKeys) {
            if ($nodeByKey.ContainsKey($key)) { $nodeByKey[$key].Name } else { $key }
        }

        $components.Add([PSCustomObject]@{
            Keys     = @($componentKeys)
            Size     = $componentKeys.Count
            SortName = @($componentNames | Sort-Object | Select-Object -First 1)
        })
    }

    $sectionByNodeKey = @{}
    $sectionIndex = 0
    foreach ($component in @($components | Sort-Object @{ Expression = 'Size'; Descending = $true }, SortName)) {
        # Only components large enough to risk tangling get their own numbered
        # section. Smaller components are intentionally left unsectioned so their
        # nodes consolidate into shared per-layout "parent cards" (increasing
        # magnetism between like-layout assets) instead of each spawning its own
        # tiny section. Because these small components have no edges between one
        # another, merging them by layout adds no new edge crossings.
        if ($component.Size -lt $MinSectionSize) { continue }

        $sectionIndex++
        $section = [PSCustomObject]@{
            Index = $sectionIndex
            Size  = $component.Size
            Label = "Section $sectionIndex"
        }

        foreach ($key in $component.Keys) {
            $sectionByNodeKey[$key] = $section
        }
    }

    [PSCustomObject]@{
        Count            = $sectionIndex
        SectionByNodeKey = $sectionByNodeKey
    }
}

function Get-HuduProceduresForRelateMap {
    param(
        [Parameter(Mandatory)][object]$Company,
        [ValidateSet('process', 'run')]
        [string]$Type
    )

    if (-not (Get-Command -Name Get-HuduProcedures -ErrorAction SilentlyContinue)) { return @() }

    try {
        $procedures = @(Get-HuduProcedures -CompanyId $Company.id -Type $Type)
        return @(
            foreach ($procedure in $procedures) {
                foreach ($item in @($procedure)) {
                    Get-NormalizedHuduObject -Object $item
                }
            }
        )
    } catch {
        Write-Warning "Could not load $Type procedures for company $($Company.name): $($_.Exception.Message)"
        return @()
    }
}

function Get-CompanyRelationGraph {
    param(
        [Parameter(Mandatory)][object]$Company,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Relations,
        [Parameter(Mandatory)][hashtable]$LayoutById,
        [Parameter(Mandatory)][hashtable]$CompanyById,
        [Parameter(Mandatory)][string[]]$ScopeObjectTypes,
        [switch]$IncludeArchived,
        [switch]$IncludeGlobalKb,
        [bool]$OnlyIncludeExternalRelationsWhenSparse = $true,
        [int]$ExternalRelationThreshold = 25,
        [int]$MaxExternalRelations = 150,
        [int]$MaxRelationMapNodes = 350,
        [bool]$EmbedAssetPasswordsInAssetNodes = $true,
        [bool]$HideEmbeddedAssetPasswordRelationNodes = $true
    )

    Write-Host "Building relation graph for $($Company.name)..." -ForegroundColor Cyan

    $scopeTypeSet = New-RelationTypeScopeSet -Types $ScopeObjectTypes

    $assets = @(
        if ($scopeTypeSet.Contains('Asset')) {
            Get-HuduAssets -CompanyId $Company.id
        }
    )
    if (-not $IncludeArchived.IsPresent) {
        $assets = @($assets | Where-Object {
            (Get-HuduPropertyValue -Object $_ -Name 'archived' -DefaultValue $false) -ne $true -and
            $null -eq (Get-HuduPropertyValue -Object $_ -Name 'archived_at')
        })
    }

    $articles = @(
        if ($scopeTypeSet.Contains('Article')) {
            Get-HuduArticles -CompanyId $Company.id
        }
    )
    if ($scopeTypeSet.Contains('Article') -and $IncludeGlobalKb.IsPresent) {
        $articles = @($articles) + @(Get-HuduArticles | Where-Object { $null -eq (Get-HuduPropertyValue -Object $_ -Name 'company_id') })
    }
    $excludedArticleKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($article in $articles) {
        $articleName = [string](Get-HuduPropertyValue -Object $article -Name 'name')
        $articleId = Get-HuduPropertyValue -Object $article -Name 'id'
        if (
            -not [string]::IsNullOrWhiteSpace($ArticleNamePrefix) -and
            $articleName -like "$ArticleNamePrefix*" -and
            $null -ne $articleId
        ) {
            $null = $excludedArticleKeys.Add((Get-ObjectKey -Type 'Article' -Id $articleId))
        }
    }

    $articles = @($articles | Where-Object {
        $articleName = [string](Get-HuduPropertyValue -Object $_ -Name 'name')
        [string]::IsNullOrWhiteSpace($ArticleNamePrefix) -or $articleName -notlike "$ArticleNamePrefix*"
    })

    $assetById = @{}
    $objectByKey = @{}
    foreach ($asset in $assets) {
        $normalized = Get-NormalizedHuduObject -Object $asset
        $normalizedId = Get-HuduPropertyValue -Object $normalized -Name 'id'
        if ($normalized -and $null -ne $normalizedId) {
            $key = Get-ObjectKey -Type 'Asset' -Id $normalizedId
            $assetById[$key] = $normalized
            $objectByKey[$key] = $normalized
        }
    }

    $articleById = @{}
    foreach ($article in $articles) {
        $normalized = Get-NormalizedHuduObject -Object $article
        $normalizedId = Get-HuduPropertyValue -Object $normalized -Name 'id'
        if ($normalized -and $null -ne $normalizedId) {
            $key = Get-ObjectKey -Type 'Article' -Id $normalizedId
            $articleById[$key] = $normalized
            $objectByKey[$key] = $normalized
        }
    }

    $scopeKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @(@($assetById.Keys) + @($articleById.Keys))) {
        $null = $scopeKeys.Add($key)
    }

    $assetPasswordMap = @{}
    $embeddedPasswordIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $embeddedPasswordAssetKeyByPasswordKey = @{}
    if ($EmbedAssetPasswordsInAssetNodes -eq $true) {
        foreach ($password in @(Get-CompanyPasswordsForRelateMap -Company $Company)) {
            $passwordId = Get-HuduPropertyValue -Object $password -Name 'id'
            $passwordableType = Get-HuduPropertyValue -Object $password -Name 'passwordable_type'
            $passwordableId = Get-HuduPropertyValue -Object $password -Name 'passwordable_id'

            if ($null -eq $passwordId -or $passwordableType -ine 'Asset' -or $null -eq $passwordableId) { continue }

            $assetKey = Get-ObjectKey -Type 'Asset' -Id $passwordableId
            if (-not $assetById.ContainsKey($assetKey)) { continue }

            if (-not $assetPasswordMap.ContainsKey($assetKey)) {
                $assetPasswordMap[$assetKey] = [System.Collections.Generic.List[object]]::new()
            }

            $assetPasswordMap[$assetKey].Add($password)
            $passwordKey = Get-ObjectKey -Type 'AssetPassword' -Id $passwordId
            $null = $embeddedPasswordIds.Add($passwordKey)
            $embeddedPasswordAssetKeyByPasswordKey[$passwordKey] = $assetKey
        }
    }

    foreach ($scopeType in @($ScopeObjectTypes | Where-Object { $_ -ine 'Asset' -and $_ -ine 'Article' })) {
        foreach ($scopeObject in @(Get-HuduObjectsForRelationScope -Type $scopeType -Company $Company)) {
            $scopeObjectId = Get-HuduPropertyValue -Object $scopeObject -Name 'id'
            if ($null -eq $scopeObjectId) { continue }

            $scopeKey = Get-ObjectKey -Type $scopeType -Id $scopeObjectId
            $objectByKey[$scopeKey] = $scopeObject
            $null = $scopeKeys.Add($scopeKey)
        }
    }

    $scopedRelations = [System.Collections.Generic.List[object]]::new()
    $externalRelations = [System.Collections.Generic.List[object]]::new()
    $outOfScopeRelationsSkipped = 0
    foreach ($relation in $Relations) {
        if (
            -not $scopeTypeSet.Contains([string]$relation.fromable_type) -or
            -not $scopeTypeSet.Contains([string]$relation.toable_type)
        ) {
            $outOfScopeRelationsSkipped++
            continue
        }

        $fromKey = Get-ObjectKey -Type $relation.fromable_type -Id $relation.fromable_id
        $toKey = Get-ObjectKey -Type $relation.toable_type -Id $relation.toable_id
        if ($excludedArticleKeys.Contains($fromKey) -or $excludedArticleKeys.Contains($toKey)) { continue }

        $fromInScope = $scopeKeys.Contains($fromKey)
        $toInScope = $scopeKeys.Contains($toKey)

        if ($fromInScope -and $toInScope) {
            if (
                $HideEmbeddedAssetPasswordRelationNodes -eq $true -and
                (
                    ($embeddedPasswordIds.Contains($fromKey) -and $embeddedPasswordAssetKeyByPasswordKey[$fromKey] -eq $toKey) -or
                    ($embeddedPasswordIds.Contains($toKey) -and $embeddedPasswordAssetKeyByPasswordKey[$toKey] -eq $fromKey)
                )
            ) {
                continue
            }

            $scopedRelations.Add($relation)
        } elseif ($fromInScope -or $toInScope) {
            $externalRelations.Add($relation)
        }
    }

    $includeExternalRelations = (
        $OnlyIncludeExternalRelationsWhenSparse -ne $true -or
        $ExternalRelationThreshold -lt 1 -or
        $scopedRelations.Count -lt $ExternalRelationThreshold
    )

    if (-not $includeExternalRelations -and $externalRelations.Count -gt 0) {
        Write-Host "Skipping $($externalRelations.Count) external relation(s) for $($Company.name) because $($scopedRelations.Count) scoped relations meets/exceeds threshold $ExternalRelationThreshold." -ForegroundColor DarkYellow
    }

    $externalRelationsSkippedByThreshold = if ($includeExternalRelations) { 0 } else { $externalRelations.Count }
    $externalRelationsSkippedByLimit = 0
    $includedExternalRelations = [System.Collections.Generic.List[object]]::new()

    if ($includeExternalRelations) {
        $projectedNodeKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($relation in $scopedRelations) {
            $null = $projectedNodeKeys.Add((Get-ObjectKey -Type $relation.fromable_type -Id $relation.fromable_id))
            $null = $projectedNodeKeys.Add((Get-ObjectKey -Type $relation.toable_type -Id $relation.toable_id))
        }

        foreach ($relation in @($externalRelations | Sort-Object id)) {
            if ($MaxExternalRelations -gt 0 -and $includedExternalRelations.Count -ge $MaxExternalRelations) {
                $externalRelationsSkippedByLimit++
                continue
            }

            $endpointKeys = @(
                Get-ObjectKey -Type $relation.fromable_type -Id $relation.fromable_id
                Get-ObjectKey -Type $relation.toable_type -Id $relation.toable_id
            )

            $newNodeCount = 0
            foreach ($endpointKey in $endpointKeys) {
                if (-not $projectedNodeKeys.Contains($endpointKey)) { $newNodeCount++ }
            }

            if ($MaxRelationMapNodes -gt 0 -and ($projectedNodeKeys.Count + $newNodeCount) -gt $MaxRelationMapNodes) {
                $externalRelationsSkippedByLimit++
                continue
            }

            $includedExternalRelations.Add($relation)
            foreach ($endpointKey in $endpointKeys) {
                $null = $projectedNodeKeys.Add($endpointKey)
            }
        }

        if ($externalRelationsSkippedByLimit -gt 0) {
            $limitReasons = [System.Collections.Generic.List[string]]::new()
            if ($MaxExternalRelations -gt 0) { $limitReasons.Add("$MaxExternalRelations external relation(s)") }
            if ($MaxRelationMapNodes -gt 0) { $limitReasons.Add("$MaxRelationMapNodes total node(s)") }
            Write-Host "Skipping $externalRelationsSkippedByLimit external relation(s) for $($Company.name) to keep the map under $($limitReasons -join ' and ')." -ForegroundColor DarkYellow
        }
    }

    $graphRelations = @(
        $scopedRelations
        $includedExternalRelations
    )

    $nodes = @{}
    foreach ($relation in $graphRelations) {
        $endpoints = @(
            @{ Type = $relation.fromable_type; Id = $relation.fromable_id },
            @{ Type = $relation.toable_type; Id = $relation.toable_id }
        )

        foreach ($endpoint in $endpoints) {
            $nodeKey = Get-ObjectKey -Type $endpoint.Type -Id $endpoint.Id
            if (-not $nodes.ContainsKey($nodeKey)) {
                $nodes[$nodeKey] = Resolve-RelationEndpointNode `
                    -Type $endpoint.Type `
                    -Id $endpoint.Id `
                    -ObjectByKey $objectByKey `
                    -LayoutById $LayoutById `
                    -CompanyById $CompanyById `
                    -ScopeCompanyId ([int]$Company.id)
            }
        }
    }

    foreach ($node in @($nodes.Values | Where-Object { $_.Type -ieq 'Asset' })) {
        if ($assetPasswordMap.ContainsKey($node.Key)) {
            $node.EmbeddedPasswords = @($assetPasswordMap[$node.Key])
        }
    }

    [PSCustomObject]@{
        Company   = $Company
        Assets    = $assets
        Articles  = $articles
        Relations = $graphRelations
        Nodes     = @($nodes.Values)
        ScopedRelationCount   = $scopedRelations.Count
        ExternalRelationCount = $includedExternalRelations.Count
        ExternalRelationsSkipped = $externalRelationsSkippedByThreshold + $externalRelationsSkippedByLimit
        ExternalRelationsSkippedByThreshold = $externalRelationsSkippedByThreshold
        ExternalRelationsSkippedByLimit = $externalRelationsSkippedByLimit
        OutOfScopeRelationsSkipped = $outOfScopeRelationsSkipped
    }
}

function Get-RelationMapSeriationOrder {
    # Assigns each unit (a card, or a node) a 1-D "pseudo-distance" coordinate
    # that minimizes the weighted sum of squared line lengths between connected
    # units: sum over edges of w_ij * (x_i - x_j)^2. The minimizer (subject to
    # being non-constant) is the Fiedler vector -- the eigenvector of the
    # second-smallest eigenvalue of the weighted graph Laplacian L = D - W.
    # Exact Minimum Linear Arrangement is NP-hard; this spectral relaxation is
    # the standard, well-behaved approximation and, unlike the mean-barycenter
    # heuristic, does not oscillate.
    #
    # We avoid needing a matrix library by using shifted power iteration:
    # iterating y = (c*I - L) x amplifies the smallest eigenvalues of L, and
    # subtracting the mean each step deflates the trivial all-ones eigenvector
    # (eigenvalue 0), so the iteration converges to the Fiedler vector. Units
    # are then ranked by their coordinate, placing strongly connected units
    # adjacent so relationship lines stay short and untangled.
    param(
        [Parameter(Mandatory)][string[]]$UnitKeys,
        [Parameter(Mandatory)][hashtable]$Adjacency,
        [int]$Iterations = 200
    )

    $n = $UnitKeys.Count
    if ($n -le 2) {
        $trivial = @{}
        for ($i = 0; $i -lt $n; $i++) { $trivial[$UnitKeys[$i]] = [double]$i }
        return $trivial
    }

    $index = @{}
    for ($i = 0; $i -lt $n; $i++) { $index[$UnitKeys[$i]] = $i }

    $degree = New-Object 'double[]' $n
    $hasEdge = $false
    foreach ($unit in $UnitKeys) {
        $neighbors = $Adjacency[$unit]
        if ($null -eq $neighbors) { continue }
        $d = 0.0
        foreach ($neighbor in $neighbors.Keys) {
            if (-not $index.ContainsKey($neighbor)) { continue }
            $d += [double]$neighbors[$neighbor]
            $hasEdge = $true
        }
        $degree[$index[$unit]] = $d
    }

    if (-not $hasEdge) {
        $order = @{}
        for ($i = 0; $i -lt $n; $i++) { $order[$UnitKeys[$i]] = [double]$i }
        return $order
    }

    $maxDegree = 0.0
    for ($i = 0; $i -lt $n; $i++) { if ($degree[$i] -gt $maxDegree) { $maxDegree = $degree[$i] } }
    $shift = (2.0 * $maxDegree) + 1.0

    # Deterministic, non-constant starting vector so results are reproducible.
    $x = New-Object 'double[]' $n
    for ($i = 0; $i -lt $n; $i++) { $x[$i] = [math]::Sin($i + 1.0) }

    for ($iter = 0; $iter -lt $Iterations; $iter++) {
        $mean = 0.0
        for ($i = 0; $i -lt $n; $i++) { $mean += $x[$i] }
        $mean /= $n
        for ($i = 0; $i -lt $n; $i++) { $x[$i] -= $mean }

        # y = (shift*I - L) x = (shift - degree_i) * x_i + sum_j W_ij * x_j
        $y = New-Object 'double[]' $n
        for ($i = 0; $i -lt $n; $i++) { $y[$i] = ($shift - $degree[$i]) * $x[$i] }
        foreach ($unit in $UnitKeys) {
            $neighbors = $Adjacency[$unit]
            if ($null -eq $neighbors) { continue }
            $ui = $index[$unit]
            foreach ($neighbor in $neighbors.Keys) {
                if (-not $index.ContainsKey($neighbor)) { continue }
                $y[$ui] += [double]$neighbors[$neighbor] * $x[$index[$neighbor]]
            }
        }

        $norm = 0.0
        for ($i = 0; $i -lt $n; $i++) { $norm += $y[$i] * $y[$i] }
        $norm = [math]::Sqrt($norm)
        if ($norm -le 1e-12) { break }
        for ($i = 0; $i -lt $n; $i++) { $x[$i] = $y[$i] / $norm }
    }

    $positions = @{}
    $sortedKeys = @($UnitKeys | Sort-Object @{ Expression = { $x[$index[$_]] } }, @{ Expression = { $index[$_] } })
    for ($i = 0; $i -lt $sortedKeys.Count; $i++) { $positions[$sortedKeys[$i]] = [double]$i }
    return $positions
}

function New-MermaidRelationMap {
    param(
        [Parameter(Mandatory)][object]$Graph,
        [Parameter(Mandatory)][string]$Direction,
        [int]$EdgeStrokeWidth = 3,
        [int]$MaxEmbeddedAssetPasswords = 8,
        [string]$HuduBaseURL,
        [bool]$GroupLargeMapsByConnectedSection = $true,
        [int]$LargeMapSectionThreshold = 40,
        [int]$MinConnectedSectionSize = 1,
        [bool]$OptimizeLayoutOrdering = $true,
        [string]$MapBackgroundColor = '#f7f9fc',
        [string]$InCompanyNodeColor = '#e9f5ff',
        [string]$OutsideCompanyNodeColor = '#fff4e5'
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("%% Generated by Relation-Charts.ps1 $RelationMapGeneratorVersion")
    if (-not [string]::IsNullOrWhiteSpace($MapBackgroundColor)) {
        $safeBackgroundColor = ConvertTo-MermaidQuotedText -Value $MapBackgroundColor
        $lines.Add("%%{init: {`"theme`": `"base`", `"themeVariables`": {`"background`": `"$safeBackgroundColor`"}} }}%%")
    }
    $lines.Add("flowchart $Direction")

    if (-not $Graph.Nodes -or -not $Graph.Relations) {
        $lines.Add("    empty[`"No Hudu relations found for $(ConvertTo-MermaidLabel -Value $Graph.Company.name)`"]")
        return ($lines -join "`n")
    }

    $useConnectedSections = (
        $GroupLargeMapsByConnectedSection -eq $true -and
        $LargeMapSectionThreshold -gt 0 -and
        (
            @($Graph.Nodes).Count -ge $LargeMapSectionThreshold -or
            @($Graph.Relations).Count -ge $LargeMapSectionThreshold
        )
    )
    $sectionInfo = if ($useConnectedSections) {
        Get-RelationMapConnectedSections -Nodes @($Graph.Nodes) -Relations @($Graph.Relations) -MinSectionSize $MinConnectedSectionSize
    } else {
        $null
    }

    # Nodes are grouped by their "parent card": the object type, and for assets
    # the asset layout (both already captured in $node.Category, e.g.
    # "Asset: Firewall" / "Article" / "Website"). Scope (scoped / external /
    # global) is deliberately excluded from the grouping key so that, for
    # example, every Firewall lands in the same layout group regardless of which
    # company owns it. Scope is still conveyed through node color and the
    # company name appended to external node labels, so we drop the old scope
    # prefixes from titles to keep the map readable. For large maps we still
    # split into connected-component sections to keep the web untangled, but
    # within each section the grouping remains type/layout based.
    $groupedNodes = foreach ($node in @($Graph.Nodes)) {
        $section = $null
        if (
            $useConnectedSections -and
            $null -ne $sectionInfo -and
            $sectionInfo.SectionByNodeKey.ContainsKey($node.Key)
        ) {
            $section = $sectionInfo.SectionByNodeKey[$node.Key]
        }

        $sectionIndex = if ($null -ne $section -and $sectionInfo.Count -gt 1) { [int]$section.Index } else { 0 }
        $title = if ($sectionIndex -gt 0) { "Section $sectionIndex - $($node.Category)" } else { $node.Category }

        [PSCustomObject]@{
            Node         = $node
            GroupKey     = "$sectionIndex|$($node.Category)"
            SortKey      = ('{0:D4}|{1}' -f $sectionIndex, $node.Category)
            SectionIndex = $sectionIndex
            Title        = $title
        }
    }

    $groupKeyByNodeKey = @{}
    foreach ($groupedNode in $groupedNodes) {
        $groupKeyByNodeKey[$groupedNode.Node.Key] = $groupedNode.GroupKey
    }

    # Start from a stable, human-friendly order (section, then category name).
    $groups = @($groupedNodes | Sort-Object SortKey, { $_.Node.Name }, { $_.Node.Id } | Group-Object -Property GroupKey)

    # Pseudo-distance ordering: relationship lines are shortest and least
    # tangled when strongly connected cards sit next to each other. We weight
    # each pair of cards by the number of relations crossing between them and
    # run a barycenter pass to seriate the cards, then emit them (and the nodes
    # inside them) in that order so Mermaid/dagre lays them out accordingly.
    # Sections stay contiguous because components never share cross-edges.
    $nodeBary = @{}
    if ($OptimizeLayoutOrdering -eq $true -and $groups.Count -gt 1) {
        $initialGroupKeys = @($groups | ForEach-Object { $_.Name })

        $groupAdjacency = @{}
        foreach ($groupKey in $initialGroupKeys) { $groupAdjacency[$groupKey] = @{} }

        foreach ($relation in $Graph.Relations) {
            $fromKey = Get-ObjectKey -Type $relation.fromable_type -Id $relation.fromable_id
            $toKey = Get-ObjectKey -Type $relation.toable_type -Id $relation.toable_id
            if (-not $groupKeyByNodeKey.ContainsKey($fromKey) -or -not $groupKeyByNodeKey.ContainsKey($toKey)) { continue }

            $fromGroup = $groupKeyByNodeKey[$fromKey]
            $toGroup = $groupKeyByNodeKey[$toKey]
            if ($fromGroup -eq $toGroup) { continue }

            if (-not $groupAdjacency[$fromGroup].ContainsKey($toGroup)) { $groupAdjacency[$fromGroup][$toGroup] = 0 }
            if (-not $groupAdjacency[$toGroup].ContainsKey($fromGroup)) { $groupAdjacency[$toGroup][$fromGroup] = 0 }
            $groupAdjacency[$fromGroup][$toGroup]++
            $groupAdjacency[$toGroup][$fromGroup]++
        }

        $groupPos = Get-RelationMapSeriationOrder -UnitKeys $initialGroupKeys -Adjacency $groupAdjacency

        # Nudge each node toward the average position of the cards it links to,
        # so nodes line up along the edge of their card facing their neighbors.
        $nodeNeighborGroupPos = @{}
        foreach ($relation in $Graph.Relations) {
            $fromKey = Get-ObjectKey -Type $relation.fromable_type -Id $relation.fromable_id
            $toKey = Get-ObjectKey -Type $relation.toable_type -Id $relation.toable_id
            if (-not $groupKeyByNodeKey.ContainsKey($fromKey) -or -not $groupKeyByNodeKey.ContainsKey($toKey)) { continue }

            foreach ($pair in @(, @($fromKey, $toKey)) + @(, @($toKey, $fromKey))) {
                $selfKey = $pair[0]
                $otherKey = $pair[1]
                if (-not $nodeNeighborGroupPos.ContainsKey($selfKey)) {
                    $nodeNeighborGroupPos[$selfKey] = [System.Collections.Generic.List[double]]::new()
                }
                $nodeNeighborGroupPos[$selfKey].Add([double]$groupPos[$groupKeyByNodeKey[$otherKey]])
            }
        }

        foreach ($nodeKey in $nodeNeighborGroupPos.Keys) {
            $values = $nodeNeighborGroupPos[$nodeKey]
            if ($values.Count -eq 0) { continue }
            $sum = 0.0
            foreach ($value in $values) { $sum += $value }
            $nodeBary[$nodeKey] = $sum / $values.Count
        }

        $groups = @($groups | Sort-Object `
            @{ Expression = { [int]($_.Group[0].SectionIndex) } }, `
            @{ Expression = { $groupPos[$_.Name] } }, `
            @{ Expression = { $_.Group[0].Title } })
    }

    foreach ($group in $groups) {
        $first = $group.Group | Select-Object -First 1
        $title = $first.Title
        $firstNode = $first.Node

        $subgraphId = ConvertTo-MermaidId -Value "group_$($first.SectionIndex)_$($firstNode.Category)"
        $lines.Add("    subgraph $subgraphId[`"$(ConvertTo-MermaidLabel -Value $title)`"]")

        $orderedGroupNodes = if ($nodeBary.Count -gt 0) {
            @($group.Group | Sort-Object `
                @{ Expression = { if ($nodeBary.ContainsKey($_.Node.Key)) { $nodeBary[$_.Node.Key] } else { [double]::MaxValue } } }, `
                @{ Expression = { $_.Node.Name } }, `
                @{ Expression = { $_.Node.Id } })
        } else {
            @($group.Group | Sort-Object { $_.Node.Name }, { $_.Node.Id })
        }

        foreach ($groupedNode in $orderedGroupNodes) {
            $node = $groupedNode.Node
            $labelParts = @($node.Name)
            if ($node.Type -ieq 'Asset' -and -not [string]::IsNullOrWhiteSpace($node.AssetLayout)) {
                $labelParts += $node.AssetLayout
            } elseif ($node.Type -ine 'Asset') {
                $labelParts += $node.Type
            }

            if ($node.Type -ieq 'Asset' -and @($node.EmbeddedPasswords).Count -gt 0) {
                $passwordNames = @(
                    $node.EmbeddedPasswords |
                        Select-Object -First $MaxEmbeddedAssetPasswords |
                        ForEach-Object {
                            $passwordName = Get-HuduObjectName -Object $_
                            if ([string]::IsNullOrWhiteSpace($passwordName)) {
                                $passwordName = "Password $(Get-HuduPropertyValue -Object $_ -Name 'id')"
                            }

                            "- $passwordName"
                        }
                )

                $remainingPasswords = @($node.EmbeddedPasswords).Count - $passwordNames.Count
                $labelParts += 'Passwords'
                $labelParts += $passwordNames
                if ($remainingPasswords -gt 0) {
                    $labelParts += "+ $remainingPasswords more"
                }
            }

            if ($node.Scope -eq 'External' -and -not [string]::IsNullOrWhiteSpace($node.CompanyName)) {
                $labelParts += $node.CompanyName
            }

            $shapeOpen = if ($node.Type -ieq 'Article') { '[[' } else { '[' }
            $shapeClose = if ($node.Type -ieq 'Article') { ']]' } else { ']' }
            $label = ConvertTo-MermaidLabel -Value ($labelParts -join '<br/>')
            $lines.Add("        $($node.MermaidId)$shapeOpen`"$label`"$shapeClose")
        }

        $lines.Add("    end")
    }

    $nodeByKey = @{}
    foreach ($node in $Graph.Nodes) {
        $nodeByKey[$node.Key] = $node
    }

    $edgeRecords = [System.Collections.Generic.List[object]]::new()
    $edgeByPair = @{}
    foreach ($relation in @($Graph.Relations | Sort-Object id)) {
        $fromKey = Get-ObjectKey -Type $relation.fromable_type -Id $relation.fromable_id
        $toKey = Get-ObjectKey -Type $relation.toable_type -Id $relation.toable_id
        if (-not $nodeByKey.ContainsKey($fromKey) -or -not $nodeByKey.ContainsKey($toKey)) { continue }

        $pairParts = @($fromKey, $toKey) | Sort-Object
        $pairKey = "$($pairParts[0])<>$($pairParts[1])"
        $directionKey = "$fromKey>$toKey"

        if (-not $edgeByPair.ContainsKey($pairKey)) {
            $edge = [PSCustomObject]@{
                PairKey       = $pairKey
                FirstFromKey  = $fromKey
                FirstToKey    = $toKey
                DirectionKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }

            $edgeByPair[$pairKey] = $edge
            $edgeRecords.Add($edge)
        }

        $null = $edgeByPair[$pairKey].DirectionKeys.Add($directionKey)
    }

    foreach ($edge in $edgeRecords) {
        $connector = if ($edge.DirectionKeys.Count -gt 1) { '<-->' } else { '-->' }
        $lines.Add("    $($nodeByKey[$edge.FirstFromKey].MermaidId) $connector $($nodeByKey[$edge.FirstToKey].MermaidId)")
    }

    if ($EdgeStrokeWidth -gt 1 -and $edgeRecords.Count -gt 0) {
        $lines.Add("    linkStyle default stroke-width:${EdgeStrokeWidth}px;")
    }

    $lines.Add("    classDef scopeScoped fill:$InCompanyNodeColor,stroke:#3478bd,color:#102235;")
    $lines.Add("    classDef scopeExternal fill:$OutsideCompanyNodeColor,stroke:#d97706,color:#3b2200;")
    $lines.Add("    classDef scopeGlobal fill:#eef8ed,stroke:#39833b,color:#0f2f12;")

    $nodeIdsByClass = @{
        scopeScoped = [System.Collections.Generic.List[string]]::new()
        scopeExternal = [System.Collections.Generic.List[string]]::new()
        scopeGlobal = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($node in $Graph.Nodes) {
        $className = switch ($node.Scope) {
            'External' { 'scopeExternal' }
            'Global' { 'scopeGlobal' }
            default { 'scopeScoped' }
        }
        $nodeIdsByClass[$className].Add($node.MermaidId)
    }

    foreach ($className in @('scopeScoped', 'scopeExternal', 'scopeGlobal')) {
        $nodeIds = @($nodeIdsByClass[$className] | Sort-Object)
        for ($i = 0; $i -lt $nodeIds.Count; $i += 50) {
            $endIndex = [Math]::Min($i + 49, $nodeIds.Count - 1)
            $chunk = @($nodeIds[$i..$endIndex])
            $lines.Add("    class $($chunk -join ',') $className;")
        }
    }

    foreach ($node in @($Graph.Nodes | Sort-Object MermaidId)) {
        $url = Get-HuduObjectUrl -Object $node.Object -BaseUrl $HuduBaseURL
        if ([string]::IsNullOrWhiteSpace($url)) { continue }

        $safeUrl = ConvertTo-MermaidQuotedText -Value $url
        $lines.Add("    click $($node.MermaidId) `"$safeUrl`"")
    }

    return ($lines -join "`n")
}

function New-RelationMapArticleHtml {
    param(
        [Parameter(Mandatory)][object]$Graph,
        [Parameter(Mandatory)][string]$Mermaid,
        [bool]$GroupLargeMapsByConnectedSection = $true,
        [int]$LargeMapSectionThreshold = 40
    )

    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
    $source = ConvertTo-HtmlText -Value $Mermaid
    $nodeCount = @($Graph.Nodes).Count
    $relationCount = @($Graph.Relations).Count
    $summaryParts = [System.Collections.Generic.List[string]]::new()
    $summaryParts.Add("Generated $generated by Relation-Charts.ps1 $RelationMapGeneratorVersion.")
    $summaryParts.Add("Shows $nodeCount related object node$(if ($nodeCount -eq 1) { '' } else { 's' }) and $relationCount relation record$(if ($relationCount -eq 1) { '' } else { 's' }) touching this company's scoped objects.")

    if ((Get-HuduPropertyValue -Object $Graph -Name 'ExternalRelationsSkippedByThreshold' -DefaultValue 0) -gt 0) {
        $summaryParts.Add("External related nodes were skipped because this company already has $($Graph.ScopedRelationCount) in-company relation records.")
    }

    if ((Get-HuduPropertyValue -Object $Graph -Name 'ExternalRelationCount' -DefaultValue 0) -gt 0) {
        $summaryParts.Add("Includes $($Graph.ExternalRelationCount) external relation record$(if ($Graph.ExternalRelationCount -eq 1) { '' } else { 's' }).")
    }

    if ((Get-HuduPropertyValue -Object $Graph -Name 'ExternalRelationsSkippedByLimit' -DefaultValue 0) -gt 0) {
        $summaryParts.Add("Skipped $($Graph.ExternalRelationsSkippedByLimit) external relation record$(if ($Graph.ExternalRelationsSkippedByLimit -eq 1) { '' } else { 's' }) to keep this large map renderable.")
    }

    if ((Get-HuduPropertyValue -Object $Graph -Name 'OutOfScopeRelationsSkipped' -DefaultValue 0) -gt 0) {
        $summaryParts.Add("Skipped $($Graph.OutOfScopeRelationsSkipped) relation record$(if ($Graph.OutOfScopeRelationsSkipped -eq 1) { '' } else { 's' }) involving object types outside ScopeObjectTypes.")
    }

    if (
        $GroupLargeMapsByConnectedSection -eq $true -and
        $LargeMapSectionThreshold -gt 0 -and
        ($nodeCount -ge $LargeMapSectionThreshold -or $relationCount -ge $LargeMapSectionThreshold)
    ) {
        $summaryParts.Add("Large maps are grouped into connected sections to reduce visual crossing while keeping direct relation lines.")
    }

    $summary = ConvertTo-HtmlText -Value ($summaryParts -join ' ')

    @"
<h1>Relation Map - $(ConvertTo-HtmlText -Value $Graph.Company.name)</h1>
<p>$summary</p>
<pre class="mermaid">
$source
</pre>
<details>
  <summary>Mermaid source</summary>
  <pre>$source</pre>
</details>
"@
}

function New-RelationMapStandaloneHtml {
    param(
        [Parameter(Mandatory)][object]$Graph,
        [Parameter(Mandatory)][string]$ArticleHtml,
        [string]$MapBackgroundColor = '#f7f9fc'
    )

    $title = ConvertTo-HtmlText -Value "Relation Map - $($Graph.Company.name)"

    @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <style>
    body { margin: 24px; font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #172033; background: $MapBackgroundColor; }
    main { max-width: 1400px; margin: 0 auto; }
    pre { overflow: auto; background: $MapBackgroundColor; border: 1px solid #d7deea; border-radius: 8px; padding: 16px; }
    details { margin-top: 24px; }
  </style>
</head>
<body>
  <main>
    $ArticleHtml
  </main>
  <script type="module">
    import mermaid from "https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.esm.min.mjs";
    mermaid.initialize({ startOnLoad: true, securityLevel: "loose" });
  </script>
</body>
</html>
"@
}

function Get-SafeFileName {
    param([Parameter(Mandatory)][string]$Name)

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = -join ($Name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '_' } else { $_ }
    })

    return ($safe -replace '\s+', ' ').Trim()
}

function Publish-RelationMapArticle {
    param(
        [Parameter(Mandatory)][object]$Company,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Content
    )

    $existing = Get-HuduArticles -CompanyId $Company.id -Name $Name | Select-Object -First 1
    $request = @{
        Name      = $Name
        Content   = $Content
        CompanyId = $Company.id
    }

    if ($existing) {
        $normalizedExisting = Get-NormalizedHuduObject -Object $existing
        $request.Id = $normalizedExisting.id
        Set-HuduArticle @request | Out-Null
        Write-Host "Updated Hudu article '$Name' for $($Company.name)." -ForegroundColor Green
    } else {
        New-HuduArticle @request | Out-Null
        Write-Host "Created Hudu article '$Name' for $($Company.name)." -ForegroundColor Green
    }
}

Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance -HuduAPIKey $huduapikey -HuduBaseURL $HuduBaseURL; Get-HuduVersionCompatible;

New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
[string[]]$AllLobjectTypes = @('Asset', 'Article', 'AssetPassword', 'Procedure', 'Website', 'Company', 'Network', 'RackStorage', 'Vlan', 'VlanZone', 'IpAddress')
$SkippedObjectTypes = @($AllLobjectTypes | Where-Object { $_ -notin $ScopeObjectTypes })

Write-Host "Loading companies" -ForegroundColor Cyan; $companies = @(Get-HuduCompanies);
Write-Host "Loading asset layouts" -ForegroundColor Cyan; $layouts = @(Get-HuduAssetLayouts);
Write-Host "Loading loading relations for relating to $($ScopeObjectTypes -join ', ')..." -ForegroundColor Cyan; $relations = @(Get-HuduRelations);
Write-Host "$(if ($SkippedObjectTypes.count -gt 0) {"Skipping Object Types: $($SkippedObjectTypes -join ', ')"} else {'No skipped object types'})" -ForegroundColor darkcyan


$companyById = @{}
foreach ($company in $companies) {
    $companyById[[string]$company.id] = $company
}

$layoutById = @{}
foreach ($layout in $layouts) {
    $layoutById[[string]$layout.id] = $layout
}

$selectedCompanies = @($companies)


if (-not $selectedCompanies) {
    throw "No companies matched the requested filters."
}

Write-Host "Creating relation maps for $($selectedCompanies.Count) compan$(if ($selectedCompanies.Count -eq 1) { 'y' } else { 'ies' })." -ForegroundColor Cyan

$results = foreach ($company in $selectedCompanies) {
    $graph = Get-CompanyRelationGraph `
        -Company $company `
        -Relations $relations `
        -LayoutById $layoutById `
        -CompanyById $companyById `
        -ScopeObjectTypes $ScopeObjectTypes `
        -IncludeArchived:$IncludeArchivedAssets `
        -IncludeGlobalKb:$IncludeGlobalArticles `
        -OnlyIncludeExternalRelationsWhenSparse $OnlyIncludeExternalRelationsWhenSparse `
        -ExternalRelationThreshold $ExternalRelationThreshold `
        -MaxExternalRelations $MaxExternalRelations `
        -MaxRelationMapNodes $MaxRelationMapNodes `
        -EmbedAssetPasswordsInAssetNodes $EmbedAssetPasswordsInAssetNodes `
        -HideEmbeddedAssetPasswordRelationNodes $HideEmbeddedAssetPasswordRelationNodes

    if (@($graph.Relations).Count -eq 0) {
        Write-Host "Skipping $($company.name); no relations found for scoped objects." -ForegroundColor DarkYellow
        continue
    }

    $mermaid = New-MermaidRelationMap `
        -Graph $graph `
        -Direction $Direction `
        -EdgeStrokeWidth $EdgeStrokeWidth `
        -MaxEmbeddedAssetPasswords $MaxEmbeddedAssetPasswords `
        -HuduBaseURL $HuduBaseURL `
        -GroupLargeMapsByConnectedSection $GroupLargeMapsByConnectedSection `
        -LargeMapSectionThreshold $LargeMapSectionThreshold `
        -MinConnectedSectionSize $MinConnectedSectionSize `
        -OptimizeLayoutOrdering $OptimizeLayoutOrdering `
        -MapBackgroundColor $MapBackgroundColor `
        -InCompanyNodeColor $InCompanyNodeColor `
        -OutsideCompanyNodeColor $OutsideCompanyNodeColor
    $articleHtml = New-RelationMapArticleHtml `
        -Graph $graph `
        -Mermaid $mermaid `
        -GroupLargeMapsByConnectedSection $GroupLargeMapsByConnectedSection `
        -LargeMapSectionThreshold $LargeMapSectionThreshold
        $standaloneHtml = New-RelationMapStandaloneHtml -Graph $graph -ArticleHtml $articleHtml -MapBackgroundColor $MapBackgroundColor
    $fileBase = Get-SafeFileName -Name "$($company.name)-relation-map"
    $mmdPath = Join-Path $OutputDirectory "$fileBase.mmd"
    $htmlPath = Join-Path $OutputDirectory "$fileBase.html"

    $mermaid | Set-Content -Path $mmdPath -Encoding UTF8
    $standaloneHtml | Set-Content -Path $htmlPath -Encoding UTF8

    if ($PublishArticles -eq $true) {
        Publish-RelationMapArticle -Company $company -Name "$ArticleNamePrefix$($company.name)" -Content $articleHtml
    }

    [PSCustomObject]@{
        CompanyId     = $company.id
        CompanyName   = $company.name
        Nodes         = @($graph.Nodes).Count
        Relations     = @($graph.Relations).Count
        ScopedRelations = $graph.ScopedRelationCount
        ExternalRelations = $graph.ExternalRelationCount
        ExternalSkipped = $graph.ExternalRelationsSkipped
        OutOfScopeSkipped = $graph.OutOfScopeRelationsSkipped
        MermaidPath   = $mmdPath
        HtmlPath      = $htmlPath
        ArticleName   = "$ArticleNamePrefix$($company.name)"
        ArticleSynced = $PublishArticles
    }
}
Set-StrictMode -Off

if ($true -eq $PublishArticles){
    try{remove-item -path "$OutputDirectory\*" -force -ErrorAction SilentlyContinue} catch {}
}
$HuduAPIKey = $null

$results
