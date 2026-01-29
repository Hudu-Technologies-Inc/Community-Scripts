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
