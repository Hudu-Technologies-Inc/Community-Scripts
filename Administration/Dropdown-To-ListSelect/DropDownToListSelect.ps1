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
        [version]$RequiredHuduVersion = [version]"2.39.4",
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

function Get-SafeFilename {
    param([string]$Name,
        [int]$MaxLength=25
    )

    # If there's a '?', take only the part before it
    $BaseName = $Name -split '\?' | Select-Object -First 1

    # Extract extension (including the dot), if present
    $Extension = [System.IO.Path]::GetExtension($BaseName)
    $NameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseName)

    # Sanitize name and extension
    $SafeName = $NameWithoutExt -replace '[\\\/:*?"<>|]', '_'
    $SafeExt = $Extension -replace '[\\\/:*?"<>|]', '_'

    # Truncate base name to 25 chars
    if ($SafeName.Length -gt $MaxLength) {
        $SafeName = $SafeName.Substring(0, $MaxLength)
    }

    return "$SafeName$SafeExt"
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

function Get-NormalizedOptions {
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
  if ($out.Count -eq 0) { @('None','N/A') } else { $out.ToArray() }
}
function New-LayoutFieldPayload($Field){
  $o = [ordered]@{
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

function Set-DropDownsToListSelect {
  param (
    [PSCustomObject]$layout,
    [bool]$ReuseListsWherePossible = $false,
    [bool]$PrefixLayoutNameInList = $true
  )
    $layout = $layout.asset_layout ?? $layout
    $Errored = @{ Lists=@(); Assets=@(); Layouts=@(); Relations=@(); Passwords=@() }
    $Processed = @{ Lists=@(); Assets=@(); Layouts=@(); Relations=@(); Passwords=@() }

    $dropFields = $layout.fields | Where-Object { $_.field_type -match '^(DropDown|Dropdown)$' }
    if (-not $dropFields -or $dropFields.Count -eq 0) { Write-Host "No Dropdown fields in $($layout.name)"; return $Errored }

    ###### 1 -- Create (or select per-user) Lists to replace dropdowns with same options
    $mapsForLayout = @()
    $idx = 0
    foreach ($f in $dropFields) {
      $idx++
      $options = Get-NormalizedOptions -OptionsRaw $f.options
      if ($true -eq $PrefixLayoutNameInList){$expectedListname = "$($layout.name)-$($f.label)"} else {$expectedListname = $f.label}
      $listName = Get-UniqueListName -BaseName $expectedListname -allowReuse $($ReuseListsWherePossible ?? $false)
      $Processed.Lists += @{Action="determined list $($idx) of $($dropFields.count) for $($layout.name) name as $listname for source field $($f.label)"}      
      Write-Host "$($($Processed.Lists | Select-Object -Last 1).Action)"

      try {
        $newList = New-HuduList -name $listName -Items $options
      } catch {
        $Errored.Lists += @{ Issue="Create list failed"; Layout=$layout.name; Field=$f.label; Options=($options -join ','); Exception=$_ }
        return [PSCustomObject]@{Errored = $Errored; Processed = $Processed; Reason = "Create list failed for $listname"}
      }
      if (-not $newList -or -not $newList.id) {
        $Errored.Lists += @{ Issue="No list id returned"; Layout=$layout.name; Field=$f.label; Options=($options -join ',') }
        return [PSCustomObject]@{Errored = $Errored; Processed = $Processed; Reason = "No list id returned during list create for $listname"}
      }
      $Processed.Lists += @{Action="Created New List $($newlist.id) - Named $($listname) with $($options -join ",")"}

      $itemByText = @{}
      foreach ($it in $newList.items) {
        if ($it.name) { $itemByText[$it.name] = $it.id }
      }
      $newLabel = $f.label

      $mapsForLayout += @{
        From      = $f
        List      = $newList
        ItemByText= $itemByText
        NewLabel  = $newLabel
      }
    }

  if ($mapsForLayout.Count -eq 0) {Write-Host "Nothing mapped for layout, skipping $($layout.name)"
    return [PSCustomObject]@{Errored = $Errored; Processed = $Processed; Reason = "Nothing mapped for layout, skipping $($layout.name)"}
  }
  $Processed.Lists += @{Action="Mapped $($mapsForLayout.Count) Dropdowns to Listselects for layout $($layout.name)"}

  ###### 2 - create new layout with ListSelect fields
  $newlayoutRequest = @{}
  foreach ($prop in $($layout | Get-Member -MemberType Properties)){
    $propName = $prop.Name
    if ($propname -ilike "Id" -or $propname -ilike "Fields" -or $propname -ilike "Custom_Fields" -or $propname -ilike "Name"){write-host "skipping prop $propname for layout $($layout.name)"; continue}
      Write-Host "Setting prop $propname for new layout"
      $newlayoutRequest[$PropName]=$layout.$propName
    }
    foreach ($unwantedProp in @("fields","custom_fields","Id","updated_at","created_at","slug","location","active","sidebar_folder_id")){
      $newlayoutRequest.Remove($unwantedProp)
    }
    # add back all normal fields to new layout  
    $updatedFields = foreach ($f in $layout.fields | where-object {$_.field_type -ne "DropDown"}) { New-LayoutFieldPayload $f }
    # map new listselect fields to new layout
    foreach ($map in $mapsForLayout){
        $lbl = if ([string]::IsNullOrWhiteSpace($map.NewLabel)) { $map.From.label } else { $map.NewLabel }
        $lid = [int]$map.List.id
        $updatedFields += [ordered]@{
        label        = "$lbl".Trim()
        field_type   = 'ListSelect'
        list_id      = $lid
        required     = $($from.required ?? $false)
        show_in_list = $($from.show_in_list ?? $true)
        position     = $($from.position ?? $(get-random -Minimum 444 -Maximum 999))
      }
    }
    $newlayoutRequest["Name"]="$($layout.name)-WithListSelect"
    $newlayoutRequest["Fields"]=$updatedFields

    try { 
      $NewLayout =New-HuduASsetLayout @newlayoutRequest
      $NewLayout = $NewLayout.asset_layout ?? $NewLayout
    }
    catch {
      write-host "issue during layout create for $($layout.name)- $_"
      $Errored.Layouts += @{Issue="create layout failed"; Layout=$layout; Exception=$_; Request=$newlayoutRequest}
      return [PSCustomObject]@{Errored = $Errored; Processed = $Processed; Reason = "create layout failed for '$($layout.name)-WithListSelect'"}
    }
    $Processed.Layouts += @{Action="Created replacement layout '$($layout.name)-WithListSelect' for $($layout.name)"}


  ###### 3 - Append previous values to new fields in layout
  $allRelations = Get-HuduRelations
  $allPasswords = Get-HuduPasswords

  Write-Host "Migrating asset to new temp-layout: $($layout.name)"

    $LayoutAssets = Get-huduAssets -AssetLayoutId $layout.id
    if (-not $LayoutAssets -or $LayoutAssets.count -lt 1){Write-Host "Skipping Value Reassignment, layout $($layout.name) has no assets."}

    foreach ($asset in $layoutAssets) {
      Write-Host "moving asset $($asset.name) for layout $($layout.name)"
      $FieldValues = $asset.fields
      $NewAssetRequest = @{
        Name=$asset.name
        CompanyID=$asset.company_id
      }    
      foreach ($prop in @("primary_serial","primary_mail","primary_model","primary_manufacturer")){
        if ([string]::IsNullOrEmpty($asset.$prop)){continue}
        $NewAssetRequest[$prop]=$asset.prop
      }

      $updatedFields = @()
      foreach ($potentialValue in $($FieldValues | where-object {-not $([string]::IsNullOrWhiteSpace($_.value))})) {
        $updatedFields+=@{$potentialValue.label = $potentialValue.Value}
      }
      try {
        $NewAssetRequest["AssetLayoutId"]=$newlayout.id
        $NewAssetRequest["Fields"]=$updatedFields
        $NewAssetRequest["CompanyID"]=$asset.company_id
        $NewAsset = New-HuduAsset @NewAssetRequest
        $NewAsset = $NewAsset.asset ?? $NewAsset
      } catch {
        $Errored.Assets += @{Issue="create replacement asset failed for $($asset.name) on company $($asset.company_id)"; Asset=$Asset; Exception=$_; Request=$NewAssetRequest}
        return [PSCustomObject]@{Errored = $Errored; Processed = $Processed; Reason = "create layout failed for '$($layout.name)-WithListSelect'"}
      }
      $Processed.Assets += @{Action="Created replacement asset $($asset.name) for $($layout.name)"}

      if ($newAsset){
      # turn off debug messages / retry for relations
        $global:SKIP_HAPI_ERROR_RETRY=$true

        $sourceToables  = $($($allrelations | where-object {$_.toable_type -eq 'Asset' -and $asset.id -eq $_.toable_id }) ?? @())
        $sourceFromables  = $($($allrelations | where-object {$_.fromable_type -eq 'Asset' -and $asset.id -eq $_.fromable_id }) ?? @())
        Write-Host "removed source asset, replicating $($sourceFromables.count) fromable relations and $($sourceToables.count) toable relations to new asset"
        
      # re-allocate relations
        foreach ($rel in $sourceToables) {
          $newToable=$null
          try {
                $newToable=New-HuduRelation -FromableType $rel.fromable_type -FromableId $rel.fromable_id `
                                -ToableType "Asset" -ToableId $newAsset.id
                write-host "created toable rel $($newToable.id)"
          } catch {
                $Errored.Relations+=@{Error="Error creating toable relationship for asset $($asset.name)"; asset=$asset; reason=$_; Info="this can be safely ignored if related to inverse relation existing"}
          }
          $processed.Relations+=@{Action="Created toable relation $($newToable.id ?? '') for new asset $($newasset.name)"}
        }
        foreach ($rel in $sourceFromables) {
          $newFromable=$null
          try {
                $newFromable=New-HuduRelation -FromableType "Asset" -FromableId $newAsset.id `
                                -ToableType $rel.toable_type -ToableId $rel.toable_id
                write-host "created fromable rel $($newFromable.id)"
          } catch {
                $Errored.Relations+=@{Error="Error creating fromable relationship for asset $($asset.name)"; asset=$asset; reason=$_; Info="this can be safely ignored if related to inverse relation existing"}
          }
          $processed.Relations+=@{Action="Created fromable relation $($newFromable.id ?? '') for new asset $($newasset.name)"}
        }


      # re-allocate passwords  
        foreach ($relatedPassword in $($allPasswords | where-object {$_.passwordable_type -eq 'Asset' -and $_.passwordable_id -eq $asset.id})) {
          try {
            $relatedPassword = $relatedPassword.asset_password ?? $relatedPassword
            Set-HuduPassword -id $relatedPassword.id -passwordable_type 'Asset' -PasswordableId $newAsset.id

          } catch {
            $Errored.Passwords+=@{Error="Issue during re-allocation of password to new asset";Asset=$NewAsset; Exception=$_}
          }
          $Processed.Passwords+=@{Action="re-allocated password $($relatedPassword.id) / $($relatedPassword.name) to new asset";Asset=$NewAsset; Exception=$_}
        }
      # Remove source asset
        try {
          $null = Remove-HuduAsset -id $asset.id -CompanyId $asset.company_id -Confirm:$false
          Write-Host "removed source asset... "
          $processed.Assets+=@{Action="Removed original / source asset with ID: $($asset.id)"}
        } catch {
          $errored.Assets+=@{Error="couldn't remove source asset $($asset.name)"; Exception=$_}
          return [PSCustomObject]@{Errored = $Errored; Processed = $Processed; Reason = "Issue removing source asset. Do you have delete permissions in Hudu API?"}
        }
      } else {
          $errored.Assets+=@{Error="Couldnt create replacement / destination asset for $($asset.name)"; Exception=$_}
      }
      $global:SKIP_HAPI_ERROR_RETRY=$false
    }
    # End of per-asset loop


    try {
      $null = Set-HuduAssetLayout -id $layout.id -name "$($layout.name)-OLD" -active $false
      $Processed.Layouts+=@{Action = "Set source asset layout $($layout.name) as inactive, appended OLD to name."}
    } catch {
        $errored.Layouts+=@{Error="couldn't deactivate source layout $($layout.name)"; Exception=$_}
    }
    try {
      $null = Set-HuduAssetLayout -id $newlayout.id -name "$($newlayout.name -replace "-WithListSelect",'')".Trim() -active $true
      $Processed.Layouts+=@{Action = "Set completed layout $($layout.name) as final name (removed -WithListSelect suffix, set active)"}
    } catch {
        $errored.Layouts+=@{Error="couldn't activate destination layout $($layout.name)-WithListSelect or remove temporary suffix"; Exception=$_}
    }

    return [PSCustomObject]@{Errored = $Errored; Processed = $Processed; Success = $true }
}


# begin
Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible;


$layoutsToProcess = @()
$DropdownLayouts=$($(Get-HuduAssetLayouts) | where-object {$_.fields.field_type -contains "DropDown" -and $($_.active ?? $false)})

if (-not $DropdownLayouts -or $DropdownLayouts.count -lt 1){
  Write-host "No more layotus with dropdowns to process!"; exit 0;
}

if ("Process a single Layout" -eq $(Select-ObjectFromList -message "Which layouts to replace with ListSelect for?" -allowNull $false -objects @("Process a single Layout","Process All Eligible $($DropdownLayouts.count) layouts"))){
  $layoutsToProcess+=$(Select-ObjectFromList -message "Which layout to process individually?" -objects $DropdownLayouts -allowNull $false)
} else {$layoutsToProcess = $DropdownLayouts}

if ("No" -eq $(Select-ObjectFromList -objects @("Yes","No") -message "Have you performed a backup first?")){
  Write-Host "Oof, you might consider making a backup first, it's reccomended to do so."
  exit 0
} else {
  if ("Yes" -eq $(Select-ObjectFromList -message "Are you Self-Hosted?" -objects @("Yes","No"))){
    Write-Host "You might consider running a (rails console) conversion command for self-hosters, as it is more strightforward"
    Write-Host "Please see the community post HERE: https://community.hudu.com/script-library-awpwerdu/post/self-hosted-convert-legacy-dropdown-to-list-HXoZuMgFcoTmO8C"
  }


  Read-Host "Press any key to start"
}

foreach ($l in $layoutsToProcess){
  Write-Host "Starting $($l.name)"
  $result = Set-DropDownsToListSelect -layout $l -ReuseListsWherePossible $false -PrefixLayoutNameInList $true
  if ($result -and $result.success){
    "Success processing $($l.name)"
  }
  $outFile = "$PSScriptRoot\$(Get-SafeFilename -Name "$($l.name)-LSremoval.json")"
  $result | convertto-json -depth 99 | out-file $outFile
  Write-Host "Result for $($l.name) written to $outFile"

}
