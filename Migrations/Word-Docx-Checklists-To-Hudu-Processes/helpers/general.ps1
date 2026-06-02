# General utilities shared across the Checklists-To-Processes tool.
# Several of these are adapted from the Files-Hudu-Migration project so the
# behavior (prompts, logging, fuzzy company matching) stays consistent.

function Set-PrintAndLog {
    param (
        [string]$message,
        [Alias("ForegroundColor")]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color = "Gray"
    )
    $logline = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    Write-Host $message -ForegroundColor $Color
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logline -ErrorAction SilentlyContinue
    }
}

function Get-YesNoResponse {
    param([string]$message)
    do {
        $response = (Read-Host "$message (y/n)")
        $response = if ($null -ne $response) { $response.ToLower() } else { "" }
        if ($response -in @('y','yes')) { return $true }
        elseif ($response -in @('n','no')) { return $false }
        else { Write-Host "Please enter 'y' or 'n'." -ForegroundColor Red }
    } while ($true)
}

function Select-ObjectFromList {
    param($objects, $message, [switch]$AllowNull, [string]$NullLabel = "None / Global (no company)")
    $objects = @($objects)
    while ($true) {
        if ($AllowNull) { Write-Host "0: $NullLabel" -ForegroundColor DarkGray }
        for ($i = 0; $i -lt $objects.Count; $i++) {
            $o = $objects[$i]
            $label = if ($null -ne $o.OptionMessage) { $o.OptionMessage }
                     elseif ($null -ne $o.name) { $o.name }
                     else { "$o" }
            Write-Host "$($i+1): $label" -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }
        $choice = Read-Host $message
        if (-not ($choice -as [int]) -and $choice -ne "0") {
            Write-Host "Invalid input. Enter a number." -ForegroundColor Red; continue
        }
        $choice = [int]$choice
        if ($choice -eq 0 -and $AllowNull) { return $null }
        if ($choice -ge 1 -and $choice -le $objects.Count) { return $objects[$choice - 1] }
        Write-Host "Invalid selection." -ForegroundColor Red
    }
}

function Get-PercentDone {
    param([int]$Current, [int]$Total)
    if ($Total -le 0) { return 100 }
    return [Math]::Min(100, [Math]::Round(($Current / $Total) * 100, 1))
}

function Get-EnsuredPath {
    param([string]$path)
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path (Resolve-Path .).Path "debug"
    }
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
    }
    return $path
}

# Clean a raw title/filename into a friendly process name:
# strips extension, leading numbering ("01 - ", "1. ", "12)_", "1.2.3 "),
# underscores/dashes -> spaces, collapses whitespace.
function Get-CleanProcessName {
    param([string]$Raw, [switch]$IsFileName)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "Untitled Process" }
    $name = $Raw
    if ($IsFileName) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
    }
    # strip leading numbering tokens: 1  1.  1)  1-  01_  1.2.3  etc.
    $name = [regex]::Replace($name, '^\s*\d+(\.\d+)*\s*[\.\)\-_:]*\s*', '')
    $name = $name -replace '[_]+', ' '
    $name = ($name -replace '\s{2,}', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return ($Raw -replace '[_]+',' ').Trim() }
    return $name
}

# ---- Fuzzy matching (adapted from Files-Hudu-Migration) -------------------

function Normalize-Text {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s = $s.Trim().ToLowerInvariant()
    $s = [regex]::Replace($s, '[\s_\-]+', ' ')
    $formD = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    ($sb.ToString()).Normalize([System.Text.NormalizationForm]::FormC)
}

function Get-Similarity {
    param([string]$A, [string]$B)
    $a = [string](Normalize-Text $A)
    $b = [string](Normalize-Text $B)
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 1.0 }
    if ([string]::IsNullOrEmpty($a) -or  [string]::IsNullOrEmpty($b)) { return 0.0 }
    $n = $a.Length; $m = $b.Length
    if ($n -eq 0) { return [double]($m -eq 0) }
    if ($m -eq 0) { return 0.0 }
    $d = New-Object 'int[,]' ($n+1), ($m+1)
    for ($i = 0; $i -le $n; $i++) { $d[$i,0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0,$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $ai = $a[$i-1]
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($ai -eq $b[$j-1]) { 0 } else { 1 }
            $del = [int]$d[$i,$j-1] + 1
            $ins = [int]$d[$i-1,$j] + 1
            $sub = [int]$d[$i-1,$j-1] + $cost
            $d[$i,$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }
    $dist = [double]$d[$n,$m]
    return 1.0 - ($dist / [Math]::Max($n,$m))
}

# Pick the best-matching object from $choices whose $prop is most similar to
# $Name, provided it clears $Threshold. Returns $null if nothing qualifies.
function Find-BestByName {
    param([string]$Name, [array]$choices, [string]$prop = 'name', [double]$Threshold = 0.90)
    if ([string]::IsNullOrWhiteSpace($Name) -or -not $choices) { return $null }
    $scored = $choices |
        Where-Object { -not [string]::IsNullOrEmpty($_.$prop) } |
        ForEach-Object {
            [pscustomobject]@{ Choice = $_; Score = (Get-Similarity -A $Name -B $_.$prop) }
        } |
        Where-Object { $_.Score -ge $Threshold } |
        Sort-Object Score -Descending |
        Select-Object -First 1
    return $scored.Choice
}
