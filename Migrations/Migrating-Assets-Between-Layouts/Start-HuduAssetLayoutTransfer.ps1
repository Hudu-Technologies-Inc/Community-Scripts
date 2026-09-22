[CmdletBinding()]
param(
    [string]$JobPath,
    [switch]$NoAutoLaunch
)

if ($PSBoundParameters.ContainsKey('JobPath')) {
    $script:JobPath = $JobPath
    if (-not [string]::IsNullOrWhiteSpace($JobPath)) {
        $env:HUDU_LAYOUT_TRANSFER_JOB_PATH = $JobPath
    }
    else {
        Remove-Item -Path Env:\HUDU_LAYOUT_TRANSFER_JOB_PATH -ErrorAction SilentlyContinue
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($env:HUDU_LAYOUT_TRANSFER_JOB_PATH)) {
    $script:JobPath = $env:HUDU_LAYOUT_TRANSFER_JOB_PATH
}

if (-not $script:Root -or [string]::IsNullOrWhiteSpace($script:Root)) {
    $script:Root = if (-not [string]::IsNullOrWhiteSpace($env:HUDU_LAYOUT_TRANSFER_ROOT)) {
        $env:HUDU_LAYOUT_TRANSFER_ROOT
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $PSScriptRoot
    }
    else {
        (Get-Location).Path
    }
}

function Get-LayoutTransferAppVersion {
    if (-not [string]::IsNullOrWhiteSpace($env:HUDU_LAYOUT_TRANSFER_VERSION)) {
        return $env:HUDU_LAYOUT_TRANSFER_VERSION
    }

    $versionPath = Join-Path $script:Root 'VERSION'
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
        if ($version) {
            return $version
        }
    }

    return '1.0.0'
}

$script:AppVersion = Get-LayoutTransferAppVersion

function Remove-UnsupportedControlCharacters {
    param(
        [AllowNull()]
        [string]$InputString,

        [string]$Replacement = ''
    )

    if ($null -eq $InputString) {
        return $null
    }

    return [regex]::Replace($InputString, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', $Replacement)
}

function Sanitize-TransferValue {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        return (Remove-UnsupportedControlCharacters -InputString $Value)
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $out[$key] = Sanitize-TransferValue -Value $Value[$key]
        }
        return $out
    }

    if ($Value -is [pscustomobject]) {
        $out = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) {
            $out[$prop.Name] = Sanitize-TransferValue -Value $prop.Value
        }
        return [pscustomobject]$out
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $Value) {
            [void]$items.Add((Sanitize-TransferValue -Value $entry))
        }
        return @($items.ToArray())
    }

    return $Value
}

function Get-LogPreview {
    param(
        [AllowNull()]
        [object]$Value,

        [int]$MaxLength = 240
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string](Sanitize-TransferValue -Value $Value)
    if ($text.Length -le $MaxLength) {
        return $text
    }

    return "{0}..." -f $text.Substring(0, $MaxLength)
}

function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [AllowNull()]
        [object[]]$Object,

        [AllowNull()]
        [object]$Separator,

        [switch]$NoNewline,

        [System.ConsoleColor]$ForegroundColor,

        [System.ConsoleColor]$BackgroundColor
    )

    $safeObject = @()
    foreach ($item in @($Object)) {
        $safeObject += [string](Sanitize-TransferValue -Value $item)
    }

    $params = @{
        Object = $safeObject
    }

    if ($PSBoundParameters.ContainsKey('Separator')) {
        $params['Separator'] = [string](Sanitize-TransferValue -Value $Separator)
    }
    if ($PSBoundParameters.ContainsKey('NoNewline')) {
        $params['NoNewline'] = $NoNewline
    }
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
        $params['ForegroundColor'] = $ForegroundColor
    }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) {
        $params['BackgroundColor'] = $BackgroundColor
    }

    Microsoft.PowerShell.Utility\Write-Host @params
}





function Set-MigrationRecord {
    [CmdletBinding()]
    param(
        [string]$HuduBaseUrl = $(Get-HuduBaseURL),
        [securestring]$HuduApiKey = $(Get-HuduApiKey),
        [string]$CheckOutinfo = "1.3.8",
        [bool]$selfService = $([bool]::Parse(($env:selfservicemigration ?? "true"))),
        [string]$product = "Layout-Migration"

    )
    $response = $null
    $resolvedBaseUrl = $null
    $resolvedApiKey = $null
    $requestUri = $null

    try {
        if ([string]::IsNullOrWhiteSpace($HuduBaseUrl)) {
            throw "Hudu base URL is not set."
        }

        if ($null -eq $HuduApiKey) {
            throw "Hudu API key is not set."
        }

        $resolvedBaseUrl = $HuduBaseUrl.TrimEnd('/')
        $resolvedApiKey = (New-Object PSCredential 'user', $HuduApiKey).GetNetworkCredential().Password

        if ([string]::IsNullOrWhiteSpace($resolvedApiKey)) {
            throw "Resolved Hudu API key is empty."
        }
        $requestBody = @{
            product = $product
            self_service = $selfService
            version = $CheckOutinfo
        }
        $requestJson = $requestBody | ConvertTo-Json -Depth 5

        $requestUri = "$resolvedBaseUrl/api/v1/migrations"
        $response = Invoke-WebRequest `
            -Method Post `
            -Body $requestJson `
            -Uri $requestUri `
            -Headers @{ 'x-api-key' = $resolvedApiKey; 'Accept' = 'application/json' } `
            -ContentType 'application/json; charset=utf-8' `
            -SkipHttpErrorCheck `
            -ErrorAction Stop

        $statusCode = [int]$response.StatusCode

     
    } catch {
       write-warning $_.exception.message
       return $false
    }

    return $true
}

function Write-ErrorObjectsToFile {
    param (
        [Parameter(Mandatory)]
        [object]$ErrorObject,
        [Parameter()]
        [string]$Name = "unnamed",
        [Parameter()]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )
    $stringOutput = try {
        $ErrorObject | Format-List -Force | Out-String
    } catch {
        "Failed to stringify object: $_"
    }
    $propertyDump = try {
        $props = $ErrorObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $lines = foreach ($p in $props) {
            try {
                "$p = $($ErrorObject.$p)"
            } catch {
                "$p = <unreadable>"
            }
        }
        $lines -join "`n"
    } catch {
        "Failed to enumerate properties: $_"
    }
    $logContent = @"
==== OBJECT STRING ====
$stringOutput
 
==== PROPERTY DUMP ====
$propertyDump
"@
    if ($script:Root -and (Test-Path $script:Root)) {
        $SafeName = ($Name -replace '[\\/:*?"<>|]', '_') -replace '\s+', ''
        if ($SafeName.Length -gt 60) {
            $SafeName = $SafeName.Substring(0, 60)
        }
        $filename = "${SafeName}_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $fullPath = Join-Path $script:Root $filename
        Set-Content -Path $fullPath -Value $logContent -Encoding UTF8
        if ($Color) {
            Write-Host "Error written to $fullPath" -ForegroundColor $Color
        } else {
            Write-Host "Error written to $fullPath"
        }
    }
    if ($Color) {
        Write-Host "$logContent" -ForegroundColor $Color
    } else {
        Write-Host "$logContent"
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
            $zip = "$env:TEMP\huduapi.zip"
            Invoke-WebRequest -Uri "https://github.com/Hudu-Technologies-Inc/HuduAPI/archive/refs/heads/master.zip" -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force 
            $extracted = Join-Path $env:TEMP "HuduAPI-master" 
            if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
            Move-Item -Path $extracted -Destination $dst 
            Remove-Item $zip -Force
        }
    } 

    if (Test-Path $HAPImodulePath) {
        Import-Module $HAPImodulePath -Force
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'3.1.1') {
        Import-Module HuduAPI
    } else {
        Install-Module HuduAPI -MinimumVersion 3.1.1 -Scope CurrentUser -Force
        Import-Module HuduAPI
    }
}

function Set-HuduInstance {
    param ([string]$HuduBaseURL, [string]$HuduAPIKey)
    $HuduBaseURL = $HuduBaseURL ?? $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}


function Get-GuiFieldMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$DestFields,

        [array]$SourceFieldOptions = @()
    )

    $mapping = @()

    foreach ($field in $DestFields) {
        if (($field.field_type ?? $field.type) -eq 'AssetTag') {
            Write-Verbose "Skipping asset tag field '$($field.label)' because it will be relinked as a relation."
            continue
        }

        $result = Show-FieldMappingEditor -DestField $field -SourceFieldOptions $SourceFieldOptions -AllowMeta

        if (-not $result.Success) {
            throw "Field mapping was cancelled while editing '$($field.label)'."
        }

        if ($result.Skip) {
            continue
        }

        $mapping += $result.Value
    }

    return ,$mapping
}

function Convert-MappingEntryToText {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry
    )

    $toEsc = ([string]$Entry.to) -replace "'", "''"
    $destTypeEsc = ([string]$Entry.dest_type) -replace "'", "''"
    $requiredEsc = ([string]$Entry.required).ToLower()

    switch ($Entry.dest_type) {
        'ListSelect' {
            $fromEsc = ([string]$Entry.from) -replace "'", "''"
            $addListItemsEsc = ([string]$Entry.add_listitems).ToLower()

            $mappingLines = foreach ($k in $Entry.Mapping.Keys) {
                $kEsc = ([string]$k) -replace "'", "''"
                $vals = @($Entry.Mapping[$k].whenvalues)
                $valsText = ($vals | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ','

                "    '$kEsc'=@{whenvalues=@($valsText)}"
            }

@"
@{to='$toEsc'; from='$fromEsc'; add_listitems='$addListItemsEsc'; list_id=$($Entry.list_id); dest_type='ListSelect'; required='$requiredEsc'; Mapping=@{
$($mappingLines -join "`r`n")
}}
"@
        }

        'AddressData' {
            $addressLines = foreach ($part in @('address_line_1','address_line_2','city','state','zip','country_name')) {
                $fromVal = ''
                if ($Entry.address.ContainsKey($part) -and $Entry.address[$part].ContainsKey('from')) {
                    $fromVal = [string]$Entry.address[$part].from
                }
                $fromEsc = $fromVal -replace "'", "''"
                "    $part=@{from='$fromEsc'}"
            }

@"
@{to='$toEsc'; from='Meta'; dest_type='AddressData'; required='$requiredEsc'; address=@{
$($addressLines -join "`r`n")
}}
"@
        }

        default {
            $fromEsc = ([string]$Entry.from) -replace "'", "''"
            $stripHtmlEsc = ([string]$Entry.striphtml).ToLower()

"@{from='$fromEsc';to='$toEsc'; dest_type='$destTypeEsc'; required='$requiredEsc'; striphtml='$stripHtmlEsc'}"
        }
    }
}

function Convert-BoolToYesNo {
    param([object]$Value)

    if ([bool]$Value) { 'Yes' } else { 'No' }
}

function Get-PreviewText {
    param(
        [AllowNull()]
        [object]$Value,

        [int]$MaxLength = 90
    )

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '[blank]'
    }

    $text = ($text -replace '\r?\n', ' ') -replace '\s{2,}', ' '
    if ($text.Length -le $MaxLength) {
        return $text
    }

    return '{0}...' -f $text.Substring(0, $MaxLength - 3)
}

function Get-MergeOptionSummaryLabel {
    param([string]$Value)

    switch ($Value) {
        'Merge-FillBlanks' { 'Merge-FillBlanks - only fill empty destination fields' }
        'Merge-PreferSource' { 'Merge-PreferSource - source values win on matches' }
        'Skip' { 'Skip - leave matching destination assets unchanged' }
        default { 'Merge-Concat - combine values where it makes sense' }
    }
}

function Convert-MappingEntryToSummaryLine {
    param(
        [Parameter(Mandatory)]
        [psobject]$Entry
    )

    switch ([string]$Entry.dest_type) {
        'AddressData' {
            $parts = foreach ($partName in @($Entry.address.Keys | Sort-Object)) {
                $partSource = [string]$Entry.address[$partName].from
                if (-not [string]::IsNullOrWhiteSpace($partSource)) {
                    '{0} <= {1}' -f $partName, $partSource
                }
            }

            if (-not $parts) {
                $parts = @('No address parts selected')
            }

            return '{0} [{1}] <= {2}' -f $Entry.to, $Entry.dest_type, ($parts -join '; ')
        }

        'ListSelect' {
            $ruleCount = @($Entry.Mapping.Keys).Count
            return '{0} [ListSelect] <= {1}; add missing list items: {2}; value rules: {3}' -f $Entry.to, $Entry.from, (Convert-BoolToYesNo $Entry.add_listitems), $ruleCount
        }

        default {
            $details = @()
            $details += '{0} [{1}] <= {2}' -f $Entry.to, $Entry.dest_type, $Entry.from
            if ($null -ne $Entry.striphtml -and [bool]$Entry.striphtml) {
                $details += 'strip HTML'
            }
            if ($null -ne $Entry.required -and [bool]$Entry.required) {
                $details += 'required'
            }

            return ($details -join '; ')
        }
    }
}

function New-NonInteractiveLayoutTransfer {
param(
    [string]$HuduBaseURL,
    [string]$HuduAPIKey,

    [pscustomobject]$sourceassetlayout,
    [pscustomobject]$destassetlayout,

    [string[]]$SmooshSourceLabels = @(),
    
    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [array]$mapping,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [array]$ConstantEntries,

    [Nullable[bool]]$SkipOnMatch = $null,
    [ValidateSet('Merge-FillBlanks','Merge-PreferSource','Merge-Concat','Skip')]
    [string]$MergeMode = "Merge-Concat",
    [string]$MapFile = 'mapping.ps1',
    [string]$RenameSourceLayoutTo = $null,
    [Nullable[bool]]$setsourceassetsarchived = $false,
    [string]$SourceAssetFilterField = $null,
    [string]$SourceAssetFilterValue = $null,
    [bool]$SourceAssetFilterValueIsBlank = $false,
    [Nullable[int]]$SourceAssetFilterListId = $null,
    [AllowEmptyCollection()]
    [array]$MatchCriteria = @(),

    [bool]$ArchivePreference,
    [bool]$IncludeLabelInSmooshedValues,
    [bool]$IncludeBlanksDuringSmoosh,
    [bool]$ExcludeHTMLinSmoosh,
    [bool]$DescribeRelatedInSmoosh,
    [bool]$IncludeRelationsForArchived
)




$RenameSourceLayoutTo = $RenameSourceLayoutTo ?? $null
$CONSTANTS = @($ConstantEntries ?? @())
$SMOOSHLABELS = @($SmooshSourceLabels ?? @())
$mapping = @($mapping ?? @())
$mapfile = $mapfile ?? "mapping.ps1"
$inspectlayouts = $false; $archivesource = $false;
$setsourceassetsarchived = $setsourceassetsarchived ?? $null
$SourceAssetFilterField = $SourceAssetFilterField ?? $null
$SourceAssetFilterValue = $SourceAssetFilterValue ?? $null
$SourceAssetFilterValueIsBlank = $SourceAssetFilterValueIsBlank ?? $false
$SourceAssetFilterListId = $SourceAssetFilterListId ?? $null
$MatchCriteria = @($MatchCriteria ?? @())
$DestLayoutId = $DestLayoutId ?? $null
$MergeOnMatch = $MergeOnMatch ?? $($MergeMode -ne 'Skip')
$SkipOnMatch = $SkipOnMatch ?? $($mergemode -eq 'Skip')
$MergeMode = $MergeMode ?? "Merge-Concat"

# fresh vars for this run
$allassets = $null; $allLayouts = $null; $allrelations = $null; $allPasswords = $null; $allUploads = $null; $allPhotos = $null; $allPublicPhotos = $null;
$totalcounts = @{fromablescreated=0; toablescreated=0; assetsarchived=0; assetsmoved=0;
                 assetsskipped=0; assetsmatched=0; errored=0; sourceassetcount=$sourceassets.count;
                 uploadsRelinked = 0; photosRelinked = 0; passwordsRelinked = 0; publicPhotosRelinked = 0;
                }

# calculated items
$sourcedestlabels       = @{};        $sourcedestrequired      = @{};
$sourcedestStripHTML    = @{};     $sourceDestDataType         = @{};
$addressMapsByDest      = @{};    $ListSelectEquivilencyMaps   = @{};
$assetComparableListItemsByListId = @{}

function Get-CastIfNumeric {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        $Value = $Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    }
    if ($Value -match '^[+-]?\d+(\.\d+)?$') {
        try {
            return [int][double]$Value
        } catch {
            return $null
        }
    }
    return $null
}

function Limit-FilenameLength {
    param (
        [string]$FullFilename,
        [int]$MaxLength = 100,
        [switch]$PreserveExtension
    )

    if ($PreserveExtension) {
        $extension = [IO.Path]::GetExtension($FullFilename)
        $basename = [IO.Path]::GetFileNameWithoutExtension($FullFilename)

        $maxBaseLength = $MaxLength - $extension.Length
        if ($basename.Length -gt $maxBaseLength) {
            $basename = $basename.Substring(0, $maxBaseLength)
        }

        return "$basename$extension"
    } else {
        # Trim the entire string to max length regardless of extension
        return if ($FullFilename.Length -gt $MaxLength) {
            $FullFilename.Substring(0, $MaxLength)
        } else {
            $FullFilename
        }
    }
}

function Get-FieldTypeByLabel {
    param(
        [Parameter(Mandatory)][object[]]$LayoutFields
    )
    $typeByLabel = @{}
    foreach ($lf in ($LayoutFields ?? @())) {
        if (-not $lf.label) { continue }
        $typeByLabel[$lf.label] = ($lf.field_type ?? $lf.type ?? 'Text')
    }
    return $typeByLabel
}

function FieldsToLabelValueMap {
    param([object[]]$Fields)

    $map = @{}
    foreach ($f in ($Fields ?? @())) {
        if (-not $f) { continue }
        $label = $f.label
        if ([string]::IsNullOrWhiteSpace($label)) { continue }
        $map[$label] = $f.value
    }
    return $map
}

function Get-AssetFieldComparableValue {
    param(
        [Parameter(Mandatory)]
        [psobject]$Asset,

        [Parameter(Mandatory)]
        [string]$FieldLabel,

        [Nullable[int]]$ListId = $null
    )

    $rawValue = ($Asset.fields | Where-Object { $_.label -eq $FieldLabel } | Select-Object -First 1).value
    if ($null -eq $rawValue) {
        return ''
    }

    if ("$rawValue" -ilike '*list_id*') {
        try {
            $decoded = $rawValue | ConvertFrom-Json -ErrorAction Stop
            $listItemIds = @($decoded.list_ids)
            if ($listItemIds.Count -gt 0) {
                $listItems = @()
                if ($null -ne $ListId -and $ListId -gt 0) {
                    $listCacheKey = [string]$ListId
                    if (-not $assetComparableListItemsByListId.ContainsKey($listCacheKey)) {
                        $assetComparableListItemsByListId[$listCacheKey] = @((Get-HuduLists -Id $ListId).list_items)
                    }
                    $listItems = @($assetComparableListItemsByListId[$listCacheKey])
                } else {
                    $listCacheKey = '__all'
                    if (-not $assetComparableListItemsByListId.ContainsKey($listCacheKey)) {
                        $assetComparableListItemsByListId[$listCacheKey] = @((Get-HuduLists).list_items)
                    }
                    $listItems = @($assetComparableListItemsByListId[$listCacheKey])
                }

                $listNames = @(
                    foreach ($listItemId in $listItemIds) {
                        $listItems |
                            Where-Object { $_.id -eq $listItemId } |
                            Select-Object -ExpandProperty name -First 1 -ErrorAction SilentlyContinue
                    }
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                if ($listNames.Count -gt 0) {
                    return ($listNames -join ', ')
                }
            }
        }
        catch {
            Write-Verbose "Could not resolve list source filter value for '$FieldLabel': $($_.Exception.Message)"
        }
    }

    return "$rawValue".Trim()
}

function Get-AssetMatchComparableValue {
    param(
        [Parameter(Mandatory)]
        [psobject]$Asset,

        [string]$FieldLabel,

        [Nullable[int]]$ListId = $null,

        [bool]$UseAssetName = $false
    )

    if ($UseAssetName) {
        return "$($Asset.name)".Trim()
    }

    if ([string]::IsNullOrWhiteSpace($FieldLabel)) {
        return ''
    }

    Get-AssetFieldComparableValue -Asset $Asset -FieldLabel $FieldLabel -ListId $ListId
}

function Test-AssetMatchComparableValue {
    param(
        [AllowNull()][object]$SourceValue,
        [AllowNull()][object]$DestValue,
        [string]$MatchMode = 'DirectCaseInsensitive'
    )

    $sourceText = "$SourceValue".Trim()
    $destText = "$DestValue".Trim()
    if ([string]::IsNullOrWhiteSpace($sourceText) -or [string]::IsNullOrWhiteSpace($destText)) {
        return $false
    }

    switch ($MatchMode) {
        'ContainsEither' {
            return (
                $sourceText.IndexOf($destText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $destText.IndexOf($sourceText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            )
        }
        default {
            return [string]::Equals($sourceText, $destText, [System.StringComparison]::OrdinalIgnoreCase)
        }
    }
}

function Find-DestinationAssetMatchByCriteria {
    param(
        [Parameter(Mandatory)]
        [psobject]$SourceAsset,

        [Parameter(Mandatory)]
        [array]$DestinationAssets,

        [Parameter(Mandatory)]
        [array]$Criteria
    )

    $companyMatches = @(
        $DestinationAssets |
        ForEach-Object { $_.asset ?? $_ } |
        Where-Object { $_.company_id -eq $SourceAsset.company_id }
    )
    $candidateScope = @($companyMatches)
    $bestMatches = @()
    $bestCriterion = $null
    $bestSourceValue = $null

    foreach ($criterion in @($Criteria | Sort-Object -Property Order)) {
        $sourceListId = if ($criterion.SourceListId) { [Nullable[int]][int]$criterion.SourceListId } else { $null }
        $destListId = if ($criterion.DestListId) { [Nullable[int]][int]$criterion.DestListId } else { $null }
        $matchMode = if ([string]::IsNullOrWhiteSpace([string]$criterion.MatchMode)) { 'DirectCaseInsensitive' } else { [string]$criterion.MatchMode }
        $sourceValue = Get-AssetMatchComparableValue `
            -Asset $SourceAsset `
            -FieldLabel ([string]$criterion.SourceField) `
            -ListId $sourceListId `
            -UseAssetName ([bool]$criterion.SourceIsAssetName)

        if ([string]::IsNullOrWhiteSpace([string]$sourceValue)) {
            Write-Host "Skipping match criterion '$($criterion.Label)' for source asset '$($SourceAsset.name)' because the source value is blank."
            continue
        }

        $matches = @(
            foreach ($candidate in $candidateScope) {
                $destValue = Get-AssetMatchComparableValue `
                    -Asset $candidate `
                    -FieldLabel ([string]$criterion.DestField) `
                    -ListId $destListId `
                    -UseAssetName ([bool]$criterion.DestIsAssetName)

                if (Test-AssetMatchComparableValue -SourceValue $sourceValue -DestValue $destValue -MatchMode $matchMode) {
                    [pscustomobject]@{
                        Asset       = $candidate
                        Criterion   = $criterion
                        SourceValue = $sourceValue
                        DestValue   = $destValue
                    }
                }
            }
        )

        if ($matches.Count -eq 1) {
            return $matches[0]
        }

        if ($matches.Count -gt 1) {
            $bestMatches = @($matches)
            $bestCriterion = $criterion
            $bestSourceValue = $sourceValue
            $candidateScope = @($matches | ForEach-Object { $_.Asset })
            Write-Host "Criterion '$($criterion.Label)' using '$($criterion.MatchModeLabel ?? $matchMode)' matched $($matches.Count) destination assets for source value '$sourceValue'; checking the next criterion to narrow it down."
            continue
        }

        if ($bestMatches.Count -gt 0) {
            Write-Host "No remaining destination match found by criterion '$($criterion.Label)' for source value '$sourceValue'; keeping the earlier narrowed matches."
        } else {
            Write-Host "No destination match found by criterion '$($criterion.Label)' for source value '$sourceValue'."
            $candidateScope = @($companyMatches)
        }
    }

    if ($bestMatches.Count -gt 0) {
        Write-Host "Multiple destination assets still matched after all custom criteria; using the first match from criterion '$($bestCriterion.Label)'."
        return [pscustomobject]@{
            Asset       = $bestMatches[0].Asset
            Criterion   = $bestCriterion
            SourceValue = $bestSourceValue
            DestValue   = $bestMatches[0].DestValue
        }
    }

    return $null
}

function LabelValueMapToFields {
    param(
        [Parameter(Mandatory)][hashtable]$Map,
        [object[]]$LayoutFields = $null
    )

    $out = @()

    # Preserve layout ordering if given
    if ($LayoutFields) {
        $layoutLabels = @($LayoutFields | ForEach-Object { $_.label } | Where-Object { $_ })
        foreach ($lab in $layoutLabels) {
            if ($Map.ContainsKey($lab)) {
                $out += @{ $lab = $Map[$lab] }
            }
        }
        # Any extras not in layout
        foreach ($k in $Map.Keys | Where-Object { $_ -notin $layoutLabels }) {
            $out += @{ $k = $Map[$k] }
        }
    } else {
        foreach ($k in $Map.Keys) { $out += @{ $k = $Map[$k] } }
    }

    return $out
}

function Is-BlankValue {
    param([object]$Value)
    if ($null -eq $Value) { return $true }

    # AddressData / objects should count as blank only if no meaningful fields
    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        try {
            $pairs = $Value.PSObject.Properties | ForEach-Object { $_.Value }
            return -not ($pairs | Where-Object { -not (Is-BlankValue $_) } | Select-Object -First 1)
        } catch {
            return $false
        }
    }

    return [string]::IsNullOrWhiteSpace([string]$Value)
}

function Test-Equiv {
    param([string]$A, [string]$B)
    $a = Normalize-Text $A; $b = Normalize-Text $B
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    $reA = "(^| )$([regex]::Escape($a))( |$)"
    $reB = "(^| )$([regex]::Escape($b))( |$)"
    if ($b -match $reA -or $a -match $reB) { return $true } 
    if ($a.Replace(' ', '') -eq $b.Replace(' ', '')) { return $true }
    return $false
}

function remove-hudupasswordfromfolder {
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id
    )
    $AssetPassword = [ordered]@{asset_password = $(Get-HuduPasswords -Id $Id) }
    $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password_folder_id -Force -Value $null
    Invoke-HuduRequest -Method put -Resource "/api/v1/asset_passwords/$Id" -Body $($AssetPassword | ConvertTo-Json -Depth 10)
}

function New-HuduGlobalPasswordFolder {
    param ([Parameter(Mandatory)] [string]$Name)
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/password_folders" -Body $(@{password_folder = @{name = $Name; security = "all_users"; allowed_groups  = @()}} | ConvertTo-Json -Depth 10)
        return $res
    } catch {
        Write-Warning "Failed to create new password folder '$Name'- $_"; return $null;
    }
}
function Normalize-Text {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s = $s.Trim().ToLowerInvariant()
    $s = [regex]::Replace($s, '[\s_-]+', ' ')  # "primary_email" -> "primary email"
    # strip diacritics (prénom -> prenom)
    $formD = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()){
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    ($sb.ToString()).Normalize([System.Text.NormalizationForm]::FormC)
}
function Get-Similarity {
    param([string]$A, [string]$B)

    $a = [string](Normalize-Text $A)
    $b = [string](Normalize-Text $B)
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 1.0 }
    if ([string]::IsNullOrEmpty($a) -or  [string]::IsNullOrEmpty($b))  { return 0.0 }

    $n = [int]$a.Length
    $m = [int]$b.Length
    if ($n -eq 0) { return [double]($m -eq 0) }
    if ($m -eq 0) { return 0.0 }

    $d = New-Object 'int[,]' ($n+1), ($m+1)
    for ($i = 0; $i -le $n; $i++) { $d[$i,0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0,$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $im1 = ([int]$i) - 1
        $ai  = $a[$im1]
        for ($j = 1; $j -le $m; $j++) {
            $jm1 = ([int]$j) - 1
            $cost = if ($ai -eq $b[$jm1]) { 0 } else { 1 }

            $del = [int]$d[$i,  $j]   + 1
            $ins = [int]$d[$i,  $jm1] + 1
            $sub = [int]$d[$im1,$jm1] + $cost

            $d[$i,$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }

    $dist   = [double]$d[$n,$m]
    $maxLen = [double][Math]::Max($n,$m)
    return 1.0 - ($dist / $maxLen)
}
function Get-SimilaritySafe { param([string]$A,[string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0.0 }
    $score = Get-Similarity $A $B
    write-host "$A ... $B SCORED $score"
    return $score
}

function Get-CastIfBoolean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value,

        [array]$trueVals  = @("true","t","yes","y","1","on"),# Accepted truthy keyword mappings
        [array]$falseVals = @("false","f","no","n","0","off"), # Accepted falsey keyword mappings
        [bool]$allowFuzzy=$true
    )
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $Value = $Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    }

    # Already a real boolean? return it
    if ($Value -is [bool]) {
        return $Value
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        if ([int]$Value -eq 1) { return $true }
        if ([int]$Value -eq 0) { return $false }
        return $null
    }
    if ($Value -is [string]) {
        $lower = $Value.ToLowerInvariant()

        if ($trueVals  -contains $lower) { return $true }
        if ($falseVals -contains $lower) { return $false }
        if ($true -eq $allowFuzzy){
            foreach ($t in $truevals){
                if ($value -ilike "*$t" -or $value -ilike "$t*") {return $true}
            }
            foreach ($f in $falseVals){
                if ($value -ilike "*$f" -or $value -ilike "$f*") {return $false}
            }
            foreach ($t in $truevals){
                if ($value -ilike "*$t*") {return $true}
            }
            foreach ($f in $falseVals){
                if ($value -ilike "*$f*") {return $false}
            }            
        }


        return $null
    }
    return $null
}

function Set-SmooshAssetFieldsToField {
    param (
        [PSCustomObject]$sourceAsset,
        [array]$smooshsource,
        [bool]$includeBlanks=$false
    )
    if ($excludeHTMLinSMOOSH -and $true -eq $excludeHTMLinSMOOSH) {
        $lineDelmit = " "
    } else {
        $lineDelmit = "<br><hr>"
    }
    foreach ($sourcefieldsmoosh in $smooshsource) {
        if ($null -eq $($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)){
            if ($false -eq $includeBlanks) {continue}
        }
        
        if ($includeLabelInSmooshedValues){
            $header = "$sourcefieldsmoosh -"
        } else {$header = ""}
        $textToUse = ""
        if ("$($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)" -ilike '*list_id*'){
            $precastValue="$($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)"
            $listItemId = $null; 
            $listItemId = $(SafeDecode "$($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)").list_ids[0]
            $textToUse = $($(get-hudulists).list_items | where-object {$_.id -eq $listItemId} | select-object -first 1).name
            Write-Host "non-empty source val [for smoosh] appears to contain listIDs; Raw val '$($precastValue)'... $($textToUse)" -foregroundColor DarkCyan
        } else {
            $textToUse = "$($($sourceasset.fields | where-object {$_.label -ieq $sourcefieldsmoosh}).value)"
        }
        $textToUse = Sanitize-TransferValue -Value $textToUse
        # generate single entry
        $smooshin=@"
$header
$textToUse
"@
        # append to smoosh
        $smoosh=@"
$smoosh
$lineDelmit
$smooshin
"@
}
    if ($excludeHTMLinSMOOSH -and $true -eq $excludeHTMLinSMOOSH) {
        Write-Host "Not using HTML for smoosh; Cleaning values to text-friendly single-line."
        $smoosh = $smoosh -replace "`r?`n", ' '
        $smoosh = $smoosh -replace '\s{2,}', ' '
        $smoosh = Remove-HtmlTags -InputString $smoosh
        $smoosh = $smoosh.Trim()
    }
    $smoosh = Sanitize-TransferValue -Value $smoosh
    write-host "Smooshed preview ($($smoosh.Length) chars): $(Get-LogPreview -Value $smoosh -MaxLength 400)"
    return $smoosh
}

function Get-RelinkableAssetTagLayoutFields {
    param (
        [int]$fromLayoutId
    )
    $linkableLayouts = @()
    $labelLinkMap = @{}
    $relinkables=$($(Get-HuduAssetLayouts -id $fromLayoutId).fields | where-object {$_.field_type -eq "AssetTag" -and $null -ne $_.linkable_id})
    write-host "$($relinkables.count) are likely relinkable."
    $linkableIDX=0
    foreach ($relinkable in $relinkables){
        $linkableIDX=$linkableIDX+1
        $linkablelayout = Get-HuduAssetLayouts -id $relinkable.linkable_id
        if (-not $linkablelayout -or $null -eq $linkablelayout) {continue}
        $labelLinkMap[$relinkable.label]=$linkablelayout
        write-host "linkable $linkableIDX of $($relinkables.count): label $($relinkable.label) is linkable to $($linkablelayout.name)"
        $linkableLayouts+=$linkablelayout
    }    
    return $labelLinkMap
}

function Get-CleansedEmailAddresses {
    <#
    returns a semicolon-delimited series of email addresses (if going to Text field, it's good to do this after stripping HTML, as to remove table row / column names)
    #>
    param (
        [string]$InputString,
        [string]$pattern = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    )
    
    $cleansed  = ( $inputString | Select-String -AllMatches -Pattern $pattern ).Matches.Value -join '; '
    return "$cleansed".Trim()
}

function Get-SmooshedLinkableDescription {
    param (
        [array]$linkableObjects
    )
    $description=""
    if (-not $linkableObjects -or $linkableObjects.count -lt 1) {
        return ""
    }

    foreach ($linkable in $linkableObjects) {
        if ($linkable.linkedasset.url){
        $descriptor=@"
<br><hr>
<a href='$($linkable.linkedasset.url)'>Related $($linkable.LinkedLayout.name) - $($linkable.LinkedAsset.name)</a>
"@
} else {
        $descriptor=@"
Related $($linkable.LinkedLayout.name) - $($linkable.LinkedAsset.name)
"@    
    }
    $description = "$description<br><hr>$descriptor"
    }
    return $description
}
function Get-EnsuredPath {
    param([string]$path)
    $basePath = if (-not [string]::IsNullOrWhiteSpace($script:Root)) {
        $script:Root
    }
    else {
        (Get-Location).Path
    }

    $outpath = if (-not $path -or [string]::IsNullOrWhiteSpace($path)) {
        Join-Path $basePath 'debug'
    }
    elseif ([System.IO.Path]::IsPathRooted($path)) {
        $path
    }
    else {
        Join-Path $basePath $path
    }

    if (-not (Test-Path -LiteralPath $outpath -PathType Container)) {
        New-Item -ItemType Directory -Path $outpath -Force -ErrorAction Stop | Out-Null
        write-host "path is now present: $outpath"
    } else {write-host "path is present: $outpath"}
    return $outpath
}

function Get-RelinkableRelationsForAsset {
    param (
        [PSCustomObject]$sourceAsset,
        [hashtable]$labelLinkMap
    )
    $linkableObjects = @()
    foreach ($linkableField in $sourceAsset.fields | Where-Object {
        $_.label -and $_.label -in $labelLinkMap.Keys
    }) {
        $layoutForLinking = $labelLinkMap[$linkableField.label]

        try {
            $linkedItems = $null
            if ($linkableField.value -is [string] -and $linkableField.value.Trim().StartsWith("[")) {
                $linkedItems = $linkableField.value | ConvertFrom-Json
            }

            foreach ($linkedItem in $linkedItems) {
                $linkedAsset = Get-HuduAssets -Id $linkedItem.id
                if ($false -eq $includeRelationsForArchived -and $true -eq $linkedAsset.archived){
                    write-host "archived link, continuing"
                    continue
                }

                $linkableObjects+=[PSCustomObject]@{
                    SourceAssetId   = $sourceAsset.id
                    SourceField     = $linkableField.label
                    LinkedAsset     = $linkedAsset
                    LinkedLayout    = $layoutForLinking
                }
            }
        }
        catch {
            Write-Warning "Could not parse linked values for field [$($linkableField.label)] in asset [$($sourceAsset.id)]"
        }
    }
    return $linkableObjects
}

function Remove-HtmlTags {
    param (
        [string]$InputString
    )
    $tags = @(
'hr','br', 'tr', 'td', 'th', 'table', 'div', 'span',
'p', 'ul', 'ol', 'li', 'h[1-6]', 'strong', 'em', 'b', 'i',
'colgroup', 'col', 'input', 'column', 'section', 'article',
'header', 'footer', 'aside', 'nav', 'main', 'figure', 'figcaption',
'blockquote', 'pre', 'address', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
'thead', 'tbody', 'tfoot','script','noscript','style','template','head','svg','math'
        )
    $cleaned = $InputString
    foreach ($tag in $tags) {
        # Regex matches both opening <tag ...> and closing </tag>
        $pattern = "<\/?$tag\b[^>]*>"
        $cleaned = [regex]::Replace($cleaned, $pattern, " ", "IgnoreCase")
    }
    return $cleaned.Trim()
}
function Select-ObjectFromList($objects, $message, $inspectObjects = $false, $allowNull = $false) {
    $validated = $false
    while (-not $validated) {
        if ($allowNull) {
            Write-Host "0: None/Custom"
        }
        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]
            $displayLine = if ($inspectObjects) {
                "$($i+1): $(Write-InspectObject -object $object)"
            } elseif ($null -ne $object.OptionMessage) {
                "$($i+1): $($object.OptionMessage)"
            } elseif ($null -ne $object.name) {
                "$($i+1): $($object.name)"
            } else {
                "$($i+1): $($object)"
            }
            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }
        $choice = Read-Host $message
        if (-not ($choice -as [int])) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }
        $choice = [int]$choice
        if ($choice -eq 0 -and $allowNull) {
            return $null
        }
        if ($choice -ge 1 -and $choice -le $objects.Count) {
            return $objects[$choice - 1]
        } else {
            Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
        }
    }
}
function Get-UniqueListName {
  param([Parameter(Mandatory)][string]$BaseName,[bool]$allowReuse=$false)

  $name = $BaseName.Trim()
  $i = 0
  while ($true) {
    $existing = Get-HuduLists -name $name
    if (-not $existing) { return $name }
    if ($existing -and $true -eq $allowReuse) {return $existing}
    $i++
    $name = "{0}-{1}" -f $BaseName.Trim(), $i
  }
}

function Get-NormalizedDropdownOptions {
  param([Parameter(Mandatory)]$OptionsRaw)
  $lines =
    if ($null -eq $OptionsRaw) { @() }
    elseif ($OptionsRaw -is [string]) { $OptionsRaw -split "`r?`n" }
    elseif ($OptionsRaw -is [System.Collections.IEnumerable]) { @($OptionsRaw) }
    else { @("$OptionsRaw") }

  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in $lines) {
    $x = "$l".Trim()
    if ($x -ne "" -and $seen.Add($x)) { $out.Add($x) }
  }
  if ($out.Count -eq 0) { @('None','N/A') } elseif ($out.Count -eq 1) { @('None',$out[0] ?? "N/A") } else { $out.ToArray() }
}
function Get-FieldValueByLabel {
    param([array]$Fields, [string]$Label)
    if (-not $Label) { return $null }
    ($Fields | Where-Object { $_.label -eq $Label } | Select-Object -First 1).value
}
function Normalize-Region {
    param([string]$State)
    if (-not $State) { return $null }
    $s = $State.Trim()

    # Already 2 letters?
    if ($s -match '^[A-Za-z]{2}$') { return $s.ToUpper() }

    $us = @{
        'alabama'='AL'; 'alaska'='AK'; 'arizona'='AZ'; 'arkansas'='AR'; 'california'='CA'
        'colorado'='CO'; 'connecticut'='CT'; 'delaware'='DE'; 'florida'='FL'; 'georgia'='GA'
        'hawaii'='HI'; 'idaho'='ID'; 'illinois'='IL'; 'indiana'='IN'; 'iowa'='IA'
        'kansas'='KS'; 'kentucky'='KY'; 'louisiana'='LA'; 'maine'='ME'; 'maryland'='MD'
        'massachusetts'='MA'; 'michigan'='MI'; 'minnesota'='MN'; 'mississippi'='MS'; 'missouri'='MO'
        'montana'='MT'; 'nebraska'='NE'; 'nevada'='NV'; 'new hampshire'='NH'; 'new jersey'='NJ'
        'new mexico'='NM'; 'new york'='NY'; 'north carolina'='NC'; 'north dakota'='ND'
        'ohio'='OH'; 'oklahoma'='OK'; 'oregon'='OR'; 'pennsylvania'='PA'; 'rhode island'='RI'
        'south carolina'='SC'; 'south dakota'='SD'; 'tennessee'='TN'; 'texas'='TX'; 'utah'='UT'
        'vermont'='VT'; 'virginia'='VA'; 'washington'='WA'; 'west virginia'='WV'; 'wisconsin'='WI'; 'wyoming'='WY'
        'district of columbia'='DC'; 'washington dc'='DC'; 'dc'='DC'
    }
    $key = $s.ToLower()
    if ($us.ContainsKey($key)) { return $us[$key] }
    return $s  # fallback (leave as-is)
}

function Normalize-CountryName {
    param([string]$Country)
    if (-not $Country) { return $null }
    $c = $Country.Trim()
    $map = @{
        'us'='USA'; 'u.s.'='USA'; 'u.s.a'='USA'; 'usa'='USA'; 'united states'='USA'; 'united states of america'='USA'
        'uk'='United Kingdom'; 'u.k.'='United Kingdom'; 'gb'='United Kingdom'; 'gbr'='United Kingdom'
        'uae'='United Arab Emirates'
    }
    $key = $c.ToLower().Replace('.','')
    if ($map.ContainsKey($key)) { return $map[$key] }
    # Title-case fallback
    return -join ($c.ToLower().Split(' ') | ForEach-Object { if ($_){ $_.Substring(0,1).ToUpper()+$_.Substring(1) } })
}

function Normalize-Zip {
    param([string]$Zip)
    if (-not $Zip) { return $null }
    $z = $Zip -replace '\s+', ''  # collapse spaces (e.g., “802 02”)
    return $z.Trim()
}

function Write-InspectObject {
    param (
        [object]$object,
        [int]$Depth = 32,
        [int]$MaxLines = 16
    )
    $stringifiedObject = $null
    if ($null -eq $object) {
        return "Unreadable Object (null input)"
    }
    # Try JSON
    $stringifiedObject = try {
        $json = $object | ConvertTo-Json -Depth $Depth -ErrorAction Stop
        "# Type: $($object.GetType().FullName)`n$json"
    } catch { $null }
    # Try Format-Table
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-Table -Force | Out-String
        } catch { $null }
    }
    # Try Format-List
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-List -Force | Out-String
        } catch { $null }
    }
    # Fallback to manual property dump
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $props = $object | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            $lines = foreach ($p in $props) {
                try {
                    "$p = $($object.$p)"
                } catch {
                    "$p = <unreadable>"
                }
            }
            "# Type: $($object.GetType().FullName)`n" + ($lines -join "`n")
        } catch {
            "Unreadable Object"
        }
    }
    if (-not $stringifiedObject) {
        $stringifiedObject =  try {"$($($object).ToString())"} catch {$null}
    }
    # Truncate to max lines if necessary
    $lines = $stringifiedObject -split "`r?`n"
    if ($lines.Count -gt $MaxLines) {
        $lines = $lines[0..($MaxLines - 1)] + "... (truncated)"
    }
    return $lines -join "`n"
}
function Test-DateAfter {
    param(
        [Parameter(Mandatory)][string]$DateString,
        [datetime]$Cutoff = [datetime]'1000-01-01'
    )
    $dt = $null
    $ok = [datetime]::TryParseExact(
        $DateString,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$dt
    )
    if (-not $ok) { return $false }   # invalid format → fail
    return ($dt -ge $Cutoff)
}

function Get-CoercedDate {
    param(
        [Parameter(Mandatory)]
        [object]$InputDate,  # allow string or [datetime]

        [datetime]$Cutoff = [datetime]'1000-01-01',

        [ValidateSet('DD.MM.YYYY','YYYY.MM.DD','MM/DD/YYYY')]
        [string]$OutputFormat = 'MM/DD/YYYY'
    )

    $Inv = [System.Globalization.CultureInfo]::InvariantCulture

    if ($InputDate -is [datetime]) {
        $dt = [datetime]$InputDate
    }
    else {
        $text = "$InputDate".Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }

        # 2) Try strict formats first via ParseExact
        $formats = @(
            'MM/dd/yyyy HH:mm:ss'
            'MM/dd/yyyy hh:mm:ss tt'
            'MM/dd/yyyy'
        )

        $dt   = $null
        $ok   = $false

        foreach ($fmt in $formats) {
            try {
                $dt = [System.DateTime]::ParseExact($text, $fmt, $Inv)
                $ok = $true
                break
            } catch {
                # ignore and try next format
            }
        }

        # 3) Fallback: general Parse (handles lots of “normal” date strings)
        if (-not $ok) {
            try {
                $dt = [System.DateTime]::Parse($text, $Inv)
            } catch {
                return $null
            }
        }
    }

    if ($dt -lt $Cutoff) { return $null }

    switch ($OutputFormat) {
        'DD.MM.YYYY' { $dt.ToString('dd.MM.yyyy', $Inv) }
        'YYYY.MM.DD' { $dt.ToString('yyyy.MM.dd', $Inv) }
        'MM/DD/YYYY' { $dt.ToString('MM/dd/yyyy', $Inv) }
    }
}


function Set-LayoutsForTransfer {
    param ($allLayouts)
    $layoutMap = @{}
    foreach ($layout in $allLayouts) {
        $layoutMap[$layout.id] = $layout
    }
    $layoutSummaries = $allLayouts  | ForEach-Object {
        [PSCustomObject]@{
            ID          = $_.id
            OptionMessage = "$($_.name): $( ($_.fields).Count ) fields with $($_.assetsInLayoutCount) assets present"
            Name        = $_.name
    }}
    write-host "$(if ($layoutSummaries.count -ne $allLayouts.count) {
        "$([int]$allLayouts.count - [int]$layoutSummaries.count) layouts were excluded due to not having fields, not having assets, or being otherwise ineligible."
    } else {
        "created user-friendly summaries for $($layoutSummaries.count) asset layouts"
    })" -ForegroundColor darkcyan
    $sourceLayout = $null
    $destLayout = $null
    while ($true) {
        $sourceSummary = Select-ObjectFromList -objects $layoutSummaries -message "Which source / origin asset layout?" -allowNull $false -inspectObjects $inspectlayouts
        $sourceLayout  = $layoutMap[$sourceSummary.ID]

        $destSummaries = $layoutSummaries | Where-Object { $_.ID -ne $sourceLayout.id }
        $destSummary   = Select-ObjectFromList -objects $destSummaries -message "Which dest / target asset layout?" -allowNull $false -inspectObjects $inspectlayouts
        $destLayout    = $layoutMap[$destSummary.ID]
        if ($($null -ne $sourceLayout -and $null -ne $destLayout) -and $(Select-ObjectFromList -objects @("yes","no") -message "You've selected source layout as: $($sourceLayout.name) and dest layout as: $($destLayout.name). Proceed?") -eq "yes") {
            return @{
                SourceLayout = $sourceLayout
                DestLayout   = $destLayout
            }
        } else {
            Write-Host "Opting to re-select."
        }
    }
}

function Get-SourceListItemNameFieldFromID {
    param ([string]$RawValue,[string]$FieldLabel)
    if ([string]::IsNullOrWhiteSpace($RawValue)){return $null}
    $mapped = $null
    if ("$RawValue" -ilike '*list_id*') {
        try {
            $listItemId = ($RawValue | ConvertFrom-Json).list_ids[0]
            if ($FieldLabel) {
                $mapped = (Get-HuduLists -Name $FieldLabel).list_items |
                          Where-Object { $_.id -eq $listItemId } |
                          Select-Object -ExpandProperty name -ErrorAction SilentlyContinue
            }
            if ($mapped) { return $mapped }
        }
        catch {
            Write-Host "Error transforming list_id source value '$RawValue' — $_"
            return $mapped
        }
    } else {
        Write-Host "list item is presumed human-readable"
        return $RawValue
    }
}
function SafeDecode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -isnot [string]) {
        return $InputObject
    }

    $s = $InputObject.Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }

    try {
        return $s | ConvertFrom-Json -ErrorAction Stop
    } catch {
        # Not valid JSON; just return the original string
        return $InputObject
    }
}


function Convert-ToListSelectMappingHashtable {
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    $normalized = @{}

    if ($null -eq $InputObject) {
        return $normalized
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $normalized[[string]$key] = $InputObject[$key]
        }
        return $normalized
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        foreach ($item in @($InputObject)) {
            if ($null -eq $item) {
                continue
            }

            if ($item -is [System.Collections.DictionaryEntry]) {
                $normalized[[string]$item.Key] = $item.Value
                continue
            }

            if ($item -is [System.Collections.IDictionary]) {
                foreach ($key in $item.Keys) {
                    $normalized[[string]$key] = $item[$key]
                }
                continue
            }

            $keyProp = $item.PSObject.Properties['Key']
            $valueProp = $item.PSObject.Properties['Value']
            if ($keyProp -and $valueProp) {
                $normalized[[string]$keyProp.Value] = $valueProp.Value
                continue
            }

            foreach ($property in $item.PSObject.Properties) {
                $normalized[[string]$property.Name] = $property.Value
            }
        }

        return $normalized
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $normalized[[string]$property.Name] = $property.Value
    }

    return $normalized
}

function Get-ListSelectWhenValues {
    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }

    $whenValues = $null

    if ($Value -is [System.Collections.IDictionary] -and $Value.Contains('whenvalues')) {
        $whenValues = $Value['whenvalues']
    } elseif ($Value.PSObject.Properties['whenvalues']) {
        $whenValues = $Value.PSObject.Properties['whenvalues'].Value
    } else {
        $whenValues = $Value
    }

    return @(
        @($whenValues) |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Set-MappedListSelectItemFromuserMapping {
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        # Hashtable of key -> string[] (whenvalues), or a serialized equivalent.
        [Parameter(Mandatory)]
        [object]$Mapping,

        # Raw field value (field.value from the source asset)
        [Parameter(Mandatory)]
        $RawValue,

        # Optional: for list_id → label resolution (if needed later)
        [Parameter()]
        [hashtable]$SourceListItemMap,

        [Parameter()]
        [string]$FieldLabel
    )

    $Mapping = Convert-ToListSelectMappingHashtable -InputObject $Mapping

    $result = @{
        MatchFound   = $false
        Key          = $null        # destination list item label, e.g. 'these options'
        Normalized   = $RawValue    # coerced/clean value used for comparison
        NeedsNewItem = $true
    }

    # --- 1. Normalize / coerce list_id JSON if present ---
    $listItemValue = $RawValue
    if ("$RawValue" -ilike '*list_id*') {
        try {
            $listItemId = ($RawValue | ConvertFrom-Json).list_ids[0]


            $mapped = $null

            if ($FieldLabel) {
                $mapped = (Get-HuduLists -Name $FieldLabel).list_items |
                          Where-Object { $_.id -eq $listItemId } |
                          Select-Object -ExpandProperty name -ErrorAction SilentlyContinue
            }

            if ($mapped) { $listItemValue = $mapped }
        }
        catch {
            Write-Host "Error transforming list_id source value '$RawValue' — $_"
        }
    }

    $result.Normalized = $listItemValue
    $normalizedListItemValue = Remove-HtmlTags -InputString "$listItemValue"

    # --- 2. Filter mappings to only non-empty whenvalues arrays ---
    $nonEmptyMappings = $Mapping.GetEnumerator() | Where-Object {
        @(Get-ListSelectWhenValues -Value $_.Value).Count -gt 0
    }

    if ($nonEmptyMappings.Count -eq 0) {
        return $result
    }

    # --- 3. Try to match: find key whose whenvalues contains our value ---
    foreach ($entry in $nonEmptyMappings) {
        $keyName   = $entry.Key          # e.g. 'these options' / 'milk'
        $whenvalues = @(Get-ListSelectWhenValues -Value $entry.Value)

        foreach ($potentialMatch in $whenvalues) {
            if ($(Test-Equiv -A "$potentialMatch" -B "$listItemValue") -or $(Test-Equiv -A "$potentialMatch" -B "$normalizedListItemValue")) {

                $result.MatchFound   = $true
                $result.Key          = $keyName   # <- THIS is what Hudu wants
                $result.NeedsNewItem = $false
                return $result
            }
        }
    }

    # No match
    return $result
}

function Normalize-WebURL {
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    $Url = $Url.Trim()
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }

    # 1) UNC paths: \\server\share\path or //server/share/path
    if ($Url -match '^(\\\\|//)(?<host>[^\\/]+)(?<rest>.*)$') {
        $parsedHost = $matches.host
        $rest = $matches.rest -replace '\\','/'
        $rest = $rest.Trim()

        if ($rest -and -not $rest.StartsWith('/')) {
            $rest = '/' + $rest
        }

        $normalized = "https://$parsedHost$rest"
        return $normalized.TrimEnd('/')
    }

    # 2) file:// URLs (local or UNC-ish)
    if ($Url -match '^file://(?<rest>.+)$') {
        $rest = $matches.rest.TrimStart('\','/')
        $rest = $rest -replace '\\','/'
        $normalized = "https://$rest"
        return $normalized.TrimEnd('/')
    }

    # 3) Any other scheme: http://, ftp://, whatever://
    if ($Url -match '^(?<scheme>[a-z][a-z0-9+\-.]*://)(?<rest>.+)$') {
        $rest = $matches.rest.TrimStart('/')
        $normalized = "https://$rest"
        return $normalized.TrimEnd('/')
    }

    # 4) No scheme at all → assume https://
    return ("https://$Url").TrimEnd('/','\')
}

function Convert-FieldArrayToMap {
    param([Parameter(Mandatory)][object[]]$FieldArray)

    $map = @{}
    foreach ($ht in $FieldArray) {
        if ($ht -isnot [hashtable] -and $ht -isnot [System.Collections.IDictionary]) { continue }
        foreach ($k in $ht.Keys) {
            $map[$k] = $ht[$k]
        }
    }
    return $map
}

function Merge-HuduFieldMaps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$SourceMap,   # transformed/source
        [Parameter(Mandatory)][hashtable]$DestMap,     # matched/dest existing
        [Parameter(Mandatory)][object[]]$LayoutFields, # dest layout fields
        [ValidateSet('Merge-FillBlanks','Merge-PreferSource','Merge-Concat')]
        [string]$Mode = 'Merge-FillBlanks',

        # For Merge-Concat: which field types should be concatenated?
        [string[]]$ConcatTypes = @('RichText','Text', "Heading", "ConfidentialText","Password"),

        # Separators
        [string]$RichTextSeparator = "<br><hr>",
        [string]$TextSeparator     = "`n`n---`n`n",

        # Provenance stamping
        [switch]$StampProvenance,
        [string]$SourceStamp = "Imported (source)",
        [string]$DestStamp   = "Existing (dest)"
    )

    $typeByLabel = Get-FieldTypeByLabel -LayoutFields $LayoutFields

    $out = @{}

    $labels = @($SourceMap.Keys + $DestMap.Keys) | Select-Object -Unique
    foreach ($label in $labels) {
        $listItemId = $null; $humanReadable = $null;
        $src = $SourceMap[$label]
        $dst = $DestMap[$label]
        $srcBlank = Is-BlankValue $src
        $dstBlank = Is-BlankValue $dst
        # only fetched-dest will be in non-human format when list
        if (-not $dstBlank -and $dst -ilike '*list_id*'){
            try {
                $listItemId = $(SafeDecode $dst).list_ids[0]
                $humanReadable = $($(get-hudulists).list_items | where-object {$_.id -eq $listItemId} | select-object -first 1).name
            } catch {
                Write-Host "Error transforming list_id source value '$dst' — $_"
            }
            if (-not ([string]::IsNullOrWhiteSpace($humanReadable))) {
                $dst = $humanReadable
                write-host "existing dest value for '$label' is a list item ID ($listItemId), transformed to human-readable '$dst'"
            }
        }
        

        $fieldType = $typeByLabel[$label]
        if (-not $fieldType) { $fieldType = 'Text' }

        switch ($Mode) {

            'Merge-FillBlanks' {
                # dest wins unless blank
                if (-not $dstBlank) {
                    $out[$label] = $dst
                } elseif (-not $srcBlank) {
                    $out[$label] = $src
                }
            }

            'Merge-PreferSource' {
                # source wins unless blank
                if (-not $srcBlank) {
                    $out[$label] = $src
                } elseif (-not $dstBlank) {
                    $out[$label] = $dst
                }
            }

            'Merge-Concat' {
                $isConcat = $ConcatTypes -contains $fieldType

                if (-not $isConcat) {
                    # For non-concat field types, default to PreferSource (tweak if you prefer)
                    if (-not $srcBlank) { $out[$label] = $src }
                    elseif (-not $dstBlank) { $out[$label] = $dst }
                    break
                }

                # Concat path (only when both present)
                if (-not $srcBlank -and -not $dstBlank) {

                    $sep = if ($fieldType -eq 'RichText') { $RichTextSeparator } else { $TextSeparator }

                    if ($StampProvenance) {
                        if ($fieldType -eq 'RichText') {
                            $lhs = "<div><strong>$SourceStamp</strong></div>$src"
                            $rhs = "<div><strong>$DestStamp</strong></div>$dst"
                            $out[$label] = "$lhs$sep$rhs"
                        } else {
                            $lhs = "$SourceStamp`n$src"
                            $rhs = "$DestStamp`n$dst"
                            $out[$label] = "$lhs$sep$rhs"
                        }
                    } else {
                        $out[$label] = ([string]$src) + $sep + ([string]$dst)
                    }

                } elseif (-not $srcBlank) {
                    $out[$label] = $src
                } elseif (-not $dstBlank) {
                    $out[$label] = $dst
                }
            }
        }
    }

    return $out
}
function FieldListToMap {
    param([object[]]$FieldList)

    $map = @{}
    foreach ($ht in ($FieldList ?? @())) {
        if ($ht -isnot [System.Collections.IDictionary]) { continue }
        foreach ($k in $ht.Keys) {
            $map[$k] = $ht[$k]   # last wins
        }
    }
    $map
}

function MapToFieldList {
    param(
        [hashtable]$Map,
        [object[]]$LayoutFields = $null  # optional for ordering
    )

    $out = @()

    if ($LayoutFields) {
        foreach ($lf in $LayoutFields) {
            $label = $lf.label
            if ($label -and $Map.ContainsKey($label)) {
                $out += @{ $label = $Map[$label] }
            }
        }
        # include any extras not in layout
        foreach ($k in $Map.Keys | Where-Object { $_ -notin ($LayoutFields.label) }) {
            $out += @{ $k = $Map[$k] }
        }
    } else {
        foreach ($k in $Map.Keys) { $out += @{ $k = $Map[$k] } }
    }

    $out
}


function Ensure-HuduListItemByName {
    param(
        [Parameter(Mandatory)][int]$ListId,
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$listNameExistsByListId
    )

    $nameTrim = $Name.Trim()
    $needle = $nameTrim.ToLowerInvariant()

    if (-not $listNameExistsByListId.ContainsKey($ListId)) {
        Refresh-ListCache
    }

    $map = $listNameExistsByListId[$ListId]
    if ($map -and $map.ContainsKey($needle)) {
        return $map[$needle]  # return canonical name as stored
    }

    # Add item to list
    $list = Get-HuduLists -Id $ListId
    $listName = $list.name

    $items = @()
    foreach ($existing in ($list.list_items ?? @())) {
        $items += @{ id = [int]$existing.id; name = [string]$existing.name }
    }
    $items += @{ name = $nameTrim }

    $null = Set-HuduList -Id $ListId -Name $listName -ListItems $items

    # refresh cache and return
    $listNameExistsByListId = Refresh-ListCache
    $map = $listNameExistsByListId[$ListId]
    if ($map.ContainsKey($needle)) { return $map[$needle] }

    throw "Failed to add/list item '$Name' to list $ListId"
}
function Refresh-ListCache {
    $listNameExistsByListId = @{}
    foreach ($l in Get-HuduLists) {
        $lid = [int]$l.id
        $map = @{}
        foreach ($it in ($l.list_items ?? @())) {
            if ($it.name) {
                $map[$it.name.ToString().Trim().ToLowerInvariant()] = [string]$it.name
            }
        }
        $listNameExistsByListId[$lid] = $map
    }
    return $listNameExistsByListId
}
$allRelations = get-hudurelations

Write-Host "Loaded $($allRelations.count) relations"
## START
try {$migrationRecord = Set-MigrationRecord} catch {}
# load supplementary data
write-host "$(if ($allPasswords -and $null -ne $allPasswords) {'refreshing existing passwordables cache'} else {'refreshing passwordables cache'})"; $allPasswords = $(Get-HuduPasswords);
write-host "$(if ($allUploads -and $null -ne $allUploads) {'refreshing existing uploadables cache'} else {'refreshing uploadables cache'})"; $allUploads = $(Get-HuduUploads);
write-host "$(if ($allPhotos -and $null -ne $allPhotos) {'refreshing existing photos cache'} else {'refreshing photos cache'})"; $allphotos = $(Get-HuduPhotos);
write-host "$(if ($allPublicPhotos -and $null -ne $allPublicPhotos) {'refreshing existing public photos cache'} else {'refreshing public photos cache'})"; $allPublicPhotos = $(Get-HuduPublicPhotos);

foreach ($entry in $mapping) {
    if ($entry.dest_type -eq 'ListSelect' -and -not ([string]::IsNullOrWhiteSpace($entry.from))) {
        $parsedMap = @{}
        $entryMapping = Convert-ToListSelectMappingHashtable -InputObject $entry.Mapping
        $entryMapping.GetEnumerator().ForEach({
            $whenValues = @(Get-ListSelectWhenValues -Value $_.Value)
            if ($whenValues.Count -gt 0) {
                $parsedMap[$_.Key] = $whenValues
            }
        })
        $ListSelectEquivilencyMaps[$entry.to]=@{Mapping = $parsedMap; list_options=$($entryMapping.Keys); list_id=$entry.list_id; add_listitems=$("$($entry.add_listitems)" -ilike "t*" ?? $false)}
        $sourcedestlabels[$entry.from] = $entry.to
        $sourcedestStripHTML[$entry.from] = [bool]$(@('t','true','y','yes') -contains "$($entry.striphtml ?? "true")".ToLower())
        $sourceDestDataType[$entry.from] = 'ListSelect'
        continue
    } elseif ($entry.dest_type -eq 'AddressData') {
        $addressMapsByDest[$entry.to] = $entry.address
        $sourcedestrequired[$entry.from] = $false
        $sourceDestDataType[$entry.from] = 'AddressData'
        $sourcedestlabels[$entry.from] = 'Meta'
        continue
    }
    $sourcedestStripHTML[$entry.from] = [bool]$(@('t','true','y','yes') -contains "$($entry.striphtml ?? "False")".ToLower())
    write-host "mapping $($entry.from) to $($entry.to) $(if ($true -eq $sourcedestStripHTML[$entry.from]) {"destination field of $($entry.to) will have HTML stripped."} else {'as-is'})"
    $sourcedestlabels[$entry.from] = $entry.to
    $sourcedestrequired[$entry.from] = $((Get-CastIfBoolean ($entry.required ?? $false) -allowFuzzy $false) ?? $false)
    $sourceDestDataType[$entry.from] = $($entry.dest_type ?? 'Text')
}

$mappingtosmooshed = [bool]$($SMOOSHLABELS.count -gt 0)
$sourceAssets = get-huduassets -assetlayoutid $sourceassetlayout.id
if (-not [string]::IsNullOrWhiteSpace($SourceAssetFilterField) -and ($SourceAssetFilterValueIsBlank -or -not [string]::IsNullOrWhiteSpace($SourceAssetFilterValue))) {
    $unfilteredSourceAssetCount = @($sourceAssets).Count
    $sourceAssets = @(
        $sourceAssets | Where-Object {
            $comparableValue = Get-AssetFieldComparableValue -Asset $_ -FieldLabel $SourceAssetFilterField -ListId $SourceAssetFilterListId
            if ($SourceAssetFilterValueIsBlank) {
                [string]::IsNullOrWhiteSpace($comparableValue)
            } else {
                $comparableValue -eq $SourceAssetFilterValue
            }
        }
    )
    $sourceFilterValueForLog = if ($SourceAssetFilterValueIsBlank) { '[Blank / Null]' } else { $SourceAssetFilterValue }
    Write-Host ("Source asset filter applied: when '{0}' is '{1}'. {2} of {3} source assets will be processed." -f $SourceAssetFilterField, $sourceFilterValueForLog, @($sourceAssets).Count, $unfilteredSourceAssetCount)
}
$totalcounts.sourceassetcount = @($sourceAssets).Count
$destassets = get-huduassets -assetlayoutid $destassetlayout.id
if ($sourceassets.count -lt 1) { write-host "NO SOURCE ASSETS!"; exit}
write-host "$($($addressMapsByDest.GetEnumerator()).count) Location Types in Target"


# write-out user-defined infos before start
if ($mappingtosmooshed) {write-host "Smooshing $SMOOSHLABELS => $mappingtosmooshed; $(($mapping | Where-Object { $_.from -eq 'SMOOSH' }).to)"}
if ($CONSTANTS) {
    foreach ($c in $CONSTANTS){write-host "Dest Labels containing $($c.to_label) will be given static value from literal $($c.literal) as literal value!"}
} else {write-host "No constants mapped"}
if ($ListSelectEquivilencyMaps.Keys.count -gt 0){Write-host "$($ListSelectEquivilencyMaps.Keys.count) listselect target items mapped for $($ListSelectEquivilencyMaps.Keys -join ",")"}
if (@($MatchCriteria).Count -gt 0) {
    Write-Host "Custom matching criteria enabled: $(@($MatchCriteria | Sort-Object -Property Order | ForEach-Object { $_.Label }) -join ' -> ')"
} else {
    Write-Host "Custom matching criteria not configured; using default destination name matching."
}

if ($mappingtosmooshed) {
    Write-Host "SMOOSH source labels supplied: $($SMOOSHLABELS.Count) => $($SMOOSHLABELS -join ', ')"
}
Write-Host "Smooshing $(if ($excludeHTMLinSMOOSH -and $true -eq $excludeHTMLinSMOOSH) {'using plaintext value-joining'} else {'using traditional HTML value joining'})"
Write-Host "$($sourceassets.count) source assets and $($destassets.count) dest assets."



$sourceassetsIDX=0
foreach ($originalasset in $sourceassets) {
    $sourceassetsIDX=$sourceassetsIDX+1
    $linkableToAssetInfo = $null; $NewAssetName = $originalasset.name; $matchedMap = $null; $match = $null; $newAsset = $null;
    write-host "matching existing assets to asset $sourceassetsIDX of $($sourceassets.count) in destination layout assets ($($destassets.count) total) to determine if overlap"
    if (@($MatchCriteria).Count -gt 0) {
        $customMatch = Find-DestinationAssetMatchByCriteria -SourceAsset $originalasset -DestinationAssets $destassets -Criteria $MatchCriteria
        if ($customMatch -and $customMatch.Asset) {
            $match = $customMatch.Asset
            Write-Host ("Matched by custom criterion #{0} '{1}' using '{2}': source '{3}' matched destination '{4}'." -f $customMatch.Criterion.Order, $customMatch.Criterion.Label, ($customMatch.Criterion.MatchModeLabel ?? $customMatch.Criterion.MatchMode ?? 'Direct match (case insensitive)'), $customMatch.SourceValue, $customMatch.DestValue)
        } else {
            Write-Host "No custom matching criteria matched source asset '$($originalasset.name)'. A new destination asset will be created unless later logic changes that."
        }
    } else {
        $match = $destassets | Where-Object { $_.company_id -eq $originalasset.company_id -and $_.name -ieq $originalasset.name } | Select-Object -First 1
        if (-not $match -and $originalasset.name.length -gt 6) {
            $match = $destassets | where-object {$_.company_id -eq $originalasset.company_id -and ($_.name -ilike "$($originalasset.name)*" -or $_.name -ilike "*$($originalasset.name)")} | Select-Object -First 1
        }
    }
    $match = $match.asset ?? $match
    if ($match -and $null -ne $match -and $null -ne $match.fields) {
        $totalcounts.assetsmatched=$totalcounts.assetsmatched+1
        if ($true -eq $MergeOnMatch){
            write-host "Matched existing asset '$($match.name)' (ID: $($match.id)) in destination layout for source asset '$($originalasset.name)' (ID: $($originalasset.id)) - will compile complete list of fields from both"
            $matchedMap = FieldsToLabelValueMap $match.fields
        } elseif ($true -eq $SkipOnMatch) {
            write-host "match found in dest layout. (#$($totalcounts.assetsmatched)) thus far"
            write-host "original: $($($originalasset | ConvertTo-Json -depth 6).ToString())" -ForegroundColor Yellow
            write-host "match: $($($match | ConvertTo-Json -depth 6).ToString())" -ForegroundColor Blue
            continue
        } else {
            write-host "match found in dest layout. (#$($totalcounts.assetsmatched)) thus far"
            $NewAssetName = "$($originalasset.name) (from layout $($sourceassetlayout.name))"
            write-host "overridding name -> $($NewAssetName) and keeping both per user-preference"
        }
    }

    $transformedFields = @()
    # map fields from source to dest, applying any transformations or mappings as needed based on user input in $mapping and the field types in source/dest layouts
    foreach ($field in $originalasset.fields) {
        # acquire destination information
        $transformedlabel = $sourcedestlabels[$field.label] ?? $null
        $destTranslationFieldRequired = $(Get-CastIfBoolean $($sourcedestrequired[$field.label] ?? $false)) ?? $false
        $stripHTML = $($sourcedestStripHTML["$($field.label)"] ?? $false)
        $destFieldType = $sourceDestDataType["$($field.label)"] ?? 'Text'

        # checking presence + validity
        if (-not $transformedlabel -or $null -eq $transformedlabel) {write-host "no destination mapping for source field $($field.label)"; continue;}
        if (-not $field.value -or $null -eq $field.value -or ([string]::IsNullOrWhiteSpace($field.value))) {
            write-host "no source value for $($field.label)";
            # if empty + required, make sure we either have a constant mapped or prompt user for input.
            if ($true -eq $destTranslationFieldRequired) {
                if ($CONSTANTS | where-object {$_.to_label -eq $transformedlabel}){
                    write-host "constant value of $($($CONSTANTS | where-object {$_.to_label -eq $transformedlabel} | select-object -first 1).literal) configured for required field $transformedlabel, using that value for required field."
                    continue
                }
                write-host "no value for REQUIRED $($field.label) => $transformedlabel"
                $field.value = "None"
            } else {
                write-host "no value for optional $($field.label) => $transformedlabel"
                continue
            }
        # pre-process listselect source values as human-readable from sources
        } elseif ($field.value -ilike '*list_id*'){
            $precastValue=$field.value;
            $decodedListValue = SafeDecode $field.value
            $listItemIds = @($decodedListValue.list_ids)
            $listItemId = if ($listItemIds.Count -gt 0) { $listItemIds[0] } else { $null }
            $humanValue = $null
            if ($null -ne $listItemId) {
                $humanValue = $($(get-hudulists).list_items | where-object {$_.id -eq $listItemId} | select-object -first 1).name
            }
            $field.value = $humanValue
            Write-Host "non-empty source val appears to contain listIDs; Raw val '$($precastValue)' as $destFieldType... $($field.value)" -foregroundColor DarkCyan
        }
        if (Is-BlankValue $field.value) {
            if ($true -eq $destTranslationFieldRequired) {
                if ($CONSTANTS | where-object {$_.to_label -eq $transformedlabel}){
                    write-host "decoded source value for $($field.label) is blank, but a constant is configured for required field $transformedlabel. The constant will be applied later."
                    continue
                }
                write-host "decoded source value is blank for REQUIRED $($field.label) => $transformedlabel"
                $field.value = "None"
            } else {
                write-host "decoded source value is blank for optional $($field.label) => $transformedlabel"
                continue
            }
        }
        # handle listselect item-level mappings if present
        $listMapping = $null
        if ($ListSelectEquivilencyMaps.Keys -contains $transformedlabel) {
            $valueEquivilencies = $ListSelectEquivilencyMaps[$transformedlabel]
            $listMapping        = Convert-ToListSelectMappingHashtable -InputObject $valueEquivilencies.Mapping
        } else {
            $valueEquivilencies = $null
        }
        if (-not $valueEquivilencies -or $null -eq $listMapping) {
        # destination field-type validation and post-processing
            write-host "No list mapping for $($field.label) => $transformedlabel, continuing onto destination-specific ($destFieldType) validation and casting."
            if ($true -eq $stripHTML) {
                $field.value="$(Remove-HtmlTags -InputString "$($field.value)")"
            }
            if ($destFieldType -eq "Number"){
                $precastValue=$field.value
                $numericValue = Get-CastIfNumeric -Value $field.value
                if ($null -eq $numericValue) {
                    $digitsOnly = "$($field.value)" -replace '\D+', ''
                    if (-not [string]::IsNullOrWhiteSpace($digitsOnly)) {
                        $numericValue = Get-CastIfNumeric -Value $digitsOnly
                    }
                }
                $field.value = $numericValue
                Write-Host "non-empty source val on Number target; Casting '$($precastValue)' as int...$($field.value)"
            } elseif ($destFieldType -eq "CheckBox"){
                $precastValue=$field.value; $field.value = $(Get-CastIfBoolean $field.value -allowFuzzy $true) ?? $null
                Write-Host "non-empty source val on CheckBox/Boolean target; Casting '$($precastValue)' as bool...$($field.value)"
            } elseif ($destFieldType -eq "Date"){
                $precastValue=$field.value; $field.value = $(Get-CoercedDate -InputDate "$($field.value)" -OutputFormat 'MM/DD/YYYY') ?? $null;
                Write-Host "non-empty source val on Date target; Casting '$($precastValue)' as date...$($field.value)"
            } elseif ($destFieldType -ieq "Website"){
                $precastValue=$field.value; $field.value = Normalize-WebURL -Url "$($field.value)";
                Write-Host "non-empty source val on Website target; Normalizing '$($precastValue)' as URL...$($field.value)"
            } elseif ($destFieldType -eq "ListSelect" -and $valueEquivilencies -and (Get-CastIfBoolean $valueEquivilencies.add_listitems) -and -not [string]::IsNullOrWhiteSpace([string]$field.value)){
                $precastValue = "$($field.value)".Trim()
                Write-Host "non-empty source val on ListSelect target with add-list-items enabled; ensuring '$precastValue' exists in list id $($valueEquivilencies.list_id)..."
                $listCache = Refresh-ListCache
                $field.value = Ensure-HuduListItemByName -ListId $valueEquivilencies.list_id -Name $precastValue -listNameExistsByListId $listCache
                Write-Host "ListSelect target ensured '$precastValue' as '$($field.value)'"
            }
            if ($null -eq $field.value -or ([string]::IsNullOrWhiteSpace([string]$field.value) -and $destFieldType -ne "CheckBox")) {
                Write-Host "No usable value remains for $($field.label) => $transformedlabel after $destFieldType validation; leaving it empty."
                continue
            }
            $field.value = Sanitize-TransferValue -Value $field.value
            $transformedFields += @{$transformedlabel = $field.value}
        } else {
            # mapping for non-empty individual listitems [list_id => human readable user-mapping] for individual listselect source fields
            if ([string]::IsNullOrWhiteSpace($field.value)){continue}
            $result = Set-MappedListSelectItemFromuserMapping -Mapping $listMapping -RawValue $field.value -SourceListItemMap $sourceListItemMap -FieldLabel $field.label
            if ($result.MatchFound) {
                Write-Host "$transformedlabel value '$($field.value)' mapped to listselect item '$($result.Key)'"
                $transformedFields += @{ $transformedlabel = (Sanitize-TransferValue -Value $result.Key) }
            } elseif (Get-CastIfBoolean $valueEquivilencies.add_listitems) {
                write-host "List item not in range, adding $($field.value) to list id $($valueEquivilencies.list_id)..." -ForegroundColor Yellow
                $listCache = Refresh-ListCache
                $field.value = Ensure-HuduListItemByName -ListId $valueEquivilencies.list_id -Name "$($field.value)".Trim() -listNameExistsByListId $listCache
                $field.value = Sanitize-TransferValue -Value $field.value
                $transformedFields += @{ $transformedlabel = $field.value }
            } else {Write-Host "No value matches for list id $($valueEquivilencies.list_id) from '$($field.value)' / '$($result.Normalized)'; not configured to add list items, so leaving empty."}
        }
        # mask logging/output for password fields but still process them
        if ($destFieldType -ilike "Password"){
            write-host "$($field.label) => *** [masked password] for value"
        } else {
            write-host "$($field.label) => $transformedlabel for value $($field.value)"
        }
    }
    # handle any constants that should be applied regardless of source value presence, but only if dest field doesn't already have a value from source mapping ( to avoid clobbering )
    if ($CONSTANTS -and $CONSTANTS.Count -gt 0) {
        foreach ($c in $CONSTANTS) {
            if (-not ($transformedFields | Where-Object {$_.Keys | Where-Object { $_ -ieq $c.to_label }})) {
                $transformedFields += @{ $c.to_label = (Sanitize-TransferValue -Value $c.literal) }
            } else {
                write-host "constant mapping for $($c.to_label) is configured but destination field already has a value from source mapping, skipping constant value assignment of $($c.literal)"
            }
        }
    }

    # seperate section for meta-mapping address source fields to addressdata target
    foreach ($kv in $addressMapsByDest.GetEnumerator()) {
        $destLabel = $kv.Key
        $addrMap   = $kv.Value

        $addr1 = Get-FieldValueByLabel $originalasset.fields $addrMap.address_line_1.from
        $addr2 = Get-FieldValueByLabel $originalasset.fields $addrMap.address_line_2.from
        $city  = Get-FieldValueByLabel $originalasset.fields $addrMap.city.from
        $state = Get-FieldValueByLabel $originalasset.fields $addrMap.state.from
        $zip   = Get-FieldValueByLabel $originalasset.fields $addrMap.zip.from
        $cntry = Get-FieldValueByLabel $originalasset.fields $addrMap.country_name.from

        $addr1 = Sanitize-TransferValue -Value $addr1
        $addr2 = Sanitize-TransferValue -Value $addr2
        $city  = Sanitize-TransferValue -Value $city
        $state = Normalize-Region $state
        $zip   = Normalize-Zip    $zip
        $cntry = Normalize-CountryName $cntry
        $state = Sanitize-TransferValue -Value $state
        $zip   = Sanitize-TransferValue -Value $zip
        $cntry = Sanitize-TransferValue -Value $cntry

        if ($addr1 -or $addr2 -or $city -or $state -or $zip -or $cntry) {
            $NewAddress = [ordered]@{
                address_line_1 = $addr1
                city           = $city
                state          = $state
                zip            = $zip
                country_name   = $cntry
            }
            if ($addr2) { $NewAddress['address_line_2'] = $addr2 }
            $transformedFields += @{ $destLabel = $NewAddress }
        }
    }


    if ($sourceassetlayout.linkables -and $sourceassetlayout.linkables.keys.count -gt 0){
        Write-host "Getting linkable items for asset $($originalasset.name) from $($sourceassetlayout.linkables.keys.count) potentially linkable"
        $linkableToAssetInfo = Get-RelinkableRelationsForAsset -sourceAsset $originalasset -labelLinkMap $sourceassetlayout.linkables
    }
    # map custom smooshed fields ( notes, richtext, whatever we smooshed to in map)
    if ($true -eq $mappingtosmooshed) {
        $smooshTargetLabel = [string]$sourcedestlabels["SMOOSH"]
        if ([string]::IsNullOrWhiteSpace($smooshTargetLabel)) {
            throw "SMOOSH source fields were configured, but no SMOOSH destination target was found in the mapping."
        }
        Write-Host "Building SMOOSH for '$($originalasset.name)' into '$smooshTargetLabel' from $($SMOOSHLABELS.Count) source field(s)."
        $valueToAdd = "$(Set-SmooshAssetFieldsToField -sourceAsset $originalasset -smooshsource $SMOOSHLABELS -includeBlanks $IncludeBlanksDuringSmoosh)"
        # if linkables, smoosh in too.
        if ($describeRelatedInSmoosh -and $true -eq $describeRelatedInSmoosh){
            $describerelated=Get-SmooshedLinkableDescription -linkableObjects $linkableToAssetInfo
            $valueToAdd="$describerelated<br>$valueToAdd"
            if ($true -eq $excludeHTMLinSMOOSH){$valueToAdd = Remove-HtmlTags -InputString $valueToAdd }
        }
        $valueToAdd = Sanitize-TransferValue -Value $valueToAdd
        if ([string]::IsNullOrWhiteSpace([string]$valueToAdd)) {
            Write-Host "SMOOSH produced an empty value for '$smooshTargetLabel' on asset '$($originalasset.name)'." -ForegroundColor Yellow
        } else {
            Write-Host "SMOOSH produced $($valueToAdd.Length) characters for '$smooshTargetLabel' on asset '$($originalasset.name)'."
        }
        $transformedFields += @{ $smooshTargetLabel = $valueToAdd }
    }

    $newAssetRequest = @{
        Name            = (Sanitize-TransferValue -Value ($NewAssetName ?? $originalasset.name))
        CompanyId       = $originalasset.company_id
        AssetLayoutId   = $destassetlayout.id
    }

    # Merge on match if user-elected to do so, with source and dest field values combined according to selected merge mode (fill blanks, prefer source, concat)
    if ($null -ne $matchedmap -and $matchedmap.count -gt 0){
        write-host "Merging transformed fields with matched existing asset fields..."
        $transformedMap = Convert-FieldArrayToMap $transformedFields 
        $finalMap = Merge-HuduFieldMaps `
            -SourceMap $transformedMap -DestMap $matchedMap -LayoutFields $destassetlayout.fields -Mode $mergeMode `
            -StampProvenance:$true -SourceStamp "From $($sourceassetlayout.name) " -DestStamp   "Existing $($destassetlayout.name) "
        $newAssetRequest["Fields"] = LabelValueMapToFields -Map $finalMap -LayoutFields $destassetlayout.fields
        $newAssetRequest["Id"]     = $match.id
    } elseif ($transformedFields -and $transformedFields.count -gt 0){
        $newAssetRequest["Fields"]=$transformedFields
        write-host $($($transformedFields | convertto-json -depth 5).ToString())
    }

    # prepare any typical asset properties, falling back to a match if a match is present + configured for merge
    $propPairs = @(
        @{ Dest = 'PrimarySerial';       Source = 'primary_serial' }
        @{ Dest = 'PrimaryMail';         Source = 'primary_mail' }
        @{ Dest = 'PrimaryModel';        Source = 'primary_model' }
        @{ Dest = 'PrimaryManufacturer'; Source = 'primary_manufacturer' }
    )
    foreach ($pairing in $propPairs) {
        if ($null -ne $matchedMap -and $matchedMap.count -gt 0){
            write-host "using matched asset for fallback to common property $($pairing.Source) since merging on match is enabled"
            $commonPropValue = $originalAsset.($pairing.Source) ?? $match.($pairing.Source)
        } else {
            $commonPropValue = $originalAsset.($pairing.Source)
        }
        if (-not [string]::IsNullOrEmpty("$commonPropValue")) {
            Write-Host "using value $commonPropValue from source $($pairing.source)->$($pairing.dest)"
            $newAssetRequest[$pairing.Dest] = $commonPropValue
        } else {
            Write-Host "skipping empty value for common-property, $($pairing.source)"             
        }
    }
    $newAssetRequest = Sanitize-TransferValue -Value $newAssetRequest
    # update or create, depending on if we had a match or not
    try {
        if ($null -ne $newAssetRequest.id -and $newAssetRequest.id -gt 0){
            write-host "Prepared asset update for '$($newAssetRequest.Name)' with $(@($newAssetRequest.Fields).Count) field value(s)."
            $newAsset = $(set-huduasset @newAssetRequest)
            $newAsset = $newAsset.asset ?? $newAsset
            write-host "updated asset $($newAsset.id)"
        } else {
            write-host "Prepared asset create for '$($newAssetRequest.Name)' with $(@($newAssetRequest.Fields).Count) field value(s)."
            $newAsset = $(new-huduasset @newAssetRequest)
            $newAsset = $newAsset.asset ?? $newAsset
            write-host "Created asset $($newAsset.id)"
        }
    } catch {
        Write-ErrorObjectsToFile -ErrorObject @{Err=$_; request=$newAssetRequest} -Name "$($newAssetRequest.name)$(if ($null -ne $newAssetRequest.id -and $newAssetRequest.id -gt 0) {"-update-$($newAssetRequest.id)"} else {"-create"})"
        continue
    }

    if (-not $newAsset -or $null -eq $newAsset) {
        Write-ErrorObjectsToFile -ErrorObject $newAssetRequest -Name "NC-$($newAssetRequest.name)"
        $totalcounts.errored=$totalcounts.errored+1
        continue
    }
    if ($null -ne $newAssetRequest.id -and $newAssetRequest.id -gt 0){
        write-host "updated asset $($newasset.id), no need to archive matched target asset (even if the matching source was archived.)"
    } else {
        # archive new asset if original was archived
        if ($originalasset.archived -eq $true) {
            Set-HuduAssetArchive -CompanyId $newAsset.company_id -Id $newAsset.id -Archive $true
            $totalcounts.assetsarchived=$totalcounts.assetsarchived+1
        }
        # archive source asset if configured to do so
        if ($archivesource -eq $true) {
            Set-HuduAssetArchive -CompanyId $originalasset.company_id -Id $originalasset.id -Archive $true
            $totalcounts.assetsarchived=$totalcounts.assetsarchived+1
        }
    }
    $totalcounts.assetsmoved=$totalcounts.assetsmoved+1
    write-host "created asset $($newasset.id), adding relations now."
    # add relations

    $sourceToables  = $($($allrelations | where-object {$_.toable_type -eq 'Asset' -and $originalasset.id -eq $_.toable_id }) ?? @())
    write-host "$($sourceToables.count) toable relations"
    $sourceFromables  = $($($allrelations | where-object {$_.fromable_type -eq 'Asset' -and $originalasset.id -eq $_.fromable_id }) ?? @())
    write-host "$($sourceFromables.count) fromable relations"
    $relationsTo = $sourceToables | Where-Object { $_.toable_id -eq $originalasset.id }
    
    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
    foreach ($rel in $relationsTo) {
        try {
            $newToable=New-HuduRelation -FromableType $rel.fromable_type -FromableId $rel.fromable_id -ToableType "Asset" -ToableId $newAsset.id
            write-host "created toable rel $($newToable.id)"
            $totalcounts.toablescreated= if ($newToable) {$totalcounts.toablescreated+1} else {$totalcounts.toablescreated}
        } catch {
            Write-ErrorObjectsToFile -ErrorObject @{Err= $_; From = $relationsFrom; To=$relationsTo} -Name "NCREL-TOABLE-$($newasset.name)"
        }
    }
    $relationsFrom = $sourceFromables | Where-Object { $_.fromable_id -eq $originalasset.id }
    foreach ($rel in $relationsFrom) {
        try {
            $newFromable=New-HuduRelation -FromableType "Asset" -FromableId $newAsset.id -ToableType $rel.toable_type -ToableId $rel.toable_id
            write-host "created fromable rel $($newFromable.id)"
            $totalcounts.fromablescreated= if ($newFromable) {$totalcounts.fromablescreated+1} else {$totalcounts.fromablescreated}
        } catch {
            Write-ErrorObjectsToFile -ErrorObject @{Err= $_; From = $relationsFrom; To=$relationsTo} -Name "NCREL-FROMABLE-$($newasset.name)"
        }            
    }
    # add assettag linking regardless of match/merge or made assets
    if ($linkableToAssetInfo -and $linkableToAssetInfo.count -gt 0){
        if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
        write-host "Asset has external asset links, relinking $($linkableToAssetInfo.count) for $($originalasset.name)"
        foreach ($linkableToAsset in $linkableToAssetInfo) {
            $linkedAsset=$linkableToAsset.LinkedAsset
            if (-not $linkableToAsset.LinkedAsset) {continue}
            try {
                $newToable=New-HuduRelation -FromableType 'Asset' -ToableType "Asset" -FromableId $LinkedAsset.id -ToableID $newAsset.id
                $totalcounts.toablescreated= if ($newToable) {$totalcounts.toablescreated+1} else {$totalcounts.toablescreated}
                write-host "created asset-toable rel $($newToable.id)"
            } catch {
                $totalcounts.errored=$totalcounts.errored+1
                Write-ErrorObjectsToFile -ErrorObject @{Err = $_; From = $relationsFrom; To=$relationsTo} -Name "NCREL-AL-$($newasset.name)"
            }
        }
    }
    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}

    # relink all photos, public photos, uploads, and passwords for asset if applicable, with error handling to log any failures but continue processing rest of assets and relations
    $relatedUploads = $null; $relatedPhotos = $null; $relatedPublicPhotos = $null; $relatedPasswords = $null;
    $relatedPasswords = $allpasswords | where-object {$_.passwordable_id -eq $originalasset.id -and $_.passwordable_type -eq 'Asset'};
    $relatedPhotos = $allphotos | where-object {$_.photoable_id -eq $originalasset.id -and $_.photoable_type -eq 'Asset'};
    $relatedPublicPhotos = $allPublicPhotos | where-object {$_.record_id -eq $originalasset.id -and $_.record_type -eq 'Asset'};
    $relateduploads = $allUploads | where-object {$_.uploadable_id -eq $originalasset.id -and $_.uploadable_type -eq 'Asset'};
    Write-Host "Checking for and relinking photos ($($relatedPhotos.count)), public photos ($($relatedPublicPhotos.count)), uploads ($($relatedUploads.count)), and passwords ($($relatedPasswords.count)) for asset..."


    $relatedPasswords | ForEach-Object {
        try {
            Set-HuduPassword -Id $_.id -PasswordableId $newAsset.id -PasswordableType 'Asset' -description "$($_.description)`n--Relinked to asset $($originalasset.id) from layout $($sourceassetlayout.name)"
            write-host "relinked password $($_.id) to asset $($newAsset.id)"
            $totalcounts.passwordsRelinked = $totalcounts.passwordsRelinked+1
        } catch {
            Write-ErrorObjectsToFile -ErrorObject @{Err = $_; PasswordId = $_.id; AssetId = $newAsset.id} -Name "NCPASS-$($newasset.name)"
        }
    }
    $relatedPhotos | ForEach-Object {
        try {
            Set-HuduPhoto -Id $_.id -photoableID $newAsset.id -photoableType 'Asset' -caption "$($_.caption)`n--Relinked to asset $($originalasset.id) from layout $($sourceassetlayout.name)"
            write-host "relinked photo $($_.id) to asset $($newAsset.id)"
            $totalcounts.photosRelinked = $totalcounts.photosRelinked+1
        } catch {
            Write-ErrorObjectsToFile -ErrorObject @{Err = $_; PhotoId = $_.id; AssetId = $newAsset.id} -Name "NCPHOTO-$($newasset.name)"
        }
    }
    $relatedpublicPhotos | ForEach-Object {
        try {
            Set-HuduPublicPhoto -Id $_.numeric_id -record_id $newAsset.id -PhotableType 'Asset'
            write-host "relinked public photo $($_.numeric_id) to asset $($newAsset.id)"
            $totalcounts.publicPhotosRelinked = $totalcounts.publicPhotosRelinked+1
        } catch {
            Write-ErrorObjectsToFile -ErrorObject @{Err = $_; PublicPhotoId = $_.id; AssetId = $newAsset.id} -Name "NCPUBPHOTO-$($newasset.name)"
        }
    }
    if ($huduVersion -and $huduVersion -ge "2.39.0"){
        $outpath = Get-EnsuredPath -path "tempdownloads"
        $relatedUploads | ForEach-Object {
            try {
                $download = get-huduuploads -id $_.id -download -outdir $outpath; $download = $download.upload ?? $download;
                if ($null -ne $download.localPath){
                    new-huduupload -uploadable_id $newAsset.id -uploadable_type 'Asset' -FilePath $download.localpath
                }
                write-host "relinked upload $($_.id) to asset $($newAsset.id)"
                $totalcounts.uploadsRelinked = $totalcounts.uploadsRelinked+1
            } catch {
                Write-ErrorObjectsToFile -ErrorObject @{Err = $_; UploadId = $_.id; AssetId = $newAsset.id} -Name "NCUPLOAD-$($newasset.name)"
            }
        }
    }
}
    Write-host "wrap-up" -ForegroundColor cyan

    if ([string]::IsNullOrWhiteSpace($RenameSourceLayoutTo)) {$RenameSourceLayoutTo = $sourceassetlayout.name}

    if ($RenameSourceLayoutTo -and $RenameSourceLayoutTo -ne $sourceassetlayout.name){
        Set-HuduAssetLayout -id $sourceassetlayout.id -Name $RenameSourceLayoutTo
    }
    if ($true -eq $setsourceassetsarchived) {
        foreach ($originalasset in $($sourceassets | where-object {$_.archived -ne $true})) {
            $result=Set-HuduAssetArchive -id $originalasset.id -CompanyId $originalasset.company_id -archive $true
            $totalcounts.assetsarchived=$(if ($result) {$totalcounts.assetsarchived+1} else {$totalcounts.assetsarchived})
        }
    }
    foreach ($entry in $totalcounts.GetEnumerator()) {Write-Host "$($entry.Key): $($entry.Value)" -ForegroundColor DarkCyan}
    return $totalcounts
}
function New-TransferReviewSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [psobject]$SourceLayout,

        [Parameter(Mandatory)]
        [psobject]$DestLayout,

        [Parameter(Mandatory)]
        [string]$MergeOption,

        [Parameter(Mandatory)]
        [bool]$ArchivePreference,

        [Parameter(Mandatory)]
        [string]$RenameSourceLayoutTo,

        [Parameter()]
        [psobject]$SourceAssetFilter,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$MappingEntries,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$ConstantEntries,

        [Parameter()]
        [string[]]$SmooshSourceLabels = @(),

        [Parameter()]
        [psobject]$SmooshTargetEntry,

        [Parameter()]
        [string[]]$SkippedFieldLabels = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [array]$MatchCriteria = @(),

        [Parameter()]
        [array]$PerJobSettingSummaries = @(),

        [Parameter(Mandatory)]
        [string]$MapFilePath,
        
        [Parameter()]
        [AllowEmptyCollection()]
        [array]$relinkedFields
    )

    $apiKeyPreview = if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        '[not set]'
    } elseif ($ApiKey.Length -le 4) {
        ('*' * $ApiKey.Length)
    } else {
        ('*' * ($ApiKey.Length - 4)) + $ApiKey.Substring($ApiKey.Length - 4)
    }

    $relinkedFieldsSummary = @('Relinked Fields:')
    if ($relinkedFields -and $relinkedFields.Count -gt 0) {
        foreach ($field in $relinkedFields) {
            $relinkedFieldsSummary += ('- {0}' -f "$($field.label) (ID: $($field.id)) will be relinked as Relationships to respective $($(get-huduassetlayouts -id $field.linkable_id).Name) assets")
        }
    } else {
        $relinkedFieldsSummary += '- N/A'
    }

    $lines = @(
        'Please review this transfer plan before anything runs.',
        '',
        'Transfer Overview',
        ('- Base URL: {0}' -f $BaseUrl),
        ('- API key: {0}' -f $apiKeyPreview),
        ('- Source layout: {0} [ID {1}]' -f $SourceLayout.Name, $SourceLayout.id),
        ('- Destination layout: {0} [ID {1}]' -f $DestLayout.Name, $DestLayout.id),
        ('- Merge behavior on matched assets: {0}' -f (Get-MergeOptionSummaryLabel -Value $MergeOption)),
        ('- Custom matching criteria: {0}' -f $(if (@($MatchCriteria).Count -gt 0) { 'Enabled' } else { 'Default name matching' })),
        ('- Rename source layout to: {0}' -f $RenameSourceLayoutTo),
        ('- Archive remaining source assets after transfer: {0}' -f (Convert-BoolToYesNo $ArchivePreference)),
        ('- Source asset filter: {0}' -f $(if ($SourceAssetFilter -and $SourceAssetFilter.Enabled) { "when '$($SourceAssetFilter.FieldLabel)' is '$($SourceAssetFilter.DisplayValue ?? $SourceAssetFilter.Value)' ($($SourceAssetFilter.MatchingCount) matching)" } else { 'None' })),
        ('- Mapping file: {0}' -f $MapFilePath)
    )

    foreach ($item in $relinkedFieldsSummary) {
        $lines += $item
    }

    $lines += 'Direct Field Mappings'
    if (@($MappingEntries | Where-Object { $_.from -ne 'SMOOSH' }).Count -gt 0) {
        foreach ($entry in ($MappingEntries | Where-Object { $_.from -ne 'SMOOSH' })) {
            $lines += '- ' + (Convert-MappingEntryToSummaryLine -Entry $entry)
        }
    } else {
        $lines += '- None'
    }
    $lines += ''

    $lines += 'Constant Values'
    if (@($ConstantEntries).Count -gt 0) {
        foreach ($entry in $ConstantEntries) {
            $lines += ('- {0} <= "{1}"' -f $entry.to_label, (Get-PreviewText -Value $entry.literal))
        }
    } else {
        $lines += '- None'
    }
    $lines += ''

    $lines += 'SMOOSH Configuration'
    if ($null -ne $SmooshTargetEntry) {
        $lines += ('- Target field: {0}' -f $SmooshTargetEntry.to)
        $lines += ('- Source fields: {0}' -f $(if (@($SmooshSourceLabels).Count -gt 0) { $SmooshSourceLabels -join ', ' } else { 'None' }))
    } else {
        $lines += '- Not used'
    }
    $lines += ''

    $lines += 'Custom Matching Criteria'
    if (@($MatchCriteria).Count -gt 0) {
        foreach ($criterion in ($MatchCriteria | Sort-Object -Property Order)) {
            $lines += ('- {0}. {1} [{2}]' -f $criterion.Order, $criterion.Label, ($criterion.MatchModeLabel ?? 'Direct match (case insensitive)'))
        }
    } else {
        $lines += '- Not used; default same-company name matching will be used'
    }
    $lines += ''

    $lines += 'Skipped Destination Fields'
    if (@($SkippedFieldLabels).Count -gt 0) {
        foreach ($fieldLabel in $SkippedFieldLabels) {
            $lines += ('- {0}' -f $fieldLabel)
        }
    } else {
        $lines += '- None'
    }
    $lines += ''

    $lines += 'Per-Job Settings'
    if (@($PerJobSettingSummaries).Count -gt 0) {
        foreach ($setting in $PerJobSettingSummaries) {
            $lines += ('- {0}: {1}' -f $setting.Name, (Convert-BoolToYesNo $setting.Value))
        }
    } else {
        $lines += '- None'
    }

    return ($lines -join "`r`n")
}

function layout2layout{
param (
    [string]$sourceLayoutName = "",
    [string]$targetLayoutName = "",
    [string]$SourceAssetFilterField = $null,
    [string]$SourceAssetFilterValue = $null,
    [bool]$SourceAssetFilterValueIsBlank = $false,
    [Nullable[int]]$SourceAssetFilterListId = $null
)

    # usage- move assets between same-field layouts
    # particularly useful for un-splitting split-configurations from ITG

    if ([string]::isnullorempty($sourceLayoutName) -or [string]::isnullorempty($targetLayoutName)) {
        write-error "sourceLayoutName and targetLayoutName parameters are required"
        exit 1
    }
    write-verbose "starting layout to layout move from '$sourceLayoutName' to '$targetLayoutName'"
    
    $results = $results ?? @()
    $sourcelayout = Get-HuduASsetlayouts -name $sourceLayoutName | select-object -first 1
    $targetLayout = Get-HuduASsetlayouts -name $targetLayoutName | select-object -first 1
    $sourceLayout = $sourcelayout.asset_layout ?? $sourcelayout
    $targetLayout = $targetLayout.asset_layout ?? $targetLayout

    $sourceLayoutID= $sourceLayout.id
    $targetLayoutId = $targetLayout.id
    if (-not $sourceLayoutID -or -not $targetLayoutId) {
        write-error "source or target layout not found"
        exit 1
    }

    $sourceFilterFieldInfo = $null
    $effectiveSourceFilterListId = $SourceAssetFilterListId
    if (-not [string]::IsNullOrWhiteSpace($SourceAssetFilterField)) {
        $sourceFilterFieldInfo = $sourceLayout.fields |
            Where-Object { $_.label -eq $SourceAssetFilterField } |
            Select-Object -First 1

        if (($null -eq $effectiveSourceFilterListId -or $effectiveSourceFilterListId -le 0) -and $sourceFilterFieldInfo -and $sourceFilterFieldInfo.list_id) {
            $effectiveSourceFilterListId = [int]$sourceFilterFieldInfo.list_id
        }
    }

    $directFilterState = @{
        ListItems = $null
    }
    function Get-LayoutToLayoutFilterValue {
        param(
            [Parameter(Mandatory)]
            [psobject]$Asset,

            [Parameter(Mandatory)]
            [string]$FieldLabel
        )

        $rawValue = ($Asset.fields | Where-Object { $_.label -eq $FieldLabel } | Select-Object -First 1).value
        if ($null -eq $rawValue) {
            return ''
        }

        if ("$rawValue" -ilike '*list_id*') {
            try {
                $listItemIds = @(($rawValue | ConvertFrom-Json -ErrorAction Stop).list_ids)
                if ($listItemIds.Count -gt 0) {
                    if ($null -eq $directFilterState.ListItems) {
                        if ($effectiveSourceFilterListId -and $effectiveSourceFilterListId -gt 0) {
                            $directFilterState.ListItems = @((Get-HuduLists -Id $effectiveSourceFilterListId).list_items)
                        } else {
                            $directFilterState.ListItems = @((Get-HuduLists).list_items)
                        }
                    }

                    $listItemNames = @(
                        foreach ($listItemId in $listItemIds) {
                            $directFilterState.ListItems |
                                Where-Object { $_.id -eq $listItemId } |
                                Select-Object -ExpandProperty name -First 1 -ErrorAction SilentlyContinue
                        }
                    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                    if ($listItemNames.Count -gt 0) {
                        return ($listItemNames -join ', ')
                    }
                }
            }
            catch {
                Write-Verbose "Could not resolve direct-transfer source filter value for '$FieldLabel': $($_.Exception.Message)"
            }
        }

        "$rawValue".Trim()
    }

    function Move-HuduAssetToNewLayout {
        Param ([Int]$targetLayoutId,[Int]$Id)
        $asset = Get-HuduAssets -id $Id; $asset = $asset.asset ?? $asset;
        if (-not $asset) {throw "Asset with id $Id not found"}
        try {$moved = $(Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$($asset.company_id)/assets/$($asset.id)/move_layout" -Body $($([pscustomobject]@{asset_layout_id = $targetLayoutId}) | ConvertTo-Json -Depth 10))
            return $moved
        } catch {
            throw $_
        }
    }

    foreach ($l in $(get-huduassetlayouts -id $sourceLayoutID)){
        write-verbose "starting movements for $($l.name), obtaining assets"
        $allassets = Get-HuduAssets -AssetLayoutId $l.id
        if (-not [string]::IsNullOrWhiteSpace($SourceAssetFilterField) -and ($SourceAssetFilterValueIsBlank -or -not [string]::IsNullOrWhiteSpace($SourceAssetFilterValue))) {
            $unfilteredAssetCount = @($allassets).Count
            $allassets = @(
                $allassets | Where-Object {
                    $candidate = Get-LayoutToLayoutFilterValue -Asset $_ -FieldLabel $SourceAssetFilterField
                    if ($SourceAssetFilterValueIsBlank) {
                        [string]::IsNullOrWhiteSpace($candidate)
                    } else {
                        $candidate -eq $SourceAssetFilterValue
                    }
                }
            )
            $filterValueForLog = if ($SourceAssetFilterValueIsBlank) { '[Blank / Null]' } else { $SourceAssetFilterValue }
            write-verbose "source asset filter applied to direct transfer: when '$SourceAssetFilterField' is '$filterValueForLog'. $(@($allassets).Count) of $unfilteredAssetCount assets will be moved."
        }
        write-verbose "$($allassets.count) assets found, moving to layout id $targetLayoutId"
        foreach ($a in $allassets){
            try {
            $result = $null
            $result = Move-HuduAssetToNewLayout -id $a.id -targetLayoutId $targetLayoutId
            } catch {
                $result = @{
                    assetId = $a.id
                    companyId = $a.company_id
                    status = "error"
                    message = $_.exception.message
                }
                write-verbose "error moving asset id $($a.id) for company id $($a.company_id): $($_.exception.message)" 
            } finally {
                $results += $result
            }

        }
    }
    return $results
}
function Show-TransferReviewDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SummaryText,

        [string]$Title = 'Review Transfer Plan'
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(920,700)
    $form.MinimumSize = New-Object System.Drawing.Size(760,560)
    $form.Topmost = $true

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(12,12)
    $intro.Size = New-Object System.Drawing.Size(880,36)
    $intro.Text = 'Review the full transfer plan below. Choose Run Transfer to continue, or Cancel to stop before any changes are made.'
    $form.Controls.Add($intro)

    $summaryBox = New-Object System.Windows.Forms.TextBox
    $summaryBox.Location = New-Object System.Drawing.Point(12,56)
    $summaryBox.Size = New-Object System.Drawing.Size(880,560)
    $summaryBox.Multiline = $true
    $summaryBox.ReadOnly = $true
    $summaryBox.ScrollBars = 'Both'
    $summaryBox.WordWrap = $false
    $summaryBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $summaryBox.Text = $SummaryText
    $form.Controls.Add($summaryBox)

    $runButton = New-Object System.Windows.Forms.Button
    $runButton.Location = New-Object System.Drawing.Point(692,625)
    $runButton.Size = New-Object System.Drawing.Size(95,30)
    $runButton.Text = 'Run Transfer'
    $runButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($runButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(797,625)
    $cancelButton.Size = New-Object System.Drawing.Size(95,30)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $runButton
    $form.CancelButton = $cancelButton

    return ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
}

function Show-TransferMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Title = 'Hudu Asset Layout Transfer',

        [ValidateSet('Info','Warning','Error','Question')]
        [string]$Kind = 'Info',

        [switch]$YesNo
    )

    Add-Type -AssemblyName System.Windows.Forms

    $icon = switch ($Kind) {
        'Warning'  { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error'    { [System.Windows.Forms.MessageBoxIcon]::Error }
        'Question' { [System.Windows.Forms.MessageBoxIcon]::Question }
        default    { [System.Windows.Forms.MessageBoxIcon]::Information }
    }

    $buttons = if ($YesNo) {
        [System.Windows.Forms.MessageBoxButtons]::YesNo
    } else {
        [System.Windows.Forms.MessageBoxButtons]::OK
    }

    $dialogResult = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        $buttons,
        $icon
    )

    if ($YesNo) {
        return $dialogResult
    }
}

function Normalize-HuduBaseUrl {
    [CmdletBinding()]
    param([string]$Value)

    $normalized = [string]$Value
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    $normalized = $normalized.Trim() -replace '[\\/]+$', ''
    if ($normalized -notmatch '^(?i)https?://') {
        $normalized = "https://$normalized"
    }

    try {
        $uri = [System.Uri]$normalized
    }
    catch {
        return $null
    }

    if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        return $null
    }

    $uri.GetLeftPart([System.UriPartial]::Authority)
}

function Test-HuduApiKeyFormat {
    [CmdletBinding()]
    param([string]$Value)

    -not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim().Length -eq 24
}

function Get-LayoutChoiceLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Layout)

    $fieldCount = @($Layout.Fields).Count
    $requiredCount = @($Layout.Fields | Where-Object { $_.required -eq $true }).Count

    '{0} [ID {1}] - {2} fields, {3} required' -f $Layout.Name, $Layout.id, $fieldCount, $requiredCount
}

function Show-LayoutPairDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$AssetLayouts
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Choose Layouts'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(820,260)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Topmost = $true
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = $null

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(16,14)
    $intro.Size = New-Object System.Drawing.Size(760,34)
    $intro.Text = 'Choose the source layout to transfer from and the destination layout to transfer into.'
    $form.Controls.Add($intro)

    $sourceLabel = New-Object System.Windows.Forms.Label
    $sourceLabel.Location = New-Object System.Drawing.Point(16,62)
    $sourceLabel.Size = New-Object System.Drawing.Size(130,24)
    $sourceLabel.Text = 'Source layout'
    $form.Controls.Add($sourceLabel)

    $destLabel = New-Object System.Windows.Forms.Label
    $destLabel.Location = New-Object System.Drawing.Point(16,102)
    $destLabel.Size = New-Object System.Drawing.Size(130,24)
    $destLabel.Text = 'Destination layout'
    $form.Controls.Add($destLabel)

    $sourceCombo = New-Object System.Windows.Forms.ComboBox
    $sourceCombo.Location = New-Object System.Drawing.Point(155,58)
    $sourceCombo.Size = New-Object System.Drawing.Size(620,24)
    $sourceCombo.DropDownStyle = 'DropDownList'
    $form.Controls.Add($sourceCombo)

    $destCombo = New-Object System.Windows.Forms.ComboBox
    $destCombo.Location = New-Object System.Drawing.Point(155,98)
    $destCombo.Size = New-Object System.Drawing.Size(620,24)
    $destCombo.DropDownStyle = 'DropDownList'
    $form.Controls.Add($destCombo)

    $layoutLookup = [ordered]@{}
    foreach ($layout in ($AssetLayouts | Sort-Object -Property name)) {
        $label = Get-LayoutChoiceLabel -Layout $layout
        $layoutLookup[$label] = $layout
        [void]$sourceCombo.Items.Add($label)
    }

    $refreshDestOptions = {
        $destCombo.Items.Clear()
        $selectedSource = $layoutLookup[[string]$sourceCombo.SelectedItem]
        foreach ($layout in ($AssetLayouts | Where-Object { $null -eq $selectedSource -or $_.id -ne $selectedSource.id } | Sort-Object -Property name)) {
            [void]$destCombo.Items.Add((Get-LayoutChoiceLabel -Layout $layout))
        }
        if ($destCombo.Items.Count -gt 0) {
            $destCombo.SelectedIndex = 0
        }
    }

    $sourceCombo.add_SelectedIndexChanged($refreshDestOptions)
    if ($sourceCombo.Items.Count -gt 0) {
        $sourceCombo.SelectedIndex = 0
    }

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(575,170)
    $okButton.Size = New-Object System.Drawing.Size(95,30)
    $okButton.Text = 'Continue'
    $okButton.Add_Click({
        if ($null -eq $sourceCombo.SelectedItem -or $null -eq $destCombo.SelectedItem) {
            Show-TransferMessage -Title 'Choose Layouts' -Kind Warning -Message 'Choose both a source and destination layout.' | Out-Null
            return
        }

        $source = $layoutLookup[[string]$sourceCombo.SelectedItem]
        $dest = $layoutLookup[[string]$destCombo.SelectedItem]
        if ($null -eq $source -or $null -eq $dest -or $source.id -eq $dest.id) {
            Show-TransferMessage -Title 'Choose Layouts' -Kind Warning -Message 'The source and destination layouts must be different.' | Out-Null
            return
        }

        $form.Tag = [pscustomobject]@{
            Success      = $true
            SourceLayout = $source
            DestLayout   = $dest
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(680,170)
    $cancelButton.Size = New-Object System.Drawing.Size(95,30)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or $null -eq $form.Tag) {
        return [pscustomobject]@{ Success = $false }
    }

    $form.Tag
}

function Show-InitialTransferOptionsDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$SourceLayout,

        [Parameter(Mandatory)]
        [psobject]$DestLayout
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Transfer Options'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(760,400)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Topmost = $true
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = $null

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(16,14)
    $intro.Size = New-Object System.Drawing.Size(700,50)
    $intro.Text = "Source: $($SourceLayout.Name)`r`nDestination: $($DestLayout.Name)"
    $form.Controls.Add($intro)

    $mergeLabel = New-Object System.Windows.Forms.Label
    $mergeLabel.Location = New-Object System.Drawing.Point(16,82)
    $mergeLabel.Size = New-Object System.Drawing.Size(170,24)
    $mergeLabel.Text = 'Matched asset behavior'
    $form.Controls.Add($mergeLabel)

    $mergeCombo = New-Object System.Windows.Forms.ComboBox
    $mergeCombo.Location = New-Object System.Drawing.Point(205,78)
    $mergeCombo.Size = New-Object System.Drawing.Size(500,24)
    $mergeCombo.DropDownStyle = 'DropDownList'
    foreach ($option in @('Merge-Concat','Merge-FillBlanks','Merge-PreferSource','Skip')) {
        [void]$mergeCombo.Items.Add($option)
    }
    $mergeCombo.SelectedItem = 'Merge-Concat'
    $form.Controls.Add($mergeCombo)

    $renameLabel = New-Object System.Windows.Forms.Label
    $renameLabel.Location = New-Object System.Drawing.Point(16,125)
    $renameLabel.Size = New-Object System.Drawing.Size(170,24)
    $renameLabel.Text = 'Rename source layout to'
    $form.Controls.Add($renameLabel)

    $renameText = New-Object System.Windows.Forms.TextBox
    $renameText.Location = New-Object System.Drawing.Point(205,121)
    $renameText.Size = New-Object System.Drawing.Size(500,24)
    $renameText.Text = $SourceLayout.Name
    $form.Controls.Add($renameText)

    $archiveCheck = New-Object System.Windows.Forms.CheckBox
    $archiveCheck.Location = New-Object System.Drawing.Point(205,165)
    $archiveCheck.Size = New-Object System.Drawing.Size(500,24)
    $archiveCheck.Text = 'Archive remaining source layout assets after transfer'
    $archiveCheck.Checked = $false
    $form.Controls.Add($archiveCheck)

    $customMatchCheck = New-Object System.Windows.Forms.CheckBox
    $customMatchCheck.Location = New-Object System.Drawing.Point(205,198)
    $customMatchCheck.Size = New-Object System.Drawing.Size(500,24)
    $customMatchCheck.Text = 'Choose custom matching criteria after field mapping'
    $customMatchCheck.Checked = $false
    $form.Controls.Add($customMatchCheck)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point(205,232)
    $hint.Size = New-Object System.Drawing.Size(500,52)
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Text = 'Merge-Concat keeps both values where it makes sense. Custom matching lets you choose primary, secondary, and tertiary mapped field matches.'
    $form.Controls.Add($hint)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(505,315)
    $okButton.Size = New-Object System.Drawing.Size(95,30)
    $okButton.Text = 'Continue'
    $okButton.Add_Click({
        $renameValue = if ([string]::IsNullOrWhiteSpace($renameText.Text)) { $SourceLayout.Name } else { $renameText.Text.Trim() }
        $form.Tag = [pscustomobject]@{
            Success              = $true
            MergeOption          = [string]$mergeCombo.SelectedItem
            RenameSourceLayoutTo = $renameValue
            ArchivePreference    = [bool]$archiveCheck.Checked
            CustomMatchingCriteria = [bool]$customMatchCheck.Checked
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(610,315)
    $cancelButton.Size = New-Object System.Drawing.Size(95,30)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or $null -eq $form.Tag) {
        return [pscustomobject]@{ Success = $false }
    }

    $form.Tag
}

function Show-SourceAssetFilterDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$SourceLayout
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Source Asset Filter'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(780,380)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Topmost = $true
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = $null
    $filterState = @{
        SourceAssets = $null
    }
    $blankValueDisplay = '[Blank / Null]'

    $enableCheck = New-Object System.Windows.Forms.CheckBox
    $enableCheck.Location = New-Object System.Drawing.Point(16,16)
    $enableCheck.Size = New-Object System.Drawing.Size(720,24)
    $enableCheck.Text = "Only transfer source assets from '$($SourceLayout.Name)' when a field matches a selected value"
    $form.Controls.Add($enableCheck)

    $fieldLabel = New-Object System.Windows.Forms.Label
    $fieldLabel.Location = New-Object System.Drawing.Point(16,58)
    $fieldLabel.Size = New-Object System.Drawing.Size(160,24)
    $fieldLabel.Text = 'When field'
    $form.Controls.Add($fieldLabel)

    $fieldCombo = New-Object System.Windows.Forms.ComboBox
    $fieldCombo.Location = New-Object System.Drawing.Point(185,54)
    $fieldCombo.Size = New-Object System.Drawing.Size(540,24)
    $fieldCombo.DropDownStyle = 'DropDownList'
    $form.Controls.Add($fieldCombo)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Location = New-Object System.Drawing.Point(16,100)
    $valueLabel.Size = New-Object System.Drawing.Size(160,24)
    $valueLabel.Text = 'Is value'
    $form.Controls.Add($valueLabel)

    $valueCombo = New-Object System.Windows.Forms.ComboBox
    $valueCombo.Location = New-Object System.Drawing.Point(185,96)
    $valueCombo.Size = New-Object System.Drawing.Size(540,24)
    $valueCombo.DropDownStyle = 'DropDownList'
    $form.Controls.Add($valueCombo)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(185,137)
    $statusLabel.Size = New-Object System.Drawing.Size(540,58)
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($statusLabel)

    $matchCountLabel = New-Object System.Windows.Forms.Label
    $matchCountLabel.Location = New-Object System.Drawing.Point(185,205)
    $matchCountLabel.Size = New-Object System.Drawing.Size(540,28)
    $matchCountLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $matchCountLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 90, 120)
    $form.Controls.Add($matchCountLabel)

    $fieldLookup = [ordered]@{}
    $fieldInfoByLabel = @{}
    foreach ($field in ($SourceLayout.Fields | Where-Object { $_.label -and ($_.field_type ?? $_.type) -ne 'AssetTag' } | Sort-Object -Property label)) {
        $fieldType = [string]($field.field_type ?? $field.type ?? 'Text')
        $label = '{0} [{1}]' -f $field.label, $fieldType
        $fieldLookup[$label] = [string]$field.label
        $fieldInfoByLabel[[string]$field.label] = [pscustomobject]@{
            Label = [string]$field.label
            Type  = $fieldType
            ListId = $field.list_id
        }
        [void]$fieldCombo.Items.Add($label)
    }
    $listItemsByListId = @{}

    $getFieldValue = {
        param(
            [psobject]$Asset,
            [string]$FieldLabel
        )

        if ($null -eq $Asset -or [string]::IsNullOrWhiteSpace($FieldLabel)) {
            return $null
        }

        $field = $Asset.fields | Where-Object { $_.label -eq $FieldLabel } | Select-Object -First 1
        if ($null -eq $field) {
            return $null
        }

        $field.value
    }

    $getDisplayValue = {
        param(
            [psobject]$Asset,
            [string]$FieldLabel
        )

        $rawValue = & $getFieldValue -Asset $Asset -FieldLabel $FieldLabel
        if ($null -eq $rawValue) {
            return ''
        }

        if ("$rawValue" -ilike '*list_id*') {
            try {
                $fieldInfo = $fieldInfoByLabel[$FieldLabel]
                $listItemIds = @(($rawValue | ConvertFrom-Json -ErrorAction Stop).list_ids)
                if ($listItemIds.Count -gt 0 -and $null -ne $fieldInfo -and $fieldInfo.Type -eq 'ListSelect' -and $fieldInfo.ListId) {
                    $listIdKey = [string]$fieldInfo.ListId
                    if (-not $listItemsByListId.ContainsKey($listIdKey)) {
                        $listItemsByListId[$listIdKey] = @((Get-HuduLists -Id ([int]$fieldInfo.ListId)).list_items)
                    }

                    $listItemNames = @(
                        foreach ($listItemId in $listItemIds) {
                            $listItemsByListId[$listIdKey] |
                                Where-Object { $_.id -eq $listItemId } |
                                Select-Object -ExpandProperty name -First 1 -ErrorAction SilentlyContinue
                        }
                    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                    if ($listItemNames.Count -gt 0) {
                        return ($listItemNames -join ', ')
                    }
                }
            }
            catch {
                Write-Verbose "Could not resolve list source filter value for '$FieldLabel': $($_.Exception.Message)"
            }
        }

        "$rawValue".Trim()
    }

    $ensureSourceAssetsLoaded = {
        if ($null -ne $filterState.SourceAssets) {
            return $true
        }

        try {
            $statusLabel.Text = "Loading source assets from '$($SourceLayout.Name)'..."
            [System.Windows.Forms.Application]::DoEvents()
            $filterState.SourceAssets = @(Get-HuduAssets -AssetLayoutId $SourceLayout.id)
            return $true
        }
        catch {
            $statusLabel.Text = 'Source assets could not be loaded.'
            Show-TransferMessage -Title 'Source Asset Filter' -Kind Error -Message "Source assets could not be loaded.`r`n`r`n$($_.Exception.Message)" | Out-Null
            return $false
        }
    }

    $getMatchingCount = {
        param(
            [string]$FieldLabel,
            [string]$SelectedValue
        )

        if ($null -eq $filterState.SourceAssets -or [string]::IsNullOrWhiteSpace($FieldLabel)) {
            return 0
        }

        @(
            $filterState.SourceAssets | Where-Object {
                $candidate = & $getDisplayValue -Asset $_ -FieldLabel $FieldLabel
                if ($SelectedValue -eq $blankValueDisplay) {
                    [string]::IsNullOrWhiteSpace($candidate)
                } else {
                    $candidate -eq $SelectedValue
                }
            }
        ).Count
    }

    $updateMatchCountLabel = {
        if (-not $enableCheck.Checked) {
            $matchCountLabel.Text = ''
            return
        }

        $rawFieldLabel = $fieldLookup[[string]$fieldCombo.SelectedItem]
        $selectedValue = [string]$valueCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($rawFieldLabel) -or [string]::IsNullOrWhiteSpace($selectedValue)) {
            $matchCountLabel.Text = ''
            return
        }

        $matchingCount = & $getMatchingCount -FieldLabel $rawFieldLabel -SelectedValue $selectedValue
        $matchCountLabel.Text = ("{0} source asset(s) match this filter." -f $matchingCount)
    }

    $refreshValueOptions = {
        $valueCombo.Items.Clear()
        if (-not $enableCheck.Checked) {
            $statusLabel.Text = 'No source filter will be applied.'
            & $updateMatchCountLabel
            return
        }

        if (-not (& $ensureSourceAssetsLoaded)) {
            return
        }

        $rawFieldLabel = $fieldLookup[[string]$fieldCombo.SelectedItem]
        if ([string]::IsNullOrWhiteSpace($rawFieldLabel)) {
            $statusLabel.Text = 'Choose a source field to load unique values.'
            & $updateMatchCountLabel
            return
        }

        [void]$valueCombo.Items.Add($blankValueDisplay)
        $values = @(
            foreach ($asset in $filterState.SourceAssets) {
                & $getDisplayValue -Asset $asset -FieldLabel $rawFieldLabel
            }
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

        foreach ($value in $values) {
            [void]$valueCombo.Items.Add([string]$value)
        }
        $nonBlankValueCount = @($values).Count
        if ($valueCombo.Items.Count -gt 0) {
            if ($valueCombo.SelectedIndex -lt 0) {
                $valueCombo.SelectedIndex = 0
            }
            $statusLabel.Text = ("Loaded {0} non-empty unique value(s), plus blank/null, from {1} source asset(s)." -f $nonBlankValueCount, @($filterState.SourceAssets).Count)
        } else {
            $statusLabel.Text = 'No non-empty values were found for this field.'
        }
        & $updateMatchCountLabel
    }

    $updateEnabledState = {
        $fieldCombo.Enabled = $enableCheck.Checked
        $valueCombo.Enabled = $enableCheck.Checked
        if (-not $enableCheck.Checked) {
            $valueCombo.Items.Clear()
            $statusLabel.Text = 'No source filter will be applied.'
            & $updateMatchCountLabel
        } elseif ($fieldCombo.Items.Count -gt 0 -and $null -eq $fieldCombo.SelectedItem) {
            $fieldCombo.SelectedIndex = 0
        } else {
            & $refreshValueOptions
        }
    }

    $fieldCombo.add_SelectedIndexChanged($refreshValueOptions)
    $valueCombo.add_SelectedIndexChanged($updateMatchCountLabel)
    $enableCheck.add_CheckedChanged($updateEnabledState)
    $enableCheck.Checked = $false
    & $updateEnabledState

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(525,285)
    $okButton.Size = New-Object System.Drawing.Size(95,30)
    $okButton.Text = 'Continue'
    $okButton.Add_Click({
        if (-not $enableCheck.Checked) {
            $form.Tag = [pscustomobject]@{
                Success       = $true
                Enabled       = $false
                FieldLabel    = $null
                Value         = $null
                MatchingCount = $null
            }
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
            return
        }

        $rawFieldLabel = $fieldLookup[[string]$fieldCombo.SelectedItem]
        $selectedValue = [string]$valueCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($rawFieldLabel) -or [string]::IsNullOrWhiteSpace($selectedValue)) {
            Show-TransferMessage -Title 'Source Asset Filter' -Kind Warning -Message 'Choose both a source field and one of its loaded values, or turn the filter off.' | Out-Null
            return
        }

        $valueIsBlank = ($selectedValue -eq $blankValueDisplay)
        $matchingCount = & $getMatchingCount -FieldLabel $rawFieldLabel -SelectedValue $selectedValue

        $form.Tag = [pscustomobject]@{
            Success       = $true
            Enabled       = $true
            FieldLabel    = $rawFieldLabel
            ListId        = $fieldInfoByLabel[$rawFieldLabel].ListId
            Value         = $(if ($valueIsBlank) { $null } else { $selectedValue })
            DisplayValue  = $(if ($valueIsBlank) { $blankValueDisplay } else { $selectedValue })
            ValueIsBlank  = $valueIsBlank
            MatchingCount = $matchingCount
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(630,285)
    $cancelButton.Size = New-Object System.Drawing.Size(95,30)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or $null -eq $form.Tag) {
        return [pscustomobject]@{ Success = $false }
    }

    $form.Tag
}

function Show-PerJobSettingsDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Questions,

        [bool]$SmooshConfigured
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Per-Job Settings'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(820,380)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Topmost = $true
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = $null

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(16,14)
    $intro.Size = New-Object System.Drawing.Size(760,34)
    $intro.Text = 'Choose the remaining per-job behaviors for this transfer.'
    $form.Controls.Add($intro)

    $checkBoxes = [ordered]@{}
    $y = 58
    foreach ($question in $Questions) {
        $isSmooshQuestion = [string]$question.SettingName -ilike '*SMOOSH*'

        $check = New-Object System.Windows.Forms.CheckBox
        $check.Location = New-Object System.Drawing.Point(20,$y)
        $check.Size = New-Object System.Drawing.Size(330,24)
        $check.Text = $question.SettingName
        $check.Checked = [bool]$question.DefaultValue
        $check.Enabled = ($SmooshConfigured -or -not $isSmooshQuestion)
        $form.Controls.Add($check)

        $desc = New-Object System.Windows.Forms.Label
        $desc.Location = New-Object System.Drawing.Point(365,$y)
        $desc.Size = New-Object System.Drawing.Size(405,44)
        $desc.ForeColor = [System.Drawing.Color]::DimGray
        $desc.Text = $question.Description
        $form.Controls.Add($desc)

        $checkBoxes[$question.VariableName] = $check
        $y += 58
    }

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(585,292)
    $okButton.Size = New-Object System.Drawing.Size(95,30)
    $okButton.Text = 'Continue'
    $okButton.Add_Click({
        $answers = @{}
        foreach ($question in $Questions) {
            $answers[$question.VariableName] = [bool]$checkBoxes[$question.VariableName].Checked
        }
        $form.Tag = [pscustomobject]@{
            Success = $true
            Answers = $answers
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(690,292)
    $cancelButton.Size = New-Object System.Drawing.Size(95,30)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or $null -eq $form.Tag) {
        return [pscustomobject]@{ Success = $false }
    }

    $form.Tag
}

function Show-MatchCriteriaDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$SourceLayout,

        [Parameter(Mandatory)]
        [psobject]$DestLayout,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$MappingEntries
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Custom Matching Criteria'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(920,340)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Topmost = $true
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Tag = $null

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(16,14)
    $intro.Size = New-Object System.Drawing.Size(860,42)
    $intro.Text = 'Choose ordered field-value criteria and how each criterion compares source and destination text.'
    $form.Controls.Add($intro)

    $sourceFieldInfoByLabel = @{}
    foreach ($field in @($SourceLayout.Fields)) {
        if ($field.label) {
            $sourceFieldInfoByLabel[[string]$field.label] = $field
        }
    }

    $destFieldInfoByLabel = @{}
    foreach ($field in @($DestLayout.Fields)) {
        if ($field.label) {
            $destFieldInfoByLabel[[string]$field.label] = $field
        }
    }

    $matchOptions = [ordered]@{}
    $assetNameLabel = 'Asset name <= Source asset name'
    $matchOptions[$assetNameLabel] = [pscustomobject]@{
        Label             = $assetNameLabel
        SourceField       = $null
        DestField         = $null
        SourceListId      = $null
        DestListId        = $null
        SourceIsAssetName = $true
        DestIsAssetName   = $true
    }

    foreach ($entry in @($MappingEntries | Where-Object { $_.from -and $_.to -and $_.from -notin @('SMOOSH','Meta') })) {
        $sourceLabel = [string]$entry.from
        $destLabel = [string]$entry.to
        if ([string]::IsNullOrWhiteSpace($sourceLabel) -or [string]::IsNullOrWhiteSpace($destLabel)) {
            continue
        }

        $label = '{0} <= {1}' -f $destLabel, $sourceLabel
        if ($matchOptions.Contains($label)) {
            continue
        }

        $sourceFieldInfo = $sourceFieldInfoByLabel[$sourceLabel]
        $destFieldInfo = $destFieldInfoByLabel[$destLabel]
        $matchOptions[$label] = [pscustomobject]@{
            Label             = $label
            SourceField       = $sourceLabel
            DestField         = $destLabel
            SourceListId      = $sourceFieldInfo.list_id
            DestListId        = $(if ($entry.list_id) { $entry.list_id } else { $destFieldInfo.list_id })
            SourceIsAssetName = $false
            DestIsAssetName   = $false
        }
    }

    if ($matchOptions.Count -le 1) {
        Show-TransferMessage `
            -Title 'Custom Matching Criteria' `
            -Kind Warning `
            -Message 'No field mappings are available for custom matching yet. Asset name matching will remain available.'
    }

    $noneLabel = '<none>'
    $criteriaCombos = @()
    $modeCombos = @()
    $modeLookup = [ordered]@{
        'Direct match (case insensitive)' = 'DirectCaseInsensitive'
        'Source text includes dest / dest text includes source' = 'ContainsEither'
    }
    $rowDefinitions = @(
        @{ Text = 'Primary match';   Required = $true  },
        @{ Text = 'Secondary match'; Required = $false },
        @{ Text = 'Tertiary match';  Required = $false }
    )

    $criteriaHeader = New-Object System.Windows.Forms.Label
    $criteriaHeader.Location = New-Object System.Drawing.Point(175,58)
    $criteriaHeader.Size = New-Object System.Drawing.Size(430,18)
    $criteriaHeader.Text = 'Criterion'
    $form.Controls.Add($criteriaHeader)

    $modeHeader = New-Object System.Windows.Forms.Label
    $modeHeader.Location = New-Object System.Drawing.Point(620,58)
    $modeHeader.Size = New-Object System.Drawing.Size(250,18)
    $modeHeader.Text = 'Match mode'
    $form.Controls.Add($modeHeader)

    $y = 78
    foreach ($row in $rowDefinitions) {
        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point(16,$y)
        $label.Size = New-Object System.Drawing.Size(145,24)
        $label.Text = $row.Text
        $form.Controls.Add($label)

        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.Location = New-Object System.Drawing.Point(175,($y - 4))
        $combo.Size = New-Object System.Drawing.Size(420,24)
        $combo.DropDownStyle = 'DropDownList'
        if (-not $row.Required) {
            [void]$combo.Items.Add($noneLabel)
        }
        foreach ($optionLabel in $matchOptions.Keys) {
            [void]$combo.Items.Add($optionLabel)
        }
        $combo.SelectedIndex = 0
        $form.Controls.Add($combo)
        $criteriaCombos += $combo

        $modeCombo = New-Object System.Windows.Forms.ComboBox
        $modeCombo.Location = New-Object System.Drawing.Point(620,($y - 4))
        $modeCombo.Size = New-Object System.Drawing.Size(250,24)
        $modeCombo.DropDownStyle = 'DropDownList'
        foreach ($modeLabel in $modeLookup.Keys) {
            [void]$modeCombo.Items.Add($modeLabel)
        }
        $modeCombo.SelectedIndex = 0
        $form.Controls.Add($modeCombo)
        $modeCombos += $modeCombo
        $y += 44
    }

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point(175,210)
    $hint.Size = New-Object System.Drawing.Size(695,36)
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Text = 'Blank source values are skipped. Matching is limited to destination assets in the same company.'
    $form.Controls.Add($hint)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(670,260)
    $okButton.Size = New-Object System.Drawing.Size(95,30)
    $okButton.Text = 'Continue'
    $okButton.Add_Click({
        $selectedLabels = @(
            foreach ($combo in $criteriaCombos) {
                $selected = [string]$combo.SelectedItem
                if (-not [string]::IsNullOrWhiteSpace($selected) -and $selected -ne $noneLabel) {
                    $selected
                }
            }
        )

        if ($selectedLabels.Count -eq 0) {
            Show-TransferMessage -Title 'Custom Matching Criteria' -Kind Warning -Message 'Choose at least a primary matching criterion.' | Out-Null
            return
        }

        if (($selectedLabels | Sort-Object -Unique).Count -ne $selectedLabels.Count) {
            Show-TransferMessage -Title 'Custom Matching Criteria' -Kind Warning -Message 'Each matching criterion can only be selected once.' | Out-Null
            return
        }

        $criteria = @()
        $order = 1
        for ($idx = 0; $idx -lt $criteriaCombos.Count; $idx++) {
            $selectedLabel = [string]$criteriaCombos[$idx].SelectedItem
            if ([string]::IsNullOrWhiteSpace($selectedLabel) -or $selectedLabel -eq $noneLabel) {
                continue
            }

            $option = $matchOptions[$selectedLabel]
            $modeLabel = [string]$modeCombos[$idx].SelectedItem
            $modeValue = [string]$modeLookup[$modeLabel]
            $criteria += [pscustomobject]@{
                Order             = $order
                Label             = $option.Label
                MatchMode         = $modeValue
                MatchModeLabel    = $modeLabel
                SourceField       = $option.SourceField
                DestField         = $option.DestField
                SourceListId      = $option.SourceListId
                DestListId        = $option.DestListId
                SourceIsAssetName = [bool]$option.SourceIsAssetName
                DestIsAssetName   = [bool]$option.DestIsAssetName
            }
            $order++
        }

        $form.Tag = [pscustomobject]@{
            Success  = $true
            Criteria = $criteria
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(775,260)
    $cancelButton.Size = New-Object System.Drawing.Size(95,30)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or $null -eq $form.Tag) {
        return [pscustomobject]@{ Success = $false }
    }

    $form.Tag
}

function Show-FieldMappingEditor {
    param(
        [Parameter(Mandatory)]
        [psobject]$DestField,
        [string]$summaryLabel,

        [array]$SourceFieldOptions = @(),

        [string[]]$ExistingSmooshLabels = @(),

        [string[]]$AllDestinationLabels = @(),

        [System.Collections.IDictionary]$FieldStateByDestination = $null,

        [psobject]$InitialSelection = $null,

        [int]$CurrentIndex = 1,

        [int]$TotalCount = 1,

        [switch]$AllowMeta
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function New-Label {
        param([string]$Text,[int]$X,[int]$Y,[int]$W=180,[int]$H=22)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Text
        $lbl.Location = New-Object System.Drawing.Point($X,$Y)
        $lbl.Size = New-Object System.Drawing.Size($W,$H)
        $lbl
    }

    function New-TextBox {
        param([int]$X,[int]$Y,[int]$W=420,[string]$Text='')
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point($X,$Y)
        $tb.Size = New-Object System.Drawing.Size($W,24)
        $tb.Text = $Text
        $tb
    }

    function New-StatusTextBox {
        param([int]$X,[int]$Y,[int]$W=295,[int]$H=70)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point($X,$Y)
        $tb.Size = New-Object System.Drawing.Size($W,$H)
        $tb.Multiline = $true
        $tb.ReadOnly = $true
        $tb.ScrollBars = 'Vertical'
        $tb.BackColor = [System.Drawing.Color]::White
        $tb.BorderStyle = 'FixedSingle'
        $tb
    }

    function New-Combo {
        param([int]$X,[int]$Y,[int]$W=420,[string[]]$Options=@(),[string]$Default='')
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.Location = New-Object System.Drawing.Point($X,$Y)
        $cb.Size = New-Object System.Drawing.Size($W,24)
        $cb.DropDownStyle = 'DropDownList'
        foreach ($o in $Options) { [void]$cb.Items.Add($o) }
        if ($Default -and $cb.Items.Contains($Default)) {
            $cb.SelectedItem = $Default
        } elseif ($cb.Items.Count -gt 0) {
            $cb.SelectedIndex = 0
        }
        $cb
    }

    function Add-SourceOption {
        param(
            [Parameter(Mandatory)]
            [string]$Label,

            [string]$FieldType = ''
        )

        if ([string]::IsNullOrWhiteSpace($Label)) {
            return
        }

        $display = if ([string]::IsNullOrWhiteSpace($FieldType)) {
            $Label
        } else {
            '{0} [{1}]' -f $Label, $FieldType
        }

        $baseDisplay = $display
        $suffix = 2
        while ($sourceOptionLookup.Contains($display)) {
            $display = '{0} ({1})' -f $baseDisplay, $suffix
            $suffix++
        }

        $sourceOptionLookup[$display] = $Label
        $sourceOptionDisplayValues.Add($display) | Out-Null
    }

    $destType  = [string]($DestField.field_type ?? $DestField.type)
    $destLabel = [string]$DestField.label
    $required  = [bool]($DestField.required ?? $false)
    $listId    = $DestField.list_id

    if ($null -eq $FieldStateByDestination) {
        $FieldStateByDestination = @{}
    }

    if ($CurrentIndex -lt 1) {
        $CurrentIndex = 1
    }

    if ($TotalCount -lt 1) {
        $TotalCount = 1
    }

    if (@($AllDestinationLabels).Count -eq 0) {
        $AllDestinationLabels = @($destLabel)
    }

    $canSmoosh = $destType -in @('Text','RichText','Heading')
    $smooshTakenByOtherField = @($ExistingSmooshLabels | Where-Object { $_ -ne $destLabel }).Count -gt 0

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Review Destination Field Mapping'
    $form.Size = New-Object System.Drawing.Size(1070, 715)
    $form.StartPosition = 'CenterScreen'
    $form.Topmost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.BackColor = [System.Drawing.Color]::WhiteSmoke
    $form.Tag = $null
    $titleLabel = New-Label -Text $destLabel -X 20 -Y 12 -W 640 -H 28
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $form.Controls.Add($titleLabel)

    $progressLabel = New-Label -Text ("Field {0} of {1}" -f $CurrentIndex, $TotalCount) -X 690 -Y 16 -W 300 -H 24
    $progressLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $progressLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 90, 120)
    $form.Controls.Add($progressLabel)

    $summaryText = if ([string]::IsNullOrWhiteSpace($summaryLabel)) {
        "Choose how to fill this $destType field."
    } else {
        $summaryLabel
    }
    $summaryControl = New-Label -Text $summaryText -X 20 -Y 42 -W 640 -H 36
    $summaryControl.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($summaryControl)

    $tipLabel = New-Label -Text 'Tip: Use Source Field for a direct match, Constant Value for required defaults, and Skip only when the destination field is truly optional.' -X 20 -Y 80 -W 640 -H 36
    $tipLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 90, 120)
    $form.Controls.Add($tipLabel)

    $y = 125

    $form.Controls.Add((New-Label -Text "Mapping Mode:" -X 20 -Y $y))
    $modeOptions = @('Source Field','Constant Value','Skip')
    if ($canSmoosh -and -not $smooshTakenByOtherField) {
        $modeOptions = @('Source Field','Constant Value','SMOOSH','Skip')
    }

    $cbMode = New-Combo -X 210 -Y $y -Options $modeOptions
    $form.Controls.Add($cbMode)
    $y += 32

    $form.Controls.Add((New-Label -Text "Destination Label:" -X 20 -Y $y))
    $tbDest = New-TextBox -X 210 -Y $y -Text $destLabel
    $tbDest.ReadOnly = $true
    $form.Controls.Add($tbDest)
    $y += 32

    $form.Controls.Add((New-Label -Text "Destination Type:" -X 20 -Y $y))
    $tbType = New-TextBox -X 210 -Y $y -Text $destType
    $tbType.ReadOnly = $true
    $form.Controls.Add($tbType)
    $y += 32

    $form.Controls.Add((New-Label -Text "Required:" -X 20 -Y $y))
    $chkRequired = New-Object System.Windows.Forms.CheckBox
    $chkRequired.Location = New-Object System.Drawing.Point(210,$y)
    $chkRequired.Size = New-Object System.Drawing.Size(120,24)
    $chkRequired.Checked = $required
    $chkRequired.Enabled = $false
    $form.Controls.Add($chkRequired)
    $y += 36

    $pnlStandard = New-Object System.Windows.Forms.Panel
    $pnlStandard.Location = New-Object System.Drawing.Point(15,$y)
    $pnlStandard.Size = New-Object System.Drawing.Size(650,120)

    $pnlAddress = New-Object System.Windows.Forms.Panel
    $pnlAddress.Location = New-Object System.Drawing.Point(15,$y)
    $pnlAddress.Size = New-Object System.Drawing.Size(650,220)
    $pnlAddress.Visible = $false

    $pnlList = New-Object System.Windows.Forms.Panel
    $pnlList.Location = New-Object System.Drawing.Point(15,$y)
    $pnlList.Size = New-Object System.Drawing.Size(650,260)
    $pnlList.Visible = $false

    $pnlConstant = New-Object System.Windows.Forms.Panel
    $pnlConstant.Location = New-Object System.Drawing.Point(15,$y)
    $pnlConstant.Size = New-Object System.Drawing.Size(650,80)
    $pnlConstant.Visible = $false

    $pnlSmoosh = New-Object System.Windows.Forms.Panel
    $pnlSmoosh.Location = New-Object System.Drawing.Point(15,$y)
    $pnlSmoosh.Size = New-Object System.Drawing.Size(650,260)
    $pnlSmoosh.Visible = $false

    $sourceOptionLookup = [ordered]@{}
    $sourceOptionDisplayValues = New-Object System.Collections.Generic.List[string]
    foreach ($sourceOption in $SourceFieldOptions) {
        if ($sourceOption -is [string]) {
            Add-SourceOption -Label ([string]$sourceOption)
            continue
        }

        $optionLabel = [string]($sourceOption.label ?? $sourceOption.Label ?? $sourceOption.name ?? $sourceOption.Name)
        $optionType = [string]($sourceOption.field_type ?? $sourceOption.type ?? $sourceOption.FieldType)
        Add-SourceOption -Label $optionLabel -FieldType $optionType
    }
    if ($AllowMeta -and -not ($sourceOptionLookup.Values -contains 'Meta')) {
        Add-SourceOption -Label 'Meta' -FieldType 'Pseudo'
    }
    $sourceOptions = @($sourceOptionDisplayValues)
    $allSourceLabels = @(
        $sourceOptions |
        ForEach-Object { [string]($sourceOptionLookup[[string]$_] ?? [string]$_) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notin @('SMOOSH','Meta') } |
        Sort-Object -Unique
    )

    $resolveSourceSelection = {
        param([object]$SelectedItem)

        [string]($sourceOptionLookup[[string]$SelectedItem] ?? [string]$SelectedItem)
    }

    $setComboToSourceLabel = {
        param(
            [Parameter(Mandatory)]
            [System.Windows.Forms.ComboBox]$Combo,

            [string]$RawLabel
        )

        if ([string]::IsNullOrWhiteSpace($RawLabel)) {
            if ($Combo.Items.Count -gt 0) {
                $Combo.SelectedIndex = 0
            }
            return
        }

        foreach ($item in $Combo.Items) {
            $candidate = [string]($sourceOptionLookup[[string]$item] ?? [string]$item)
            if ($candidate -eq $RawLabel) {
                $Combo.SelectedItem = $item
                return
            }
        }
    }

    $getSelectionSourceLabels = {
        param([psobject]$Selection)

        if ($null -eq $Selection -or $Selection.Skip) {
            return @()
        }

        switch ([string]$Selection.Value.kind) {
            'mapping' {
                if ([string]$Selection.Value.dest_type -eq 'AddressData') {
                    return @(
                        foreach ($partKey in @($Selection.Value.address.Keys)) {
                            [string]$Selection.Value.address[$partKey].from
                        }
                    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notin @('Meta','SMOOSH') }
                }

                $mappedFrom = [string]$Selection.Value.from
                if ([string]::IsNullOrWhiteSpace($mappedFrom) -or $mappedFrom -in @('Meta','SMOOSH')) {
                    return @()
                }

                return @($mappedFrom)
            }
            'smoosh' {
                return @(
                    $Selection.Value.smooshSourceLabels |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notin @('Meta','SMOOSH') }
                )
            }
            default {
                return @()
            }
        }
    }

    $pnlStandard.Controls.Add((New-Label -Text "Source Field:" -X 5 -Y 5))
    $cbFrom = New-Combo -X 195 -Y 5 -Options (@('') + $sourceOptions)
    $pnlStandard.Controls.Add($cbFrom)

    $chkStripHtml = New-Object System.Windows.Forms.CheckBox
    $chkStripHtml.Location = New-Object System.Drawing.Point(195,40)
    $chkStripHtml.Size = New-Object System.Drawing.Size(200,24)
    $chkStripHtml.Text = 'Strip HTML'
    $pnlStandard.Controls.Add($chkStripHtml)

    $pnlConstant.Controls.Add((New-Label -Text "Constant Value:" -X 5 -Y 5))
    $tbConstant = New-TextBox -X 195 -Y 5 -W 420
    $pnlConstant.Controls.Add($tbConstant)

    $pnlSmoosh.Controls.Add((New-Label -Text "Source Fields To Combine:" -X 5 -Y 5 -W 180))
    $smooshHint = New-Label -Text 'Choose the source fields that should be concatenated into the single destination SMOOSH field.' -X 195 -Y 5 -W 430 -H 36
    $smooshHint.ForeColor = [System.Drawing.Color]::DimGray
    $pnlSmoosh.Controls.Add($smooshHint)

    $smooshSourceOptions = @(
        $sourceOptions |
        Where-Object {
            ([string]($sourceOptionLookup[[string]$_] ?? [string]$_)) -notin @('SMOOSH','Meta')
        }
    )

    $smooshSelectionState = [pscustomobject]@{
        Fields = @()
    }

    $lblSmooshSelection = New-Label -Text 'No source fields selected yet.' -X 195 -Y 55 -W 420 -H 70
    $lblSmooshSelection.ForeColor = [System.Drawing.Color]::FromArgb(60, 90, 120)
    $pnlSmoosh.Controls.Add($lblSmooshSelection)

    $btnChooseSmooshFields = New-Object System.Windows.Forms.Button
    $btnChooseSmooshFields.Location = New-Object System.Drawing.Point(195,140)
    $btnChooseSmooshFields.Size = New-Object System.Drawing.Size(160,30)
    $btnChooseSmooshFields.Text = 'Choose Source Fields'
    $pnlSmoosh.Controls.Add($btnChooseSmooshFields)

    $updateSmooshSummary = {
        if ($smooshSelectionState.Fields.Count -eq 0) {
            $lblSmooshSelection.Text = 'No source fields selected yet.'
            return
        }

        $previewItems = @($smooshSelectionState.Fields | Select-Object -First 5)
        $previewText = $previewItems -join ', '
        if ($smooshSelectionState.Fields.Count -gt 5) {
            $previewText = '{0}, +{1} more' -f $previewText, ($smooshSelectionState.Fields.Count - 5)
        }

        $lblSmooshSelection.Text = 'Selected source fields: ' + $previewText
    }

    $openSmooshPicker = {
        $picker = New-Object System.Windows.Forms.Form
        $picker.Text = "Choose SMOOSH Source Fields"
        $picker.Size = New-Object System.Drawing.Size(560, 500)
        $picker.StartPosition = 'CenterParent'
        $picker.TopMost = $true
        $picker.FormBorderStyle = 'FixedDialog'
        $picker.MaximizeBox = $false
        $picker.MinimizeBox = $false
        $picker.Font = New-Object System.Drawing.Font('Segoe UI', 9)

        $pickerIntro = New-Object System.Windows.Forms.Label
        $pickerIntro.Location = New-Object System.Drawing.Point(15,15)
        $pickerIntro.Size = New-Object System.Drawing.Size(510,40)
        $pickerIntro.Text = "Select one or more source fields to concatenate into '$destLabel'."
        $picker.Controls.Add($pickerIntro)

        $pickerList = New-Object System.Windows.Forms.CheckedListBox
        $pickerList.Location = New-Object System.Drawing.Point(15,65)
        $pickerList.Size = New-Object System.Drawing.Size(510,320)
        $pickerList.CheckOnClick = $true
        foreach ($option in $smooshSourceOptions) {
            $index = $pickerList.Items.Add($option)
            $rawLabel = [string]($sourceOptionLookup[[string]$option] ?? [string]$option)
            if ($rawLabel -in $smooshSelectionState.Fields) {
                $pickerList.SetItemChecked($index, $true)
            }
        }
        $picker.Controls.Add($pickerList)

        $pickerOk = New-Object System.Windows.Forms.Button
        $pickerOk.Location = New-Object System.Drawing.Point(360,400)
        $pickerOk.Size = New-Object System.Drawing.Size(75,28)
        $pickerOk.Text = 'OK'
        $pickerOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $picker.Controls.Add($pickerOk)

        $pickerCancel = New-Object System.Windows.Forms.Button
        $pickerCancel.Location = New-Object System.Drawing.Point(450,400)
        $pickerCancel.Size = New-Object System.Drawing.Size(75,28)
        $pickerCancel.Text = 'Cancel'
        $pickerCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $picker.Controls.Add($pickerCancel)

        $picker.AcceptButton = $pickerOk
        $picker.CancelButton = $pickerCancel

        if ($picker.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $smooshSelectionState.Fields = @(
                $pickerList.CheckedItems |
                ForEach-Object { [string]($sourceOptionLookup[[string]$_] ?? [string]$_) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            & $updateSmooshSummary
        }
    }

    $btnChooseSmooshFields.Add_Click({ & $openSmooshPicker })
    & $updateSmooshSummary

    $buildSmooshValue = {
        if ($smooshSelectionState.Fields.Count -eq 0) {
            & $openSmooshPicker
        }

        if ($smooshSelectionState.Fields.Count -eq 0) {
            Show-TransferMessage `
                -Title 'SMOOSH Needs Source Fields' `
                -Kind Warning `
                -Message "Choose one or more source fields to combine into '$destLabel'."
            return $null
        }

        @{
            kind               = 'smoosh'
            smooshSourceLabels = @($smooshSelectionState.Fields)
            smooshTarget       = @{
                kind      = 'mapping'
                from      = 'SMOOSH'
                to        = $destLabel
                dest_type = $destType
                required  = $required
                striphtml = $false
            }
        }
    }

    $addressParts = @(
        @{ Key='address_line_1'; Label='Address Line 1' },
        @{ Key='address_line_2'; Label='Address Line 2' },
        @{ Key='city';           Label='City' },
        @{ Key='state';          Label='State' },
        @{ Key='zip';            Label='Zip' },
        @{ Key='country_name';   Label='Country' }
    )

    $addressCombos = @{}
    $ay = 5
    foreach ($part in $addressParts) {
        $pnlAddress.Controls.Add((New-Label -Text "$($part.Label):" -X 5 -Y $ay))
        $combo = New-Combo -X 195 -Y $ay -Options (@('') + $sourceOptions)
        $pnlAddress.Controls.Add($combo)
        $addressCombos[$part.Key] = $combo
        $ay += 30
    }

    $pnlList.Controls.Add((New-Label -Text "Source Field:" -X 5 -Y 5))
    $cbListFrom = New-Combo -X 195 -Y 5 -Options (@('') + $sourceOptions)
    $pnlList.Controls.Add($cbListFrom)

    $chkAddListItems = New-Object System.Windows.Forms.CheckBox
    $chkAddListItems.Location = New-Object System.Drawing.Point(195,40)
    $chkAddListItems.Size = New-Object System.Drawing.Size(220,24)
    $chkAddListItems.Text = 'Add missing list items'
    $pnlList.Controls.Add($chkAddListItems)

    $pnlList.Controls.Add((New-Label -Text "List Value Mapping:" -X 5 -Y 75 -W 180))

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(5,100)
    $grid.Size = New-Object System.Drawing.Size(620,145)
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    [void]$grid.Columns.Add('ListItem','Destination List Item')
    [void]$grid.Columns.Add('WhenValues','Source values (comma-separated)')
    $pnlList.Controls.Add($grid)

    if ($destType -eq 'ListSelect' -and $listId) {
        try {
            $listItems = (Get-HuduLists -id $listId).list_items.name
            foreach ($item in $listItems) {
                [void]$grid.Rows.Add($item, '')
            }
        } catch {}
    }

    $form.Controls.Add($pnlStandard)
    $form.Controls.Add($pnlAddress)
    $form.Controls.Add($pnlList)
    $form.Controls.Add($pnlConstant)
    $form.Controls.Add($pnlSmoosh)

    $statusGroup = New-Object System.Windows.Forms.GroupBox
    $statusGroup.Location = New-Object System.Drawing.Point(675, 52)
    $statusGroup.Size = New-Object System.Drawing.Size(330, 570)
    $statusGroup.Text = 'Current Mapping Snapshot'
    $form.Controls.Add($statusGroup)

    $statusIntro = New-Label -Text 'Green shows configured or in-use items. Red shows items still available or pending. Skipped destinations are highlighted in amber.' -X 15 -Y 22 -W 295 -H 36
    $statusIntro.ForeColor = [System.Drawing.Color]::DimGray
    $statusGroup.Controls.Add($statusIntro)

    $statusY = 65
    $statusGroup.Controls.Add((New-Label -Text 'Configured Destination Fields' -X 15 -Y $statusY -W 280 -H 20))
    $tbMappedDest = New-StatusTextBox -X 15 -Y ($statusY + 18)
    $tbMappedDest.ForeColor = [System.Drawing.Color]::ForestGreen
    $statusGroup.Controls.Add($tbMappedDest)

    $statusY += 100
    $statusGroup.Controls.Add((New-Label -Text 'Pending Destination Fields' -X 15 -Y $statusY -W 280 -H 20))
    $tbPendingDest = New-StatusTextBox -X 15 -Y ($statusY + 18)
    $tbPendingDest.ForeColor = [System.Drawing.Color]::Firebrick
    $statusGroup.Controls.Add($tbPendingDest)

    $statusY += 100
    $statusGroup.Controls.Add((New-Label -Text 'Skipped Destination Fields' -X 15 -Y $statusY -W 280 -H 20))
    $tbSkippedDest = New-StatusTextBox -X 15 -Y ($statusY + 18)
    $tbSkippedDest.ForeColor = [System.Drawing.Color]::DarkGoldenrod
    $statusGroup.Controls.Add($tbSkippedDest)

    $statusY += 100
    $statusGroup.Controls.Add((New-Label -Text 'Mapped Source Fields' -X 15 -Y $statusY -W 280 -H 20))
    $tbMappedSource = New-StatusTextBox -X 15 -Y ($statusY + 18)
    $tbMappedSource.ForeColor = [System.Drawing.Color]::ForestGreen
    $statusGroup.Controls.Add($tbMappedSource)

    $statusY += 100
    $statusGroup.Controls.Add((New-Label -Text 'Unmapped Source Fields' -X 15 -Y $statusY -W 280 -H 20))
    $tbUnmappedSource = New-StatusTextBox -X 15 -Y ($statusY + 18)
    $tbUnmappedSource.ForeColor = [System.Drawing.Color]::Firebrick
    $statusGroup.Controls.Add($tbUnmappedSource)

    $updateModeUi = {
        $mode = [string]$cbMode.SelectedItem

        $pnlStandard.Visible = $false
        $pnlAddress.Visible  = $false
        $pnlList.Visible     = $false
        $pnlConstant.Visible = $false
        $pnlSmoosh.Visible   = $false

        switch ($mode) {
            'Constant Value' {
                $pnlConstant.Visible = $true
            }
            'Source Field' {
                switch ($destType) {
                    'AddressData' { $pnlAddress.Visible = $true }
                    'ListSelect'  { $pnlList.Visible = $true }
                    default       { $pnlStandard.Visible = $true }
                }
            }
            'SMOOSH' { $pnlSmoosh.Visible = $true }
            'Skip'   { }
        }
    }

    $getDraftSelection = {
        $mode = [string]$cbMode.SelectedItem

        switch ($mode) {
            'Skip' {
                return [pscustomobject]@{
                    Success = $true
                    Skip    = $true
                    Value   = $null
                }
            }
            'Constant Value' {
                if ([string]::IsNullOrWhiteSpace($tbConstant.Text)) {
                    return $null
                }

                return [pscustomobject]@{
                    Success = $true
                    Skip    = $false
                    Value   = @{
                        kind     = 'constant'
                        to_label = $destLabel
                        literal  = $tbConstant.Text
                    }
                }
            }
            'SMOOSH' {
                if ($smooshSelectionState.Fields.Count -eq 0) {
                    return $null
                }

                return [pscustomobject]@{
                    Success = $true
                    Skip    = $false
                    Value   = @{
                        kind               = 'smoosh'
                        smooshSourceLabels = @($smooshSelectionState.Fields)
                        smooshTarget       = @{
                            kind      = 'mapping'
                            from      = 'SMOOSH'
                            to        = $destLabel
                            dest_type = $destType
                            required  = $required
                            striphtml = $false
                        }
                    }
                }
            }
            'Source Field' {
                switch ($destType) {
                    'AddressData' {
                        $addressMap = @{}
                        foreach ($part in $addressParts) {
                            $addressMap[$part.Key] = @{
                                from = [string](& $resolveSourceSelection $addressCombos[$part.Key].SelectedItem)
                            }
                        }

                        if (@($addressMap.Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.from) }).Count -eq 0) {
                            return $null
                        }

                        return [pscustomobject]@{
                            Success = $true
                            Skip    = $false
                            Value   = @{
                                kind      = 'mapping'
                                to        = $destLabel
                                from      = 'Meta'
                                dest_type = 'AddressData'
                                required  = $required
                                address   = $addressMap
                            }
                        }
                    }
                    'ListSelect' {
                        $selectedListSource = [string](& $resolveSourceSelection $cbListFrom.SelectedItem)
                        if ([string]::IsNullOrWhiteSpace($selectedListSource)) {
                            return $null
                        }

                        return [pscustomobject]@{
                            Success = $true
                            Skip    = $false
                            Value   = @{
                                kind          = 'mapping'
                                to            = $destLabel
                                from          = $selectedListSource
                                add_listitems = [bool]$chkAddListItems.Checked
                                list_id       = $listId
                                dest_type     = 'ListSelect'
                                required      = $required
                                Mapping       = @{}
                            }
                        }
                    }
                    default {
                        $selectedStandardSource = [string](& $resolveSourceSelection $cbFrom.SelectedItem)
                        if ([string]::IsNullOrWhiteSpace($selectedStandardSource)) {
                            return $null
                        }

                        if ($selectedStandardSource -eq 'SMOOSH' -and $canSmoosh -and $smooshSelectionState.Fields.Count -gt 0) {
                            return [pscustomobject]@{
                                Success = $true
                                Skip    = $false
                                Value   = @{
                                    kind               = 'smoosh'
                                    smooshSourceLabels = @($smooshSelectionState.Fields)
                                    smooshTarget       = @{
                                        kind      = 'mapping'
                                        from      = 'SMOOSH'
                                        to        = $destLabel
                                        dest_type = $destType
                                        required  = $required
                                        striphtml = [bool]$chkStripHtml.Checked
                                    }
                                }
                            }
                        }

                        return [pscustomobject]@{
                            Success = $true
                            Skip    = $false
                            Value   = @{
                                kind      = 'mapping'
                                from      = $selectedStandardSource
                                to        = $destLabel
                                dest_type = $destType
                                required  = $required
                                striphtml = [bool]$chkStripHtml.Checked
                            }
                        }
                    }
                }
            }
            default {
                return $null
            }
        }
    }

    $updateStatusSnapshot = {
        $effectiveSelections = [ordered]@{}
        foreach ($entry in $FieldStateByDestination.GetEnumerator()) {
            if ([string]$entry.Key -eq $destLabel) {
                continue
            }

            $effectiveSelections[[string]$entry.Key] = $entry.Value
        }

        $draftSelection = & $getDraftSelection
        if ($null -ne $draftSelection) {
            $effectiveSelections[$destLabel] = $draftSelection
        }

        $mappedDestinations = New-Object System.Collections.Generic.List[string]
        $pendingDestinations = New-Object System.Collections.Generic.List[string]
        $skippedDestinations = New-Object System.Collections.Generic.List[string]

        foreach ($candidateDestLabel in $AllDestinationLabels) {
            if ($effectiveSelections.Contains($candidateDestLabel)) {
                $candidateSelection = $effectiveSelections[$candidateDestLabel]
                if ($null -ne $candidateSelection -and $candidateSelection.Skip) {
                    $skippedDestinations.Add([string]$candidateDestLabel) | Out-Null
                } else {
                    $mappedDestinations.Add([string]$candidateDestLabel) | Out-Null
                }
            } else {
                $pendingDestinations.Add([string]$candidateDestLabel) | Out-Null
            }
        }

        $usedSourceLabels = @(
            foreach ($selection in $effectiveSelections.Values) {
                & $getSelectionSourceLabels $selection
            }
        ) | Sort-Object -Unique

        $unusedSourceLabels = @(
            $allSourceLabels |
            Where-Object { $_ -notin $usedSourceLabels }
        )

        $tbMappedDest.Text = if ($mappedDestinations.Count -gt 0) { $mappedDestinations -join [Environment]::NewLine } else { '<none yet>' }
        $tbPendingDest.Text = if ($pendingDestinations.Count -gt 0) { $pendingDestinations -join [Environment]::NewLine } else { '<none>' }
        $tbSkippedDest.Text = if ($skippedDestinations.Count -gt 0) { $skippedDestinations -join [Environment]::NewLine } else { '<none>' }
        $tbMappedSource.Text = if (@($usedSourceLabels).Count -gt 0) { @($usedSourceLabels) -join [Environment]::NewLine } else { '<none yet>' }
        $tbUnmappedSource.Text = if (@($unusedSourceLabels).Count -gt 0) { @($unusedSourceLabels) -join [Environment]::NewLine } else { '<none>' }
    }

    $cbMode.Add_SelectedIndexChanged($updateModeUi)
    $cbMode.Add_SelectedIndexChanged({
        if ([string]$cbMode.SelectedItem -eq 'SMOOSH' -and $smooshSelectionState.Fields.Count -eq 0) {
            & $openSmooshPicker
        }
    })
    $cbMode.Add_SelectedIndexChanged($updateStatusSnapshot)
    $cbFrom.Add_SelectedIndexChanged({
        $selectedSourceLabel = [string](& $resolveSourceSelection $cbFrom.SelectedItem)
        if ($selectedSourceLabel -eq 'SMOOSH' -and $canSmoosh) {
            $cbMode.SelectedItem = 'SMOOSH'
            if ($smooshSelectionState.Fields.Count -eq 0) {
                & $openSmooshPicker
            }
        }
    })
    $cbFrom.Add_SelectedIndexChanged($updateStatusSnapshot)
    $cbListFrom.Add_SelectedIndexChanged($updateStatusSnapshot)
    $tbConstant.Add_TextChanged($updateStatusSnapshot)
    foreach ($combo in $addressCombos.Values) {
        $combo.Add_SelectedIndexChanged($updateStatusSnapshot)
    }
    & $updateModeUi

    if ($null -ne $InitialSelection) {
        if ($InitialSelection.Skip) {
            $cbMode.SelectedItem = 'Skip'
        } else {
            switch ([string]$InitialSelection.Value.kind) {
                'constant' {
                    $cbMode.SelectedItem = 'Constant Value'
                    $tbConstant.Text = [string]$InitialSelection.Value.literal
                }
                'smoosh' {
                    if ($cbMode.Items.Contains('SMOOSH')) {
                        $cbMode.SelectedItem = 'SMOOSH'
                    }
                    $smooshSelectionState.Fields = @($InitialSelection.Value.smooshSourceLabels)
                    & $updateSmooshSummary
                }
                'mapping' {
                    $cbMode.SelectedItem = 'Source Field'
                    switch ([string]$InitialSelection.Value.dest_type) {
                        'AddressData' {
                            foreach ($part in $addressParts) {
                                $savedSource = [string]($InitialSelection.Value.address[$part.Key].from)
                                & $setComboToSourceLabel -Combo $addressCombos[$part.Key] -RawLabel $savedSource
                            }
                        }
                        'ListSelect' {
                            & $setComboToSourceLabel -Combo $cbListFrom -RawLabel ([string]$InitialSelection.Value.from)
                            $chkAddListItems.Checked = [bool]$InitialSelection.Value.add_listitems
                            foreach ($row in $grid.Rows) {
                                $savedListItemName = [string]$row.Cells['ListItem'].Value
                                $savedListConfig = $InitialSelection.Value.Mapping[$savedListItemName]
                                if ($null -ne $savedListConfig) {
                                    $row.Cells['WhenValues'].Value = @($savedListConfig.whenvalues) -join ', '
                                }
                            }
                        }
                        default {
                            if ([string]$InitialSelection.Value.from -eq 'SMOOSH' -and $cbMode.Items.Contains('SMOOSH')) {
                                $cbMode.SelectedItem = 'SMOOSH'
                            } else {
                                & $setComboToSourceLabel -Combo $cbFrom -RawLabel ([string]$InitialSelection.Value.from)
                            }
                            $chkStripHtml.Checked = [bool]$InitialSelection.Value.striphtml
                        }
                    }
                }
            }
        }
    }

    & $updateStatusSnapshot

    $backButton = New-Object System.Windows.Forms.Button
    $backButton.Location = New-Object System.Drawing.Point(315,625)
    $backButton.Size = New-Object System.Drawing.Size(75,28)
    $backButton.Text = 'Back'
    $backButton.Enabled = $CurrentIndex -gt 1
    $form.Controls.Add($backButton)

    $skipButton = New-Object System.Windows.Forms.Button
    $skipButton.Location = New-Object System.Drawing.Point(400,625)
    $skipButton.Size = New-Object System.Drawing.Size(75,28)
    $skipButton.Text = 'Skip'
    $form.Controls.Add($skipButton)

    $nextButton = New-Object System.Windows.Forms.Button
    $nextButton.Location = New-Object System.Drawing.Point(490,625)
    $nextButton.Size = New-Object System.Drawing.Size(75,28)
    $nextButton.Text = $(if ($CurrentIndex -ge $TotalCount) { 'Finish' } else { 'Next' })
    $form.Controls.Add($nextButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(580,625)
    $cancelButton.Size = New-Object System.Drawing.Size(75,28)
    $cancelButton.Text = 'Cancel'
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $nextButton
    $form.CancelButton = $cancelButton

    $commitSelection = {
        param(
            [string]$Navigate = 'Next',
            [switch]$ForceSkip
        )

        $mode = if ($ForceSkip) { 'Skip' } else { [string]$cbMode.SelectedItem }

        if ($mode -eq 'Skip') {
            if ($required) {
                $result = Show-TransferMessage `
                    -Title 'Required Field' `
                    -Kind Question `
                    -YesNo `
                    -Message "The destination field '$destLabel' is marked required. Skipping it may cause the transfer to fail or require a manual fix later.`r`n`r`nDo you still want to skip it?"

                if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                    return
                }
            }

            $form.Tag = [pscustomobject]@{
                Success  = $true
                Skip     = $true
                Value    = $null
                Navigate = $Navigate
            }
            $form.Close()
            return
        }

        switch ($mode) {
            'Constant Value' {
                if ($required -and [string]::IsNullOrWhiteSpace($tbConstant.Text)) {
                    Show-TransferMessage `
                        -Title 'Constant Required' `
                        -Kind Warning `
                        -Message "The destination field '$destLabel' is required. Enter a constant value, or switch this field to Source Field or Skip."
                    return
                }

                $form.Tag = [pscustomobject]@{
                    Success  = $true
                    Skip     = $false
                    Value    = @{
                        kind     = 'constant'
                        to_label = $destLabel
                        literal  = $tbConstant.Text
                    }
                    Navigate = $Navigate
                }
                $form.Close()
                return
            }
            'SMOOSH' {
                $smooshValue = & $buildSmooshValue
                if ($null -eq $smooshValue) { return }

                $form.Tag = [pscustomobject]@{
                    Success  = $true
                    Skip     = $false
                    Value    = $smooshValue
                    Navigate = $Navigate
                }
                $form.Close()
                return
            }
            'Source Field' {
                switch ($destType) {
                    'AddressData' {
                        $addressSelections = @(
                            foreach ($part in $addressParts) {
                                [string]$addressCombos[$part.Key].SelectedItem
                            }
                        )

                        if (@($addressSelections | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
                            Show-TransferMessage `
                                -Title 'Address Mapping Needed' `
                                -Kind Warning `
                                -Message "Choose at least one source field for the address mapping, or skip '$destLabel' if you do not want to populate it."
                            return
                        }
                    }
                    'ListSelect' {
                        if ([string]::IsNullOrWhiteSpace([string]$cbListFrom.SelectedItem)) {
                            Show-TransferMessage `
                                -Title 'Source Field Required' `
                                -Kind Warning `
                                -Message "Choose a source field for '$destLabel', or switch the mapping mode to Constant Value or Skip."
                            return
                        }
                    }
                    default {
                        $selectedStandardSource = [string](& $resolveSourceSelection $cbFrom.SelectedItem)
                        if ([string]::IsNullOrWhiteSpace([string]$cbFrom.SelectedItem)) {
                            Show-TransferMessage `
                                -Title 'Source Field Required' `
                                -Kind Warning `
                                -Message "Choose a source field for '$destLabel', or switch the mapping mode to Constant Value or Skip."
                            return
                        }
                        if ($selectedStandardSource -eq 'SMOOSH') {
                            if ($canSmoosh) {
                                $cbMode.SelectedItem = 'SMOOSH'
                                $smooshValue = & $buildSmooshValue
                                if ($null -eq $smooshValue) {
                                    return
                                }

                                $form.Tag = [pscustomobject]@{
                                    Success  = $true
                                    Skip     = $false
                                    Value    = $smooshValue
                                    Navigate = $Navigate
                                }
                                $form.Close()
                            } else {
                                Show-TransferMessage `
                                    -Title 'SMOOSH Not Supported Here' `
                                    -Kind Warning `
                                    -Message "SMOOSH can only be used for Text, RichText, or Heading destination fields."
                            }
                            return
                        }
                    }
                }

                $result = switch ($destType) {
                    'AddressData' {
                        $addressMap = @{}
                        foreach ($part in $addressParts) {
                            $addressMap[$part.Key] = @{
                                from = [string](& $resolveSourceSelection $addressCombos[$part.Key].SelectedItem)
                            }
                        }
                        @{
                            kind      = 'mapping'
                            to        = $destLabel
                            from      = 'Meta'
                            dest_type = 'AddressData'
                            required  = $required
                            address   = $addressMap
                        }
                    }
                    'ListSelect' {
                        $listMap = @{}
                        foreach ($row in $grid.Rows) {
                            $itemName = [string]$row.Cells['ListItem'].Value
                            $whenRaw = [string]$row.Cells['WhenValues'].Value
                            $whenValues = @()

                            if (-not [string]::IsNullOrWhiteSpace($whenRaw)) {
                                $whenValues = @(
                                    $whenRaw -split ',' |
                                    ForEach-Object { $_.Trim() } |
                                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                                )
                            }

                            $listMap[$itemName] = @{
                                whenvalues = $whenValues
                            }
                        }

                        @{
                            kind          = 'mapping'
                            to            = $destLabel
                            from          = [string](& $resolveSourceSelection $cbListFrom.SelectedItem)
                            add_listitems = [bool]$chkAddListItems.Checked
                            list_id       = $listId
                            dest_type     = 'ListSelect'
                            required      = $required
                            Mapping       = $listMap
                        }
                    }
                    default {
                        @{
                            kind      = 'mapping'
                            from      = [string](& $resolveSourceSelection $cbFrom.SelectedItem)
                            to        = $destLabel
                            dest_type = $destType
                            required  = $required
                            striphtml = [bool]$chkStripHtml.Checked
                        }
                    }
                }

                $form.Tag = [pscustomobject]@{
                    Success  = $true
                    Skip     = $false
                    Value    = $result
                    Navigate = $Navigate
                }
                $form.Close()
            }
        }
    }

    $skipButton.Add_Click({
        & $commitSelection -Navigate 'Next' -ForceSkip
    })

    $backButton.Add_Click({
        $form.Tag = [pscustomobject]@{
            Success        = $true
            Skip           = $false
            Value          = $null
            Navigate       = 'Back'
            ApplySelection = $false
        }
        $form.Close()
    })

    $nextButton.Add_Click({
        & $commitSelection -Navigate 'Next'
    })

    $cancelButton.Add_Click({ $form.Close() })

    [void]$form.ShowDialog()

    if ($null -ne $form.Tag) {
        return $form.Tag
    }

    [pscustomobject]@{
        Success = $false
        Skip    = $false
        Value   = $null
    }
}

function Show-InputPopup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [string]$Title = "Input Required",

        [Parameter(Mandatory)]
        [ValidateSet("Text","Password","ListSelect","YesNo")]
        [string]$InputType,

        [string[]]$Options = @(),

        [string]$DefaultValue = ""
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if ($InputType -eq 'YesNo') {
        $result = [System.Windows.Forms.MessageBox]::Show(
            $Prompt,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        return [pscustomobject]@{
            Success = $true
            Type    = 'YesNo'
            Value   = ($result -eq [System.Windows.Forms.DialogResult]::Yes)
            Raw     = $result.ToString()
        }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(420,210)
    $form.StartPosition = 'CenterScreen'
    $form.Topmost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(15,15)
    $label.MaximumSize = New-Object System.Drawing.Size(370,0)
    $label.AutoSize = $true
    $label.Text = $Prompt
    $form.Controls.Add($label)

    $inputTop = $label.Bottom + 10
    $inputControl = $null

    switch ($InputType) {
        'Text' {
            $textBox = New-Object System.Windows.Forms.TextBox
            $textBox.Location = New-Object System.Drawing.Point(15,$inputTop)
            $textBox.Size = New-Object System.Drawing.Size(370,23)
            $textBox.Text = $DefaultValue
            $form.Controls.Add($textBox)
            $inputControl = $textBox
        }

        'Password' {
            $textBox = New-Object System.Windows.Forms.TextBox
            $textBox.Location = New-Object System.Drawing.Point(15,$inputTop)
            $textBox.Size = New-Object System.Drawing.Size(370,23)
            $textBox.Text = $DefaultValue
            $textBox.UseSystemPasswordChar = $true
            $form.Controls.Add($textBox)
            $inputControl = $textBox
        }

        'ListSelect' {
            $comboBox = New-Object System.Windows.Forms.ComboBox
            $comboBox.Location = New-Object System.Drawing.Point(15,$inputTop)
            $comboBox.Size = New-Object System.Drawing.Size(370,23)
            $comboBox.DropDownStyle = 'DropDownList'

            if ($Options.Count -gt 0) {
                [void]$comboBox.Items.AddRange($Options)
            }

            if ($DefaultValue -and $comboBox.Items.Contains($DefaultValue)) {
                $comboBox.SelectedItem = $DefaultValue
            }
            elseif ($comboBox.Items.Count -gt 0) {
                $comboBox.SelectedIndex = 0
            }

            $form.Controls.Add($comboBox)
            $inputControl = $comboBox
        }
    }

    $buttonTop = $inputTop + 45
    $form.ClientSize = New-Object System.Drawing.Size(400,($buttonTop + 45))

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(220,$buttonTop)
    $okButton.Size = New-Object System.Drawing.Size(75,28)
    $okButton.Text = 'OK'
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(310,$buttonTop)
    $cancelButton.Size = New-Object System.Drawing.Size(75,28)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $result = $form.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return [pscustomobject]@{
            Success = $false
            Type    = $InputType
            Value   = $null
            Raw     = 'Cancel'
        }
    }

    $value = switch ($InputType) {
        'Text'       { $inputControl.Text }
        'Password'   { $inputControl.Text }
        'ListSelect' { $inputControl.SelectedItem }
    }

    return [pscustomobject]@{
        Success = $true
        Type    = $InputType
        Value   = $value
        Raw     = $result.ToString()
    }
}

function New-GuiJob {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $state = [ordered]@{
        AssetLayouts = @()
        Job          = $null
        ApiKey       = ''
        BaseUrl      = ''
    }
    $mapfile = Join-Path $script:Root 'mapping.ps1'

    $Mainform = New-Object System.Windows.Forms.Form
    $Mainform.Text = "Hudu Asset Layout Transfer v$script:AppVersion"
    $Mainform.Size = New-Object System.Drawing.Size(1100, 760)
    $Mainform.StartPosition = 'CenterScreen'
    $font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Mainform.Font = $font

    Show-TransferMessage `
        -Title 'Welcome' `
        -Kind Info `
        -Message "This wizard will help you connect to Hudu, choose a source and destination layout, and build a reusable mapping plan.`r`n`r`nNothing changes in Hudu until the final transfer step."

    $authenticated = $false

    while (-not $authenticated) {
        $urlInputResult = Show-InputPopup `
            -Prompt 'Enter the Hudu Base URL for the target environment:' `
            -Title 'Hudu Asset Layout Transfer' `
            -InputType 'Text' `
            -DefaultValue 'https://'

        if (-not $urlInputResult.Success -or [string]::IsNullOrWhiteSpace($urlInputResult.Value)) {
            throw 'Base URL is required to proceed.'
        }

        $normalizedBaseUrl = Normalize-HuduBaseUrl -Value $urlInputResult.Value
        if (-not $normalizedBaseUrl) {
            Show-TransferMessage `
                -Title 'Check The URL' `
                -Kind Warning `
                -Message 'Enter a valid Hudu URL such as https://example.huducloud.com.'
            continue
        }

        $apiKeyInputResult = Show-InputPopup `
            -Prompt 'Enter your Hudu API Key:' `
            -Title 'Hudu Asset Layout Transfer' `
            -InputType 'Password'

        if (-not $apiKeyInputResult.Success -or [string]::IsNullOrWhiteSpace($apiKeyInputResult.Value)) {
            throw 'API Key is required to proceed.'
        }

        if (-not (Test-HuduApiKeyFormat -Value $apiKeyInputResult.Value)) {
            Show-TransferMessage `
                -Title 'Check The API Key' `
                -Kind Warning `
                -Message 'Hudu API keys should be 24 characters long. Double-check the key and try again.'
            continue
        }

        try {
            Get-HuduModule
            Set-HuduInstance -HuduBaseURL $normalizedBaseUrl -HuduAPIKey $apiKeyInputResult.Value

            $state.BaseUrl = $normalizedBaseUrl
            $state.ApiKey  = $apiKeyInputResult.Value
            $authenticated = $true
        }
        catch {
            Show-TransferMessage `
                -Title 'Authentication Failed' `
                -Kind Error `
                -Message "Authentication failed. Please try again.`r`n`r`n$($_.Exception.Message)" | Out-Null
        }
    }

    $state.AssetLayouts = @(Get-HuduAssetLayouts)
    if (-not $state.AssetLayouts -or $state.AssetLayouts.Count -eq 0) {
        throw 'No asset layouts were found.'
    }

    $sourceLayout = $null
    $destLayout = $null

    $layoutSelection = Show-LayoutPairDialog -AssetLayouts $state.AssetLayouts
    if (-not $layoutSelection.Success) {
        throw 'Layout selection is required.'
    }
    $sourceLayout = $layoutSelection.SourceLayout
    $destLayout = $layoutSelection.DestLayout

    $sourceFilter = Show-SourceAssetFilterDialog -SourceLayout $sourceLayout
    if (-not $sourceFilter.Success) {
        throw 'Source asset filter selection was cancelled.'
    }

    $layoutToLayoutDirectPossible = $true
    $DirectTransferWanted = $false
    foreach ($field in $sourceLayout.fields) {
        $directMatch = $destLayout.fields | Where-Object {
            $_.label -eq $field.label -and $_.field_type -eq $field.field_type
        } | Select-Object -First 1

        if (-not $directMatch) {
            $layoutToLayoutDirectPossible = $false
            break
        }
    }

    if ($layoutToLayoutDirectPossible) {
        $directFilterSummary = if ($sourceFilter.Enabled) {
            "`r`n`r`nSource filter: only assets where '$($sourceFilter.FieldLabel)' is '$($sourceFilter.DisplayValue ?? $sourceFilter.Value)' will be moved ($($sourceFilter.MatchingCount) matching)."
        } else {
            ''
        }
        $directTransferResult = Show-InputPopup `
            -Title 'Direct Transfer Possible Without Custom Mapping' `
            -inputType 'YesNo' `
            -Prompt "The source and destination layouts have matching fields that would allow for a direct transfer without field-by-field mapping.$directFilterSummary`r`n`r`nDo you want to proceed with a direct transfer?`r`nFor cases like this, it is reccomended."
        $DirectTransferWanted = if ($directTransferResult.Success) { [bool]($directTransferResult.Value) } else { $false }
    }
    if ($DirectTransferWanted) {
        $directReviewFilterSummary = if ($sourceFilter.Enabled) {
            "`r`nSource asset filter: when '$($sourceFilter.FieldLabel)' is '$($sourceFilter.DisplayValue ?? $sourceFilter.Value)' ($($sourceFilter.MatchingCount) matching)."
        } else {
            "`r`nSource asset filter: None."
        }
        $confirmed = Show-TransferReviewDialog -SummaryText "Transferring $($sourceLayout.name) to $($destLayout.name) with direct field mapping.$directReviewFilterSummary`r`n`r`nStart Now?"
        if ($confirmed) {
            $L2Lresults = layout2layout `
                -sourceLayoutName $sourceLayout.name `
                -targetLayoutName $destLayout.name `
                -SourceAssetFilterField $(if ($sourceFilter.Enabled) { $sourceFilter.FieldLabel } else { $null }) `
                -SourceAssetFilterValue $(if ($sourceFilter.Enabled) { $sourceFilter.Value } else { $null }) `
                -SourceAssetFilterValueIsBlank $(if ($sourceFilter.Enabled) { [bool]$sourceFilter.ValueIsBlank } else { $false }) `
                -SourceAssetFilterListId $(if ($sourceFilter.Enabled -and $sourceFilter.ListId) { [int]$sourceFilter.ListId } else { $null })
            $L2Lresults | convertto-json -depth 99 | Out-File -FilePath (Join-Path $script:Root "l2l_transferresults_$(Get-Date -Format 'yyyyMMdd_HHmmss').json") -Encoding utf8
            exit 0
        } else {
            Write-Verbose "Proceeding to custom-mapping workflow per user choice, even though a direct layout-to-layout transfer is possible."
        }
    }

    $initialOptions = Show-InitialTransferOptionsDialog -SourceLayout $sourceLayout -DestLayout $destLayout
    if (-not $initialOptions.Success) {
        throw 'Transfer options were cancelled.'
    }
    $preferredMergeOption = [string]$initialOptions.MergeOption
    $renameSourceLayoutto = [string]$initialOptions.RenameSourceLayoutTo
    $archivePreference = [bool]$initialOptions.ArchivePreference
    $useCustomMatchingCriteria = [bool]$initialOptions.CustomMatchingCriteria

    $reviewFields = @(
        $destLayout.Fields |
        Where-Object { ($_.field_type ?? $_.type) -ne 'AssetTag' } |
        Sort-Object -Property label
    )

    Show-TransferMessage `
        -Title 'Field Review' `
        -Kind Info `
        -Message ("You are about to review {0} destination fields for '{1}'.`r`n`r`nFriendly reminder:`r`n- Required fields should map to a source field or a constant value.`r`n- Skip is best reserved for optional fields.`r`n- Use Back and Next to revisit earlier choices without losing your progress.`r`n- SMOOSH is ideal for notes-style destination fields." -f $reviewFields.Count, $destLayout.Name)

    $relinkedFields = $sourceLayout.Fields | where-object {($_.field_type -eq 'AssetTag') -and $null -ne $_.linkable_id}

    $sourceFieldOptions = @(
        $sourceLayout.Fields |
        Where-Object { $_.label -and ($_.field_type -ne 'AssetTag') } |
        ForEach-Object {
            [pscustomobject]@{
                label      = [string]$_.label
                field_type = [string]($_.field_type)
            }
        }
    ) + [PSCustomObject]@{
        label = "SMOOSH"
        field_type = "Pseudo [multiple source fields]"
    }
    $fieldSelections = [ordered]@{}
    $fieldIndex = 0
    while ($fieldIndex -lt $reviewFields.Count) {
        $field = $reviewFields[$fieldIndex]
        $fieldLabel = [string]$field.label
        $existingSmooshLabels = @(
            foreach ($entry in $fieldSelections.GetEnumerator()) {
                if ([string]$entry.Key -eq $fieldLabel) {
                    continue
                }

                if ($null -ne $entry.Value -and -not $entry.Value.Skip -and [string]$entry.Value.Value.kind -eq 'smoosh') {
                    [string]$entry.Key
                }
            }
        )

        $fieldResult = Show-FieldMappingEditor `
            -DestField $field `
            -SourceFieldOptions $($sourceFieldOptions | sort-object -Property label) `
            -ExistingSmooshLabels $existingSmooshLabels `
            -AllDestinationLabels @($reviewFields | ForEach-Object { [string]$_.label }) `
            -FieldStateByDestination $fieldSelections `
            -InitialSelection $fieldSelections[$fieldLabel] `
            -CurrentIndex ($fieldIndex + 1) `
            -TotalCount $reviewFields.Count `
            -summaryLabel "Mapping for '$($field.label)' $($field.field_type) from $($sourceLayout.Name) to $($destLayout.Name)"

        if (-not $fieldResult.Success) {
            throw "User cancelled mapping."
        }

        if ($fieldResult.ApplySelection -ne $false) {
            $fieldSelections[$fieldLabel] = $fieldResult
        }

        if ([string]$fieldResult.Navigate -eq 'Back') {
            if ($fieldIndex -gt 0) {
                $fieldIndex--
            }
            continue
        }

        $fieldIndex++
    }

    $mappingEntries = @()
    $constantEntries = @()
    $smooshSourceLabels = @()
    $smooshTargetEntry = $null
    $skippedFieldLabels = @()

    foreach ($field in $reviewFields) {
        $fieldLabel = [string]$field.label
        $fieldResult = $fieldSelections[$fieldLabel]

        if ($null -eq $fieldResult -or $fieldResult.Skip) {
            $skippedFieldLabels += $fieldLabel
            continue
        }

        switch ([string]$fieldResult.Value.kind) {
            'constant' {
                $constantEntries += ,$fieldResult.Value
            }
            'smoosh' {
                if ($null -ne $smooshTargetEntry -and $smooshTargetEntry.to -ne $fieldResult.Value.smooshTarget.to) {
                    throw "Only one destination field can be assigned SMOOSH."
                }
                $smooshSourceLabels = @($fieldResult.Value.smooshSourceLabels)
                $smooshTargetEntry = $fieldResult.Value.smooshTarget
            }
            default {
                $mappingEntries += ,$fieldResult.Value
            }
        }
    }

    if ($null -ne $smooshTargetEntry) {
        $mappingEntries += ,$smooshTargetEntry
    }

    $matchCriteria = @()
    if ($useCustomMatchingCriteria) {
        $matchCriteriaResult = Show-MatchCriteriaDialog `
            -SourceLayout $sourceLayout `
            -DestLayout $destLayout `
            -MappingEntries $mappingEntries

        if (-not $matchCriteriaResult.Success) {
            throw 'Custom matching criteria selection was cancelled.'
        }

        $matchCriteria = @($matchCriteriaResult.Criteria)
    }



    $PerJobSettings = ""
    $PerJobSettingSummaries = @()
    $perjobAnswers = @{}
    $perjobQuestions = @(
        @{
            SettingName = 'Include Blank Values In SMOOSH?'
            VariableName = 'includeblanksduringsmoosh'
            DefaultValue = $false
            Description = "Include empty source fields when building the SMOOSH output. Leaving this off usually keeps the combined value cleaner."
        },
        @{
            SettingName = 'Include Relations For Archived Objects?'
            VariableName = 'includeRelationsForArchived'
            DefaultValue = $true
            Description = "Allow archived objects to stay related to the new asset, even if related item is Archived. Turn this off to only relate to active items."
        },
        @{
            SettingName = 'Strip HTML In SMOOSH Output?'
            VariableName = 'excludeHTMLinSMOOSH'
            DefaultValue = $false
            Description = "Remove HTML formatting when SMOOSHing into plain-text destinations. Leave this off to preserve formatting for rich-text fields."
        },
        @{
            SettingName = 'Include Field Labels In SMOOSH Values?'
            VariableName = 'includeLabelInSmooshedValues'
            DefaultValue = $true
            Description = "Prefix each SMOOSHed value with its source field label. Turn this off if you only want the raw combined values."
        }
    )

    $perjobResult = Show-PerJobSettingsDialog -Questions $perjobQuestions -SmooshConfigured ($null -ne $smooshTargetEntry)
    if (-not $perjobResult.Success) {
        throw 'Per-job settings were cancelled.'
    }

    foreach ($perjobQuestion in $perjobQuestions) {
        $answer = if ($perjobResult.Answers.ContainsKey($perjobQuestion.VariableName)) {
            [bool]$perjobResult.Answers[$perjobQuestion.VariableName]
        } else {
            [bool]$perjobQuestion.DefaultValue
        }
        $perjobAnswers[$perjobQuestion.VariableName] = $answer
        $PerJobSettings += '$' + $perjobQuestion.VariableName + ' = $' + $answer + "`r`n"
        $PerJobSettingSummaries += [pscustomobject]@{
            Name  = $perjobQuestion.SettingName.TrimEnd('?')
            Value = $answer
        }
    }

        $reviewedFieldCount = @($destLayout.Fields | Where-Object { ($_.field_type ?? $_.type) -ne 'AssetTag' }).Count
        $configuredFieldCount = $mappingEntries.Count + $constantEntries.Count
        $skippedFieldCount = $skippedFieldLabels.Count
        $smooshTargetLabel = if ($null -ne $smooshTargetEntry) { $smooshTargetEntry.to } else { 'None' }
        $directMappingCount = $mappingEntries.Count - $(if ($null -ne $smooshTargetEntry) { 1 } else { 0 })

        Show-TransferMessage `
            -Title 'Mapping Plan Ready' `
            -Kind Info `
            -Message ("Your mapping plan has been prepared for '{0}' -> '{1}'.`r`n`r`nDirect mappings: {2}`r`nConstants: {3}`r`nSMOOSH target: {4}`r`nSMOOSH source fields: {5}`r`nSkipped fields: {6}`r`n`r`nThis is a good checkpoint to pause and sanity-check the plan before any live transfer run." -f $sourceLayout.Name, $destLayout.Name, $directMappingCount, $constantEntries.Count, $smooshTargetLabel, $smooshSourceLabels.Count, $skippedFieldCount)

        $reviewSummaryText = New-TransferReviewSummary `
            -BaseUrl $state.BaseUrl `
            -ApiKey $state.ApiKey `
            -SourceLayout $sourceLayout `
            -DestLayout $destLayout `
            -MergeOption $preferredMergeOption `
            -ArchivePreference $archivePreference `
            -RenameSourceLayoutTo $renameSourceLayoutto `
            -SourceAssetFilter $sourceFilter `
            -MappingEntries $mappingEntries `
            -ConstantEntries $constantEntries `
            -SmooshSourceLabels $smooshSourceLabels `
            -SmooshTargetEntry $smooshTargetEntry `
            -SkippedFieldLabels $skippedFieldLabels `
            -MatchCriteria $matchCriteria `
            -PerJobSettingSummaries $PerJobSettingSummaries `
            -MapFilePath $mapfile `
            -relinkedFields $relinkedFields

        $confirmed = Show-TransferReviewDialog -SummaryText $reviewSummaryText
        if (-not $confirmed) {
            Show-TransferMessage `
                -Title 'Transfer Cancelled' `
                -Kind Warning `
                -Message 'The transfer was cancelled during final review. No changes were made.'
            return $null
        }
        $results = New-NonInteractiveLayoutTransfer `
            -HuduBaseURL $state.BaseUrl `
            -HuduAPIKey $state.ApiKey `
            -sourceassetlayout $sourceLayout `
            -destassetlayout $destLayout `
            -SmooshSourceLabels $smooshSourceLabels `
            -mapping $mappingEntries `
            -ConstantEntries $constantEntries `
            -SkipOnMatch ($preferredMergeOption -eq 'Skip') `
            -MergeMode $preferredMergeOption `
            -RenameSourceLayoutTo $renameSourceLayoutto `
            -setsourceassetsarchived $archivePreference `
            -SourceAssetFilterField $(if ($sourceFilter.Enabled) { $sourceFilter.FieldLabel } else { $null }) `
            -SourceAssetFilterValue $(if ($sourceFilter.Enabled) { $sourceFilter.Value } else { $null }) `
            -SourceAssetFilterValueIsBlank $(if ($sourceFilter.Enabled) { [bool]$sourceFilter.ValueIsBlank } else { $false }) `
            -SourceAssetFilterListId $(if ($sourceFilter.Enabled -and $sourceFilter.ListId) { [int]$sourceFilter.ListId } else { $null }) `
            -MatchCriteria $matchCriteria `
            -IncludeLabelInSmooshedValues ($perjobAnswers["includeLabelInSmooshedValues"] ?? $false) `
            -IncludeBlanksDuringSmoosh ($perjobAnswers["includeblanksduringsmoosh"] ?? $false) `
            -ExcludeHTMLinSmoosh ($perjobAnswers["excludeHTMLinSmoosh"] ?? $false) `
            -DescribeRelatedInSmoosh $false `
            -includeRelationsForArchived ($perjobAnswers["includeRelationsForArchived"] ?? $true)

        $results | convertto-json -depth 99 | Out-File -FilePath (Join-Path $script:Root "transferresults_$(Get-Date -Format 'yyyyMMdd_HHmmss').json") -Encoding utf8
        exit 0
}

if (-not $NoAutoLaunch -and $MyInvocation.InvocationName -ne '.') {
    $script:Gui = $true
    New-GuiJob
}
