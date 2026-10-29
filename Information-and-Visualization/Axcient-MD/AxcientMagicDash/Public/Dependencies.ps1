$script:AmdTrustedAxcientApiHashes = [ordered]@{
    'AxcientAPI.psd1' = '2555AFB9A9A86DD533E18060A0AECF8CE844F49B21BE04151D9CE8C68E63596B'
    'AxcientAPI.psm1' = '1C2A08ACF20CA4EF77E26F05391BC02F3CF322BD3565F689102998451DCF4A9D'
}

function Assert-AmdAxcientApiIntegrity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModuleDirectory)

    foreach ($entry in $script:AmdTrustedAxcientApiHashes.GetEnumerator()) {
        $path = Join-Path $ModuleDirectory $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "The pinned AxcientAPI dependency is incomplete: $($entry.Key) is missing. Restore the reviewed AxcientAPI 0.4.0 files and rerun."
        }
        $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        if (-not [string]::Equals($actualHash, [string]$entry.Value, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The pinned AxcientAPI dependency failed its reviewed SHA-256 check: $($entry.Key). Restore the reviewed AxcientAPI 0.4.0 files and rerun."
        }
    }
}

function Import-AmdLockedModule {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManifestPath)

    $resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
    $moduleDirectory = Split-Path -Parent $resolvedManifest
    $moduleName = [IO.Path]::GetFileNameWithoutExtension($resolvedManifest)
    $files = @(Get-ChildItem -LiteralPath $moduleDirectory -Recurse -File -Force)
    $locks = [System.Collections.Generic.List[IO.FileStream]]::new()
    try {
        foreach ($file in $files) {
            $locks.Add([IO.File]::Open(
                $file.FullName,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read
            ))
        }
        if ([string]::Equals($moduleName, 'AxcientAPI', [StringComparison]::OrdinalIgnoreCase)) {
            # Locks are already held without write/delete sharing, so the bytes
            # checked here are the same files Import-Module can subsequently load.
            Assert-AmdAxcientApiIntegrity -ModuleDirectory $moduleDirectory
        }
        # A vendored manifest can declare a working-directory-relative RootModule.
        # PowerShell resolves that relative path against the current location, not
        # the module base, so a file planted in the working directory could be
        # loaded instead of the locked one. Import from inside the module directory,
        # then prove which root module actually loaded. This proves the location, not
        # the contents: content hashing belongs to the verified elevation snapshot
        # and only runs on that path.
        Push-Location -LiteralPath $moduleDirectory
        try {
            $imported = Import-Module -Name $resolvedManifest -Force -PassThru -ErrorAction Stop
        }
        finally {
            Pop-Location
        }

        $expectedPrefix = $moduleDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $loadedRoot = [string]$imported.Path
        if ([string]::IsNullOrWhiteSpace($loadedRoot) -or
            -not [IO.Path]::GetFullPath($loadedRoot).StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
            throw "The $moduleName manifest loaded its root module from outside the verified module directory. Remove any stray $moduleName.psm1 from the working directory and rerun."
        }
    }
    finally {
        foreach ($stream in $locks) { $stream.Dispose() }
    }
}

function Import-AmdRequiredModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalModulePath,
        [switch]$Interactive,
        [switch]$ProjectLocalOnly,
        [scriptblock]$ReadInput = { param($Prompt) Read-Host $Prompt }
    )

    if ([Environment]::GetEnvironmentVariable('AMD_VERIFIED_ELEVATION', [EnvironmentVariableTarget]::Process) -eq '1') {
        $verifiedModuleRoot = [Environment]::GetEnvironmentVariable('AMD_VERIFIED_MODULE_ROOT', [EnvironmentVariableTarget]::Process)
        if ([string]::IsNullOrWhiteSpace($verifiedModuleRoot) -or
            -not (Test-Path -LiteralPath $verifiedModuleRoot -PathType Container)) {
            throw 'The administrator process has no immutable verified dependency snapshot. Close it and rerun the entry point.'
        }
        $LocalModulePath = $verifiedModuleRoot
        $ProjectLocalOnly = $true
    }

    # The remaining PowerShell dependency is pinned to an exact, validated
    # version. Never widen this to a minimum-version range: an unreviewed future
    # release would be auto-loaded into an administrator process. The Hudu client
    # and its Python runtime are bundled separately and are never downloaded here.
    $requirements = @(
        [pscustomobject]@{ Name = 'AxcientAPI'; MinimumVersion = [version]'0.4.0'; RequiredVersion = [version]'0.4.0' }
    )

    foreach ($requirement in $requirements) {
        $candidate = $null
        if (Test-Path -LiteralPath $LocalModulePath -PathType Container) {
            $candidate = Get-ChildItem -LiteralPath (Join-Path $LocalModulePath $requirement.Name) -Filter "$($requirement.Name).psd1" -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try {
                        $manifest = Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
                        [pscustomobject]@{ Path = $_.FullName; Version = [version]$manifest.Version }
                    }
                    catch { $null }
                } |
                Where-Object {
                    $null -ne $_ -and
                    $(if ($requirement.RequiredVersion) {
                        $_.Version -eq $requirement.RequiredVersion
                    }
                    else {
                        $_.Version -ge $requirement.MinimumVersion
                    })
                } |
                Sort-Object Version -Descending |
                Select-Object -First 1
        }

        if ($candidate) {
            Import-AmdLockedModule -ManifestPath $candidate.Path
            Write-Host "$($requirement.Name) $($candidate.Version) loaded from the project Modules folder." -ForegroundColor Green
            continue
        }
        if ([Environment]::GetEnvironmentVariable('AMD_VERIFIED_ELEVATION', [EnvironmentVariableTarget]::Process) -eq '1') {
            throw "$($requirement.Name) was not present in the verified pre-elevation dependency snapshot. Close this window and rerun run.ps1."
        }

        $installed = if (-not $ProjectLocalOnly) {
            Get-Module -ListAvailable -Name $requirement.Name |
                Where-Object {
                    if ($requirement.RequiredVersion) {
                        $_.Version -eq $requirement.RequiredVersion
                    }
                    else {
                        $_.Version -ge $requirement.MinimumVersion
                    }
                } |
                Sort-Object Version -Descending |
                Select-Object -First 1
        }
        else { $null }

        if ($installed) {
            Import-AmdLockedModule -ManifestPath $installed.Path
            Write-Host "$($requirement.Name) $($installed.Version) loaded." -ForegroundColor Green
            continue
        }

        if (-not $Interactive) {
            $versionText = if ($requirement.RequiredVersion) { "exactly $($requirement.RequiredVersion)" } else { "$($requirement.MinimumVersion) or newer" }
            throw "$($requirement.Name) $versionText is required. Run run.ps1 to install project-local modules."
        }

        $versionText = if ($requirement.RequiredVersion) { "exactly $($requirement.RequiredVersion)" } else { "$($requirement.MinimumVersion) or newer" }
        Write-Host "`n$($requirement.Name) $versionText is required but was not found." -ForegroundColor Yellow
        $answerValue = & $ReadInput "Download it from PowerShell Gallery into '$LocalModulePath'? (Y/n)"
        if ($null -eq $answerValue) {
            throw [IO.EndOfStreamException]::new(
                'Interactive input ended before dependency consent was answered. Run run.ps1 in an interactive PowerShell console and try again.'
            )
        }
        $answer = [string]$answerValue
        $answer = $answer.Trim()
        if ($answer -notin '', 'y', 'Y', 'yes', 'YES', 'Yes') {
            throw "$($requirement.Name) is required. Setup cannot continue until it is installed."
        }

        if (-not (Test-Path -LiteralPath $LocalModulePath -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $LocalModulePath -Force
        }

        try {
            $saveParams = @{
                Name        = $requirement.Name
                Path        = $LocalModulePath
                Repository  = 'PSGallery'
                ErrorAction = 'Stop'
            }
            if ($requirement.RequiredVersion) {
                $saveParams.RequiredVersion = $requirement.RequiredVersion
            }
            else {
                $saveParams.MinimumVersion = $requirement.MinimumVersion
            }
            Save-Module @saveParams
        }
        catch {
            throw "Could not download $($requirement.Name) from PowerShell Gallery. Check Internet access and PSGallery trust, then rerun run.ps1. $($_.Exception.Message)"
        }

        $downloaded = Get-ChildItem -LiteralPath (Join-Path $LocalModulePath $requirement.Name) -Filter "$($requirement.Name).psd1" -Recurse -File -ErrorAction Stop |
            ForEach-Object {
                $manifest = Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
                [pscustomobject]@{ Path = $_.FullName; Version = [version]$manifest.Version }
            } |
            Where-Object {
                if ($requirement.RequiredVersion) {
                    $_.Version -eq $requirement.RequiredVersion
                }
                else {
                    $_.Version -ge $requirement.MinimumVersion
                }
            } |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $downloaded) {
            throw "The $($requirement.Name) download completed, but no usable module version was found."
        }

        Import-AmdLockedModule -ManifestPath $downloaded.Path
        Write-Host "$($requirement.Name) $($downloaded.Version) downloaded and loaded." -ForegroundColor Green
    }
}
