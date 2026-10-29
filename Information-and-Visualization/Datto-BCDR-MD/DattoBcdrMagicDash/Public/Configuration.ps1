function Protect-DbmSecret {
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
        throw 'DATTO-BCDR-MAGIC-DASH stores API keys with Windows DPAPI and must be configured on Windows.'
    }

    $plainBytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $entropy = [Text.Encoding]::UTF8.GetBytes('DATTO-BCDR-MAGIC-DASH/config/v2')
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

function Unprotect-DbmSecret {
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
        $entropy = [Text.Encoding]::UTF8.GetBytes('DATTO-BCDR-MAGIC-DASH/config/v2')
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

function Get-DbmConfigProperty {
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

function ConvertTo-DbmScheduleHours {
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

function ConvertTo-DbmStaleBackupHours {
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

function ConvertTo-DbmTimeZoneId {
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

function ConvertTo-DbmStoredTimeZoneId {
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

function ConvertTo-DbmTaskName {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $ownedTaskName = 'DATTO-BCDR-MAGIC-DASH Sync'
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $ownedTaskName
    }
    if (-not [string]::Equals([string]$Value, $ownedTaskName, [StringComparison]::Ordinal)) {
        throw "config.json taskName must be '$ownedTaskName'. Refusing to modify an unrelated scheduled task."
    }
    return $ownedTaskName
}

function ConvertTo-DbmBoolean {
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

function ConvertTo-DbmPositiveId {
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

function ConvertTo-DbmAssetLayoutId {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    $parsed = ConvertTo-DbmPositiveId $Value
    if ($null -eq $parsed) {
        throw "config.json property 'assetLayoutId' must be a positive integer or null."
    }
    return $parsed
}

function ConvertTo-DbmAssetLayoutName {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text.Trim()
}

function ConvertTo-DbmAssetLayoutSlug {
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

function Test-DbmAssetLayoutName {
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
    if ([string]::IsNullOrWhiteSpace((ConvertTo-DbmAssetLayoutSlug -Name $trimmed))) {
        return 'The asset layout name cannot slugify to an empty value.'
    }
    foreach ($layout in @($ExistingLayouts)) {
        $layoutName = [string](Get-DbmConfigProperty $layout 'name' '')
        if (-not [string]::Equals($layoutName, $trimmed, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (Test-DbmAssetLayoutIsOurs -Layout $layout -StoredLayoutId $StoredLayoutId) {
            continue
        }
        return "A Hudu asset layout named '$trimmed' already exists and is not the DATTO-BCDR-MAGIC-DASH device layout. Choose another name."
    }
    return $null
}

function Test-DbmAssetLayoutIsOurs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Layout,
        [AllowNull()][int64]$StoredLayoutId
    )

    $layoutId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $Layout 'id')
    if ($null -ne $StoredLayoutId -and $null -ne $layoutId -and $layoutId -eq $StoredLayoutId) {
        return $true
    }
    return Test-DbmAssetLayoutHasDetailsField -Layout $Layout
}

function Test-DbmAssetLayoutHasDetailsField {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Layout)

    foreach ($field in @(Get-DbmConfigProperty $Layout 'fields' @())) {
        $label = [string](Get-DbmConfigProperty $field 'label' '')
        $fieldType = [string](Get-DbmConfigProperty $field 'field_type' '')
        if ([string]::Equals($label, 'Asset Details', [StringComparison]::OrdinalIgnoreCase) -and
            ($fieldType -eq 'RichText' -or $fieldType -eq 'rich_text')) {
            return $true
        }
    }
    return $false
}

function Test-DbmAssetLayoutIsReady {
    [CmdletBinding()]
    param([AllowNull()]$Layout)

    if ($null -eq $Layout) { return $false }
    $activeValue = Get-DbmConfigProperty $Layout 'active'
    $isActive = $activeValue -eq $true -or [string]$activeValue -eq '1'
    return $isActive -and (Test-DbmAssetLayoutHasDetailsField -Layout $Layout)
}

function ConvertTo-DbmPendingOperations {
    [CmdletBinding()]
    param([AllowNull()][object[]]$InputOperations = @())

    $validated = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $InputOperations) {
        if ($null -eq $item) {
            throw 'config.json contains a null pending matching operation.'
        }
        $action = [string](Get-DbmConfigProperty $item 'Action' '')
        $sourceId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $item 'SourceHuduId')
        $dattoId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $item 'DattoId')
        if ($action -notin 'Delete', 'Move' -or $null -eq $sourceId -or $null -eq $dattoId) {
            throw 'config.json contains an invalid pending matching operation.'
        }
        $targetId = $null
        if ($action -eq 'Move') {
            $parsedTarget = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $item 'TargetHuduId')
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
            SourceHuduName   = [string](Get-DbmConfigProperty $item 'SourceHuduName' '')
            SourceHuduExists = ConvertTo-DbmBoolean (Get-DbmConfigProperty $item 'SourceHuduExists' $null) -PropertyName 'pendingOperations.SourceHuduExists' -Default $true
            TargetHuduId     = $targetId
            TargetHuduName   = [string](Get-DbmConfigProperty $item 'TargetHuduName' '')
            DattoId        = $dattoId
            DattoName      = [string](Get-DbmConfigProperty $item 'DattoName' '')
        })
    }
    return @($validated)
}

function ConvertTo-DbmValidatedMatchCollection {
    [CmdletBinding()]
    param([AllowNull()][object[]]$InputMatches = @())

    $validated = [System.Collections.Generic.List[object]]::new()
    $seenHudu = [System.Collections.Generic.HashSet[int64]]::new()
    $seenDatto = [System.Collections.Generic.HashSet[int64]]::new()
    $index = 0
    foreach ($matchItem in @($InputMatches)) {
        if ($null -eq $matchItem) {
            throw "Match entry $index is null. Every match must include a positive huduID and dattoId."
        }
        $dattoId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $matchItem 'dattoId')
        $huduId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $matchItem 'huduID')
        if ($null -eq $dattoId) {
            throw "Match entry $index has a missing or invalid dattoId."
        }
        if ($null -eq $huduId) {
            throw "Match entry $index has a missing or invalid huduID."
        }
        if (-not $seenDatto.Add($dattoId)) {
            throw "Datto client ID $dattoId appears in more than one match. Each client can connect to only one Hudu company."
        }
        if (-not $seenHudu.Add($huduId)) {
            throw "Hudu company ID $huduId appears in more than one match. Each Hudu company can connect to only one Datto client."
        }
        $validated.Add([pscustomobject]@{
            name      = [string](Get-DbmConfigProperty $matchItem 'name' '')
            dattoId = $dattoId
            huduID    = $huduId
        })
        $index++
    }
    return @($validated)
}

function ConvertTo-DbmAutoMatchExclusions {
    [CmdletBinding()]
    param([AllowNull()][object[]]$InputExclusions = @())

    $validated = [System.Collections.Generic.List[object]]::new()
    $seenPairs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($InputExclusions)) {
        if ($null -eq $item) {
            throw 'config.json contains a null automatch exclusion.'
        }
        $dattoId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $item 'dattoId')
        $huduId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $item 'huduID')
        if ($null -eq $dattoId -or $null -eq $huduId) {
            throw 'config.json contains an automatch exclusion with a missing or invalid positive ID.'
        }
        if ($seenPairs.Add("$dattoId`:$huduId")) {
            $validated.Add([pscustomobject]@{ dattoId = $dattoId; huduID = $huduId })
        }
    }
    return @($validated)
}

function Reset-DbmHuduScopedSettings {
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
    if ($changedInstance -and @(Get-DbmConfigProperty $Config 'pendingOperations' @()).Count -gt 0) {
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

function Complete-DbmAssetLayoutBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][scriptblock]$ReadInput
    )

    $storedId = ConvertTo-DbmAssetLayoutId (Get-DbmConfigProperty $Config 'assetLayoutId')
    $sessionLayoutId = $null
    $sessionLayoutName = $null
    $sessionReadFailures = 0

    while ($true) {
        $raw = [string](& $ReadInput 'Please pick a name for your Datto Asset Layout in Hudu')
        $name = if ($null -eq $raw) { '' } else { $raw.Trim() }
        $nameError = Test-DbmAssetLayoutName -Name $name
        if ($nameError) {
            Write-Host $nameError -ForegroundColor Red
        }
        else {
            $layout = $null
            if ($null -ne $sessionLayoutId) {
                try {
                    $layout = Get-DbmHuduAssetLayout -Id $sessionLayoutId -ErrorAction Stop
                }
                catch {
                    $sessionReadFailures++
                    Write-Host "The Hudu layout created during this setup attempt could not be retrieved. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)" -ForegroundColor Red
                }
                $retrievedSessionId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $layout 'id')
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
                $layouts = @(Get-DbmHuduAssetLayout -ErrorAction Stop)
                $sameNameLayouts = @(
                    $layouts | Where-Object {
                        [string]::Equals(
                            [string](Get-DbmConfigProperty $_ 'name' ''),
                            $name,
                            [StringComparison]::OrdinalIgnoreCase
                        )
                    }
                )
                $sameNameOurs = [Collections.Generic.List[object]]::new()
                $sameNameConflict = $false
                foreach ($candidate in $sameNameLayouts) {
                    $candidateId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $candidate 'id')
                    if ($null -eq $candidateId) {
                        $sameNameConflict = $true
                        continue
                    }
                    $candidateDetail = $null
                    try {
                        $candidateDetail = Get-DbmHuduAssetLayout -Id $candidateId -ErrorAction Stop
                    }
                    catch {
                        Write-Host "The existing Hudu layout '$name' could not be verified by ID. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)" -ForegroundColor Red
                        $sameNameConflict = $true
                        continue
                    }
                    if (Test-DbmAssetLayoutIsOurs -Layout $candidateDetail -StoredLayoutId $storedId) {
                        $sameNameOurs.Add($candidateDetail)
                    }
                    else {
                        $sameNameConflict = $true
                    }
                }

                if ($sameNameConflict -or $sameNameOurs.Count -gt 1) {
                    Write-Host "A Hudu asset layout named '$name' already exists and could not be uniquely verified as the DATTO-BCDR-MAGIC-DASH device layout. Choose another name." -ForegroundColor Red
                    continue
                }
                if ($sameNameOurs.Count -eq 1) {
                    $layout = $sameNameOurs[0]
                    Write-Host "Reusing the existing DATTO-BCDR-MAGIC-DASH layout '$([string](Get-DbmConfigProperty $layout 'name' $name))'." -ForegroundColor Cyan
                }
                elseif ($null -ne $storedId) {
                    try {
                        $storedLayout = Get-DbmHuduAssetLayout -Id $storedId -ErrorAction Stop
                        if (Test-DbmAssetLayoutIsOurs -Layout $storedLayout -StoredLayoutId $storedId) {
                            $layout = $storedLayout
                        }
                    }
                    catch {
                        $layout = $null
                    }
                }

                if ($null -eq $layout -and $null -ne $storedId) {
                    throw "Stored Hudu asset layout ID $storedId could not be verified as the bound DATTO-BCDR-MAGIC-DASH layout. No replacement layout was created. Run run.ps1 and use the explicit missing-layout recovery choices."
                }

                if ($null -eq $layout) {
                    $createdLayout = $null
                    try {
                        $createdLayout = New-DbmHuduAssetLayout `
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
                        Write-Host "The layout could not be created. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)" -ForegroundColor Red
                    }
                    if ($null -ne $createdLayout) {
                        $createdId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $createdLayout 'id')
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
                $layoutId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $layout 'id')
                if ($null -eq $layoutId) {
                    Write-Host 'Hudu did not return a layout ID after create or lookup. Try again.' -ForegroundColor Red
                }
                else {
                    $verified = $null
                    $activateError = $null
                    try {
                        if (-not (Test-DbmAssetLayoutIsReady -Layout $layout)) {
                            Set-DbmHuduAssetLayoutActive -Id $layoutId -Confirm:$false -ErrorAction Stop | Out-Null
                        }
                        $verified = Get-DbmHuduAssetLayout -Id $layoutId -ErrorAction Stop
                    }
                    catch {
                        $activateError = ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message
                        try {
                            $verified = Get-DbmHuduAssetLayout -Id $layoutId -ErrorAction Stop
                        }
                        catch {
                            $verified = $null
                        }
                    }
                    if (-not (Test-DbmAssetLayoutIsReady -Layout $verified)) {
                        if ($activateError) {
                            Write-Host "The layout could not be activated. $activateError" -ForegroundColor Red
                        }
                        else {
                            Write-Host 'The layout could not be activated with a RichText Asset Details field. Repair it in Hudu or choose another name.' -ForegroundColor Red
                        }
                    }
                    else {
                        $Config.assetLayoutId = $layoutId
                        $Config.assetLayoutName = [string](Get-DbmConfigProperty $verified 'name' $name)
                        Write-Host "Device assets will use layout '$($Config.assetLayoutName)' (Hudu ID $layoutId)." -ForegroundColor Green
                        return $Config
                    }
                }
            }
        }
    }
}

function ConvertTo-DbmRuntimeConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)

    $schemaValue = Get-DbmConfigProperty $InputObject 'schemaVersion'
    if ($null -ne $schemaValue -and $schemaValue -isnot [int] -and $schemaValue -isnot [int64]) {
        throw 'config.json schemaVersion must be the whole number 1 or 2.'
    }
    $schemaVersion = if ($null -eq $schemaValue) { 1 } else { [int64]$schemaValue }
    if ($schemaVersion -notin 1, 2) {
        throw "config.json schemaVersion '$schemaVersion' is unsupported. Upgrade DATTO-BCDR-MAGIC-DASH before opening a newer configuration."
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
    $rawBaseUrl = [string](Get-DbmConfigProperty $InputObject 'huduBaseUrl' '')
    if ([string]::IsNullOrWhiteSpace($rawBaseUrl)) {
        throw "config.json does not contain a Hudu web address in 'huduBaseUrl'. Correct it or rename it and run run.ps1 again."
    }
    $baseUrl = try { ConvertTo-NormalizedHuduUrl -Url $rawBaseUrl }
    catch {
        throw "config.json contains a Hudu web address that could not be used. Correct it or rename it and run run.ps1 again. Details: $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)"
    }
    $huduProtected = [string](Get-DbmConfigProperty $InputObject 'huduAPIKeyProtected' '')
    $dattoProtected = [string](Get-DbmConfigProperty $InputObject 'dattoAPIKeyProtected' '')
    $huduPlain = [string](Get-DbmConfigProperty $InputObject 'huduAPIKey' '')
    $dattoPlain = [string](Get-DbmConfigProperty $InputObject 'dattoAPIKey' '')

    $huduKey = if ($huduProtected) { Unprotect-DbmSecret $huduProtected } else { $huduPlain }
    $dattoKey = if ($dattoProtected) { Unprotect-DbmSecret $dattoProtected } else { $dattoPlain }

    $normalizedMatches = @(ConvertTo-DbmValidatedMatchCollection -InputMatches @(Get-DbmConfigProperty $InputObject 'matches' @()))
    $autoMatchExclusions = @(ConvertTo-DbmAutoMatchExclusions -InputExclusions @(Get-DbmConfigProperty $InputObject 'autoMatchExclusions' @()))

    $styling = Get-DbmConfigProperty $InputObject 'styling'
    $healthy = [string](Get-DbmConfigProperty $styling 'dashHealthy' '')
    if (-not $healthy) {
        $healthy = [string](Get-DbmConfigProperty $styling 'magicDashHealthyClass' 'success')
    }
    $warning = [string](Get-DbmConfigProperty $styling 'dashWarning' '')
    if (-not $warning) {
        $warning = [string](Get-DbmConfigProperty $styling 'magicDashWarningClass' 'danger')
    }

    $schedule = ConvertTo-DbmScheduleHours (Get-DbmConfigProperty $InputObject 'scheduleHours')
    $staleBackupHours = ConvertTo-DbmStaleBackupHours (Get-DbmConfigProperty $InputObject 'staleBackupHours')
    $timeZoneId = ConvertTo-DbmStoredTimeZoneId (Get-DbmConfigProperty $InputObject 'timeZoneId')
    $pendingOperations = @(ConvertTo-DbmPendingOperations -InputOperations (Get-DbmConfigProperty $InputObject 'pendingOperations' @()))
    $assetLayoutId = ConvertTo-DbmAssetLayoutId (Get-DbmConfigProperty $InputObject 'assetLayoutId')
    $assetLayoutName = ConvertTo-DbmAssetLayoutName (Get-DbmConfigProperty $InputObject 'assetLayoutName')

    [pscustomobject][ordered]@{
        schemaVersion       = 2
        huduBaseUrl         = $baseUrl
        huduAPIKey          = $huduKey
        dattoAPIKey       = $dattoKey
        setupComplete       = ConvertTo-DbmBoolean (Get-DbmConfigProperty $InputObject 'setupComplete' $null) -PropertyName 'setupComplete' -Default $true
        autoMatch           = ConvertTo-DbmBoolean (Get-DbmConfigProperty $InputObject 'autoMatch' $null) -PropertyName 'autoMatch' -Default $true
        reportOrphanedDashes = ConvertTo-DbmBoolean (Get-DbmConfigProperty $InputObject 'reportOrphanedDashes' $null) -PropertyName 'reportOrphanedDashes' -Default $true
        staleBackupHours    = $staleBackupHours
        timeZoneId          = $timeZoneId
        scheduleHours       = $schedule
        taskName            = ConvertTo-DbmTaskName (Get-DbmConfigProperty $InputObject 'taskName')
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

function Read-DbmConfig {
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
        throw "Could not read config.json. The file may be empty, corrupt, or hand-edited incorrectly. Correct it or rename it and run run.ps1 again. Details: $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)"
    }

    return ConvertTo-DbmRuntimeConfig -InputObject $parsed
}

function Set-DbmPrivateConfigAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not $IsWindows) { return }
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($identity in @(
        Get-DbmOperatingUserSid
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

function Save-DbmConfig {
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
    $schedule = ConvertTo-DbmScheduleHours (Get-DbmConfigProperty $Config 'scheduleHours')
    $staleBackupHours = ConvertTo-DbmStaleBackupHours (Get-DbmConfigProperty $Config 'staleBackupHours')
    $timeZoneId = ConvertTo-DbmTimeZoneId (Get-DbmConfigProperty $Config 'timeZoneId')
    $setupComplete = ConvertTo-DbmBoolean (Get-DbmConfigProperty $Config 'setupComplete' $null) -PropertyName 'setupComplete' -Default $true
    # A completed setup with no key round-trips happily and then fails at the API
    # with 'the key was rejected', which sends the operator hunting for a revoked
    # key instead of an absent one. The key-recovery path reached through run.ps1 blanks both
    # keys on purpose, but it re-enters them before it saves.
    if ($setupComplete) {
        foreach ($keyProperty in 'huduAPIKey', 'dattoAPIKey') {
            if ([string]::IsNullOrWhiteSpace([string](Get-DbmConfigProperty $Config $keyProperty ''))) {
                throw "Saving a completed setup requires a '$keyProperty' value. Run run.ps1 to paste the key, or set setupComplete to false."
            }
        }
    }

    $persistedMatches = @(
        ConvertTo-DbmValidatedMatchCollection -InputMatches @(Get-DbmConfigProperty $Config 'matches' @()) |
            ForEach-Object {
                [ordered]@{ name = $_.name; dattoId = $_.dattoId; huduID = $_.huduID }
            }
    )
    $persistedExclusions = @(
        ConvertTo-DbmAutoMatchExclusions -InputExclusions @(Get-DbmConfigProperty $Config 'autoMatchExclusions' @()) |
            ForEach-Object { [ordered]@{ dattoId = $_.dattoId; huduID = $_.huduID } }
    )
    $persistedOperations = @(
        ConvertTo-DbmPendingOperations -InputOperations (Get-DbmConfigProperty $Config 'pendingOperations' @()) |
            ForEach-Object {
                [ordered]@{
                    Action           = $_.Action
                    SourceHuduId     = $_.SourceHuduId
                    SourceHuduName   = $_.SourceHuduName
                    SourceHuduExists = $_.SourceHuduExists
                    TargetHuduId     = $_.TargetHuduId
                    TargetHuduName   = $_.TargetHuduName
                    DattoId        = $_.DattoId
                    DattoName      = $_.DattoName
                }
            }
    )
    $styling = Get-DbmConfigProperty $Config 'styling'
    $persisted = [ordered]@{
        schemaVersion          = 2
        huduBaseUrl            = ConvertTo-NormalizedHuduUrl -Url ([string](Get-DbmConfigProperty $Config 'huduBaseUrl' ''))
        huduAPIKeyProtected    = Protect-DbmSecret -Value ([string](Get-DbmConfigProperty $Config 'huduAPIKey' ''))
        dattoAPIKeyProtected = Protect-DbmSecret -Value ([string](Get-DbmConfigProperty $Config 'dattoAPIKey' ''))
        setupComplete          = $setupComplete
        autoMatch              = ConvertTo-DbmBoolean (Get-DbmConfigProperty $Config 'autoMatch' $null) -PropertyName 'autoMatch' -Default $true
        reportOrphanedDashes   = ConvertTo-DbmBoolean (Get-DbmConfigProperty $Config 'reportOrphanedDashes' $null) -PropertyName 'reportOrphanedDashes' -Default $true
        staleBackupHours       = $staleBackupHours
        timeZoneId             = $timeZoneId
        scheduleHours          = $schedule
        taskName               = ConvertTo-DbmTaskName (Get-DbmConfigProperty $Config 'taskName')
        styling                = [ordered]@{
            dashHealthy = [string](Get-DbmConfigProperty $styling 'dashHealthy' 'success')
            dashWarning = [string](Get-DbmConfigProperty $styling 'dashWarning' 'danger')
        }
        matches                = $persistedMatches
        autoMatchExclusions    = $persistedExclusions
        pendingOperations      = $persistedOperations
        assetLayoutId          = ConvertTo-DbmAssetLayoutId (Get-DbmConfigProperty $Config 'assetLayoutId')
        assetLayoutName        = ConvertTo-DbmAssetLayoutName (Get-DbmConfigProperty $Config 'assetLayoutName')
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
        Set-DbmPrivateConfigAcl -Path $tempPath
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
        Set-DbmPrivateConfigAcl -Path $Path
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
