function Get-AssetFieldUniqueValues {
    param([pscustomobject]$assetLayout,[string]$label)
    $assetlayout = $assetLayout.asset_layout ?? $assetLayout; $assetlayoutid = [int]($assetlayout.id ?? $null);
    if (-not $assetlayoutid -or -not $assetLayout) {return $null}
    if ($assetLayout.fields | Where-Object { $_.label -ieq $label } | Select-Object -First 1) {
        write-host "found field $label in AL $assetlayoutname" -ForegroundColor Green
    } else {
        return $null
    }
    Write-Host "obtaining unique field values for $label in Asset Layout $assetLayoutName" -ForegroundColor Green
    $allassets = Get-HuduAssets -AssetLayoutId $assetlayoutid
    $matches = @()

    foreach ($a in $allassets) {
        $asset = $a.asset ?? $a

        $fieldvalue = ($asset.fields | Where-Object { $_.label -ieq $label } | Select-Object -First 1).value

        if ($null -ne $fieldvalue -and -not ([string]::IsNullOrWhiteSpace($fieldvalue))) {
            $matches += $fieldvalue
        }
    }

    return $matches | Sort-Object -Unique
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

function New-LayoutFieldPayload($Field){
  $o = [ordered]@{
    id           = $Field.id
    label        = $Field.label
    field_type   = $Field.field_type
    required     = [bool]$Field.required
    show_in_list = [bool]($Field.show_in_list ?? $true)
    position     = [int]($Field.position ?? 0)
  }
  if ($Field.field_type -eq 'ListSelect' -and $Field.PSObject.Properties['list_id']) {
    $o.list_id = [int]$Field.list_id
    if ($Field.PSObject.Properties['multiple_options']) {
      $o.multiple_options = [bool]$Field.multiple_options
    }
  }
  $o
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
    Refresh-ListCache
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

function Listify-TextField {
    param ([PSCustomObject]$assetlayout,[string]$fieldLabel)
    
    $assetlayout = $assetlayout.asset_layout ?? $assetlayout
    $assetLayoutName = $assetlayout.name

    if (($null -eq $assetlayout) -or ([string]::IsNullOrWhiteSpace($assetLayoutName)) -or [string]::IsNullOrWhiteSpace($fieldLabel)) {write-host "assetLayout and fieldLabel are required parameters" -ForegroundColor Yellow; return;}
    $assetLayout = Get-HuduAssetLayouts -Name $assetLayoutName | select-object -first 1
    $assetlayout = $assetlayout.asset_layout ?? $assetLayout
    
    # validate layout and matched field
    if (-not $assetlayout) {write-host "Asset Layout $assetLayoutName not found, skipping" -ForegroundColor Yellow; return;}
    $matchingField = $assetlayout.fields | Where-Object { $_.label -ieq $fieldLabel } | Select-Object -First 1
    if (-not $matchingField) {
        write-host "Field $fieldLabel not found in Asset Layout $assetLayoutName, skipping" -ForegroundColor Yellow; return;
    } elseif ($matchingField.field_type -ne "Text") {
        write-host "Field $fieldLabel in Asset Layout $assetLayoutName is field type of $($matchingField.field_type), but must be of type 'Text'. Skipping ineligible field" -ForegroundColor Yellow; return;
    }

    $newFieldLabel = "$fieldLabel List"

    # get unique values and create/ensure list
    $values = Get-AssetFieldUniqueValues -assetLayout $assetLayout -label $fieldLabel
    if ($null -eq $values -or $values.count -lt 1) {return $null} else {write-host "Found $($values.count) unique values for field $fieldLabel in Asset Layout $assetLayoutName" -ForegroundColor Yellow}
    $listName = "$assetLayoutName - $($fieldLabel)s"
    $list = get-hudulists -name $listName | select-object -first 1
    if ($null -eq $list){
        $list = New-HuduList -Name $listName -Items $values;
        $listId = [int]($list.list?.id ?? $list.id);
        write-host "created list $listName with id $listId" -ForegroundColor Green
    } else {
        $listNameExistsByListId = Refresh-ListCache

        foreach ($v in $values) {
            Ensure-HuduListItemByName -ListId ([int]$list.id) -Name $v  -listNameExistsByListId $listNameExistsByListId | Out-Null
        }
        $listId = [int]($list.list?.id ?? $list.id)
        write-host "updated found list $listName with id $listId" -ForegroundColor Green
    }


    $assetlayout = Get-HuduAssetLayouts -Name $assetLayoutName; $assetlayout = $assetlayout.asset_layout ?? $assetlayout;
    if ($assetlayout.fields | Where-Object { $_.label -ieq $newFieldLabel } | Select-Object -First 1) {
        write-host "Asset Layout $assetLayoutName already has field $newFieldLabel, skipping layout update" -ForegroundColor Yellow
    } else {
        write-host "updating Asset Layout $assetLayoutName to add field $newFieldLabel" -ForegroundColor Green
        $layoutFields = @(foreach ($f in $assetlayout.fields) { New-LayoutFieldPayload $f })
        $layoutFields += [ordered]@{
            label        = "$newFieldLabel"
            field_type   = 'ListSelect'
            list_id      = $list.id ?? $listId
            required     = $false
            show_in_list = $true
            position     = 2 + $assetlayout.fields.Count
        }

        # update layout with list
        $assetlayout = set-HuduAssetLayout -id $assetlayout.id -Fields $layoutFields
        $assetlayout = $assetlayout.asset_layout ?? $assetlayout
    }

    # GENERATE asset payloads
    $listNameExistsByListId = Refresh-ListCache
    $layoutDefByLabel = @{}
    foreach ($lf in ($assetlayout.fields ?? @())) {
        $layoutDefByLabel[$lf.label.ToString().Trim().ToLowerInvariant()] = $lf
    }
    $updated = 0
    write-host "Obtaining assets for Asset Layout $assetLayoutName for update" -ForegroundColor Green
    $relatedAssets = (Get-HuduAssets -AssetLayoutId $assetlayout.id)
    write-host "Updating $($relatedAssets.Count) possible assets in Asset Layout $assetLayoutName to use List field $newFieldLabel" -ForegroundColor Green
    foreach ($assetObj in $relatedAssets) {
        $asset = $assetObj.asset ?? $assetObj

        $srcVal = ($asset.fields | Where-Object { $_.label -ieq $FieldLabel } | Select-Object -First 1).value
        $srcVal = [string]$srcVal
        if ([string]::IsNullOrWhiteSpace($srcVal)) { continue }

        
        $canonical = Ensure-HuduListItemByName -ListId $listId -Name $srcVal -listNameExistsByListId $listNameExistsByListId
        if ([string]::IsNullOrWhiteSpace($canonical)) { continue }

        
        try {
            Set-HuduAsset -Id $asset.id -Name $asset.name -CompanyID $asset.company_id -Fields  @(@{ $newFieldLabel = $canonical }) | Out-Null
            $updated++
        } catch {
            Write-Warning "Failed updating asset $($asset.id) - $_"
        }
    }
    write-host "Updated $updated assets of $($relatedAssets.Count) (those with non-empty values for $fieldLabel) in Asset Layout $assetLayoutName to use List field $newFieldLabel" -ForegroundColor Green

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
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}
function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.37.1",
        $DisallowedVersions = @([version]"2.37.0")
    )
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

function Set-HuduInstance {
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


Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible;

$allLayouts = Get-HuduAssetLayouts
$allLayouts = $allLayouts | where-object { ($_.asset_layout ?? $_).fields | where-object { $_.field_type -ieq "Text" } | select-object -first 1 }

$ForLayout = $null
$forLayout = Select-ObjectFromList -message "For Which layout to convert text field to list field?" -objects $allLayouts
$forlayout = $forlayout.asset_layout ?? $forlayout

$ForField = Select-ObjectFromList -message "Which text field to convert to list field?" -objects ($forlayout.fields | where-object { $_.field_type -ieq "Text" }) -inspectObjects $true

Read-Host "About to convert text field '$($forfield.label)' in Asset Layout '$($forlayout.name)' to List field. Press Enter to continue..."

Listify-TextField -assetlayout $forlayout -fieldlabel $forfield.label

Start-Process "https://$((Get-HuduBaseURL) -replace '^https?://')/admin/asset_layouts/$($forlayout.slug)"
start-Process "https://$((Get-HuduBaseURL) -replace '^https?://')/global/global_assets?asset_layout=$($forlayout.slug)"
