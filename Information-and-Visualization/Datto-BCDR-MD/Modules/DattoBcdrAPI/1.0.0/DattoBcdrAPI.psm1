#Requires -Version 7.2
Set-StrictMode -Version Latest

<#
    Datto BCDR REST API client.

    This module replaces the vendored AxcientAPI module the Axcient build used.
    It exports the SAME command names and emits the SAME object shapes, so the
    rest of the application is unchanged: Get-Client, $client | Get-Device and
    $client | Get-Appliance behave exactly as they did, and only what is behind
    them is Datto instead of Axcient.

    The vocabularies are not the same on both sides, so the translation is:

        Datto client   (organisation)      -> Client
        Datto asset    (protected machine) -> Device
        Datto device   (BCDR appliance)    -> Appliance

    That is deliberate. Axcient's "device" is a protected machine and its
    "appliance" is the hardware; Datto uses "device" for the hardware and
    "asset" for the protected machine. Mapping by MEANING rather than by name
    keeps every downstream health, staleness and storage calculation correct.

    Endpoints used are only the ones confirmed against the live API in
    Datto_BCDR_API_Reference.txt. Nothing here guesses at an undocumented path.
#>

$script:DattoBcdrBaseUrl = 'https://api.datto.com/v1'
$script:DattoBcdrUserAgent = 'DATTO-BCDR-MAGIC-DASH/1.0.0'
$script:DattoBcdrCredential = $null
$script:DattoBcdrTimeoutSec = 60

# Page size for the paginated envelope endpoints. The API defaults to 100 and
# VM restores to 25; asking for more than an endpoint allows is ignored rather
# than rejected, so one number is safe for all of them.
$script:DattoBcdrPageSize = 100

# The per-run cache. /bcdr/device is the partner-wide call whose answer every
# client and appliance lookup is derived from; without this, a
# sync of 200 companies would re-read the entire partner account 200 times.
$script:DattoBcdrCache = $null

function Initialize-DattoBcdrAPI {
    <#
    .SYNOPSIS
        Registers the Datto REST API credentials for this session.

    .DESCRIPTION
        Datto authenticates with HTTP Basic auth: the public key is the
        username and the private key is the password. Both are required.

        -ApiKey accepts the two joined as "public:private" so callers that
        carry a single opaque key string keep working.

    .PARAMETER PublicKey
        The Datto REST API public key.

    .PARAMETER PrivateKey
        The Datto REST API private key.

    .PARAMETER ApiKey
        Both keys as one "public:private" string.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pair')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Pair')]
        [string]$PublicKey,

        [Parameter(Mandatory, ParameterSetName = 'Pair')]
        [string]$PrivateKey,

        [Parameter(Mandatory, ParameterSetName = 'Combined')]
        [string]$ApiKey,

        [ValidateRange(5, 300)]
        [int]$TimeoutSec = 60
    )

    if ($PSCmdlet.ParameterSetName -eq 'Combined') {
        $parts = ([string]$ApiKey).Split(':', 2)
        if ($parts.Count -ne 2) {
            throw 'The Datto API key must be supplied as "publicKey:privateKey", or as separate -PublicKey and -PrivateKey values. Datto uses Basic auth and needs both halves.'
        }
        $PublicKey = $parts[0]
        $PrivateKey = $parts[1]
    }

    $PublicKey = ([string]$PublicKey).Trim()
    $PrivateKey = ([string]$PrivateKey).Trim()
    if ([string]::IsNullOrWhiteSpace($PublicKey)) { throw 'The Datto REST API public key is empty.' }
    if ([string]::IsNullOrWhiteSpace($PrivateKey)) { throw 'The Datto REST API private key is empty.' }

    $script:DattoBcdrCredential = [pscredential]::new(
        $PublicKey,
        (ConvertTo-SecureString -String $PrivateKey -AsPlainText -Force)
    )
    $script:DattoBcdrTimeoutSec = $TimeoutSec
    # Credentials changing means the cached partner data belongs to a different
    # account. Keeping it would silently show one partner's devices under
    # another partner's key.
    $script:DattoBcdrCache = $null
}

function Clear-DattoBcdrCache {
    <#
    .SYNOPSIS
        Drops the cached partner-wide reads so the next call refetches.
    #>
    [CmdletBinding()]
    param()
    $script:DattoBcdrCache = $null
}

function Assert-DattoBcdrInitialized {
    if ($null -eq $script:DattoBcdrCredential) {
        throw 'The Datto API is not initialised. Call Initialize-DattoBcdrAPI with the public and private keys first.'
    }
}

function Invoke-DattoBcdrAPI {
    <#
    .SYNOPSIS
        One GET against the Datto REST API, with paging where the endpoint pages.

    .DESCRIPTION
        Datto returns a few different shapes and the caller should not have to
        care which: most list endpoints return { pagination, items } and some
        asset endpoints return a plain array. All of them come back here as a
        flat array of records.

        Failures are raised as HttpResponseException so the application's
        existing retry and rate-limit handling recognises them; it inspects the
        status code and the Retry-After header and neither survives being
        flattened into a plain string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [switch]$Raw,
        [ValidateSet('items', 'clients', 'data', 'auto')]
        [string]$ResultProperty = 'items',
        [ValidateRange(1, 500)][int]$MaxPages = 200,
        [switch]$AllowPartialResult
    )

    Assert-DattoBcdrInitialized

    $relative = ([string]$Endpoint).TrimStart('/')
    $results = [System.Collections.Generic.List[object]]::new()
    $page = 1

    while ($true) {
        $uri = if ($Raw) {
            "$script:DattoBcdrBaseUrl/$relative"
        }
        else {
            $separator = if ($relative.Contains('?')) { '&' } else { '?' }
            "$script:DattoBcdrBaseUrl/$relative$separator" + "page=$page&perPage=$script:DattoBcdrPageSize"
        }

        $response = Invoke-WebRequest `
            -Uri $uri `
            -Method Get `
            -Authentication Basic `
            -Credential $script:DattoBcdrCredential `
            -Headers @{ Accept = 'application/json' } `
            -UserAgent $script:DattoBcdrUserAgent `
            -TimeoutSec $script:DattoBcdrTimeoutSec `
            -MaximumRedirection 0 `
            -SkipHttpErrorCheck `
            -ErrorAction Stop

        if ([int]$response.StatusCode -ne 200) {
            throw (New-DattoBcdrHttpException -Response $response -Endpoint $relative)
        }

        try {
            $payload = $response.Content | ConvertFrom-Json -Depth 20 -ErrorAction Stop
        }
        catch {
            throw "Datto returned a response for '$relative' that is not valid JSON. $($_.Exception.Message)"
        }

        if ($Raw) { return $payload }

        # Plain array (agents, shares) versus the paginated envelope.
        if ($payload -is [System.Array]) {
            foreach ($item in $payload) { $results.Add($item) }
            break
        }
        if ($null -eq $payload) { break }

        $properties = @($payload.PSObject.Properties.Name)
        $collectionProperty = $null
        if ($ResultProperty -ne 'auto' -and $properties -contains $ResultProperty) {
            $collectionProperty = $ResultProperty
        }
        elseif ($ResultProperty -eq 'auto') {
            foreach ($candidate in @('items', 'clients', 'data')) {
                if ($properties -contains $candidate) {
                    $collectionProperty = $candidate
                    break
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($collectionProperty)) {
            # A single object, or an envelope this code has not seen. Either way
            # it is one record, not a page of them.
            $results.Add($payload)
            break
        }

        foreach ($item in @($payload.$collectionProperty)) { $results.Add($item) }

        $totalPages = 1
        if ($properties -contains 'pagination' -and $null -ne $payload.pagination) {
            $paginationProperties = @($payload.pagination.PSObject.Properties.Name)
            if ($paginationProperties -contains 'totalPages') {
                $parsed = 0
                if (-not [int]::TryParse(
                        [string]$payload.pagination.totalPages,
                        [Globalization.NumberStyles]::None,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$parsed
                    ) -or $parsed -lt 1) {
                    throw "Datto returned invalid pagination.totalPages metadata for '$relative'. No partial inventory was accepted."
                }
                $totalPages = $parsed
            }
        }
        if ($totalPages -gt $MaxPages -and -not $AllowPartialResult) {
            throw "Datto reports $totalPages pages for '$relative', exceeding the $MaxPages-page safety limit. No partial inventory was accepted."
        }
        if ($page -ge $totalPages -or $page -ge $MaxPages) { break }
        $page++
    }

    return $results.ToArray()
}

function New-DattoBcdrHttpException {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$Endpoint
    )

    $statusCode = [int]$Response.StatusCode
    $httpResponse = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$statusCode)
    # Retry-After is the whole reason this is an HttpResponseException and not a
    # string: the caller's backoff reads it off the response.
    # This module runs under Set-StrictMode -Version Latest, where reading a
    # header that is not present is a terminating PropertyNotFound error. Because
    # that happened inside the error path, EVERY failed call surfaced as "the
    # property 'Retry-After' cannot be found on this object" and buried the
    # 401/403/404/429 hints below - including the 401 hint about creating the key
    # with the vendor dropdown left blank, which is the most common setup mistake.
    $retryAfter = $null
    $headers = $Response.Headers
    if ($null -ne $headers) {
        try {
            if ($headers.ContainsKey('Retry-After')) {
                $retryAfter = @($headers['Retry-After']) | Select-Object -First 1
            }
        }
        catch {
            # A header collection without ContainsKey is not worth failing the
            # error path over. The status code is the part the caller needs.
            $retryAfter = $null
        }
    }
    if ($retryAfter) {
        $null = $httpResponse.Headers.TryAddWithoutValidation('Retry-After', [string]$retryAfter)
    }
    $hint = switch ($statusCode) {
        401 { ' The public/private key pair was rejected. Check both halves, and that the key was created with the vendor/organisation dropdown left BLANK.' }
        403 { ' The key authenticated but is not allowed to read this. A key scoped to one organisation cannot read partner-wide endpoints.' }
        404 { ' That path does not exist on the Datto API.' }
        429 { ' Datto is rate limiting this key.' }
        default { '' }
    }
    return [Microsoft.PowerShell.Commands.HttpResponseException]::new(
        "Datto API GET /$Endpoint returned HTTP $statusCode.$hint",
        $httpResponse
    )
}

function Get-DattoBcdrPartnerData {
    <#
    .SYNOPSIS
        Reads and caches the two partner-wide lists everything else derives from.

    .DESCRIPTION
        /bcdr/device is the confirmed list of appliances and carries Datto's
        organizationId / organizationName client fields. It is read once per run
        and shared.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $script:DattoBcdrCache) { return $script:DattoBcdrCache }
    Assert-DattoBcdrInitialized

    $appliances = @(Invoke-DattoBcdrAPI -Endpoint 'bcdr/device')

    $clients = @(ConvertFrom-DattoBcdrDeviceClients -Devices $appliances)

    $applianceBySerial = @{}
    $ownerBySerial = @{}
    foreach ($appliance in $appliances) {
        $serial = ([string](Get-DattoBcdrProperty -Object $appliance -Names @('serialNumber', 'serial_number', 'serial'))).Trim()
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }

        $owner = ([string](Get-DattoBcdrProperty -Object $appliance -Names @('organizationId', 'organizationID', 'organization_id') -Default '0')).Trim()
        if ([string]::IsNullOrWhiteSpace($owner)) { $owner = '0' }
        if ($owner -ne '0') {
            if ($ownerBySerial.ContainsKey($serial) -and $ownerBySerial[$serial] -ne $owner) {
                throw "Datto appliance serial '$serial' is assigned to multiple organizations ('$($ownerBySerial[$serial])' and '$owner'). No client data was accepted."
            }
            $ownerBySerial[$serial] = $owner
        }

        if (-not $applianceBySerial.ContainsKey($serial)) {
            $applianceBySerial[$serial] = $appliance
            continue
        }

        $existingOwner = ([string](Get-DattoBcdrProperty -Object $applianceBySerial[$serial] -Names @('organizationId', 'organizationID', 'organization_id') -Default '0')).Trim()
        if (($existingOwner -eq '0' -or [string]::IsNullOrWhiteSpace($existingOwner)) -and $owner -ne '0') {
            $applianceBySerial[$serial] = $appliance
        }
    }

    $script:DattoBcdrCache = [pscustomobject]@{
        Clients           = $clients
        Appliances        = $appliances
        ApplianceBySerial = $applianceBySerial
        AssetCache        = @{}
        DetailCache       = @{}
        AlertCache        = @{}
        RestoreCache      = @{}
    }
    return $script:DattoBcdrCache
}

function Get-DattoBcdrProperty {
    <#
        Reads the first property that exists out of several candidate names.

        Datto uses several spellings for the same concepts across endpoints, so
        fields are probed rather than assumed. Guessing one name and silently
        producing empty clients would look like "the partner has no customers".
    #>
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string[]]$Names,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $available = @($Object.PSObject.Properties.Name)
    foreach ($name in $Names) {
        if ($available -contains $name) {
            $value = $Object.$name
            if ($null -ne $value) { return $value }
        }
    }
    return $Default
}

function ConvertFrom-DattoBcdrClientPayload {
    <#
        Legacy compatibility helper for older /bcdr/agent-shaped fixtures.

        Shape is probed, not assumed - see Get-DattoBcdrProperty. If the payload
        carries no recognisable client collection the error names the properties
        that WERE present, because the alternative is a run that reports zero
        customers and looks like a matching problem instead of a shape problem.
    #>
    param([AllowNull()]$Payload)

    if ($null -eq $Payload) { return @() }

    $clientRecords = $null
    if ($Payload -is [System.Array]) {
        $clientRecords = @($Payload)
    }
    else {
        $clientRecords = Get-DattoBcdrProperty -Object $Payload -Names @('clients', 'items', 'data')
        if ($null -eq $clientRecords) {
            $seen = @($Payload.PSObject.Properties.Name) -join ', '
            throw "The Datto /bcdr/agent response carries no 'clients' collection. Properties returned: $seen. The Magic Dash matches Datto clients to Hudu companies, so it cannot continue without them."
        }
    }

    foreach ($record in @($clientRecords)) {
        $name = [string](Get-DattoBcdrProperty -Object $record -Names @('name', 'clientName', 'companyName', 'client_name') -Default '')
        $nativeId = Get-DattoBcdrProperty -Object $record -Names @('id', 'clientId', 'clientID', 'client_id', 'uuid') -Default $null
        $agents = @(Get-DattoBcdrProperty -Object $record -Names @('agents', 'assets', 'devices') -Default @())

        [pscustomobject]@{
            # Numeric by contract: saved company matches are keyed on this value
            # and the application casts it to [int64]. See ConvertTo-DattoBcdrNumericId.
            id           = ConvertTo-DattoBcdrNumericId -Value $nativeId -Fallback $name
            client_uid   = if ($null -ne $nativeId) { [string]$nativeId } else { '' }
            name         = $name
            objectschema = 'client'
            agents       = $agents
            Source       = $record
        }
    }
}

function ConvertFrom-DattoBcdrDeviceClients {
    <#
        Builds Datto client objects from /bcdr/device records.

        Datto BCDR exposes client identity on device records rather than through
        a dedicated clients endpoint. organizationId 0 is unassigned, and devices
        with agentCount 0 are not syncable client members.
    #>
    param([AllowNull()][object[]]$Devices)

    if ($null -eq $Devices) { return @() }

    $byOrganizationId = [ordered]@{}
    foreach ($device in @($Devices)) {
        $organizationId = Get-DattoBcdrProperty -Object $device -Names @('organizationId', 'organizationID', 'organization_id') -Default $null
        $organizationIdText = ([string]$organizationId).Trim()
        if ([string]::IsNullOrWhiteSpace($organizationIdText) -or $organizationIdText -eq '0') { continue }

        $name = ''
        $recordNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $availableProperties = @($device.PSObject.Properties.Name)
        foreach ($nameProperty in @('organizationName', 'clientCompanyName', 'organization_name', 'client_company_name')) {
            if ($availableProperties -contains $nameProperty) {
                $candidateName = ([string]$device.$nameProperty).Trim()
                if (-not [string]::IsNullOrWhiteSpace($candidateName)) {
                    if ([string]::IsNullOrWhiteSpace($name)) { $name = $candidateName }
                    $null = $recordNames.Add($candidateName)
                }
            }
        }
        if ($recordNames.Count -gt 1) {
            throw "Datto organization ID '$organizationIdText' has conflicting name fields ('$(@($recordNames) -join "' and '")'). No client mapping was accepted."
        }

        if (-not $byOrganizationId.Contains($organizationIdText)) {
            $byOrganizationId[$organizationIdText] = [pscustomobject]@{
                id           = ConvertTo-DattoBcdrNumericId -Value $organizationIdText -Fallback $name
                client_uid   = $organizationIdText
                name         = $name
                objectschema = 'client'
                agents       = [System.Collections.Generic.List[object]]::new()
                agentSerials = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                Source       = [System.Collections.Generic.List[object]]::new()
            }
        }

        $client = $byOrganizationId[$organizationIdText]
        if ([string]::IsNullOrWhiteSpace([string]$client.name) -and -not [string]::IsNullOrWhiteSpace($name)) {
            $client.name = $name
        }
        elseif (-not [string]::IsNullOrWhiteSpace($name) -and
            -not [string]::Equals([string]$client.name, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Datto organization ID '$organizationIdText' has conflicting names ('$($client.name)' and '$name'). No client mapping was accepted."
        }
        $null = $client.Source.Add($device)

        $agentCount = Get-DattoBcdrProperty -Object $device -Names @('agentCount', 'agent_count') -Default $null
        $parsedAgentCount = 0
        if ($null -eq $agentCount -or
            -not [int]::TryParse([string]$agentCount, [ref]$parsedAgentCount) -or
            $parsedAgentCount -le 0) {
            continue
        }

        $serial = [string](Get-DattoBcdrProperty -Object $device -Names @('serialNumber', 'serial_number', 'serial') -Default '')
        if (-not [string]::IsNullOrWhiteSpace($serial) -and $client.agentSerials.Add($serial)) {
            $null = $client.agents.Add([pscustomobject]@{
                    serialNumber = $serial
                    agentCount   = $agentCount
                    Source       = $device
                })
        }
    }

    foreach ($client in $byOrganizationId.Values) {
        [pscustomobject]@{
            id           = $client.id
            client_uid   = $client.client_uid
            name         = $client.name
            objectschema = $client.objectschema
            agents       = @($client.agents)
            Source       = @($client.Source)
        }
    }
}

function ConvertTo-DattoBcdrNumericId {
    <#
        A stable positive [int64] for a client.

        Datto client identifiers may be integers or UUIDs depending on the
        account, and the application stores saved Hudu-to-Datto matches keyed on
        a numeric id. A UUID would fail the [int64] cast and take every saved
        match with it, so a non-numeric id is folded into an int64 by hashing.

        The hash is of the native id, so it is stable for as long as Datto keeps
        that id stable - which is exactly the property saved matches need. The
        native value is kept alongside as client_uid.
    #>
    param(
        [AllowNull()]$Value,
        [string]$Fallback = ''
    )

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { $text = $Fallback }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'A Datto client arrived with neither an id nor a name, so it cannot be matched to a Hudu company or saved.'
    }

    $parsed = [int64]0
    if ([int64]::TryParse($text, [ref]$parsed) -and $parsed -gt 0) { return $parsed }

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
        # Top bit cleared so the result is always positive; 8 bytes is far more
        # than enough to keep partner-sized client lists collision-free.
        $bytes[0] = [byte]($bytes[0] -band 0x7F)
        return [BitConverter]::ToInt64($bytes, 0) -band 0x7FFFFFFFFFFFFFFF
    }
    finally {
        $sha.Dispose()
    }
}

function Get-DattoBcdrClientSerials {
    <#
        The appliance serial numbers a client's machines live on.

        Every confirmed asset endpoint is keyed by appliance serial, so this is
        how a client turns into something that can actually be queried.
    #>
    param([Parameter(Mandatory)]$Client)

    $serials = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($agent in @(Get-DattoBcdrProperty -Object $Client -Names @('agents') -Default @())) {
        $serial = [string](Get-DattoBcdrProperty -Object $agent -Names @(
                'serialNumber', 'deviceSerialNumber', 'serial_number', 'device_serial_number', 'serial'
            ) -Default '')
        if (-not [string]::IsNullOrWhiteSpace($serial)) { $null = $serials.Add($serial) }
    }
    return @($serials)
}

function Get-DattoBcdrApplianceAssets {
    <#
        All assets on one appliance, cached per serial for the run.
    #>
    param([Parameter(Mandatory)][string]$SerialNumber)

    $cache = Get-DattoBcdrPartnerData
    if ($cache.AssetCache.ContainsKey($SerialNumber)) { return $cache.AssetCache[$SerialNumber] }

    $assets = @()
    try {
        $assets = @(Invoke-DattoBcdrAPI -Endpoint "bcdr/device/$SerialNumber/asset")
    }
    catch {
        # One unreachable appliance must not take the whole client's dashboard
        # down: the caller records the gap and the other appliances still render.
        $cache.AssetCache[$SerialNumber] = @()
        throw
    }
    $cache.AssetCache[$SerialNumber] = $assets
    return $assets
}

function Get-DattoBcdrApplianceAgent {
    <#
        Agent-type assets on one appliance.

        The path is /asset/agent, not /agent - the bare path is a confirmed 404.
    #>
    param([Parameter(Mandatory)][string]$SerialNumber)
    return @(Invoke-DattoBcdrAPI -Endpoint "bcdr/device/$SerialNumber/asset/agent")
}

function Get-DattoBcdrApplianceShare {
    <#
        Share-type assets on one appliance.

        The path is /asset/share, not /share - the bare path is a confirmed 404.
    #>
    param([Parameter(Mandatory)][string]$SerialNumber)
    return @(Invoke-DattoBcdrAPI -Endpoint "bcdr/device/$SerialNumber/asset/share")
}

function Get-DattoBcdrAssetIdentityKey {
    param([Parameter(Mandatory)]$Asset)

    $id = ([string](Get-DattoBcdrProperty -Object $Asset -Names @('assetId', 'id') -Default '')).Trim()
    if (-not [string]::IsNullOrWhiteSpace($id)) { return "id::$id" }

    $name = ([string](Get-DattoBcdrProperty -Object $Asset -Names @('name') -Default '')).Trim()
    $volume = ([string](Get-DattoBcdrProperty -Object $Asset -Names @('volumeName', 'volume', 'volumeHash') -Default '')).Trim()
    $address = ([string](Get-DattoBcdrProperty -Object $Asset -Names @('localIp', 'local_ip') -Default '')).Trim()
    if (-not [string]::IsNullOrWhiteSpace($name) -or
        -not [string]::IsNullOrWhiteSpace($volume) -or
        -not [string]::IsNullOrWhiteSpace($address)) {
        return "fields::$name::$volume::$address"
    }

    throw 'Datto returned an asset without an ID, name, volume, or address, so duplicate-safe fallback processing is impossible.'
}

function Get-DattoBcdrApplianceTypedAssets {
    <#
        Every asset on an appliance, each tagged with the kind it came back as.

        /asset returns agents and shares mixed together with nothing on the
        record to tell them apart, so the two typed endpoints are read instead
        and the kind is taken from which one answered. If either typed endpoint
        fails, the mixed list is used as a fallback so a share outage cannot
        hide the agents.
    #>
    param([Parameter(Mandatory)][string]$SerialNumber)

    $cache = Get-DattoBcdrPartnerData
    $cacheKey = "typed::$SerialNumber"
    if ($cache.AssetCache.ContainsKey($cacheKey)) { return $cache.AssetCache[$cacheKey] }

    $typed = [System.Collections.Generic.List[object]]::new()
    $agentsFailed = $false
    try {
        foreach ($agent in (Get-DattoBcdrApplianceAgent -SerialNumber $SerialNumber)) {
            $typed.Add([pscustomobject]@{ Asset = $agent; Kind = 'Agent' })
        }
    }
    catch { $agentsFailed = $true }

    $sharesFailed = $false
    try {
        foreach ($share in (Get-DattoBcdrApplianceShare -SerialNumber $SerialNumber)) {
            $typed.Add([pscustomobject]@{ Asset = $share; Kind = 'Share' })
        }
    }
    catch { $sharesFailed = $true }

    if ($agentsFailed -or $sharesFailed) {
        # A typed endpoint outage must not turn the surviving endpoint into a
        # successful partial fleet. Use the mixed endpoint to fill only the
        # missing records while retaining the type of records already identified.
        $knownAssets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $typed) {
            $null = $knownAssets.Add((Get-DattoBcdrAssetIdentityKey -Asset $item.Asset))
        }
        $fallbackKind = if ($agentsFailed -and -not $sharesFailed) {
            'Agent'
        }
        elseif ($sharesFailed -and -not $agentsFailed) {
            'Share'
        }
        else {
            'Unknown'
        }
        foreach ($asset in (Get-DattoBcdrApplianceAssets -SerialNumber $SerialNumber)) {
            if ($knownAssets.Add((Get-DattoBcdrAssetIdentityKey -Asset $asset))) {
                $typed.Add([pscustomobject]@{ Asset = $asset; Kind = $fallbackKind })
            }
        }
    }

    $result = $typed.ToArray()
    $cache.AssetCache[$cacheKey] = $result
    return $result
}

function Get-DattoBcdrVmRestore {
    <#
        VM restore jobs for one appliance.

        The path is /vm-restores with a hyphen; /vmRestore is a confirmed 404.
        An empty items array means no active restores and is not an error.
    #>
    param([Parameter(Mandatory)][string]$SerialNumber)

    $cache = Get-DattoBcdrPartnerData
    if ($cache.RestoreCache.ContainsKey($SerialNumber)) { return $cache.RestoreCache[$SerialNumber] }

    # The failure is NOT caught here. Swallowing it and returning $null meant the
    # caller's Invoke-DbmWithRetry wrapper never saw a throw, so a transient 429
    # could never be retried and was cached as "unreadable" for the whole run -
    # and the reason was discarded, leaving the operator a bare "unavailable".
    # The caller already turns a throw into an unavailable panel WITH the reason.
    $restores = @(Invoke-DattoBcdrAPI -Endpoint "bcdr/device/$SerialNumber/vm-restores")

    $normalised = @(foreach ($restore in $restores) {
            [pscustomobject]@{
                appliance_serial = $SerialNumber
                asset_name       = [string](Get-DattoBcdrProperty -Object $restore -Names @('name', 'assetName', 'agentName', 'hostname') -Default '')
                volume           = [string](Get-DattoBcdrProperty -Object $restore -Names @('volume', 'volumeName') -Default '')
                type             = [string](Get-DattoBcdrProperty -Object $restore -Names @('type', 'restoreType') -Default '')
                status           = [string](Get-DattoBcdrProperty -Object $restore -Names @('status', 'state') -Default '')
                started          = ConvertTo-DattoBcdrUtcString (Get-DattoBcdrProperty -Object $restore -Names @('startTime', 'started', 'createdAt', 'creationTime') -Default $null)
                snapshot         = ConvertTo-DattoBcdrUtcString (Get-DattoBcdrProperty -Object $restore -Names @('snapshot', 'snapshotEpoch', 'point') -Default $null)
                Source           = $restore
            }
        })
    $cache.RestoreCache[$SerialNumber] = $normalised
    return $normalised
}

function Get-DattoBcdrDtcAssetCount {
    <#
        How many Direct-to-Cloud assets exist on the partner account, or -1 when
        that cannot be read.

        DTC is a separate inventory from /bcdr, so a DTC-protected machine appears
        in NEITHER the appliance list nor any appliance's asset list. Without this
        check such a machine is simply absent from the dashboard, and absent reads
        as "this client has no other machines" rather than as a gap.

        This deliberately reports a COUNT and nothing more. The account this was
        built against has zero DTC assets, so the per-asset record shape has never
        been observed; writing a mapper against a guessed shape is what produced
        the alert-record bug. The count is enough to say "N machines are not shown
        here", which is the honest answer until a real payload can be sampled.

        -Raw because /dtc/assets rejects page and perPage with HTTP 400
        "Unknown filter fields", unlike every /bcdr list endpoint.
    #>
    [CmdletBinding()]
    param()

    Assert-DattoBcdrInitialized
    try {
        $payload = Invoke-DattoBcdrAPI -Endpoint 'dtc/assets' -Raw
    }
    catch {
        return -1
    }
    if ($null -eq $payload) { return -1 }
    if ($payload -is [System.Array]) { return @($payload).Count }

    $properties = @($payload.PSObject.Properties.Name)
    if ($properties -contains 'items') { return @($payload.items).Count }
    if ($properties -contains 'pagination') {
        $count = Get-DattoBcdrProperty -Object $payload.pagination -Names @('count') -Default $null
        $parsed = 0
        if ($null -ne $count -and [int]::TryParse([string]$count, [ref]$parsed) -and $parsed -ge 0) { return $parsed }
    }
    return -1
}
function Get-DattoBcdrApplianceDetail {
    param([Parameter(Mandatory)][string]$SerialNumber)

    $cache = Get-DattoBcdrPartnerData
    if ($cache.DetailCache.ContainsKey($SerialNumber)) { return $cache.DetailCache[$SerialNumber] }
    $detail = $null
    try {
        $detail = @(Invoke-DattoBcdrAPI -Endpoint "bcdr/device/$SerialNumber") | Select-Object -First 1
    }
    catch {
        $detail = $null
    }
    $cache.DetailCache[$SerialNumber] = $detail
    return $detail
}

function ConvertTo-DattoBcdrAlertRuleName {
    <#
        'DeviceNotSeenAlert' -> 'Device Not Seen'. Datto sends the rule type as a
        single PascalCase token; showing it raw makes a readable dashboard read
        like a debug dump.
    #>
    param([AllowNull()][string]$Type)

    if ([string]::IsNullOrWhiteSpace($Type)) { return 'Alert rule' }
    $spaced = [regex]::Replace($Type.Trim(), '(?<=[a-z0-9])(?=[A-Z])', ' ')
    $spaced = [regex]::Replace($spaced, '\s+Alert$', '')
    if ([string]::IsNullOrWhiteSpace($spaced)) { return 'Alert rule' }
    return $spaced
}

function Get-DattoBcdrAlertRule {
    <#
        The alert RULES configured on one appliance, normalised.

        /bcdr/device/{serial}/alert does not return firing alerts. Sampled live
        across a whole partner account, every record has exactly these five
        fields and no others:

            type            'DeviceNotSeenAlert'
            threshold       60
            unit            'Minutes'
            dateTriggered   when this rule last fired
            dateSent        when its last notification went out

        There is no message, no severity, and - decisively - no asset or volume
        on the record, so a rule cannot be attributed to a protected machine.
        The count of firing alerts comes from alertCount on the appliance record
        instead; see Get-DattoBcdrApplianceAlertCount.

        An empty items array is the documented "nothing configured" answer, not a
        failure. A read that FAILS throws, so the caller can retry it and then
        say the rules could not be read - and why - rather than showing a
        reassuring "none".
    #>
    param([Parameter(Mandatory)][string]$SerialNumber)

    $cache = Get-DattoBcdrPartnerData
    if ($cache.AlertCache.ContainsKey($SerialNumber)) { return $cache.AlertCache[$SerialNumber] }

    # Not caught here, for the same reason as Get-DattoBcdrVmRestore: swallowing
    # the error defeated the caller's retry wrapper and hid why the read failed.
    $rules = @(Invoke-DattoBcdrAPI -Endpoint "bcdr/device/$SerialNumber/alert")

    $normalised = @(foreach ($rule in $rules) {
            $type = [string](Get-DattoBcdrProperty -Object $rule -Names @('type') -Default '')
            $threshold = Get-DattoBcdrProperty -Object $rule -Names @('threshold') -Default $null
            $unit = [string](Get-DattoBcdrProperty -Object $rule -Names @('unit') -Default '')
            $name = ConvertTo-DattoBcdrAlertRuleName -Type $type
            # A threshold of 0 with no unit is Datto's "this rule has no numeric
            # threshold" form, so rendering 'threshold 0' would invent a limit.
            $parsedThreshold = 0
            $hasThreshold = $null -ne $threshold -and
                [int]::TryParse([string]$threshold, [ref]$parsedThreshold) -and
                $parsedThreshold -gt 0
            $description = if ($hasThreshold -and -not [string]::IsNullOrWhiteSpace($unit)) {
                "$name after $parsedThreshold $($unit.ToLowerInvariant())"
            }
            elseif ($hasThreshold) { "$name after $parsedThreshold" }
            else { $name }

            [pscustomobject]@{
                appliance_serial = $SerialNumber
                type             = $type
                name             = $name
                threshold        = if ($hasThreshold) { $parsedThreshold } else { $null }
                unit             = $unit
                description      = $description
                last_triggered   = ConvertTo-DattoBcdrUtcString $(Get-DattoBcdrProperty -Object $rule -Names @('dateTriggered') -Default $null)
                last_sent        = ConvertTo-DattoBcdrUtcString $(Get-DattoBcdrProperty -Object $rule -Names @('dateSent') -Default $null)
                Source           = $rule
            }
        })
    $cache.AlertCache[$SerialNumber] = $normalised
    return $normalised
}
function Get-DattoBcdrApplianceAlertCount {
    <#
        How many alerts Datto currently reports as firing on one appliance, or
        -1 when that is unknown.

        This reads alertCount off the appliance's own /bcdr/device record. It
        deliberately does NOT count /bcdr/device/{serial}/alert, because that
        endpoint returns the appliance's configured alert RULES - type, threshold,
        unit, and when each last triggered - not the alerts firing right now.

        Counting rules marked healthy appliances as unhealthy. Verified against
        the live partner account: every appliance reported alertCount 0 while
        holding one to three rules, including appliances last seen minutes
        earlier that still listed a 60-minute "Device Not Seen" rule whose last
        trigger was months in the past.

        -1 rather than 0: an appliance whose count cannot be read has not been
        shown to be healthy.
    #>
    param([Parameter(Mandatory)][string]$SerialNumber)

    $cache = Get-DattoBcdrPartnerData
    if (-not $cache.ApplianceBySerial.ContainsKey($SerialNumber)) { return -1 }
    $value = Get-DattoBcdrProperty -Object $cache.ApplianceBySerial[$SerialNumber] -Names @('alertCount') -Default $null
    if ($null -eq $value) { return -1 }
    $parsed = 0
    if (-not [int]::TryParse([string]$value, [ref]$parsed)) { return -1 }
    if ($parsed -lt 0) { return -1 }
    return $parsed
}

function ConvertTo-DattoBcdrUtcString {
    <#
        Datto timestamps arrive as unix seconds (lastSnapshot) or as ISO strings
        (latestOffsite). The application parses recovery points as date strings,
        so both are normalised to ISO 8601 here rather than in the UI layer.
    #>
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o') }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $seconds = [int64]0
    if ([int64]::TryParse($text, [ref]$seconds)) {
        if ($seconds -le 0) { return $null }
        return [DateTimeOffset]::FromUnixTimeSeconds($seconds).UtcDateTime.ToString('o')
    }

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($text, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.ToString('o')
    }
    return $null
}

function ConvertTo-DattoBcdrDevice {
    <#
        One Datto asset as the Device shape the application already renders.

        Health is derived rather than reported: Datto has no single status field
        on an asset, so the states that actually mean "this machine is not being
        protected right now" are mapped to a non-NORMAL status, and everything
        else to NORMAL. 'NORMAL' is the exact string the badge treats as healthy.
    #>
    param(
        [Parameter(Mandatory)]$Asset,
        [Parameter(Mandatory)][string]$SerialNumber,
        [string]$AssetType = 'Agent',
        # Datto returns a real per-appliance portal URL (remoteWebUrl) on the
        # appliance record. Callers that have that record pass it through so a
        # device row links to the appliance protecting it instead of a generic
        # login page. It is passed in, never built from a guessed URL pattern.
        [AllowNull()][string]$ApplianceUrl = ''
    )

    $isPaused = [bool](Get-DattoBcdrProperty -Object $Asset -Names @('isPaused') -Default $false)
    $isArchived = [bool](Get-DattoBcdrProperty -Object $Asset -Names @('isArchived') -Default $false)
    $lastSnapshot = ConvertTo-DattoBcdrUtcString (Get-DattoBcdrProperty -Object $Asset -Names @('lastSnapshot') -Default $null)
    $latestOffsite = ConvertTo-DattoBcdrUtcString (Get-DattoBcdrProperty -Object $Asset -Names @('latestOffsite') -Default $null)

    $status = 'NORMAL'
    $reason = ''
    if ($isArchived) {
        $status = 'ARCHIVED'
        $reason = 'The asset is archived on the appliance and is no longer being backed up.'
    }
    elseif ($isPaused) {
        $status = 'PAUSED'
        $reason = 'Backups are paused for this asset on the appliance.'
    }
    elseif ($null -eq $lastSnapshot) {
        $status = 'NO BACKUP'
        $reason = 'The appliance reports no completed local snapshot for this asset.'
    }

    $osName = [string](Get-DattoBcdrProperty -Object $Asset -Names @('os') -Default '')
    $protectedVolumes = @(Get-DattoBcdrProperty -Object $Asset -Names @('protectedVolumeNames') -Default @())
    $unprotectedVolumes = @(Get-DattoBcdrProperty -Object $Asset -Names @('unprotectedVolumeNames') -Default @())

    # Type decides which dashboard panel the row lands in, so it has to stay in
    # the SERVER / WORKSTATION vocabulary the panels are built around. Datto does
    # not report that distinction, but its os string does: "Windows Server 2012R2"
    # is a server, "Windows 10 Pro" is not. A share has no OS and is its own kind.
    $type = if ($AssetType -eq 'Share') {
        'SHARE'
    }
    elseif ($osName -match '(?i)\bserver\b') {
        'SERVER'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($osName)) {
        'WORKSTATION'
    }
    else {
        'UNKNOWN'
    }

    [pscustomobject]@{
        id                      = Get-DattoBcdrProperty -Object $Asset -Names @('assetId', 'id') -Default $null
        name                    = [string](Get-DattoBcdrProperty -Object $Asset -Names @('name') -Default '')
        type                    = $type
        objectschema            = 'device'
        d2c                     = $false
        os                      = [pscustomobject]@{
            os_name = $osName
            os_type = ''
            bits    = $null
        }
        ip_address              = [string](Get-DattoBcdrProperty -Object $Asset -Names @('localIp', 'local_ip') -Default '')
        agent_version           = [string](Get-DattoBcdrProperty -Object $Asset -Names @('agentVersion') -Default '')
        current_health_status   = [pscustomobject]@{ status = $status; reason = $reason }
        latest_local_rp         = $lastSnapshot
        latest_cloud_rp         = $latestOffsite
        # Datto has no local-cache concept. Leaving 'enabled' off the object is
        # what tells the application that applicability is unknown, rather than
        # claiming a cache is switched off.
        local_cache_details     = [pscustomobject]@{}
        # Datto returns a real per-appliance portal URL on the appliance record
        # (remoteWebUrl). That is the closest genuine deep link for a protected
        # machine - it opens the appliance protecting it - so it is preferred
        # over the generic login page. The value is read from the API, never
        # built from a guessed URL pattern.
        device_details_page_url = $(
            if ([string]::IsNullOrWhiteSpace($ApplianceUrl)) { 'https://auth.datto.com/login' } else { $ApplianceUrl }
        )
        appliance_serial        = $SerialNumber
        asset_kind              = $AssetType
        # Screenshot backup verification. Datto boots the recovery point and
        # reports whether it came up: the strongest evidence a backup is not just
        # present but restorable. Both fields confirmed on live agent records.
        screenshot_attempt      = ConvertTo-DattoBcdrUtcString $(Get-DattoBcdrProperty -Object $Asset -Names @('lastScreenshotAttempt') -Default $null)
        screenshot_url          = [string](Get-DattoBcdrProperty -Object $Asset -Names @('lastScreenshotUrl') -Default '')
        screenshot_status       = $(
            $rawScreenshot = Get-DattoBcdrProperty -Object $Asset -Names @('lastScreenshotAttemptStatus') -Default $null
            if ($null -eq $rawScreenshot) { $null } else { [bool]$rawScreenshot }
        )
        # The volume hash, not the machine name. Every asset-level sub-endpoint,
        # every asset-level sub-endpoint, is keyed on this value.
        volume_name             = [string](Get-DattoBcdrProperty -Object $Asset -Names @('volume') -Default '')
        local_snapshots         = Get-DattoBcdrProperty -Object $Asset -Names @('localSnapshots') -Default $null
        protected_volumes       = $protectedVolumes
        unprotected_volumes     = $unprotectedVolumes
        protected_volume_count  = @($protectedVolumes).Count
        unprotected_volume_count = @($unprotectedVolumes).Count
        is_paused               = $isPaused
        is_archived             = $isArchived
        Source                  = $Asset
    }
}

function ConvertTo-DattoBcdrAppliance {
    <#
        One Datto BCDR device as the Appliance shape the application renders.

        Storage arrives as { units, size } - the reference samples KB - and the
        application formats raw bytes, so it is converted here. drive_size is
        used + available because Datto reports free space, not capacity.
    #>
    param(
        [Parameter(Mandatory)]$Appliance,
        [AllowNull()]$Detail,
        [int]$AlertCount = -1,
        [object[]]$Devices = @()
    )

    $source = if ($null -ne $Detail) { $Detail } else { $Appliance }
    $serial = [string](Get-DattoBcdrProperty -Object $Appliance -Names @('serialNumber', 'serial_number', 'serial') -Default '')
    $used = ConvertTo-DattoBcdrByteSize (Get-DattoBcdrProperty -Object $source -Names @('localStorageUsed') -Default $null)
    $available = ConvertTo-DattoBcdrByteSize (Get-DattoBcdrProperty -Object $source -Names @('localStorageAvailable') -Default $null)
    $driveSize = if ($null -ne $used -and $null -ne $available) { $used + $available } else { $null }

    $activeTickets = 0
    $ticketValue = Get-DattoBcdrProperty -Object $source -Names @('activeTickets') -Default 0
    $parsedTickets = 0
    if ([int]::TryParse([string]$ticketValue, [ref]$parsedTickets)) { $activeTickets = $parsedTickets }

    $status = 'NORMAL'
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($AlertCount -gt 0) {
        $status = 'ALERTS'
        $null = $reasons.Add("$AlertCount active alert(s)")
    }
    if ($activeTickets -gt 0) {
        if ($status -eq 'NORMAL') { $status = 'TICKETS OPEN' }
        $null = $reasons.Add("$activeTickets open ticket(s)")
    }
    $lastSeen = ConvertTo-DattoBcdrUtcString (Get-DattoBcdrProperty -Object $source -Names @('lastSeenDate') -Default $null)
    if ($null -ne $lastSeen) {
        $lastSeenUtc = [datetime]::Parse($lastSeen, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
        if (([DateTime]::UtcNow - $lastSeenUtc).TotalHours -gt 24) {
            $status = 'OFFLINE'
            $null = $reasons.Add("Last seen $($lastSeenUtc.ToString('u'))")
        }
    }

    [pscustomobject]@{
        id                   = $serial
        alias                = [string](Get-DattoBcdrProperty -Object $Appliance -Names @('name') -Default $serial)
        objectschema         = 'appliance'
        health_status        = $status
        health_status_reason = ($reasons -join ' · ')
        storage_details      = [pscustomobject]@{
            used_size  = $used
            drive_size = $driveSize
        }
        devices              = @($Devices)
        serial_number        = $serial
        model                = [string](Get-DattoBcdrProperty -Object $Appliance -Names @('model') -Default '')
        service_plan         = [string](Get-DattoBcdrProperty -Object $source -Names @('servicePlan') -Default '')
        last_seen            = $lastSeen
        active_tickets       = $activeTickets
        alert_count          = $AlertCount
        remote_web_url       = [string](Get-DattoBcdrProperty -Object $source -Names @('remoteWebUrl') -Default '')
        warranty_expire      = ConvertTo-DattoBcdrUtcString $(Get-DattoBcdrProperty -Object $source -Names @('warrantyExpire') -Default $null)
        Source               = $source
    }
}

function ConvertTo-DattoBcdrByteSize {
    <#
        { units: "KB", size: 648932024 } -> bytes.

        An unrecognised unit returns $null rather than a number in the wrong
        scale: "Unknown" in a storage cell is recoverable, a figure that is
        wrong by 1024x is not.
    #>
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }

    $size = $null
    $units = 'B'
    if ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [hashtable]) {
        $size = Get-DattoBcdrProperty -Object ([pscustomobject]$Value) -Names @('size') -Default $null
        $units = [string](Get-DattoBcdrProperty -Object ([pscustomobject]$Value) -Names @('units') -Default 'B')
    }
    else {
        $size = $Value
    }

    $number = [double]0
    if (-not [double]::TryParse([string]$size, [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$number)) {
        return $null
    }

    switch (([string]$units).Trim().ToUpperInvariant()) {
        'B' { return [int64]$number }
        'BYTES' { return [int64]$number }
        'KB' { return [int64]($number * 1024) }
        'MB' { return [int64]($number * 1024 * 1024) }
        'GB' { return [int64]($number * 1024 * 1024 * 1024) }
        'TB' { return [int64]($number * 1024 * 1024 * 1024 * 1024) }
        default { return $null }
    }
}

function Get-Client {
    <#
    .SYNOPSIS
        All Datto clients, or one by id.

    .DESCRIPTION
        Drop-in replacement for the Axcient command of the same name. Emits
        objects with id, name and objectschema='client'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject], [PSCustomObject[]])]
    param(
        [Parameter(ValueFromPipeline, ParameterSetName = 'Client')]
        [Alias('Id')]
        [object[]]$Client
    )

    process {
        $all = @((Get-DattoBcdrPartnerData).Clients)
        if ($PSCmdlet.ParameterSetName -ne 'Client') {
            return $all
        }
        foreach ($reference in @($Client)) {
            $wanted = [string](Resolve-DattoBcdrReferenceId -Reference $reference)
            $all | Where-Object { [string]$_.id -eq $wanted }
        }
    }
}

function Get-Device {
    <#
    .SYNOPSIS
        The protected machines (Datto assets) for a client.

    .DESCRIPTION
        Drop-in replacement for the Axcient command of the same name. Assets are
        gathered from every appliance the client's agents live on.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject], [PSCustomObject[]])]
    param(
        [Parameter(ValueFromPipeline, ParameterSetName = 'Client')]
        [object[]]$Client,

        [Parameter(ParameterSetName = 'Device')]
        [Alias('Id')]
        [object[]]$Device
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Device') {
            $wanted = @(@($Device) | ForEach-Object { [string](Resolve-DattoBcdrReferenceId -Reference $_) })
            return @(Get-DattoBcdrAllDevices | Where-Object { [string]$_.id -in $wanted })
        }
        if ($PSCmdlet.ParameterSetName -eq 'All') {
            return @(Get-DattoBcdrAllDevices)
        }

        $cache = Get-DattoBcdrPartnerData
        foreach ($thisClient in @($Client)) {
            $resolved = Resolve-DattoBcdrClient -Reference $thisClient
            if ($null -eq $resolved) { continue }
            foreach ($serial in (Get-DattoBcdrClientSerials -Client $resolved)) {
                $applianceUrl = ''
                if ($cache.ApplianceBySerial.ContainsKey($serial)) {
                    $applianceUrl = [string](Get-DattoBcdrProperty -Object $cache.ApplianceBySerial[$serial] -Names @('remoteWebUrl') -Default '')
                }
                foreach ($typed in @(Get-DattoBcdrApplianceTypedAssets -SerialNumber $serial)) {
                    ConvertTo-DattoBcdrDevice -Asset $typed.Asset -SerialNumber $serial -AssetType $typed.Kind -ApplianceUrl $applianceUrl
                }
            }
        }
    }
}

function Get-Appliance {
    <#
    .SYNOPSIS
        The BCDR appliances for a client.

    .DESCRIPTION
        Drop-in replacement for the Axcient command of the same name. One
        appliance per serial number the client's agents report.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject], [PSCustomObject[]])]
    param(
        [Parameter(ValueFromPipeline, ParameterSetName = 'Client')]
        [object[]]$Client
    )

    process {
        $cache = Get-DattoBcdrPartnerData
        if ($PSCmdlet.ParameterSetName -ne 'Client') {
            return @(foreach ($appliance in $cache.Appliances) {
                    ConvertTo-DattoBcdrAppliance -Appliance $appliance -Detail $null -AlertCount -1
                })
        }

        foreach ($thisClient in @($Client)) {
            $resolved = Resolve-DattoBcdrClient -Reference $thisClient
            if ($null -eq $resolved) { continue }
            foreach ($serial in (Get-DattoBcdrClientSerials -Client $resolved)) {
                if (-not $cache.ApplianceBySerial.ContainsKey($serial)) { continue }
                $assets = @()
                try { $assets = @(Get-DattoBcdrApplianceAssets -SerialNumber $serial) } catch { $assets = @() }
                $detail = $null
                try { $detail = Get-DattoBcdrApplianceDetail -SerialNumber $serial } catch { $detail = $null }
                $alertCount = -1
                try { $alertCount = Get-DattoBcdrApplianceAlertCount -SerialNumber $serial } catch { $alertCount = -1 }
                ConvertTo-DattoBcdrAppliance `
                    -Appliance $cache.ApplianceBySerial[$serial] `
                    -Detail $detail `
                    -AlertCount $alertCount `
                    -Devices @($assets | ForEach-Object {
                            # Objects with an id, not bare ids: the dashboard builds its
                            # appliance-membership set by reading .id off each entry.
                            [pscustomobject]@{ id = Get-DattoBcdrProperty -Object $_ -Names @('assetId', 'id') -Default $null }
                        })
            }
        }
    }
}

function Get-DattoBcdrAllDevices {
    $devices = [System.Collections.Generic.List[object]]::new()
    foreach ($client in @((Get-DattoBcdrPartnerData).Clients)) {
        foreach ($device in @(Get-Device -Client $client)) { $devices.Add($device) }
    }
    return $devices.ToArray()
}

function Resolve-DattoBcdrReferenceId {
    param([AllowNull()]$Reference)

    if ($null -eq $Reference) { return $null }
    if ($Reference -is [string] -or $Reference -is [int] -or $Reference -is [int64]) { return $Reference }
    return (Get-DattoBcdrProperty -Object $Reference -Names @('id') -Default $null)
}

function Resolve-DattoBcdrClient {
    param([AllowNull()]$Reference)

    if ($null -eq $Reference) { return $null }
    $available = @()
    if ($Reference -isnot [string] -and $Reference -isnot [int] -and $Reference -isnot [int64]) {
        $available = @($Reference.PSObject.Properties.Name)
    }
    # An object that already carries its agents is the one this module emitted,
    # so it is used as-is rather than being looked up again.
    if ($available -contains 'agents') { return $Reference }

    $wanted = [string](Resolve-DattoBcdrReferenceId -Reference $Reference)
    if ([string]::IsNullOrWhiteSpace($wanted)) { return $null }
    return @((Get-DattoBcdrPartnerData).Clients | Where-Object { [string]$_.id -eq $wanted }) | Select-Object -First 1
}

Export-ModuleMember -Function @(
    'Initialize-DattoBcdrAPI',
    'Clear-DattoBcdrCache',
    'Invoke-DattoBcdrAPI',
    'Get-Client',
    'Get-Device',
    'Get-Appliance',
    'Get-DattoBcdrApplianceAssets',
    'Get-DattoBcdrApplianceDetail',
    'Get-DattoBcdrApplianceAlertCount',
        'Get-DattoBcdrAlertRule',
    'Get-DattoBcdrDtcAssetCount',
    'Get-DattoBcdrApplianceAgent',
        'Get-DattoBcdrApplianceShare',
        'Get-DattoBcdrApplianceTypedAssets',
        'Get-DattoBcdrVmRestore',
    'ConvertTo-DattoBcdrDevice',
    'ConvertTo-DattoBcdrAppliance',
    'ConvertTo-DattoBcdrByteSize',
    'ConvertTo-DattoBcdrUtcString',
    'ConvertFrom-DattoBcdrClientPayload',
    'ConvertFrom-DattoBcdrDeviceClients',
    'ConvertTo-DattoBcdrNumericId',
    'Get-DattoBcdrProperty',
    'Get-DattoBcdrClientSerials',
    'Get-DattoBcdrPartnerData'
)
