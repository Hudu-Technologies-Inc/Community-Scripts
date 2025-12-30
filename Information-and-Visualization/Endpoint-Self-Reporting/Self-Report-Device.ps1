# Based on the original script by Kelvin Tegelaar https://github.com/KelvinTegelaar/AutomaticDocumentation
#####################################################################
# -------------------------------------------------------------------------
# User Environment
# -------------------------------------------------------------------------
$AzVault_HuduSecretName = "masontesting"                         # Name of your secret in AZure Keystore for your Hudu API key
$AzVault_Name           = "hudu-pshell-learning"                 # Name of your Azure Keyvault
$HuduBaseURL            = "https://YourHuduUrl.huducloud.com"    # URL of your Hudu Instance
$CompanyName            = "Company to Record Into"               # Company Name (exact) which this device should be attributed to
$HowOftenDays           = 2                                      # how often or how far back to record data for (in days)
$HuduAssetLayoutName    = "Monitored Workstation"                # name of asset layout to create/use
$TableTheme = @{
    Font      = '13px/1.35 system-ui, Segoe UI, Arial'
    Border    = '#191d67ac'
    HeaderBg  = '#cdd9e681'
    HeaderFg  = '#04153bd3'
    RowAltBg  = '#8ebae587'
    CellPad   = '6px'
    CellAlign = 'center'
}
$TableAttributes = @{
  'th' = @{ align='center' }
  'tr' = @{ style='transition: background .2s ease' }
}
# optional table styling information
    
# -------------------------------------------------------------------------
# Init Modules and Sign-In
# -------------------------------------------------------------------------

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
Get-PSVersionCompatible
foreach ($module in @('Az.KeyVault', 'HuduAPI')) {if (Get-Module -ListAvailable -Name $module) 
    { Write-Host "Importing module, $module..."; Import-Module $module } else {Write-Host "Installing and importing module $module..."; Install-Module $module -Force -AllowClobber; Import-Module $module }
}
if (-not (Get-AzContext)) { Connect-AzAccount };
function Set-HtmlTagAttributes {
    param(
        [Parameter(Mandatory)][string]$Html,
        [hashtable]$TagAttributes  # e.g. @{ 'th'=@{align='center'; style='background:#6136ff'}; 'tr'=@{style='...'} }
    )
    if (-not $TagAttributes) { return $Html }
    foreach ($tag in $TagAttributes.Keys) {
        $attrStr = ($TagAttributes[$tag].GetEnumerator() | ForEach-Object {
            '{0}="{1}"' -f $_.Key, ($_.Value -replace '"','&quot;')
        }) -join ' '
        # Add attributes to each opening tag; preserves existing attrs
        $pattern = "<$tag\b(?![^>]*\s$($TagAttributes[$tag].Keys -join '|')=)([^>]*)>"
        $Html = [regex]::Replace($Html, $pattern, "<$tag`$1 $attrStr>", 'IgnoreCase')
    }
    return $Html
}
function Add-HtmlTableTheme {
    param(
        [Parameter(Mandatory)][string]$Html,
        [string]$TableClass = 'kv',
        [hashtable]$Theme
    )
    # Defaults (user can override any of these via -Theme)
    $defaults = @{
        Font      = '13px/1.35 system-ui, Segoe UI, Arial'
        Border    = '#e5e7eb'
        HeaderBg  = '#f9fafb'
        HeaderFg  = '#111827'
        RowAltBg  = '#f8fafc'
        CellPad   = '6px'
        CellAlign = 'left'
    }
    if (-not $Theme) { $Theme = @{} }
    $t = $defaults.Clone(); $Theme.GetEnumerator() | ForEach-Object { $t[$_.Key] = $_.Value }

    $css = @"
<style>
.$TableClass { border-collapse: collapse; width: 100%; font: $($t.Font); }
.$TableClass th { text-align: $($t.CellAlign); background: $($t.HeaderBg); color: $($t.HeaderFg); padding: $($t.CellPad); border: 1px solid $($t.Border); }
.$TableClass td { padding: $($t.CellPad); border: 1px solid $($t.Border); }
.$TableClass tr:nth-child(even) td { background: $($t.RowAltBg); }
</style>
"@

    # Ensure the first <table> gets the class
    $styled = [regex]::Replace($Html, '<table\b', "<table class=""$TableClass""", 1)
    return $css + $styled
}

New-HuduAPIKey "$(Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AzVault_HuduSecretName" -AsPlainText)"
New-HuduBaseUrl $HuduBaseURL

$Company = Get-HuduCompanies -name $CompanyName


$Company = Get-HuduCompanies -name $CompanyName
$cutoff = $(get-date).AddDays(-[math]::Abs([double]$HowOftenDays))
if ($null -eq $company) {
    Write-Error "No company found with name: $CompanyName in $(Get-HuduBaseURL)"; exit
}
$ComputerName = $($Env:COMPUTERNAME)

$PrimarySerial = $(get-ciminstance win32_bios).serialnumber
$PrimaryManufacturer = $(Get-CimInstance Win32_BIOS).Manufacturer
$ExistingRecord = Get-HuduAssets -primary_serial $PrimarySerial\

$Layout = Get-HuduAssetLayouts -name $HuduAssetLayoutName
if ($Layout -is [array]) {Write-Warning "Multiple Possible Layouts for $HuduAssetLayoutName"; $Layout = $Layout[0]}
if (!$Layout) {
    $AssetLayoutFields = @(
        @{label        = 'Device Name'       ; field_type   = 'Text'},
        @{label        = 'QuickFacts'        ; field_type   = 'RichText'},
        @{label        = 'Events'            ; field_type   = 'RichText'},
        @{label        = 'User Profiles'     ; field_type   = 'RichText'},
        @{label        = 'Installed Updates' ; field_type   = 'RichText'},
        @{label        = 'Installed Software'; field_type   = 'RichText'})
    $idx = 0
    $AssetLayoutFields | ForEach-Object {
        $idx++
        $_.position     = $idx
        $_.show_in_list = ($_.field_type -eq 'Text') ? 'true' : 'false'
    } | Out-Null

    Write-Host "Creating New Asset Layout $HuduAssetLayoutName"
    $NewLayout = New-HuduAssetLayout -name $HuduAssetLayoutName -icon "fas fa-book" -color "#3d19b2ff" -icon_color "#ffffff" -include_passwords $true -include_photos $true -include_comments $true -include_files $true -fields $AssetLayoutFields
    $Layout = Get-HuduAssetLayouts -name $HuduAssetLayoutName
}
$null = Set-HuduAssetLayout -id $Layout.id -Active $true

write-host "Starting documentation process." -foregroundColor green
write-host "Getting update history." -foregroundColor green
$date = Get-Date
$hotfixesInstalled = get-hotfix

write-host "Getting User Profiles." -foregroundColor green
$UsersProfiles = foreach ($Profile in $(Get-CimInstance win32_userprofile | Where-Object { $_.special -eq $false } | select-object localpath, LastUseTime, Username)) {
    $profile.username = ($profile.localpath -split '\', -1, 'simplematch') | Select-Object -Last 1
    $Profile
}

write-host "Getting Installed applications." -foregroundColor green
$installedSoftware = foreach ($Application in $((Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\" | Get-ItemProperty) + ($software += Get-ChildItem "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\" | Get-ItemProperty) | Select-Object Displayname, Publisher, Displayversion, InstallLocation, InstallDate)) {
    if ($null -eq $application.InstallLocation) { continue }
    if ($null -eq $Application.InstallDate) { $application.installdate = $((get-item $application.InstallLocation -ErrorAction SilentlyContinue).CreationTime).ToString('yyyyMMdd') }
    $Application.InstallDate = [datetime]::parseexact($Application.InstallDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd HH:mm')
    if ($null -eq $application.InstallDate) { continue }
    $application
}

write-host "Checking WAN IP" -foregroundColor green
$events = @()
$previousIP = get-content "$($env:ProgramData)/LastIP.txt" -ErrorAction SilentlyContinue | Select-Object -first 1
if (!$previousIP) { Write-Host "No previous IP found. Compare will fail." }
$Currentip = (Invoke-RestMethod -Uri "https://ipinfo.io/ip") -replace "`n", ""
$Currentip | out-file "$($env:ProgramData)/LastIP.txt" -Force

if ($Currentip -ne $previousIP) {
    $Events += [pscustomobject]@{
        date  = $date.ToString('yyyy-MM-dd HH:mm')
        Event = "WAN IP has changed from $PreviousIP to $CurrentIP"
        type  = "WAN Event"
    }
}

write-host "Getting Installed applications in last $(24 * [int]$HowOftenDays) hours for events list" -foregroundColor green
foreach ($installation in $($installedsoftware | where-object { $_.installDate -ge $cutoff.tostring('yyyy-MM-dd') })) {
    $Events += [pscustomobject]@{
        date  = $installation.InstallDate
        Event = "New Software: $($Installation.displayname) has been installed or updated."
        type  = "Software Event"
    }
}

write-host "Getting KBs in last $(24 * [int]$HowOftenDays) hours for events list" -foregroundColor green
foreach ($InstalledHotfix in $(get-hotfix | where-object { $_.InstalledOn -ge $cutoff })) {
    $Events += [pscustomobject]@{
        date  = $InstalledHotfix.installedOn.tostring('yyyy-MM-dd HH:mm')
        Event = "Update $($InstalledHotfix.Hotfixid) has been installed."
        type  = "Update Event"
    }
}

write-host "Getting user logon/logoff events of last $(24 * [int]$HowOftenDays) hours." -foregroundColor green
foreach ($Users in $(get-childitem "C:\Users")) {
    if ($users.CreationTime -gt $cutoff) {
        $Events += [pscustomobject]@{
            date  = $users.CreationTime.tostring('yyyy-MM-dd HH:mm')
            Event = "First time logon: $($Users.name) has logged on for the first time."
            type  = "User event"
        }
    }
    $NTUser = get-item "$($users.FullName)\NTUser.dat" -force -ErrorAction SilentlyContinue
    if ($NTUser.LastWriteTime -gt $cutoff) {
        $Events += [pscustomobject]@{
            date  = $NTUser.LastWriteTime.tostring('yyyy-MM-dd HH:mm')
            Event = "Logoff: $($Users.name) has logged off or restarted the computer."
            type  = "User event"
        }
    }
    if ($NTUser.LastAccessTime -gt $cutoff) {
        $Events += [pscustomobject]@{
            date  = $NTUser.LastAccessTime.tostring('yyyy-MM-dd HH:mm')
            Event = "Logon: $($Users.name) has logged on."
            type  = "User event"

            }
        }
    }

    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $proc = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS
    $enclosure = Get-CimInstance Win32_SystemEnclosure
    $chassis = ($enclosure.ChassisTypes | ForEach-Object {
        switch ($_){
            3 {'Desktop'} 4 {'LowProfileDesktop'} 6 {'MiniTower'} 8 {'Portable'}
            9 {'Laptop'} 10 {'Notebook'} 11 {'Handheld'} 14 {'SubNotebook'}
            30 {'Tablet'} 31 {'Convertible'} 32 {'Detachable'} 1 {'Other'}
            Default {'Unknown'}
        }
    }) -join '/'

    $uptime = (Get-Date) - $os.LastBootUpTime
    $sysDrive = Get-Volume -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction SilentlyContinue
    $sysFreePct = if ($sysDrive) { [math]::Round(($sysDrive.SizeRemaining/$sysDrive.Size)*100,1) } else { $null }

    # Defender
    $mp = $null; try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch {}

    # BitLocker / Secure Boot / TPM
    $bit = $null; try { $bit = Get-BitLockerVolume -MountPoint $env:SystemDrive } catch {}
    $sb = $null;  try { $sb = Confirm-SecureBootUEFI } catch {}
    $tpm = $null; try { $tpm = Get-Tpm } catch {}

    $QuickFacts = [pscustomobject]@{
        Model          = $cs.Model
        Chassis        = $chassis
        CPU            = "$($proc.Name) ($($proc.NumberOfCores)x$($proc.NumberOfLogicalProcessors))"
        RAM_GB         = [math]::Round($cs.TotalPhysicalMemory/1GB,1)
        OS_Version     = "$($os.Caption) $($os.Version) (Build $($os.BuildNumber))"
        BIOS           = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) $($([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd'))"
        Uptime         = "{0}d {1}h" -f [int]$uptime.TotalDays, $uptime.Hours
        System_Drive_Free = $sysFreePct
        Defender_RTP    = $mp.RealTimeProtectionEnabled
        Defender_Signatures = if ($mp) { [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays }
        BitLocker        = if ($bit) { $bit.ProtectionStatus } else { $null }
        SecureBoot      = $sb
        TPM_Present        = if ($tpm) { $tpm.TpmPresent } else { $false }
    }
    # Populate Asset Fields
    $AssetFields = @{
        'device_name'        = $ComputerName
        'QuickFacts'         = $QuickFacts
        'user_profiles'      = $UsersProfiles
        'events'             = $($events | Sort-Object -Property date -Descending)
        'installed_updates'  = $($hotfixesInstalled | select-object InstalledOn, Hotfixid, caption, InstalledBy)
        'installed_software' = $installedSoftware
    }
    foreach ($key in @($AssetFields.Keys)) {
        if ($key -eq 'device_name') { continue }

        $val  = $AssetFields[$key]
        $html = $val | ConvertTo-Html -Fragment | Out-String
        $html = Set-HtmlTagAttributes -Html $html -TagAttributes $TableAttributes
        $html = Add-HtmlTableTheme   -Html $html -Theme $TableTheme

        $AssetFields[$key] = $html
    }
    $AssetName = "$ComputerName - Logbook"

    write-host "Documenting to Hudu"  -ForegroundColor Green
    if ($null -eq $Layout.id) {
        Write-Host "Error: Invalid layout ID" -ForegroundColor Red; exit 1
    }
    $AssetRequest = @{
        Name                = $AssetName
        CompanyId           = $Company.id
        Assetlayoutid       = $Layout.id
    }
    $Asset = $(Get-HuduAssets -name $AssetName -CompanyId $company.id -assetlayoutid $Layout.id) ?? $(Get-HuduAssets -primary_serial $PrimarySerial -assetlayoutid $Layout.id -name $AssetName)
    if ($Asset -and $Asset.id){
        $AssetRequest["Id"]=$Asset.id
    }
    if (-not [string]::IsNullOrWhiteSpace($PrimaryManufacturer)){
        $AssetRequest["PrimaryManufacturer"]=$PrimaryManufacturer
    }
    if (-not [string]::IsNullOrWhiteSpace($PrimarySerial)){
        $AssetRequest["PrimarySerial"]=$PrimarySerial
    }
    $AssetRequest["Fields"]=$AssetFields
    if (!$Asset) {
        Write-Host "Creating new Asset for $ComputerName"; $Asset = New-HuduAsset @AssetRequest
    } else {
        Write-Host "Updating $ComputerName"; $Asset = Set-HuduAsset @AssetRequest
    }

Remove-HuduAPIKey; $HuduApikey = $null; $HuduBaseURL = $null;
