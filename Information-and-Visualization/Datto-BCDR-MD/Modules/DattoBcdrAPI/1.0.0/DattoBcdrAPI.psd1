@{
    RootModule        = 'DattoBcdrAPI.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c2f4a1d6-8b3e-4d59-9a72-6f1c0b5e4d38'
    Author            = 'Hudu Technologies'
    CompanyName       = 'Hudu Technologies, Inc.'
    Copyright         = '(c) Hudu Technologies, Inc. All rights reserved.'
    Description       = 'Datto BCDR REST API client for the DATTO-BCDR-MAGIC-DASH integration. Replaces the AxcientAPI module used by the Axcient build, exporting the same command names and object shapes over Datto endpoints.'
    PowerShellVersion = '7.2'

    # Same names the Axcient build called, so the application is unchanged.
    FunctionsToExport = @(
        'Initialize-DattoBcdrAPI',
        'Clear-DattoBcdrCache',
        'Invoke-DattoBcdrAPI',
        'Get-Client',
        'Get-Device',
        'Get-Appliance',
        'Get-DattoBcdrApplianceAssets',
        'Get-DattoBcdrApplianceDetail',
        'Get-DattoBcdrApplianceAlertCount',
        'Get-DattoBcdrAlertRule',
        'Get-DattoBcdrDtcAssetCount',
        'Get-DattoBcdrApplianceAgent',
        'Get-DattoBcdrApplianceShare',
        'Get-DattoBcdrApplianceTypedAssets',
        'Get-DattoBcdrVmRestore',
        'ConvertTo-DattoBcdrDevice',
        'ConvertTo-DattoBcdrAppliance',
        'ConvertTo-DattoBcdrByteSize',
        'ConvertTo-DattoBcdrUtcString',
        'ConvertFrom-DattoBcdrClientPayload',
        'ConvertFrom-DattoBcdrDeviceClients',
        'ConvertTo-DattoBcdrNumericId',
        'Get-DattoBcdrProperty',
        'Get-DattoBcdrClientSerials',
        'Get-DattoBcdrPartnerData'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('Datto', 'BCDR', 'Backup', 'Hudu', 'MagicDash')
            ProjectUri = 'https://auth.datto.com/login'
        }
    }
}
