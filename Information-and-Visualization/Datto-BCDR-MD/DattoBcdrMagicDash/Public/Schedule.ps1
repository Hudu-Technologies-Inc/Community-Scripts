function Get-DbmPwshExecutable {
    [CmdletBinding()]
    param()

    return Get-DbmCurrentPwshPath
}

function Get-DbmScheduledArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunScriptPath)

    $escapedScript = $RunScriptPath.Replace('"', '""')
    return "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$escapedScript`" -Scheduled"
}

$script:DbmTaskOwnershipMarker = 'DATTO-BCDR-MAGIC-DASH managed task v2'

function Get-DbmTaskOwnershipMarker {
    [CmdletBinding()]
    param()

    return $script:DbmTaskOwnershipMarker
}

function Test-DbmTaskOwnershipMarker {
    [CmdletBinding()]
    param([AllowNull()]$Description)

    $text = [string]$Description
    if ([string]::Equals($text, $script:DbmTaskOwnershipMarker, [StringComparison]::Ordinal)) { return $true }
    # v1 hashed the run.ps1 path into the marker, and the task name is a single
    # constant, so moving or renaming the project folder made the existing task
    # unrecognizable: it could then be neither repaired nor removed, and kept firing
    # at a path that no longer existed. The hash was only ever a path fingerprint,
    # never an authorization token, so any v1 marker is still this product's.
    return $text -match '^DATTO-BCDR-MAGIC-DASH managed task v1 \([0-9A-Fa-f]{64}\)$'
}

function Test-DbmTaskPrincipalMatch {
    [CmdletBinding()]
    param([AllowNull()]$PrincipalUserId)

    # Registration resolves the account to a SID, and Task Scheduler renders it back
    # as the bare account name - never the qualified 'DOMAIN\user' it was given. So
    # comparing what was registered against what is read back never matched, and the
    # task was torn down and re-registered on every setup and every manual run, each
    # time restarting its repetition clock and claiming it had repaired something.
    $actual = [string]$PrincipalUserId
    if ([string]::IsNullOrWhiteSpace($actual)) { return $false }
    $expectedSid = Get-DbmOperatingUserSid
    $actualSid = try { [Security.Principal.SecurityIdentifier]::new($actual) } catch { $null }
    if ($null -eq $actualSid) {
        $actualSid = try {
            [Security.Principal.NTAccount]::new($actual).Translate([Security.Principal.SecurityIdentifier])
        }
        catch { $null }
    }
    if ($null -ne $actualSid) { return $actualSid.Equals($expectedSid) }
    # A name that no longer resolves - a deleted account, or a domain that cannot be
    # reached right now - is still comparable. Task Scheduler commonly reports a
    # bare account name, but a qualified name must retain its domain identity: two
    # unreachable domains can contain different accounts with the same leaf name.
    $expectedName = [string](Get-DbmOperatingUserName)
    if ($actual.Contains('\')) {
        return [string]::Equals($actual, $expectedName, [StringComparison]::OrdinalIgnoreCase)
    }
    return [string]::Equals(
        $actual,
        $expectedName.Split('\')[-1],
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Get-DbmScheduleRepetitionDuration {
    [CmdletBinding()]
    param()

    # Task Scheduler validates <Duration> as a signed 32-bit number of seconds,
    # so roughly 24,855 days and above is rejected and the task never registers.
    # Ten years keeps the repetition effectively permanent while staying well
    # inside that limit, and Sync-DbmScheduleState re-registers if it ever lapses.
    return [TimeSpan]::FromDays(3650)
}

function ConvertTo-DbmTaskTimeSpan {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [TimeSpan]) { return $Value }
    try { return [Xml.XmlConvert]::ToTimeSpan([string]$Value) }
    catch { return $null }
}

function ConvertTo-DbmTaskDateTimeOffset {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try { return [DateTimeOffset]$Value }
    catch { return $null }
}

function Get-DbmSchedule {
    [CmdletBinding()]
    param([string]$TaskName = 'DATTO-BCDR-MAGIC-DASH Sync')

    if (-not $IsWindows) {
        return [pscustomobject]@{ Exists = $false; TaskName = $TaskName; State = 'Unavailable'; Hours = $null }
    }
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        throw 'Windows Task Scheduler commands are unavailable, so schedule state cannot be verified.'
    }

    $task = @(
        Get-ScheduledTask -ErrorAction Stop |
            Where-Object {
                [string]::Equals([string]$_.TaskName, $TaskName, [StringComparison]::OrdinalIgnoreCase) -and
                ($_.TaskPath -eq '\' -or [string]::IsNullOrWhiteSpace([string]$_.TaskPath))
            }
    ) | Select-Object -First 1
    if (-not $task) {
        return [pscustomobject]@{ Exists = $false; TaskName = $TaskName; State = 'Not configured'; Hours = $null }
    }

    $taskInfo = $null
    if (Get-Command Get-ScheduledTaskInfo -ErrorAction SilentlyContinue) {
        try {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath '\' -ErrorAction Stop
        }
        catch {
            Write-Verbose "Task Scheduler runtime information for '$TaskName' could not be read: $($_.Exception.Message)"
        }
    }

    $hours = $null
    $triggers = @($task.Triggers)
    $trigger = @($triggers | Where-Object Repetition | Select-Object -First 1)
    $timeSpan = $null
    if ($trigger -and $trigger[0].Repetition.Interval) {
        $timeSpan = ConvertTo-DbmTaskTimeSpan $trigger[0].Repetition.Interval
        if ($timeSpan) { $hours = $timeSpan.TotalHours }
    }

    [pscustomobject]@{
        Exists   = $true
        TaskName = $TaskName
        State    = [string]$task.State
        Description = [string]$task.Description
        Hours    = $hours
        Task     = $task
        Interval = $timeSpan
        Actions  = @($task.Actions)
        Triggers = $triggers
        Action   = @($task.Actions | Select-Object -First 1)
        Principal = $task.Principal
        Settings = $task.Settings
        NextRunTime = if ($null -ne $taskInfo) { $taskInfo.NextRunTime } else { $null }
        LastRunTime = if ($null -ne $taskInfo) { $taskInfo.LastRunTime } else { $null }
        LastTaskResult = if ($null -ne $taskInfo) { $taskInfo.LastTaskResult } else { $null }
    }
}

function Set-DbmSchedule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        $Hours,

        [Parameter(Mandatory)]
        [string]$RunScriptPath,

        [string]$TaskName = 'DATTO-BCDR-MAGIC-DASH Sync'
    )

    if (-not $IsWindows) {
        throw 'Windows Task Scheduler is required for automatic DATTO-BCDR-MAGIC-DASH runs.'
    }
    $Hours = ConvertTo-DbmScheduleHours $Hours
    if ($null -eq $Hours) { throw 'The schedule interval must be a whole-number integer from 1 through 48 hours.' }
    if (-not (Test-Path -LiteralPath $RunScriptPath -PathType Leaf)) {
        throw "Cannot create the schedule because run.ps1 was not found at: $RunScriptPath"
    }

    $pwshPath = Get-DbmPwshExecutable
    $ownershipMarker = Get-DbmTaskOwnershipMarker
    $existing = Get-DbmSchedule -TaskName $TaskName
    if ($existing.Exists -and -not (Test-DbmTaskOwnershipMarker -Description $existing.Description)) {
        throw "A scheduled task named '$TaskName' already exists in the root task folder but is not owned by this DATTO-BCDR-MAGIC-DASH installation. Rename or remove it manually; it will not be overwritten."
    }

    if (-not $PSCmdlet.ShouldProcess($TaskName, "Run every $Hours hour(s)")) {
        return
    }

    $arguments = Get-DbmScheduledArguments -RunScriptPath $RunScriptPath
    $actionParams = @{
        Execute  = $pwshPath
        Argument = $arguments
    }
    $workingDirectory = Split-Path -Parent $RunScriptPath
    if ((Get-Command New-ScheduledTaskAction).Parameters.ContainsKey('WorkingDirectory')) {
        $actionParams.WorkingDirectory = $workingDirectory
    }
    $action = New-ScheduledTaskAction @actionParams

    # The interactive setup/run menu owns the same cross-session lock as sync.
    # Starting two minutes after registration routinely raced a still-open matching
    # window and left the first unattended run failed for an entire interval.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours($Hours) `
        -RepetitionInterval (New-TimeSpan -Hours $Hours) `
        -RepetitionDuration (Get-DbmScheduleRepetitionDuration)

    $settingsParams = @{
        StartWhenAvailable = $true
        MultipleInstances  = 'IgnoreNew'
        ExecutionTimeLimit = (New-TimeSpan -Hours 2)
        RestartCount       = 2
        RestartInterval    = (New-TimeSpan -Minutes 5)
    }
    if ((Get-Command New-ScheduledTaskSettingsSet).Parameters.ContainsKey('RunOnlyIfNetworkAvailable')) {
        $settingsParams.RunOnlyIfNetworkAvailable = $true
    }
    $settings = New-ScheduledTaskSettingsSet @settingsParams
    $userId = Get-DbmOperatingUserName
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType S4U -RunLevel Limited

    try {
        Register-ScheduledTask -TaskName $TaskName `
            -TaskPath '\' `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description $ownershipMarker `
            -Force `
            -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Windows could not create or update the scheduled task '$TaskName'. Run PowerShell as an administrator if Task Scheduler reports access denied. $($_.Exception.Message)"
    }

    return Get-DbmSchedule -TaskName $TaskName
}

function Remove-DbmSchedule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Ownership no longer depends on where the project lives, so removal does not
        # need the script path and must keep working after the folder is moved.
        [string]$TaskName = 'DATTO-BCDR-MAGIC-DASH Sync'
    )

    if (-not $IsWindows) {
        return $false
    }
    if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        throw 'Windows Task Scheduler commands are unavailable, so the existing schedule cannot be disabled safely.'
    }
    $current = Get-DbmSchedule -TaskName $TaskName
    if (-not $current.Exists) {
        return $false
    }
    if (-not (Test-DbmTaskOwnershipMarker -Description $current.Description)) {
        throw "The scheduled task '$TaskName' is not owned by this DATTO-BCDR-MAGIC-DASH installation and will not be removed."
    }
    if ($PSCmdlet.ShouldProcess($TaskName, 'Remove automatic sync schedule')) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
        return $true
    }
    return $false
}

function Sync-DbmScheduleState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$RunScriptPath
    )

    $taskName = if ($Config.taskName) { [string]$Config.taskName } else { 'DATTO-BCDR-MAGIC-DASH Sync' }
    if ($null -eq $Config.scheduleHours) {
        $current = Get-DbmSchedule -TaskName $taskName
        if ($current.Exists) { Remove-DbmSchedule -TaskName $taskName | Out-Null }
        return Get-DbmSchedule -TaskName $taskName
    }

    $desired = [int]$Config.scheduleHours
    $current = Get-DbmSchedule -TaskName $taskName
    $expectedExecutable = Get-DbmPwshExecutable
    $expectedArguments = Get-DbmScheduledArguments -RunScriptPath $RunScriptPath
    $expectedWorkingDirectory = Split-Path -Parent $RunScriptPath
    $actions = @($current.Actions)
    $triggers = @($current.Triggers)
    $action = @($actions | Select-Object -First 1)
    $principal = $current.Principal
    $settings = $current.Settings
    $workingDirectoryMatches = if ((Get-Command New-ScheduledTaskAction).Parameters.ContainsKey('WorkingDirectory')) {
        $action.Count -eq 1 -and [string]::Equals([string]$action[0].WorkingDirectory, $expectedWorkingDirectory, [StringComparison]::OrdinalIgnoreCase)
    }
    else { $true }
    $networkSettingMatches = if ((Get-Command New-ScheduledTaskSettingsSet).Parameters.ContainsKey('RunOnlyIfNetworkAvailable')) {
        [bool]$settings.RunOnlyIfNetworkAvailable
    }
    else { $true }
    $repetitionDuration = if ($triggers.Count -eq 1) {
        ConvertTo-DbmTaskTimeSpan $triggers[0].Repetition.Duration
    }
    else { $null }
    $triggerClass = if ($triggers.Count -eq 1 -and $triggers[0].CimClass) {
        [string]$triggers[0].CimClass.CimClassName
    }
    else { '' }
    $startBoundary = if ($triggers.Count -eq 1) {
        ConvertTo-DbmTaskDateTimeOffset $triggers[0].StartBoundary
    }
    else { $null }
    $triggerWindowMatches = $false
    if ($null -ne $startBoundary -and $null -ne $repetitionDuration) {
        try {
            $now = [DateTimeOffset]::Now
            $triggerWindowMatches =
                $startBoundary -le $now.AddHours($desired).AddMinutes(10) -and
                $startBoundary.Add($repetitionDuration) -gt $now
        }
        catch {
            Write-Verbose "The scheduled trigger boundaries could not be evaluated: $($_.Exception.Message)"
        }
    }
    $definitionMatches =
        $current.Exists -and
        $current.State -ne 'Disabled' -and
        (Test-DbmTaskOwnershipMarker -Description $current.Description) -and
        $current.Interval -eq [TimeSpan]::FromHours($desired) -and
        $repetitionDuration -eq (Get-DbmScheduleRepetitionDuration) -and
        $actions.Count -eq 1 -and
        $triggers.Count -eq 1 -and
        [bool]$triggers[0].Enabled -and
        $triggerClass -eq 'MSFT_TaskTimeTrigger' -and
        $triggerWindowMatches -and
        [string]::Equals([string]$action[0].Execute, $expectedExecutable, [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$action[0].Arguments, $expectedArguments, [StringComparison]::Ordinal) -and
        $workingDirectoryMatches -and
        (Test-DbmTaskPrincipalMatch -PrincipalUserId $principal.UserId) -and
        [string]$principal.LogonType -eq 'S4U' -and
        [string]$principal.RunLevel -eq 'Limited' -and
        [bool]$settings.StartWhenAvailable -and
        [string]$settings.MultipleInstances -eq 'IgnoreNew' -and
        (ConvertTo-DbmTaskTimeSpan $settings.ExecutionTimeLimit) -eq [TimeSpan]::FromHours(2) -and
        [int]$settings.RestartCount -eq 2 -and
        (ConvertTo-DbmTaskTimeSpan $settings.RestartInterval) -eq [TimeSpan]::FromMinutes(5) -and
        $networkSettingMatches

    if ($definitionMatches) { return $current }
    return Set-DbmSchedule -Hours $desired -RunScriptPath $RunScriptPath -TaskName $taskName
}

function Complete-DbmSetupScheduleFinalization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$RunScriptPath,
        [Parameter(Mandatory)][bool]$WasSetupComplete
    )

    try {
        Sync-DbmScheduleState -Config $Config -RunScriptPath $RunScriptPath | Out-Null
        $Config.setupComplete = $true
        Save-DbmConfig -Config $Config -Path $ConfigPath | Out-Null
        return [pscustomobject]@{
            Succeeded                 = $true
            PreservedCompletedSetup   = $WasSetupComplete
            Config                    = $Config
            ErrorRecord               = $null
            CleanupErrors             = @()
        }
    }
    catch {
        $finalizationError = $_
        if ($WasSetupComplete) {
            $Config.setupComplete = $true
            return [pscustomobject]@{
                Succeeded                 = $false
                PreservedCompletedSetup   = $true
                Config                    = $Config
                ErrorRecord               = $finalizationError
                CleanupErrors             = @()
            }
        }

        $Config.setupComplete = $false
        $cleanupErrors = [System.Collections.Generic.List[string]]::new()
        try {
            Save-DbmConfig -Config $Config -Path $ConfigPath | Out-Null
        }
        catch {
            $cleanupErrors.Add("config.json could not be marked incomplete: $($_.Exception.Message)")
        }
        try {
            $partialTask = Get-DbmSchedule -TaskName $Config.taskName
            if ($partialTask.Exists) {
                Remove-DbmSchedule -TaskName $Config.taskName | Out-Null
            }
        }
        catch {
            $cleanupErrors.Add("the partial scheduled task could not be removed: $($_.Exception.Message)")
        }
        return [pscustomobject]@{
            Succeeded                 = $false
            PreservedCompletedSetup   = $false
            Config                    = $Config
            ErrorRecord               = $finalizationError
            CleanupErrors             = @($cleanupErrors)
        }
    }
}

function Update-DbmScheduleConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [AllowNull()]$NewHours,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$RunScriptPath
    )

    $NewHours = ConvertTo-DbmScheduleHours $NewHours
    $oldHours = $Config.scheduleHours
    $Config.scheduleHours = $NewHours
    Save-DbmConfig -Config $Config -Path $ConfigPath | Out-Null

    try {
        $state = Sync-DbmScheduleState -Config $Config -RunScriptPath $RunScriptPath
        return [pscustomobject]@{ Config = $Config; Schedule = $state }
    }
    catch {
        $scheduleError = $_
        $Config.scheduleHours = $oldHours
        try {
            Save-DbmConfig -Config $Config -Path $ConfigPath | Out-Null
            Sync-DbmScheduleState -Config $Config -RunScriptPath $RunScriptPath | Out-Null
        }
        catch {
            throw "The schedule change failed and its previous state could not be fully restored. Original error: $($scheduleError.Exception.Message). Restore error: $($_.Exception.Message)"
        }
        throw "The schedule change failed and the previous config/task state was restored. $($scheduleError.Exception.Message)"
    }
}

function Read-DbmScheduleSelection {
    [CmdletBinding()]
    param(
        [AllowNull()][Nullable[int]]$CurrentHours,
        [scriptblock]$ReadInput = { param($Prompt) Read-Host $Prompt }
    )

    while ($true) {
        Write-Host "`nAutomatic sync schedule" -ForegroundColor Magenta
        Write-Host 'The scheduled task runs run.ps1 automatically, even when you forget to run it manually.' -ForegroundColor Yellow
        Write-Host 'Choose every 1 through 8 hours, or enter a custom whole number up to 48 hours.' -ForegroundColor Yellow
        if ($null -ne $CurrentHours) {
            Write-Host "Current schedule: every $CurrentHours hour(s)." -ForegroundColor Cyan
        }
        else {
            Write-Host 'Current schedule: disabled.' -ForegroundColor Cyan
        }

        Write-Host @'
  0. Disable automatic runs
  1. Every 1 hour
  2. Every 2 hours
  3. Every 3 hours
  4. Every 4 hours
  5. Every 5 hours
  6. Every 6 hours
  7. Every 7 hours
  8. Every 8 hours
  C. Custom interval (1-48 hours)
'@
        $choiceValue = & $ReadInput 'Select an option'
        if ($null -eq $choiceValue) {
            throw [IO.EndOfStreamException]::new(
                'Interactive input ended before the schedule choice was answered. Run this command in an interactive PowerShell console and try again.'
            )
        }
        $choice = [string]$choiceValue
        $choice = $choice.Trim()

        if ($choice -eq '0') { return $null }
        if ($choice -match '^[1-8]$') { return [int]$choice }
        if ($choice -match '^(?i)c(?:ustom)?$') {
            $customValue = & $ReadInput 'Enter a whole number of hours from 1 through 48'
            if ($null -eq $customValue) {
                throw [IO.EndOfStreamException]::new(
                    'Interactive input ended before the custom interval was answered. Run this command in an interactive PowerShell console and try again.'
                )
            }
            $custom = [string]$customValue
            $parsed = 0
            if ([int]::TryParse($custom.Trim(), [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 48) {
                return $parsed
            }
            Write-Host 'That interval is not valid. Enter a whole number from 1 through 48. Longer intervals can make backup status too stale.' -ForegroundColor Red
            continue
        }

        Write-Host 'Choose 0 through 8, or C for a custom interval.' -ForegroundColor Red
    }
}
