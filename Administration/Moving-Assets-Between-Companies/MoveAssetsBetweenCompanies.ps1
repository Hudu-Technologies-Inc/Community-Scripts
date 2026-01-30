<#
Move Hudu Assets between Companies (interactive)

Prompts:
- Source company (pick from list)
- Destination company (pick from list)
- Criteria:
  1) Asset Name contains <text>
  2) Asset Layout Field contains <text>
  3) Name contains <text> AND Field contains <text>
  - If criteria 2 or 3 selected, prompts for Asset Layout and Field to evaluate
#>
function Move-HuduAssetCompany {
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Id,
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SourceCompanyId,
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$DestCompanyId
    )
    $src = Get-HuduAssets -id $Id
    if (-not $src) { throw "Asset $Id not found under company $SourceCompanyId." }
    $payload = [ordered]@{
        asset = [ordered]@{
            name           = $src.name
            asset_layout_id = $src.asset_layout_id
            custom_fields  = $src.custom_fields
            company_id = $DestCompanyId
        }
    }
    $json = $payload | ConvertTo-Json -Depth 50
    $resource = "/api/v1/companies/$sourcecompanyId/assets/$Id"
    try {
    $r = Invoke-HuduRequest -Method put -Resource $resource -Body $json
    } catch {
      return $_
    }
    return $r
}
function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSversion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Versionx
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
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}
function Set-HuduInstance {
    param ([string]$HuduBaseURL,[string]$HuduAPIKey)
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

function Select-ObjectFromList($objects, $message, $allowNull = $false) {
    $validated = $false
    while (-not $validated) {
        if ($allowNull) {Write-Host "0: None/Custom"}

        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]
            $displayLine = if ($null -ne $object.OptionMessage) {
                "$($i+1): $($object.OptionMessage)"
            } elseif ($null -ne $object.name) {
                "$($i+1): $($object.name)"
            } else {
                "$($i+1): $($object)"
            }
            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }

        $choice = Read-Host $message
        if (-not ($choice -as [int])) {Write-Host "Invalid input. Please enter a number." -ForegroundColor Red; continue;}
        $choice = [int]$choice
        if ($choice -eq 0 -and $allowNull) {return $null}

        if ($choice -ge 1 -and $choice -le $objects.Count) {return $objects[$choice - 1]} else {Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red}
    }
}
function Get-EnsureModule {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber `
            -ErrorAction SilentlyContinue *> $null
    }
    try {
        Import-Module -Name $Name -Force -ErrorAction Stop *> $null
    } catch {
        Write-Warning "Failed to import module '$Name': $($_.Exception.Message)"
    }
}

# -----------------------------
# Start
# -----------------------------

$HuduAPIKey = $HuduAPIKey ?? $(read-host "Please Enter Hudu API Key")
$HuduBaseURL = $HuduBaseURL ?? $(read-host "Please Enter Hudu Base URL (e.g. https://myinstance.huducloud.com)")
Get-HuduModule; Set-HuduInstance -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey;
write-host "getting companies..."; $huducompanies = get-huducompanies;
$sourceCompany = Select-ObjectFromList -objects $huducompanies -message "Select company to MOVE FROM"
$destCompany   = Select-ObjectFromList -objects $($huducompanies | Where-Object { $_.id -ne $sourceCompany.id }) -message "Select company to MOVE TO"
$mode = select-ObjectFromList -objects @("1","2","3") -message "Select criteria mode:`n[1] Asset Name contains text`n[2] Specific Asset Layout Field contains text`n[3] Name contains AND Field contains"
write-host "getting layouts..."; $layouts = Get-HuduAssetLayouts;
$selectedLayout = Select-ObjectFromList -objects $layouts -message "Select Asset Layout to evaluate field on"; $selectedLayout = $selectedLayout.asset_layout ?? $selectedLayout; 

if ($mode -in @(1,3)) {
  $nameContains = ""
  while ([string]::IsNullOrWhiteSpace($nameContains)) {
  $nameContains = read-host "Enter text that the Asset Name must contain"
}}

if ($mode -in @(2,3)) {
  $selectedField = Select-ObjectFromList -message "Select field to evaluate" -objects $selectedLayout.fields
  $fieldContains = ""
  while ([string]::IsNullOrWhiteSpace($fieldContains)) {
    $fieldContains = read-host "Enter text that the selected field must contain"
  }
}

Write-Host "`nLoading assets from '$($sourceCompany.name)'..." -ForegroundColor Gray
$assets = get-huduassets -AssetLayoutId $selectedLayout.id -CompanyId $sourceCompany.id; Write-Host ("Total assets loaded: {0}" -f $assets.Count) -ForegroundColor Gray;

$matches =@()
foreach ($a in $assets) {
  if ($mode -in @(1,3)) {
    if (-not ("$($a.name)" -ilike "*$nameContains*")) { continue }
  }
  if ($mode -in @(2,3)) {
    $valString = $($a.fields | where-object {$_.label -ieq $($selectedField.label)}).Value
    if (([string]::IsNullOrWhiteSpace($valString)) -or -not ($valString -ilike "*$fieldContains*")) { continue }
  }
  $Matches += $a
}
Write-Host ("`nMatched assets to move: {0}" -f ($matches.Count)) -ForegroundColor Green

if ($matches.Count -gt 0) {
  Write-Host "`nPreview (up to 20):" -ForegroundColor Cyan
  $matches | Select-Object -First 20 | ForEach-Object {
    write-host "$($($_ | ConvertTo-Json -Depth 5 | Out-String))`n" -ForegroundColor Yellow
  }
}

$confirm = Select-ObjectFromList "`Select 'MOVE' to confirm moving $($matches.Count) assets from '$($sourceCompany.name)' to '$($destCompany.name)', or anything else to cancel." -objects @("MOVE","CANCEL")
if ($confirm -ne "MOVE") {Write-Host "Cancelled." -ForegroundColor Yellow; return;}

$log = $(foreach ($a in $matches) {
  Move-HuduAssetCompany -id $a.id -DestCompanyId $destCompany.id -SourceCompanyId $sourceCompany.id
})
write-host "$($log | Out-String)" -ForegroundColor Green
$($log | ConvertTo-Json -depth 99) | out-file -FilePath "$(Join-Path -Path (Get-Location) -ChildPath ("hudu-asset-move-log-{0}.json" -f $(Get-Date -Format "yyyyMMdd-HHmmss")))"