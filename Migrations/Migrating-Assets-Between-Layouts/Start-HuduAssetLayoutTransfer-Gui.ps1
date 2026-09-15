[CmdletBinding()]
param(
    [string]$JobPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-NormalizedPath {
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LiteralPath)
}

function Get-PwshPath {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    $fallbacks = @(
        (Join-Path ${env:ProgramFiles} 'PowerShell\7\pwsh.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

    return @($fallbacks | Select-Object -First 1)[0]
}

function Get-AppVersion {
    param(
        [Parameter(Mandatory)]
        [string]$LauncherRoot
    )

    $versionPath = Join-Path $LauncherRoot 'VERSION'
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
        if ($version) {
            return $version
        }
    }

    return '1.0.0'
}

function Restore-EnvironmentVariable {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        Remove-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
        return
    }

    Set-Item -Path ("Env:{0}" -f $Name) -Value $Value
}

function Start-InPowerShell7 {
    param(
        [Parameter(Mandatory)]
        [string]$LauncherPath,

        [AllowNull()]
        [string]$JobPath
    )

    $pwshPath = Get-PwshPath
    if (-not $pwshPath) {
        throw 'This launcher requires PowerShell 7 because the transfer script uses PowerShell 7 syntax. Install PowerShell 7 and try again.'
    }

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $LauncherPath
    )

    if (-not [string]::IsNullOrWhiteSpace($JobPath)) {
        $arguments += @('-JobPath', $JobPath)
    }

    & $pwshPath @arguments
    exit $LASTEXITCODE
}

$launcherRoot = Resolve-NormalizedPath -LiteralPath $PSScriptRoot
$launcherPath = Resolve-NormalizedPath -LiteralPath $PSCommandPath

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Start-InPowerShell7 -LauncherPath $launcherPath -JobPath $JobPath
}

$payloadPath = Join-Path $launcherRoot 'Start-HuduAssetLayoutTransfer.ps1'
if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
    throw "Could not find Start-HuduAssetLayoutTransfer.ps1 next to this launcher: $payloadPath"
}

$previousRoot = $env:HUDU_LAYOUT_TRANSFER_ROOT
$previousVersion = $env:HUDU_LAYOUT_TRANSFER_VERSION
$previousJobPath = $env:HUDU_LAYOUT_TRANSFER_JOB_PATH

$env:HUDU_LAYOUT_TRANSFER_ROOT = $launcherRoot
$env:HUDU_LAYOUT_TRANSFER_VERSION = Get-AppVersion -LauncherRoot $launcherRoot
if (-not [string]::IsNullOrWhiteSpace($JobPath)) {
    $env:HUDU_LAYOUT_TRANSFER_JOB_PATH = $JobPath
}
else {
    Remove-Item -Path Env:\HUDU_LAYOUT_TRANSFER_JOB_PATH -ErrorAction SilentlyContinue
}

$script:Root = $launcherRoot
$script:Gui = $true
$script:JobPath = $JobPath

Push-Location -LiteralPath $launcherRoot
try {
    . $payloadPath

    $guiEntryPoint = Get-Command -Name New-GuiJob -CommandType Function -ErrorAction SilentlyContinue
    if (-not $guiEntryPoint) {
        throw "The transfer script did not define the expected entry point 'New-GuiJob'."
    }

    & $guiEntryPoint
}
finally {
    Pop-Location
    Restore-EnvironmentVariable -Name 'HUDU_LAYOUT_TRANSFER_ROOT' -Value $previousRoot
    Restore-EnvironmentVariable -Name 'HUDU_LAYOUT_TRANSFER_VERSION' -Value $previousVersion
    Restore-EnvironmentVariable -Name 'HUDU_LAYOUT_TRANSFER_JOB_PATH' -Value $previousJobPath
}
