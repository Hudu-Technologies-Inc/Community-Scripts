function ConvertTo-NormalizedHuduUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )

    $candidate = $Url.Trim()
    while ($candidate.Length -ge 2 -and
        (($candidate.StartsWith('"') -and $candidate.EndsWith('"')) -or
         ($candidate.StartsWith("'") -and $candidate.EndsWith("'")))) {
        $candidate = $candidate.Substring(1, $candidate.Length - 2).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'Enter the web address for your Hudu instance.'
    }

    $candidate = $candidate.Replace([char]0xFF0F, '/').Replace([char]0xFF3C, '/').Replace([char]0xFF1A, ':')
    $candidate = $candidate.Replace('\', '/')
    $candidate = $candidate -replace '\s+', ''

    if ($candidate -match '^(?i)(?:ftp|file|javascript|data):') {
        throw 'The Hudu address must be an HTTP or HTTPS web address.'
    }

    # Remembered before the scheme is stripped. An http address carries port 80 as
    # its default, and forcing https would otherwise keep that port and make the
    # same instance normalize two different ways.
    $wroteHttp = $candidate -match '^(?i)http:'
    # Remove even badly pasted HTTP schemes, such as "https:/", "https:////", or "http: //".
    $candidate = $candidate -replace '^(?i)https?:/*', ''
    $candidate = $candidate -replace '^/+', ''

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'The Hudu address does not contain a domain name.'
    }

    $parsed = $null
    if (-not [Uri]::TryCreate("https://$candidate", [UriKind]::Absolute, [ref]$parsed)) {
        throw 'The Hudu address is not a valid domain or URL. Use the complete address shown in your Hudu browser tab.'
    }

    if ($parsed.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($parsed.Host)) {
        throw 'The Hudu address is not a valid HTTPS web address.'
    }

    if (-not [string]::IsNullOrEmpty($parsed.UserInfo)) {
        throw 'Do not include a username or password in the Hudu address.'
    }

    $hostKind = [Uri]::CheckHostName($parsed.Host)
    if ($hostKind -eq [UriHostNameType]::Unknown) {
        throw 'The Hudu address does not contain a valid domain name.'
    }

    if ($hostKind -eq [UriHostNameType]::Dns -and -not $parsed.Host.Contains('.')) {
        throw 'Enter the complete Hudu domain name, including its domain suffix.'
    }

    $builder = [UriBuilder]::new($parsed)
    $builder.Scheme = 'https'
    # A trailing dot is the same host fully qualified. Two spellings of one instance
    # must not compare as different, because that is read as an instance change and
    # clears every company match and queued recovery operation.
    $builder.Host = $parsed.IdnHost.ToLowerInvariant().TrimEnd('.')
    $builder.Path = '/'
    $builder.Query = ''
    $builder.Fragment = ''
    if ($parsed.IsDefaultPort -or $parsed.Port -eq 443 -or ($wroteHttp -and $parsed.Port -eq 80)) {
        $builder.Port = -1
    }

    return $builder.Uri.GetLeftPart([UriPartial]::Authority).TrimEnd('/')
}

function ConvertTo-AmdNormalizedApiKey {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Key
    )

    $original = if ($null -eq $Key) { '' } else { [string]$Key }
    $trimmed = $original.Trim()
    while ($trimmed.Length -ge 2 -and
        (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
         ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'")))) {
        $trimmed = $trimmed.Substring(1, $trimmed.Length - 2).Trim()
    }

    [pscustomobject]@{
        Value                 = $trimmed
        HadOuterWhitespace    = ($original -ne $original.Trim())
        HadSurroundingQuotes  = ($original.Trim() -ne $trimmed)
        HasEmbeddedWhitespace = [bool]($trimmed -match '\s')
        IsEmpty               = [string]::IsNullOrWhiteSpace($trimmed)
        IsUsable              = -not [string]::IsNullOrWhiteSpace($trimmed) -and $trimmed -notmatch '\s'
    }
}

function Get-AmdHttpStatusCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ErrorRecord)

    $current = $ErrorRecord
    for ($i = 0; $i -lt 5 -and $null -ne $current; $i++) {
        $statusProperty = $current.PSObject.Properties['StatusCode']
        if ($null -ne $statusProperty -and $null -ne $statusProperty.Value) {
            try { return [int]$statusProperty.Value } catch { Write-Verbose 'The API status code could not be converted to an integer.' }
        }
        if ($null -ne $current.Response -and $null -ne $current.Response.StatusCode) {
            try { return [int]$current.Response.StatusCode } catch { Write-Verbose 'The HTTP status code could not be converted to an integer.' }
        }
        if ($null -ne $current.Exception) {
            $current = $current.Exception
        }
        elseif ($null -ne $current.InnerException) {
            $current = $current.InnerException
        }
        else {
            break
        }
    }
    return $null
}

function Get-AmdApiFailureMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Hudu', 'Axcient')]
        [string]$Service,

        [Parameter(Mandatory)]
        $ErrorRecord,

        [switch]$HadEmbeddedWhitespace
    )

    if ($HadEmbeddedWhitespace) {
        return "The $Service API key contains spaces, tabs, or line breaks inside the key. Copy the key again without extra characters and retry."
    }

    $statusCode = Get-AmdHttpStatusCode -ErrorRecord $ErrorRecord
    $message = if ($ErrorRecord.Exception) {
        [string]$ErrorRecord.Exception.Message
    }
    else {
        [string]$ErrorRecord
    }
    $lower = $message.ToLowerInvariant()

    if ($statusCode -eq 401 -or $lower -match '\b401\b|unauthori[sz]ed|invalid (api )?key|authentication failed') {
        return "The $Service API key was rejected. It may be incorrect, disabled, revoked, expired, or no longer present in $Service. Create or copy an active key and try again."
    }
    if ($statusCode -eq 403 -or $lower -match '\b403\b|\bforbidden\b|permission denied|not permitted') {
        return "The $Service API accepted the request but denied access. Confirm that the key is active and has permission to read the required companies, clients, devices, and backup data."
    }
    if ($statusCode -eq 404 -or $lower -match '\b404\b') {
        return "The $Service server was reached, but the required API endpoint was not found. Confirm the server URL and that this $Service version supports its API."
    }
    if ($statusCode -eq 429 -or $lower -match '\b429\b|too many requests|rate.?limit') {
        return "$Service is temporarily rate-limiting API requests. Wait a few minutes, then retry with the same key."
    }
    if ($lower -match 'name or service not known|no such host|remote name could not be resolved|nodename nor servname|\bdns\b') {
        return "The $Service server name could not be resolved. Check the URL, DNS, and Internet connection; the API key has not been blamed."
    }
    if ($lower -match 'certificate|ssl|tls|secure channel|trust relationship') {
        return "A TLS/certificate error prevented a secure connection to $Service. Check the server certificate, system clock, and trusted certificate chain."
    }
    if ($lower -match 'timed? ?out|timeout|operation was canceled|connection.*refused|actively refused|unreachable') {
        return "The $Service server did not respond in time. Check the URL, firewall, service status, and Internet connection, then retry."
    }

    return "The $Service connection test failed for an unexpected reason. Recheck the server address and key, then retry. If it continues, verify that the $Service API service is online."
}

function Test-AmdHuduReachability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,
        [ValidateRange(2, 60)]
        [int]$TimeoutSec = 15
    )

    # Normalized outside the try, and every result below reports this value, so it
    # always holds at least the caller's original input. Inside the try its precise
    # rejection reason would be handed to the API failure classifier, which has no
    # branch for it and reports 'failed for an unexpected reason' instead.
    $normalized = [string]$BaseUrl
    try { $normalized = ConvertTo-NormalizedHuduUrl -Url $BaseUrl }
    catch {
        # These messages name the exact problem with the address and hold no secrets.
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message; BaseUrl = $normalized }
    }
    try {
        $null = Invoke-WebRequest -Uri $normalized -Method Head -TimeoutSec $TimeoutSec -MaximumRedirection 3 -ErrorAction Stop
        return [pscustomobject]@{ Success = $true; Message = "Reached $normalized."; BaseUrl = $normalized }
    }
    catch {
        $status = Get-AmdHttpStatusCode -ErrorRecord $_
        if ($status -ge 100 -and $status -le 599) {
            return [pscustomobject]@{ Success = $true; Message = "The Hudu host responded with HTTP $status. The API key test will verify API access next."; BaseUrl = $normalized }
        }
        return [pscustomobject]@{
            Success = $false
            Message = Get-AmdApiFailureMessage -Service Hudu -ErrorRecord $_
            BaseUrl = $normalized
        }
    }
}

function Test-AmdHuduConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$ApiKey
    )

    $keyInfo = ConvertTo-AmdNormalizedApiKey -Key $ApiKey
    if (-not $keyInfo.IsUsable) {
        $message = if ($keyInfo.IsEmpty) {
            'The Hudu API key is empty. Paste an active API key and try again.'
        }
        else {
            Get-AmdApiFailureMessage -Service Hudu -ErrorRecord ([System.Exception]::new('Invalid key format')) -HadEmbeddedWhitespace
        }
        return [pscustomobject]@{ Success = $false; Message = $message; Data = $null }
    }
    # Registered before the call, not after it: a vendor failure can echo the key,
    # so it has to already be redactable. Registration still happens only once the
    # value could be a key at all - Set-AmdSensitiveValues drops anything too short
    # to be one, so a mistyped word cannot become a session-wide redaction rule that
    # blanks that word out of every later message.
    Set-AmdSensitiveValues -Values @($keyInfo.Value) -Add

    # Normalized outside the try for the same reason as Test-AmdHuduReachability:
    # its rejection reason names the exact problem, and the API failure classifier
    # would replace that with a generic message.
    $normalized = [string]$BaseUrl
    try { $normalized = ConvertTo-NormalizedHuduUrl -Url $BaseUrl }
    catch {
        return [pscustomobject]@{
            Success = $false
            Message = $_.Exception.Message
            Data    = $null
            BaseUrl = $normalized
        }
    }
    try {
        Connect-AmdHudu -InstanceUrl $normalized -ApiKey $keyInfo.Value -ErrorAction Stop
        $appInfo = Get-AmdHuduAppInfo -ErrorAction Stop
        $appVersion = [string](Get-AmdConfigProperty $appInfo 'version' '')
        if ($null -eq $appInfo -or
            [string]::IsNullOrWhiteSpace($appVersion) -or
            [string]::Equals($appVersion, '0.0.0.0', [StringComparison]::OrdinalIgnoreCase)) {
            # HuduAPI 2.50 used to swallow any request failure and return version
            # 0.0.0.0. The bridge now surfaces structured failures, but keeping this
            # payload check prevents a future client regression from turning a
            # rejected key into a false "Connected successfully" result again.
            throw [System.InvalidOperationException]::new(
                'Hudu did not return usable application information; the API key was not accepted.'
            )
        }
        return [pscustomobject]@{
            Success = $true
            Message = "Connected successfully to Hudu at $normalized."
            Data    = $appInfo
            BaseUrl = $normalized
        }
    }
    catch {
        $connectionError = $_
        # A rejected key is a valid protocol response, so the persistent bridge stays
        # alive unless this layer closes it. Do not leave an authenticated child and
        # its open session running while setup waits for the operator to retry.
        try { Disconnect-AmdHudu }
        catch {
            Write-Verbose "The failed Hudu connection could not be closed cleanly: $(ConvertTo-AmdRedactedText $_.Exception.Message)"
        }
        return [pscustomobject]@{
            Success = $false
            Message = Get-AmdApiFailureMessage -Service Hudu -ErrorRecord $connectionError -HadEmbeddedWhitespace:$keyInfo.HasEmbeddedWhitespace
            Data    = $null
            BaseUrl = $normalized
        }
    }
}

function Test-AmdAxcientConnection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ApiKey)

    $keyInfo = ConvertTo-AmdNormalizedApiKey -Key $ApiKey
    if (-not $keyInfo.IsUsable) {
        $message = if ($keyInfo.IsEmpty) {
            'The Axcient API key is empty. Paste an active API key and try again.'
        }
        else {
            Get-AmdApiFailureMessage -Service Axcient -ErrorRecord ([System.Exception]::new('Invalid key format')) -HadEmbeddedWhitespace
        }
        return [pscustomobject]@{ Success = $false; Message = $message; Data = @() }
    }
    # Added rather than replaced, so a Hudu key registered earlier in the same
    # session stays redacted. See Test-AmdHuduConnection for why this sits between
    # the format check and the call.
    Set-AmdSensitiveValues -Values @($keyInfo.Value) -Add

    try {
        Initialize-AxcientAPI -ApiKey $keyInfo.Value -ErrorAction Stop
        $clients = @(Get-Client -ErrorAction Stop)
        return [pscustomobject]@{
            Success = $true
            Message = "Connected successfully to Axcient and found $($clients.Count) client(s)."
            Data    = $clients
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Message = Get-AmdApiFailureMessage -Service Axcient -ErrorRecord $_ -HadEmbeddedWhitespace:$keyInfo.HasEmbeddedWhitespace
            Data    = @()
        }
    }
}

function Get-AmdAxcientClientUsage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int64]$ClientId,
        [Parameter(Mandatory)][string]$ApiKey,
        [ValidateRange(2, 60)][int]$TimeoutSec = 30
    )

    if ($ClientId -le 0) { throw 'Axcient client usage requires a positive client ID.' }
    $keyInfo = ConvertTo-AmdNormalizedApiKey -Key $ApiKey
    if (-not $keyInfo.IsUsable) { throw 'Axcient client usage requires a usable API key.' }
    Set-AmdSensitiveValues -Values @($keyInfo.Value) -Add

    # This endpoint is documented by Axcient but is not wrapped by the pinned
    # AxcientAPI 0.4.0 module. Keep this narrow request read-only and refuse
    # redirects so the API key can never be forwarded to another host.
    $response = Invoke-WebRequest `
        -Uri "https://axapi.axcient.com/x360recover/client/$ClientId/usage" `
        -Method Get `
        -Headers @{ 'X-API-Key' = $keyInfo.Value; Accept = 'application/json' } `
        -UserAgent 'AXCIENT-MAGIC-DASH/2.4.0' `
        -TimeoutSec $TimeoutSec `
        -MaximumRedirection 0 `
        -SkipHttpErrorCheck `
        -ErrorAction Stop
    if ([int]$response.StatusCode -ne 200) {
        $httpResponse = [Net.Http.HttpResponseMessage]::new(
            [Net.HttpStatusCode][int]$response.StatusCode
        )
        $retryAfter = $response.Headers.'Retry-After'
        if ($retryAfter) {
            $null = $httpResponse.Headers.TryAddWithoutValidation('Retry-After', [string]$retryAfter)
        }
        throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
            "Axcient client usage returned HTTP $([int]$response.StatusCode).",
            $httpResponse
        )
    }
    try {
        return $response.Content | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    }
    catch {
        throw "Axcient client usage returned an invalid JSON response. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)"
    }
}

function Get-AmdAxcientClient {
    [CmdletBinding()]
    param()

    # AxcientAPI is deliberately imported into this module's verified session
    # state. Entry-point scripts must call this wrapper instead of trying to
    # resolve the vendor command from their separate script scope.
    return @(Get-Client -ErrorAction Stop)
}

function Connect-AmdServices {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    Set-AmdSensitiveValues -Values @([string]$Config.huduAPIKey, [string]$Config.axcientAPIKey)
    # An absent key otherwise reaches the vendor as an empty one and comes back as
    # 'the key was rejected', which points the operator at a revoked key rather than
    # a missing one. A hand-edited config.json is the way this state survives.
    foreach ($keyName in 'huduAPIKey', 'axcientAPIKey') {
        if ([string]::IsNullOrWhiteSpace([string]$Config.$keyName)) {
            throw "config.json has no '$keyName' value, so there is nothing to connect with. Run run.ps1 and paste the key."
        }
    }
    Connect-AmdHudu -InstanceUrl ([string]$Config.huduBaseUrl) -ApiKey ([string]$Config.huduAPIKey) -ErrorAction Stop
    Initialize-AxcientAPI -ApiKey $Config.axcientAPIKey -ErrorAction Stop
}
