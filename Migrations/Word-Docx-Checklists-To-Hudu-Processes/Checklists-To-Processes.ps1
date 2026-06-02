<#
.SYNOPSIS
Convert numbered Microsoft Word "checklist" documents into Hudu Processes.

.DESCRIPTION
Point this at a local folder of .docx checklists (e.g. a SharePoint / OneDrive
library synced into Explorer). Each document becomes one Hudu Process; each
numbered/bulleted item becomes an ordered task, and indented sub-items become
subtasks. Re-running is idempotent at the process level (existing processes are
skipped by default).

.PARAMETER TargetDocumentDir
Folder containing the checklist .docx files. Prompted if omitted.

.PARAMETER Filter
File name filter / wildcard (e.g. "*.docx", "1*"). Default: all supported docs
whose name starts with a number (configurable in config.ps1).

.PARAMETER Recurse
Search subdirectories.

.PARAMETER DestinationStrategy
GlobalTemplate | SingleCompany | VariousCompanies | ByFolderName | ByFileName.
Prompted if omitted.

.PARAMETER SubItemHandling
Subtask (default) | Description | TopLevel. How indented sub-items are mapped.

.PARAMETER OnExisting
Skip (default) | Update | Replace | Recreate. Behaviour when a process of the
same name already exists in the target scope.

.PARAMETER OnNoCompanyMatch
Prompt (default) | Skip | Global. Used by ByFolderName / ByFileName when no
company name matches.

.PARAMETER DryRun
Parse and report what would happen without writing anything to Hudu.

.EXAMPLE
. .\Checklists-To-Processes.ps1 -TargetDocumentDir 'C:\Sync\Team Checklists' -DestinationStrategy GlobalTemplate

.EXAMPLE
. .\Checklists-To-Processes.ps1 -TargetDocumentDir 'X:\Clients' -Recurse -DestinationStrategy ByFolderName -OnExisting Update
#>
[CmdletBinding()]
param(
    [string]$TargetDocumentDir,
    [string]$Filter,
    [switch]$Recurse,
    [ValidateSet("GlobalTemplate","SingleCompany","VariousCompanies","ByFolderName","ByFileName")]
    [string]$DestinationStrategy,
    [ValidateSet("Subtask","Description","TopLevel")]
    [string]$SubItemHandling,
    [ValidateSet("Skip","Update","Replace","Recreate")]
    [string]$OnExisting,
    [ValidateSet("Prompt","Skip","Global")]
    [string]$OnNoCompanyMatch,
    [int]$MaxItems = 1000,
    [int]$MaxDepth = 5,
    [switch]$DryRun,
    [string]$HuduBaseURL,
    [string]$HuduAPIKey
)

$workdir = $PSScriptRoot

# ---- Load config + helpers -------------------------------------------------
. (Join-Path $workdir "config.ps1")
foreach ($h in @("general.ps1","init.ps1","docx.ps1","processes.ps1","destination.ps1")) {
    . (Join-Path $workdir "helpers\$h")
}

# Apply config defaults where parameters were not supplied
if (-not $SubItemHandling)  { $SubItemHandling  = $script:DefaultSubItemHandling }
if (-not $OnExisting)       { $OnExisting       = $script:DefaultOnExisting }
if (-not $OnNoCompanyMatch) { $OnNoCompanyMatch = $script:DefaultOnNoCompanyMatch }

# ---- Logging / output ------------------------------------------------------
$runStamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputDir  = Get-EnsuredPath -path (Join-Path $workdir "runs\$runStamp")
$script:LogFile = Join-Path $outputDir "run.log"
Set-Content -Path $script:LogFile -Value "Checklists-To-Processes run $runStamp"

Set-PrintAndLog -message "=== Checklists -> Hudu Processes ===" -Color Magenta
Get-PSVersionCompatible | Out-Null

# ---- Connect to Hudu -------------------------------------------------------
# The HuduAPI fork (with Process/Procedure cmdlets) is downloaded on first run
# and cached under .huduapi\ for subsequent runs.
$moduleCacheDir = Join-Path $workdir ".huduapi"
$huduVersion = Initialize-HuduModule -ModuleCacheDir $moduleCacheDir -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey

# ---- Resolve source folder + files ----------------------------------------
while ([string]::IsNullOrWhiteSpace($TargetDocumentDir) -or -not (Test-Path -LiteralPath $TargetDocumentDir -PathType Container)) {
    $TargetDocumentDir = (Read-Host "Enter the folder containing your checklist .docx files").Trim('"',' ')
}

$gciParams = @{ LiteralPath = $TargetDocumentDir; File = $true }
if ($Recurse) { $gciParams.Recurse = $true; $gciParams.Depth = $MaxDepth }

$allFiles = Get-ChildItem @gciParams | Where-Object {
    $script:SupportedExtensions -contains $_.Extension.ToLowerInvariant()
}

# Apply name filter
if ($Filter) {
    $allFiles = $allFiles | Where-Object { $_.Name -like $Filter }
} else {
    $allFiles = $allFiles | Where-Object { $_.BaseName -match $script:NumberedNamePattern }
}

$allFiles = @($allFiles | Sort-Object FullName)
if ($allFiles.Count -eq 0) {
    Set-PrintAndLog -message "No matching checklist documents found in $TargetDocumentDir." -Color Red
    return
}
if ($allFiles.Count -gt $MaxItems) {
    Set-PrintAndLog -message "Found $($allFiles.Count) files; capping at MaxItems=$MaxItems." -Color Yellow
    $allFiles = $allFiles[0..($MaxItems-1)]
}
Set-PrintAndLog -message "Found $($allFiles.Count) checklist document(s)." -Color Green

# ---- Destination strategy --------------------------------------------------
if (-not $DestinationStrategy) {
    $opt = Select-ObjectFromList -objects @(
        [pscustomobject]@{ name="Global templates (available to all companies)"; key="GlobalTemplate" }
        [pscustomobject]@{ name="A single Hudu company (all docs)"; key="SingleCompany" }
        [pscustomobject]@{ name="Choose a company per document"; key="VariousCompanies" }
        [pscustomobject]@{ name="Match company by parent FOLDER name"; key="ByFolderName" }
        [pscustomobject]@{ name="Match company by FILE name"; key="ByFileName" }
    ) -message "How should these processes be scoped?"
    $DestinationStrategy = $opt.key
}

$singleCompanyId = $null; $singleCompanyName = $null
if ($DestinationStrategy -eq "SingleCompany") {
    $picked = Select-ObjectFromList -objects (Get-AllHuduCompaniesCached) -message "Select the company for ALL documents" -AllowNull
    if ($picked) { $singleCompanyId = [int]$picked.id; $singleCompanyName = $picked.name }
    else { $DestinationStrategy = "GlobalTemplate" }
}

Set-PrintAndLog -message "Strategy=$DestinationStrategy | SubItems=$SubItemHandling | OnExisting=$OnExisting | DryRun=$DryRun" -Color DarkCyan

# ---- Process each document -------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($file in $allFiles) {
    $i++
    $pct = Get-PercentDone -Current $i -Total $allFiles.Count
    Set-PrintAndLog -message "[$pct%] ($i/$($allFiles.Count)) $($file.Name)" -Color White

    try {
        $model = ConvertTo-ChecklistModel -Path $file.FullName -SubItemHandling $SubItemHandling -TitleStyleHints $script:TitleStyleHints
    } catch {
        Set-PrintAndLog -message "  Parse failed: $($_.Exception.Message)" -Color Red
        $results.Add([pscustomobject]@{ SourceFile=$file.FullName; Action="Parse error"; Error=$_.Exception.Message; TasksCreated=0; SubTasksCreated=0 }) | Out-Null
        continue
    }

    $counts = Get-ChecklistTaskCount -Model $model
    if ($counts.Total -eq 0) {
        Set-PrintAndLog -message "  No checklist items detected; skipping." -Color Yellow
        $results.Add([pscustomobject]@{ SourceFile=$file.FullName; Action="No items"; TasksCreated=0; SubTasksCreated=0 }) | Out-Null
        continue
    }

    # Process name: doc title, else cleaned file name
    $procName = if ($model.Title) { Get-CleanProcessName -Raw $model.Title } else { Get-CleanProcessName -Raw $file.Name -IsFileName }

    # Destination
    $dest = Resolve-Destination -FilePath $file.FullName -Strategy $DestinationStrategy `
                -SingleCompanyId $singleCompanyId -SingleCompanyName $singleCompanyName `
                -Threshold $script:CompanyMatchThreshold -OnNoMatch $OnNoCompanyMatch
    if ($dest.Skip) {
        Set-PrintAndLog -message "  Skipped (no company match, OnNoCompanyMatch=Skip)." -Color Yellow
        $results.Add([pscustomobject]@{ SourceFile=$file.FullName; ProcessName=$procName; Action="Skipped (no company)"; TasksCreated=0; SubTasksCreated=0 }) | Out-Null
        continue
    }

    Set-PrintAndLog -message "  '$procName' -> $($dest.CompanyName) | $($counts.TopLevel) tasks, $($counts.SubTasks) subtasks" -Color Gray

    $res = Sync-ChecklistToProcess -Model $model -ProcessName $procName -CompanyId $dest.CompanyId -OnExisting $OnExisting -DryRun:$DryRun
    $res | Add-Member -NotePropertyName CompanyName -NotePropertyValue $dest.CompanyName -Force
    Set-PrintAndLog -message "  -> $($res.Action) (process id $($res.ProcessId)); created $($res.TasksCreated) tasks / $($res.SubTasksCreated) subtasks" -Color $(if ($res.Action -eq "Error") { "Red" } else { "Green" })
    $results.Add($res) | Out-Null
}

# ---- Summary ---------------------------------------------------------------
$summaryPath = Join-Path $outputDir "summary.json"
$results | ConvertTo-Json -Depth 8 | Out-File -FilePath $summaryPath -Encoding UTF8

$created  = @($results | Where-Object { $_.Action -in @("Created","Recreated") }).Count
$updated  = @($results | Where-Object { $_.Action -in @("Updated","Replaced") }).Count
$skipped  = @($results | Where-Object { "$($_.Action)" -like "Skipped*" -or $_.Action -eq "No items" }).Count
$errored  = @($results | Where-Object { $_.Action -in @("Error","Parse error") }).Count
$totTasks = ($results | Measure-Object TasksCreated -Sum).Sum
$totSubs  = ($results | Measure-Object SubTasksCreated -Sum).Sum

Set-PrintAndLog -message ""
Set-PrintAndLog -message "=== Done ===" -Color Magenta
Set-PrintAndLog -message "Created: $created | Updated/Replaced: $updated | Skipped: $skipped | Errors: $errored" -Color Magenta
Set-PrintAndLog -message "Tasks created: $totTasks | Subtasks created: $totSubs" -Color Magenta
Set-PrintAndLog -message "Summary: $summaryPath" -Color Magenta
