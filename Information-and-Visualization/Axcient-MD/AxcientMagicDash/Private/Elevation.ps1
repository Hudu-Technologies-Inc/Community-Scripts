$script:AmdTrustedRuntimeManifestHash = 'c17a406c56fc3957ee0969d9aa6461b4841e162ab5edb23619442675c2cf5973'

function Get-AmdCurrentPwshPath {
    [CmdletBinding()]
    param()

    $processPath = [Environment]::ProcessPath
    $fileName = if ([string]::IsNullOrWhiteSpace($processPath)) { '' } else { [IO.Path]::GetFileName($processPath) }
    if ([string]::IsNullOrWhiteSpace($processPath) -or
        $fileName -notin 'pwsh', 'pwsh.exe' -or
        -not (Test-Path -LiteralPath $processPath -PathType Leaf)) {
        throw 'The current PowerShell 7 executable could not be verified. Start this script from PowerShell 7.2 or newer.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $processPath -ErrorAction Stop
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
        throw 'Administrator elevation requires a valid Microsoft-signed PowerShell 7 executable.'
    }
    return [IO.Path]::GetFullPath($processPath)
}

function Test-AmdAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AmdNotFileSystemLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not [string]::IsNullOrWhiteSpace([string]$item.LinkType) -or $null -ne $item.Target) {
        throw "Verified elevation refuses symbolic links and junctions: $($item.FullName)"
    }
}

function Assert-AmdTreeContainsNoFileSystemLinks {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    Assert-AmdNotFileSystemLink -Path $Root
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop) {
        if (-not [string]::IsNullOrWhiteSpace([string]$item.LinkType) -or $null -ne $item.Target) {
            throw "Verified elevation refuses symbolic links and junctions: $($item.FullName)"
        }
    }
}

function Assert-AmdTrustedRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [string]$ExpectedManifestHash = $script:AmdTrustedRuntimeManifestHash
    )

    $root = [IO.Path]::GetFullPath($RuntimeRoot)
    $manifestPath = Join-Path $root 'VENDOR_MANIFEST.sha256'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "The bundled Python runtime trust manifest is missing: $manifestPath"
    }
    Assert-AmdNotFileSystemLink -Path $manifestPath
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256 -ErrorAction Stop).Hash
    if (-not [string]::Equals($manifestHash, $ExpectedManifestHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The bundled Python runtime trust manifest does not match the reviewed release.'
    }

    $expected = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $manifestPath -ErrorAction Stop) {
        $match = [regex]::Match([string]$line, '\A([0-9a-fA-F]{64})  (.+)\z')
        if (-not $match.Success) {
            throw "The bundled Python runtime trust manifest contains a malformed line: $line"
        }
        $relative = $match.Groups[2].Value.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ([IO.Path]::IsPathRooted($relative)) {
            throw "The bundled Python runtime trust manifest contains an absolute path: $relative"
        }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relative))
        $rootPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($fullPath, $manifestPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The bundled Python runtime trust manifest contains an unsafe path: $relative"
        }
        if ($expected.ContainsKey($fullPath)) {
            throw "The bundled Python runtime trust manifest repeats a path: $relative"
        }
        $expected.Add($fullPath, $match.Groups[1].Value)
    }
    if ($expected.Count -eq 0) {
        throw 'The bundled Python runtime trust manifest contains no reviewed files.'
    }

    $actual = @(
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction Stop |
            Where-Object { -not [string]::Equals($_.FullName, $manifestPath, [StringComparison]::OrdinalIgnoreCase) }
    )
    if ($actual.Count -ne $expected.Count -or
        @($actual | Where-Object { -not $expected.ContainsKey([IO.Path]::GetFullPath($_.FullName)) }).Count -gt 0) {
        throw 'The bundled Python runtime file inventory does not match the reviewed release.'
    }
    foreach ($file in $actual) {
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop).Hash
        if (-not [string]::Equals($actualHash, $expected[$fullPath], [StringComparison]::OrdinalIgnoreCase)) {
            throw "The bundled Python runtime file failed reviewed-hash verification: $($file.FullName)"
        }
    }
}

function Set-AmdOriginalUserContext {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$UserName = '',
        [AllowEmptyString()][string]$UserSid = ''
    )

    if ([string]::IsNullOrWhiteSpace($UserName) -and [string]::IsNullOrWhiteSpace($UserSid)) {
        $verifiedElevation = [Environment]::GetEnvironmentVariable('AMD_VERIFIED_ELEVATION', [EnvironmentVariableTarget]::Process) -eq '1'
        $forwardedName = [Environment]::GetEnvironmentVariable('AMD_ORIGINAL_USER_NAME', [EnvironmentVariableTarget]::Process)
        $forwardedSid = [Environment]::GetEnvironmentVariable('AMD_ORIGINAL_USER_SID', [EnvironmentVariableTarget]::Process)
        if ($verifiedElevation -and
            -not [string]::IsNullOrWhiteSpace($forwardedName) -and
            -not [string]::IsNullOrWhiteSpace($forwardedSid)) {
            if (-not (Test-AmdAdministrator)) {
                throw 'Forwarded original-user identity is valid only inside a verified administrator process.'
            }
            $UserName = $forwardedName
            $UserSid = $forwardedSid
        }
        else {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $UserName = $identity.Name
            $UserSid = $identity.User.Value
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($UserName) -or [string]::IsNullOrWhiteSpace($UserSid)) {
        throw 'The original Windows user name and SID must be supplied together.'
    }

    try {
        $sid = [Security.Principal.SecurityIdentifier]::new($UserSid)
        $translatedName = $sid.Translate([Security.Principal.NTAccount]).Value
    }
    catch {
        throw "The original Windows user identity could not be validated. $($_.Exception.Message)"
    }
    if (-not [string]::Equals($translatedName, $UserName, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The original Windows user name does not match the supplied SID.'
    }

    [Environment]::SetEnvironmentVariable('AMD_ORIGINAL_USER_NAME', $translatedName, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ORIGINAL_USER_SID', $sid.Value, [EnvironmentVariableTarget]::Process)
    return [pscustomobject]@{ UserName = $translatedName; UserSid = $sid.Value }
}

function Get-AmdOperatingUserName {
    [CmdletBinding()]
    param()

    $name = [Environment]::GetEnvironmentVariable('AMD_ORIGINAL_USER_NAME', [EnvironmentVariableTarget]::Process)
    $sidValue = [Environment]::GetEnvironmentVariable('AMD_ORIGINAL_USER_SID', [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($sidValue)) {
        return [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    return (Set-AmdOriginalUserContext -UserName $name -UserSid $sidValue).UserName
}

function Get-AmdOperatingUserSid {
    [CmdletBinding()]
    param()

    $name = [Environment]::GetEnvironmentVariable('AMD_ORIGINAL_USER_NAME', [EnvironmentVariableTarget]::Process)
    $sidValue = [Environment]::GetEnvironmentVariable('AMD_ORIGINAL_USER_SID', [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($sidValue)) {
        return [Security.Principal.WindowsIdentity]::GetCurrent().User
    }
    $context = Set-AmdOriginalUserContext -UserName $name -UserSid $sidValue
    return [Security.Principal.SecurityIdentifier]::new($context.UserSid)
}

function ConvertTo-AmdBoundedDiagnosticText {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [ValidateRange(64, 8192)][int]$MaximumLength = 3500
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $safe = if (Get-Command ConvertTo-AmdRedactedText -ErrorAction SilentlyContinue) {
        ConvertTo-AmdRedactedText -Text $Text
    }
    else { $Text }
    # Elevation diagnostics can be produced before the module (and its registered
    # sensitive values) is available, so always strip credential-shaped tokens too.
    $safe = $safe -replace '(?i)\b(authorization|x-api-key|api[-_ ]?key|apikey|password|secret|token)\b\s*[:=]\s*(?:bearer\s+)?\S+', '$1: [REDACTED]'
    $safe = [regex]::Replace($safe, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ' ')
    if ($safe.Length -gt $MaximumLength) {
        $safe = $safe.Substring(0, $MaximumLength) + '...'
    }
    return $safe
}

function Get-AmdErrorSourceLocation {
    [CmdletBinding()]
    param([AllowNull()]$ErrorRecord)

    $invocation = $ErrorRecord.InvocationInfo
    if ($null -eq $invocation) { return 'unknown location' }
    $scriptName = [string]$invocation.ScriptName
    # Report the file name and line only. Full paths add no diagnostic value here
    # and would push user directory names into a shared status file.
    $leaf = if ([string]::IsNullOrWhiteSpace($scriptName)) { '<inline>' } else { [IO.Path]::GetFileName($scriptName) }
    return "$leaf`:$([int]$invocation.ScriptLineNumber)"
}

function Write-AmdElevationFailureStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Stage = ''
    )

    if ([Environment]::GetEnvironmentVariable('AMD_VERIFIED_ELEVATION', [EnvironmentVariableTarget]::Process) -ne '1') {
        return
    }
    # The status file has its own container variable. It used to share
    # AMD_VERIFIED_MODULE_CONTAINER, which Initialize-AmdVerifiedModuleSnapshot
    # repoints at the ProgramData module snapshot - after which the check below threw
    # and discarded the run's only diagnostic, in Stop-AmdSetup even skipping the exit.
    $container = [Environment]::GetEnvironmentVariable('AMD_ELEVATION_STATUS_CONTAINER', [EnvironmentVariableTarget]::Process)
    $statusPath = [Environment]::GetEnvironmentVariable('AMD_ELEVATION_STATUS_PATH', [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($container) -or [string]::IsNullOrWhiteSpace($statusPath)) {
        return
    }
    $expectedStatusPath = Join-Path ([IO.Path]::GetFullPath($container)) 'status.txt'
    if (-not [string]::Equals([IO.Path]::GetFullPath($statusPath), $expectedStatusPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The verified elevation status path is invalid.'
    }
    foreach ($path in $container, $statusPath) {
        Assert-AmdNotFileSystemLink -Path $path
    }
    $stageName = if ([string]::IsNullOrWhiteSpace($Stage)) {
        [string][Environment]::GetEnvironmentVariable('AMD_ELEVATION_STAGE', [EnvironmentVariableTarget]::Process)
    }
    else { $Stage }
    $prefix = if ([string]::IsNullOrWhiteSpace($stageName)) { '' } else { "[stage: $stageName] " }
    $safeMessage = $prefix + (ConvertTo-AmdBoundedDiagnosticText -Text $Message -MaximumLength 4096)
    if ($safeMessage.Length -gt 4096) {
        $safeMessage = $safeMessage.Substring(0, 4096) + '...'
    }
    [IO.File]::WriteAllText($statusPath, $safeMessage, [Text.Encoding]::UTF8)
}

function Get-AmdSha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha.ComputeHash($Bytes))
    }
    finally {
        $sha.Dispose()
    }
}

function Read-AmdBoundedStreamBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][ValidateRange(1, 16777216)][long]$MaximumBytes,
        [Parameter(Mandatory)][string]$Description
    )

    if ($Stream.Length -le 0 -or $Stream.Length -gt $MaximumBytes) {
        throw "The $Description has an invalid size."
    }
    $Stream.Position = 0
    $bytes = [byte[]]::new([int]$Stream.Length)
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -le 0) {
            throw "The $Description could not be read completely."
        }
        $offset += $read
    }
    if ($Stream.Read([byte[]]::new(1), 0, 1) -ne 0) {
        throw "The $Description grew while it was being read."
    }
    return , $bytes
}

function Read-AmdBoundedFileBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateRange(1, 16777216)][long]$MaximumBytes,
        [Parameter(Mandatory)][string]$Description
    )

    # Read the whole bounded file once, denying writers for the duration, so the
    # bytes that get hashed are exactly the bytes the caller goes on to use. A
    # second read of the same handle would reopen a check/use window.
    $stream = [IO.File]::Open(
        [IO.Path]::GetFullPath($Path),
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    try {
        return , (Read-AmdBoundedStreamBytes -Stream $stream -MaximumBytes $MaximumBytes -Description $Description)
    }
    finally {
        $stream.Dispose()
    }
}

function Write-AmdProtectedElevationFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$ExpectedHash,
        [Parameter(Mandatory)][string]$Description
    )

    if ($Bytes.LongLength -le 0 -or $Bytes.LongLength -gt 16MB) {
        throw "The $Description is empty or too large to protect."
    }

    # Write through an exclusive handle, release every write-capable handle, then
    # return a read-only guard. The guard denies writers for as long as the
    # elevated child consumes the file, so its content cannot be substituted
    # after it was hashed, and this process keeps no way to rewrite it either.
    $writeStream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $writeStream.Write($Bytes, 0, $Bytes.Length)
        $writeStream.Flush($true)
    }
    finally {
        $writeStream.Dispose()
    }

    $guard = $null
    try {
        $openAttempts = 0
        while ($null -eq $guard) {
            $openAttempts++
            try {
                $guard = [IO.File]::Open(
                    $Path,
                    [IO.FileMode]::Open,
                    [IO.FileAccess]::Read,
                    [IO.FileShare]::Read
                )
            }
            catch {
                $retryable = $_.Exception -is [UnauthorizedAccessException] -or
                    $_.Exception -is [IO.IOException]
                if ($openAttempts -ge 5 -or -not $retryable) {
                    throw
                }
                Start-Sleep -Milliseconds (100 * $openAttempts)
            }
        }
        $verified = Read-AmdBoundedStreamBytes -Stream $guard -MaximumBytes $Bytes.LongLength -Description $Description
        if (-not [string]::Equals((Get-AmdSha256Hex -Bytes $verified), $ExpectedHash, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The $Description was replaced before it could be protected."
        }
        return $guard
    }
    catch {
        if ($null -ne $guard) { $guard.Dispose() }
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Read-AmdVerifiedSnapshotManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedHash
    )

    if ($ExpectedHash -notmatch '\A[0-9A-Fa-f]{64}\z') {
        throw 'The verified dependency snapshot hash is invalid.'
    }
    $bytes = Read-AmdBoundedFileBytes `
        -Path $Path `
        -MaximumBytes 16MB `
        -Description 'verified dependency snapshot manifest'
    if (-not [string]::Equals((Get-AmdSha256Hex -Bytes $bytes), $ExpectedHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The verified dependency snapshot manifest changed while administrator access was requested.'
    }
    return ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($bytes)) -ErrorAction Stop
}

function Initialize-AmdVerifiedModuleSnapshot {
    [CmdletBinding()]
    param()

    if ([Environment]::GetEnvironmentVariable('AMD_VERIFIED_ELEVATION', [EnvironmentVariableTarget]::Process) -ne '1') {
        return $null
    }
    $existingModuleRoot = [Environment]::GetEnvironmentVariable('AMD_VERIFIED_MODULE_ROOT', [EnvironmentVariableTarget]::Process)
    $existingRuntimeRoot = [Environment]::GetEnvironmentVariable('AMD_VERIFIED_RUNTIME_ROOT', [EnvironmentVariableTarget]::Process)
    if (-not [string]::IsNullOrWhiteSpace($existingModuleRoot) -and
        (Test-Path -LiteralPath $existingModuleRoot -PathType Container)) {
        if ([string]::IsNullOrWhiteSpace($existingRuntimeRoot) -or
            -not (Test-Path -LiteralPath $existingRuntimeRoot -PathType Container)) {
            throw 'The administrator process has no immutable verified Python runtime snapshot. Close it and rerun the entry point.'
        }
        $resolvedModuleRoot = [IO.Path]::GetFullPath($existingModuleRoot)
        $resolvedRuntimeRoot = [IO.Path]::GetFullPath($existingRuntimeRoot)
        $expectedRuntimeRoot = Join-Path (Split-Path -Parent $resolvedModuleRoot) 'Runtime'
        if (-not [string]::Equals($resolvedRuntimeRoot, $expectedRuntimeRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The verified Python runtime is not beside the verified Modules directory. Close the administrator process and rerun the entry point.'
        }
        Assert-AmdTreeContainsNoFileSystemLinks -Root $resolvedModuleRoot
        Assert-AmdTreeContainsNoFileSystemLinks -Root $resolvedRuntimeRoot
        return $resolvedModuleRoot
    }
    $manifestPath = [Environment]::GetEnvironmentVariable('AMD_VERIFIED_SNAPSHOT_PATH', [EnvironmentVariableTarget]::Process)
    $manifestHash = [Environment]::GetEnvironmentVariable('AMD_VERIFIED_SNAPSHOT_HASH', [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($manifestPath) -or [string]::IsNullOrWhiteSpace($manifestHash)) {
        throw 'The verified dependency snapshot manifest is unavailable.'
    }
    $snapshot = Read-AmdVerifiedSnapshotManifest -Path $manifestPath -ExpectedHash $manifestHash
    if ([string]::IsNullOrWhiteSpace([string]$snapshot.RuntimeRoot)) {
        throw 'The verified dependency snapshot does not contain the bundled Python runtime.'
    }
    $runtimeRoot = [IO.Path]::GetFullPath([string]$snapshot.RuntimeRoot)
    if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
        throw 'The bundled Python runtime disappeared before the verified snapshot could be initialized.'
    }
    Assert-AmdTreeContainsNoFileSystemLinks -Root $runtimeRoot
    $verifiedBase = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'AXCIENT-MAGIC-DASH\VerifiedModules'
    if (Test-Path -LiteralPath $verifiedBase) {
        Assert-AmdNotFileSystemLink -Path $verifiedBase
    }
    else {
        $null = New-Item -ItemType Directory -Path $verifiedBase -Force
    }

    $snapshotAcl = [Security.AccessControl.DirectorySecurity]::new()
    $snapshotAcl.SetAccessRuleProtection($true, $false)
    $administratorsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $snapshotAcl.SetOwner($administratorsSid)
    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($identitySid in 'S-1-5-18', 'S-1-5-32-544') {
        $snapshotAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($identitySid),
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            $none,
            $allow
        ))
    }
    Set-Acl -LiteralPath $verifiedBase -AclObject $snapshotAcl -ErrorAction Stop
    $verifiedContainer = Join-Path $verifiedBase ([Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $verifiedContainer
    Set-Acl -LiteralPath $verifiedContainer -AclObject $snapshotAcl -ErrorAction Stop
    $verifiedModuleRoot = Join-Path $verifiedContainer 'Modules'
    $null = New-Item -ItemType Directory -Path $verifiedModuleRoot
    Set-Acl -LiteralPath $verifiedModuleRoot -AclObject $snapshotAcl -ErrorAction Stop
    $verifiedRuntimeRoot = Join-Path $verifiedContainer 'Runtime'
    $null = New-Item -ItemType Directory -Path $verifiedRuntimeRoot
    Set-Acl -LiteralPath $verifiedRuntimeRoot -AclObject $snapshotAcl -ErrorAction Stop
    $snapshotFileAcl = [Security.AccessControl.FileSecurity]::new()
    $snapshotFileAcl.SetAccessRuleProtection($true, $false)
    $snapshotFileAcl.SetOwner($administratorsSid)
    foreach ($identitySid in 'S-1-5-18', 'S-1-5-32-544') {
        $snapshotFileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($identitySid),
            [Security.AccessControl.FileSystemRights]::FullControl,
            $allow
        ))
    }

    try {
        foreach ($dependencyRootValue in @($snapshot.DependencyRoots)) {
            $dependencyRoot = [IO.Path]::GetFullPath([string]$dependencyRootValue)
            Assert-AmdTreeContainsNoFileSystemLinks -Root $dependencyRoot
            $dependencyName = Split-Path -Leaf $dependencyRoot
            $targetRoot = Join-Path $verifiedModuleRoot $dependencyName
            $null = New-Item -ItemType Directory -Path $targetRoot
            Set-Acl -LiteralPath $targetRoot -AclObject $snapshotAcl -ErrorAction Stop
            $dependencyPrefix = $dependencyRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            foreach ($record in @($snapshot.Records | Where-Object {
                [IO.Path]::GetFullPath([string]$_.Path).StartsWith($dependencyPrefix, [StringComparison]::OrdinalIgnoreCase)
            })) {
                $relative = [IO.Path]::GetRelativePath($dependencyRoot, [string]$record.Path)
                if ($relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
                    throw "A verified dependency path escaped its root: $($record.Path)"
                }
                $targetPath = Join-Path $targetRoot $relative
                $targetDirectory = Split-Path -Parent $targetPath
                if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
                    $null = New-Item -ItemType Directory -Path $targetDirectory -Force
                }
                Set-Acl -LiteralPath $targetDirectory -AclObject $snapshotAcl -ErrorAction Stop
                Copy-Item -LiteralPath $record.Path -Destination $targetPath -ErrorAction Stop
                Set-Acl -LiteralPath $targetPath -AclObject $snapshotFileAcl -ErrorAction Stop
                $copiedHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash
                if (-not [string]::Equals($copiedHash, [string]$record.Hash, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "A verified dependency copy did not match its source: $($record.Path)"
                }
            }
        }
        $runtimePrefix = $runtimeRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $runtimeRecords = @($snapshot.Records | Where-Object {
            [IO.Path]::GetFullPath([string]$_.Path).StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)
        })
        $expectedRuntimePaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($record in $runtimeRecords) {
            $null = $expectedRuntimePaths.Add([IO.Path]::GetFullPath([string]$record.Path))
        }
        $currentRuntimePaths = @(
            Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -Force -ErrorAction Stop |
                ForEach-Object { [IO.Path]::GetFullPath($_.FullName) } |
                Sort-Object -Unique
        )
        if ($runtimeRecords.Count -eq 0 -or
            $currentRuntimePaths.Count -ne $expectedRuntimePaths.Count -or
            @($currentRuntimePaths | Where-Object { -not $expectedRuntimePaths.Contains($_) }).Count -gt 0) {
            throw 'The bundled Python runtime inventory changed before the verified snapshot could be initialized.'
        }
        foreach ($record in $runtimeRecords) {
            $relative = [IO.Path]::GetRelativePath($runtimeRoot, [string]$record.Path)
            if ($relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
                throw "A verified runtime path escaped its root: $($record.Path)"
            }
            $targetPath = Join-Path $verifiedRuntimeRoot $relative
            $targetDirectory = Split-Path -Parent $targetPath
            if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $targetDirectory -Force
            }
            Set-Acl -LiteralPath $targetDirectory -AclObject $snapshotAcl -ErrorAction Stop
            Copy-Item -LiteralPath $record.Path -Destination $targetPath -ErrorAction Stop
            Set-Acl -LiteralPath $targetPath -AclObject $snapshotFileAcl -ErrorAction Stop
            $copiedHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if (-not [string]::Equals($copiedHash, [string]$record.Hash, [StringComparison]::OrdinalIgnoreCase)) {
                throw "A verified runtime copy did not match its source: $($record.Path)"
            }
        }
        [Environment]::SetEnvironmentVariable('AMD_VERIFIED_MODULE_ROOT', $verifiedModuleRoot, [EnvironmentVariableTarget]::Process)
        [Environment]::SetEnvironmentVariable('AMD_VERIFIED_RUNTIME_ROOT', $verifiedRuntimeRoot, [EnvironmentVariableTarget]::Process)
        [Environment]::SetEnvironmentVariable('AMD_VERIFIED_MODULE_CONTAINER', $verifiedContainer, [EnvironmentVariableTarget]::Process)
        return $verifiedModuleRoot
    }
    catch {
        Remove-Item -LiteralPath $verifiedContainer -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Start-AmdElevatedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [AllowEmptyCollection()][AllowNull()][string[]]$ForwardedArguments = @(),
        [switch]$Sta
    )

    $resolvedScript = [IO.Path]::GetFullPath($ScriptPath)
    $resolvedDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
    if (-not (Test-Path -LiteralPath $resolvedScript -PathType Leaf)) {
        throw "The script to elevate was not found: $resolvedScript"
    }
    if (-not (Test-Path -LiteralPath $resolvedDirectory -PathType Container)) {
        throw "The elevation working directory was not found: $resolvedDirectory"
    }
    Assert-AmdNotFileSystemLink -Path $resolvedScript
    Assert-AmdNotFileSystemLink -Path $resolvedDirectory

    $sourceFiles = [System.Collections.Generic.List[string]]::new()
    $sourceFiles.Add($resolvedScript)
    # The snapshot always records ModuleSource, and the elevated child resolves
    # it, so a missing module directory has to fail here with a clear message
    # instead of inside the protected child after the UAC prompt.
    $moduleSource = Join-Path $resolvedDirectory 'AxcientMagicDash'
    if (-not (Test-Path -LiteralPath $moduleSource -PathType Container)) {
        throw "The verified elevation snapshot requires the AxcientMagicDash module directory next to the entry point: $moduleSource"
    }
    Assert-AmdTreeContainsNoFileSystemLinks -Root $moduleSource
    foreach ($file in Get-ChildItem -LiteralPath $moduleSource -Recurse -File -Force -Include '*.ps1', '*.psm1', '*.psd1', '*.py') {
        Assert-AmdNotFileSystemLink -Path $file.FullName
        $fullName = [IO.Path]::GetFullPath($file.FullName)
        if (-not $sourceFiles.Contains($fullName)) { $sourceFiles.Add($fullName) }
    }
    $dependencyRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($dependencyName in 'AxcientAPI') {
        $dependencyRoot = Join-Path $resolvedDirectory "Modules\$dependencyName"
        if (-not (Test-Path -LiteralPath $dependencyRoot -PathType Container)) {
            throw "The verified elevation snapshot requires project-local $dependencyName files. Run run.ps1 to install dependencies before elevation."
        }
        $resolvedDependencyRoot = [IO.Path]::GetFullPath($dependencyRoot)
        Assert-AmdTreeContainsNoFileSystemLinks -Root $resolvedDependencyRoot
        $dependencyRoots.Add($resolvedDependencyRoot)
        foreach ($file in Get-ChildItem -LiteralPath $resolvedDependencyRoot -Recurse -File) {
            Assert-AmdNotFileSystemLink -Path $file.FullName
            $fullName = [IO.Path]::GetFullPath($file.FullName)
            if (-not $sourceFiles.Contains($fullName)) { $sourceFiles.Add($fullName) }
        }
    }
    $runtimeRoot = Join-Path $resolvedDirectory 'Runtime'
    if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
        throw "The verified elevation snapshot requires the bundled Python Runtime directory next to the entry point: $runtimeRoot"
    }
    $resolvedRuntimeRoot = [IO.Path]::GetFullPath($runtimeRoot)
    Assert-AmdTreeContainsNoFileSystemLinks -Root $resolvedRuntimeRoot
    # Verify against the reviewed release manifest before hashing the current tree
    # into the UAC snapshot. Otherwise a modified runtime simply becomes the newly
    # "verified" administrator payload.
    Assert-AmdTrustedRuntime -RuntimeRoot $resolvedRuntimeRoot
    $runtimeFiles = @(Get-ChildItem -LiteralPath $resolvedRuntimeRoot -Recurse -File -Force -ErrorAction Stop)
    if ($runtimeFiles.Count -eq 0) {
        throw "The bundled Python Runtime directory is empty: $resolvedRuntimeRoot"
    }
    foreach ($file in $runtimeFiles) {
        Assert-AmdNotFileSystemLink -Path $file.FullName
        $fullName = [IO.Path]::GetFullPath($file.FullName)
        if (-not $sourceFiles.Contains($fullName)) { $sourceFiles.Add($fullName) }
    }
    $hashRecords = @(
        $sourceFiles |
            Sort-Object |
            ForEach-Object {
                [ordered]@{
                    Path = $_
                    Hash = (Get-FileHash -LiteralPath $_ -Algorithm SHA256 -ErrorAction Stop).Hash
                }
            }
    )
    $snapshot = [ordered]@{
        ScriptPath      = $resolvedScript
        WorkingDirectory = $resolvedDirectory
        ModuleSource    = [IO.Path]::GetFullPath($moduleSource)
        DependencyRoots = @($dependencyRoots)
        RuntimeRoot     = $resolvedRuntimeRoot
        Records         = $hashRecords
    }
    $manifestBytes = [Text.Encoding]::UTF8.GetBytes(($snapshot | ConvertTo-Json -Compress -Depth 6))
    $manifestContainer = Join-Path ([IO.Path]::GetTempPath()) "AXCIENT-MAGIC-DASH-$([Guid]::NewGuid().ToString('N')).snapshot"
    $null = New-Item -ItemType Directory -Path $manifestContainer
    $manifestPath = Join-Path $manifestContainer 'snapshot.json'
    $bootstrapPath = Join-Path $manifestContainer 'bootstrap.ps1'
    $statusPath = Join-Path $manifestContainer 'status.txt'
    $manifestLock = $null
    $manifestCreated = $false
    $bootstrapLock = $null
    $bootstrapCreated = $false
    try {
        $manifestHash = Get-AmdSha256Hex -Bytes $manifestBytes
        $manifestLock = Write-AmdProtectedElevationFile `
            -Path $manifestPath `
            -Bytes $manifestBytes `
            -ExpectedHash $manifestHash `
            -Description 'elevation snapshot manifest'
        $manifestCreated = $true
        # Forward switches by name. Splatting an array would bind its values
        # positionally, so '-Schedule' would arrive as a positional argument that an
        # advanced entry point rejects; a name/value map splats correctly.
        #
        # Do not wrap $ForwardedArguments in @(). An empty @() bound to [string[]]
        # becomes $null, and @($null) is one empty item — not "no switches".
        $switchArguments = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $ForwardedArguments) {
            foreach ($candidate in $ForwardedArguments) {
                $switchArguments.Add([string]$candidate)
            }
        }
        $forwardedSwitches = [ordered]@{}
        foreach ($forwardedArgument in $switchArguments) {
            if ([string]$forwardedArgument -notmatch '\A-[A-Za-z][A-Za-z0-9]*\z') {
                throw "Only bare switch names can be forwarded through verified elevation: $forwardedArgument"
            }
            $forwardedSwitches[([string]$forwardedArgument).Substring(1)] = $true
        }
        $forwardedJson = ConvertTo-Json -InputObject $forwardedSwitches -Compress
        $argumentPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($forwardedJson))
        $launchIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $identityPayload = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes((@{
                UserName = $launchIdentity.Name
                UserSid  = $launchIdentity.User.Value
            } | ConvertTo-Json -Compress))
        )
        $escapedManifestPath = $manifestPath.Replace("'", "''")
        $escapedManifestHash = $manifestHash.Replace("'", "''")
        $escapedBootstrapPath = $bootstrapPath.Replace("'", "''")
        $escapedStatusPath = $statusPath.Replace("'", "''")
        $bootstrap = @"
`$ErrorActionPreference = 'Stop'
[Environment]::SetEnvironmentVariable('AMD_ELEVATION_STAGE', 'bootstrap', [EnvironmentVariableTarget]::Process)
`$manifestPath = '$escapedManifestPath'
`$manifestHash = '$escapedManifestHash'
function Read-AmdElevationBytes {
    param(
        [Parameter(Mandatory)][string]`$Path,
        [Parameter(Mandatory)][long]`$MaximumBytes,
        [Parameter(Mandatory)][string]`$Description
    )

    # One bounded read with writers denied, so the hashed bytes are the used bytes.
    `$stream = [IO.File]::Open(`$Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if (`$stream.Length -le 0 -or `$stream.Length -gt `$MaximumBytes) { throw "The `$Description has an invalid size." }
        `$buffer = [byte[]]::new([int]`$stream.Length)
        `$offset = 0
        while (`$offset -lt `$buffer.Length) {
            `$read = `$stream.Read(`$buffer, `$offset, `$buffer.Length - `$offset)
            if (`$read -le 0) { throw "The `$Description could not be read completely." }
            `$offset += `$read
        }
        if (`$stream.Read([byte[]]::new(1), 0, 1) -ne 0) { throw "The `$Description grew while it was being read." }
        return , `$buffer
    }
    finally { `$stream.Dispose() }
}
function Get-AmdElevationHash {
    param([Parameter(Mandatory)][byte[]]`$Bytes)

    `$sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString(`$sha.ComputeHash(`$Bytes)) }
    finally { `$sha.Dispose() }
}
`$manifestBytes = Read-AmdElevationBytes -Path `$manifestPath -MaximumBytes 16MB -Description 'verified dependency snapshot manifest'
if (-not [string]::Equals((Get-AmdElevationHash -Bytes `$manifestBytes), `$manifestHash, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Elevation cancelled because the dependency snapshot manifest changed while the UAC prompt was open.'
}
`$snapshot = ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString(`$manifestBytes)) -ErrorAction Stop
`$identity = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$identityPayload')) | ConvertFrom-Json
`$originalUserSid = [Security.Principal.SecurityIdentifier]::new([string]`$identity.UserSid)
`$verifiedContainer = Split-Path -Parent `$manifestPath
`$containerItem = Get-Item -LiteralPath `$verifiedContainer -Force -ErrorAction Stop
if (-not [string]::IsNullOrWhiteSpace([string]`$containerItem.LinkType) -or `$null -ne `$containerItem.Target) {
    throw 'Elevation cancelled because the protected snapshot container became a symbolic link or junction.'
}
`$expectedContainerFiles = @(`$manifestPath, '$escapedBootstrapPath')
`$unexpectedContainerItems = @(Get-ChildItem -LiteralPath `$verifiedContainer -Force | Where-Object FullName -notin `$expectedContainerFiles)
if (`$unexpectedContainerItems.Count -gt 0) {
    throw 'Elevation cancelled because unexpected content appeared in the protected snapshot container.'
}
`$administratorsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
`$allow = [Security.AccessControl.AccessControlType]::Allow
`$inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
`$none = [Security.AccessControl.PropagationFlags]::None
`$containerAcl = [Security.AccessControl.DirectorySecurity]::new()
`$containerAcl.SetAccessRuleProtection(`$true, `$false)
`$containerAcl.SetOwner(`$administratorsSid)
foreach (`$trustedSidValue in 'S-1-5-18', 'S-1-5-32-544') {
    `$containerAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new(`$trustedSidValue),
        [Security.AccessControl.FileSystemRights]::FullControl,
        `$inheritance,
        `$none,
        `$allow
    ))
}
`$locks = [System.Collections.Generic.Dictionary[string, IO.FileStream]]::new([StringComparer]::OrdinalIgnoreCase)
`$cleanupWarnings = [System.Collections.Generic.List[string]]::new()
`$protectedProjectRoot = `$null
`$statusReady = `$false
# Container hardening belongs inside the try. Its finally block is the only code
# that hands access back to the launching user, so a failure above it would leave
# an Administrators-only directory the unelevated parent can neither read nor delete.
try {
Set-Acl -LiteralPath `$verifiedContainer -AclObject `$containerAcl -ErrorAction Stop
if (`$null -ne (Get-Item -LiteralPath '$escapedStatusPath' -Force -ErrorAction SilentlyContinue)) {
    throw 'Elevation cancelled because the elevation status file already existed before it was created.'
}
`$statusStream = [IO.File]::Open('$escapedStatusPath', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
`$statusStream.Dispose()
# Only a status file this process created is ever written to, so a planted link
# in the still-unprotected container cannot redirect an administrator write.
`$statusReady = `$true
`$expectedContainerFiles += '$escapedStatusPath'
`$manifestAcl = [Security.AccessControl.FileSecurity]::new()
`$manifestAcl.SetAccessRuleProtection(`$true, `$false)
`$manifestAcl.SetOwner(`$administratorsSid)
foreach (`$trustedSidValue in 'S-1-5-18', 'S-1-5-32-544') {
    `$manifestAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new(`$trustedSidValue),
        [Security.AccessControl.FileSystemRights]::FullControl,
        `$allow
    ))
}
# Do not Set-Acl snapshot.json or bootstrap.ps1 here. The unelevated parent
# keeps FileShare.Read guards on those files for the whole elevated run, and
# Windows then denies WRITE_DAC ("Access to the path ... is denied").
if (@(Get-ChildItem -LiteralPath `$verifiedContainer -Force | Where-Object FullName -notin `$expectedContainerFiles).Count -gt 0) {
    throw 'Elevation cancelled because the protected snapshot container changed before it was secured.'
}
`$protectedProjectRoot = Join-Path `$verifiedContainer 'Project'
`$null = New-Item -ItemType Directory -Path `$protectedProjectRoot
if ([string]::IsNullOrWhiteSpace([string]`$snapshot.RuntimeRoot)) {
    throw 'Elevation cancelled because the verified snapshot does not contain the bundled Python runtime.'
}
`$runtimeRoot = [IO.Path]::GetFullPath([string]`$snapshot.RuntimeRoot)
foreach (`$verifiedPath in @(`$snapshot.ScriptPath, `$snapshot.WorkingDirectory, `$snapshot.ModuleSource, `$runtimeRoot) + @(`$snapshot.DependencyRoots) + @(`$snapshot.Records | ForEach-Object Path)) {
    `$item = Get-Item -LiteralPath `$verifiedPath -Force -ErrorAction Stop
    if (-not [string]::IsNullOrWhiteSpace([string]`$item.LinkType) -or `$null -ne `$item.Target) {
        throw "Elevation cancelled because a verified path became a symbolic link or junction: `$verifiedPath"
    }
}
foreach (`$verifiedRoot in @(`$snapshot.ModuleSource, `$runtimeRoot) + @(`$snapshot.DependencyRoots)) {
    foreach (`$item in Get-ChildItem -LiteralPath `$verifiedRoot -Recurse -Force -ErrorAction Stop) {
        if (-not [string]::IsNullOrWhiteSpace([string]`$item.LinkType) -or `$null -ne `$item.Target) {
            throw "Elevation cancelled because the verified source tree contains a symbolic link or junction: `$(`$item.FullName)"
        }
    }
}
`$currentFiles = [System.Collections.Generic.List[string]]::new()
`$currentFiles.Add([IO.Path]::GetFullPath([string]`$snapshot.ScriptPath))
foreach (`$file in Get-ChildItem -LiteralPath `$snapshot.ModuleSource -Recurse -File -Force -Include '*.ps1', '*.psm1', '*.psd1', '*.py') {
    `$currentFiles.Add([IO.Path]::GetFullPath(`$file.FullName))
}
foreach (`$dependencyRoot in @(`$snapshot.DependencyRoots)) {
    if (-not (Test-Path -LiteralPath `$dependencyRoot -PathType Container)) {
        throw "Elevation cancelled because a dependency directory disappeared: `$dependencyRoot"
    }
    foreach (`$file in Get-ChildItem -LiteralPath `$dependencyRoot -Recurse -File) {
        `$currentFiles.Add([IO.Path]::GetFullPath(`$file.FullName))
    }
}
if (-not (Test-Path -LiteralPath `$runtimeRoot -PathType Container)) {
    throw 'Elevation cancelled because the bundled Python runtime directory disappeared.'
}
foreach (`$file in Get-ChildItem -LiteralPath `$runtimeRoot -Recurse -File -Force -ErrorAction Stop) {
    `$currentFiles.Add([IO.Path]::GetFullPath(`$file.FullName))
}
`$expectedPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach (`$record in @(`$snapshot.Records)) { `$null = `$expectedPaths.Add([IO.Path]::GetFullPath([string]`$record.Path)) }
`$actualPaths = @(`$currentFiles | Sort-Object -Unique)
if (`$actualPaths.Count -ne `$expectedPaths.Count -or @(`$actualPaths | Where-Object { -not `$expectedPaths.Contains(`$_) }).Count -gt 0) {
    throw 'Elevation cancelled because the project, dependency, or runtime file inventory changed while the UAC prompt was open.'
}
    foreach (`$record in @(`$snapshot.Records)) {
        `$recordPath = [IO.Path]::GetFullPath([string]`$record.Path)
        if (-not (Test-Path -LiteralPath `$recordPath -PathType Leaf)) { throw "Elevation cancelled because a project file disappeared: `$recordPath" }
        `$stream = [IO.File]::Open(`$recordPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        # Registered before hashing so the finally block still releases the
        # write-denying handle if hashing itself fails.
        `$locks.Add(`$recordPath, `$stream)
        `$sha = [Security.Cryptography.SHA256]::Create()
        try { `$actual = [Convert]::ToHexString(`$sha.ComputeHash(`$stream)) }
        finally { `$sha.Dispose() }
        if (-not [string]::Equals(`$actual, [string]`$record.Hash, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Elevation cancelled because a project file changed while the UAC prompt was open: `$recordPath"
        }
    }
    foreach (`$record in @(`$snapshot.Records)) {
        `$recordPath = [IO.Path]::GetFullPath([string]`$record.Path)
        `$relativePath = [IO.Path]::GetRelativePath([string]`$snapshot.WorkingDirectory, `$recordPath)
        if (`$relativePath -eq '..' -or `$relativePath.StartsWith("..`$([IO.Path]::DirectorySeparatorChar)")) {
            throw "Elevation cancelled because a verified source escaped the project root: `$recordPath"
        }
        `$targetPath = Join-Path `$protectedProjectRoot `$relativePath
        `$targetDirectory = Split-Path -Parent `$targetPath
        if (-not (Test-Path -LiteralPath `$targetDirectory -PathType Container)) {
            `$null = New-Item -ItemType Directory -Path `$targetDirectory -Force
        }
        `$sourceStream = `$locks[`$recordPath]
        `$sourceStream.Position = 0
        `$targetStream = [IO.File]::Open(`$targetPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            `$sourceStream.CopyTo(`$targetStream)
            `$targetStream.Flush(`$true)
        }
        finally { `$targetStream.Dispose() }
        `$targetVerificationStream = [IO.File]::Open(`$targetPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            `$targetSha = [Security.Cryptography.SHA256]::Create()
            try { `$targetHash = [Convert]::ToHexString(`$targetSha.ComputeHash(`$targetVerificationStream)) }
            finally { `$targetSha.Dispose() }
        }
        finally { `$targetVerificationStream.Dispose() }
        if (-not [string]::Equals(`$targetHash, [string]`$record.Hash, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Elevation cancelled because the protected project copy did not match its verified source: `$recordPath"
        }
    }
    `$scriptRelativePath = [IO.Path]::GetRelativePath([string]`$snapshot.WorkingDirectory, [string]`$snapshot.ScriptPath)
    `$protectedScript = Join-Path `$protectedProjectRoot `$scriptRelativePath
    Set-Acl -LiteralPath '$escapedStatusPath' -AclObject `$manifestAcl -ErrorAction Stop
    [Environment]::SetEnvironmentVariable('AMD_ORIGINAL_USER_NAME', [string]`$identity.UserName, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ORIGINAL_USER_SID', [string]`$identity.UserSid, [EnvironmentVariableTarget]::Process)
    `$forwardedJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$argumentPayload'))
    # Direct assignment, never the result of an if-statement: a statement whose
    # only output is an empty collection assigns `$null, and splatting `$null
    # passes one `$null positional argument that an advanced entry point rejects.
    `$forwarded = @{}
    if (-not [string]::IsNullOrWhiteSpace(`$forwardedJson)) {
        foreach (`$forwardedSwitch in (ConvertFrom-Json -InputObject `$forwardedJson).PSObject.Properties) {
            if (`$forwardedSwitch.Name -notmatch '\A[A-Za-z][A-Za-z0-9]*\z' -or `$forwardedSwitch.Value -isnot [bool]) {
                throw 'The verified elevation argument payload contained an unsupported entry.'
            }
            `$forwarded[`$forwardedSwitch.Name] = [bool]`$forwardedSwitch.Value
        }
    }
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_ELEVATION', '1', [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_SNAPSHOT_PATH', `$manifestPath, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_SNAPSHOT_HASH', `$manifestHash, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_MODULE_ROOT', (Join-Path `$protectedProjectRoot 'Modules'), [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_RUNTIME_ROOT', (Join-Path `$protectedProjectRoot 'Runtime'), [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_MODULE_CONTAINER', `$verifiedContainer, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ORIGINAL_PROJECT_ROOT', [string]`$snapshot.WorkingDirectory, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ELEVATION_STATUS_PATH', '$escapedStatusPath', [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ELEVATION_STATUS_CONTAINER', `$verifiedContainer, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ELEVATION_STAGE', 'application', [EnvironmentVariableTarget]::Process)
    & `$protectedScript @forwarded
    `$childExitCode = if (`$null -eq `$LASTEXITCODE) { 1 } else { [int]`$LASTEXITCODE }
}
catch {
    `$failureStage = [string][Environment]::GetEnvironmentVariable('AMD_ELEVATION_STAGE', [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace(`$failureStage)) { `$failureStage = 'bootstrap' }
    `$failureInvocation = `$_.InvocationInfo
    `$failureScript = if (`$null -eq `$failureInvocation -or [string]::IsNullOrWhiteSpace([string]`$failureInvocation.ScriptName)) {
        '<inline>'
    }
    else { [IO.Path]::GetFileName([string]`$failureInvocation.ScriptName) }
    `$failureLine = if (`$null -eq `$failureInvocation) { 0 } else { [int]`$failureInvocation.ScriptLineNumber }
    `$failureLocation = '{0}:{1}' -f `$failureScript, `$failureLine
    `$failureText = if (`$failureStage -eq 'workflow') {
        # Only the location is forwarded: workflow messages can contain customer
        # data, and the entry point that owns them reports its own redacted text.
        # Reaching here means the failure escaped that reporting, and the elevated
        # console closes with it, so the message must not promise a preserved copy.
        "Verified elevation failed during the workflow stage at `$failureLocation without recording a redacted message, which means it escaped the entry point's own error reporting. Rerun the same step to reproduce it."
    }
    else {
        `$startupDetail = [regex]::Replace([string]`$_.Exception.Message, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ' ')
        `$startupDetail = `$startupDetail -replace '(?i)\b(authorization|x-api-key|api[-_ ]?key|apikey|password|secret|token)\b\s*[:=]\s*(?:bearer\s+)?\S+', '`$1: [REDACTED]'
        if (`$startupDetail.Length -gt 3500) { `$startupDetail = `$startupDetail.Substring(0, 3500) + '...' }
        "Verified elevation failed during the `$failureStage stage at `$failureLocation (`$(`$_.FullyQualifiedErrorId)): `$startupDetail"
    }
    if (`$statusReady) { [IO.File]::WriteAllText('$escapedStatusPath', `$failureText, [Text.Encoding]::UTF8) }
    throw
}
finally {
    foreach (`$stream in `$locks.Values) {
        try { `$stream.Dispose() }
        catch { `$cleanupWarnings.Add('A verified source-file lock could not be released cleanly.') }
    }
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_MODULE_ROOT', `$null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_RUNTIME_ROOT', `$null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_SNAPSHOT_PATH', `$null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_SNAPSHOT_HASH', `$null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_VERIFIED_MODULE_CONTAINER', `$null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ORIGINAL_PROJECT_ROOT', `$null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ELEVATION_STATUS_PATH', `$null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('AMD_ELEVATION_STATUS_CONTAINER', `$null, [EnvironmentVariableTarget]::Process)
    if (`$protectedProjectRoot -and (Test-Path -LiteralPath `$protectedProjectRoot)) {
        try { Remove-Item -LiteralPath `$protectedProjectRoot -Recurse -Force -ErrorAction Stop }
        catch { `$cleanupWarnings.Add('The protected project copy could not be fully removed.') }
    }
    if (`$verifiedContainer -and (Test-Path -LiteralPath `$verifiedContainer)) {
        `$cleanupAcl = [Security.AccessControl.DirectorySecurity]::new()
        `$cleanupAcl.SetAccessRuleProtection(`$true, `$false)
        `$cleanupAcl.SetOwner(`$originalUserSid)
        `$cleanupAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            `$originalUserSid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            `$inheritance,
            `$none,
            `$allow
        ))
        `$cleanupFileAcl = [Security.AccessControl.FileSecurity]::new()
        `$cleanupFileAcl.SetAccessRuleProtection(`$true, `$false)
        `$cleanupFileAcl.SetOwner(`$originalUserSid)
        `$cleanupFileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            `$originalUserSid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            `$allow
        ))
        # snapshot.json and bootstrap.ps1 still have the unelevated parent's
        # FileShare.Read guards at this point. Their original user-owned ACLs were
        # never changed, so restoring the container is sufficient and avoids a
        # WRITE_DAC attempt that Windows rejects while those guards are open.
        if (`$cleanupWarnings.Count -gt 0 -and `$statusReady) {
            try {
                `$existingStatus = [IO.File]::ReadAllText('$escapedStatusPath', [Text.Encoding]::UTF8)
                `$cleanupText = "Elevation cleanup warning: `$(`$cleanupWarnings -join ' ')"
                `$combinedStatus = if ([string]::IsNullOrWhiteSpace(`$existingStatus)) { `$cleanupText } else { "`$existingStatus``r``n`$cleanupText" }
                if (`$combinedStatus.Length -gt 4096) { `$combinedStatus = `$combinedStatus.Substring(0, 4093) + '...' }
                [IO.File]::WriteAllText('$escapedStatusPath', `$combinedStatus, [Text.Encoding]::UTF8)
            }
            catch { Write-Warning 'Elevation cleanup encountered an additional status-reporting failure.' -WarningAction Continue }
        }
        if (`$statusReady) {
            try { Set-Acl -LiteralPath '$escapedStatusPath' -AclObject `$cleanupFileAcl -ErrorAction Stop }
            catch {
                `$cleanupWarnings.Add('The elevation status permissions could not be returned to the launching user.')
            }
        }
        try { Set-Acl -LiteralPath `$verifiedContainer -AclObject `$cleanupAcl -ErrorAction Stop }
        catch {
            `$cleanupWarnings.Add('The elevation container permissions could not be returned to the launching user.')
        }
        foreach (`$cleanupWarning in `$cleanupWarnings) { Write-Warning `$cleanupWarning -WarningAction Continue }
    }
}
exit `$childExitCode
"@
        $bootstrapBytes = [Text.Encoding]::UTF8.GetBytes($bootstrap)
        $bootstrapHash = Get-AmdSha256Hex -Bytes $bootstrapBytes
        $bootstrapLock = Write-AmdProtectedElevationFile `
            -Path $bootstrapPath `
            -Bytes $bootstrapBytes `
            -ExpectedHash $bootstrapHash `
            -Description 'elevation bootstrap'
        $bootstrapCreated = $true
        $escapedBootstrapHash = $bootstrapHash.Replace("'", "''")
        $loader = @"
`$ErrorActionPreference = 'Stop'
`$bootstrapStream = [IO.File]::Open('$escapedBootstrapPath', [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    if (`$bootstrapStream.Length -le 0 -or `$bootstrapStream.Length -gt 1MB) { throw 'The verified elevation bootstrap has an invalid size.' }
    # Read the bootstrap once into memory, then hash and execute those exact
    # bytes. Re-reading the handle after hashing would reopen a check/use window.
    `$bootstrapBuffer = [byte[]]::new([int]`$bootstrapStream.Length)
    `$bootstrapOffset = 0
    while (`$bootstrapOffset -lt `$bootstrapBuffer.Length) {
        `$bootstrapRead = `$bootstrapStream.Read(`$bootstrapBuffer, `$bootstrapOffset, `$bootstrapBuffer.Length - `$bootstrapOffset)
        if (`$bootstrapRead -le 0) { throw 'The verified elevation bootstrap could not be read completely.' }
        `$bootstrapOffset += `$bootstrapRead
    }
    if (`$bootstrapStream.Read([byte[]]::new(1), 0, 1) -ne 0) { throw 'The verified elevation bootstrap grew while it was being read.' }
}
finally { `$bootstrapStream.Dispose() }
`$sha = [Security.Cryptography.SHA256]::Create()
try { `$actualHash = [Convert]::ToHexString(`$sha.ComputeHash(`$bootstrapBuffer)) }
finally { `$sha.Dispose() }
if (-not [string]::Equals(`$actualHash, '$escapedBootstrapHash', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Elevation cancelled because the verified bootstrap changed while the UAC prompt was open.'
}
`$bootstrapText = [Text.Encoding]::UTF8.GetString(`$bootstrapBuffer)
try {
    & ([ScriptBlock]::Create(`$bootstrapText))
}
catch {
    # `$ErrorActionPreference is 'Stop' here, so a bare Write-Error would be
    # terminating and would skip the exit code below. Never echo the original
    # exception here: workflow failures can contain credentials or customer data.
    # The parent process reads the bounded, redacted status file instead.
    Write-Error 'The verified elevated process failed. Review the redacted status message in the original console.' -ErrorAction Continue
    exit 1
}
"@
        $encodedBootstrap = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($loader))
        if ($encodedBootstrap.Length -gt 28000) {
            throw 'The verified elevation loader is too large for the Windows command line.'
        }
        $arguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in @('-NoLogo', '-NoProfile')) { $arguments.Add($argument) }
        if ($Sta) { $arguments.Add('-STA') }
        foreach ($argument in @(
            '-ExecutionPolicy'
            'Bypass'
            '-EncodedCommand'
            $encodedBootstrap
        )) {
            $arguments.Add($argument)
        }

        # Resolved before the Start-Process try below so a failed PowerShell
        # verification keeps its own message instead of being reported as a
        # declined UAC prompt.
        $pwshPath = Get-AmdCurrentPwshPath
        try {
            $process = Start-Process -FilePath $pwshPath `
                -Verb RunAs `
                -ArgumentList $arguments.ToArray() `
                -WorkingDirectory $resolvedDirectory `
                -Wait `
                -PassThru `
                -ErrorAction Stop
        }
        catch {
            throw "Administrator access is required. Approve the Windows UAC prompt and try again. $($_.Exception.Message)"
        }
        # [int]$null is 0, so an elevated run that ended without a usable exit code
        # would be reported to the caller as a clean success.
        $elevatedExitCode = if ($null -eq $process -or $null -eq $process.ExitCode) { 1 } else { [int]$process.ExitCode }
        if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
            $rawElevatedStatus = Get-Content -LiteralPath $statusPath -Raw -ErrorAction SilentlyContinue
            $elevatedStatus = if ($null -eq $rawElevatedStatus) { '' } else { ([string]$rawElevatedStatus).Trim() }
            if (-not [string]::IsNullOrWhiteSpace($elevatedStatus)) {
                if ($elevatedExitCode -ne 0) {
                    Write-Host "`n$elevatedStatus" -ForegroundColor Red
                }
                else {
                    Write-Warning $elevatedStatus -WarningAction Continue
                }
            }
        }
        return $elevatedExitCode
    }
    finally {
        if ($null -ne $manifestLock) {
            try { $manifestLock.Dispose() }
            catch { Write-Warning 'The local elevation manifest lock could not be released cleanly.' -WarningAction Continue }
        }
        if ($null -ne $bootstrapLock) {
            try { $bootstrapLock.Dispose() }
            catch { Write-Warning 'The local elevation bootstrap lock could not be released cleanly.' -WarningAction Continue }
        }
        if ($bootstrapCreated -and (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
            try { Remove-Item -LiteralPath $bootstrapPath -Force -ErrorAction Stop }
            catch { Write-Warning 'The temporary elevation bootstrap could not be removed. Delete the stale AXCIENT-MAGIC-DASH snapshot from the current user temp directory.' -WarningAction Continue }
        }
        if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
            try { Remove-Item -LiteralPath $statusPath -Force -ErrorAction Stop }
            catch { Write-Warning 'The temporary elevation status file could not be removed. Delete the stale AXCIENT-MAGIC-DASH snapshot from the current user temp directory.' -WarningAction Continue }
        }
        if ($manifestCreated -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            try { Remove-Item -LiteralPath $manifestPath -Force -ErrorAction Stop }
            catch { Write-Warning 'The temporary elevation manifest could not be removed. Delete the stale AXCIENT-MAGIC-DASH snapshot from the current user temp directory.' -WarningAction Continue }
        }
        if (Test-Path -LiteralPath $manifestContainer -PathType Container) {
            try { Remove-Item -LiteralPath $manifestContainer -Recurse -Force -ErrorAction Stop }
            catch { Write-Warning 'The temporary elevation snapshot directory could not be removed. Delete the stale AXCIENT-MAGIC-DASH snapshot from the current user temp directory.' -WarningAction Continue }
        }
    }
}
