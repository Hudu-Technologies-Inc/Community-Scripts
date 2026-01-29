$HuduAPIKey = $HuduAPIKey ?? $(read-host "Please Enter Hudu API Key")
$HuduBaseURL = $HuduBaseURL ?? $(read-host "Please Enter Hudu Base URL (e.g. https://myinstance.huducloud.com)")

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

function Get-HuduModule {
    param ([string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",[bool]$use_hudu_fork = $true)
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
function Convert-DetailsToObject {
    param([Parameter(Mandatory)]$Details)
    if ($null -eq $Details) { return $null }
    if ($Details -is [System.Collections.IDictionary] -or $Details -is [pscustomobject]) {
        return $Details
    }
    if ($Details -is [string]) {
        $s = $Details.Trim()
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        try {
            return $s | ConvertFrom-Json -ErrorAction Stop
        } catch {
            return $s
        }
    }
    return $Details
}
function Format-DetailsHuman {
    param([Parameter(Mandatory)]$DetailsObject)
    if ($null -eq $DetailsObject) { return $null }
    if ($DetailsObject -is [string]) {
    return "Details: $DetailsObject"
    }
    $lines = foreach ($p in $DetailsObject.PSObject.Properties) {
    $v = $p.Value
    if ($null -eq $v) { continue }
    if ($v -is [pscustomobject] -or $v -is [System.Collections.IDictionary] -or ($v -is [System.Collections.IEnumerable] -and $v -isnot [string])) {
        $v = ($v | ConvertTo-Json -Depth 25 -Compress)
    }
    " $($p.Name): $v"
    }
    if (-not $lines) { return $null }
    return "Details:`n$($lines -join "`n")"
}
Get-HuduModule; Set-HuduInstance -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey;

$activitylogsSample = get-huduactivitylogs


$activityAttributes = @{}
$activityLogsProperties = $($activitylogsSample | ForEach-Object { $_.PSObject.Properties.Name } | Sort-Object -Unique)
foreach ($prop in $activityLogsProperties){$activityAttributes[$prop] = $activitylogsSample.$prop | Sort-Object -Unique}

$selectedattribute = Select-ObjectFromList -objects $activityLogsProperties -message "Select an attribute to drill into"
$whenValue = select-ObjectFromList -objects $activityAttributes[$selectedattribute] -message "Select a value for attribute '$selectedattribute' to filter on"
$filteredActivityLogs = $activitylogsSample | Where-Object { $_.$selectedattribute -ieq $whenValue } 
write-host "$($($filteredActivityLogs | ForEach-Object {
        $user = $_.user_name ?? (($_.user_email ?? $_.user_short_name ?? $_.user_initialis) ?? $(if ($_.record_user_url) {"User at $($_.record_user_url)"}) ?? 'someone')
        $action = $_.action ?? 'did something'
        $recordType = $_.record_type ?? 'an object'
        $recordName = $_.record_name ?? $_.original_record_name ?? "Record At $($_.record_url)"
        $company = if ($_.company_name) { "from company: $($_.company_name)" } else { $null }
        $ipPart = if ($_.ip_address) { "with source IP $($_.ip_address)" } else { $null }
        $detailsObj = Convert-DetailsToObject $_.details
        $details = if ($detailsObj) { Format-DetailsHuman $detailsObj } else { $null }
        $browser = if ($_.agent_string -match "Chrome/([\d\.]+)") {
            "Chrome $($Matches[1])"
        } elseif ($_.agent_string -match "Firefox/([\d\.]+)") {
            "Firefox $($Matches[1])"
        } elseif ($_.agent_string -match "Safari/([\d\.]+)") {
            "Safari $($Matches[1])"
        } else { $null }
        $appPart = "$(if ($_.app_type) { "via $($_.app_type)" } elseif ($browser) { "via $browser" } else { $null })$(if ($_.os ?? $_.device) { " on $($_.os)" } else { '' })"
        $namePart = if ($recordName) { "$recordType $recordName" } else { $recordType }
( @(
"$user $action $namePart"
$company
$appPart
$ipPart
$details
$_.formatted_datetime
) | Where-Object { $_ } ) -join ' '
}) -join "`n")" -ForegroundColor Green
