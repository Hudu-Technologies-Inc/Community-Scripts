# Hop helper for Windows PowerShell 5.x. This file must parse in 5.1: no
# requires directive, no IsWindows automatic variable, and no ?? or && so
# setup.ps1 and run.ps1 can re-launch Microsoft PowerShell 7.2+ before
# Import-Module.

function Test-DbmPwshWindowsAppsStub {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    return $Path -match '(?i)\\Microsoft\\WindowsApps\\pwsh\.exe$'
}

function Add-DbmPwshCandidatePath {
    param(
        $List,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (Test-DbmPwshWindowsAppsStub -Path $Path) { return }
    $resolved = $null
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $resolved = [IO.Path]::GetFullPath($Path)
        }
    }
    catch {
        return
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) { return }
    if (Test-DbmPwshWindowsAppsStub -Path $resolved) { return }
    foreach ($existing in $List) {
        if ([string]::Equals($existing, $resolved, [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $null = $List.Add($resolved)
}

function Test-DbmMicrosoftSignedPwsh72 {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }
    if (Test-DbmPwshWindowsAppsStub -Path $Candidate) { return $false }
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { return $false }

    $signature = $null
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Candidate
    }
    catch {
        return $false
    }
    if ($null -eq $signature) { return $false }
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) { return $false }
    if ($null -eq $signature.SignerCertificate) { return $false }
    if ($signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
        return $false
    }

    $candidateVersion = $null
    $candidateVersionText = $null
    try {
        $candidateVersionText = [Diagnostics.FileVersionInfo]::GetVersionInfo($Candidate).FileVersion
    }
    catch {
        return $false
    }
    if (-not [version]::TryParse($candidateVersionText, [ref]$candidateVersion)) { return $false }
    if ($candidateVersion -lt [version]'7.2') { return $false }
    return $true
}

function Resolve-DbmMicrosoftPwsh72Path {
    $candidates = New-Object 'System.Collections.Generic.List[string]'

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        Add-DbmPwshCandidatePath -List $candidates -Path (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        Add-DbmPwshCandidatePath -List $candidates -Path (Join-Path $programFilesX86 'PowerShell\7\pwsh.exe')
    }

    $versioned = New-Object 'System.Collections.Generic.List[object]'
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $powerShellRoot = Join-Path $env:ProgramFiles 'PowerShell'
        if (Test-Path -LiteralPath $powerShellRoot -PathType Container) {
            $directories = @(
                Get-ChildItem -LiteralPath $powerShellRoot -Directory -ErrorAction SilentlyContinue
            )
            foreach ($directory in $directories) {
                if ($directory.Name -match '(?i)preview') { continue }
                $pwshPath = Join-Path $directory.FullName 'pwsh.exe'
                if (-not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) { continue }
                $fileVersion = $null
                $fileVersionText = $null
                try {
                    $fileVersionText = [Diagnostics.FileVersionInfo]::GetVersionInfo($pwshPath).FileVersion
                }
                catch {
                    continue
                }
                if (-not [version]::TryParse($fileVersionText, [ref]$fileVersion)) { continue }
                if ($fileVersion -lt [version]'7.2') { continue }
                $null = $versioned.Add([pscustomobject]@{
                    Path    = $pwshPath
                    Version = $fileVersion
                })
            }
        }
    }
    foreach ($entry in @($versioned | Sort-Object Version -Descending)) {
        Add-DbmPwshCandidatePath -List $candidates -Path $entry.Path
    }

    $pathCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $pathCommand) {
        Add-DbmPwshCandidatePath -List $candidates -Path ([string]$pathCommand.Source)
    }

    try {
        $packages = @(Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction Stop)
        foreach ($package in $packages) {
            if ([string]::IsNullOrWhiteSpace([string]$package.InstallLocation)) { continue }
            Add-DbmPwshCandidatePath -List $candidates -Path (Join-Path $package.InstallLocation 'pwsh.exe')
        }
    }
    catch {
        Write-Verbose 'Get-AppxPackage could not be used to locate Microsoft PowerShell.'
    }

    foreach ($candidate in $candidates) {
        if (-not (Test-DbmMicrosoftSignedPwsh72 -Candidate $candidate)) { continue }
        $candidateVersion = $null
        $candidateVersionText = [Diagnostics.FileVersionInfo]::GetVersionInfo($candidate).FileVersion
        if (-not [version]::TryParse($candidateVersionText, [ref]$candidateVersion) -or
            $candidateVersion -lt [version]'7.2') {
            continue
        }
        return [IO.Path]::GetFullPath($candidate)
    }

    return $null
}
