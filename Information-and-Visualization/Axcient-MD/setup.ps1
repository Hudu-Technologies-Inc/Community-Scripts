[CmdletBinding()]
param(
    [switch]$SuppressExitPause,

    [Parameter(DontShow)]
    [switch]$Ongoing
)

function Clear-AmdPendingConsoleInput {
    [CmdletBinding()]
    param()

    try {
        if ([Console]::IsInputRedirected) { return }
        while ([Console]::KeyAvailable) {
            $null = [Console]::ReadKey($true)
        }
    }
    catch {
        # Read-Host still provides correct line submission in hosts that do not
        # expose a System.Console input buffer (ISE, remoting, redirected input).
        Write-Verbose "The console input buffer could not be cleared in this host: $($_.Exception.Message)"
    }
}

function Read-AmdConfirmedInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$MaskInput,
        [switch]$RequireNonEmpty,
        [string]$EmptyMessage = 'Enter a value and press Enter.'
    )

    while ($true) {
        # A pasted key or a double Enter can leave a complete blank line queued
        # for the next Read-Host call. Drain it before the next prompt is shown,
        # so only input submitted for this visible prompt can be accepted.
        Clear-AmdPendingConsoleInput
        $value = if ($MaskInput) {
            Read-Host $Prompt -MaskInput
        }
        else {
            Read-Host $Prompt
        }
        if ($null -eq $value) {
            throw [IO.EndOfStreamException]::new(
                'Interactive input ended before the prompt was answered. Run this command in an interactive PowerShell console and try again.'
            )
        }
        $text = [string]$value
        if (-not $RequireNonEmpty -or -not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
        Write-Host $EmptyMessage -ForegroundColor Red
    }
}

function Confirm-AmdSetupExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(0, 255)][int]$ExitCode,
        [ValidateSet('setup', 'run menu')][string]$WorkflowName = 'setup',
        [switch]$SuppressPause
    )

    if ($SuppressPause) { return }
    if ($ExitCode -eq 0) {
        Write-Host "`nAXCIENT-MAGIC-DASH $WorkflowName finished successfully." -ForegroundColor Green
    }
    else {
        Write-Host "`nAXCIENT-MAGIC-DASH $WorkflowName failed with exit code $ExitCode." -ForegroundColor Red
    }
    Read-AmdConfirmedInput -Prompt "Press Enter to close $WorkflowName" | Out-Null
}

$readOptionalInput = { param($Prompt) Read-AmdConfirmedInput -Prompt $Prompt }
$readRequiredInput = { param($Prompt) Read-AmdConfirmedInput -Prompt $Prompt -RequireNonEmpty }

if ([Console]::IsInputRedirected) {
    throw 'AXCIENT-MAGIC-DASH setup is interactive and cannot read piped or redirected input. Open an interactive PowerShell console and run setup.ps1 again.'
}

if ($PSVersionTable.PSVersion -lt [version]'7.2') {
    $pwshHelper = Join-Path $PSScriptRoot 'AxcientMagicDash\Private\Resolve-AmdPwsh72.ps1'
    . $pwshHelper
    $verifiedPwsh = Resolve-AmdMicrosoftPwsh72Path

    if ([string]::IsNullOrWhiteSpace($verifiedPwsh)) {
        $message = 'AXCIENT-MAGIC-DASH requires Microsoft PowerShell 7.2 or newer. Install PowerShell 7 from https://aka.ms/powershell-release?tag=stable and run setup.ps1 again.'
        Write-Host $message -ForegroundColor Red
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            [Windows.MessageBox]::Show($message, 'AXCIENT-MAGIC-DASH Setup', 'OK', 'Error') | Out-Null
        }
        catch {
            Read-AmdConfirmedInput -Prompt 'Press Enter to close' | Out-Null
        }
        exit 1
    }

    $forwardedArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) {
        $forwardedArguments.Add($argument)
    }
    if ($Ongoing) { $forwardedArguments.Add('-Ongoing') }
    $forwardedArguments.Add('-SuppressExitPause')
    & $verifiedPwsh @forwardedArguments
    $childExitCode = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    Confirm-AmdSetupExit -ExitCode $childExitCode -WorkflowName $(if ($Ongoing) { 'run menu' } else { 'setup' }) -SuppressPause:$SuppressExitPause
    exit $childExitCode
}

$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'AXCIENT-MAGIC-DASH setup requires Windows.'
}
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
}
catch {
    throw 'AXCIENT-MAGIC-DASH setup requires Windows Desktop Experience with WPF. Windows Server Core is not supported.'
}

$elevationPath = Join-Path $PSScriptRoot 'AxcientMagicDash\Private\Elevation.ps1'
. $elevationPath
$isAdministrator = Test-AmdAdministrator
$null = Set-AmdOriginalUserContext
$isVerifiedElevation = [Environment]::GetEnvironmentVariable('AMD_VERIFIED_ELEVATION', [EnvironmentVariableTarget]::Process) -eq '1'
$originalProjectRoot = [Environment]::GetEnvironmentVariable('AMD_ORIGINAL_PROJECT_ROOT', [EnvironmentVariableTarget]::Process)
$projectRoot = if ($isVerifiedElevation -and -not [string]::IsNullOrWhiteSpace($originalProjectRoot)) {
    [IO.Path]::GetFullPath($originalProjectRoot)
}
else {
    [IO.Path]::GetFullPath($PSScriptRoot)
}
if ($isVerifiedElevation -and -not $isAdministrator) {
    throw 'The verified elevation marker is invalid because this process is not running as an administrator.'
}

$existingConfigPath = Join-Path $projectRoot 'config.json'
if ((Test-Path -LiteralPath $existingConfigPath -PathType Leaf) -and -not $Ongoing) {
    Write-Host @'

First-time setup has already been started on this computer.
Use run.ps1 for every later action, including completing setup recovery,
changing settings, matching companies, scheduling, testing connections,
and running a sync.
'@ -ForegroundColor Yellow
    exit 0
}

if (-not $isVerifiedElevation) {
    $preElevationModulePath = Join-Path $PSScriptRoot 'AxcientMagicDash\AxcientMagicDash.psd1'
    $preElevationModules = Join-Path $PSScriptRoot 'Modules'
    $preElevationRuntime = Join-Path $PSScriptRoot 'Runtime'
    if (-not (Test-Path -LiteralPath $preElevationRuntime -PathType Container)) {
        throw 'The bundled Python Runtime folder is missing. Restore the complete AXCIENT-MAGIC-DASH distribution and rerun setup.ps1.'
    }
    if (-not $isAdministrator) {
        Import-Module $preElevationModulePath -Force -DisableNameChecking
        Import-AmdRequiredModules `
            -LocalModulePath $preElevationModules `
            -Interactive `
            -ProjectLocalOnly `
            -ReadInput $readOptionalInput
        Remove-Module AxcientMagicDash -Force
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $preElevationModules 'AxcientAPI') -PathType Container)) {
        throw 'Close this administrator window and run setup.ps1 from a normal PowerShell 7 window once so project-local dependencies can be prepared before verified elevation.'
    }
    $elevatedExitCode = 1
    try {
        $elevationParameters = @{
            ScriptPath       = $PSCommandPath
            WorkingDirectory = $PSScriptRoot
        }
        if ($Ongoing) {
            $elevationParameters['ForwardedArguments'] = @('-Ongoing')
        }
        $elevatedExitCode = Start-AmdElevatedProcess @elevationParameters -Sta
    }
    catch {
        $safeElevationError = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
        Write-Host "`nAXCIENT-MAGIC-DASH could not start or finish the elevated $(if ($Ongoing) { 'run menu' } else { 'setup' }): $safeElevationError" -ForegroundColor Red
    }
    Confirm-AmdSetupExit -ExitCode $elevatedExitCode -WorkflowName $(if ($Ongoing) { 'run menu' } else { 'setup' }) -SuppressPause:$SuppressExitPause
    exit $elevatedExitCode
}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
    $staArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in '-NoLogo', '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) {
        $staArguments.Add($argument)
    }
    if ($Ongoing) { $staArguments.Add('-Ongoing') }
    & (Get-AmdCurrentPwshPath) @staArguments
    # A child that died before it could set an exit code must not be reported as
    # a successful setup.
    exit $(if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE })
}

$modulePath = Join-Path $PSScriptRoot 'AxcientMagicDash\AxcientMagicDash.psd1'
$configPath = Join-Path $projectRoot 'config.json'
$localModules = Join-Path $PSScriptRoot 'Modules'
$runScript = Join-Path $projectRoot 'run.ps1'
$lockPath = $null
$projectLock = $null

function Get-AmdSafeErrorText {
    param([Parameter(Mandatory)]$ErrorRecord)
    # Elevation.ps1 is dot-sourced before the module, so this bounded form still
    # works when the module import itself is what failed: it redacts registered
    # secrets when they exist and strips credential-shaped tokens either way.
    return ConvertTo-AmdBoundedDiagnosticText -Text $ErrorRecord.Exception.Message
}

function Stop-AmdSetup {
    param(
        [Parameter(Mandatory)][ValidateRange(0, 255)][int]$ExitCode,
        [string]$FailureMessage
    )
    if ($ExitCode -ne 0) {
        $safeMessage = if ([string]::IsNullOrWhiteSpace($FailureMessage)) {
            "AXCIENT-MAGIC-DASH workflow stopped with exit code $ExitCode."
        }
        else {
            $FailureMessage
        }
        # Reporting the failure must never prevent reporting the exit code. Without
        # this, a status write that threw skipped the exit below, the catch called
        # this again, and the elevated console closed having said nothing at all.
        try { Write-AmdElevationFailureStatus -Message $safeMessage }
        catch {
            $statusError = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
            Write-Warning "The elevated failure status could not be recorded: $statusError" -WarningAction Continue
        }
        if (-not $SuppressExitPause) {
            $closeName = if ($Ongoing) { 'run menu' } else { 'setup' }
            Read-AmdConfirmedInput -Prompt "Press Enter to close $closeName" | Out-Null
        }
    }
    exit $ExitCode
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $suffix = if ($Default) { '(Y/n)' } else { '(y/N)' }
    while ($true) {
        $answer = (Read-AmdConfirmedInput -Prompt "$Prompt $suffix").Trim()
        if (-not $answer) { return $Default }
        if ($answer -in 'y', 'Y', 'yes', 'Yes', 'YES') { return $true }
        if ($answer -in 'n', 'N', 'no', 'No', 'NO') { return $false }
        Write-Host 'Enter Y or N.' -ForegroundColor Red
    }
}

function Invoke-AmdUnownedLegacyMagicDashCleanup {
    [CmdletBinding()]
    param([AllowNull()][scriptblock]$ReadConfirmation)

    $candidates = @(Get-AmdUnownedLegacyMagicDashCandidates -ErrorAction Continue)
    if ($candidates.Count -eq 0) { return 0 }

    Write-Host "`nPossible leftover Axcient Magic Dashes" -ForegroundColor Magenta
    Write-Host 'These entries have the expected title and older Axcient-related content, but not the current ownership marker.' -ForegroundColor Yellow
    $displayLimit = 20
    foreach ($candidate in @($candidates | Select-Object -First $displayLimit)) {
        $safeCompanyName = ConvertTo-AmdBoundedDiagnosticText -Text ([string]$candidate.CompanyName) -MaximumLength 160
        Write-Host "  - $safeCompanyName (Magic Dash ID $($candidate.DashId))" -ForegroundColor Yellow
    }
    if ($candidates.Count -gt $displayLimit) {
        Write-Host "  - ...and $($candidates.Count - $displayLimit) more candidate(s)." -ForegroundColor Yellow
    }

    $confirmation = if ($null -ne $ReadConfirmation) {
        & $ReadConfirmation 'Delete every listed unowned legacy Magic Dash?' $false
    }
    else {
        Read-YesNo 'Delete every listed unowned legacy Magic Dash?' $false
    }
    if (-not $confirmation) {
        Write-Host 'No legacy Magic Dashes were deleted.' -ForegroundColor Cyan
        return 0
    }

    $deleted = 0
    foreach ($candidate in $candidates) {
        $dashId = [int64]$candidate.DashId
        try {
            Remove-AmdHuduMagicDash -Id $dashId -Confirm:$false -ErrorAction Stop | Out-Null
            $deleted++
        }
        catch {
            Write-Warning "Legacy Magic Dash ID $dashId could not be deleted. Continuing to device layout setup. $(Get-AmdSafeErrorText $_)" -WarningAction Continue
        }
    }
    Write-Host "Deleted $deleted of $($candidates.Count) listed legacy Magic Dash candidate(s)." -ForegroundColor Green
    return $deleted
}

function Connect-AmdExistingAssetLayoutInteractive {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $layouts = @(Get-AmdHuduAssetLayout -ErrorAction Stop | Sort-Object name, id)
    if ($layouts.Count -eq 0) {
        Write-Host 'Hudu has no existing asset layouts available to connect.' -ForegroundColor Yellow
        return $false
    }
    Write-Host "`nExisting Hudu asset layouts" -ForegroundColor Magenta
    $displayLimit = 50
    foreach ($layout in @($layouts | Select-Object -First $displayLimit)) {
        Write-Host "  ID $($layout.id): $([string]$layout.name)" -ForegroundColor Yellow
    }
    if ($layouts.Count -gt $displayLimit) {
        Write-Host "  ...and $($layouts.Count - $displayLimit) more. Enter a Hudu layout ID from the full Asset Layouts page if it is not shown here." -ForegroundColor Yellow
    }

    while ($true) {
        $raw = (Read-AmdConfirmedInput -Prompt 'Enter the Hudu asset layout ID to connect, or Q to cancel').Trim()
        if ($raw -eq 'Q') { return $false }
        $selectedId = 0L
        if (-not [int64]::TryParse(
                $raw,
                [Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$selectedId
            ) -or $selectedId -lt 1) {
            Write-Host 'Enter a positive Hudu asset layout ID, or Q.' -ForegroundColor Red
            continue
        }
        $listed = @($layouts | Where-Object { [int64]$_.id -eq $selectedId })
        if ($listed.Count -ne 1) {
            Write-Host 'That ID was not returned by Hudu. Refresh Hudu Asset Layouts and choose one of its current IDs.' -ForegroundColor Red
            continue
        }
        try {
            Add-AmdHuduAssetLayoutDetailsField -Id $selectedId -Confirm:$false -ErrorAction Stop | Out-Null
            $verified = Get-AmdHuduAssetLayout -Id $selectedId -ErrorAction Stop
            if (-not (& (Get-Module AxcientMagicDash) { param($Layout) Test-AmdAssetLayoutIsReady -Layout $Layout } $verified)) {
                throw 'Hudu did not return an active layout with a RichText Asset Details field after the connection update.'
            }
            $Config.assetLayoutId = $selectedId
            $Config.assetLayoutName = [string]$verified.name
            Write-Host "Connected Hudu asset layout '$($Config.assetLayoutName)' (ID $selectedId). Existing customer fields and settings were preserved." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "That layout could not be connected safely. $(Get-AmdSafeErrorText $_)" -ForegroundColor Red
            Write-Host 'Choose a different layout, or enter Q to leave device assets disconnected.' -ForegroundColor Yellow
        }
    }
}

function Resolve-AmdInteractiveAssetLayoutHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$OfferMissingRecovery
    )

    $layoutId = $Config.assetLayoutId
    if ($null -eq $layoutId) {
        Write-Host 'Axcient asset layout: not connected (use menu option 9).' -ForegroundColor Yellow
        return [pscustomobject]@{ Status = 'Unbound'; Layout = $null; Changed = $false }
    }
    try {
        Connect-AmdHudu -InstanceUrl $Config.huduBaseUrl -ApiKey $Config.huduAPIKey -ErrorAction Stop
        $layout = Get-AmdHuduAssetLayout -Id ([int64]$layoutId) -ErrorAction Stop
        if ([int64]$layout.id -ne [int64]$layoutId) {
            throw [Management.Automation.ItemNotFoundException]::new("Hudu did not return layout ID $layoutId.")
        }
    }
    catch {
        $statusCode = & (Get-Module AxcientMagicDash) {
            param($ErrorRecord)
            Get-AmdHttpStatusCode -ErrorRecord $ErrorRecord
        } $_
        $conclusivelyMissing = $statusCode -eq 404 -or $_.Exception -is [Management.Automation.ItemNotFoundException]
        if (-not $conclusivelyMissing) {
            Write-Host "Axcient asset layout status could not be checked. No layout was created or changed. $(Get-AmdSafeErrorText $_)" -ForegroundColor Red
            return [pscustomobject]@{ Status = 'Unavailable'; Layout = $null; Changed = $false }
        }
        Write-Host 'Your Axcient asset layout may have been renamed, moved, or deleted.' -ForegroundColor Red
        if (-not $OfferMissingRecovery) {
            Write-Host 'Use run.ps1 menu option 9 to create a new layout, connect an existing layout, or leave device assets disconnected.' -ForegroundColor Yellow
            return [pscustomobject]@{ Status = 'Missing'; Layout = $null; Changed = $false }
        }
        Write-Host '  1. Create a new layout and connect it.' -ForegroundColor Yellow
        Write-Host '  2. Connect an existing Hudu asset layout.' -ForegroundColor Yellow
        Write-Host '  3. Leave device assets disconnected for now.' -ForegroundColor Yellow
        while ($true) {
            $choice = (Read-AmdConfirmedInput -Prompt 'Choose 1, 2, or 3').Trim()
            if ($choice -in '1', '2', '3') { break }
            Write-Host 'Choose 1, 2, or 3.' -ForegroundColor Red
        }
        if ($choice -eq '3') {
            return [pscustomobject]@{ Status = 'Missing'; Layout = $null; Changed = $false }
        }
        if ($choice -eq '2') {
            $changed = Connect-AmdExistingAssetLayoutInteractive -Config $Config
            $connected = if ($changed) { Get-AmdHuduAssetLayout -Id ([int64]$Config.assetLayoutId) -ErrorAction Stop } else { $null }
            $recoveryStatus = if ($changed) { 'Healthy' } else { 'Missing' }
            return [pscustomobject]@{ Status = $recoveryStatus; Layout = $connected; Changed = [bool]$changed }
        }

        $oldId = $Config.assetLayoutId
        $oldName = $Config.assetLayoutName
        try {
            $Config.assetLayoutId = $null
            $Config.assetLayoutName = $null
            $Config = Complete-AmdAssetLayoutBinding -Config $Config -ReadInput $readOptionalInput
            $created = Get-AmdHuduAssetLayout -Id ([int64]$Config.assetLayoutId) -ErrorAction Stop
            return [pscustomobject]@{ Status = 'Healthy'; Layout = $created; Changed = $true }
        }
        catch {
            $Config.assetLayoutId = $oldId
            $Config.assetLayoutName = $oldName
            throw
        }
    }

    $actualName = [string]$layout.name
    if (-not [string]::Equals([string]$Config.assetLayoutName, $actualName, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Axcient asset layout: Hudu ID $layoutId is now named '$actualName' (stored name '$($Config.assetLayoutName)'). The ID remains authoritative." -ForegroundColor Yellow
    }
    $ready = & (Get-Module AxcientMagicDash) { param($Layout) Test-AmdAssetLayoutIsReady -Layout $Layout } $layout
    if ($ready) {
        Write-Host "Axcient asset layout: active and healthy ('$actualName', Hudu ID $layoutId)." -ForegroundColor Green
        return [pscustomobject]@{ Status = 'Healthy'; Layout = $layout; Changed = $false }
    }
    Write-Host "Axcient asset layout: present but inactive or missing the compatible RichText Asset Details field (Hudu ID $layoutId). Use menu option 9 to repair it." -ForegroundColor Yellow
    return [pscustomobject]@{ Status = 'NeedsRepair'; Layout = $layout; Changed = $false }
}

function Read-HuduSettings {
    :UrlEntry while ($true) {
        $rawUrl = Read-AmdConfirmedInput `
            -Prompt 'Enter your complete Hudu URL from the browser address bar' `
            -RequireNonEmpty `
            -EmptyMessage 'Enter the Hudu URL and press Enter.'
        try {
            $baseUrl = ConvertTo-NormalizedHuduUrl -Url $rawUrl
            Write-Host "Normalized Hudu URL: $baseUrl" -ForegroundColor Cyan
            $reachability = Test-AmdHuduReachability -BaseUrl $baseUrl
            if (-not $reachability.Success) {
                Write-Host $reachability.Message -ForegroundColor Red
                continue UrlEntry
            }
        }
        catch {
            Write-Host (Get-AmdSafeErrorText $_) -ForegroundColor Red
            continue UrlEntry
        }

        while ($true) {
            Write-Host "`nCreate or review Hudu API keys at: $baseUrl/admin/api_keys/new" -ForegroundColor Yellow
            $key = Read-AmdConfirmedInput `
                -Prompt 'Paste the Hudu API key' `
                -MaskInput `
                -RequireNonEmpty `
                -EmptyMessage 'Paste the Hudu API key and press Enter.'
            $keyInfo = ConvertTo-AmdNormalizedApiKey -Key $key
            $result = Test-AmdHuduConnection -BaseUrl $baseUrl -ApiKey $keyInfo.Value
            if ($result.Success) {
                Write-Host $result.Message -ForegroundColor Green
                return [pscustomobject]@{ BaseUrl = $result.BaseUrl; ApiKey = $keyInfo.Value }
            }
            Write-Host $result.Message -ForegroundColor Red
            Write-Host '  K. Re-enter the API key' -ForegroundColor Yellow
            Write-Host '  U. Change the Hudu URL' -ForegroundColor Yellow
            Write-Host '  Q. Cancel setup' -ForegroundColor Yellow
            $action = (Read-AmdConfirmedInput `
                -Prompt 'Choose K, U, or Q' `
                -RequireNonEmpty `
                -EmptyMessage 'Choose K, U, or Q and press Enter.').Trim().ToUpperInvariant()
            if ($action -eq 'U') { continue UrlEntry }
            if ($action -eq 'Q') { throw [OperationCanceledException]::new('Hudu configuration was cancelled by the user.') }
            if ($action -ne 'K') { Write-Host 'Unknown choice; the API key prompt will be shown again.' -ForegroundColor Yellow }
        }
    }
}

function Read-AxcientSettings {
    while ($true) {
        Write-Host "`nCreate or review Axcient API keys at: https://partner.axcient.com/settings/api-keys" -ForegroundColor Yellow
        $key = Read-AmdConfirmedInput `
            -Prompt 'Paste the Axcient API key' `
            -MaskInput `
            -RequireNonEmpty `
            -EmptyMessage 'Paste the Axcient API key and press Enter.'
        $keyInfo = ConvertTo-AmdNormalizedApiKey -Key $key
        $result = Test-AmdAxcientConnection -ApiKey $keyInfo.Value
        if ($result.Success) {
            Write-Host $result.Message -ForegroundColor Green
            return [pscustomobject]@{ ApiKey = $keyInfo.Value; Clients = @($result.Data) }
        }
        Write-Host $result.Message -ForegroundColor Red
        Write-Host 'You may paste a corrected key now; setup does not need to be restarted.' -ForegroundColor Yellow
    }
}

function Read-AmdStaleBackupHours {
    param([Parameter(Mandatory)][int]$CurrentHours)

    while ($true) {
        $raw = Read-AmdConfirmedInput -Prompt "Backup age warning threshold in hours [current: $CurrentHours]"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $CurrentHours }
        $hours = 0
        if ([int]::TryParse(
            $raw,
            [Globalization.NumberStyles]::None,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$hours
        ) -and $hours -ge 1 -and $hours -le 720) {
            return $hours
        }
        Write-Host 'Enter a whole number from 1 through 720 hours.' -ForegroundColor Red
    }
}

function Read-AmdTimeZoneSelection {
    param(
        [Parameter(Mandatory)][string]$CurrentTimeZoneId,
        [scriptblock]$ReadInput = { param($Prompt) Read-AmdConfirmedInput -Prompt $Prompt },
        [TimeZoneInfo[]]$AvailableTimeZones = [TimeZoneInfo]::GetSystemTimeZones()
    )

    $timeZones = @($AvailableTimeZones)
    $current = try {
        [TimeZoneInfo]::FindSystemTimeZoneById($CurrentTimeZoneId)
    }
    catch {
        [TimeZoneInfo]::Local
    }
    $listWasShown = $false
    $normalizeListEntry = {
        param([AllowEmptyString()][string]$Value)

        $normalized = $Value.Trim()
        $normalized = $normalized -replace '[\u2010-\u2015\u2212]', '-'
        $normalized = [regex]::Replace($normalized, '\s+', ' ')
        return $normalized
    }
    while ($true) {
        Write-Host "`nDashboard time zone" -ForegroundColor Magenta
        Write-Host "Current: $($current.DisplayName) [$($current.Id)]" -ForegroundColor Cyan
        Write-Host 'Enter L to list every available time zone, K to keep the current selection, a time-zone ID, or an exact display name. After listing, you may also enter its number or paste the entire row. A blank Enter is ignored so a leftover keystroke cannot skip this step.' -ForegroundColor Yellow
        $raw = [string](& $ReadInput 'Dashboard time zone')
        $selection = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($selection)) {
            Write-Host 'Type K to keep the current time zone, L to list, or a time-zone ID, then press Enter.' -ForegroundColor Red
            continue
        }
        if ($selection -eq 'K') {
            Write-Host "Dashboard timestamps will keep $($current.DisplayName)." -ForegroundColor Green
            return $current.Id
        }
        if ($selection -eq 'L') {
            $listWasShown = $true
            for ($index = 0; $index -lt $timeZones.Count; $index++) {
                $timeZone = $timeZones[$index]
                Write-Host ("  {0,3}. ID: {1}  |  Display name: {2}" -f ($index + 1), $timeZone.Id, $timeZone.DisplayName)
            }
            continue
        }

        $selected = $null
        try {
            $selected = [TimeZoneInfo]::FindSystemTimeZoneById($selection)
        }
        catch {
            $idMatches = @(
                $timeZones | Where-Object {
                    [string]::Equals($_.Id, $selection, [StringComparison]::OrdinalIgnoreCase)
                }
            )
            if ($idMatches.Count -eq 1) {
                $selected = $idMatches[0]
            }
        }
        if ($null -eq $selected) {
            $listedNumber = 0
            if ($listWasShown -and
                [int]::TryParse(
                    $selection,
                    [Globalization.NumberStyles]::None,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$listedNumber
                ) -and
                $listedNumber -ge 1 -and
                $listedNumber -le $timeZones.Count) {
                $selected = $timeZones[$listedNumber - 1]
            }
        }
        if ($null -eq $selected) {
            $displayMatches = @(
                $timeZones | Where-Object {
                    [string]::Equals($_.DisplayName, $selection, [StringComparison]::OrdinalIgnoreCase)
                }
            )
            if ($displayMatches.Count -gt 1) {
                Write-Host 'More than one time zone uses that display name. Enter the exact time-zone ID shown by L instead.' -ForegroundColor Red
                continue
            }
            if ($displayMatches.Count -eq 1) {
                $selected = $displayMatches[0]
            }
        }
        if ($null -eq $selected) {
            $normalizedSelection = & $normalizeListEntry $selection
            $rowMatches = @(
                for ($index = 0; $index -lt $timeZones.Count; $index++) {
                    $timeZone = $timeZones[$index]
                    $acceptedRows = @(
                        "$($timeZone.Id) - $($timeZone.DisplayName)"
                        "$($timeZone.Id) | $($timeZone.DisplayName)"
                        "ID: $($timeZone.Id) | Display name: $($timeZone.DisplayName)"
                        "$($index + 1). ID: $($timeZone.Id) | Display name: $($timeZone.DisplayName)"
                    )
                    if (@($acceptedRows | Where-Object {
                        [string]::Equals(
                            (& $normalizeListEntry $_),
                            $normalizedSelection,
                            [StringComparison]::OrdinalIgnoreCase
                        )
                    }).Count -gt 0) {
                        $timeZone
                    }
                }
            )
            if ($rowMatches.Count -eq 1) {
                $selected = $rowMatches[0]
            }
        }
        if ($null -ne $selected) {
            Write-Host "Dashboard timestamps will use $($selected.DisplayName)." -ForegroundColor Green
            return $selected.Id
        }
        Write-Host 'That time zone was not recognized. Enter L, then choose a listed number, copy the value after ID:, enter an exact display name, or paste the whole row.' -ForegroundColor Red
    }
}

function Set-DestinationSettings {
    param([Parameter(Mandatory)]$Config)

    Write-Host "`nMagic Dash settings" -ForegroundColor Magenta
    Write-Host 'Every matched Hudu company receives a Magic Dash. If you answer Y, each sync also checks unmatched Hudu companies and warns when one still has a dash this tool owns. It never deletes those dashes.' -ForegroundColor Yellow
    $Config.reportOrphanedDashes = Read-YesNo 'Warn when an unmatched Hudu company still has a Magic Dash this tool created?' $Config.reportOrphanedDashes
    $Config.staleBackupHours = Read-AmdStaleBackupHours -CurrentHours $Config.staleBackupHours
    $Config.timeZoneId = Read-AmdTimeZoneSelection -CurrentTimeZoneId $Config.timeZoneId -ReadInput $readRequiredInput
}

function Set-ProjectSchedule {
    param([Parameter(Mandatory)]$Config)

    $newHours = Read-AmdScheduleSelection -CurrentHours $Config.scheduleHours -ReadInput $readRequiredInput
    $result = Update-AmdScheduleConfiguration -Config $Config -NewHours $newHours -ConfigPath $configPath -RunScriptPath $runScript
    if ($null -eq $newHours) {
        Write-Host 'Automatic sync schedule is disabled in config.json and Task Scheduler.' -ForegroundColor Cyan
    }
    else {
        Write-Host "Scheduled task '$($result.Schedule.TaskName)' and config.json now use every $newHours hour(s)." -ForegroundColor Green
        if ($null -ne $result.Schedule.NextRunTime) {
            Write-Host "Next automatic run: $($result.Schedule.NextRunTime)." -ForegroundColor Cyan
        }
    }
}

function Read-AmdConfigWithKeyRecovery {
    param([Parameter(Mandatory)][string]$Path)

    try {
        return Read-AmdConfig -Path $Path
    }
    catch {
        if ($_.Exception.Message -notmatch 'API key.+could not be decrypted|could not be decrypted.+API key') {
            throw
        }
        Write-Host (Get-AmdSafeErrorText $_) -ForegroundColor Red
        if (-not (Read-YesNo 'Re-enter both API keys while preserving the remaining configuration?' $true)) {
            throw 'The protected API keys could not be opened and key recovery was cancelled.'
        }

        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 30 -ErrorAction Stop
        foreach ($propertyName in 'huduAPIKeyProtected', 'axcientAPIKeyProtected', 'huduAPIKey', 'axcientAPIKey') {
            if ($raw.PSObject.Properties.Name -contains $propertyName) {
                $raw.$propertyName = ''
            }
            else {
                $raw | Add-Member -NotePropertyName $propertyName -NotePropertyValue ''
            }
        }
        $recovered = & (Get-Module AxcientMagicDash) {
            param($InputObject)
            ConvertTo-AmdRuntimeConfig -InputObject $InputObject
        } $raw
        $hudu = Read-HuduSettings
        $axcient = Read-AxcientSettings
        $recovered = (Reset-AmdHuduScopedSettings -Config $recovered -NewBaseUrl $hudu.BaseUrl -NewApiKey $hudu.ApiKey).Config
        $recovered.axcientAPIKey = $axcient.ApiKey
        Save-AmdConfig -Config $recovered -Path $Path | Out-Null
        Write-Host 'The replacement API keys were validated and protected for this computer. Other configuration settings were preserved.' -ForegroundColor Green
        return $recovered
    }
}

function Invoke-MatchingWorkflow {
    param([Parameter(Mandatory)]$Config)

    Connect-AmdServices -Config $Config
    $recoveredOperationsProcessed = $false
    if (@($Config.pendingOperations).Count -gt 0) {
        Write-Host "`nRetrying previously journaled matching operations before opening the matcher..." -ForegroundColor Cyan
        $recoverySummary = & (Get-Module AxcientMagicDash) { New-AmdSyncSummary }
        Invoke-AmdPendingOperations -Config $Config -Summary $recoverySummary | Out-Null
        $recoveredOperationsProcessed = $recoverySummary.OperationResults.Count -gt 0
        Save-AmdConfig -Config $Config -Path $configPath | Out-Null
        $recoverySummary.CompletedUtc = [DateTime]::UtcNow
        Show-AmdSyncSummary -Summary $recoverySummary
        if (@($Config.pendingOperations).Count -gt 0) {
            $null = Resolve-AmdMissingMoveDestinations `
                -Config $Config `
                -ConfigPath $configPath `
                -ReadConfirmation { param($Prompt) Read-YesNo $Prompt $false }
        }
        if (@($Config.pendingOperations).Count -gt 0) {
            Write-Host 'The matching window was not opened because an earlier accepted move/delete operation still needs recovery. Correct the listed API problem and rerun run.ps1.' -ForegroundColor Red
            return [pscustomobject]@{ Cancelled = $false; Applied = $false; SyncHadErrors = $true; Config = $Config }
        }
    }
    Write-Host "`nLoading Hudu companies and Axcient clients..." -ForegroundColor Cyan
    $companies = @(Get-AmdHuduCompany -ErrorAction Stop | Sort-Object name, id)
    $clients = @(Get-AmdAxcientClient -ErrorAction Stop | Sort-Object name, id)
    $preWindowMatches = @($Config.matches)
    $preWindowExclusions = @($Config.autoMatchExclusions)
    $preWindowPendingOperations = @($Config.pendingOperations)
    $stagedMatches = @($Config.matches)

    if ($Config.autoMatch) {
        $before = $stagedMatches.Count
        $stagedMatches = @(Update-AmdAutomaticMatches -HuduCompanies $companies -AxcientClients $clients -Matches $stagedMatches -Exclusions @($Config.autoMatchExclusions))
        $added = $stagedMatches.Count - $before
        Write-Host "Exact-name automatch added $added match(es)." -ForegroundColor Green
    }

    Write-Host 'Opening the matching window. This window only stages matching decisions; API changes happen afterward in this console.' -ForegroundColor Yellow
    $matching = Show-AmdMatchingWindow -HuduCompanies $companies -AxcientClients $clients -Matches $stagedMatches
    if ($matching.Cancelled) {
        if ($recoveredOperationsProcessed) {
            Write-Host 'Matching was cancelled. No new matching decisions or newly queued actions were saved. Previously accepted recovery operations were processed before the window opened, as shown in the recovery summary.' -ForegroundColor Yellow
        }
        else {
            Write-Host 'Matching was cancelled. No matching decisions were saved and no queued move/delete actions were run.' -ForegroundColor Yellow
        }
        return [pscustomobject]@{ Cancelled = $true; Applied = $false; SyncHadErrors = $false; Config = $Config }
    }

    # Persist the intended matching state before any queued API mutation. If this
    # write fails, no delete/move action is allowed to start.
    $Config.matches = @($matching.Matches)
    $Config.autoMatchExclusions = @(
        Update-AmdMatchExclusions -ExistingExclusions @($Config.autoMatchExclusions) -Matches @($matching.Matches) -Operations @($matching.Operations)
    )
    $Config.pendingOperations = @($matching.Operations)
    $failureSummary = & (Get-Module AxcientMagicDash) { New-AmdSyncSummary }
    try {
        Save-AmdConfig -Config $Config -Path $configPath | Out-Null
    }
    catch {
        $Config.matches = $preWindowMatches
        $Config.autoMatchExclusions = $preWindowExclusions
        $Config.pendingOperations = $preWindowPendingOperations
        $failureSummary.Errors.Add("Matching decisions and their recovery journal could not be saved, so no queued backend action or full sync was started. $(Get-AmdSafeErrorText $_)")
        $failureSummary.CompletedUtc = [DateTime]::UtcNow
        Show-AmdSyncSummary -Summary $failureSummary
        return [pscustomobject]@{ Cancelled = $false; Applied = $false; SyncHadErrors = $true; Config = $Config }
    }

    Write-Host "`nRunning the full sync..." -ForegroundColor Cyan
    $syncResult = Invoke-AmdSync -Config $Config -AlreadyConnected -ConfigPath $configPath
    $finalSaved = $false
    try {
        Save-AmdConfig -Config $syncResult.Config -Path $configPath | Out-Null
        $finalSaved = $true
        Write-Host "Saved $(@($syncResult.Config.matches).Count) company match(es); $(@($syncResult.Config.pendingOperations).Count) backend operation(s) remain journaled." -ForegroundColor Green
    }
    catch {
        $syncResult.Summary.Errors.Add("The sync finished, but its final configuration could not be saved. $(Get-AmdSafeErrorText $_)")
    }
    finally {
        Show-AmdSyncSummary -Summary $syncResult.Summary
    }
    return [pscustomobject]@{
        Cancelled     = $false
        Applied       = $finalSaved
        SyncHadErrors = $syncResult.Summary.Errors.Count -gt 0
        Config        = $syncResult.Config
    }
}

function Show-CurrentConfiguration {
    param($Config)
    $dashboardTimeZone = try {
        [TimeZoneInfo]::FindSystemTimeZoneById([string]$Config.timeZoneId)
    }
    catch {
        $null
    }
    Write-Host "`nCurrent AXCIENT-MAGIC-DASH configuration" -ForegroundColor Magenta
    Write-Host "  Initial setup complete:    $($Config.setupComplete)"
    Write-Host "  Hudu URL:                 $($Config.huduBaseUrl)"
    Write-Host '  Hudu API key:             DPAPI-protected for this Windows computer'
    Write-Host '  Axcient API key:          DPAPI-protected for this Windows computer'
    Write-Host "  Report orphaned dashes:   $($Config.reportOrphanedDashes)"
    Write-Host "  Stale backup threshold:   $($Config.staleBackupHours) hour(s)"
    if ($null -ne $dashboardTimeZone) {
        Write-Host "  Dashboard time zone:      $($dashboardTimeZone.DisplayName) [$($dashboardTimeZone.Id)]"
    }
    else {
        Write-Host "  Dashboard time zone:      $($Config.timeZoneId) (unavailable on this computer)" -ForegroundColor Yellow
        Write-Host '  Time-zone action:         Use option 3 before syncing; dashboard writes fail closed until repaired.' -ForegroundColor Yellow
    }
    Write-Host "  Exact-name automatch:     $($Config.autoMatch)"
    Write-Host "  Automatch exclusions:     $(@($Config.autoMatchExclusions).Count)"
    Write-Host "  Company matches:          $(@($Config.matches).Count)"
    Write-Host "  Device asset layout:      $(if ($Config.assetLayoutId) { "$($Config.assetLayoutName) (ID $($Config.assetLayoutId))" } else { 'Not bound — use menu option 9' })"
    Write-Host "  Pending backend actions:  $(@($Config.pendingOperations).Count)"
    Write-Host "  Automatic schedule:       $(if ($Config.scheduleHours) { "Every $($Config.scheduleHours) hour(s)" } else { 'Disabled' })"
}

try {
# Inside the try, matching run.ps1: a failure preparing the module, the lock
# directory, or the verified snapshot is reported by this workflow's redacting handler
# instead of by the generic elevated-child handler.
Import-Module $modulePath -Force -DisableNameChecking
$lockPath = Initialize-AmdProjectLock
Initialize-AmdVerifiedModuleSnapshot | Out-Null
[Environment]::SetEnvironmentVariable('AMD_ELEVATION_STAGE', 'workflow', [EnvironmentVariableTarget]::Process)
$projectLock = Enter-AmdProjectLock -Path $lockPath -Purpose $(if ($Ongoing) { 'run menu' } else { 'setup' })
Clear-Host
if ($Ongoing) {
    Write-Host 'AXCIENT-MAGIC-DASH' -ForegroundColor Cyan
    Write-Host '==================' -ForegroundColor Cyan
    Write-Host 'Use this run menu for every action after first-time setup. Only company matching opens a graphical window.' -ForegroundColor Yellow
}
else {
    Write-Host 'AXCIENT-MAGIC-DASH First-Time Setup' -ForegroundColor Cyan
    Write-Host '===================================' -ForegroundColor Cyan
    Write-Host 'This setup runs once. After it finishes, use run.ps1 for every action.' -ForegroundColor Yellow
}

Import-AmdRequiredModules `
    -LocalModulePath $localModules `
    -Interactive `
    -ReadInput $readOptionalInput

if (-not (Test-Path -LiteralPath $configPath)) {
    $legacyPath = Join-Path (Split-Path $projectRoot -Parent) 'Hudu-Axcient-Dashboard\Deploy-StandAlone\config.json'
    if ((Test-Path -LiteralPath $legacyPath) -and (Read-YesNo 'A configuration from Hudu-Axcient-Dashboard was found. Import it into AXCIENT-MAGIC-DASH?' $true)) {
        $legacyImported = $false
        try {
            $legacy = Read-AmdConfig -Path $legacyPath
            Save-AmdConfig -Config $legacy -Path $configPath | Out-Null
            $legacyImported = $true
            $Ongoing = $true
            Write-Host 'Imported the old settings. API keys are now protected by this Windows computer.' -ForegroundColor Green
        }
        catch {
            Write-Host "The old configuration could not be imported: $(Get-AmdSafeErrorText $_)" -ForegroundColor Red
        }
        if ($legacyImported) {
            # Import is copy-only. The legacy deployment may still be active, so
            # changing its credentials here would disable it without rollback.
            Write-Host "The old project was left unchanged. Its plaintext API keys remain in '$legacyPath'; remove them manually only after that deployment is retired." -ForegroundColor Red
        }
    }
}
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "`nInitial setup" -ForegroundColor Magenta
    $hudu = Read-HuduSettings
    $axcient = Read-AxcientSettings
    $config = [pscustomobject][ordered]@{
        schemaVersion       = 2
        huduBaseUrl         = $hudu.BaseUrl
        huduAPIKey          = $hudu.ApiKey
        axcientAPIKey       = $axcient.ApiKey
        setupComplete       = $false
        autoMatch           = $true
        reportOrphanedDashes = $true
        staleBackupHours    = 24
        timeZoneId          = [TimeZoneInfo]::Local.Id
        scheduleHours       = $null
        taskName            = 'AXCIENT-MAGIC-DASH Sync'
        styling             = [pscustomobject]@{ dashHealthy = 'success'; dashWarning = 'danger' }
        matches             = @()
        autoMatchExclusions = @()
        pendingOperations   = @()
        assetLayoutId       = $null
        assetLayoutName     = $null
    }
    Set-AmdSensitiveValues -Values @($config.huduAPIKey, $config.axcientAPIKey)
    Connect-AmdHudu -InstanceUrl $config.huduBaseUrl -ApiKey $config.huduAPIKey -ErrorAction Stop
    Invoke-AmdUnownedLegacyMagicDashCleanup -ReadConfirmation {
        param($Prompt, $Default)
        Read-YesNo -Prompt $Prompt -Default $Default
    } | Out-Null
    $config = Complete-AmdAssetLayoutBinding -Config $config -ReadInput $readOptionalInput
    Set-DestinationSettings -Config $config
    Write-Host "`nExact-name automatch connects otherwise-unmatched clients only when one Hudu company has the same name. Explicitly deleted pairs stay excluded." -ForegroundColor Yellow
    $config.autoMatch = Read-YesNo 'Enable exact-name automatch on future runs?' $true
    $config.scheduleHours = Read-AmdScheduleSelection -CurrentHours $config.scheduleHours -ReadInput $readRequiredInput
    Save-AmdConfig -Config $config -Path $configPath | Out-Null
    Write-Host 'API keys, the device asset layout, and Magic Dash settings were saved. Company matching is next; if you cancel, continue later with run.ps1.' -ForegroundColor Cyan
    $workflow = Invoke-MatchingWorkflow -Config $config
    if ($workflow.Cancelled) {
        Write-Host 'Matching was cancelled. API keys, the device asset layout, and Magic Dash settings were saved. Continue with run.ps1.' -ForegroundColor Yellow
        Stop-AmdSetup -ExitCode 1 -FailureMessage 'Matching was cancelled after a draft configuration was saved. Continue with run.ps1.'
    }
    if (-not $workflow.Applied) {
        Write-Host 'Initial setup is incomplete because matching decisions or their recovery journal could not be finalized. Review the summary and rerun run.ps1.' -ForegroundColor Red
        Stop-AmdSetup -ExitCode 2 -FailureMessage 'Initial setup is incomplete because matching decisions or their recovery journal could not be finalized. Rerun run.ps1 to recover.'
    }
    $config = $workflow.Config
    if ($workflow.SyncHadErrors) {
        $config.setupComplete = $false
        Save-AmdConfig -Config $config -Path $configPath | Out-Null
        Write-Host 'Initial setup remains incomplete because the first sync reported errors. No automatic task was created; correct the listed errors and rerun run.ps1.' -ForegroundColor Yellow
        Stop-AmdSetup -ExitCode 2 -FailureMessage 'Initial setup remains incomplete because the first sync reported errors. Rerun run.ps1 after correcting the errors shown in the protected console.'
    }
    $finalization = Complete-AmdSetupScheduleFinalization `
        -Config $config `
        -ConfigPath $configPath `
        -RunScriptPath $runScript `
        -WasSetupComplete $false
    $config = $finalization.Config
    if (-not $finalization.Succeeded) {
        $scheduleError = Get-AmdSafeErrorText $finalization.ErrorRecord
        if ($finalization.CleanupErrors.Count -gt 0) {
            $safeCleanupErrors = @($finalization.CleanupErrors | ForEach-Object { ConvertTo-AmdRedactedText -Text $_ })
            throw "Setup and the first sync completed, but automatic scheduling failed and cleanup could not be fully verified. Original error: $scheduleError Cleanup error(s): $($safeCleanupErrors -join ' ')"
        }
        throw "Setup and the first sync completed, but the automatic schedule could not be created. The owned task was removed; your requested interval remains saved for retry after setup recovery. $scheduleError"
    }
    Write-Host 'Initial setup is complete.' -ForegroundColor Green
    exit 0
}

if (-not $Ongoing) {
    throw 'Existing configurations must be managed through run.ps1.'
}

try {
    $config = Read-AmdConfigWithKeyRecovery -Path $configPath
    Set-AmdSensitiveValues -Values @($config.huduAPIKey, $config.axcientAPIKey)
    # Rewrite immediately so legacy user-scoped DPAPI blobs are migrated to the
    # machine-scoped format required by logged-off S4U scheduled runs.
    Save-AmdConfig -Config $config -Path $configPath | Out-Null
}
catch {
    $safeError = Get-AmdSafeErrorText $_
    Write-Host $safeError -ForegroundColor Red
    Stop-AmdSetup -ExitCode 1 -FailureMessage $safeError
}

$sessionFailures = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$startupLayoutHealth = Resolve-AmdInteractiveAssetLayoutHealth -Config $config -OfferMissingRecovery
if ($startupLayoutHealth.Changed) {
    Save-AmdConfig -Config $config -Path $configPath | Out-Null
    Write-Host 'Recovered device asset layout setting saved immediately.' -ForegroundColor Green
}
if ($config.setupComplete) {
    try {
        $beforeSchedule = Get-AmdSchedule -TaskName $config.taskName
        $afterSchedule = Sync-AmdScheduleState -Config $config -RunScriptPath $runScript
        if ($beforeSchedule.Exists -ne $afterSchedule.Exists -or $beforeSchedule.Hours -ne $afterSchedule.Hours) {
            Write-Host 'Repaired Windows Task Scheduler so it matches config.json.' -ForegroundColor Green
        }
    }
    catch {
        $null = $sessionFailures.Add('Schedule')
        Write-Host "The saved schedule could not be reconciled with Windows Task Scheduler: $(Get-AmdSafeErrorText $_)" -ForegroundColor Red
        Write-Host 'You can correct or disable it with menu option 4.' -ForegroundColor Yellow
    }
}
else {
    $null = $sessionFailures.Add('InitialSetup')
    Write-Host 'This configuration contains an incomplete initial setup. Automatic scheduling is suppressed until company matching and a clean first sync finish through menu option 5.' -ForegroundColor Red
    try {
        $incompleteTask = Get-AmdSchedule -TaskName $config.taskName
        if ($incompleteTask.Exists) {
            Remove-AmdSchedule -TaskName $config.taskName | Out-Null
            Write-Host 'Removed the owned scheduled task until initial setup is complete.' -ForegroundColor Yellow
        }
    }
    catch {
        $null = $sessionFailures.Add('Schedule')
        Write-Host "The owned scheduled task could not be suppressed safely: $(Get-AmdSafeErrorText $_)" -ForegroundColor Red
    }
}

while ($true) {
    Show-CurrentConfiguration -Config $config
    Write-Host @'

What would you like to do?
  1. Change Hudu URL and Hudu API key
  2. Change Axcient API key
  3. Change Magic Dash settings (orphan reporting, stale threshold, and time zone)
  4. Change automatic run schedule
  5. Open company matching (then apply decisions and sync)
  6. Test both stored API connections
  7. Run a full sync now
  8. Enable or disable exact-name automatch
  9. Create, bind, or repair the Axcient device asset layout
  S. Save current settings and exit
  Q. Exit (accepted menu changes are saved immediately)
'@ -ForegroundColor Yellow
    while ($true) {
        $choice = (Read-AmdConfirmedInput `
            -Prompt 'Select an option' `
            -RequireNonEmpty `
            -EmptyMessage 'Choose 1 through 9, S, or Q, then press Enter.').Trim().ToUpperInvariant()
        if ($choice -match '^[1-9SQ]$') { break }
        Write-Host 'Choose 1 through 9, S, or Q.' -ForegroundColor Red
    }
    switch ($choice) {
        '1' {
            $hudu = Read-HuduSettings
            $reset = Reset-AmdHuduScopedSettings -Config $config -NewBaseUrl $hudu.BaseUrl -NewApiKey $hudu.ApiKey
            $config = $reset.Config
            Set-AmdSensitiveValues -Values @($config.huduAPIKey, $config.axcientAPIKey)
            if ($reset.ChangedInstance) {
                Write-Host 'The Hudu instance changed. Old company IDs, automatch exclusions, matches, and the device asset layout were cleared to prevent writing into unrelated records with the same numeric IDs.' -ForegroundColor Yellow
            }
            Save-AmdConfig -Config $config -Path $configPath | Out-Null
            $null = $sessionFailures.Remove('HuduConnection')
        }
        '2' {
            $axcient = Read-AxcientSettings
            $keyChanged = -not [string]::Equals([string]$config.axcientAPIKey, [string]$axcient.ApiKey, [StringComparison]::Ordinal)
            if ($keyChanged -and @($config.pendingOperations).Count -gt 0) {
                Write-Host 'The Axcient API key was not changed because matching move/delete operations are still pending. Finish or resolve those operations first.' -ForegroundColor Red
                continue
            }
            if ($keyChanged -and @($config.matches).Count -gt 0) {
                Write-Host 'Axcient does not expose a stable partner identity through this connection test. A key for another partner could make the saved Axcient client IDs point at unrelated clients.' -ForegroundColor Yellow
                if (-not (Read-YesNo 'Keep the existing company matches with this new Axcient key?' $false)) {
                    Write-Host 'The Axcient API key and existing matches were left unchanged.' -ForegroundColor Yellow
                    continue
                }
            }
            $config.axcientAPIKey = $axcient.ApiKey
            Set-AmdSensitiveValues -Values @($config.huduAPIKey, $config.axcientAPIKey)
            Save-AmdConfig -Config $config -Path $configPath | Out-Null
            $null = $sessionFailures.Remove('AxcientConnection')
        }
        '3' {
            Set-DestinationSettings -Config $config
            Save-AmdConfig -Config $config -Path $configPath | Out-Null
        }
        '4' {
            if ($config.setupComplete) {
                Set-ProjectSchedule -Config $config
                $null = $sessionFailures.Remove('Schedule')
                Write-Host 'Schedule setting saved immediately.' -ForegroundColor Green
            }
            else {
                $config.scheduleHours = Read-AmdScheduleSelection -CurrentHours $config.scheduleHours -ReadInput $readRequiredInput
                Save-AmdConfig -Config $config -Path $configPath | Out-Null
                Write-Host 'The preferred interval was saved, but its task remains disabled until initial setup completes through option 5.' -ForegroundColor Yellow
            }
        }
        '5' {
            $wasSetupComplete = [bool]$config.setupComplete
            $workflow = Invoke-MatchingWorkflow -Config $config
            $config = $workflow.Config
            if (-not $workflow.Cancelled -and -not $workflow.Applied) {
                Write-Host 'Matching changes were not fully finalized. Review the summary before leaving the run menu.' -ForegroundColor Red
            }
            if (-not $workflow.Cancelled) {
                if (-not $workflow.Applied -or $workflow.SyncHadErrors) {
                    $null = $sessionFailures.Add('Matching')
                }
                else {
                    $null = $sessionFailures.Remove('Matching')
                    $finalization = Complete-AmdSetupScheduleFinalization `
                        -Config $config `
                        -ConfigPath $configPath `
                        -RunScriptPath $runScript `
                        -WasSetupComplete $wasSetupComplete
                    $config = $finalization.Config
                    if ($finalization.Succeeded) {
                        foreach ($resolvedFailure in 'InitialSetup', 'Matching', 'Sync', 'Schedule', 'HuduConnection', 'AxcientConnection') {
                            $null = $sessionFailures.Remove($resolvedFailure)
                        }
                        if ($wasSetupComplete) {
                            Write-Host 'Matching and sync saved; the automatic schedule is reconciled.' -ForegroundColor Green
                        }
                        else {
                            Write-Host 'Initial setup recovery completed; automatic scheduling is now eligible to run.' -ForegroundColor Green
                        }
                        $nextSchedule = Get-AmdSchedule -TaskName $config.taskName
                        if ($null -ne $nextSchedule.NextRunTime) {
                            Write-Host "Next automatic run: $($nextSchedule.NextRunTime)." -ForegroundColor Cyan
                        }
                    }
                    else {
                        if ($finalization.PreservedCompletedSetup) {
                            $null = $sessionFailures.Add('Schedule')
                            Write-Host "Matching and sync completed, but the existing schedule could not be reconciled. The completed setup remains usable. $(Get-AmdSafeErrorText $finalization.ErrorRecord)" -ForegroundColor Red
                        }
                        else {
                            foreach ($cleanupError in @($finalization.CleanupErrors)) {
                                Write-Host (ConvertTo-AmdRedactedText -Text $cleanupError) -ForegroundColor Red
                            }
                            $null = $sessionFailures.Add('InitialSetup')
                            Write-Host "Matching and sync completed, but setup could not be finalized safely. $(Get-AmdSafeErrorText $finalization.ErrorRecord)" -ForegroundColor Red
                        }
                    }
                }
            }
        }
        '6' {
            $huduTest = Test-AmdHuduConnection -BaseUrl $config.huduBaseUrl -ApiKey $config.huduAPIKey
            Write-Host $huduTest.Message -ForegroundColor $(if ($huduTest.Success) { 'Green' } else { 'Red' })
            $axcientTest = Test-AmdAxcientConnection -ApiKey $config.axcientAPIKey
            Write-Host $axcientTest.Message -ForegroundColor $(if ($axcientTest.Success) { 'Green' } else { 'Red' })
            if (-not $huduTest.Success) {
                Write-Host 'Use option 1 to replace the Hudu URL/key.' -ForegroundColor Yellow
                $null = $sessionFailures.Add('HuduConnection')
            }
            else {
                $null = $sessionFailures.Remove('HuduConnection')
            }
            if (-not $axcientTest.Success) {
                Write-Host 'Use option 2 to replace the Axcient key.' -ForegroundColor Yellow
                $null = $sessionFailures.Add('AxcientConnection')
            }
            else {
                $null = $sessionFailures.Remove('AxcientConnection')
            }
        }
        '7' {
            if (-not $config.setupComplete) {
                Write-Host 'Initial setup is incomplete. Use option 5 to finish company matching and a clean first sync before running sync now.' -ForegroundColor Red
                $null = $sessionFailures.Add('InitialSetup')
                continue
            }
            try {
                $null = Sync-AmdScheduleState -Config $config -RunScriptPath $runScript
                $null = $sessionFailures.Remove('Schedule')
            }
            catch {
                $null = $sessionFailures.Add('Schedule')
                Write-Host "Warning: Task Scheduler could not be reconciled, but the requested manual sync will continue. $(Get-AmdSafeErrorText $_)" -ForegroundColor Yellow
            }
            Save-AmdConfig -Config $config -Path $configPath | Out-Null
            $sync = Invoke-AmdSync -Config $config -ConfigPath $configPath
            $config = $sync.Config
            try {
                Save-AmdConfig -Config $config -Path $configPath | Out-Null
            }
            catch {
                $sync.Summary.Errors.Add("The sync finished, but config.json could not be saved. $(Get-AmdSafeErrorText $_)")
            }
            finally {
                Show-AmdSyncSummary -Summary $sync.Summary
            }
            if ($sync.Summary.Errors.Count -gt 0) {
                $null = $sessionFailures.Add('Sync')
            }
            else {
                $null = $sessionFailures.Remove('Sync')
                $null = $sessionFailures.Remove('HuduConnection')
                $null = $sessionFailures.Remove('AxcientConnection')
            }
        }
        '8' {
            Write-Host 'Exact-name automatch affects only currently unmatched clients and never overrides an explicit match. Pairs explicitly deleted in the matching window remain excluded.' -ForegroundColor Yellow
            $config.autoMatch = Read-YesNo 'Enable exact-name automatch?' $config.autoMatch
            Save-AmdConfig -Config $config -Path $configPath | Out-Null
        }
        '9' {
            $layoutHealth = Resolve-AmdInteractiveAssetLayoutHealth -Config $config -OfferMissingRecovery
            if ($layoutHealth.Changed) {
                Save-AmdConfig -Config $config -Path $configPath | Out-Null
                Write-Host 'Device asset layout setting saved immediately.' -ForegroundColor Green
                continue
            }
            if ($layoutHealth.Status -eq 'Unbound') {
                Connect-AmdHudu -InstanceUrl $config.huduBaseUrl -ApiKey $config.huduAPIKey -ErrorAction Stop
                Invoke-AmdUnownedLegacyMagicDashCleanup -ReadConfirmation {
                    param($Prompt, $Default)
                    Read-YesNo -Prompt $Prompt -Default $Default
                } | Out-Null
                $config = Complete-AmdAssetLayoutBinding -Config $config -ReadInput $readOptionalInput
            }
            elseif ($layoutHealth.Status -eq 'NeedsRepair') {
                Add-AmdHuduAssetLayoutDetailsField -Id ([int64]$config.assetLayoutId) -Confirm:$false -ErrorAction Stop | Out-Null
                $verifiedLayout = Get-AmdHuduAssetLayout -Id ([int64]$config.assetLayoutId) -ErrorAction Stop
                $verifiedReady = & (Get-Module AxcientMagicDash) {
                    param($Layout)
                    Test-AmdAssetLayoutIsReady -Layout $Layout
                } $verifiedLayout
                if (-not $verifiedReady) {
                    throw "Hudu asset layout ID $($config.assetLayoutId) is still inactive or incompatible after repair. No configuration was changed."
                }
                $config.assetLayoutName = [string]$verifiedLayout.name
            }
            elseif ($layoutHealth.Status -ne 'Healthy') {
                Write-Host 'No layout change was made. Device assets remain disconnected until Hudu can verify the selected layout.' -ForegroundColor Yellow
                continue
            }
            Save-AmdConfig -Config $config -Path $configPath | Out-Null
            Write-Host 'Device asset layout setting saved immediately.' -ForegroundColor Green
        }
        'S' {
            Save-AmdConfig -Config $config -Path $configPath | Out-Null
            Write-Host 'Configuration saved.' -ForegroundColor Green
            $menuExitCode = if ($sessionFailures.Count -gt 0) { 2 } else { 0 }
            Stop-AmdSetup -ExitCode $menuExitCode -FailureMessage "Run menu exited with unresolved session failures: $(@($sessionFailures) -join ', ')."
        }
        'Q' {
            # A failed save is one of the session failures, so this must not
            # promise that everything from the session reached config.json.
            if ($sessionFailures.Count -gt 0) {
                Write-Host 'Exited with unresolved failures. Review the errors above; some of this session may not have been saved. Rerun run.ps1 to finish.' -ForegroundColor Red
            }
            else {
                Write-Host 'Exited. Accepted menu changes were already saved.' -ForegroundColor Yellow
            }
            $menuExitCode = if ($sessionFailures.Count -gt 0) { 2 } else { 0 }
            Stop-AmdSetup -ExitCode $menuExitCode -FailureMessage "Run menu exited with unresolved session failures: $(@($sessionFailures) -join ', ')."
        }
        default { Write-Host 'Choose 1 through 9, S, or Q.' -ForegroundColor Red }
    }
}
}
catch {
    $safeError = Get-AmdSafeErrorText $_
    $failureLocation = Get-AmdErrorSourceLocation -ErrorRecord $_
    $failedWorkflow = if ($Ongoing) { 'run menu' } else { 'setup' }
    Write-Host "`nAXCIENT-MAGIC-DASH $failedWorkflow could not complete: $safeError" -ForegroundColor Red
    Stop-AmdSetup -ExitCode 1 -FailureMessage "AXCIENT-MAGIC-DASH $failedWorkflow could not complete at ${failureLocation}: $safeError"
}
finally {
    # The lock functions come from the module, so releasing has to tolerate a run
    # that failed before the import and must not mask that original failure.
    if ($lockPath -and (Get-Command Exit-AmdProjectLock -ErrorAction SilentlyContinue)) {
        Exit-AmdProjectLock -LockStream $projectLock -Path $lockPath
    }
}
