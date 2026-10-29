#requires -Version 7.2

$moduleFiles = @(
    'Private\Core.ps1'
    'Private\HuduBridge.ps1'
    'Private\Elevation.ps1'
    'Private\Templates.ps1'
    'Public\Configuration.ps1'
    'Public\HuduClient.ps1'
    'Public\Connection.ps1'
    'Public\Dependencies.ps1'
    'Public\Lock.ps1'
    'Public\Matching.ps1'
    'Public\Schedule.ps1'
    'Public\Sync.ps1'
)

foreach ($relativePath in $moduleFiles) {
    $filePath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Required AXCIENT-MAGIC-DASH module file is missing: $relativePath"
    }
    try {
        . $filePath
    }
    catch {
        throw "Failed to load AXCIENT-MAGIC-DASH module file '$relativePath': $($_.Exception.Message)"
    }
}

# Import-Module -Force removes the previous module instance before loading this
# one. Close its persistent Hudu child while its module-scoped state is still
# reachable instead of leaving process cleanup to host exit or garbage collection.
$ExecutionContext.SessionState.Module.OnRemove = {
    try { Stop-AmdHuduBridge }
    catch {
        Write-Verbose "The Hudu bridge could not be closed during module removal: $(ConvertTo-AmdRedactedText $_.Exception.Message)"
    }
}
