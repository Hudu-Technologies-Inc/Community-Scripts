# Environment + HuduAPI module bootstrap.
#
# The Process/Procedure cmdlets this tool relies on (New-HuduProcedure,
# procedure_tasks, etc.) live in the Hudu fork of the HuduAPI module:
#   https://github.com/Hudu-Technologies-Inc/HuduAPI
#
# Rather than bundling the module, we download/clone it on first run (like the
# ITGlue / Files migration tools) and cache it locally for subsequent runs.
# Override the source with the HUDUAPI_REPOSITORY_URL / HUDUAPI_REPOSITORY_BRANCH
# / HUDUAPI_ZIP_URL environment variables if needed.

function Get-PSVersionCompatible {
    param([version]$RequiredPSversion = [version]"7.5.1")
    $current = (Get-Host).Version
    if ($current -lt $RequiredPSversion) {
        Write-Host "PowerShell $RequiredPSversion or newer is required. You have $current." -ForegroundColor Red
        throw "Incompatible PowerShell version."
    }
    Write-Host "PowerShell $current is compatible." -ForegroundColor Green
    return $current
}

function Test-HuduApiModuleLayout {
    param([Parameter(Mandatory)][string]$ModulePath)
    if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) { return $false }
    $dir = Split-Path -Path $ModulePath -Parent
    return ((Test-Path -LiteralPath (Join-Path $dir "Public") -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $dir "Private") -PathType Container))
}

function Get-GitHubRepositoryParts {
    param([Parameter(Mandatory)][string]$RepositoryUrl)
    if ($RepositoryUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$') { return $null }
    [pscustomobject]@{ Owner = $matches.owner; Repo = ($matches.repo -replace '\.git$', '') }
}

function Unblock-PathSafe {
    param([string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) {
            Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
            Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
        }
    } catch {}
}

# Locate the "...\HuduAPI\HuduAPI.psm1" inside an extracted/cloned tree.
function Find-HuduApiModuleInTree {
    param([Parameter(Mandatory)][string]$Root)
    $candidates = @(Get-Item -LiteralPath $Root -ErrorAction SilentlyContinue)
    $candidates += Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue
    foreach ($c in $candidates) {
        $psm1 = Join-Path $c.FullName "HuduAPI\HuduAPI.psm1"
        if (Test-HuduApiModuleLayout -ModulePath $psm1) { return (Split-Path $psm1 -Parent) }  # the HuduAPI module dir
    }
    return $null
}

# Download the fork as a zip from GitHub codeload and stage the module dir.
function Install-HuduApiFromZip {
    param([Parameter(Mandatory)][string]$RepoUrl, [Parameter(Mandatory)][string]$Branch,
          [string]$ZipUrl, [Parameter(Mandatory)][string]$DestModuleDir)
    if ([string]::IsNullOrWhiteSpace($ZipUrl)) {
        $parts = Get-GitHubRepositoryParts -RepositoryUrl $RepoUrl
        if (-not $parts) { throw "Zip install requires a github.com repo URL (or set HUDUAPI_ZIP_URL)." }
        $ZipUrl = "https://codeload.github.com/$($parts.Owner)/$($parts.Repo)/zip/refs/heads/$Branch"
    }
    $staging = Join-Path ([IO.Path]::GetTempPath()) "HuduAPI-zip-$([guid]::NewGuid().Guid)"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    $zip = Join-Path $staging "HuduAPI.zip"
    Invoke-WebRequest -Uri $ZipUrl -Headers @{ "User-Agent" = "Checklists-To-Processes" } -OutFile $zip -ErrorAction Stop | Out-Null
    Unblock-PathSafe -Path $zip
    $extract = Join-Path $staging "extract"
    Expand-Archive -Path $zip -DestinationPath $extract -Force -ErrorAction Stop
    $found = Find-HuduApiModuleInTree -Root $extract
    if (-not $found) { throw "Downloaded zip did not contain a complete HuduAPI module." }
    Copy-Item -LiteralPath $found -Destination $DestModuleDir -Recurse -Force -ErrorAction Stop
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}

# Clone the fork via git and stage the module dir.
function Install-HuduApiFromGit {
    param([Parameter(Mandatory)][string]$RepoUrl, [Parameter(Mandatory)][string]$Branch,
          [Parameter(Mandatory)][string]$DestModuleDir)
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { throw "git was not found on PATH." }
    $staging = Join-Path ([IO.Path]::GetTempPath()) "HuduAPI-git-$([guid]::NewGuid().Guid)"
    $old = $env:GIT_TERMINAL_PROMPT
    try {
        $env:GIT_TERMINAL_PROMPT = "0"
        & $git.Source clone --depth 1 --branch $Branch $RepoUrl $staging 2>$null
        if ($LASTEXITCODE -ne 0) { throw "git clone exited with code $LASTEXITCODE." }
    } finally { $env:GIT_TERMINAL_PROMPT = $old }
    $found = Find-HuduApiModuleInTree -Root $staging
    if (-not $found) { throw "Clone did not contain a complete HuduAPI module." }
    Copy-Item -LiteralPath $found -Destination $DestModuleDir -Recurse -Force -ErrorAction Stop
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}

function Set-HuduInstance {
    param([string]$HuduBaseURL, [string]$HuduAPIKey)
    while ([string]::IsNullOrWhiteSpace($HuduBaseURL)) {
        $HuduBaseURL = (Read-Host -Prompt 'Hudu base URL (e.g. https://myinstance.huducloud.com)').Trim()
        $HuduBaseURL = $HuduBaseURL -replace '[\\/]+$', ''
        $HuduBaseURL = $HuduBaseURL -replace '^(?!https://)', 'https://'
    }
    while ([string]::IsNullOrWhiteSpace($HuduAPIKey) -or $HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Hudu API key (from $HuduBaseURL/admin/api_keys)").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "That key is $($HuduAPIKey.Length) chars; a Hudu key should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

# Bootstraps the module (download/cache if missing) and authenticates.
# Returns the connected Hudu version.
function Initialize-HuduModule {
    param(
        [Parameter(Mandatory)][string]$ModuleCacheDir,   # where the fork is cached/imported from
        [string]$RepoUrl = ($env:HUDUAPI_REPOSITORY_URL ?? "https://github.com/Hudu-Technologies-Inc/HuduAPI.git"),
        [string]$Branch  = ($env:HUDUAPI_REPOSITORY_BRANCH ?? "master"),
        [string]$ZipUrl  = $env:HUDUAPI_ZIP_URL,
        [bool]$AllowGalleryFallback = $false,
        [version]$RequiredHuduVersion = [version]"2.41.0",
        [switch]$ForceRefresh,
        [string]$HuduBaseURL,
        [string]$HuduAPIKey
    )

    try { Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop }
    catch { Write-Warning "Could not set process execution policy: $($_.Exception.Message)" }
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {}
    $ProgressPreference = 'SilentlyContinue'

    # cached module dir layout: <ModuleCacheDir>\HuduAPI\{HuduAPI.psm1,Public,Private}
    $moduleDir = Join-Path $ModuleCacheDir "HuduAPI"
    $psm1 = Join-Path $moduleDir "HuduAPI.psm1"

    if ($ForceRefresh -and (Test-Path -LiteralPath $moduleDir)) {
        Remove-Item -LiteralPath $moduleDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-HuduApiModuleLayout -ModulePath $psm1)) {
        New-Item -ItemType Directory -Path $ModuleCacheDir -Force | Out-Null
        if (Test-Path -LiteralPath $moduleDir) { Remove-Item -LiteralPath $moduleDir -Recurse -Force -ErrorAction SilentlyContinue }

        $methods = @(
            @{ Name = "GitHub zip"; Script = { Install-HuduApiFromZip -RepoUrl $RepoUrl -Branch $Branch -ZipUrl $ZipUrl -DestModuleDir $moduleDir } }
            @{ Name = "git clone";  Script = { Install-HuduApiFromGit -RepoUrl $RepoUrl -Branch $Branch -DestModuleDir $moduleDir } }
        )
        $installed = $false
        foreach ($m in $methods) {
            try {
                Write-Host "Fetching HuduAPI module via $($m.Name) from $RepoUrl ($Branch)..." -ForegroundColor Cyan
                & $m.Script
                if (Test-HuduApiModuleLayout -ModulePath $psm1) { $installed = $true; break }
            } catch {
                Write-Warning "$($m.Name) failed: $($_.Exception.Message)"
                if (Test-Path -LiteralPath $moduleDir) { Remove-Item -LiteralPath $moduleDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        if ($installed) {
            Unblock-PathSafe -Path $moduleDir
            Write-Host "HuduAPI module cached at $moduleDir" -ForegroundColor Green
        }
    } else {
        Write-Host "Using cached HuduAPI module at $moduleDir" -ForegroundColor DarkGray
    }

    Remove-Module HuduAPI -Force -ErrorAction SilentlyContinue
    if (Test-HuduApiModuleLayout -ModulePath $psm1) {
        $psd1 = [System.IO.Path]::ChangeExtension($psm1, ".psd1")
        $importPath = if (Test-Path -LiteralPath $psd1 -PathType Leaf) { $psd1 } else { $psm1 }
        Import-Module $importPath -Force -ErrorAction Stop
        Write-Host "HuduAPI module imported from $importPath" -ForegroundColor Green
    }
    elseif ($AllowGalleryFallback) {
        Write-Warning "Falling back to PSGallery HuduAPI. Process/Procedure cmdlets may be missing on older versions."
        Install-Module HuduAPI -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module HuduAPI -Force -ErrorAction Stop
    }
    else {
        throw "Could not obtain the HuduAPI fork from $RepoUrl ($Branch). Check your internet/git access, or set HUDUAPI_ZIP_URL. You can also manually clone it into '$ModuleCacheDir'."
    }

    # sanity: the Process cmdlets we depend on must exist
    if (-not (Get-Command New-HuduProcedure -ErrorAction SilentlyContinue)) {
        throw "The loaded HuduAPI module does not provide New-HuduProcedure. The Hudu fork ($RepoUrl) is required."
    }

    Set-HuduInstance -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey

    $current = [version]((Get-HuduAppInfo).version)
    if ($current -lt $RequiredHuduVersion) {
        Write-Host "Hudu $RequiredHuduVersion+ is required for the Process (template/run) model. You have $current." -ForegroundColor Red
        throw "Incompatible Hudu version."
    }
    Write-Host "Connected to Hudu $current." -ForegroundColor Green
    return $current
}
