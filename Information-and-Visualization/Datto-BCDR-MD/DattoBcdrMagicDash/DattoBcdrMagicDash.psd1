@{
    RootModule        = 'DattoBcdrMagicDash.psm1'
    ModuleVersion     = '2.4.0'
    GUID              = 'b86a431a-291b-4c14-a03a-25a7c0d756c8'
    Author            = 'Hudu Technologies, Inc.'
    CompanyName       = 'Hudu Technologies, Inc.'
    Copyright         = '(c) Hudu Technologies, Inc. All rights reserved.'
    Description       = 'Setup, matching, scheduling, and sync engine for DATTO-BCDR-MAGIC-DASH.'
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Archive-DbmHuduAsset',
        'Connect-DbmHudu',
        'Connect-DbmServices',
        'ConvertTo-DbmNormalizedApiKey',
        'ConvertTo-NormalizedHuduUrl',
        'ConvertTo-DbmRedactedText',
        'Complete-DbmAssetLayoutBinding',
        'Complete-DbmSetupScheduleFinalization',
        'Enter-DbmProjectLock',
        'Exit-DbmProjectLock',
        'Disconnect-DbmHudu',
        'Get-DbmApiFailureMessage',
        'Get-DbmDattoClient',
        'Get-DbmHuduAppInfo',
        'Get-DbmHuduAsset',
        'Get-DbmHuduAssetLayout',
        'Get-DbmHuduCompany',
        'Get-DbmHuduMagicDash',
        'Get-DbmUnownedLegacyMagicDashCandidates',
        'Get-DbmSchedule',
        'Import-DbmRequiredModules',
        'Initialize-DbmProjectLock',
        'Initialize-DbmVerifiedModuleSnapshot',
        'Invoke-DbmMatchOperations',
        'Invoke-DbmPendingOperations',
        'Invoke-DbmSync',
        'New-DbmHuduAssetLayout',
        'New-DbmMatchRows',
        'Protect-DbmSecret',
        'Read-DbmConfig',
        'Read-DbmScheduleSelection',
        'Remove-DbmHuduMagicDash',
        'Remove-DbmSchedule',
        'Resolve-DbmMissingMoveDestinations',
        'Reset-DbmHuduScopedSettings',
        'Save-DbmConfig',
        'Set-DbmSensitiveValues',
        'Set-DbmSchedule',
        'Set-DbmHuduAsset',
        'Set-DbmHuduAssetLayoutActive',
        'Add-DbmHuduAssetLayoutDetailsField',
        'Set-DbmHuduMagicDash',
        'Set-DbmHuduMagicDashForCompany',
        'Show-DbmMatchingWindow',
        'Show-DbmSyncSummary',
        'Sync-DbmScheduleState',
        'Test-DbmDattoConnection',
        'Test-DbmHuduConnection',
        'Test-DbmHuduReachability',
        'Update-DbmAutomaticMatches',
        'Update-DbmMatchExclusions',
        'Update-DbmScheduleConfiguration',
        'Unprotect-DbmSecret'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Hudu', 'Datto', 'MagicDash', 'Windows')
            ProjectUri = 'https://github.com/adamburley/Hudu-Datto-Dashboard'
        }
    }
}
