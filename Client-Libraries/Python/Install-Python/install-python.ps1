[CmdletBinding()]
param(
    [switch]$ForceRecreateVenv
)

$ErrorActionPreference = "Stop"

# When this script is streamed into Invoke-Expression, $PSScriptRoot is empty.
# Fall back to the caller's current directory so .venv is created where the user runs it.
$ScriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    (Get-Location).ProviderPath
} else {
    $PSScriptRoot
}

function Get-PythonCommand {
    $candidates = @()

    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) { $candidates += $pyCmd.Source }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) { $candidates += $pythonCmd.Source }

    $candidates += @(
        "$env:LocalAppData\Programs\Python\Python314\python.exe",
        "$env:ProgramFiles\Python314\python.exe",
        "$env:ProgramFiles\Python\Python314\python.exe"
    )

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [Parameter(Mandatory)][string]$ErrorMessage
    )

    & $Script

    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage Exit code: $LASTEXITCODE"
    }
}

function Ensure-Python {
    $python = Get-PythonCommand
    if ($python) {
        return $python
    }

    Write-Host "Python not found. Installing Python 3.14 with winget..." -ForegroundColor Yellow
    Invoke-NativeCommand -ErrorMessage "winget failed to install Python 3.14." {
        winget install -e --id Python.Python.3.14
    }

    $python = Get-PythonCommand
    if (-not $python) {
        $python = "$env:LocalAppData\Programs\Python\Python314\python.exe"
    }

    if (-not (Test-Path $python)) {
        throw "Python installation appears to have succeeded, but python.exe could not be found."
    }

    return $python
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Script
    )
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Script
}

$PythonCmd = Ensure-Python
$VenvPython = Join-Path $ScriptRoot ".venv\Scripts\python.exe"

if ($ForceRecreateVenv -and (Test-Path (Join-Path $ScriptRoot ".venv"))) {
    Invoke-Step "Removing existing virtual environment" {
        Remove-Item -Recurse -Force (Join-Path $ScriptRoot ".venv")
    }
}

if (-not (Test-Path $VenvPython)) {
    Invoke-Step "Creating virtual environment" {
        Invoke-NativeCommand -ErrorMessage "Python failed to create the virtual environment." {
            & $PythonCmd -m venv (Join-Path $ScriptRoot ".venv")
        }
    }
}

$VenvPython = Join-Path $ScriptRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $VenvPython)) {
    throw "Virtual environment creation did not produce $VenvPython"
}

Invoke-Step "Upgrading pip" {
    Invoke-NativeCommand -ErrorMessage "pip failed to upgrade inside the virtual environment." {
        & $VenvPython -m pip install --upgrade pip --no-cache-dir
    }
}

Write-Host "Installed Python at $(Get-PythonCommand)" -ForegroundColor Green
Write-Host "Created Venv $VenvPython"
Write-Host "pip has been upgraded in virtual environment"
Write-Host "Activate your virtual environment any time later with:" -ForegroundColor Green
Write-Host ". $ScriptRoot\.venv\Scripts\Activate.ps1"
