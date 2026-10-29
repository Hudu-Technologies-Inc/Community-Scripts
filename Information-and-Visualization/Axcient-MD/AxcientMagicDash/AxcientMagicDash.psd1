@{
    RootModule        = 'AxcientMagicDash.psm1'
    ModuleVersion     = '2.4.0'
    GUID              = 'b86a431a-291b-4c14-a03a-25a7c0d756c8'
    Author            = 'Hudu Technologies, Inc.'
    CompanyName       = 'Hudu Technologies, Inc.'
    Copyright         = '(c) Hudu Technologies, Inc. All rights reserved.'
    Description       = 'Setup, matching, scheduling, and sync engine for AXCIENT-MAGIC-DASH.'
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Archive-AmdHuduAsset',
        'Connect-AmdHudu',
        'Connect-AmdServices',
        'ConvertTo-AmdNormalizedApiKey',
        'ConvertTo-NormalizedHuduUrl',
        'ConvertTo-AmdRedactedText',
        'Complete-AmdAssetLayoutBinding',
        'Complete-AmdSetupScheduleFinalization',
        'Enter-AmdProjectLock',
        'Exit-AmdProjectLock',
        'Disconnect-AmdHudu',
        'Get-AmdApiFailureMessage',
        'Get-AmdAxcientClient',
        'Get-AmdHuduAppInfo',
        'Get-AmdHuduAsset',
        'Get-AmdHuduAssetLayout',
        'Get-AmdHuduCompany',
        'Get-AmdHuduMagicDash',
        'Get-AmdUnownedLegacyMagicDashCandidates',
        'Get-AmdSchedule',
        'Import-AmdRequiredModules',
        'Initialize-AmdProjectLock',
        'Initialize-AmdVerifiedModuleSnapshot',
        'Invoke-AmdMatchOperations',
        'Invoke-AmdPendingOperations',
        'Invoke-AmdSync',
        'New-AmdHuduAssetLayout',
        'New-AmdMatchRows',
        'Protect-AmdSecret',
        'Read-AmdConfig',
        'Read-AmdScheduleSelection',
        'Remove-AmdHuduMagicDash',
        'Remove-AmdSchedule',
        'Resolve-AmdMissingMoveDestinations',
        'Reset-AmdHuduScopedSettings',
        'Save-AmdConfig',
        'Set-AmdSensitiveValues',
        'Set-AmdSchedule',
        'Set-AmdHuduAsset',
        'Set-AmdHuduAssetLayoutActive',
        'Add-AmdHuduAssetLayoutDetailsField',
        'Set-AmdHuduMagicDash',
        'Set-AmdHuduMagicDashForCompany',
        'Show-AmdMatchingWindow',
        'Show-AmdSyncSummary',
        'Sync-AmdScheduleState',
        'Test-AmdAxcientConnection',
        'Test-AmdHuduConnection',
        'Test-AmdHuduReachability',
        'Update-AmdAutomaticMatches',
        'Update-AmdMatchExclusions',
        'Update-AmdScheduleConfiguration',
        'Unprotect-AmdSecret'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Hudu', 'Axcient', 'MagicDash', 'Windows')
            ProjectUri = 'https://github.com/adamburley/Hudu-Axcient-Dashboard'
        }
    }
}
