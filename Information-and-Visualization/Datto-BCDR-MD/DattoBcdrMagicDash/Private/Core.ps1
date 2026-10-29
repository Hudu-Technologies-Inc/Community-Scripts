# Hudu and Datto both issue keys far longer than this. The floor exists only to
# keep an operator's typo out of the redaction list, so it is deliberately well
# below any real key rather than tuned to one vendor's current format.
$script:DbmMinimumSecretLength = 12

# Initialised at load, not left to the first Set-DbmSensitiveValues call. Under
# Set-StrictMode -Version Latest, reading an unset variable is a terminating
# error, so any failure reported BEFORE a credential was registered - a bad
# config path, an API probe that fails before connect - crashed inside
# ConvertTo-DbmRedactedText while trying to format the error message, replacing
# the real problem with a variable-not-set error.
$script:DbmSensitiveValues = @()

function Set-DbmSensitiveValues {
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
            if ($text.Length -lt $script:DbmMinimumSecretLength) { continue }
            $text
            $encoded = [Uri]::EscapeDataString($text)
            if (-not [string]::Equals($encoded, $text, [StringComparison]::Ordinal)) {
                $encoded
            }
        }
    )
    $candidates = if ($Add) {
        @($script:DbmSensitiveValues) + $newCandidates
    }
    else {
        $newCandidates
    }
    $script:DbmSensitiveValues = @(
        $candidates |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            # Redaction below is ordinal, so de-duplication has to be too. A
            # case-insensitive unique drops one of two values differing only by case
            # and leaves it printable.
            Sort-Object -Unique -CaseSensitive
    )
}

function ConvertTo-DbmRedactedText {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ($null -eq $Text) { return '' }
    $safe = $Text
    # Replace the longest values first. If one registered key is a prefix of
    # another, replacing the shorter key first would leave the longer key's
    # suffix readable.
    foreach ($secret in @($script:DbmSensitiveValues | Sort-Object Length -Descending)) {
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
            # DattoBcdrAPI 1.0.0 includes the first five key characters inside a
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
    return $safe -replace "(?i)\b(authorization|x-api-key|api[-_ ]?key)\s*[:=]\s*(?:bearer\s+)?[^\s,;]{$script:DbmMinimumSecretLength,}", '$1: [REDACTED]'
}

function ConvertTo-DbmNumber {
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

function ConvertTo-DbmHtml {
    [CmdletBinding()]
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-DbmSafeHref {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $uri = $null
    if ($null -eq $Value -or
        -not [Uri]::TryCreate([string]$Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin 'http', 'https') {
        return '#'
    }
    return ConvertTo-DbmHtml $uri.AbsoluteUri
}

function Merge-DbmTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Values
    )

    # One pass, so each placeholder is resolved exactly once. Replacing key by key
    # depends on hashtable order and lets a substituted value that happens to
    # contain '{{other_key}}' - a Datto client or device name, for example -
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

function Test-DbmTransientFailure {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ErrorRecord)

    $statusCode = if (Get-Command Get-DbmHttpStatusCode -ErrorAction SilentlyContinue) {
        Get-DbmHttpStatusCode -ErrorRecord $ErrorRecord
    }
    else { 0 }
    if ($statusCode -gt 0) { return $statusCode -in 408, 425, 429, 500, 502, 503, 504 }
    $message = [string]$ErrorRecord.Exception.Message
    return $message -match '(?i)\b429\b|too many requests|rate.?limit|timed? ?out|timeout|temporar|connection.*(reset|refused|closed)|unreachable|name.*could not be resolved|no such host|TLS|secure channel'
}

function Get-DbmRetryDelaySeconds {
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
        # Probed rather than dereferenced. Most exception types have no Response
        # property at all, and under Set-StrictMode -Version Latest reading a
        # missing property is a terminating error - thrown from inside the retry
        # path, so a plain timeout or socket failure was reported to the operator
        # as "The property 'Response' cannot be found on this object" instead of
        # the failure that actually happened.
        $retryAfter = $null
        $responseProperty = $exception.PSObject.Properties['Response']
        if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
            $headersProperty = $responseProperty.Value.PSObject.Properties['Headers']
            if ($null -ne $headersProperty -and $null -ne $headersProperty.Value) {
                $retryAfterProperty = $headersProperty.Value.PSObject.Properties['RetryAfter']
                if ($null -ne $retryAfterProperty) { $retryAfter = $retryAfterProperty.Value }
            }
        }
        if ($retryAfter) {
            $deltaProperty = $retryAfter.PSObject.Properties['Delta']
            $dateProperty = $retryAfter.PSObject.Properties['Date']
            if ($null -ne $deltaProperty -and $deltaProperty.Value) {
                $retryAfterDelta = $deltaProperty.Value
                $seconds = [math]::Ceiling($retryAfterDelta.TotalSeconds)
                return $(if ($seconds -le $MaximumDelaySeconds) { $seconds } else { -1 })
            }
            if ($null -ne $dateProperty -and $dateProperty.Value) {
                $seconds = [math]::Max(0, [math]::Ceiling(($dateProperty.Value.UtcDateTime - [DateTime]::UtcNow).TotalSeconds))
                return $(if ($seconds -le $MaximumDelaySeconds) { $seconds } else { -1 })
            }
        }
        $exception = $exception.InnerException
    }
    return [math]::Min($MaximumDelaySeconds, [math]::Min(30, $BaseDelaySeconds * [math]::Pow(2, $Attempt - 1)))
}

function Invoke-DbmWithRetry {
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
            if ($attempt -eq $Attempts -or -not (Test-DbmTransientFailure -ErrorRecord $_)) { throw }
            $delay = Get-DbmRetryDelaySeconds `
                -ErrorRecord $_ `
                -Attempt $attempt `
                -BaseDelaySeconds $DelaySeconds `
                -MaximumDelaySeconds $MaximumDelaySeconds
            if ($delay -lt 0) { throw }
            if ($delay -gt 0) { Start-Sleep -Seconds $delay }
        }
    }
}

function New-DbmSyncSummary {
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
        DattoDevicesRetrieved = 0
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

function New-DbmEmptyState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)

    return "<p class=`"dbm-empty`">$(ConvertTo-DbmHtml $Message)</p>"
}

function New-DbmStatusBadge {
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
        " · <span class=`"dbm-reason`">$(ConvertTo-DbmHtml $reasonText)</span>"
    }
    return "<span class=`"dbm-badge dbm-badge--$modifier`">$(ConvertTo-DbmHtml $label)</span>$reasonHtml"
}

function Format-DbmByteSize {
    [CmdletBinding()]
    param([AllowNull()]$Bytes)

    $value = ConvertTo-DbmNumber $Bytes
    if ($null -eq $value -or $value -lt 0) { return 'Unknown' }
    if ($value -ge 1TB) { return "$([math]::Round($value / 1TB, 2)) TB" }
    if ($value -ge 1GB) { return "$([math]::Round($value / 1GB, 1)) GB" }
    if ($value -ge 1MB) { return "$([math]::Round($value / 1MB, 0)) MB" }
    if ($value -ge 1KB) { return "$([math]::Round($value / 1KB, 0)) KB" }
    if ($value -eq 0) { return '0 MB' }
    return "$([math]::Round($value, 0)) bytes"
}

function ConvertTo-DbmUtcDateTime {
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

function Format-DbmAge {
    [CmdletBinding()]
    param([Parameter(Mandatory)][TimeSpan]$Age)

    if ($Age.TotalMinutes -lt 60) { return "$([math]::Floor([math]::Max(0, $Age.TotalMinutes)))m" }
    if ($Age.TotalHours -lt 48) { return "$([math]::Round($Age.TotalHours, 1))h" }
    return "$([math]::Round($Age.TotalDays, 1))d"
}

function Get-DbmRecoveryPointState {
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
    $timestamp = ConvertTo-DbmUtcDateTime $Value
    if ($null -eq $timestamp -or $timestamp -gt $comparisonUtc) {
        return [pscustomobject]@{ Display = 'Unknown'; IsKnown = $false; IsStale = $false; Applicable = $true }
    }
    $age = $comparisonUtc - $timestamp
    if ($age.TotalSeconds -lt 0) { $age = [TimeSpan]::Zero }
    $displayTimestamp = [TimeZoneInfo]::ConvertTimeFromUtc($timestamp, $TimeZone)
    return [pscustomobject]@{
        Display    = "$($displayTimestamp.ToString('g')) ($(Format-DbmAge -Age $age) ago)"
        IsKnown    = $true
        IsStale    = $age.TotalHours -gt $StaleBackupHours
        Applicable = $true
    }
}

function Get-DbmDeviceVolumeState {
    <#
        What Datto is and is not protecting on one asset.

        An unprotected volume is the failure this panel exists to surface: the
        machine backs up nightly, the dashboard is green, and the volume holding
        the data was never in the backup set. Count and names are both kept -
        the count drives the badge, the names tell the operator which disk.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Device)

    $protected = @(Get-DbmConfigProperty $Device 'protected_volumes' @() | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $unprotected = @(Get-DbmConfigProperty $Device 'unprotected_volumes' @() | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $display = if ($protected.Count -eq 0 -and $unprotected.Count -eq 0) {
        'Not reported'
    }
    elseif ($unprotected.Count -eq 0) {
        "$($protected.Count) protected"
    }
    else {
        "$($protected.Count) protected · $($unprotected.Count) NOT protected"
    }

    [pscustomobject]@{
        Protected          = $protected
        Unprotected        = $unprotected
        ProtectedCount     = $protected.Count
        UnprotectedCount   = $unprotected.Count
        HasUnprotected     = $unprotected.Count -gt 0
        Display            = $display
        ProtectedDetail    = if ($protected.Count -gt 0) { $protected -join ', ' } else { 'None reported' }
        UnprotectedDetail  = if ($unprotected.Count -gt 0) { $unprotected -join ', ' } else { 'None' }
    }
}

function Get-DbmDeviceProtectionMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Device,
        [AllowNull()][System.Collections.Generic.HashSet[string]]$ApplianceDeviceIds,
        [Parameter(Mandatory)][bool]$ApplianceDataAvailable
    )

    $deviceId = ConvertTo-DbmNumber $Device.id -AsInt64
    if ($Device.PSObject.Properties.Name -contains 'd2c' -and $Device.d2c -is [bool] -and $Device.d2c) {
        return 'D2C'
    }
    if ($null -ne $deviceId -and
        $null -ne $ApplianceDeviceIds -and
        $ApplianceDeviceIds.Contains([string]$deviceId)) {
        return 'Appliance'
    }

    return 'Unknown'
}

function Get-DbmDeviceDashboardStates {
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
            $id = ConvertTo-DbmNumber $applianceDevice.id -AsInt64
            if ($null -ne $id) { $null = $applianceDeviceIds.Add([string]$id) }
        }
    }

    foreach ($device in @($Devices)) {
        $method = Get-DbmDeviceProtectionMethod `
            -Device $device `
            -ApplianceDeviceIds $applianceDeviceIds `
            -ApplianceDataAvailable $ApplianceDataAvailable
        $hasLocalPoint = -not [string]::IsNullOrWhiteSpace([string]$device.latest_local_rp)
        $hasCloudPoint = -not [string]::IsNullOrWhiteSpace([string]$device.latest_cloud_rp)
        $localCacheApplicabilityKnown = $device.local_cache_details -and
            $device.local_cache_details.PSObject.Properties.Name -contains 'enabled' -and
            $device.local_cache_details.enabled -is [bool]
        $localCacheEnabled = $localCacheApplicabilityKnown -and $device.local_cache_details.enabled

        $localApplicable = switch ($method) {
            'Appliance' { $true }
            'D2C' { $localCacheEnabled }
            default { $hasLocalPoint }
        }
        $cloudApplicable = switch ($method) {
            'Appliance' { $hasCloudPoint }
            'D2C' { $true }
            default { $hasCloudPoint }
        }
        $localApplicabilityKnown = switch ($method) {
            'D2C' { $localCacheApplicabilityKnown }
            default { $true }
        }
        $localPoint = Get-DbmRecoveryPointState `
            -Value $device.latest_local_rp `
            -Applicable $localApplicable `
            -ApplicabilityKnown $localApplicabilityKnown `
            -StaleBackupHours $StaleBackupHours `
            -NowUtc $NowUtc `
            -TimeZone $TimeZone
        $cloudPoint = Get-DbmRecoveryPointState `
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
        $osBits = ConvertTo-DbmNumber $device.os.bits -AsInt64
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
        $deviceId = ConvertTo-DbmNumber $device.id -AsInt64
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
            DattoDeviceId    = $deviceId
            Name               = if ($null -ne $deviceId) { "$rawName ($deviceId)" } else { $rawName }
            Type               = $normalizedType
            ProtectionMethod   = $method
            OperatingSystem    = if ($osParts.Count -gt 0) { $osParts -join ' · ' } else { 'Unknown' }
            IpAddress          = if ([string]::IsNullOrWhiteSpace([string]$device.ip_address)) { 'Unknown' } else { [string]$device.ip_address }
            AgentVersion       = if ([string]::IsNullOrWhiteSpace([string]$device.agent_version)) { 'Unknown' } else { [string]$device.agent_version }
            HealthStatus       = $healthStatus
            HealthReason       = [string]$device.current_health_status.reason
            LocalRecoveryPoint = $localPoint
            CloudRecoveryPoint = $cloudPoint
            IsStale            = $localPoint.IsStale -or $cloudPoint.IsStale
            Classification     = $classification
            DetailsUrl         = [string]$device.device_details_page_url
            AssetKind          = [string](Get-DbmConfigProperty $device 'asset_kind' 'Agent')
            VolumeName         = [string](Get-DbmConfigProperty $device 'volume_name' '')
            Volumes            = Get-DbmDeviceVolumeState -Device $device
            ScreenshotStatus   = Get-DbmConfigProperty $device 'screenshot_status' $null
            ScreenshotUrl      = [string](Get-DbmConfigProperty $device 'screenshot_url' '')
            ScreenshotAttempt  = $(
                $shotUtc = ConvertTo-DbmUtcDateTime (Get-DbmConfigProperty $device 'screenshot_attempt' $null)
                if ($null -eq $shotUtc) { '' } else { [TimeZoneInfo]::ConvertTimeFromUtc($shotUtc, $TimeZone).ToString('g') }
            )
            # Filled in by Add-DbmDeviceContext, which fetches per appliance and
            # joins down to the device. Present from the start so nothing has to
            # test for its existence under StrictMode.
            Restores           = @()
        }
    }
}

function Get-DbmFleetCounts {
    [CmdletBinding()]
    param([AllowNull()][object[]]$DeviceStates = @())

    # No Offline count. Datto reports no per-device connectivity field, so the
    # Axcient build's offline tile could only ever render "Unknown" - a permanently
    # empty box that reads as missing data rather than as "not applicable here".
    # ScreenshotVerified replaces it with something Datto does report: how many
    # machines Datto has booted from their recovery point and confirmed came up.
    $states = @($DeviceStates)
    [pscustomobject]@{
        Healthy            = @($states | Where-Object Classification -eq 'Healthy').Count
        Warning            = @($states | Where-Object Classification -eq 'Warning').Count
        Unknown            = @($states | Where-Object Classification -eq 'Unknown').Count
        ScreenshotVerified = @($states | Where-Object { (Get-DbmConfigProperty $_ 'ScreenshotStatus' $null) -eq $true }).Count
        # Shares are excluded from the denominator. Datto screenshots a machine by
        # booting its recovery point, which a file share has none of, so counting
        # shares would permanently understate the ratio: a client with 10 agents
        # and 5 shares would read "8 / 15" when 8 of 10 bootable machines are
        # verified. AssetKind is set by this code from the typed endpoint the
        # record came from, not read from the share payload, so it is reliable
        # even though no share has ever been sampled.
        ScreenshotTotal    = @($states | Where-Object {
                -not [string]::Equals(
                    [string](Get-DbmConfigProperty $_ 'AssetKind' ''),
                    'Share',
                    [StringComparison]::OrdinalIgnoreCase
                )
            }).Count
    }
}

function Get-DbmProtectionCounts {
    [CmdletBinding()]
    param([AllowNull()][object[]]$DeviceStates = @())

    $counts = [ordered]@{
        ApplianceServer       = 0
        ApplianceWorkstation  = 0
        D2cServer             = 0
        D2cWorkstation        = 0
    }
    foreach ($state in @($DeviceStates)) {
        $type = ([string](Get-DbmConfigProperty $state 'Type' '')).Trim()
        if (-not [string]::Equals($type, 'SERVER', [StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::Equals($type, 'WORKSTATION', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $method = ([string](Get-DbmConfigProperty $state 'ProtectionMethod' '')).Trim()
        $suffix = if ([string]::Equals($type, 'SERVER', [StringComparison]::OrdinalIgnoreCase)) { 'Server' } else { 'Workstation' }
        switch -Regex ($method) {
            '^(?i:Appliance)$' { $counts["Appliance$suffix"]++; continue }
            '^(?i:D2C)$' { $counts["D2c$suffix"]++; continue }
        }
    }

    return [pscustomobject]$counts
}

function New-DbmProtectionRows {
    <#
        Rows for the protection-methods table, built from the counts rather than
        hardcoded in the template.

        Only methods that actually carry devices are rendered. Appliance-based is
        always shown because it is what this build reports; Direct-to-Cloud appears
        the moment DTC assets are ingested and stays hidden until then, instead of
        occupying a row that can only read 0 / 0. The Axcient build's Cloud Archive
        row had exactly that problem.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Counts)

    $rows = [System.Collections.Generic.List[string]]::new()
    $methods = @(
        @{ Label = 'Appliance-based'; Server = 'ApplianceServer'; Workstation = 'ApplianceWorkstation'; Always = $true }
        @{ Label = 'Direct-to-Cloud'; Server = 'D2cServer'; Workstation = 'D2cWorkstation'; Always = $false }
    )
    foreach ($method in $methods) {
        $server = [int](Get-DbmConfigProperty $Counts $method.Server 0)
        $workstation = [int](Get-DbmConfigProperty $Counts $method.Workstation 0)
        if (-not $method.Always -and $server -eq 0 -and $workstation -eq 0) { continue }
        $rows.Add(
            "<tr><th scope=`"row`">$(ConvertTo-DbmHtml $method.Label)</th>" +
            "<td class=`"dbm-num`">$server</td>" +
            "<td class=`"dbm-num`">$workstation</td></tr>"
        )
    }
    return ($rows -join '')
}
function New-DbmDeviceTable {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$DeviceStates = @(),
        [ValidateNotNullOrEmpty()][string]$PanelLabel = 'Devices'
    )

    $states = @($DeviceStates)
    $regionLabel = ConvertTo-DbmHtml "$PanelLabel device list"
    if ($states.Count -eq 0) {
        return "<div class=`"dbm-device-scroll`" role=`"region`" aria-label=`"$regionLabel`" tabindex=`"0`">$(New-DbmEmptyState -Message 'No devices found.')</div>"
    }

    $builder = [Text.StringBuilder]::new(16384)
    $null = $builder.Append("<div class=`"dbm-device-scroll`" role=`"region`" aria-label=`"$regionLabel`" tabindex=`"0`"><div class=`"dbm-device-list`" role=`"table`">")
    $null = $builder.Append('<div class="dbm-device-head dbm-device-grid" role="row"><div role="columnheader">Device</div><div role="columnheader">System</div><div role="columnheader">Agent</div><div role="columnheader">Health</div><div role="columnheader">Recovery points</div><div role="columnheader">Volumes</div><div role="columnheader">Screenshot</div></div>')
    foreach ($state in $states) {
        $rowClass = if ($state.Classification -eq 'Warning') { ' dbm-row--warn' } else { '' }
        $dattoLink = "<a class=`"dbm-chip`" href=`"$(ConvertTo-DbmSafeHref $state.DetailsUrl)`" target=`"_blank`" rel=`"noopener noreferrer`">Datto</a>"
        $staleBadge = if ($state.IsStale) { ' · <span class="dbm-badge dbm-badge--warn">Stale backup</span>' } else { '' }
        $kindChip = "<span class=`"dbm-chip dbm-chip--muted`">$(ConvertTo-DbmHtml $state.AssetKind)</span>"
        $row = @(
            "<div class=`"dbm-device-row dbm-device-grid$rowClass`" role=`"row`">"
            "<div class=`"dbm-device-cell`" role=`"cell`"><strong>$(ConvertTo-DbmHtml $state.Name)</strong> · <span class=`"dbm-note`">$(ConvertTo-DbmHtml "$($state.Type) · $($state.ProtectionMethod)")</span> · <span class=`"dbm-links`">$kindChip $dattoLink</span></div>"
            "<div class=`"dbm-device-cell`" role=`"cell`">$(ConvertTo-DbmHtml $state.OperatingSystem) · <span class=`"dbm-note`">IP: $(ConvertTo-DbmHtml $state.IpAddress)</span></div>"
            "<div class=`"dbm-device-cell`" role=`"cell`">$(ConvertTo-DbmHtml $state.AgentVersion)</div>"
            "<div class=`"dbm-device-cell`" role=`"cell`">$(New-DbmStatusBadge -Status $state.HealthStatus -Reason $state.HealthReason)$(New-DbmRestoreBadge -Restores (Get-DbmConfigProperty $state 'Restores' @()))</div>"
            "<div class=`"dbm-device-cell`" role=`"cell`"><span class=`"dbm-rp`"><strong>Local:</strong> $(ConvertTo-DbmHtml $state.LocalRecoveryPoint.Display)</span> · <span class=`"dbm-rp`"><strong>Cloud:</strong> $(ConvertTo-DbmHtml $state.CloudRecoveryPoint.Display)</span>$staleBadge</div>"
            "<div class=`"dbm-device-cell`" role=`"cell`">$(New-DbmVolumeCell -VolumeState $state.Volumes)</div>"
            "<div class=`"dbm-device-cell`" role=`"cell`">$(New-DbmScreenshotCell -DeviceState $state)</div>"
            '</div>'
        ) -join ''
        $null = $builder.Append($row)
    }
    $null = $builder.Append('</div></div>')
    return $builder.ToString()
}

function New-DbmVolumeCell {
    [CmdletBinding()]
    param([AllowNull()]$VolumeState)

    if ($null -eq $VolumeState) { return '<span class="dbm-note">Not reported</span>' }
    if ($VolumeState.HasUnprotected) {
        # An unprotected volume is named, not just counted: "1 NOT protected"
        # sends the operator back to the portal to find out which one.
        return @(
            "<span class=`"dbm-badge dbm-badge--warn`">$(ConvertTo-DbmHtml $VolumeState.Display)</span>"
            "<span class=`"dbm-note`">Unprotected: $(ConvertTo-DbmHtml $VolumeState.UnprotectedDetail)</span>"
        ) -join ' '
    }
    return @(
        "<span class=`"dbm-badge dbm-badge--ok`">$(ConvertTo-DbmHtml $VolumeState.Display)</span>"
        "<span class=`"dbm-note`">$(ConvertTo-DbmHtml $VolumeState.ProtectedDetail)</span>"
    ) -join ' '
}

function New-DbmScreenshotCell {
    <#
        Screenshot backup verification for one device row.

        Datto boots the recovery point and reports whether it came up. That is
        stronger evidence than "a backup exists": a job can complete nightly and
        still restore to an unbootable machine. A device the appliance never
        attempted is Unknown rather than a pass or a fail, because not tried and
        tried-and-failed are different facts.
    #>
    [CmdletBinding()]
    param([AllowNull()]$DeviceState)

    $status = Get-DbmConfigProperty $DeviceState 'ScreenshotStatus' $null
    $attempt = [string](Get-DbmConfigProperty $DeviceState 'ScreenshotAttempt' '')
    if ($null -eq $status) {
        return '<span class="dbm-badge dbm-badge--muted">Not attempted</span>'
    }
    $badge = if ($status) {
        '<span class="dbm-badge dbm-badge--ok">Verified</span>'
    }
    else {
        '<span class="dbm-badge dbm-badge--warn">Failed</span>'
    }
    $url = [string](Get-DbmConfigProperty $DeviceState 'ScreenshotUrl' '')
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        $badge = "<a href=`"$(ConvertTo-DbmSafeHref $url)`" target=`"_blank`" rel=`"noopener noreferrer`">$badge</a>"
    }
    if ([string]::IsNullOrWhiteSpace($attempt)) { return $badge }
    return "$badge <span class=`"dbm-note`">$(ConvertTo-DbmHtml $attempt)</span>"
}

function New-DbmAlertRuleTable {
    <#
        The alert RULES configured on a client's appliances.

        This panel is deliberately not a list of problems. /bcdr/device/{serial}/alert
        returns what each appliance is configured to alert ON - type, threshold,
        unit, and when that rule last fired - not what is wrong right now. The
        count of alerts actually firing comes from alertCount on the appliance
        record and drives the appliance health badge instead.

        A null Rules value means the endpoint could not be read, which is
        reported as such rather than as "nothing configured".
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Rules,
        [Parameter(Mandatory)][bool]$DataAvailable,
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Local
    )

    if (-not $DataAvailable) {
        return New-DbmEmptyState -Message 'Datto alert rules could not be retrieved during this run.'
    }
    $rows = @($Rules | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        return New-DbmEmptyState -Message 'No alert rules are configured on these appliances.'
    }

    $bodyRows = foreach ($rule in $rows) {
        # Rendered in the operator's configured zone like every other timestamp on
        # the dashboard. A raw ISO string here would be the only machine-formatted
        # date on the page.
        $triggeredUtc = ConvertTo-DbmUtcDateTime $rule.last_triggered
        $triggered = if ($null -eq $triggeredUtc) { 'Never' }
            else { [TimeZoneInfo]::ConvertTimeFromUtc($triggeredUtc, $TimeZone).ToString('g') }
        @(
            '<tr>'
            "<td>$(ConvertTo-DbmHtml "Appliance $([string]$rule.appliance_serial)")</td>"
            "<td>$(ConvertTo-DbmHtml $rule.description)</td>"
            "<td>$(ConvertTo-DbmHtml $triggered)</td>"
            '</tr>'
        ) -join ''
    }
    return @(
        '<div class="dbm-table-wrap"><table class="dbm-table--alerts">'
        '<colgroup><col style="width:30%"><col style="width:42%"><col style="width:28%"></colgroup>'
        '<thead><tr><th scope="col">Appliance</th><th scope="col">Alert rule</th><th scope="col">Last triggered</th></tr></thead>'
        "<tbody>$($bodyRows -join '')</tbody></table></div>"
    ) -join ''
}

function Get-DbmAlertRuleData {
    <#
        Configured alert rules for every appliance a client owns, merged.

        One unreadable appliance marks the whole panel unavailable rather than
        showing a partial list that reads as "these are all the rules".
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Appliances = @(),
        [AllowNull()]$Summary
    )

    $all = [System.Collections.Generic.List[object]]::new()
    $available = $true
    foreach ($appliance in @($Appliances)) {
        $serial = [string](Get-DbmConfigProperty $appliance 'serial_number' '')
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }
        $rules = $null
        try {
            $rules = Invoke-DbmWithRetry -Operation { Get-DattoBcdrAlertRule -SerialNumber $serial }
        }
        catch {
            $available = $false
            if ($Summary) {
                $Summary.Warnings.Add("Datto alert rules were unavailable for appliance $serial. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
            }
            continue
        }
        # No $null check here. An appliance with NO configured rules returns an
        # empty array, and Invoke-DbmWithRetry hands an empty array back as $null,
        # so testing for $null reported every quiet appliance as unreadable. A
        # genuine failure throws and is handled above, with its reason attached.
        foreach ($rule in @($rules)) { $all.Add($rule) }
    }
    return [pscustomobject]@{ Available = $available; Items = $all.ToArray() }
}

function Add-DbmDeviceContext {
    <#
        Fetches VM restores once and joins them down to the device rows, and
        collects the appliance alert rules for the summary panel.

        This is called by BOTH render paths - the Magic Dash and the Hudu device
        assets - so the two cannot drift into showing a machine different things
        about itself.

        Alerts are deliberately NOT joined to devices. A Datto alert record
        carries no asset and no volume, so there is nothing to join on; the
        previous volume-hash-then-name join could never match, and the rule that
        escalated an alerting device to Warning could never fire. Appliance
        health carries the alert signal instead.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$DeviceStates = @(),
        [AllowNull()][object[]]$Appliances = @(),
        [AllowNull()]$Summary
    )

    $restoreData = Get-DbmVmRestoreData -Appliances $Appliances -Summary $Summary
    $unmatchedRestores = @(Join-DbmDeviceRestores -DeviceStates $DeviceStates -Restores $restoreData.Items)
    $ruleData = Get-DbmAlertRuleData -Appliances $Appliances -Summary $Summary

    return [pscustomobject]@{
        RestoresAvailable = $restoreData.Available
        RestoreCount      = @($restoreData.Items).Count
        UnmatchedRestores = $unmatchedRestores
        AlertRulesAvailable = $ruleData.Available
        AlertRuleCount      = @($ruleData.Items).Count
        AlertRules          = $ruleData.Items
    }
}
function Join-DbmDeviceRestores {
    <#
        Attaches each VM restore to the device it is restoring.

        The restore endpoint is per APPLIANCE, but a restore record names the
        asset, so the join brings it down to the row the operator is actually
        looking at. Two keys, in order:

          1. volume hash - the asset's real identity, and what every asset-level
             Datto endpoint is keyed on
          2. asset name  - a fallback, because the restore payload shape is not
             sampled in the reference and may only carry a name

        Anything that matches neither is returned as unmatched rather than
        dropped: a restore running against an asset this client's list does not
        contain is exactly the thing worth seeing.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$DeviceStates = @(),
        [AllowNull()][object[]]$Restores = @()
    )

    $byVolume = @{}
    $byName = @{}
    foreach ($state in @($DeviceStates)) {
        # Every state gets the property whether or not it has restores, so the
        # renderer never has to test for its existence.
        Add-Member -InputObject $state -NotePropertyName Restores -NotePropertyValue @() -Force
        $volume = ([string]$state.VolumeName).Trim()
        if (-not [string]::IsNullOrWhiteSpace($volume)) { $byVolume[$volume.ToLowerInvariant()] = $state }
        # The row name carries an id suffix; the raw asset name is on the source.
        $rawName = ([string](Get-DbmConfigProperty $state.Source 'name' '')).Trim()
        if (-not [string]::IsNullOrWhiteSpace($rawName)) { $byName[$rawName.ToLowerInvariant()] = $state }
    }

    $unmatched = [System.Collections.Generic.List[object]]::new()
    foreach ($restore in @($Restores | Where-Object { $null -ne $_ })) {
        $volumeKey = ([string]$restore.volume).Trim().ToLowerInvariant()
        $nameKey = ([string]$restore.asset_name).Trim().ToLowerInvariant()
        $target = $null
        if ($volumeKey -and $byVolume.ContainsKey($volumeKey)) { $target = $byVolume[$volumeKey] }
        elseif ($nameKey -and $byName.ContainsKey($nameKey)) { $target = $byName[$nameKey] }

        if ($null -eq $target) { $unmatched.Add($restore); continue }
        $target.Restores = @($target.Restores) + $restore
    }
    return @($unmatched)
}

function New-DbmRestoreBadge {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Restores = @())

    $rows = @($Restores | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return '' }
    $label = if ($rows.Count -eq 1) { 'VM restore running' } else { "$($rows.Count) VM restores running" }
    $detail = @($rows | ForEach-Object {
            $parts = @([string]$_.type, [string]$_.status) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($parts.Count -gt 0) { $parts -join ' · ' } else { $null }
        } | Where-Object { $_ }) -join '; '
    $detailHtml = if ([string]::IsNullOrWhiteSpace($detail)) { '' } else { " <span class=`"dbm-note`">$(ConvertTo-DbmHtml $detail)</span>" }
    return " · <span class=`"dbm-badge dbm-badge--warn`">$(ConvertTo-DbmHtml $label)</span>$detailHtml"
}

function New-DbmVmRestoreTable {
    <#
        Active VM restores across the client's appliances.

        A null Restores value means the endpoint could not be read, which is
        reported as such. An empty array means there are genuinely none running,
        which is the normal state and is not a warning.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Restores,
        [Parameter(Mandatory)][bool]$DataAvailable,
        # True when restores were found but every one of them was joined to a
        # device row. The distinction matters: "none running" and "all of them
        # are shown on the rows above" are different facts.
        [bool]$AllJoined = $false
    )

    if (-not $DataAvailable) {
        return New-DbmEmptyState -Message 'VM restore details could not be retrieved during this run.'
    }
    $rows = @($Restores | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        $message = if ($AllJoined) {
            'Every running VM restore is shown on its device row above.'
        }
        else {
            'No VM restores are running.'
        }
        return New-DbmEmptyState -Message $message
    }

    $bodyRows = foreach ($restore in $rows) {
        $started = if ([string]::IsNullOrWhiteSpace([string]$restore.started)) {
            'Unknown'
        }
        else {
            [string]$restore.started
        }
        @(
            '<tr>'
            "<td>$(ConvertTo-DbmHtml $restore.asset_name)</td>"
            "<td>$(ConvertTo-DbmHtml $restore.type)</td>"
            "<td>$(New-DbmStatusBadge -Status $restore.status)</td>"
            "<td>$(ConvertTo-DbmHtml $started)</td>"
            '</tr>'
        ) -join ''
    }
    return @(
        '<div class="dbm-table-wrap"><table class="dbm-table--restores">'
        '<colgroup><col style="width:34%"><col style="width:20%"><col style="width:23%"><col style="width:23%"></colgroup>'
        '<thead><tr><th scope="col">Asset</th><th scope="col">Type</th><th scope="col">Status</th><th scope="col">Started</th></tr></thead>'
        "<tbody>$($bodyRows -join '')</tbody></table></div>"
    ) -join ''
}

function Get-DbmVmRestoreData {
    <#
        VM restores for every appliance a client owns, merged.

        One unreadable appliance marks the whole panel unavailable rather than
        showing a partial list that reads as "these are all the restores".
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Appliances = @(),
        [AllowNull()]$Summary
    )

    $all = [System.Collections.Generic.List[object]]::new()
    $available = $true
    foreach ($appliance in @($Appliances)) {
        $serial = [string](Get-DbmConfigProperty $appliance 'serial_number' '')
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }
        try {
            $restores = Invoke-DbmWithRetry -Operation { Get-DattoBcdrVmRestore -SerialNumber $serial }
        }
        catch {
            $available = $false
            if ($Summary) {
                $Summary.Warnings.Add("Datto VM restores were unavailable for appliance $serial. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
            }
            continue
        }
        # No $null check here: an appliance with NO running restores returns an
        # empty array, which Invoke-DbmWithRetry hands back as $null. Treating
        # that as a failure reported "restores unavailable" for every appliance
        # that simply had nothing restoring. A real failure throws, above.
        foreach ($restore in @($restores)) { $all.Add($restore) }
    }
    return [pscustomobject]@{ Available = $available; Items = $all.ToArray() }
}

function Get-DbmApplianceData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [AllowNull()]$Summary
    )

    try {
        return [pscustomobject]@{
            Available = $true
            Items     = @(Invoke-DbmWithRetry -Operation { $Client | Get-Appliance -ErrorAction Stop })
        }
    }
    catch {
        if ($Summary) {
            $Summary.Warnings.Add("Datto appliance details were unavailable for '$($Client.name)'. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        }
        return [pscustomobject]@{ Available = $false; Items = @() }
    }
}

function New-DbmApplianceTable {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Appliances = @(),
        [Parameter(Mandatory)][bool]$DataAvailable
    )

    if (-not $DataAvailable) {
        return New-DbmEmptyState -Message 'Appliance details could not be retrieved during this run.'
    }
    if (@($Appliances).Count -eq 0) { return New-DbmEmptyState -Message 'No appliances found.' }

    $rows = foreach ($appliance in @($Appliances)) {
        # Unparsable sizes and IDs degrade this row instead of throwing out of the
        # foreach and losing the entire appliance table.
        $used = ConvertTo-DbmNumber $appliance.storage_details.used_size
        $size = ConvertTo-DbmNumber $appliance.storage_details.drive_size
        $storage = if ($null -ne $used -and $null -ne $size) {
            $percent = if ($size -gt 0) { [math]::Round(($used / $size) * 100, 1) } else { 0 }
            "$(Format-DbmByteSize $used) / $(Format-DbmByteSize $size) ($percent%)"
        }
        else { 'Unknown' }
        # A Datto appliance is identified by its serial number, which is
        # alphanumeric ("00012E64B9B0"). The Axcient build parsed this id as an
        # integer, so every Datto appliance would fail that test and render
        # unlinked.
        $applianceId = [string]$appliance.id
        $applianceCell = if (-not [string]::IsNullOrWhiteSpace($applianceId)) {
            "<a class=`"dbm-chip`" href=`"https://auth.datto.com/login`" target=`"_blank`" rel=`"noopener noreferrer`">$(ConvertTo-DbmHtml $appliance.alias)</a>"
        }
        else { "<span class=`"dbm-chip dbm-chip--muted`">$(ConvertTo-DbmHtml $appliance.alias)</span>" }
        @(
            '<tr>'
            "<td>$applianceCell</td>"
            "<td>$(New-DbmStatusBadge -Status $appliance.health_status -Reason $appliance.health_status_reason)</td>"
            "<td class=`"dbm-num`">$(ConvertTo-DbmHtml $storage)</td>"
            '</tr>'
        ) -join ''
    }
    return @(
        '<div class="dbm-table-wrap"><table class="dbm-table--appliances">'
        '<colgroup><col style="width:38%"><col style="width:38%"><col style="width:24%"></colgroup>'
        '<thead><tr><th scope="col">Appliance</th><th scope="col">Status</th><th scope="col" class="dbm-num">Storage</th></tr></thead>'
        "<tbody>$($rows -join '')</tbody></table></div>"
    ) -join ''
}
