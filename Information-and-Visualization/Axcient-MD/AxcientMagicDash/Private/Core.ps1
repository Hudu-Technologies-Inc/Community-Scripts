# Hudu and Axcient both issue keys far longer than this. The floor exists only to
# keep an operator's typo out of the redaction list, so it is deliberately well
# below any real key rather than tuned to one vendor's current format.
$script:AmdMinimumSecretLength = 12

function Set-AmdSensitiveValues {
    [CmdletBinding()]
    param(
        [AllowNull()][string[]]$Values = @(),
        # Callers that only know one key must extend the redaction list. Replacing
        # it would unregister the other key and leave it readable in transcripts.
        [switch]$Add
    )

    $newCandidates = @(
        foreach ($value in @($Values)) {
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $text = [string]$value
            # A value too short to be a credential protects nothing when redacted,
            # while a mistyped word like 'test' would blank that word out of every
            # later message for the rest of the session.
            if ($text.Length -lt $script:AmdMinimumSecretLength) { continue }
            $text
            $encoded = [Uri]::EscapeDataString($text)
            if (-not [string]::Equals($encoded, $text, [StringComparison]::Ordinal)) {
                $encoded
            }
        }
    )
    $candidates = if ($Add) {
        @($script:AmdSensitiveValues) + $newCandidates
    }
    else {
        $newCandidates
    }
    $script:AmdSensitiveValues = @(
        $candidates |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            # Redaction below is ordinal, so de-duplication has to be too. A
            # case-insensitive unique drops one of two values differing only by case
            # and leaves it printable.
            Sort-Object -Unique -CaseSensitive
    )
}

function ConvertTo-AmdRedactedText {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ($null -eq $Text) { return '' }
    $safe = $Text
    # Replace the longest values first. If one registered key is a prefix of
    # another, replacing the shorter key first would leave the longer key's
    # suffix readable.
    foreach ($secret in @($script:AmdSensitiveValues | Sort-Object Length -Descending)) {
        if (-not [string]::IsNullOrWhiteSpace($secret)) {
            $safe = $safe.Replace($secret, '[REDACTED]', [StringComparison]::Ordinal)
            # Percent-escape hex digits are case-insensitive. EscapeDataString emits
            # uppercase hex, but a URL or vendor can legally report the lowercase
            # form; match encoded candidates case-insensitively so both are removed.
            if ($secret -match '%[0-9A-Fa-f]{2}') {
                $safe = [regex]::Replace(
                    $safe,
                    [regex]::Escape($secret),
                    '[REDACTED]',
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )
            }
            # AxcientAPI 0.4.0 includes the first five key characters inside a
            # bracketed "[abcde...]" sample on one 401 path. Match only that exact
            # vendor shape so ordinary five-character text remains readable.
            if ($secret.Length -ge 5) {
                $safe = $safe.Replace(
                    "[$($secret.Substring(0, 5))...]",
                    '[REDACTED]',
                    [StringComparison]::Ordinal
                )
            }
        }
    }
    # The value has to look like a credential, not just be the next word: an
    # ordinary sentence such as 'Authorization: denied by company policy' otherwise
    # lost its first diagnostic word to the redaction.
    return $safe -replace "(?i)\b(authorization|x-api-key|api[-_ ]?key)\s*[:=]\s*(?:bearer\s+)?[^\s,;]{$script:AmdMinimumSecretLength,}", '$1: [REDACTED]'
}

function ConvertTo-AmdNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [switch]$AsInt64
    )

    # API numbers are always invariant, but the single-argument TryParse overloads
    # use the current culture, where '1.5' parses as 15 under a comma decimal
    # separator. A cast would be invariant but throws on unusable input, so parse
    # explicitly against the invariant culture and report failure to the caller.
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ($AsInt64) {
        $parsedInt = [int64]0
        if ([int64]::TryParse($text, [Globalization.NumberStyles]::Integer, $culture, [ref]$parsedInt)) {
            return $parsedInt
        }
        return $null
    }
    $parsed = [double]0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, $culture, [ref]$parsed)) {
        if ([double]::IsNaN($parsed) -or [double]::IsInfinity($parsed)) { return $null }
        return $parsed
    }
    return $null
}

function ConvertTo-AmdHtml {
    [CmdletBinding()]
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-AmdSafeHref {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $uri = $null
    if ($null -eq $Value -or
        -not [Uri]::TryCreate([string]$Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin 'http', 'https') {
        return '#'
    }
    return ConvertTo-AmdHtml $uri.AbsoluteUri
}

function Merge-AmdTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Values
    )

    # One pass, so each placeholder is resolved exactly once. Replacing key by key
    # depends on hashtable order and lets a substituted value that happens to
    # contain '{{other_key}}' - an Axcient client or device name, for example -
    # be expanded again by a later key.
    $lookup = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Values.GetEnumerator()) {
        $lookup[[string]$entry.Key] = if ($null -eq $entry.Value) { '' } else { [string]$entry.Value }
    }
    return [regex]::Replace($Template, '\{\{(\w+)\}\}', {
        param($placeholder)
        $key = $placeholder.Groups[1].Value
        # Unknown placeholders are left intact so they surface as a visible bug
        # rather than silently disappearing.
        if ($lookup.ContainsKey($key)) { return $lookup[$key] }
        return $placeholder.Value
    })
}

function Test-AmdTransientFailure {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ErrorRecord)

    $statusCode = if (Get-Command Get-AmdHttpStatusCode -ErrorAction SilentlyContinue) {
        Get-AmdHttpStatusCode -ErrorRecord $ErrorRecord
    }
    else { 0 }
    if ($statusCode -gt 0) { return $statusCode -in 408, 425, 429, 500, 502, 503, 504 }
    $message = [string]$ErrorRecord.Exception.Message
    return $message -match '(?i)\b429\b|too many requests|rate.?limit|timed? ?out|timeout|temporar|connection.*(reset|refused|closed)|unreachable|name.*could not be resolved|no such host|TLS|secure channel'
}

function Get-AmdRetryDelaySeconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ErrorRecord,
        [Parameter(Mandatory)][int]$Attempt,
        [Parameter(Mandatory)][int]$BaseDelaySeconds,
        # A server can ask for a long wait. Callers that run once per sync can
        # afford it; a call made once per device cannot, so each caller states the
        # longest wait it is willing to take before giving up instead.
        [ValidateRange(1, 300)][int]$MaximumDelaySeconds = 300
    )

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        $retryAfter = $exception.Response.Headers.RetryAfter
        if ($retryAfter) {
            if ($retryAfter.Delta) {
                $seconds = [math]::Ceiling($retryAfter.Delta.TotalSeconds)
                return $(if ($seconds -le $MaximumDelaySeconds) { $seconds } else { -1 })
            }
            if ($retryAfter.Date) {
                $seconds = [math]::Max(0, [math]::Ceiling(($retryAfter.Date.UtcDateTime - [DateTime]::UtcNow).TotalSeconds))
                return $(if ($seconds -le $MaximumDelaySeconds) { $seconds } else { -1 })
            }
        }
        $exception = $exception.InnerException
    }
    return [math]::Min($MaximumDelaySeconds, [math]::Min(30, $BaseDelaySeconds * [math]::Pow(2, $Attempt - 1)))
}

function Invoke-AmdWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [ValidateRange(1, 5)][int]$Attempts = 2,
        [ValidateRange(0, 30)][int]$DelaySeconds = 2,
        [ValidateRange(1, 300)][int]$MaximumDelaySeconds = 300
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $attemptOutput = @(& $Operation)
            return $attemptOutput
        }
        catch {
            if ($attempt -eq $Attempts -or -not (Test-AmdTransientFailure -ErrorRecord $_)) { throw }
            $delay = Get-AmdRetryDelaySeconds `
                -ErrorRecord $_ `
                -Attempt $attempt `
                -BaseDelaySeconds $DelaySeconds `
                -MaximumDelaySeconds $MaximumDelaySeconds
            if ($delay -lt 0) { throw }
            if ($delay -gt 0) { Start-Sleep -Seconds $delay }
        }
    }
}

function New-AmdSyncSummary {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        StartedUtc             = [DateTime]::UtcNow
        CompletedUtc           = $null
        MatchedCompanies       = 0
        MagicDashesUpdated     = 0
        AssetsCreated          = 0
        AssetsUpdated          = 0
        AssetsArchived         = 0
        AssetsSkipped          = 0
        AxcientDevicesRetrieved = 0
        BoundLayoutId          = $null
        BoundLayoutName        = $null
        BoundLayoutActive      = $null
        BoundLayoutUsable      = $false
        AutomaticMatchesAdded  = 0
        UnmatchedClients       = [System.Collections.Generic.List[string]]::new()
        Notes                  = [System.Collections.Generic.List[string]]::new()
        Warnings               = [System.Collections.Generic.List[string]]::new()
        Errors                 = [System.Collections.Generic.List[string]]::new()
        CompanyResults         = [System.Collections.Generic.List[object]]::new()
        OperationResults       = [System.Collections.Generic.List[object]]::new()
        UnmatchedHuduCompanies = [System.Collections.Generic.List[string]]::new()
    }
}

function Get-AmdCounterSum {
    [CmdletBinding()]
    param([AllowNull()]$Collection)

    # A present but non-numeric counter cannot be summed meaningfully. Parse each
    # value explicitly so one odd Axcient response degrades that figure to Unknown
    # instead of depending on Measure-Object's error behavior. An absent count is zero.
    $total = [int64]0
    foreach ($item in @($Collection)) {
        if ($null -eq $item) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$item.count)) { continue }
        $value = ConvertTo-AmdNumber $item.count -AsInt64
        if ($null -eq $value) { return $null }
        $total += $value
    }
    return $total
}

function Get-AmdCounterValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$Collection,
        [Parameter(Mandatory)][string]$Type
    )
    $items = @(
        $Collection | Where-Object {
            [string]::Equals([string]$_.type, $Type, [StringComparison]::OrdinalIgnoreCase)
        }
    )
    if ($items.Count -eq 0) { return 0 }
    $sum = Get-AmdCounterSum -Collection $items
    if ($null -eq $sum) { return 'Unknown' }
    return $sum
}

function New-AmdEmptyState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)

    return "<p class=`"amd-empty`">$(ConvertTo-AmdHtml $Message)</p>"
}

function New-AmdStatusBadge {
    [CmdletBinding()]
    param(
        [AllowNull()]$Status,
        [AllowNull()]$Reason
    )

    $statusText = ([string]$Status).Trim()
    # 'ok' and 'warn' are the only values ever interpolated into the class name.
    $modifier = if ([string]::Equals($statusText, 'NORMAL', [StringComparison]::OrdinalIgnoreCase)) { 'ok' } else { 'warn' }
    $label = if ([string]::IsNullOrWhiteSpace($statusText)) { 'Unknown' } else { $statusText }
    $reasonText = ([string]$Reason).Trim()
    $reasonHtml = if ([string]::IsNullOrWhiteSpace($reasonText)) {
        ''
    }
    else {
        " · <span class=`"amd-reason`">$(ConvertTo-AmdHtml $reasonText)</span>"
    }
    return "<span class=`"amd-badge amd-badge--$modifier`">$(ConvertTo-AmdHtml $label)</span>$reasonHtml"
}

function Format-AmdByteSize {
    [CmdletBinding()]
    param([AllowNull()]$Bytes)

    $value = ConvertTo-AmdNumber $Bytes
    if ($null -eq $value -or $value -lt 0) { return 'Unknown' }
    if ($value -ge 1TB) { return "$([math]::Round($value / 1TB, 2)) TB" }
    if ($value -ge 1GB) { return "$([math]::Round($value / 1GB, 1)) GB" }
    if ($value -ge 1MB) { return "$([math]::Round($value / 1MB, 0)) MB" }
    if ($value -ge 1KB) { return "$([math]::Round($value / 1KB, 0)) KB" }
    if ($value -eq 0) { return '0 MB' }
    return "$([math]::Round($value, 0)) bytes"
}

function ConvertTo-AmdUtcDateTime {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $parsed = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [DateTimeOffset]::TryParse(
        [string]$Value,
        [Globalization.CultureInfo]::InvariantCulture,
        $styles,
        [ref]$parsed
    )) { return $null }
    return $parsed.UtcDateTime
}

function Format-AmdAge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][TimeSpan]$Age)

    if ($Age.TotalMinutes -lt 60) { return "$([math]::Floor([math]::Max(0, $Age.TotalMinutes)))m" }
    if ($Age.TotalHours -lt 48) { return "$([math]::Round($Age.TotalHours, 1))h" }
    return "$([math]::Round($Age.TotalDays, 1))d"
}

function Get-AmdRecoveryPointState {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][bool]$Applicable,
        [bool]$ApplicabilityKnown = $true,
        [Parameter(Mandatory)][ValidateRange(1, 720)][int]$StaleBackupHours,
        [Parameter(Mandatory)][datetime]$NowUtc,
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Local
    )

    if (-not $ApplicabilityKnown) {
        return [pscustomobject]@{ Display = 'Unknown'; IsKnown = $false; IsStale = $false; Applicable = $true }
    }
    if (-not $Applicable) {
        return [pscustomobject]@{ Display = 'N/A'; IsKnown = $true; IsStale = $false; Applicable = $false }
    }
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [pscustomobject]@{ Display = 'No recovery point'; IsKnown = $true; IsStale = $true; Applicable = $true }
    }
    $comparisonUtc = $NowUtc.ToUniversalTime()
    $timestamp = ConvertTo-AmdUtcDateTime $Value
    if ($null -eq $timestamp -or $timestamp -gt $comparisonUtc) {
        return [pscustomobject]@{ Display = 'Unknown'; IsKnown = $false; IsStale = $false; Applicable = $true }
    }
    $age = $comparisonUtc - $timestamp
    if ($age.TotalSeconds -lt 0) { $age = [TimeSpan]::Zero }
    $displayTimestamp = [TimeZoneInfo]::ConvertTimeFromUtc($timestamp, $TimeZone)
    return [pscustomobject]@{
        Display    = "$($displayTimestamp.ToString('g')) ($(Format-AmdAge -Age $age) ago)"
        IsKnown    = $true
        IsStale    = $age.TotalHours -gt $StaleBackupHours
        Applicable = $true
    }
}

function Get-AmdDeviceVaultUsage {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Device)

    $usageProperties = @(
        foreach ($propertyName in 'cloud_usage', 'vault_usage') {
            if ($Device.PSObject.Properties.Name -contains $propertyName) { $propertyName }
        }
    )
    if ($usageProperties.Count -gt 0) {
        $total = [double]0
        foreach ($propertyName in $usageProperties) {
            $value = ConvertTo-AmdNumber $Device.$propertyName
            if ($null -eq $value) { return $null }
            $total += $value
        }
        return $total
    }

    $vaults = @($Device.vaults | Where-Object { $null -ne $_ })
    if ($vaults.Count -eq 0) { return $null }
    $vaultTotal = [double]0
    foreach ($vault in $vaults) {
        $value = ConvertTo-AmdNumber $vault.device_usage
        if ($null -eq $value) { return $null }
        $vaultTotal += $value
    }
    return $vaultTotal
}

function Get-AmdDeviceProtectionMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Device,
        [AllowNull()][System.Collections.Generic.HashSet[string]]$ApplianceDeviceIds,
        [Parameter(Mandatory)][bool]$ApplianceDataAvailable
    )

    $deviceId = ConvertTo-AmdNumber $Device.id -AsInt64
    if ($Device.PSObject.Properties.Name -contains 'd2c' -and $Device.d2c -is [bool] -and $Device.d2c) {
        return 'D2C'
    }
    if ($null -ne $deviceId -and
        $null -ne $ApplianceDeviceIds -and
        $ApplianceDeviceIds.Contains([string]$deviceId)) {
        return 'Appliance'
    }
    if ($ApplianceDataAvailable -and
        $Device.PSObject.Properties.Name -contains 'd2c' -and
        $Device.d2c -is [bool] -and
        -not $Device.d2c -and
        @($Device.vaults).Count -gt 0) {
        # A non-D2C device that is absent from every client appliance is the
        # documented vault-only case represented as Cloud Archive in the portal.
        return 'Cloud Archive'
    }
    return 'Unknown'
}

function Get-AmdDeviceDashboardStates {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Devices = @(),
        [AllowNull()][object[]]$Appliances = @(),
        [Parameter(Mandatory)][bool]$ApplianceDataAvailable,
        [ValidateRange(1, 720)][int]$StaleBackupHours = 24,
        [datetime]$NowUtc = [DateTime]::UtcNow,
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Local
    )

    # A hash set keeps appliance membership O(1) per device. A linear -in search
    # becomes noticeably expensive when a company has thousands of devices.
    $applianceDeviceIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($appliance in @($Appliances)) {
        foreach ($applianceDevice in @($appliance.devices)) {
            $id = ConvertTo-AmdNumber $applianceDevice.id -AsInt64
            if ($null -ne $id) { $null = $applianceDeviceIds.Add([string]$id) }
        }
    }

    foreach ($device in @($Devices)) {
        $method = Get-AmdDeviceProtectionMethod `
            -Device $device `
            -ApplianceDeviceIds $applianceDeviceIds `
            -ApplianceDataAvailable $ApplianceDataAvailable
        $hasLocalPoint = -not [string]::IsNullOrWhiteSpace([string]$device.latest_local_rp)
        $hasCloudPoint = -not [string]::IsNullOrWhiteSpace([string]$device.latest_cloud_rp)
        $localCacheApplicabilityKnown = $device.local_cache_details -and
            $device.local_cache_details.PSObject.Properties.Name -contains 'enabled' -and
            $device.local_cache_details.enabled -is [bool]
        $localCacheEnabled = $localCacheApplicabilityKnown -and $device.local_cache_details.enabled
        $hasCloudVault = @($device.vaults | Where-Object {
            [string]::Equals([string]$_.type, 'Cloud', [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        $localApplicable = switch ($method) {
            'Appliance' { $true }
            'D2C' { $localCacheEnabled }
            'Cloud Archive' { $false }
            default { $hasLocalPoint }
        }
        $cloudApplicable = switch ($method) {
            'Appliance' { $hasCloudVault -or $hasCloudPoint }
            'D2C' { $true }
            'Cloud Archive' { $true }
            default { $hasCloudPoint }
        }
        $localApplicabilityKnown = switch ($method) {
            'D2C' { $localCacheApplicabilityKnown }
            default { $true }
        }
        $localPoint = Get-AmdRecoveryPointState `
            -Value $device.latest_local_rp `
            -Applicable $localApplicable `
            -ApplicabilityKnown $localApplicabilityKnown `
            -StaleBackupHours $StaleBackupHours `
            -NowUtc $NowUtc `
            -TimeZone $TimeZone
        $cloudPoint = Get-AmdRecoveryPointState `
            -Value $device.latest_cloud_rp `
            -Applicable $cloudApplicable `
            -StaleBackupHours $StaleBackupHours `
            -NowUtc $NowUtc `
            -TimeZone $TimeZone
        $healthStatus = ([string]$device.current_health_status.status).Trim()
        $unknownApplicablePoints = @(
            @($localPoint, $cloudPoint) |
                Where-Object Applicable |
                Where-Object { -not $_.IsKnown }
        )
        $recoveryKnown = $unknownApplicablePoints.Count -eq 0
        $classification = if ($localPoint.IsStale -or $cloudPoint.IsStale) {
            'Warning'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($healthStatus) -and
            -not [string]::Equals($healthStatus, 'NORMAL', [StringComparison]::OrdinalIgnoreCase)) {
            'Warning'
        }
        elseif ($method -ne 'Unknown' -and
            [string]::Equals($healthStatus, 'NORMAL', [StringComparison]::OrdinalIgnoreCase) -and
            $recoveryKnown) {
            'Healthy'
        }
        else {
            'Unknown'
        }

        $osParts = [Collections.Generic.List[string]]::new()
        $seenOsParts = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($osPart in @([regex]::Split([string]$device.os.os_name, '\s{2,}|\s*/\s*'))) {
            $trimmedOsPart = ([string]$osPart).Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmedOsPart) -and $seenOsParts.Add($trimmedOsPart)) {
                $osParts.Add($trimmedOsPart)
            }
        }
        $osType = ([string]$device.os.os_type).Trim()
        if (-not [string]::IsNullOrWhiteSpace($osType) -and $seenOsParts.Add($osType)) {
            $osParts.Add($osType)
        }
        $osBits = ConvertTo-AmdNumber $device.os.bits -AsInt64
        if ($null -ne $osBits) {
            $bitsToken = "$osBits-bit"
            $bitsAlreadyPresent = @(
                $osParts | Where-Object {
                    [regex]::IsMatch([string]$_, "(?i)(?:^|\W)$([regex]::Escape($bitsToken))(?:\W|$)")
                }
            ).Count -gt 0
            if (-not $bitsAlreadyPresent -and $seenOsParts.Add($bitsToken)) {
                $osParts.Add($bitsToken)
            }
        }
        $deviceId = ConvertTo-AmdNumber $device.id -AsInt64
        $rawName = if ([string]::IsNullOrWhiteSpace([string]$device.name)) { 'Unknown' } else { [string]$device.name }
        $rawType = ([string]$device.type).Trim()
        $normalizedType = if ([string]::IsNullOrWhiteSpace($rawType)) {
            'Unknown'
        }
        elseif ([string]::Equals($rawType, 'SERVER', [StringComparison]::OrdinalIgnoreCase)) {
            'SERVER'
        }
        elseif ([string]::Equals($rawType, 'WORKSTATION', [StringComparison]::OrdinalIgnoreCase)) {
            'WORKSTATION'
        }
        else {
            $rawType
        }
        [pscustomobject]@{
            Source             = $device
            AxcientDeviceId    = $deviceId
            Name               = if ($null -ne $deviceId) { "$rawName ($deviceId)" } else { $rawName }
            Type               = $normalizedType
            ProtectionMethod   = $method
            OperatingSystem    = if ($osParts.Count -gt 0) { $osParts -join ' · ' } else { 'Unknown' }
            IpAddress          = if ([string]::IsNullOrWhiteSpace([string]$device.ip_address)) { 'Unknown' } else { [string]$device.ip_address }
            AgentStatus        = 'Not provided by API'
            AgentVersion       = if ([string]::IsNullOrWhiteSpace([string]$device.agent_version)) { 'Unknown' } else { [string]$device.agent_version }
            HealthStatus       = $healthStatus
            HealthReason       = [string]$device.current_health_status.reason
            LocalRecoveryPoint = $localPoint
            CloudRecoveryPoint = $cloudPoint
            IsStale            = $localPoint.IsStale -or $cloudPoint.IsStale
            Classification     = $classification
            VaultUsage         = Format-AmdByteSize (Get-AmdDeviceVaultUsage -Device $device)
            DetailsUrl         = [string]$device.device_details_page_url
        }
    }
}

function Get-AmdFleetCounts {
    [CmdletBinding()]
    param([AllowNull()][object[]]$DeviceStates = @())

    [pscustomobject]@{
        Healthy = @($DeviceStates | Where-Object Classification -eq 'Healthy').Count
        Warning = @($DeviceStates | Where-Object Classification -eq 'Warning').Count
        # The documented device schema contains agent_version but no agent
        # connectivity field, so reporting a numeric offline count would invent data.
        Offline = $null
        Unknown = @($DeviceStates | Where-Object Classification -eq 'Unknown').Count
    }
}

function New-AmdDeviceTable {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$DeviceStates = @(),
        [ValidateNotNullOrEmpty()][string]$PanelLabel = 'Devices'
    )

    $states = @($DeviceStates)
    $regionLabel = ConvertTo-AmdHtml "$PanelLabel device list"
    if ($states.Count -eq 0) {
        return "<div class=`"amd-device-scroll`" role=`"region`" aria-label=`"$regionLabel`" tabindex=`"0`">$(New-AmdEmptyState -Message 'No devices found.')</div>"
    }

    $builder = [Text.StringBuilder]::new(16384)
    $null = $builder.Append("<div class=`"amd-device-scroll`" role=`"region`" aria-label=`"$regionLabel`" tabindex=`"0`"><div class=`"amd-device-list`" role=`"table`">")
    $null = $builder.Append('<div class="amd-device-head amd-device-grid" role="row"><div role="columnheader">Device</div><div role="columnheader">System</div><div role="columnheader">Agent</div><div role="columnheader">Health</div><div role="columnheader">Recovery points</div><div role="columnheader">Vault usage</div></div>')
    foreach ($state in $states) {
        $rowClass = if ($state.Classification -eq 'Warning') { ' amd-row--warn' } else { '' }
        $axcientLink = "<a class=`"amd-chip`" href=`"$(ConvertTo-AmdSafeHref $state.DetailsUrl)`" target=`"_blank`" rel=`"noopener noreferrer`">Axcient</a>"
        $staleBadge = if ($state.IsStale) { ' · <span class="amd-badge amd-badge--warn">Stale backup</span>' } else { '' }
        $row = @(
            "<div class=`"amd-device-row amd-device-grid$rowClass`" role=`"row`">"
            "<div class=`"amd-device-cell`" role=`"cell`"><strong>$(ConvertTo-AmdHtml $state.Name)</strong> · <span class=`"amd-note`">$(ConvertTo-AmdHtml "$($state.Type) · $($state.ProtectionMethod)")</span> · <span class=`"amd-links`">$axcientLink</span></div>"
            "<div class=`"amd-device-cell`" role=`"cell`">$(ConvertTo-AmdHtml $state.OperatingSystem) · <span class=`"amd-note`">IP: $(ConvertTo-AmdHtml $state.IpAddress)</span></div>"
            "<div class=`"amd-device-cell`" role=`"cell`">$(ConvertTo-AmdHtml $state.AgentStatus) · <span class=`"amd-note`">Version: $(ConvertTo-AmdHtml $state.AgentVersion)</span></div>"
            "<div class=`"amd-device-cell`" role=`"cell`">$(New-AmdStatusBadge -Status $state.HealthStatus -Reason $state.HealthReason)</div>"
            "<div class=`"amd-device-cell`" role=`"cell`"><span class=`"amd-rp`"><strong>Local:</strong> $(ConvertTo-AmdHtml $state.LocalRecoveryPoint.Display)</span> · <span class=`"amd-rp`"><strong>Cloud:</strong> $(ConvertTo-AmdHtml $state.CloudRecoveryPoint.Display)</span>$staleBadge</div>"
            "<div class=`"amd-device-cell amd-device-cell--usage`" role=`"cell`">$(ConvertTo-AmdHtml $state.VaultUsage)</div>"
            '</div>'
        ) -join ''
        $null = $builder.Append($row)
    }
    $null = $builder.Append('</div></div>')
    return $builder.ToString()
}

function Get-AmdApplianceData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [AllowNull()]$Summary
    )

    try {
        return [pscustomobject]@{
            Available = $true
            Items     = @(Invoke-AmdWithRetry -Operation { $Client | Get-Appliance -ErrorAction Stop })
        }
    }
    catch {
        if ($Summary) {
            $Summary.Warnings.Add("Axcient appliance details were unavailable for '$($Client.name)'. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        }
        return [pscustomobject]@{ Available = $false; Items = @() }
    }
}

function New-AmdApplianceTable {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Appliances = @(),
        [Parameter(Mandatory)][bool]$DataAvailable
    )

    if (-not $DataAvailable) {
        return New-AmdEmptyState -Message 'Appliance details could not be retrieved during this run.'
    }
    if (@($Appliances).Count -eq 0) { return New-AmdEmptyState -Message 'No appliances found.' }

    $rows = foreach ($appliance in @($Appliances)) {
        # Unparsable sizes and IDs degrade this row instead of throwing out of the
        # foreach and losing the entire appliance table.
        $used = ConvertTo-AmdNumber $appliance.storage_details.used_size
        $size = ConvertTo-AmdNumber $appliance.storage_details.drive_size
        $storage = if ($null -ne $used -and $null -ne $size) {
            $percent = if ($size -gt 0) { [math]::Round(($used / $size) * 100, 1) } else { 0 }
            "$(Format-AmdByteSize $used) / $(Format-AmdByteSize $size) ($percent%)"
        }
        else { 'Unknown' }
        $applianceId = ConvertTo-AmdNumber $appliance.id -AsInt64
        $applianceCell = if ($null -ne $applianceId) {
            "<a class=`"amd-chip`" href=`"https://my.axcient.net/home/appliance/$applianceId`" target=`"_blank`" rel=`"noopener noreferrer`">$(ConvertTo-AmdHtml $appliance.alias)</a>"
        }
        else { "<span class=`"amd-chip amd-chip--muted`">$(ConvertTo-AmdHtml $appliance.alias)</span>" }
        @(
            '<tr>'
            "<td>$applianceCell</td>"
            "<td>$(New-AmdStatusBadge -Status $appliance.health_status -Reason $appliance.health_status_reason)</td>"
            "<td class=`"amd-num`">$(ConvertTo-AmdHtml $storage)</td>"
            '</tr>'
        ) -join ''
    }
    return @(
        '<div class="amd-table-wrap"><table class="amd-table--appliances">'
        '<colgroup><col style="width:38%"><col style="width:38%"><col style="width:24%"></colgroup>'
        '<thead><tr><th scope="col">Appliance</th><th scope="col">Status</th><th scope="col" class="amd-num">Storage</th></tr></thead>'
        "<tbody>$($rows -join '')</tbody></table></div>"
    ) -join ''
}
