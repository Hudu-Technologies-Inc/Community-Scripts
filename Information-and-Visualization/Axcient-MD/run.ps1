[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName = 'Schedule')]
    [switch]$Schedule,

    [Parameter(ParameterSetName = 'Sync')]
    [switch]$Sync,

    [Parameter(ParameterSetName = 'Scheduled')]
    [switch]$Scheduled,

    [switch]$SuppressExitPause
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
        Write-Verbose "The console input buffer could not be cleared in this host: $($_.Exception.Message)"
    }
}

function Read-AmdConfirmedInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$RequireNonEmpty,
        [string]$EmptyMessage = 'Enter a value and press Enter.'
    )

    while ($true) {
        Clear-AmdPendingConsoleInput
        $value = Read-Host $Prompt
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

$readRequiredInput = { param($Prompt) Read-AmdConfirmedInput -Prompt $Prompt -RequireNonEmpty }

if ($Schedule -and [Console]::IsInputRedirected) {
    throw 'Schedule changes are interactive and cannot read piped or redirected input. Open an interactive PowerShell console and run run.ps1 -Schedule again.'
}

if ($PSVersionTable.PSVersion -lt [version]'7.2') {
    $pwshHelper = Join-Path $PSScriptRoot 'AxcientMagicDash\Private\Resolve-AmdPwsh72.ps1'
    . $pwshHelper
    $verifiedPwsh = Resolve-AmdMicrosoftPwsh72Path

    if ([string]::IsNullOrWhiteSpace($verifiedPwsh)) {
        $message = 'AXCIENT-MAGIC-DASH requires Microsoft PowerShell 7.2 or newer. Install PowerShell 7 from https://aka.ms/powershell-release?tag=stable and run run.ps1 again.'
        Write-Host $message -ForegroundColor Red
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            [Windows.MessageBox]::Show($message, 'AXCIENT-MAGIC-DASH', 'OK', 'Error') | Out-Null
        }
        catch {
            Read-AmdConfirmedInput -Prompt 'Press Enter to close' | Out-Null
        }
        exit 1
    }

    $firstRunSetupExpected = -not $Scheduled -and
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'config.json') -PathType Leaf)
    $forwardedArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) {
        $forwardedArguments.Add($argument)
    }
    if ($Schedule) { $forwardedArguments.Add('-Schedule') }
    if ($Sync) { $forwardedArguments.Add('-Sync') }
    if ($Scheduled) { $forwardedArguments.Add('-Scheduled') }
    $forwardedArguments.Add('-SuppressExitPause')
    & $verifiedPwsh @forwardedArguments
    $childExitCode = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    if (-not $SuppressExitPause -and -not $Scheduled -and
        ($childExitCode -ne 0 -or $firstRunSetupExpected)) {
        if ($childExitCode -eq 0) {
            Write-Host "`nAXCIENT-MAGIC-DASH setup finished successfully." -ForegroundColor Green
            Read-AmdConfirmedInput -Prompt 'Press Enter to close setup' | Out-Null
        }
        else {
            Write-Host "`nAXCIENT-MAGIC-DASH failed with exit code $childExitCode." -ForegroundColor Red
            Read-AmdConfirmedInput -Prompt 'Press Enter after reviewing the error above' | Out-Null
        }
    }
    exit $childExitCode
}

$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'AXCIENT-MAGIC-DASH requires Windows.'
}

$elevationPath = Join-Path $PSScriptRoot 'AxcientMagicDash\Private\Elevation.ps1'
. $elevationPath

function Write-AmdRunFailureStatusSafely {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)

    try {
        Write-AmdElevationFailureStatus -Message $Message
    }
    catch {
        $statusError = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
        Write-Warning "The elevated failure status could not be recorded: $statusError" -WarningAction Continue
    }
}

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

$openRunMenu = -not $Schedule -and -not $Sync -and -not $Scheduled
if ($openRunMenu) {
    $setupScriptPath = Join-Path $projectRoot 'setup.ps1'
    if (-not (Test-Path -LiteralPath $setupScriptPath -PathType Leaf)) {
        throw "The ongoing run menu could not start because setup.ps1 is missing from '$projectRoot'. Restore the complete distribution."
    }
    $hasConfiguration = Test-Path -LiteralPath (Join-Path $projectRoot 'config.json') -PathType Leaf
    if ($hasConfiguration) {
        & $setupScriptPath -Ongoing -SuppressExitPause:$SuppressExitPause
    }
    else {
        Write-Host "`nNo configuration exists yet. Starting first-time setup..." -ForegroundColor Yellow
        & $setupScriptPath -SuppressExitPause:$SuppressExitPause
    }
    exit $(if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE })
}

if (-not $Scheduled -and -not $isVerifiedElevation) {
    $preElevationModulePath = Join-Path $PSScriptRoot 'AxcientMagicDash\AxcientMagicDash.psd1'
    $preElevationModules = Join-Path $PSScriptRoot 'Modules'
    $preElevationRuntime = Join-Path $PSScriptRoot 'Runtime'
    if (-not (Test-Path -LiteralPath $preElevationRuntime -PathType Container)) {
        throw 'The bundled Python Runtime folder is missing. Restore the complete AXCIENT-MAGIC-DASH distribution and rerun run.ps1.'
    }
    $firstRunConfigPath = Join-Path $projectRoot 'config.json'
    if (-not (Test-Path -LiteralPath $firstRunConfigPath -PathType Leaf)) {
        $setupScriptPath = Join-Path $projectRoot 'setup.ps1'
        if (-not (Test-Path -LiteralPath $setupScriptPath -PathType Leaf)) {
            $missingSetupMessage = "Initial setup is required, but setup.ps1 is missing from '$projectRoot'. Restore the complete distribution."
            Write-Host "`n$missingSetupMessage" -ForegroundColor Red
            if (-not $SuppressExitPause) {
                Read-AmdConfirmedInput -Prompt 'Press Enter after reviewing the error above' | Out-Null
            }
            exit 1
        }
        if ($isAdministrator) {
            if (-not (Test-Path -LiteralPath (Join-Path $preElevationModules 'AxcientAPI') -PathType Container)) {
                $adminSetupMessage = 'Close this administrator window and run run.ps1 from a normal PowerShell 7 window so project-local dependencies can be prepared before verified elevation.'
                Write-Host "`n$adminSetupMessage" -ForegroundColor Red
                if (-not $SuppressExitPause) {
                    Read-AmdConfirmedInput -Prompt 'Press Enter after reviewing the error above' | Out-Null
                }
                exit 1
            }
            $setupExitCode = 1
            try {
                $setupExitCode = Start-AmdElevatedProcess `
                    -ScriptPath $setupScriptPath `
                    -WorkingDirectory $projectRoot `
                    -Sta
            }
            catch {
                $safeSetupError = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
                Write-Host "`nAXCIENT-MAGIC-DASH could not start or finish verified setup: $safeSetupError" -ForegroundColor Red
            }
            if (-not $SuppressExitPause) {
                if ($setupExitCode -eq 0) {
                    Write-Host "`nAXCIENT-MAGIC-DASH setup finished successfully." -ForegroundColor Green
                    Read-AmdConfirmedInput -Prompt 'Press Enter to close setup' | Out-Null
                }
                else {
                    Write-Host "`nAXCIENT-MAGIC-DASH setup failed with exit code $setupExitCode." -ForegroundColor Red
                    Read-AmdConfirmedInput -Prompt 'Press Enter after reviewing the error above' | Out-Null
                }
            }
            exit $setupExitCode
        }
        Write-Host "`nNo configuration exists yet. Starting AXCIENT-MAGIC-DASH setup now..." -ForegroundColor Yellow
        & $setupScriptPath -SuppressExitPause:$SuppressExitPause
        $setupExitCode = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
        exit $setupExitCode
    }
    if (-not $isAdministrator) {
        Import-Module $preElevationModulePath -Force -DisableNameChecking
        Import-AmdRequiredModules -LocalModulePath $preElevationModules -ProjectLocalOnly
        Remove-Module AxcientMagicDash -Force
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $preElevationModules 'AxcientAPI') -PathType Container)) {
        throw 'Close this administrator window and run run.ps1 from a normal PowerShell 7 window so project-local dependencies can be prepared before verified elevation.'
    }
    $forwardedArguments = [System.Collections.Generic.List[string]]::new()
    if ($Schedule) { $forwardedArguments.Add('-Schedule') }
    if ($Sync) { $forwardedArguments.Add('-Sync') }
    $elevationParameters = @{
        ScriptPath       = $PSCommandPath
        WorkingDirectory = $PSScriptRoot
    }
    if ($forwardedArguments.Count -gt 0) {
        $elevationParameters['ForwardedArguments'] = @($forwardedArguments)
    }
    $elevatedExitCode = 1
    try {
        $elevatedExitCode = Start-AmdElevatedProcess @elevationParameters
    }
    catch {
        $safeElevationError = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
        Write-Host "`nAXCIENT-MAGIC-DASH could not start or finish the elevated operation: $safeElevationError" -ForegroundColor Red
    }
    if ($elevatedExitCode -ne 0 -and -not $SuppressExitPause) {
        Write-Host "`nAXCIENT-MAGIC-DASH failed with exit code $elevatedExitCode." -ForegroundColor Red
        Read-AmdConfirmedInput -Prompt 'Press Enter after reviewing the error above' | Out-Null
    }
    exit $elevatedExitCode
}

$modulePath = Join-Path $PSScriptRoot 'AxcientMagicDash\AxcientMagicDash.psd1'
$configPath = Join-Path $projectRoot 'config.json'
$localModules = Join-Path $PSScriptRoot 'Modules'
# Task Scheduler has to receive the durable project script. Under verified
# elevation $PSCommandPath is the protected copy that is deleted when the
# elevated child exits, and its path also changes the task ownership marker.
$runScriptPath = Join-Path $projectRoot 'run.ps1'
$taskName = 'AXCIENT-MAGIC-DASH Sync'
$transcriptStarted = $false
$pendingTranscriptPath = $null
$scheduledFailureLogPath = $null
$lockStream = $null
$lockPath = $null

function Set-PrivateLogDirectoryAcl {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $acl = [Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true, $false)
        $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $propagation = [Security.AccessControl.PropagationFlags]::None
        $allow = [Security.AccessControl.AccessControlType]::Allow
        $identities = @(
            Get-AmdOperatingUserSid
            [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
            [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
        )
        foreach ($identity in $identities) {
            $rule = [Security.AccessControl.FileSystemAccessRule]::new(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance,
                $propagation,
                $allow
            )
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "Scheduled logs could not be restricted to the current user, SYSTEM, and local administrators. Review permissions on '$Path'. $(ConvertTo-AmdRedactedText -Text $_.Exception.Message)" -WarningAction Continue
        return $false
    }
}

function Enter-AmdScheduledProjectLock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Purpose = 'scheduled sync',
        [int]$TimeoutMinutes = 15,
        [int]$RetrySeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    while ($true) {
        try {
            return Enter-AmdProjectLock -Path $Path -Purpose $Purpose
        }
        catch {
            $message = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
            if ($message -notmatch 'Another AXCIENT-MAGIC-DASH process is already running') { throw }
            if ([DateTime]::UtcNow.AddSeconds($RetrySeconds) -gt $deadline) {
                throw "The scheduled sync waited $TimeoutMinutes minute(s) for another AXCIENT-MAGIC-DASH process to finish, then stopped safely without overlapping writes."
            }
            Write-Warning "Another AXCIENT-MAGIC-DASH process holds the project lock; scheduled sync will retry in $RetrySeconds seconds." -WarningAction Continue
            Start-Sleep -Seconds $RetrySeconds
        }
    }
}

try {
    Import-Module $modulePath -Force -DisableNameChecking
    $lockPath = Initialize-AmdProjectLock
    Initialize-AmdVerifiedModuleSnapshot | Out-Null
    [Environment]::SetEnvironmentVariable('AMD_ELEVATION_STAGE', 'workflow', [EnvironmentVariableTarget]::Process)

    if ($Scheduled) {
        $logDirectory = Join-Path $projectRoot 'logs'
        if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $logDirectory -Force
        }
        $secureLogging = Set-PrivateLogDirectoryAcl -Path $logDirectory
        try {
            $expiredLogs = @(
                Get-ChildItem -LiteralPath $logDirectory -Filter 'sync-*.log' -File -ErrorAction Stop |
                    Where-Object LastWriteTimeUtc -lt ([DateTime]::UtcNow.AddDays(-30))
            )
            foreach ($expiredLog in $expiredLogs) {
                try {
                    Remove-Item -LiteralPath $expiredLog.FullName -Force -ErrorAction Stop
                }
                catch {
                    Write-Warning "An expired scheduled-sync log could not be removed. Review permissions on '$logDirectory'; sync will continue." -WarningAction Continue
                }
            }
        }
        catch {
            Write-Warning "Scheduled-sync log retention could not enumerate '$logDirectory'. Logs older than 30 days may remain; sync will continue." -WarningAction Continue
        }
        if ($secureLogging) {
            $pendingTranscriptPath = Join-Path $logDirectory "sync-$((Get-Date).ToString('yyyyMMdd-HHmmss')).log"
            $scheduledFailureLogPath = $pendingTranscriptPath
        }
        else {
            Write-Warning 'The scheduled sync will continue without a transcript so customer names are not written to a broadly accessible folder.' -WarningAction Continue
        }
    }

    if ($Scheduled) {
        $lockStream = Enter-AmdScheduledProjectLock -Path $lockPath
    }
    else {
        $lockStream = Enter-AmdProjectLock -Path $lockPath -Purpose $(if ($Schedule) { 'schedule change' } else { 'manual sync' })
    }

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "config.json does not exist. Run '$projectRoot\setup.ps1' once before running the sync."
    }
    $config = Read-AmdConfig -Path $configPath
    Set-AmdSensitiveValues -Values @($config.huduAPIKey, $config.axcientAPIKey)
    if ($Scheduled -and -not [string]::IsNullOrWhiteSpace($pendingTranscriptPath)) {
        # Register both secrets before a transcript can capture a later error.
        Start-Transcript -Path $pendingTranscriptPath -Force | Out-Null
        $transcriptStarted = $true
    }
    if (-not $config.setupComplete) {
        throw 'Initial setup is incomplete. Run run.ps1 and use company matching to finish recovery before running or scheduling sync.'
    }
    if ($config.taskName) { $taskName = $config.taskName }
    if ($Scheduled -and $null -eq $config.scheduleHours) {
        Write-Host 'This orphaned scheduled launch was ignored because automatic runs are disabled in config.json.' -ForegroundColor Yellow
        exit 0
    }

    if ($Schedule) {
        $hours = Read-AmdScheduleSelection -CurrentHours $config.scheduleHours -ReadInput $readRequiredInput
        $scheduleResult = Update-AmdScheduleConfiguration -Config $config -NewHours $hours -ConfigPath $configPath -RunScriptPath $runScriptPath
        if ($null -eq $hours) {
            Write-Host 'Automatic schedule is disabled in config.json and Task Scheduler.' -ForegroundColor Cyan
        }
        else {
            Write-Host "Scheduled task '$($scheduleResult.Schedule.TaskName)' and config.json now use every $hours hour(s)." -ForegroundColor Green
            if ($null -ne $scheduleResult.Schedule.NextRunTime) {
                Write-Host "Next automatic run: $($scheduleResult.Schedule.NextRunTime)." -ForegroundColor Cyan
            }
        }
        exit 0
    }

    if (-not $Scheduled) {
        try {
            $beforeSchedule = Get-AmdSchedule -TaskName $taskName
            $afterSchedule = Sync-AmdScheduleState -Config $config -RunScriptPath $runScriptPath
            if ($beforeSchedule.Exists -ne $afterSchedule.Exists -or $beforeSchedule.Hours -ne $afterSchedule.Hours) {
                Write-Host 'Repaired Windows Task Scheduler so it matches config.json.' -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Warning: Task Scheduler could not be reconciled, but the requested manual sync will continue. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Import-AmdRequiredModules -LocalModulePath $localModules

    Write-Host "Connecting to Hudu at $($config.huduBaseUrl)" -ForegroundColor Cyan
    $result = Invoke-AmdSync -Config $config -ConfigPath $configPath
    try {
        Save-AmdConfig -Config $result.Config -Path $configPath | Out-Null
    }
    catch {
        $result.Summary.Errors.Add("The sync finished, but config.json could not be saved. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
    }
    finally {
        Show-AmdSyncSummary -Summary $result.Summary
    }

    if ($result.Summary.Errors.Count -gt 0) {
        $failureDetails = ConvertTo-AmdRedactedText -Text ((@($result.Summary.Errors) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        Write-AmdRunFailureStatusSafely -Message "AXCIENT-MAGIC-DASH sync completed with errors. $failureDetails"
        exit 2
    }
    exit 0
}
catch {
    $failureLocation = Get-AmdErrorSourceLocation -ErrorRecord $_
    # Elevation.ps1 is dot-sourced before the module, so this bounded form is still
    # available when the module import itself is what failed: it redacts registered
    # secrets when they exist and strips credential-shaped tokens either way, which
    # is better than discarding the only diagnostic this run produced.
    $failureMessage = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
    Write-Host "`nAXCIENT-MAGIC-DASH could not complete: $failureMessage" -ForegroundColor Red
    if ($Scheduled) {
        # $ErrorActionPreference is 'Stop' here, so a bare Write-Error would be
        # terminating and would skip the status write and the exit code below.
        Write-Error $failureMessage -ErrorAction Continue
        if (-not $transcriptStarted -and -not [string]::IsNullOrWhiteSpace($scheduledFailureLogPath)) {
            try {
                $failureLine = "{0:o} Scheduled sync failed before the full transcript started: {1}" -f [DateTimeOffset]::Now, $failureMessage
                Add-Content -LiteralPath $scheduledFailureLogPath -Value $failureLine -Encoding utf8 -ErrorAction Stop
            }
            catch {
                Write-Warning 'The redacted scheduled failure log could not be written.' -WarningAction Continue
            }
        }
    }
    Write-AmdRunFailureStatusSafely -Message "AXCIENT-MAGIC-DASH could not complete at ${failureLocation}: $failureMessage"
    exit 1
}
finally {
    if ($lockPath -and (Get-Command Exit-AmdProjectLock -ErrorAction SilentlyContinue)) {
        Exit-AmdProjectLock -LockStream $lockStream -Path $lockPath
    }
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { Write-Verbose "The scheduled transcript was already stopped: $($_.Exception.Message)" }
    }
}
