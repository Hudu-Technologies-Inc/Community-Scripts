function Protect-AmdSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }
    if (-not $IsWindows) {
        throw 'AXCIENT-MAGIC-DASH stores API keys with Windows DPAPI and must be configured on Windows.'
    }

    $plainBytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $entropy = [Text.Encoding]::UTF8.GetBytes('AXCIENT-MAGIC-DASH/config/v2')
    try {
        $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $entropy,
            [Security.Cryptography.DataProtectionScope]::LocalMachine
        )
        return "dpapi-machine:$([Convert]::ToBase64String($protectedBytes))"
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        [Array]::Clear($entropy, 0, $entropy.Length)
        if ($null -ne $protectedBytes) { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
    }
}

function Unprotect-AmdSecret {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }
    if ($Value.StartsWith('dpapi-machine:', [StringComparison]::OrdinalIgnoreCase)) {
        if (-not $IsWindows) {
            throw 'This configuration contains a Windows-protected API key and can only be opened on the Windows computer that created it.'
        }
        $protectedBytes = $null
        $plainBytes = $null
        $entropy = [Text.Encoding]::UTF8.GetBytes('AXCIENT-MAGIC-DASH/config/v2')
        try {
            $protectedBytes = [Convert]::FromBase64String($Value.Substring(14))
            $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
                $protectedBytes,
                $entropy,
                [Security.Cryptography.DataProtectionScope]::LocalMachine
            )
            return [Text.Encoding]::UTF8.GetString($plainBytes)
        }
        catch {
            throw 'An API key in config.json could not be decrypted on this computer. Run run.ps1 and re-enter the key.'
        }
        finally {
            [Array]::Clear($entropy, 0, $entropy.Length)
            if ($null -ne $protectedBytes) { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
            if ($null -ne $plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
        }
    }
    if (-not $Value.StartsWith('dpapi:', [StringComparison]::OrdinalIgnoreCase)) {
        # Supports migration from the original project's plaintext config.json.
        return $Value
    }
    if (-not $IsWindows) {
        throw 'This configuration contains a Windows-protected API key and can only be opened by its Windows user.'
    }

    try {
        $secure = ConvertTo-SecureString -String $Value.Substring(6) -ErrorAction Stop
        return [System.Net.NetworkCredential]::new('', $secure).Password
    }
    catch {
        throw 'An API key in config.json could not be decrypted. Run run.ps1 as the Windows user who created the configuration, or re-enter the key.'
    }
}

function Get-AmdConfigProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function ConvertTo-AmdScheduleHours {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $hours = 0
    if (-not [int]::TryParse(
        [string]$Value,
        [Globalization.NumberStyles]::None,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$hours
    ) -or $hours -lt 1 -or $hours -gt 48) {
        throw 'scheduleHours must be empty (disabled) or a whole-number integer from 1 through 48.'
    }
    return $hours
}

function ConvertTo-AmdStaleBackupHours {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 24 }
    $hours = 0
    if (-not [int]::TryParse(
        [string]$Value,
        [Globalization.NumberStyles]::None,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$hours
    ) -or $hours -lt 1 -or $hours -gt 720) {
        throw 'staleBackupHours must be a whole-number integer from 1 through 720.'
    }
    return $hours
}

function ConvertTo-AmdTimeZoneId {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $candidate = if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        [TimeZoneInfo]::Local.Id
    }
    else {
        ([string]$Value).Trim()
    }
    try {
        return [TimeZoneInfo]::FindSystemTimeZoneById($candidate).Id
    }
    catch {
        throw "config.json property 'timeZoneId' is not a time zone supported by this computer. Correct or remove that value, or rename config.json and run run.ps1 again."
    }
}

function ConvertTo-AmdStoredTimeZoneId {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $candidate = if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        [TimeZoneInfo]::Local.Id
    }
    else {
        ([string]$Value).Trim()
    }
    if ($candidate.Length -gt 128 -or $candidate -match '[\x00-\x1F\x7F]') {
        throw "config.json property 'timeZoneId' is malformed. Correct or remove that value."
    }
    try {
        return [TimeZoneInfo]::FindSystemTimeZoneById($candidate).Id
    }
    catch {
        Write-Warning "Saved dashboard time zone '$candidate' is not available on this computer. The run menu will remain available so option 3 can select a replacement; sync writes will fail closed until then."
        return $candidate
    }
}

function ConvertTo-AmdTaskName {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $ownedTaskName = 'AXCIENT-MAGIC-DASH Sync'
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $ownedTaskName
    }
    if (-not [string]::Equals([string]$Value, $ownedTaskName, [StringComparison]::Ordinal)) {
        throw "config.json taskName must be '$ownedTaskName'. Refusing to modify an unrelated scheduled task."
    }
    return $ownedTaskName
}

function ConvertTo-AmdBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][string]$PropertyName,
        [bool]$Default
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -isnot [bool]) {
        throw "config.json property '$PropertyName' must be a JSON boolean (true or false), not a string or number."
    }
    return [bool]$Value
}

function ConvertTo-AmdPositiveId {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    # IDs in config.json are written by this project, so invariant parsing without
    # padding or a leading sign reports hand-edited values instead of accepting them.
    if ($null -eq $Value) { return $null }
    $parsed = 0L
    if (-not [int64]::TryParse(
        [string]$Value,
        [Globalization.NumberStyles]::None,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )) { return $null }
    if ($parsed -le 0) { return $null }
    return $parsed
}

function ConvertTo-AmdAssetLayoutId {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    $parsed = ConvertTo-AmdPositiveId $Value
    if ($null -eq $parsed) {
        throw "config.json property 'assetLayoutId' must be a positive integer or null."
    }
    return $parsed
}

function ConvertTo-AmdAssetLayoutName {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text.Trim()
}

function ConvertTo-AmdAssetLayoutSlug {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    $builder = [Text.StringBuilder]::new()
    $previousHyphen = $false
    foreach ($character in $Name.Trim().ToLowerInvariant().ToCharArray()) {
        if ([char]::IsLetterOrDigit($character)) {
            $null = $builder.Append($character)
            $previousHyphen = $false
            continue
        }
        if (-not $previousHyphen) {
            $null = $builder.Append('-')
            $previousHyphen = $true
        }
    }
    return $builder.ToString().Trim('-')
}

function Test-AmdAssetLayoutName {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Name,
        [AllowNull()][object[]]$ExistingLayouts = @(),
        [AllowNull()][int64]$StoredLayoutId
    )

    $trimmed = if ($null -eq $Name) { '' } else { $Name.Trim() }
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return 'Enter an asset layout name.'
    }
    if ($trimmed.Length -gt 80) {
        return 'The asset layout name must be 80 characters or fewer.'
    }
    foreach ($character in $trimmed.ToCharArray()) {
        $code = [int][char]$character
        if ($code -lt 32 -or $code -eq 127 -or $character -in @("`r", "`n", "`t")) {
            return 'The asset layout name cannot contain control characters or line breaks.'
        }
        if ($character -in @('/', '\', '?', '#', '%', '<', '>', '"', "'")) {
            return 'The asset layout name cannot contain / \ ? # % < > " or '' characters.'
        }
    }
    $stripped = [regex]::Replace($trimmed, '[\s\-_&()]', '')
    if ([string]::IsNullOrWhiteSpace($stripped)) {
        return 'The asset layout name must contain letters or numbers.'
    }
    $letterOrDigitCount = 0
    foreach ($character in $stripped.ToCharArray()) {
        if ([char]::IsLetter($character) -or [char]::IsDigit($character)) {
            $letterOrDigitCount++
        }
    }
    if (($letterOrDigitCount / $stripped.Length) -lt 0.8) {
        return 'The asset layout name must be mostly letters or numbers.'
    }
    if ([string]::IsNullOrWhiteSpace((ConvertTo-AmdAssetLayoutSlug -Name $trimmed))) {
        return 'The asset layout name cannot slugify to an empty value.'
    }
    foreach ($layout in @($ExistingLayouts)) {
        $layoutName = [string](Get-AmdConfigProperty $layout 'name' '')
        if (-not [string]::Equals($layoutName, $trimmed, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (Test-AmdAssetLayoutIsOurs -Layout $layout -StoredLayoutId $StoredLayoutId) {
            continue
        }
        return "A Hudu asset layout named '$trimmed' already exists and is not the AXCIENT-MAGIC-DASH device layout. Choose another name."
    }
    return $null
}

function Test-AmdAssetLayoutIsOurs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Layout,
        [AllowNull()][int64]$StoredLayoutId
    )

    $layoutId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $Layout 'id')
    if ($null -ne $StoredLayoutId -and $null -ne $layoutId -and $layoutId -eq $StoredLayoutId) {
        return $true
    }
    return Test-AmdAssetLayoutHasDetailsField -Layout $Layout
}

function Test-AmdAssetLayoutHasDetailsField {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Layout)

    foreach ($field in @(Get-AmdConfigProperty $Layout 'fields' @())) {
        $label = [string](Get-AmdConfigProperty $field 'label' '')
        $fieldType = [string](Get-AmdConfigProperty $field 'field_type' '')
        if ([string]::Equals($label, 'Asset Details', [StringComparison]::OrdinalIgnoreCase) -and
            ($fieldType -eq 'RichText' -or $fieldType -eq 'rich_text')) {
            return $true
        }
    }
    return $false
}

function Test-AmdAssetLayoutIsReady {
    [CmdletBinding()]
    param([AllowNull()]$Layout)

    if ($null -eq $Layout) { return $false }
    $activeValue = Get-AmdConfigProperty $Layout 'active'
    $isActive = $activeValue -eq $true -or [string]$activeValue -eq '1'
    return $isActive -and (Test-AmdAssetLayoutHasDetailsField -Layout $Layout)
}

function ConvertTo-AmdPendingOperations {
    [CmdletBinding()]
    param([AllowNull()][object[]]$InputOperations = @())

    $validated = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $InputOperations) {
        if ($null -eq $item) {
            throw 'config.json contains a null pending matching operation.'
        }
        $action = [string](Get-AmdConfigProperty $item 'Action' '')
        $sourceId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $item 'SourceHuduId')
        $axcientId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $item 'AxcientId')
        if ($action -notin 'Delete', 'Move' -or $null -eq $sourceId -or $null -eq $axcientId) {
            throw 'config.json contains an invalid pending matching operation.'
        }
        $targetId = $null
        if ($action -eq 'Move') {
            $parsedTarget = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $item 'TargetHuduId')
            if ($null -eq $parsedTarget) {
                throw 'A pending Move operation has an invalid destination Hudu company ID.'
            }
            if ($parsedTarget -eq $sourceId) {
                throw 'A pending Move operation cannot use the source Hudu company as its destination.'
            }
            $targetId = $parsedTarget
        }
        if ($item.PSObject.Properties.Name -notcontains 'SourceHuduExists' -or $null -eq $item.SourceHuduExists) {
            throw 'config.json property pendingOperations.SourceHuduExists must be present and must be a JSON boolean (true or false), not null.'
        }
        $validated.Add([pscustomobject]@{
            Action           = $action
            SourceHuduId     = $sourceId
            SourceHuduName   = [string](Get-AmdConfigProperty $item 'SourceHuduName' '')
            SourceHuduExists = ConvertTo-AmdBoolean (Get-AmdConfigProperty $item 'SourceHuduExists' $null) -PropertyName 'pendingOperations.SourceHuduExists' -Default $true
            TargetHuduId     = $targetId
            TargetHuduName   = [string](Get-AmdConfigProperty $item 'TargetHuduName' '')
            AxcientId        = $axcientId
            AxcientName      = [string](Get-AmdConfigProperty $item 'AxcientName' '')
        })
    }
    return @($validated)
}

function ConvertTo-AmdValidatedMatchCollection {
    [CmdletBinding()]
    param([AllowNull()][object[]]$InputMatches = @())

    $validated = [System.Collections.Generic.List[object]]::new()
    $seenHudu = [System.Collections.Generic.HashSet[int64]]::new()
    $seenAxcient = [System.Collections.Generic.HashSet[int64]]::new()
    $index = 0
    foreach ($matchItem in @($InputMatches)) {
        if ($null -eq $matchItem) {
            throw "Match entry $index is null. Every match must include a positive huduID and axcientId."
        }
        $axcientId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $matchItem 'axcientId')
        $huduId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $matchItem 'huduID')
        if ($null -eq $axcientId) {
            throw "Match entry $index has a missing or invalid axcientId."
        }
        if ($null -eq $huduId) {
            throw "Match entry $index has a missing or invalid huduID."
        }
        if (-not $seenAxcient.Add($axcientId)) {
            throw "Axcient client ID $axcientId appears in more than one match. Each client can connect to only one Hudu company."
        }
        if (-not $seenHudu.Add($huduId)) {
            throw "Hudu company ID $huduId appears in more than one match. Each Hudu company can connect to only one Axcient client."
        }
        $validated.Add([pscustomobject]@{
            name      = [string](Get-AmdConfigProperty $matchItem 'name' '')
            axcientId = $axcientId
            huduID    = $huduId
        })
        $index++
    }
    return @($validated)
}

function ConvertTo-AmdAutoMatchExclusions {
    [CmdletBinding()]
    param([AllowNull()][object[]]$InputExclusions = @())

    $validated = [System.Collections.Generic.List[object]]::new()
    $seenPairs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($InputExclusions)) {
        if ($null -eq $item) {
            throw 'config.json contains a null automatch exclusion.'
        }
        $axcientId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $item 'axcientId')
        $huduId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $item 'huduID')
        if ($null -eq $axcientId -or $null -eq $huduId) {
            throw 'config.json contains an automatch exclusion with a missing or invalid positive ID.'
        }
        if ($seenPairs.Add("$axcientId`:$huduId")) {
            $validated.Add([pscustomobject]@{ axcientId = $axcientId; huduID = $huduId })
        }
    }
    return @($validated)
}

function Reset-AmdHuduScopedSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$NewBaseUrl,
        [Parameter(Mandatory)][string]$NewApiKey
    )

    $normalized = ConvertTo-NormalizedHuduUrl -Url $NewBaseUrl
    $changedInstance = -not [string]::Equals(
        (ConvertTo-NormalizedHuduUrl -Url ([string]$Config.huduBaseUrl)),
        $normalized,
        [StringComparison]::OrdinalIgnoreCase
    )
    if ($changedInstance -and @(Get-AmdConfigProperty $Config 'pendingOperations' @()).Count -gt 0) {
        throw 'The Hudu instance cannot be changed while matching backend operations are pending. Run the current sync until the recovery journal is empty, then change the Hudu URL.'
    }
    $Config.huduBaseUrl = $normalized
    $Config.huduAPIKey = $NewApiKey
    if ($changedInstance) {
        $Config.matches = @()
        $Config.autoMatchExclusions = @()
        $Config.pendingOperations = @()
        foreach ($layoutProperty in 'assetLayoutId', 'assetLayoutName') {
            if ($Config.PSObject.Properties.Name -contains $layoutProperty) {
                $Config.$layoutProperty = $null
            }
            else {
                $Config | Add-Member -NotePropertyName $layoutProperty -NotePropertyValue $null
            }
        }
    }
    return [pscustomobject]@{ Config = $Config; ChangedInstance = $changedInstance }
}

function Complete-AmdAssetLayoutBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][scriptblock]$ReadInput
    )

    $storedId = ConvertTo-AmdAssetLayoutId (Get-AmdConfigProperty $Config 'assetLayoutId')
    $sessionLayoutId = $null
    $sessionLayoutName = $null
    $sessionReadFailures = 0

    while ($true) {
        $raw = [string](& $ReadInput 'Please pick a name for your Axcient Asset Layout in Hudu')
        $name = if ($null -eq $raw) { '' } else { $raw.Trim() }
        $nameError = Test-AmdAssetLayoutName -Name $name
        if ($nameError) {
            Write-Host $nameError -ForegroundColor Red
        }
        else {
            $layout = $null
            if ($null -ne $sessionLayoutId) {
                try {
                    $layout = Get-AmdHuduAssetLayout -Id $sessionLayoutId -ErrorAction Stop
                }
                catch {
                    $sessionReadFailures++
                    Write-Host "The Hudu layout created during this setup attempt could not be retrieved. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)" -ForegroundColor Red
                }
                $retrievedSessionId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $layout 'id')
                if ($retrievedSessionId -ne $sessionLayoutId) {
                    if ($null -ne $layout) { $sessionReadFailures++ }
                    $layout = $null
                    Write-Host "Hudu did not return the layout created during this setup attempt (ID $sessionLayoutId). No additional layout will be created in this attempt." -ForegroundColor Red
                }
                else {
                    $sessionReadFailures = 0
                    Write-Host "Retrying activation of the layout '$sessionLayoutName' created during this setup attempt." -ForegroundColor Cyan
                }
                if ($sessionReadFailures -ge 3) {
                    $failedSessionId = $sessionLayoutId
                    $sessionLayoutId = $null
                    $sessionLayoutName = $null
                    throw "Hudu asset layout ID $failedSessionId could not be verified after 3 attempts. No replacement layout was created. Close setup, then run run.ps1 and use menu option 9 to repair or reconnect that layout."
                }
            }
            else {
                $layouts = @(Get-AmdHuduAssetLayout -ErrorAction Stop)
                $sameNameLayouts = @(
                    $layouts | Where-Object {
                        [string]::Equals(
                            [string](Get-AmdConfigProperty $_ 'name' ''),
                            $name,
                            [StringComparison]::OrdinalIgnoreCase
                        )
                    }
                )
                $sameNameOurs = [Collections.Generic.List[object]]::new()
                $sameNameConflict = $false
                foreach ($candidate in $sameNameLayouts) {
                    $candidateId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $candidate 'id')
                    if ($null -eq $candidateId) {
                        $sameNameConflict = $true
                        continue
                    }
                    $candidateDetail = $null
                    try {
                        $candidateDetail = Get-AmdHuduAssetLayout -Id $candidateId -ErrorAction Stop
                    }
                    catch {
                        Write-Host "The existing Hudu layout '$name' could not be verified by ID. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)" -ForegroundColor Red
                        $sameNameConflict = $true
                        continue
                    }
                    if (Test-AmdAssetLayoutIsOurs -Layout $candidateDetail -StoredLayoutId $storedId) {
                        $sameNameOurs.Add($candidateDetail)
                    }
                    else {
                        $sameNameConflict = $true
                    }
                }

                if ($sameNameConflict -or $sameNameOurs.Count -gt 1) {
                    Write-Host "A Hudu asset layout named '$name' already exists and could not be uniquely verified as the AXCIENT-MAGIC-DASH device layout. Choose another name." -ForegroundColor Red
                    continue
                }
                if ($sameNameOurs.Count -eq 1) {
                    $layout = $sameNameOurs[0]
                    Write-Host "Reusing the existing AXCIENT-MAGIC-DASH layout '$([string](Get-AmdConfigProperty $layout 'name' $name))'." -ForegroundColor Cyan
                }
                elseif ($null -ne $storedId) {
                    try {
                        $storedLayout = Get-AmdHuduAssetLayout -Id $storedId -ErrorAction Stop
                        if (Test-AmdAssetLayoutIsOurs -Layout $storedLayout -StoredLayoutId $storedId) {
                            $layout = $storedLayout
                        }
                    }
                    catch {
                        $layout = $null
                    }
                }

                if ($null -eq $layout -and $null -ne $storedId) {
                    throw "Stored Hudu asset layout ID $storedId could not be verified as the bound AXCIENT-MAGIC-DASH layout. No replacement layout was created. Run run.ps1 and use the explicit missing-layout recovery choices."
                }

                if ($null -eq $layout) {
                    $createdLayout = $null
                    try {
                        $createdLayout = New-AmdHuduAssetLayout `
                            -Name $name `
                            -Fields @(
                                [ordered]@{
                                    label        = 'Asset Details'
                                    field_type   = 'RichText'
                                    required     = $false
                                    show_in_list = $false
                                    position     = 1
                                }
                            ) `
                            -Confirm:$false `
                            -ErrorAction Stop
                    }
                    catch {
                        Write-Host "The layout could not be created. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)" -ForegroundColor Red
                    }
                    if ($null -ne $createdLayout) {
                        $createdId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $createdLayout 'id')
                        if ($null -eq $createdId) {
                            Write-Host 'Hudu did not return a layout ID after create. No additional layout will be created in this attempt.' -ForegroundColor Red
                            continue
                        }
                        $sessionLayoutId = $createdId
                        $sessionLayoutName = $name
                        $layout = $createdLayout
                        Write-Host "Created Hudu asset layout '$name'." -ForegroundColor Green
                    }
                }
            }

            if ($null -ne $layout) {
                $layoutId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $layout 'id')
                if ($null -eq $layoutId) {
                    Write-Host 'Hudu did not return a layout ID after create or lookup. Try again.' -ForegroundColor Red
                }
                else {
                    $verified = $null
                    $activateError = $null
                    try {
                        if (-not (Test-AmdAssetLayoutIsReady -Layout $layout)) {
                            Set-AmdHuduAssetLayoutActive -Id $layoutId -Confirm:$false -ErrorAction Stop | Out-Null
                        }
                        $verified = Get-AmdHuduAssetLayout -Id $layoutId -ErrorAction Stop
                    }
                    catch {
                        $activateError = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
                        try {
                            $verified = Get-AmdHuduAssetLayout -Id $layoutId -ErrorAction Stop
                        }
                        catch {
                            $verified = $null
                        }
                    }
                    if (-not (Test-AmdAssetLayoutIsReady -Layout $verified)) {
                        if ($activateError) {
                            Write-Host "The layout could not be activated. $activateError" -ForegroundColor Red
                        }
                        else {
                            Write-Host 'The layout could not be activated with a RichText Asset Details field. Repair it in Hudu or choose another name.' -ForegroundColor Red
                        }
                    }
                    else {
                        $Config.assetLayoutId = $layoutId
                        $Config.assetLayoutName = [string](Get-AmdConfigProperty $verified 'name' $name)
                        Write-Host "Device assets will use layout '$($Config.assetLayoutName)' (Hudu ID $layoutId)." -ForegroundColor Green
                        return $Config
                    }
                }
            }
        }
    }
}

function ConvertTo-AmdRuntimeConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)

    $schemaValue = Get-AmdConfigProperty $InputObject 'schemaVersion'
    if ($null -ne $schemaValue -and $schemaValue -isnot [int] -and $schemaValue -isnot [int64]) {
        throw 'config.json schemaVersion must be the whole number 1 or 2.'
    }
    $schemaVersion = if ($null -eq $schemaValue) { 1 } else { [int64]$schemaValue }
    if ($schemaVersion -notin 1, 2) {
        throw "config.json schemaVersion '$schemaVersion' is unsupported. Upgrade AXCIENT-MAGIC-DASH before opening a newer configuration."
    }
    if ($schemaVersion -eq 2) {
        foreach ($requiredProperty in @(
            'setupComplete'
            'autoMatch'
            'matches'
            'autoMatchExclusions'
            'pendingOperations'
        )) {
            if ($InputObject.PSObject.Properties.Name -notcontains $requiredProperty -or $null -eq $InputObject.$requiredProperty) {
                throw "config.json schemaVersion 2 requires a non-null '$requiredProperty' property."
            }
        }
        if ($InputObject.PSObject.Properties.Name -notcontains 'scheduleHours') {
            throw "config.json schemaVersion 2 requires a 'scheduleHours' property; use null to disable scheduling."
        }
        foreach ($booleanProperty in 'setupComplete', 'autoMatch', 'reportOrphanedDashes') {
            if ($InputObject.PSObject.Properties.Name -contains $booleanProperty -and $null -eq $InputObject.$booleanProperty) {
                throw "config.json property '$booleanProperty' must be a JSON boolean (true or false), not null."
            }
        }
    }

    # ConvertTo-NormalizedHuduUrl reports its failures as prompts, because its other
    # caller is the interactive setup question. Reaching it from a file has to name
    # the file instead: an operator told to 'enter the web address' has no idea the
    # problem is in config.json, and loses the guidance to correct or rename it.
    $rawBaseUrl = [string](Get-AmdConfigProperty $InputObject 'huduBaseUrl' '')
    if ([string]::IsNullOrWhiteSpace($rawBaseUrl)) {
        throw "config.json does not contain a Hudu web address in 'huduBaseUrl'. Correct it or rename it and run run.ps1 again."
    }
    $baseUrl = try { ConvertTo-NormalizedHuduUrl -Url $rawBaseUrl }
    catch {
        throw "config.json contains a Hudu web address that could not be used. Correct it or rename it and run run.ps1 again. Details: $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)"
    }
    $huduProtected = [string](Get-AmdConfigProperty $InputObject 'huduAPIKeyProtected' '')
    $axcientProtected = [string](Get-AmdConfigProperty $InputObject 'axcientAPIKeyProtected' '')
    $huduPlain = [string](Get-AmdConfigProperty $InputObject 'huduAPIKey' '')
    $axcientPlain = [string](Get-AmdConfigProperty $InputObject 'axcientAPIKey' '')

    $huduKey = if ($huduProtected) { Unprotect-AmdSecret $huduProtected } else { $huduPlain }
    $axcientKey = if ($axcientProtected) { Unprotect-AmdSecret $axcientProtected } else { $axcientPlain }

    $normalizedMatches = @(ConvertTo-AmdValidatedMatchCollection -InputMatches @(Get-AmdConfigProperty $InputObject 'matches' @()))
    $autoMatchExclusions = @(ConvertTo-AmdAutoMatchExclusions -InputExclusions @(Get-AmdConfigProperty $InputObject 'autoMatchExclusions' @()))

    $styling = Get-AmdConfigProperty $InputObject 'styling'
    $healthy = [string](Get-AmdConfigProperty $styling 'dashHealthy' '')
    if (-not $healthy) {
        $healthy = [string](Get-AmdConfigProperty $styling 'magicDashHealthyClass' 'success')
    }
    $warning = [string](Get-AmdConfigProperty $styling 'dashWarning' '')
    if (-not $warning) {
        $warning = [string](Get-AmdConfigProperty $styling 'magicDashWarningClass' 'danger')
    }

    $schedule = ConvertTo-AmdScheduleHours (Get-AmdConfigProperty $InputObject 'scheduleHours')
    $staleBackupHours = ConvertTo-AmdStaleBackupHours (Get-AmdConfigProperty $InputObject 'staleBackupHours')
    $timeZoneId = ConvertTo-AmdStoredTimeZoneId (Get-AmdConfigProperty $InputObject 'timeZoneId')
    $pendingOperations = @(ConvertTo-AmdPendingOperations -InputOperations (Get-AmdConfigProperty $InputObject 'pendingOperations' @()))
    $assetLayoutId = ConvertTo-AmdAssetLayoutId (Get-AmdConfigProperty $InputObject 'assetLayoutId')
    $assetLayoutName = ConvertTo-AmdAssetLayoutName (Get-AmdConfigProperty $InputObject 'assetLayoutName')

    [pscustomobject][ordered]@{
        schemaVersion       = 2
        huduBaseUrl         = $baseUrl
        huduAPIKey          = $huduKey
        axcientAPIKey       = $axcientKey
        setupComplete       = ConvertTo-AmdBoolean (Get-AmdConfigProperty $InputObject 'setupComplete' $null) -PropertyName 'setupComplete' -Default $true
        autoMatch           = ConvertTo-AmdBoolean (Get-AmdConfigProperty $InputObject 'autoMatch' $null) -PropertyName 'autoMatch' -Default $true
        reportOrphanedDashes = ConvertTo-AmdBoolean (Get-AmdConfigProperty $InputObject 'reportOrphanedDashes' $null) -PropertyName 'reportOrphanedDashes' -Default $true
        staleBackupHours    = $staleBackupHours
        timeZoneId          = $timeZoneId
        scheduleHours       = $schedule
        taskName            = ConvertTo-AmdTaskName (Get-AmdConfigProperty $InputObject 'taskName')
        styling             = [pscustomobject]@{
            dashHealthy = if ($healthy) { $healthy } else { 'success' }
            dashWarning = if ($warning) { $warning } else { 'danger' }
        }
        matches             = $normalizedMatches
        autoMatchExclusions = $autoMatchExclusions
        pendingOperations   = $pendingOperations
        assetLayoutId       = $assetLayoutId
        assetLayoutName     = $assetLayoutName
    }
}

function Read-AmdConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path. Run setup.ps1 first."
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw 'The file is empty.'
        }
        $parsed = $raw | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    }
    catch {
        throw "Could not read config.json. The file may be empty, corrupt, or hand-edited incorrectly. Correct it or rename it and run run.ps1 again. Details: $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)"
    }

    return ConvertTo-AmdRuntimeConfig -InputObject $parsed
}

function Set-AmdPrivateConfigAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not $IsWindows) { return }
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($identity in @(
        Get-AmdOperatingUserSid
        [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
        [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    )) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $identity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $allow
        ))
    }
    # Set-Acl reads and reapplies all security sections on an existing file. If
    # that file carries a SACL, the second hardening pass after the atomic move
    # can consequently demand SeSecurityPrivilege from an ordinary operator.
    # The FileSystemAclExtensions API persists only the DACL changes represented
    # by this newly constructed descriptor.
    [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($Path), $acl)
}

function Save-AmdConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Path
    )

    foreach ($requiredProperty in @(
        'setupComplete'
        'autoMatch'
        'matches'
        'autoMatchExclusions'
        'pendingOperations'
    )) {
        if ($Config.PSObject.Properties.Name -notcontains $requiredProperty -or $null -eq $Config.$requiredProperty) {
            throw "Saving schemaVersion 2 requires a non-null '$requiredProperty' property."
        }
    }
    if ($Config.PSObject.Properties.Name -notcontains 'scheduleHours') {
        throw "Saving schemaVersion 2 requires a 'scheduleHours' property; use null to disable scheduling."
    }
    foreach ($booleanProperty in 'setupComplete', 'autoMatch', 'reportOrphanedDashes') {
        if ($Config.PSObject.Properties.Name -contains $booleanProperty -and $null -eq $Config.$booleanProperty) {
            throw "config.json property '$booleanProperty' must be a JSON boolean (true or false), not null."
        }
    }
    $schedule = ConvertTo-AmdScheduleHours (Get-AmdConfigProperty $Config 'scheduleHours')
    $staleBackupHours = ConvertTo-AmdStaleBackupHours (Get-AmdConfigProperty $Config 'staleBackupHours')
    $timeZoneId = ConvertTo-AmdTimeZoneId (Get-AmdConfigProperty $Config 'timeZoneId')
    $setupComplete = ConvertTo-AmdBoolean (Get-AmdConfigProperty $Config 'setupComplete' $null) -PropertyName 'setupComplete' -Default $true
    # A completed setup with no key round-trips happily and then fails at the API
    # with 'the key was rejected', which sends the operator hunting for a revoked
    # key instead of an absent one. The key-recovery path reached through run.ps1 blanks both
    # keys on purpose, but it re-enters them before it saves.
    if ($setupComplete) {
        foreach ($keyProperty in 'huduAPIKey', 'axcientAPIKey') {
            if ([string]::IsNullOrWhiteSpace([string](Get-AmdConfigProperty $Config $keyProperty ''))) {
                throw "Saving a completed setup requires a '$keyProperty' value. Run run.ps1 to paste the key, or set setupComplete to false."
            }
        }
    }

    $persistedMatches = @(
        ConvertTo-AmdValidatedMatchCollection -InputMatches @(Get-AmdConfigProperty $Config 'matches' @()) |
            ForEach-Object {
                [ordered]@{ name = $_.name; axcientId = $_.axcientId; huduID = $_.huduID }
            }
    )
    $persistedExclusions = @(
        ConvertTo-AmdAutoMatchExclusions -InputExclusions @(Get-AmdConfigProperty $Config 'autoMatchExclusions' @()) |
            ForEach-Object { [ordered]@{ axcientId = $_.axcientId; huduID = $_.huduID } }
    )
    $persistedOperations = @(
        ConvertTo-AmdPendingOperations -InputOperations (Get-AmdConfigProperty $Config 'pendingOperations' @()) |
            ForEach-Object {
                [ordered]@{
                    Action           = $_.Action
                    SourceHuduId     = $_.SourceHuduId
                    SourceHuduName   = $_.SourceHuduName
                    SourceHuduExists = $_.SourceHuduExists
                    TargetHuduId     = $_.TargetHuduId
                    TargetHuduName   = $_.TargetHuduName
                    AxcientId        = $_.AxcientId
                    AxcientName      = $_.AxcientName
                }
            }
    )
    $styling = Get-AmdConfigProperty $Config 'styling'
    $persisted = [ordered]@{
        schemaVersion          = 2
        huduBaseUrl            = ConvertTo-NormalizedHuduUrl -Url ([string](Get-AmdConfigProperty $Config 'huduBaseUrl' ''))
        huduAPIKeyProtected    = Protect-AmdSecret -Value ([string](Get-AmdConfigProperty $Config 'huduAPIKey' ''))
        axcientAPIKeyProtected = Protect-AmdSecret -Value ([string](Get-AmdConfigProperty $Config 'axcientAPIKey' ''))
        setupComplete          = $setupComplete
        autoMatch              = ConvertTo-AmdBoolean (Get-AmdConfigProperty $Config 'autoMatch' $null) -PropertyName 'autoMatch' -Default $true
        reportOrphanedDashes   = ConvertTo-AmdBoolean (Get-AmdConfigProperty $Config 'reportOrphanedDashes' $null) -PropertyName 'reportOrphanedDashes' -Default $true
        staleBackupHours       = $staleBackupHours
        timeZoneId             = $timeZoneId
        scheduleHours          = $schedule
        taskName               = ConvertTo-AmdTaskName (Get-AmdConfigProperty $Config 'taskName')
        styling                = [ordered]@{
            dashHealthy = [string](Get-AmdConfigProperty $styling 'dashHealthy' 'success')
            dashWarning = [string](Get-AmdConfigProperty $styling 'dashWarning' 'danger')
        }
        matches                = $persistedMatches
        autoMatchExclusions    = $persistedExclusions
        pendingOperations      = $persistedOperations
        assetLayoutId          = ConvertTo-AmdAssetLayoutId (Get-AmdConfigProperty $Config 'assetLayoutId')
        assetLayoutName        = ConvertTo-AmdAssetLayoutName (Get-AmdConfigProperty $Config 'assetLayoutName')
        lastUpdatedUtc         = [DateTime]::UtcNow.ToString('o')
    }

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $tempPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $tempStream = $null
    try {
        $tempStream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        # Keep the CreateNew handle exclusive while applying the ACL by path so
        # another process cannot replace the file with a reparse point.
        Set-AmdPrivateConfigAcl -Path $tempPath
        $jsonBytes = [Text.Encoding]::UTF8.GetBytes(($persisted | ConvertTo-Json -Depth 12))
        try {
            $tempStream.SetLength(0)
            $tempStream.Write($jsonBytes, 0, $jsonBytes.Length)
            $tempStream.Flush($true)
        }
        finally {
            [Array]::Clear($jsonBytes, 0, $jsonBytes.Length)
        }
        $tempStream.Dispose()
        $tempStream = $null
        Move-Item -LiteralPath $tempPath -Destination $Path -Force -ErrorAction Stop
        # Move-Item replacement behavior can preserve or inherit destination ACLs
        # differently across filesystems. Reassert the contract on the final path.
        Set-AmdPrivateConfigAcl -Path $Path
    }
    finally {
        if ($null -ne $tempStream) {
            $tempStream.Dispose()
        }
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $Path
}
