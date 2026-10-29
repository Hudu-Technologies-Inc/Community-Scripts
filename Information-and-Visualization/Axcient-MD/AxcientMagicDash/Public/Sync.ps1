$script:AmdMagicDashOwnershipMarker = '<!-- AXCIENT-MAGIC-DASH:managed:v1 -->'

function Test-AmdOwnedMagicDash {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dash)

    return ([string](Get-AmdConfigProperty $Dash 'content' '')).Contains(
        $script:AmdMagicDashOwnershipMarker,
        [StringComparison]::Ordinal
    )
}

function Test-AmdPossibleLegacyMagicDash {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dash)

    $title = ([string](Get-AmdConfigProperty $Dash 'title' '')).Trim()
    if (-not [string]::Equals($title, 'Axcient X360Recover', [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (Test-AmdOwnedMagicDash -Dash $Dash) {
        return $false
    }

    $legacyText = '{0}`n{1}' -f @(
        [string](Get-AmdConfigProperty $Dash 'content' '')
        [string](Get-AmdConfigProperty $Dash 'message' '')
    )
    foreach ($hint in @(
            'AXCIENT-MAGIC-DASH'
            'x360Recover'
            'Stale backup threshold'
            'nasa__block'
            'partner.axcient.com'
            'my.axcient.net'
        )) {
        if ($legacyText.IndexOf($hint, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Get-AmdUnownedLegacyMagicDashCandidates {
    [CmdletBinding()]
    param()

    try {
        $companies = @(Get-AmdHuduCompany -ErrorAction Stop)
    }
    catch {
        Write-Warning "The optional legacy Magic Dash scan could not list Hudu companies. Continuing without cleanup. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)" -WarningAction Continue
        return @()
    }

    $seenDashIds = [System.Collections.Generic.HashSet[int64]]::new()
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($company in $companies | Sort-Object name, id) {
        $companyId = Get-AmdMatchingId (Get-AmdConfigProperty $company 'id')
        if ($null -eq $companyId) {
            Write-Warning 'The optional legacy Magic Dash scan skipped a Hudu company with no valid ID.' -WarningAction Continue
            continue
        }
        $companyName = [string](Get-AmdConfigProperty $company 'name' "Hudu company $companyId")
        try {
            $dashes = @(Get-AmdHuduMagicDash `
                    -CompanyId $companyId `
                    -Title 'Axcient X360Recover' `
                    -ErrorAction Stop)
        }
        catch {
            $safeCompanyName = ConvertTo-AmdBoundedDiagnosticText -Text $companyName -MaximumLength 160
            Write-Warning "The optional legacy Magic Dash scan could not check '$safeCompanyName' (Hudu ID $companyId). That company was skipped. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)" -WarningAction Continue
            continue
        }

        foreach ($dash in $dashes) {
            if (-not (Test-AmdPossibleLegacyMagicDash -Dash $dash)) { continue }
            $dashId = Get-AmdMatchingId (Get-AmdConfigProperty $dash 'id')
            if ($null -eq $dashId) { continue }
            $returnedCompanyId = Get-AmdMatchingId (Get-AmdConfigProperty $dash 'company_id')
            if ($null -ne $returnedCompanyId -and $returnedCompanyId -ne $companyId) {
                Write-Warning "The optional legacy Magic Dash scan ignored dash ID $dashId because Hudu returned it outside the requested company scope." -WarningAction Continue
                continue
            }
            if (-not $seenDashIds.Add($dashId)) { continue }
            $candidates.Add([pscustomobject]@{
                    CompanyId   = $companyId
                    CompanyName = $companyName
                    DashId      = $dashId
                })
        }
    }
    return @($candidates)
}

function Assert-AmdMagicDashOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int64]$CompanyId,
        [Parameter(Mandatory)][string]$CompanyName
    )

    $collisions = @(Get-AmdHuduMagicDash -CompanyId $CompanyId -Title 'Axcient X360Recover' -ErrorAction Stop)
    foreach ($dash in $collisions) {
        $dashId = Get-AmdMatchingId $dash.id
        $dashCompanyId = Get-AmdMatchingId $dash.company_id
        if ($null -eq $dashId -or
            $dashCompanyId -ne $CompanyId -or
            -not [string]::Equals(
                ([string]$dash.title).Trim(),
                'Axcient X360Recover',
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Hudu returned a Magic Dash outside company ID $CompanyId and title 'Axcient X360Recover'. No Magic Dash mutation was attempted."
        }
    }
    $unowned = @($collisions | Where-Object { -not (Test-AmdOwnedMagicDash -Dash $_) })
    if ($unowned.Count -gt 0) {
        throw "Hudu company '$CompanyName' already has an unowned Magic Dash titled 'Axcient X360Recover'. Rename or remove that collision manually; AXCIENT-MAGIC-DASH will not overwrite it."
    }
    if ($collisions.Count -gt 1) {
        throw "Hudu company '$CompanyName' has multiple owned Magic Dashes titled 'Axcient X360Recover'. Consolidate them manually; AXCIENT-MAGIC-DASH will not choose one or delete duplicates."
    }
    return $collisions
}

function Get-AmdDeviceAssetDetailsHtml {
    [CmdletBinding()]
    param([AllowNull()]$Asset)

    foreach ($field in @(Get-AmdConfigProperty $Asset 'custom_fields' @())) {
        if ($null -eq $field) { continue }
        $names = @($field.PSObject.Properties.Name)
        if ($names -contains 'Asset Details') {
            return [string]$field.'Asset Details'
        }
        $label = [string](Get-AmdConfigProperty $field 'label' '')
        if ([string]::Equals($label, 'Asset Details', [StringComparison]::OrdinalIgnoreCase)) {
            return [string](Get-AmdConfigProperty $field 'value' '')
        }
    }
    return [string](Get-AmdConfigProperty $Asset 'content' '')
}

function Get-AmdOwnedDeviceAssetAxcientId {
    [CmdletBinding()]
    param([AllowNull()]$Asset)

    $html = Get-AmdDeviceAssetDetailsHtml -Asset $Asset
    $markerMatch = [regex]::Match(
        $html,
        [regex]::Escape($script:AmdDeviceCardOwnershipMarkerPrefix) + '(\d+) -->'
    )
    if ($markerMatch.Success) {
        return ConvertTo-AmdPositiveId $markerMatch.Groups[1].Value
    }
    return $null
}

function Test-AmdOwnedDeviceAsset {
    [CmdletBinding()]
    param([AllowNull()]$Asset)

    $html = Get-AmdDeviceAssetDetailsHtml -Asset $Asset
    return $html.Contains($script:AmdDeviceCardOwnershipMarkerPrefix, [StringComparison]::Ordinal)
}

function Get-AmdBoundDeviceAssetLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Summary
    )

    $layoutId = ConvertTo-AmdAssetLayoutId (Get-AmdConfigProperty $Config 'assetLayoutId')
    if ($null -eq $layoutId) {
        return $null
    }
    $storedName = [string](Get-AmdConfigProperty $Config 'assetLayoutName' '')
    $Summary.BoundLayoutId = $layoutId
    $Summary.BoundLayoutName = $storedName
    $Summary.BoundLayoutActive = $null
    $Summary.BoundLayoutUsable = $false
    try {
        $layout = Get-AmdHuduAssetLayout -Id $layoutId -ErrorAction Stop
    }
    catch {
        $Summary.Warnings.Add("Device assets were skipped because Hudu asset layout ID $layoutId could not be read. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        return $null
    }
    $activeValue = Get-AmdConfigProperty $layout 'active'
    $isActive = $activeValue -eq $true -or [string]$activeValue -eq '1'
    $actualName = [string](Get-AmdConfigProperty $layout 'name' '')
    if (-not [string]::IsNullOrWhiteSpace($actualName)) {
        $Summary.BoundLayoutName = $actualName
    }
    $Summary.BoundLayoutActive = $isActive
    if (-not [string]::IsNullOrWhiteSpace($storedName) -and
        -not [string]::Equals($storedName, $actualName, [StringComparison]::OrdinalIgnoreCase)) {
        $Summary.Warnings.Add("Bound Hudu asset layout ID $layoutId is named '$actualName', not the stored name '$storedName'. Device assets are written to layout $layoutId. Confirm that is the layout you are viewing in Hudu.")
    }
    if (-not $isActive -or -not (Test-AmdAssetLayoutHasDetailsField -Layout $layout)) {
        $Summary.Warnings.Add("Device assets were skipped because Hudu asset layout ID $layoutId is inactive or no longer has a RichText Asset Details field.")
        return $null
    }
    $Summary.BoundLayoutUsable = $true
    return $layout
}

function Get-AmdDeviceDisplayName {
    [CmdletBinding()]
    param(
        [AllowNull()]$Device,
        [Parameter(Mandatory)][int64]$DeviceId
    )

    $name = [string](Get-AmdConfigProperty $Device 'name' '')
    if ([string]::IsNullOrWhiteSpace($name)) {
        return "Axcient device ($DeviceId)"
    }
    return "$($name.Trim()) ($DeviceId)"
}

function New-AmdOwnedDeviceAssetSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int64]$CompanyId,
        [Parameter(Mandatory)][int64]$LayoutId,
        [Parameter(Mandatory)][int64]$DeviceId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Content
    )

    try {
        $created = Set-AmdHuduAsset `
            -CompanyId $CompanyId `
            -LayoutId $LayoutId `
            -Name $Name `
            -PrimarySerial ([string]$DeviceId) `
            -Content $Content `
            -Confirm:$false `
            -ErrorAction Stop
        return [pscustomobject]@{ Asset = $created; Reconciled = $false }
    }
    catch {
        $createError = $_
        try {
            $refreshed = @(
                Invoke-AmdWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                    Get-AmdHuduAsset -CompanyId $CompanyId -LayoutId $LayoutId -ErrorAction Stop
                }
            )
        }
        catch {
            throw "The device asset create failed and its result could not be reconciled safely. Create error: $(ConvertTo-AmdBoundedDiagnosticText -Text $createError.Exception.Message) Reconciliation error: $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)"
        }
        $ownedMatches = @(
            $refreshed | Where-Object {
                (Test-AmdOwnedDeviceAsset -Asset $_) -and
                (Get-AmdOwnedDeviceAssetAxcientId -Asset $_) -eq $DeviceId
            }
        )
        if ($ownedMatches.Count -eq 1) {
            return [pscustomobject]@{ Asset = $ownedMatches[0]; Reconciled = $true }
        }
        if ($ownedMatches.Count -gt 1) {
            throw "Hudu contains $($ownedMatches.Count) owned device assets for Axcient device ID $DeviceId after a failed create. No retry was attempted."
        }
        throw $createError
    }
}

function Sync-AmdCompanyDeviceAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$HuduCompany,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Devices,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Summary,
        [AllowNull()]$Layout,
        [AllowNull()]$Client
    )

    if ($null -eq $Layout) {
        $configuredLayoutId = ConvertTo-AmdAssetLayoutId (Get-AmdConfigProperty $Config 'assetLayoutId')
        if ($null -eq $configuredLayoutId -and -not (@($Summary.Warnings) -contains 'Device assets were skipped because no Hudu asset layout is bound. Use run.ps1 menu option 9 to create or repair the layout.')) {
            $Summary.Warnings.Add('Device assets were skipped because no Hudu asset layout is bound. Use run.ps1 menu option 9 to create or repair the layout.')
        }
        $Summary.AssetsSkipped += @($Devices).Count
        return
    }

    $companyId = Get-AmdMatchingId $HuduCompany.id
    $layoutId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $Layout 'id')
    if ($null -eq $companyId -or $null -eq $layoutId) {
        $Summary.Warnings.Add("Device assets were skipped for '$([string]$HuduCompany.name)' because the Hudu company or layout ID was invalid.")
        return
    }

    try {
        $existing = @(
            Invoke-AmdWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                Get-AmdHuduAsset -CompanyId $companyId -LayoutId $layoutId -ErrorAction Stop
            }
        )
    }
    catch {
        $Summary.Warnings.Add("Device assets were skipped for '$([string]$HuduCompany.name)' because the layout assets could not be listed. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        return
    }

    $ownedByAxcientId = @{}
    $ambiguousOwnedIds = [System.Collections.Generic.HashSet[int64]]::new()
    $invalidOwnedAssetIds = [System.Collections.Generic.HashSet[int64]]::new()
    foreach ($asset in $existing) {
        if (-not (Test-AmdOwnedDeviceAsset -Asset $asset)) { continue }
        $assetId = Get-AmdMatchingId (Get-AmdConfigProperty $asset 'id')
        $axcientId = Get-AmdOwnedDeviceAssetAxcientId -Asset $asset
        if ($null -eq $axcientId) {
            if ($null -ne $assetId) { $null = $invalidOwnedAssetIds.Add($assetId) }
            $Summary.Errors.Add("Hudu asset ID $(if ($null -eq $assetId) { '<unknown>' } else { $assetId }) on '$([string]$HuduCompany.name)' contains an AXCIENT-MAGIC-DASH ownership prefix without a valid device ID. It was not changed or archived.")
            continue
        }
        if ($ambiguousOwnedIds.Contains($axcientId)) { continue }
        if ($ownedByAxcientId.ContainsKey($axcientId)) {
            $ownedByAxcientId.Remove($axcientId)
            $null = $ambiguousOwnedIds.Add($axcientId)
            $Summary.Errors.Add("Hudu company '$([string]$HuduCompany.name)' has multiple owned assets for Axcient device ID $axcientId. Those assets were left unchanged for manual consolidation.")
        }
        else {
            $ownedByAxcientId[$axcientId] = $asset
        }
    }
    $currentDeviceIds = [System.Collections.Generic.HashSet[int64]]::new()
    $statesById = @{}
    $staleBackupHours = ConvertTo-AmdStaleBackupHours (Get-AmdConfigProperty $Config 'staleBackupHours')
    $timeZoneId = ConvertTo-AmdTimeZoneId (Get-AmdConfigProperty $Config 'timeZoneId')
    $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById($timeZoneId)
    $applianceData = if ($null -ne $Client) {
        Get-AmdApplianceData -Client $Client -Summary $Summary
    }
    else {
        [pscustomobject]@{ Available = $false; Items = @() }
    }
    $deviceStates = @(
        Get-AmdDeviceDashboardStates `
            -Devices $Devices `
            -Appliances $applianceData.Items `
            -ApplianceDataAvailable $applianceData.Available `
            -StaleBackupHours $staleBackupHours `
            -NowUtc ([DateTime]::UtcNow) `
            -TimeZone $timeZone
    )
    foreach ($state in $deviceStates) {
        $deviceId = Get-AmdMatchingId (Get-AmdConfigProperty $state.Source 'id')
        if ($null -eq $deviceId) {
            $Summary.Errors.Add("An Axcient device for '$([string]$HuduCompany.name)' was skipped because it has no valid ID.")
            continue
        }
        $null = $currentDeviceIds.Add($deviceId)
        $statesById[$deviceId] = $state
    }

    foreach ($deviceId in @($statesById.Keys | Sort-Object)) {
        $state = $statesById[$deviceId]
        $displayName = Get-AmdDeviceDisplayName -Device $state.Source -DeviceId $deviceId
        $html = New-AmdDeviceCardHtml -DeviceState $state -AxcientDeviceId $deviceId
        $owned = if ($ownedByAxcientId.ContainsKey($deviceId)) { $ownedByAxcientId[$deviceId] } else { $null }
        if ($ambiguousOwnedIds.Contains([int64]$deviceId)) {
            $Summary.AssetsSkipped++
            continue
        }
        try {
            if ($null -ne $owned) {
                $assetId = Get-AmdMatchingId $owned.id
                if ($null -eq $assetId) { throw 'Owned Hudu asset is missing a valid ID.' }
                Invoke-AmdWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                    Set-AmdHuduAsset `
                        -Id $assetId `
                        -CompanyId $companyId `
                        -LayoutId $layoutId `
                        -Name $displayName `
                        -Content $html `
                        -Confirm:$false `
                        -ErrorAction Stop
                } | Out-Null
                $Summary.AssetsUpdated++
                continue
            }

            $nameCollision = @(
                $existing | Where-Object {
                    [string]::Equals(
                        [string](Get-AmdConfigProperty $_ 'name' ''),
                        $displayName,
                        [StringComparison]::OrdinalIgnoreCase
                    ) -and -not (Test-AmdOwnedDeviceAsset -Asset $_)
                }
            )
            $createName = $displayName
            if ($nameCollision.Count -gt 0) {
                $Summary.AssetsSkipped++
                $Summary.Errors.Add("Hudu company '$([string]$HuduCompany.name)' already has an unowned asset named '$displayName'. Rename that asset before syncing Axcient device ID $deviceId; AXCIENT-MAGIC-DASH did not create a duplicate.")
                continue
            }
            $createResult = New-AmdOwnedDeviceAssetSafely `
                -CompanyId $companyId `
                -LayoutId $layoutId `
                -DeviceId $deviceId `
                -Name $createName `
                -Content $html
            if ($null -ne $createResult.Asset) { $existing += $createResult.Asset }
            $Summary.AssetsCreated++
        }
        catch {
            $Summary.Errors.Add("Could not publish Axcient device '$displayName' to '$([string]$HuduCompany.name)'. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        }
    }

    foreach ($asset in $existing) {
        if (-not (Test-AmdOwnedDeviceAsset -Asset $asset)) { continue }
        $assetId = Get-AmdMatchingId (Get-AmdConfigProperty $asset 'id')
        if ($null -ne $assetId -and $invalidOwnedAssetIds.Contains($assetId)) { continue }
        $axcientId = Get-AmdOwnedDeviceAssetAxcientId -Asset $asset
        if ($null -eq $axcientId -or $ambiguousOwnedIds.Contains($axcientId)) { continue }
        if ($currentDeviceIds.Contains($axcientId)) { continue }
        if ($null -eq $assetId) { continue }
        try {
            Invoke-AmdWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                Archive-AmdHuduAsset -Id $assetId -CompanyId $companyId -Confirm:$false -ErrorAction Stop
            } | Out-Null
            $Summary.AssetsArchived++
        }
        catch {
            $Summary.Errors.Add("Could not archive a retired device asset on '$([string]$HuduCompany.name)'. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        }
    }
}

function Archive-AmdOwnedCompanyDeviceAssets {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Hudu archive is the product operation; delete is intentionally unused.')]
    param(
        [Parameter(Mandatory)][int64]$CompanyId,
        [Parameter(Mandatory)][string]$CompanyName,
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)]$Summary
    )

    $layoutId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $Layout 'id')
    if ($null -eq $layoutId) { return }
    try {
        $existing = @(Get-AmdHuduAsset -CompanyId $CompanyId -LayoutId $layoutId -ErrorAction Stop)
    }
    catch {
        $Summary.Errors.Add("Owned device assets on '$CompanyName' could not be listed for archive. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        return
    }
    foreach ($asset in $existing) {
        if (-not (Test-AmdOwnedDeviceAsset -Asset $asset)) { continue }
        $axcientId = Get-AmdOwnedDeviceAssetAxcientId -Asset $asset
        $assetId = Get-AmdMatchingId $asset.id
        if ($null -eq $axcientId) {
            $Summary.Errors.Add("Hudu asset ID $(if ($null -eq $assetId) { '<unknown>' } else { $assetId }) on '$CompanyName' has a malformed AXCIENT-MAGIC-DASH ownership marker and was not archived.")
            continue
        }
        if ($null -eq $assetId) { continue }
        try {
            Archive-AmdHuduAsset -Id $assetId -CompanyId $CompanyId -Confirm:$false -ErrorAction Stop | Out-Null
            $Summary.AssetsArchived++
        }
        catch {
            $Summary.Errors.Add("Could not archive an owned device asset on '$CompanyName'. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        }
    }
}

function Set-AmdCompanyMagicDash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)]$HuduCompany,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Devices,
        [Parameter(Mandatory)]$Config,
        [AllowNull()]$Summary
    )

    $counters = $Client.devices_counters
    $staleBackupHours = ConvertTo-AmdStaleBackupHours (Get-AmdConfigProperty $Config 'staleBackupHours')
    $timeZoneId = ConvertTo-AmdTimeZoneId (Get-AmdConfigProperty $Config 'timeZoneId')
    $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById($timeZoneId)
    $nowUtc = [DateTime]::UtcNow
    $applianceData = Get-AmdApplianceData -Client $Client -Summary $Summary
    $deviceStates = @(
        Get-AmdDeviceDashboardStates `
            -Devices $Devices `
            -Appliances $applianceData.Items `
            -ApplianceDataAvailable $applianceData.Available `
            -StaleBackupHours $staleBackupHours `
            -NowUtc $nowUtc `
            -TimeZone $timeZone
    )
    $fleetCounts = Get-AmdFleetCounts -DeviceStates $deviceStates
    $sortedDeviceStates = @($deviceStates | Sort-Object Type, Name)
    $serverDevices = @(
        $sortedDeviceStates | Where-Object {
            [string]::Equals([string]$_.Type, 'SERVER', [StringComparison]::OrdinalIgnoreCase)
        }
    )
    $workstationDevices = @(
        $sortedDeviceStates | Where-Object {
            [string]::Equals([string]$_.Type, 'WORKSTATION', [StringComparison]::OrdinalIgnoreCase)
        }
    )
    $otherDevices = @(
        $sortedDeviceStates | Where-Object {
            -not [string]::Equals([string]$_.Type, 'SERVER', [StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::Equals([string]$_.Type, 'WORKSTATION', [StringComparison]::OrdinalIgnoreCase)
        }
    )

    # Every warning row is already highlighted in its device-type table. Keep this
    # section compact so large unhealthy fleets are not serialized twice and pushed
    # over the bridge's request-frame limit.
    $warningSection = if ($fleetCounts.Warning -eq 0) {
        ''
    }
    else {
        $warningSummary = if ($fleetCounts.Warning -eq 1) {
            '1 device needs attention. Its warning row is highlighted in the device section below.'
        }
        else {
            "$($fleetCounts.Warning) devices need attention. Their warning rows are highlighted in the device sections below."
        }
        Merge-AmdTemplate -Template $script:AmdMagicDashWarningSectionTemplate -Values @{
            warning_count   = $fleetCounts.Warning
            warning_summary = ConvertTo-AmdHtml $warningSummary
        }
    }
    $otherDeviceSection = if ($otherDevices.Count -eq 0) {
        ''
    }
    else {
        Merge-AmdTemplate -Template $script:AmdMagicDashOtherDeviceSectionTemplate -Values @{
            other_devices = (New-AmdDeviceTable -DeviceStates $otherDevices -PanelLabel 'Other devices')
        }
    }

    # An unusable client ID drops the link instead of throwing away the whole
    # Magic Dash; ConvertTo-AmdSafeHref turns $null into a neutral '#'.
    $clientId = ConvertTo-AmdNumber $Client.id -AsInt64
    $clientUsage = $null
    if ($null -ne $clientId -and -not [string]::IsNullOrWhiteSpace([string]$Config.axcientAPIKey)) {
        try {
            $clientUsage = @(
                Invoke-AmdWithRetry -Operation {
                    Get-AmdAxcientClientUsage -ClientId $clientId -ApiKey ([string]$Config.axcientAPIKey)
                }
            ) | Select-Object -First 1
        }
        catch {
            if ($Summary) {
                $Summary.Warnings.Add("Axcient storage usage was unavailable for '$($Client.name)'. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
            }
        }
    }
    $localUsageBytes = if ($clientUsage) { ConvertTo-AmdNumber $clientUsage.local_usage } else { $null }
    $privateUsageBytes = if ($clientUsage) { ConvertTo-AmdNumber $clientUsage.vault_usage } else { $null }
    $cloudUsageBytes = if ($clientUsage) { ConvertTo-AmdNumber $clientUsage.cloud_usage } else { $null }
    $totalVaultBytes = if ($null -ne $privateUsageBytes -and $null -ne $cloudUsageBytes) {
        $privateUsageBytes + $cloudUsageBytes
    }
    else { $null }
    $templateValues = @{
        client_url          = if ($null -ne $clientId) { ConvertTo-AmdSafeHref "https://my.axcient.net/home/client/$clientId" } else { '#' }
        name                = ConvertTo-AmdHtml $Client.name
        health              = New-AmdStatusBadge -Status $Client.health_status
        last_update         = ConvertTo-AmdHtml ([TimeZoneInfo]::ConvertTimeFromUtc($nowUtc, $timeZone).ToString('g'))
        time_zone           = ConvertTo-AmdHtml $timeZone.DisplayName
        ab_server           = Get-AmdCounterValue $counters.appliance_based 'SERVER'
        ab_workstation      = Get-AmdCounterValue $counters.appliance_based 'WORKSTATION'
        d2c_server          = Get-AmdCounterValue $counters.d2c 'SERVER'
        d2c_workstation     = Get-AmdCounterValue $counters.d2c 'WORKSTATION'
        ar_server           = Get-AmdCounterValue $counters.cloud_archive 'SERVER'
        ar_workstation      = Get-AmdCounterValue $counters.cloud_archive 'WORKSTATION'
        fleet_healthy       = $fleetCounts.Healthy
        fleet_warning       = $fleetCounts.Warning
        fleet_offline       = if ($null -eq $fleetCounts.Offline) { 'Unknown' } else { $fleetCounts.Offline }
        fleet_unknown       = $fleetCounts.Unknown
        total_vault_usage   = Format-AmdByteSize $totalVaultBytes
        private_vault_usage = Format-AmdByteSize $privateUsageBytes
        cloud_vault_usage   = Format-AmdByteSize $cloudUsageBytes
        local_appliance_usage = Format-AmdByteSize $localUsageBytes
        stale_threshold     = $staleBackupHours
        appliances          = New-AmdApplianceTable -Appliances $applianceData.Items -DataAvailable $applianceData.Available
        warning_section     = $warningSection
        server_devices      = (New-AmdDeviceTable -DeviceStates $serverDevices -PanelLabel 'Servers')
        workstation_devices = (New-AmdDeviceTable -DeviceStates $workstationDevices -PanelLabel 'Workstations')
        other_device_section = $otherDeviceSection
    }
    $content = $script:AmdMagicDashOwnershipMarker + (
        Merge-AmdTemplate -Template $script:AmdMagicDashTemplate -Values $templateValues
    )

    $healthy = [string]::Equals([string]$Client.health_status, 'NORMAL', [StringComparison]::OrdinalIgnoreCase) -and
        $fleetCounts.Warning -eq 0 -and
        $fleetCounts.Unknown -eq 0
    $shade = if ($healthy) { [string]$Config.styling.dashHealthy } else { [string]$Config.styling.dashWarning }
    # Hudu renders Message on the small company-page tile. Keep it deliberately
    # short and plain; the full device counts and protection details live inside
    # Content, where they have enough room and cannot collide with tile controls.
    $dashboardMessage = if ($healthy) {
        "Healthy | $($fleetCounts.Healthy) protected"
    }
    else {
        'Attention needed | Review details'
    }
    $dashParameters = @{
        CompanyId           = [int64]$HuduCompany.id
        ExpectedCompanyName = [string]$HuduCompany.name
        OwnershipMarker     = $script:AmdMagicDashOwnershipMarker
        Title               = 'Axcient X360Recover'
        Message             = $dashboardMessage
        Shade               = $shade
        Content             = $content
        Icon                = 'fas fa-shield-alt'
        ImageUrl            = ''
        ErrorAction         = 'Stop'
    }
    try {
        Set-AmdHuduMagicDashForCompany @dashParameters | Out-Null
    }
    catch [ArgumentException] {
        if ($_.Exception.Message -notmatch 'bridge request exceeds the maximum frame size') {
            throw
        }
        $deviceCount = $deviceStates.Count
        $fallbackValues = $templateValues.Clone()
        $fallbackValues.appliances = New-AmdEmptyState -Message 'Appliance detail rows were omitted to keep this very large dashboard within Hudu transfer limits.'
        $fallbackValues.server_devices = if ($serverDevices.Count -gt 0) {
            New-AmdEmptyState -Message "$($serverDevices.Count) server detail row(s) were omitted to keep this very large dashboard within Hudu transfer limits."
        }
        else {
            New-AmdDeviceTable -DeviceStates @() -PanelLabel 'Servers'
        }
        $fallbackValues.workstation_devices = if ($workstationDevices.Count -gt 0) {
            New-AmdEmptyState -Message "$($workstationDevices.Count) workstation detail row(s) were omitted to keep this very large dashboard within Hudu transfer limits."
        }
        else {
            New-AmdDeviceTable -DeviceStates @() -PanelLabel 'Workstations'
        }
        $fallbackValues.other_device_section = if ($otherDevices.Count -gt 0) {
            Merge-AmdTemplate -Template $script:AmdMagicDashOtherDeviceSectionTemplate -Values @{
                other_devices = (New-AmdEmptyState -Message "$($otherDevices.Count) other-device detail row(s) were omitted to keep this very large dashboard within Hudu transfer limits.")
            }
        }
        else { '' }
        $fallbackContent = $script:AmdMagicDashOwnershipMarker + (
            Merge-AmdTemplate -Template $script:AmdMagicDashTemplate -Values $fallbackValues
        )
        $dashParameters.Content = $fallbackContent
        Set-AmdHuduMagicDashForCompany @dashParameters | Out-Null
        if ($Summary) {
            $Summary.Warnings.Add("Hudu company '$($HuduCompany.name)' has $deviceCount devices. Device and appliance detail rows were omitted because the complete Magic Dash exceeded the bridge transfer limit; fleet counts and storage totals were still updated.")
        }
    }
}

function Invoke-AmdMatchOperations {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Operations = @(),
        [Parameter(Mandatory)]$Summary,
        [AllowNull()]$Config
    )

    $operationList = @($Operations | Where-Object { $null -ne $_ })
    foreach ($operation in $operationList) {
        $operationSucceeded = $true
        $errorCountBefore = $Summary.Errors.Count
        $sourceExists = if ($operation.PSObject.Properties.Name -contains 'SourceHuduExists') {
            [bool]$operation.SourceHuduExists
        }
        else { $true }
        try {
            $sourceDashes = if ($sourceExists) {
                @(Assert-AmdMagicDashOwnership -CompanyId ([int64]$operation.SourceHuduId) -CompanyName ([string]$operation.SourceHuduName))
            }
            else { @() }
            $layout = $null
            if ($null -ne $Config) {
                $boundLayoutId = ConvertTo-AmdAssetLayoutId (Get-AmdConfigProperty $Config 'assetLayoutId')
                if ($null -ne $boundLayoutId) {
                    $layout = Get-AmdBoundDeviceAssetLayout -Config $Config -Summary $Summary
                }
            }
            if ($operation.Action -eq 'Delete') {
                if ($sourceExists -and $null -ne $layout) {
                    Archive-AmdOwnedCompanyDeviceAssets `
                        -CompanyId ([int64]$operation.SourceHuduId) `
                        -CompanyName ([string]$operation.SourceHuduName) `
                        -Layout $layout `
                        -Summary $Summary
                }
                if ($sourceDashes.Count -gt 0) {
                    foreach ($dash in $sourceDashes) {
                        Remove-AmdHuduMagicDash -Id ([int64]$dash.id) -Confirm:$false -ErrorAction Stop
                    }
                }
                if ($sourceExists) {
                    $Summary.Notes.Add("Removed the AXCIENT-MAGIC-DASH Magic Dash from '$($operation.SourceHuduName)'.")
                }
                else {
                    $Summary.Notes.Add("Removed a stale match for missing Hudu company ID $($operation.SourceHuduId); no Hudu content remained to delete.")
                }
            }
            elseif ($operation.Action -eq 'Move') {
                $targetCompany = @(
                    Resolve-AmdHuduCompanyForNameWrite `
                        -CompanyId ([int64]$operation.TargetHuduId) `
                        -ErrorAction Stop
                )
                $currentTargetName = if ($targetCompany.Count -eq 1) { [string]$targetCompany[0].name } else { '' }
                if ($targetCompany.Count -ne 1 -or
                    (Get-AmdMatchingId $targetCompany[0].id) -ne [int64]$operation.TargetHuduId) {
                    throw "The destination Hudu company ID $($operation.TargetHuduId) is missing or its current name is duplicated. Hudu's Magic Dash API targets company names, so this move was blocked to prevent writing to the wrong company."
                }
                $moveDevices = @()
                $moveClient = $null
                if ($null -ne $layout -and $sourceDashes.Count -gt 0) {
                    try {
                        $axcientClient = @(
                            Get-AmdAxcientClient -ErrorAction Stop | Where-Object {
                                (Get-AmdMatchingId $_.id) -eq [int64]$operation.AxcientId
                            }
                        )
                        if ($axcientClient.Count -eq 1) {
                            $moveClient = $axcientClient[0]
                            $moveDevices = @(Invoke-AmdWithRetry -Operation { $moveClient | Get-Device -ErrorAction Stop })
                        }
                    }
                    catch {
                        throw "Owned device assets could not be prepared for the move. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)"
                    }
                }
                foreach ($dash in $sourceDashes) {
                    $dashMessage = [string](Get-AmdConfigProperty $dash 'message' '')
                    if ([string]::IsNullOrWhiteSpace($dashMessage)) {
                        # Message is mandatory at the Hudu client boundary. A legacy
                        # or manually edited managed dash can omit it, and passing an
                        # empty string made the queued Move fail binding forever on
                        # every replay, with no recovery path outside config surgery.
                        $dashMessage = 'Axcient X360Recover'
                    }
                    Set-AmdHuduMagicDashForCompany `
                        -CompanyId ([int64]$operation.TargetHuduId) `
                        -ExpectedCompanyName $currentTargetName `
                        -OwnershipMarker $script:AmdMagicDashOwnershipMarker `
                        -Title 'Axcient X360Recover' `
                        -Message $dashMessage `
                        -Shade ([string](Get-AmdConfigProperty $dash 'shade' '')) `
                        -Content ([string](Get-AmdConfigProperty $dash 'content' '')) `
                        -ImageUrl ([string](Get-AmdConfigProperty $dash 'image_url' '')) `
                        -ErrorAction Stop | Out-Null
                }
                if ($null -ne $layout -and $sourceDashes.Count -gt 0) {
                    $assetErrorCountBefore = $Summary.Errors.Count
                    Sync-AmdCompanyDeviceAssets `
                        -HuduCompany $targetCompany[0] `
                        -Devices $moveDevices `
                        -Client $moveClient `
                        -Config $Config `
                        -Summary $Summary `
                        -Layout $layout
                    if ($Summary.Errors.Count -gt $assetErrorCountBefore) {
                        throw 'Owned device assets could not be safely created at the move destination, so source assets and the source Magic Dash were retained.'
                    }
                    if ($sourceExists) {
                        Archive-AmdOwnedCompanyDeviceAssets `
                            -CompanyId ([int64]$operation.SourceHuduId) `
                            -CompanyName ([string]$operation.SourceHuduName) `
                            -Layout $layout `
                            -Summary $Summary
                        if ($Summary.Errors.Count -gt $assetErrorCountBefore) {
                            throw 'Owned device assets could not be safely archived at the move source, so the source Magic Dash was retained.'
                        }
                    }
                }
                foreach ($dash in $sourceDashes) {
                    Remove-AmdHuduMagicDash -Id ([int64]$dash.id) -Confirm:$false -ErrorAction Stop
                }
                if ($sourceExists) {
                    $Summary.Notes.Add("Moved the AXCIENT-MAGIC-DASH Magic Dash from '$($operation.SourceHuduName)' to '$currentTargetName'.")
                }
                else {
                    $Summary.Notes.Add("Reassigned the stale match from missing Hudu company ID $($operation.SourceHuduId) to '$currentTargetName'. The full sync will create the current Magic Dash there.")
                }
            }
            else {
                throw "Unknown queued operation '$($operation.Action)'."
            }
        }
        catch {
            $operationSucceeded = $false
            $Summary.Errors.Add("Could not complete the queued '$($operation.Action)' operation for '$($operation.SourceHuduName)'. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        }
        if ($Summary.Errors.Count -gt $errorCountBefore) { $operationSucceeded = $false }
        $Summary.OperationResults.Add([pscustomobject]@{
            Operation = $operation
            Succeeded = $operationSucceeded
        })
    }
    return $Summary
}

function Invoke-AmdPendingOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Summary
    )

    if ($Config.PSObject.Properties.Name -notcontains 'pendingOperations') { return $Summary }
    $pending = @($Config.pendingOperations | Where-Object { $null -ne $_ })
    if ($pending.Count -eq 0) { return $Summary }
    $layoutId = ConvertTo-AmdAssetLayoutId (Get-AmdConfigProperty $Config 'assetLayoutId')
    if ($null -eq $layoutId) {
        $Summary.Notes.Add('Queued matching operations skipped device assets because no Hudu asset layout is bound.')
    }
    else {
        $Summary.Notes.Add('Queued matching operations also archive or move owned device assets.')
    }

    try {
        $currentCompanies = @(Get-AmdHuduCompany -ErrorAction Stop)
        $companySelection = Select-AmdUniqueSyncEndpoints `
            -Items $currentCompanies `
            -ServiceName 'Hudu' `
            -RecordType 'company'
        if ($companySelection.Errors.Count -gt 0) {
            throw "The current Hudu company list is not safe for queued operations. $($companySelection.Errors -join ' ')"
        }
        $currentCompanyIds = $companySelection.Ids
    }
    catch {
        $safeError = ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message
        $Summary.Errors.Add("Queued matching operations were not attempted because current Hudu company IDs could not be refreshed. $safeError")
        foreach ($operation in $pending) {
            $Summary.OperationResults.Add([pscustomobject]@{ Operation = $operation; Succeeded = $false })
        }
        $Summary.Warnings.Add("$($pending.Count) matching backend operation(s) remain journaled in config.json and will be retried safely on the next setup or sync run.")
        return $Summary
    }
    $sourceStateCorrections = 0
    foreach ($operation in $pending) {
        $sourceExistsNow = $currentCompanyIds.Contains([int64]$operation.SourceHuduId)
        if ($operation.PSObject.Properties.Name -notcontains 'SourceHuduExists') {
            $operation | Add-Member -NotePropertyName SourceHuduExists -NotePropertyValue $sourceExistsNow
            $sourceStateCorrections++
        }
        elseif ([bool]$operation.SourceHuduExists -ne $sourceExistsNow) {
            $operation.SourceHuduExists = $sourceExistsNow
            $sourceStateCorrections++
        }
    }
    if ($sourceStateCorrections -gt 0) {
        $Summary.Notes.Add("Refreshed source-company existence for $sourceStateCorrections journaled matching operation(s) before replay.")
    }

    $resultStart = $Summary.OperationResults.Count
        Invoke-AmdMatchOperations -Operations $pending -Summary $Summary -Config $Config | Out-Null
    $failed = @(
        @($Summary.OperationResults)[$resultStart..($Summary.OperationResults.Count - 1)] |
            Where-Object { -not $_.Succeeded } |
            ForEach-Object { $_.Operation }
    )
    $Config.pendingOperations = $failed
    if ($failed.Count -gt 0) {
        $Summary.Warnings.Add("$($failed.Count) matching backend operation(s) remain journaled in config.json and will be retried safely on the next setup or sync run.")
    }
    else {
        $Summary.Notes.Add("Completed $($pending.Count) journaled matching backend operation(s).")
    }
    return $Summary
}

function Select-AmdUniqueSyncEndpoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [Parameter(Mandatory)][string]$ServiceName,
        [Parameter(Mandatory)][string]$RecordType
    )

    $groups = @{}
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Items) {
        $id = Get-AmdMatchingId $item.id
        if ($null -eq $id) {
            $errors.Add("$ServiceName returned $RecordType '$($item.name)' with an invalid ID. That $RecordType was skipped; other companies continued.")
            continue
        }
        $key = [string]$id
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $groups[$key].Add($item)
    }

    $validItems = [System.Collections.Generic.List[object]]::new()
    $validIds = [System.Collections.Generic.HashSet[int64]]::new()
    foreach ($entry in @($groups.GetEnumerator() | Sort-Object { [int64]$_.Key })) {
        if ($entry.Value.Count -ne 1) {
            $errors.Add("$ServiceName returned $($entry.Value.Count) ${RecordType}s with ID $($entry.Key). That ambiguous ID was skipped; other companies continued.")
            continue
        }
        $validItems.Add($entry.Value[0])
        $null = $validIds.Add([int64]$entry.Key)
    }

    return [pscustomobject]@{
        Items  = @($validItems)
        Ids    = $validIds
        Errors = @($errors)
    }
}

function Invoke-AmdSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$AlreadyConnected,
        [AllowNull()][string]$ConfigPath
    )

    $summary = New-AmdSyncSummary
    try {
        if (-not $AlreadyConnected) { Connect-AmdServices -Config $Config }
        Invoke-AmdPendingOperations -Config $Config -Summary $summary | Out-Null
    }
    catch {
        $summary.Errors.Add("Initial API connection or pending-operation recovery failed. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        $summary.CompletedUtc = [DateTime]::UtcNow
        return [pscustomobject]@{ Config = $Config; Summary = $summary }
    }
    try {
        $axcientClients = @(Invoke-AmdWithRetry -Operation { Get-Client -ErrorAction Stop })
        $huduCompanies = @(Invoke-AmdWithRetry -Operation { Get-AmdHuduCompany -ErrorAction Stop })
    }
    catch {
        $summary.Errors.Add("Initial API data could not be loaded. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        $summary.CompletedUtc = [DateTime]::UtcNow
        return [pscustomobject]@{ Config = $Config; Summary = $summary }
    }

    # Normalize endpoint IDs immediately after the read so every later phase sees
    # only unambiguous records. Pending operations perform the same validation.
    $clientSelection = Select-AmdUniqueSyncEndpoints `
        -Items $axcientClients `
        -ServiceName 'Axcient' `
        -RecordType 'client'
    $companySelection = Select-AmdUniqueSyncEndpoints `
        -Items $huduCompanies `
        -ServiceName 'Hudu' `
        -RecordType 'company'
    foreach ($endpointError in @($clientSelection.Errors) + @($companySelection.Errors)) {
        $summary.Errors.Add($endpointError)
    }
    $axcientClients = @($clientSelection.Items)
    $huduCompanies = @($companySelection.Items)
    $clientIds = $clientSelection.Ids
    $companyIds = $companySelection.Ids

    if ($Config.autoMatch -and @($Config.pendingOperations).Count -eq 0) {
        $matchesBeforeAutoMatch = @($Config.matches)
        $before = $matchesBeforeAutoMatch.Count
        $Config.matches = @(Update-AmdAutomaticMatches -HuduCompanies $huduCompanies -AxcientClients $axcientClients -Matches @($Config.matches) -Exclusions @($Config.autoMatchExclusions))
        $summary.AutomaticMatchesAdded = @($Config.matches).Count - $before
        if ($summary.AutomaticMatchesAdded -gt 0) {
            if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
                $Config.matches = $matchesBeforeAutoMatch
                $summary.AutomaticMatchesAdded = 0
                $summary.Errors.Add('Automatic matches were not applied because no durable config.json path was supplied. No Hudu content was written for those unpersisted matches.')
            }
            else {
                try {
                    Save-AmdConfig -Config $Config -Path $ConfigPath | Out-Null
                    $summary.Notes.Add("Persisted $($summary.AutomaticMatchesAdded) automatic match(es) before any Hudu content was written for them.")
                }
                catch {
                    $Config.matches = $matchesBeforeAutoMatch
                    $summary.AutomaticMatchesAdded = 0
                    $summary.Errors.Add("Automatic matches could not be saved before Hudu updates, so they were not applied. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
                }
            }
        }
    }

    foreach ($storedMatch in @($Config.matches)) {
        if (-not $clientIds.Contains([int64]$storedMatch.axcientId)) {
            $summary.Errors.Add("Stored match '$($storedMatch.name)' references missing Axcient client ID $($storedMatch.axcientId). Run run.ps1 and remove or replace the stale match.")
        }
    }

    $matchesByAxcientId = @{}
    foreach ($storedMatch in @($Config.matches)) {
        $matchesByAxcientId[[int64]$storedMatch.axcientId] = $storedMatch
    }
    $companiesById = @{}
    foreach ($huduCompany in $huduCompanies) {
        $huduCompanyId = Get-AmdMatchingId $huduCompany.id
        if ($null -ne $huduCompanyId) {
            $companiesById[$huduCompanyId] = $huduCompany
        }
    }

    $deviceLayout = Get-AmdBoundDeviceAssetLayout -Config $Config -Summary $summary

    foreach ($client in $axcientClients | Sort-Object name, id) {
        $currentClientId = Get-AmdMatchingId $client.id
        if (-not $matchesByAxcientId.ContainsKey($currentClientId)) {
            $summary.UnmatchedClients.Add("$($client.name) (Axcient ID $($client.id))")
            continue
        }
        $match = $matchesByAxcientId[$currentClientId]
        $matchedHuduId = [int64]$match.huduID
        if (-not $companiesById.ContainsKey($matchedHuduId)) {
            $summary.Errors.Add("Axcient client '$($client.name)' is matched to missing Hudu company ID $matchedHuduId. Run run.ps1 and repair the stale match.")
            continue
        }
        $company = $companiesById[$matchedHuduId]

        $companyResult = [pscustomobject]@{
            HuduCompany = [string]$company.name
            AxcientClient = [string]$client.name
            MagicDashUpdated = $false
            DeviceCount = 0
        }
        try {
            $devices = @()
            $devicesLoaded = $false
            try {
                $devices = @(Invoke-AmdWithRetry -Operation { $client | Get-Device -ErrorAction Stop })
                $devicesLoaded = $true
                $summary.AxcientDevicesRetrieved += @($devices).Count
                $companyResult.DeviceCount = @($devices).Count
                Set-AmdCompanyMagicDash -Client $client -HuduCompany $company -Devices $devices -Config $Config -Summary $summary
                $summary.MagicDashesUpdated++
                $companyResult.MagicDashUpdated = $true
            }
            catch {
                $summary.Errors.Add("Could not safely update the name-based Magic Dash for Hudu company ID $($company.id). $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
            }
            if ($devicesLoaded -and $companyResult.MagicDashUpdated) {
                Sync-AmdCompanyDeviceAssets `
                    -HuduCompany $company `
                    -Devices $devices `
                    -Client $client `
                    -Config $Config `
                    -Summary $summary `
                    -Layout $deviceLayout
            }

            $summary.MatchedCompanies++
        }
        catch {
            $summary.Errors.Add("Sync failed for Axcient client '$($client.name)' / Hudu company '$($company.name)'. Other companies continued. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
        }
        $summary.CompanyResults.Add($companyResult)
    }

    $matchedHuduIds = [System.Collections.Generic.HashSet[int64]]::new()
    foreach ($matchItem in @($Config.matches)) {
        if ($clientIds.Contains([int64]$matchItem.axcientId) -and $companyIds.Contains([int64]$matchItem.huduID)) {
            $null = $matchedHuduIds.Add([int64]$matchItem.huduID)
        }
    }
    foreach ($huduCompany in $huduCompanies | Sort-Object name, id) {
        if (-not $matchedHuduIds.Contains([int64]$huduCompany.id)) {
            $summary.UnmatchedHuduCompanies.Add("$($huduCompany.name) (Hudu ID $($huduCompany.id))")
        }
    }
    foreach ($client in $axcientClients) {
        $unmatchedClientId = Get-AmdMatchingId $client.id
        if ($null -eq $unmatchedClientId -or $matchesByAxcientId.ContainsKey($unmatchedClientId)) {
            continue
        }
        $clientKey = Convert-AmdComparableCompanyName ([string]$client.name)
        if ([string]::IsNullOrWhiteSpace($clientKey)) { continue }
        foreach ($huduCompany in $huduCompanies) {
            $unmatchedCompanyId = Get-AmdMatchingId $huduCompany.id
            if ($null -eq $unmatchedCompanyId -or $matchedHuduIds.Contains($unmatchedCompanyId)) {
                continue
            }
            $companyKey = Convert-AmdComparableCompanyName ([string]$huduCompany.name)
            if ($clientKey -eq $companyKey) {
                $summary.Warnings.Add("Axcient client '$($client.name)' and Hudu company '$($huduCompany.name)' look like the same name except spacing or punctuation. Exact-name automatch did not connect them. Match them in run.ps1 if they should share a Magic Dash.")
            }
        }
    }
    if ($summary.MagicDashesUpdated -gt 0 -and [int]$summary.AxcientDevicesRetrieved -eq 0) {
        $summary.Warnings.Add('Axcient returned 0 devices for every matched client. Magic Dashes were updated with empty device lists, and no Hudu device assets were created. Confirm those Axcient clients have protected devices.')
    }
    $reportOrphanedDashes = ConvertTo-AmdBoolean `
        (Get-AmdConfigProperty $Config 'reportOrphanedDashes' $null) `
        -PropertyName 'reportOrphanedDashes' `
        -Default $true
    if ($reportOrphanedDashes -and $companySelection.Errors.Count -eq 0) {
        foreach ($huduCompany in $huduCompanies | Sort-Object name, id) {
            if ($matchedHuduIds.Contains([int64]$huduCompany.id)) { continue }
            try {
                $dashes = @(Get-AmdHuduMagicDash `
                    -CompanyId ([int64]$huduCompany.id) `
                    -Title 'Axcient X360Recover' `
                    -ErrorAction Stop)
                if (@($dashes | Where-Object { Test-AmdOwnedMagicDash -Dash $_ }).Count -gt 0) {
                    $summary.Warnings.Add("Hudu company '$($huduCompany.name)' has an owned AXCIENT-MAGIC-DASH Magic Dash but is not matched to an available Axcient client. Run run.ps1 and unmatch it properly to remove it, or remove the stale dash manually if its Axcient client no longer exists.")
                }
            }
            catch {
                $summary.Warnings.Add("Orphaned Magic Dash reporting could not check Hudu company '$($huduCompany.name)'. $(ConvertTo-AmdBoundedDiagnosticText -Text $_.Exception.Message)")
            }
        }
    }

    $summary.CompletedUtc = [DateTime]::UtcNow
    return [pscustomobject]@{ Config = $Config; Summary = $summary }
}

function Show-AmdSyncSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Summary)

    $duration = if ($Summary.CompletedUtc) {
        [math]::Round(($Summary.CompletedUtc - $Summary.StartedUtc).TotalSeconds, 1)
    }
    else { 0 }

    Write-Host "`n============================================================" -ForegroundColor DarkGray
    Write-Host 'AXCIENT-MAGIC-DASH sync summary' -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host "Matched companies:       $($Summary.MatchedCompanies)" -ForegroundColor Green
    Write-Host "Automatic matches added: $($Summary.AutomaticMatchesAdded)" -ForegroundColor Green
    Write-Host "Magic Dashes updated:    $($Summary.MagicDashesUpdated)" -ForegroundColor Green
    $deviceColor = if ([int]$Summary.AxcientDevicesRetrieved -eq 0) { 'Yellow' } else { 'Green' }
    Write-Host "Axcient devices pulled:  $($Summary.AxcientDevicesRetrieved)" -ForegroundColor $deviceColor
    if ($null -ne $Summary.BoundLayoutId) {
        $activeText = if ($null -eq $Summary.BoundLayoutActive) { 'unknown' } else { [string][bool]$Summary.BoundLayoutActive }
        $layoutColor = if ($Summary.BoundLayoutUsable) { 'Green' } else { 'Yellow' }
        Write-Host "Device asset layout:     $($Summary.BoundLayoutName) (Hudu ID $($Summary.BoundLayoutId), active=$activeText)" -ForegroundColor $layoutColor
    }
    else {
        Write-Host 'Device asset layout:     not bound' -ForegroundColor Yellow
    }
    Write-Host "Device assets created:   $($Summary.AssetsCreated)" -ForegroundColor Green
    Write-Host "Device assets updated:   $($Summary.AssetsUpdated)" -ForegroundColor Green
    Write-Host "Device assets archived:  $($Summary.AssetsArchived)" -ForegroundColor Green
    $skipColor = if ([int]$Summary.AssetsSkipped -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host "Device assets skipped:   $($Summary.AssetsSkipped)" -ForegroundColor $skipColor
    Write-Host "Duration:                $duration seconds" -ForegroundColor Green

    if ($Summary.CompanyResults.Count -gt 0) {
        Write-Host "`nCompany results" -ForegroundColor Magenta
        foreach ($result in $Summary.CompanyResults) {
            $dash = if ($result.MagicDashUpdated) { 'Magic Dash updated' } else { 'Magic Dash skipped' }
            $deviceCount = if ($null -eq $result.DeviceCount) { '?' } else { [string]$result.DeviceCount }
            Write-Host (ConvertTo-AmdRedactedText "  $($result.HuduCompany) ← $($result.AxcientClient): $dash, $deviceCount Axcient device(s)")
        }
    }
    if ($Summary.UnmatchedClients.Count -gt 0) {
        Write-Host "`nUnmatched Axcient clients" -ForegroundColor Yellow
        $Summary.UnmatchedClients | ForEach-Object { Write-Host (ConvertTo-AmdRedactedText "  - $_") -ForegroundColor Yellow }
    }
    if ($Summary.UnmatchedHuduCompanies.Count -gt 0) {
        Write-Host "`nUnmatched Hudu companies" -ForegroundColor Yellow
        $Summary.UnmatchedHuduCompanies | ForEach-Object { Write-Host (ConvertTo-AmdRedactedText "  - $_") -ForegroundColor Yellow }
    }
    if ($Summary.Notes.Count -gt 0) {
        Write-Host "`nNotes" -ForegroundColor Cyan
        $Summary.Notes | ForEach-Object { Write-Host (ConvertTo-AmdRedactedText "  - $_") -ForegroundColor Cyan }
    }
    if ($Summary.Warnings.Count -gt 0) {
        Write-Host "`nWarnings" -ForegroundColor Yellow
        $Summary.Warnings | ForEach-Object { Write-Host (ConvertTo-AmdRedactedText "  - $_") -ForegroundColor Yellow }
    }
    if ($Summary.Errors.Count -gt 0) {
        Write-Host "`nErrors" -ForegroundColor Red
        $Summary.Errors | ForEach-Object { Write-Host (ConvertTo-AmdRedactedText "  - $_") -ForegroundColor Red }
        Write-Host "`nThe sync completed everything it could. Review the errors above and rerun after correcting them." -ForegroundColor Red
    }
    elseif ($Summary.Warnings.Count -gt 0) {
        Write-Host "`nCompleted with warnings." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nCompleted without errors." -ForegroundColor Green
    }
    Write-Host ''
}
