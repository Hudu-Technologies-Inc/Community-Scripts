param(
    [string]$FieldLabel,
    [string[]]$LayoutNames = $null,
    [switch]$SkipAssetUpdate,
    [string]$HuduBaseURL,
    [string]$HuduAPIKey
)

# HuduAPI responses are sometimes returned directly and sometimes wrapped
# under properties like asset_layout, asset, or list. Normalize those shapes
# so the rest of the script can work with one object style.
function Get-HuduObject {
    param([object]$Object)

    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties['asset_layout']) { return $Object.asset_layout }
    if ($Object.PSObject.Properties['asset']) { return $Object.asset }
    if ($Object.PSObject.Properties['list']) { return $Object.list }

    return $Object
}

# Field labels are user-facing text, so match them case-insensitively while
# preserving the original label casing when we write data back to Hudu.
function Get-FieldByLabel {
    param(
        [Parameter(Mandatory)][object]$Fields,
        [Parameter(Mandatory)][string]$Label
    )

    return $Fields | Where-Object { $_.label -ieq $Label } | Select-Object -First 1
}

# Pull every non-empty value from a given Text field on one layout.
# The cross-layout collector calls this once per matching layout.
function Get-AssetFieldUniqueValues {
    param(
        [Parameter(Mandatory)][pscustomobject]$AssetLayout,
        [Parameter(Mandatory)][string]$Label
    )

    $assetLayout = Get-HuduObject $AssetLayout
    $assetLayoutId = [int]($assetLayout.id ?? $null)
    if (-not $assetLayoutId) { return @() }

    $matchingField = Get-FieldByLabel -Fields ($assetLayout.fields ?? @()) -Label $Label
    if (-not $matchingField) { return @() }

    Write-Host "    $($assetLayout.name): obtaining values from '$Label'..." -ForegroundColor Green
    $assets = @(Get-HuduAssets -AssetLayoutId $assetLayoutId)
    $matches = @()

    foreach ($assetObj in $assets) {
        $asset = Get-HuduObject $assetObj
        $fieldValue = (Get-FieldByLabel -Fields ($asset.fields ?? @()) -Label $Label).value
        if ($null -ne $fieldValue -and -not [string]::IsNullOrWhiteSpace([string]$fieldValue)) {
            $matches += ([string]$fieldValue).Trim()
        }
    }

    return @($matches | Sort-Object -Unique)
}

# Small inspection helper used by the interactive picker when objects need
# more detail than a single name can show.
function Write-InspectObject {
    param (
        [object]$Object,
        [int]$Depth = 32,
        [int]$MaxLines = 16
    )

    $stringifiedObject = $null

    if ($null -eq $Object) {
        return "Unreadable Object (null input)"
    }

    $stringifiedObject = try {
        $json = $Object | ConvertTo-Json -Depth $Depth -ErrorAction Stop
        "# Type: $($Object.GetType().FullName)`n$json"
    } catch { $null }

    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $Object | Format-Table -Force | Out-String
        } catch { $null }
    }

    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $Object | Format-List -Force | Out-String
        } catch { $null }
    }

    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $props = $Object | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            $lines = foreach ($prop in $props) {
                try {
                    "$prop = $($Object.$prop)"
                } catch {
                    "$prop = <unreadable>"
                }
            }
            "# Type: $($Object.GetType().FullName)`n" + ($lines -join "`n")
        } catch {
            "Unreadable Object"
        }
    }

    if (-not $stringifiedObject) {
        $stringifiedObject = try { "$($Object.ToString())" } catch { $null }
    }

    $lines = $stringifiedObject -split "`r?`n"
    if ($lines.Count -gt $MaxLines) {
        $lines = $lines[0..($MaxLines - 1)] + "... (truncated)"
    }

    return $lines -join "`n"
}

# Reusable numbered menu for interactive script runs.
function Select-ObjectFromList($Objects, $Message, $InspectObjects = $false, $AllowNull = $false) {
    $objects = @($Objects)
    $validated = $false

    while (-not $validated) {
        if ($AllowNull) {
            Write-Host "0: None/Custom"
        }

        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]

            $displayLine = if ($InspectObjects) {
                "$($i + 1): $(Write-InspectObject -Object $object)"
            } elseif ($null -ne $object.OptionMessage) {
                "$($i + 1): $($object.OptionMessage)"
            } elseif ($null -ne $object.name) {
                "$($i + 1): $($object.name)"
            } else {
                "$($i + 1): $($object)"
            }

            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }

        $choice = Read-Host $Message

        if (-not ($choice -as [int])) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }

        $choice = [int]$choice

        if ($choice -eq 0 -and $AllowNull) {
            return $null
        }

        if ($choice -ge 1 -and $choice -le $objects.Count) {
            return $objects[$choice - 1]
        }

        Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
    }
}

# Asset layout updates must send the full field collection back to Hudu.
# This helper preserves the fields we are not changing and keeps ListSelect
# metadata intact so existing layout fields are not accidentally stripped.
function New-LayoutFieldPayload($Field) {
    $payload = [ordered]@{
        id           = $Field.id
        label        = $Field.label
        field_type   = $Field.field_type
        required     = [bool]$Field.required
        show_in_list = [bool]($Field.show_in_list ?? $true)
        position     = [int]($Field.position ?? 0)
    }

    if ($Field.field_type -eq 'ListSelect' -and $Field.PSObject.Properties['list_id']) {
        $payload.list_id = [int]$Field.list_id
        if ($Field.PSObject.Properties['multiple_options']) {
            $payload.multiple_options = [bool]$Field.multiple_options
        }
    }

    return $payload
}

# Build a case-insensitive lookup of list item names by list ID. The values
# remain the canonical names stored in Hudu, which matters when updating assets.
function Refresh-ListCache {
    $listNameExistsByListId = @{}

    foreach ($listObj in Get-HuduLists) {
        $list = Get-HuduObject $listObj
        $listId = [int]$list.id
        $map = @{}

        foreach ($item in ($list.list_items ?? @())) {
            if ($item.name) {
                $map[$item.name.ToString().Trim().ToLowerInvariant()] = [string]$item.name
            }
        }

        $listNameExistsByListId[$listId] = $map
    }

    return $listNameExistsByListId
}

# Ensure a value exists in the target list and return the canonical item name.
# This keeps reruns idempotent and avoids repeated list reads for known items.
function Ensure-HuduListItemByName {
    param(
        [Parameter(Mandatory)][int]$ListId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$ListNameExistsByListId
    )

    $nameTrim = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($nameTrim)) { return $null }

    $needle = $nameTrim.ToLowerInvariant()
    if (-not $ListNameExistsByListId.ContainsKey($ListId)) {
        $ListNameExistsByListId[$ListId] = @{}
    }

    $map = $ListNameExistsByListId[$ListId]
    if ($map.ContainsKey($needle)) {
        return $map[$needle]
    }

    $list = Get-HuduObject (Get-HuduLists -Id $ListId)
    $items = @()

    foreach ($existing in ($list.list_items ?? @())) {
        if ($existing.id) {
            $items += @{ id = [int]$existing.id; name = [string]$existing.name }
        } else {
            $items += @{ name = [string]$existing.name }
        }
    }

    $items += @{ name = $nameTrim }
    $null = Set-HuduList -Id $ListId -Name $list.name -ListItems $items
    $map[$needle] = $nameTrim

    return $nameTrim
}

# Find layouts that contain the requested field as a Text field. Layout filters
# are optional; when supplied, unmatched requested layouts are reported.
function Find-LayoutsWithField {
    param(
        [Parameter(Mandatory)][string]$FieldLabel,
        [string[]]$LayoutFilter = $null
    )

    $layouts = @()
    $allLayouts = @(Get-HuduAssetLayouts | ForEach-Object { Get-HuduObject $_ })

    foreach ($layout in $allLayouts) {
        if ($LayoutFilter -and -not ($LayoutFilter | Where-Object { $_ -ieq $layout.name })) {
            continue
        }

        $matchingField = Get-FieldByLabel -Fields ($layout.fields ?? @()) -Label $FieldLabel
        if (-not $matchingField) { continue }

        if ($matchingField.field_type -ne 'Text') {
            Write-Warning "Layout '$($layout.name)' has '$FieldLabel', but it is '$($matchingField.field_type)' instead of 'Text'. Skipping."
            continue
        }

        $layouts += $layout
    }

    if ($LayoutFilter) {
        $foundNames = @($layouts | ForEach-Object { $_.name })
        foreach ($requestedName in $LayoutFilter) {
            if (-not ($foundNames | Where-Object { $_ -ieq $requestedName })) {
                Write-Warning "Requested layout '$requestedName' was not found with a Text field named '$FieldLabel'."
            }
        }
    }

    return $layouts
}

# When no field label is passed, show the user Text fields grouped by label
# and ordered by how many layouts they appear on.
function Get-CommonTextFieldOptions {
    $allLayouts = @(Get-HuduAssetLayouts | ForEach-Object { Get-HuduObject $_ })
    $fieldStats = @{}

    foreach ($layout in $allLayouts) {
        foreach ($field in @(($layout.fields ?? @()) | Where-Object { $_.field_type -eq 'Text' })) {
            $key = $field.label.ToString().Trim().ToLowerInvariant()
            if (-not $fieldStats.ContainsKey($key)) {
                $fieldStats[$key] = [pscustomobject]@{
                    name          = [string]$field.label
                    LayoutCount   = 0
                    OptionMessage = $null
                }
            }

            $fieldStats[$key].LayoutCount++
        }
    }

    return @(
        $fieldStats.Values |
            Sort-Object -Property @{ Expression = 'LayoutCount'; Descending = $true }, name |
            ForEach-Object {
                $_.OptionMessage = "$($_.name) ($($_.LayoutCount) layouts)"
                $_
            }
    )
}

# Aggregate values across all eligible layouts so the shared list is built from
# the complete set, not from one layout at a time.
function Collect-UniqueValuesAcrossLayouts {
    param(
        [Parameter(Mandatory)][string]$FieldLabel,
        [Parameter(Mandatory)][pscustomobject[]]$Layouts
    )

    $allValues = @()

    foreach ($layout in $Layouts) {
        $values = @(Get-AssetFieldUniqueValues -AssetLayout $layout -Label $FieldLabel)
        $sample = if ($values.Count -gt 0) {
            ($values | Select-Object -First 5) -join ', '
        } else {
            'none'
        }

        Write-Host "    $($layout.name): $($values.Count) unique values ($sample)" -ForegroundColor Yellow
        $allValues += $values
    }

    return @($allValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
}

# Create the shared Hudu list, or append missing items to the existing one.
# Existing item IDs are preserved in the Set-HuduList payload.
function Ensure-ConsolidatedHuduList {
    param(
        [Parameter(Mandatory)][string]$FieldLabel,
        [AllowEmptyCollection()][string[]]$Values = @()
    )

    $listName = "$($FieldLabel)s"
    $values = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
    $list = Get-HuduLists -Name $listName | Select-Object -First 1
    $list = Get-HuduObject $list

    if ($null -eq $list) {
        Write-Host "[+] Creating consolidated list '$listName'..." -ForegroundColor Green
        $createdList = Get-HuduObject (New-HuduList -Name $listName -Items $values)
        return (Get-HuduObject $createdList)
    }

    Write-Host "[+] Updating existing consolidated list '$listName'..." -ForegroundColor Green
    $items = @()
    $existingNames = @{}

    foreach ($existing in ($list.list_items ?? @())) {
        if ([string]::IsNullOrWhiteSpace([string]$existing.name)) { continue }

        $items += @{ id = [int]$existing.id; name = [string]$existing.name }
        $existingNames[$existing.name.ToString().Trim().ToLowerInvariant()] = $true
    }

    $added = 0
    foreach ($value in $values) {
        $needle = $value.Trim().ToLowerInvariant()
        if ($existingNames.ContainsKey($needle)) { continue }

        $items += @{ name = $value.Trim() }
        $existingNames[$needle] = $true
        $added++
    }

    if ($added -gt 0) {
        $null = Set-HuduList -Id ([int]$list.id) -Name $listName -ListItems $items
        Write-Host "    Added $added new list items." -ForegroundColor Green
        $list = Get-HuduObject (Get-HuduLists -Id ([int]$list.id))
    } else {
        Write-Host "    No new list items needed." -ForegroundColor Yellow
    }

    return $list
}

# Add the new ListSelect field to one layout while leaving the original Text
# field in place for review and rollback safety.
function Update-LayoutWithConsolidatedList {
    param(
        [Parameter(Mandatory)][pscustomobject]$Layout,
        [Parameter(Mandatory)][string]$FieldLabel,
        [Parameter(Mandatory)][int]$ListId
    )

    $layout = Get-HuduObject (Get-HuduAssetLayouts -Name $Layout.name | Select-Object -First 1)
    if (-not $layout) {
        Write-Warning "Asset Layout '$($Layout.name)' was not found during update."
        return $null
    }

    $newFieldLabel = "$FieldLabel List"
    if (Get-FieldByLabel -Fields ($layout.fields ?? @()) -Label $newFieldLabel) {
        Write-Host "    $($layout.name): already has field '$newFieldLabel'; skipping layout update." -ForegroundColor Yellow
        return $layout
    }

    $layoutFields = @(foreach ($field in ($layout.fields ?? @())) { New-LayoutFieldPayload $field })
    $layoutFields += [ordered]@{
        label        = $newFieldLabel
        field_type   = 'ListSelect'
        list_id      = $ListId
        required     = $false
        show_in_list = $true
        position     = 2 + $layout.fields.Count
    }

    Write-Host "    $($layout.name): adding field '$newFieldLabel'." -ForegroundColor Green
    $updatedLayout = Get-HuduObject (Set-HuduAssetLayout -Id $layout.id -Fields $layoutFields)

    return $updatedLayout
}

# Copy each asset's old Text value into the new ListSelect field. Individual
# asset failures are warnings so one bad record does not stop the whole run.
function Migrate-AssetsToConsolidatedList {
    param(
        [Parameter(Mandatory)][pscustomobject]$Layout,
        [Parameter(Mandatory)][string]$OriginalFieldLabel,
        [Parameter(Mandatory)][string]$NewFieldLabel,
        [Parameter(Mandatory)][int]$ListId,
        [Parameter(Mandatory)][hashtable]$ListItemCache
    )

    $layout = Get-HuduObject $Layout
    $assets = @(Get-HuduAssets -AssetLayoutId ([int]$layout.id))
    $updated = 0

    foreach ($assetObj in $assets) {
        $asset = Get-HuduObject $assetObj
        $sourceValue = (Get-FieldByLabel -Fields ($asset.fields ?? @()) -Label $OriginalFieldLabel).value
        $sourceValue = [string]$sourceValue

        if ([string]::IsNullOrWhiteSpace($sourceValue)) { continue }

        try {
            $canonical = Ensure-HuduListItemByName -ListId $ListId -Name $sourceValue -ListNameExistsByListId $ListItemCache
            if ([string]::IsNullOrWhiteSpace($canonical)) { continue }

            Set-HuduAsset -Id $asset.id -Name $asset.name -CompanyID $asset.company_id -Fields @(@{ $NewFieldLabel = $canonical }) | Out-Null
            $updated++
        } catch {
            Write-Warning "Failed updating asset '$($asset.name)' ($($asset.id)) in layout '$($layout.name)' - $_"
        }
    }

    return [pscustomobject]@{
        LayoutName  = $layout.name
        TotalAssets = $assets.Count
        Updated     = $updated
    }
}

# Main workflow: discover layouts, aggregate values, create/update the shared
# list, add layout fields, and optionally migrate assets.
function Consolidate-ListifyTextField {
    param(
        [Parameter(Mandatory)][string]$FieldLabel,
        [string[]]$LayoutNames = $null,
        [switch]$SkipAssetUpdate
    )

    $newFieldLabel = "$FieldLabel List"

    Write-Host "[+] Scanning for layouts with Text field '$FieldLabel'..." -ForegroundColor Green
    $layouts = @(Find-LayoutsWithField -FieldLabel $FieldLabel -LayoutFilter $LayoutNames)
    if ($layouts.Count -eq 0) {
        Write-Host "[-] No eligible layouts found with Text field '$FieldLabel'." -ForegroundColor Red
        return
    }

    Write-Host "    Found $($layouts.Count) layouts: $(($layouts | ForEach-Object { $_.name }) -join ', ')" -ForegroundColor Yellow

    Write-Host "[+] Collecting unique values..." -ForegroundColor Green
    $allValues = @(Collect-UniqueValuesAcrossLayouts -FieldLabel $FieldLabel -Layouts $layouts)
    Write-Host "[+] Total unique values: $($allValues.Count)" -ForegroundColor Green

    $list = Ensure-ConsolidatedHuduList -FieldLabel $FieldLabel -Values $allValues
    $list = Get-HuduObject $list
    $listId = [int]($list.id ?? $null)
    if (-not $listId) {
        throw "Unable to determine consolidated list ID."
    }
    Write-Host "    List ID: $listId" -ForegroundColor Yellow

    Write-Host "[+] Updating layouts..." -ForegroundColor Green
    $updatedLayouts = @()
    foreach ($layout in $layouts) {
        $updatedLayout = Update-LayoutWithConsolidatedList -Layout $layout -FieldLabel $FieldLabel -ListId $listId
        if ($updatedLayout) {
            $updatedLayouts += $updatedLayout
        }
    }

    if ($SkipAssetUpdate) {
        Write-Host "[+] Skipped asset migration because -SkipAssetUpdate was supplied." -ForegroundColor Yellow
        Write-Host "[+] Complete: consolidated list '$($list.name)' applied to $($updatedLayouts.Count) layouts." -ForegroundColor Green
        return
    }

    Write-Host "[+] Migrating assets to '$newFieldLabel'..." -ForegroundColor Green
    $listItemCache = Refresh-ListCache
    $totalUpdated = 0
    $totalAssets = 0

    foreach ($layout in $updatedLayouts) {
        $result = Migrate-AssetsToConsolidatedList -Layout $layout -OriginalFieldLabel $FieldLabel -NewFieldLabel $newFieldLabel -ListId $listId -ListItemCache $listItemCache
        $totalUpdated += $result.Updated
        $totalAssets += $result.TotalAssets
        Write-Host "    $($result.LayoutName): updated $($result.Updated) of $($result.TotalAssets) assets." -ForegroundColor Yellow
    }

    Write-Host "[+] Complete: $totalUpdated assets updated across $($updatedLayouts.Count) layouts ($totalAssets assets checked)." -ForegroundColor Green
}

function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
        [bool]$UseHuduFork = $true
    )

    if ($true -eq $UseHuduFork) {
        if (-not $(Test-Path $HAPImodulePath)) {
            $dst = Split-Path -Path (Split-Path -Path $HAPImodulePath -Parent) -Parent
            Write-Host "Using latest master branch of Hudu fork for HuduAPI"
            $zip = "$env:TEMP\huduapi.zip"
            Invoke-WebRequest -Uri "https://github.com/Hudu-Technologies-Inc/HuduAPI/archive/refs/heads/master.zip" -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
            $extracted = Join-Path $env:TEMP "HuduAPI-master"
            if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
            Move-Item -Path $extracted -Destination $dst
            Remove-Item $zip -Force
        }
    } else {
        Write-Host "Assuming PSGallery module if not already locally cloned at $HAPImodulePath"
    }

    if (Test-Path $HAPImodulePath) {
        Import-Module $HAPImodulePath -Force
        Write-Host "Module imported from $HAPImodulePath"
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}

# The listifying workflow relies on ListSelect layout behavior available in
# supported Hudu versions, so check before making changes.
function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.37.1"
    )

    Write-Host "Required Hudu version: $RequiredHuduVersion" -ForegroundColor Blue
    try {
        $huduAppInfo = Get-HuduAppInfo
        $currentHuduVersion = $huduAppInfo.version

        if ([version]$currentHuduVersion -lt [version]$RequiredHuduVersion) {
            Write-Host "This script requires at least version $RequiredHuduVersion and cannot run with version $currentHuduVersion. Please update your version of Hudu." -ForegroundColor Red
            exit 1
        }

        Write-Host "Hudu version $currentHuduVersion is compatible." -ForegroundColor Green
    } catch {
        Write-Host "Error encountered when checking Hudu version for $(Get-HuduBaseURL) - $_" -ForegroundColor Yellow
    }
}

# Match the existing Listify script's PowerShell version requirement.
function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSVersion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Version
    Write-Host "Required PowerShell version: $RequiredPSVersion" -ForegroundColor Blue

    if ($currentPSVersion -lt $RequiredPSVersion) {
        Write-Host "PowerShell $RequiredPSVersion or higher is required. You have $currentPSVersion." -ForegroundColor Red
        exit 1
    }

    Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
}

# Prompt for Hudu connection details unless they were supplied as parameters.
function Set-HuduInstance {
    param(
        [string]$BaseUrl,
        [string]$ApiKey
    )

    $BaseUrl = $BaseUrl ??
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $ApiKey = $ApiKey ?? "$(Read-Host 'Please Enter Hudu API Key')"

    while ($ApiKey.Length -ne 24) {
        $ApiKey = (Read-Host -Prompt "Get a Hudu API Key from $BaseUrl/admin/api_keys").Trim()
        if ($ApiKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($ApiKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }

    New-HuduAPIKey $ApiKey
    New-HuduBaseURL $BaseUrl
}

# Bootstrap the HuduAPI module and connection before any discovery or writes.
Get-PSVersionCompatible
Get-HuduModule
Set-HuduInstance -BaseUrl $HuduBaseURL -ApiKey $HuduAPIKey
Get-HuduVersionCompatible

# Interactive fallback: if the caller did not pass a field label, offer the
# most common Text fields across layouts as likely consolidation candidates.
if ([string]::IsNullOrWhiteSpace($FieldLabel)) {
    $fieldOptions = @(Get-CommonTextFieldOptions)
    if ($fieldOptions.Count -eq 0) {
        Write-Host "No Text fields were found in any asset layouts." -ForegroundColor Red
        return
    }

    $selectedField = Select-ObjectFromList -Message "Which Text field should be consolidated across layouts?" -Objects $fieldOptions
    $FieldLabel = $selectedField.name
}

# Do a preflight discovery before confirmation so the user can see exactly
# which layouts will be touched.
$matchedLayouts = @(Find-LayoutsWithField -FieldLabel $FieldLabel -LayoutFilter $LayoutNames)
if ($matchedLayouts.Count -eq 0) {
    Write-Host "No eligible layouts found for '$FieldLabel'." -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "About to consolidate Text field '$FieldLabel' into a shared list named '$($FieldLabel)s'." -ForegroundColor Cyan
Write-Host "Layouts: $(($matchedLayouts | ForEach-Object { $_.name }) -join ', ')" -ForegroundColor Cyan
if ($SkipAssetUpdate) {
    Write-Host "Asset updates will be skipped." -ForegroundColor Yellow
} else {
    Write-Host "Assets with non-empty '$FieldLabel' values will be migrated to '$FieldLabel List'." -ForegroundColor Cyan
}

Read-Host "Press Enter to continue, or Ctrl+C to cancel"

# Run the confirmed operation.
Consolidate-ListifyTextField -FieldLabel $FieldLabel -LayoutNames $LayoutNames -SkipAssetUpdate:$SkipAssetUpdate
