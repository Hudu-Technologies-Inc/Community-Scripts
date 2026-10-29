function Test-AmdTrustedProjectDirectoryAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][Security.Principal.SecurityIdentifier]$OperatingUserSid
    )

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    if (-not $acl.AreAccessRulesProtected) { return $false }
    try {
        $ownerSid = $acl.Owner.Translate([Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        try { $ownerSid = ([Security.Principal.NTAccount]::new([string]$acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { return $false }
    }
    if ($ownerSid -notin 'S-1-5-18', 'S-1-5-32-544') { return $false }
    $trustedFullControl = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null = $trustedFullControl.Add('S-1-5-18')
    $null = $trustedFullControl.Add('S-1-5-32-544')
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { return $false }
        try {
            $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        }
        catch {
            return $false
        }
        if ($trustedFullControl.Contains($sid)) { continue }
        $expectedUserRights =
            [Security.AccessControl.FileSystemRights]::ReadAndExecute -bor
            [Security.AccessControl.FileSystemRights]::Synchronize
        if (-not [string]::Equals($sid, $OperatingUserSid.Value, [StringComparison]::OrdinalIgnoreCase) -or
            [Security.AccessControl.FileSystemRights]$rule.FileSystemRights -ne $expectedUserRights) {
            return $false
        }
    }
    return $true
}

function Initialize-AmdProjectLock {
    [CmdletBinding()]
    param()

    $programData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    $directory = Join-Path $programData 'AXCIENT-MAGIC-DASH'
    $path = Join-Path $directory 'runtime.lock'
    $isAdministrator = Test-AmdAdministrator

    if ($isAdministrator) {
        $operatingUserSid = Get-AmdOperatingUserSid
        $directoryAcl = [Security.AccessControl.DirectorySecurity]::new()
        $directoryAcl.SetAccessRuleProtection($true, $false)
        $directoryAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
        $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $none = [Security.AccessControl.PropagationFlags]::None
        $allow = [Security.AccessControl.AccessControlType]::Allow
        foreach ($identity in @(
            [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
            [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
        )) {
            $directoryAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance,
                $none,
                $allow
            ))
        }
        $directoryAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $operatingUserSid,
            [Security.AccessControl.FileSystemRights]::ReadAndExecute,
            $inheritance,
            $none,
            $allow
        ))
        if (Test-Path -LiteralPath $directory -PathType Container) {
            Assert-AmdNotFileSystemLink -Path $directory
            if (-not (Test-AmdTrustedProjectDirectoryAcl -Path $directory -OperatingUserSid $operatingUserSid)) {
                throw "The protected runtime directory '$directory' already exists with untrusted permissions. Remove or rename it as an administrator, then rerun AXCIENT-MAGIC-DASH."
            }
        }
        else {
            $stagingDirectory = Join-Path $programData "AXCIENT-MAGIC-DASH.$([Guid]::NewGuid().ToString('N')).tmp"
            try {
                $null = New-Item -ItemType Directory -Path $stagingDirectory
                Set-Acl -LiteralPath $stagingDirectory -AclObject $directoryAcl -ErrorAction Stop
                Move-Item -LiteralPath $stagingDirectory -Destination $directory -ErrorAction Stop
            }
            catch {
                if (Test-Path -LiteralPath $stagingDirectory) {
                    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
                }
                throw "The protected runtime directory could not be created atomically. Another process may have created '$directory' with untrusted permissions. $($_.Exception.Message)"
            }
        }
        Set-Acl -LiteralPath $directory -AclObject $directoryAcl -ErrorAction Stop

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Assert-AmdNotFileSystemLink -Path $path
        }
        else {
            $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $stream.Dispose()
        }
        $fileAcl = [Security.AccessControl.FileSecurity]::new()
        $fileAcl.SetAccessRuleProtection($true, $false)
        $fileAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
        foreach ($identity in @(
            [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
            [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
        )) {
            $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                $allow
            ))
        }
        $userRights =
            [Security.AccessControl.FileSystemRights]::ReadData -bor
            [Security.AccessControl.FileSystemRights]::WriteData -bor
            [Security.AccessControl.FileSystemRights]::AppendData -bor
            [Security.AccessControl.FileSystemRights]::ReadAttributes -bor
            [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
            [Security.AccessControl.FileSystemRights]::ReadExtendedAttributes -bor
            [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
            [Security.AccessControl.FileSystemRights]::ReadPermissions -bor
            [Security.AccessControl.FileSystemRights]::Synchronize
        $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $operatingUserSid,
            $userRights,
            $allow
        ))
        Set-Acl -LiteralPath $path -AclObject $fileAcl -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $directory -PathType Container) -or
        -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'The protected cross-session lock has not been initialized. Run run.ps1 and approve UAC before the next scheduled sync.'
    }
    foreach ($itemPath in $directory, $path) {
        $item = Get-Item -LiteralPath $itemPath -Force -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$item.LinkType) -or $null -ne $item.Target) {
            throw "The protected cross-session lock path cannot be a symbolic link or junction: $itemPath"
        }
    }
    return $path
}

function Enter-AmdProjectLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Purpose = 'update'
    )

    $stream = $null
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$item.LinkType) -or $null -ne $item.Target) {
            throw 'The cross-session lock file cannot be a symbolic link or junction.'
        }
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        return $stream
    }
    catch {
        $lockError = $_
        if ($null -ne $stream) {
            try { $stream.Dispose() }
            catch { Write-Verbose "A partially acquired project lock could not be disposed cleanly: $($_.Exception.Message)" }
        }
        $currentException = $lockError.Exception
        $isSharingFailure = $false
        while ($null -ne $currentException) {
            if ($currentException -is [IO.IOException] -and (($currentException.HResult -band 0xFFFF) -in 32, 33)) {
                $isSharingFailure = $true
                break
            }
            $currentException = $currentException.InnerException
        }
        if ($isSharingFailure) {
            throw "Another AXCIENT-MAGIC-DASH process is already running. This $Purpose was safely stopped to prevent overlapping configuration and Hudu writes."
        }
        throw "The cross-session project lock at '$Path' could not be acquired. Check folder permissions. $($lockError.Exception.Message)"
    }
}

function Exit-AmdProjectLock {
    [CmdletBinding()]
    param(
        [AllowNull()]$LockStream,
        [Parameter(Mandatory)][string]$Path
    )

    # The Hudu sidecar is session-scoped and must never outlive either a manual
    # run or a scheduled run, even when lock acquisition failed before a stream
    # was returned.
    Disconnect-AmdHudu
    if ($null -eq $LockStream) { return }
    try { $LockStream.Dispose() }
    catch { Write-Verbose "The project lock was already released: $($_.Exception.Message)" }
    Write-Verbose "Released the protected cross-session lock at '$Path'."
}
