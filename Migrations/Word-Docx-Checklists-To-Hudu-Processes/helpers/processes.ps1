# Writes parsed checklist models into Hudu as Processes (a.k.a. "Procedures"
# in the HuduAPI module). Handles name-based dedupe and the subtask field that
# the stock New-HuduProcedureTask cmdlet does not expose (parent_task_id).

# Direct task create so we can set parent_task_id for subtasks.
function New-HuduProcessTaskEx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$ProcedureId,
        [string]$Description,
        [int]$Position,
        [Nullable[int]]$ParentTaskId
    )
    $task = @{ name = $Name; procedure_id = $ProcedureId }
    if ($PSBoundParameters.ContainsKey('Description') -and $Description) { $task.description = $Description }
    if ($PSBoundParameters.ContainsKey('Position')) { $task.position = $Position }
    if ($ParentTaskId) { $task.parent_task_id = [int]$ParentTaskId }

    $payload = @{ procedure_task = $task } | ConvertTo-Json -Depth 10
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/procedure_tasks" -Body $payload
        return ($res.procedure_task ?? $res)
    } catch {
        Write-Warning "Failed to create task '$Name' on process $ProcedureId : $($_.Exception.Message)"
        return $null
    }
}

# Find an existing process template by exact (normalized) name within scope.
function Find-ExistingProcess {
    param([Parameter(Mandatory)][string]$Name, [Nullable[int]]$CompanyId)
    $params = @{ Type = 'process'; Name = $Name }
    if ($CompanyId) { $params.CompanyId = [int]$CompanyId; $params.ProcessScope = 'company' }
    else            { $params.ProcessScope = 'global' }

    $found = @(Get-HuduProcedures @params)
    $target = Normalize-Text $Name
    return ($found | Where-Object { (Normalize-Text $_.name) -eq $target } | Select-Object -First 1)
}

# Create all tasks (and subtasks) for a process from a parsed model.
# Returns @{ Tasks; SubTasks } counts created.
function Add-ModelTasksToProcess {
    param(
        [Parameter(Mandatory)][int]$ProcedureId,
        [Parameter(Mandatory)]$Tasks
    )
    $created = 0; $subCreated = 0; $pos = 1
    foreach ($t in $Tasks) {
        $parentTask = New-HuduProcessTaskEx -Name $t.Name -ProcedureId $ProcedureId -Description $t.Description -Position $pos
        if (-not $parentTask) { $pos++; continue }
        $created++
        $pos++
        $subPos = 1
        foreach ($s in @($t.SubTasks)) {
            $sub = New-HuduProcessTaskEx -Name $s.Name -ProcedureId $ProcedureId -Description $s.Description `
                        -Position $subPos -ParentTaskId ([int]$parentTask.id)
            if ($sub) { $subCreated++ }
            $subPos++
        }
    }
    return @{ Tasks = $created; SubTasks = $subCreated }
}

# Add only tasks/subtasks that don't already exist (matched by normalized name).
function Update-ProcessTasksFromModel {
    param([Parameter(Mandatory)][int]$ProcedureId, [Parameter(Mandatory)]$Tasks)

    $existing = @(Get-HuduProcedureTasks -ProcedureId $ProcedureId)
    $topLevel = $existing | Where-Object { -not $_.parent_task_id }
    $byNameTop = @{}
    foreach ($e in $topLevel) { $byNameTop[(Normalize-Text $e.name)] = $e }

    $created = 0; $subCreated = 0
    $maxPos = ($topLevel | Measure-Object position -Maximum).Maximum
    $pos = ([int]($maxPos ?? 0)) + 1

    foreach ($t in $Tasks) {
        $key = Normalize-Text $t.Name
        $parent = $byNameTop[$key]
        if (-not $parent) {
            $parent = New-HuduProcessTaskEx -Name $t.Name -ProcedureId $ProcedureId -Description $t.Description -Position $pos
            if ($parent) { $created++; $pos++ } else { continue }
        }
        # existing subtasks under this parent
        $existingSubs = $existing | Where-Object { $_.parent_task_id -eq $parent.id }
        $subNames = @{}
        foreach ($s in $existingSubs) { $subNames[(Normalize-Text $s.name)] = $true }
        $subPos = ([int](($existingSubs | Measure-Object position -Maximum).Maximum ?? 0)) + 1
        foreach ($s in @($t.SubTasks)) {
            if ($subNames[(Normalize-Text $s.Name)]) { continue }
            $sub = New-HuduProcessTaskEx -Name $s.Name -ProcedureId $ProcedureId -Description $s.Description `
                        -Position $subPos -ParentTaskId ([int]$parent.id)
            if ($sub) { $subCreated++; $subPos++ }
        }
    }
    return @{ Tasks = $created; SubTasks = $subCreated }
}

function Clear-ProcessTasks {
    param([Parameter(Mandatory)][int]$ProcedureId)
    $existing = @(Get-HuduProcedureTasks -ProcedureId $ProcedureId)
    # Remove subtasks first, then parents, to avoid orphan issues.
    foreach ($t in ($existing | Where-Object { $_.parent_task_id } )) {
        Remove-HuduProcedureTask -Id $t.id -ErrorAction SilentlyContinue | Out-Null
    }
    foreach ($t in ($existing | Where-Object { -not $_.parent_task_id } )) {
        Remove-HuduProcedureTask -Id $t.id -ErrorAction SilentlyContinue | Out-Null
    }
}

# Main entry: create or reconcile a single process from a checklist model.
function Sync-ChecklistToProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Model,
        [Parameter(Mandatory)][string]$ProcessName,
        [Nullable[int]]$CompanyId,
        [ValidateSet("Skip","Update","Replace","Recreate")]
        [string]$OnExisting = "Skip",
        [switch]$DryRun
    )

    $counts = Get-ChecklistTaskCount -Model $Model
    $result = [pscustomobject]@{
        SourceFile      = $Model.SourceFile
        ProcessName     = $ProcessName
        CompanyId       = $CompanyId
        Action          = $null
        ProcessId       = $null
        TasksCreated    = 0
        SubTasksCreated = 0
        TasksInDoc      = $counts.Total
        Error           = $null
    }

    try {
        $existing = Find-ExistingProcess -Name $ProcessName -CompanyId $CompanyId

        if ($existing -and $OnExisting -eq "Skip") {
            $result.Action = "Skipped (exists)"; $result.ProcessId = $existing.id; return $result
        }

        if ($DryRun) {
            $result.Action = if ($existing) { "Would $OnExisting (exists)" } else { "Would create" }
            $result.ProcessId = $existing.id
            $result.TasksCreated = $counts.TopLevel
            $result.SubTasksCreated = $counts.SubTasks
            return $result
        }

        if ($existing -and $OnExisting -eq "Update") {
            $result.Action = "Updated"; $result.ProcessId = $existing.id
            $c = Update-ProcessTasksFromModel -ProcedureId ([int]$existing.id) -Tasks $Model.Tasks
            $result.TasksCreated = $c.Tasks; $result.SubTasksCreated = $c.SubTasks
            return $result
        }

        if ($existing -and $OnExisting -eq "Replace") {
            $result.Action = "Replaced"; $result.ProcessId = $existing.id
            Clear-ProcessTasks -ProcedureId ([int]$existing.id)
            $c = Add-ModelTasksToProcess -ProcedureId ([int]$existing.id) -Tasks $Model.Tasks
            $result.TasksCreated = $c.Tasks; $result.SubTasksCreated = $c.SubTasks
            return $result
        }

        # Create new (no existing, or OnExisting=Recreate)
        $newParams = @{ Name = $ProcessName }
        if ($Model.Description) { $newParams.Description = $Model.Description }
        if ($CompanyId) { $newParams.CompanyId = [int]$CompanyId }
        $proc = New-HuduProcedure @newParams
        if (-not $proc -or -not $proc.id) { throw "New-HuduProcedure returned no id." }

        $result.Action = if ($existing) { "Recreated" } else { "Created" }
        $result.ProcessId = $proc.id
        $c = Add-ModelTasksToProcess -ProcedureId ([int]$proc.id) -Tasks $Model.Tasks
        $result.TasksCreated = $c.Tasks; $result.SubTasksCreated = $c.SubTasks
        return $result
    }
    catch {
        $result.Action = "Error"; $result.Error = $_.Exception.Message
        return $result
    }
}
