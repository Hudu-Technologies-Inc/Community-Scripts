$script:DbmMagicDashOwnershipMarker = '<!-- DATTO-BCDR-MAGIC-DASH:managed:v1 -->'

function Test-DbmOwnedMagicDash {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dash)

    return ([string](Get-DbmConfigProperty $Dash 'content' '')).Contains(
        $script:DbmMagicDashOwnershipMarker,
        [StringComparison]::Ordinal
    )
}

function Test-DbmPossibleLegacyMagicDash {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dash)

    $title = ([string](Get-DbmConfigProperty $Dash 'title' '')).Trim()
    if (-not [string]::Equals($title, 'Datto BCDR', [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (Test-DbmOwnedMagicDash -Dash $Dash) {
        return $false
    }

    $legacyText = '{0}`n{1}' -f @(
        [string](Get-DbmConfigProperty $Dash 'content' '')
        [string](Get-DbmConfigProperty $Dash 'message' '')
    )
    foreach ($hint in @(
            'DATTO-BCDR-MAGIC-DASH'
            'dattoBcdr'
            'Stale backup threshold'
            'nasa__block'
            'auth.datto.com'
            'api.datto.com'
        )) {
        if ($legacyText.IndexOf($hint, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Get-DbmUnownedLegacyMagicDashCandidates {
    [CmdletBinding()]
    param()

    try {
        $companies = @(Get-DbmHuduCompany -ErrorAction Stop)
    }
    catch {
        Write-Warning "The optional legacy Magic Dash scan could not list Hudu companies. Continuing without cleanup. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)" -WarningAction Continue
        return @()
    }

    $seenDashIds = [System.Collections.Generic.HashSet[int64]]::new()
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($company in $companies | Sort-Object name, id) {
        $companyId = Get-DbmMatchingId (Get-DbmConfigProperty $company 'id')
        if ($null -eq $companyId) {
            Write-Warning 'The optional legacy Magic Dash scan skipped a Hudu company with no valid ID.' -WarningAction Continue
            continue
        }
        $companyName = [string](Get-DbmConfigProperty $company 'name' "Hudu company $companyId")
        try {
            $dashes = @(Get-DbmHuduMagicDash `
                    -CompanyId $companyId `
                    -Title 'Datto BCDR' `
                    -ErrorAction Stop)
        }
        catch {
            $safeCompanyName = ConvertTo-DbmBoundedDiagnosticText -Text $companyName -MaximumLength 160
            Write-Warning "The optional legacy Magic Dash scan could not check '$safeCompanyName' (Hudu ID $companyId). That company was skipped. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)" -WarningAction Continue
            continue
        }

        foreach ($dash in $dashes) {
            if (-not (Test-DbmPossibleLegacyMagicDash -Dash $dash)) { continue }
            $dashId = Get-DbmMatchingId (Get-DbmConfigProperty $dash 'id')
            if ($null -eq $dashId) { continue }
            $returnedCompanyId = Get-DbmMatchingId (Get-DbmConfigProperty $dash 'company_id')
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

function Assert-DbmMagicDashOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int64]$CompanyId,
        [Parameter(Mandatory)][string]$CompanyName
    )

    $collisions = @(Get-DbmHuduMagicDash -CompanyId $CompanyId -Title 'Datto BCDR' -ErrorAction Stop)
    foreach ($dash in $collisions) {
        $dashId = Get-DbmMatchingId $dash.id
        $dashCompanyId = Get-DbmMatchingId $dash.company_id
        if ($null -eq $dashId -or
            $dashCompanyId -ne $CompanyId -or
            -not [string]::Equals(
                ([string]$dash.title).Trim(),
                'Datto BCDR',
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Hudu returned a Magic Dash outside company ID $CompanyId and title 'Datto BCDR'. No Magic Dash mutation was attempted."
        }
    }
    $unowned = @($collisions | Where-Object { -not (Test-DbmOwnedMagicDash -Dash $_) })
    if ($unowned.Count -gt 0) {
        throw "Hudu company '$CompanyName' already has an unowned Magic Dash titled 'Datto BCDR'. Rename or remove that collision manually; DATTO-BCDR-MAGIC-DASH will not overwrite it."
    }
    if ($collisions.Count -gt 1) {
        throw "Hudu company '$CompanyName' has multiple owned Magic Dashes titled 'Datto BCDR'. Consolidate them manually; DATTO-BCDR-MAGIC-DASH will not choose one or delete duplicates."
    }
    return $collisions
}

function Get-DbmDeviceAssetDetailsHtml {
    [CmdletBinding()]
    param([AllowNull()]$Asset)

    # Hudu takes this field as custom_fields @{ 'Asset Details' = html } on write
    # but hands it back as fields @({ label; value }) on read, so both shapes are
    # read here. The first NON-EMPTY candidate wins rather than the first shape
    # that happens to be present: an empty container shadowing the populated one
    # would make every owned device asset read as unowned, and the next sync then
    # refuses to touch its own assets and reports them as name collisions.
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($field in @(Get-DbmConfigProperty $Asset 'custom_fields' @())) {
        if ($null -eq $field) { continue }
        $names = @($field.PSObject.Properties.Name)
        if ($names -contains 'Asset Details') {
            $candidates.Add([string]$field.'Asset Details')
            continue
        }
        $label = [string](Get-DbmConfigProperty $field 'label' '')
        if ([string]::Equals($label, 'Asset Details', [StringComparison]::OrdinalIgnoreCase)) {
            $candidates.Add([string](Get-DbmConfigProperty $field 'value' ''))
        }
    }
    foreach ($field in @(Get-DbmConfigProperty $Asset 'fields' @())) {
        if ($null -eq $field) { continue }
        $label = [string](Get-DbmConfigProperty $field 'label' '')
        if ([string]::Equals($label, 'Asset Details', [StringComparison]::OrdinalIgnoreCase)) {
            $candidates.Add([string](Get-DbmConfigProperty $field 'value' ''))
        }
    }
    $candidates.Add([string](Get-DbmConfigProperty $Asset 'content' ''))
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate }
    }
    return ''
}

function Get-DbmOwnedDeviceAssetDattoId {
    [CmdletBinding()]
    param([AllowNull()]$Asset)

    $html = Get-DbmDeviceAssetDetailsHtml -Asset $Asset
    $markerMatch = [regex]::Match(
        $html,
        [regex]::Escape($script:DbmDeviceCardOwnershipMarkerPrefix) + '(\d+) -->'
    )
    if ($markerMatch.Success) {
        return ConvertTo-DbmPositiveId $markerMatch.Groups[1].Value
    }
    return $null
}

function Test-DbmOwnedDeviceAsset {
    [CmdletBinding()]
    param([AllowNull()]$Asset)

    $html = Get-DbmDeviceAssetDetailsHtml -Asset $Asset
    return $html.Contains($script:DbmDeviceCardOwnershipMarkerPrefix, [StringComparison]::Ordinal)
}

function Get-DbmBoundDeviceAssetLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Summary
    )

    $layoutId = ConvertTo-DbmAssetLayoutId (Get-DbmConfigProperty $Config 'assetLayoutId')
    if ($null -eq $layoutId) {
        return $null
    }
    $storedName = [string](Get-DbmConfigProperty $Config 'assetLayoutName' '')
    $Summary.BoundLayoutId = $layoutId
    $Summary.BoundLayoutName = $storedName
    $Summary.BoundLayoutActive = $null
    $Summary.BoundLayoutUsable = $false
    try {
        $layout = Get-DbmHuduAssetLayout -Id $layoutId -ErrorAction Stop
    }
    catch {
        $Summary.Warnings.Add("Device assets were skipped because Hudu asset layout ID $layoutId could not be read. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        return $null
    }
    $activeValue = Get-DbmConfigProperty $layout 'active'
    $isActive = $activeValue -eq $true -or [string]$activeValue -eq '1'
    $actualName = [string](Get-DbmConfigProperty $layout 'name' '')
    if (-not [string]::IsNullOrWhiteSpace($actualName)) {
        $Summary.BoundLayoutName = $actualName
    }
    $Summary.BoundLayoutActive = $isActive
    if (-not [string]::IsNullOrWhiteSpace($storedName) -and
        -not [string]::Equals($storedName, $actualName, [StringComparison]::OrdinalIgnoreCase)) {
        $Summary.Warnings.Add("Bound Hudu asset layout ID $layoutId is named '$actualName', not the stored name '$storedName'. Device assets are written to layout $layoutId. Confirm that is the layout you are viewing in Hudu.")
    }
    if (-not $isActive -or -not (Test-DbmAssetLayoutHasDetailsField -Layout $layout)) {
        $Summary.Warnings.Add("Device assets were skipped because Hudu asset layout ID $layoutId is inactive or no longer has a RichText Asset Details field.")
        return $null
    }
    $Summary.BoundLayoutUsable = $true
    return $layout
}

function Get-DbmDeviceDisplayName {
    [CmdletBinding()]
    param(
        [AllowNull()]$Device,
        [Parameter(Mandatory)][int64]$DeviceId
    )

    $name = [string](Get-DbmConfigProperty $Device 'name' '')
    if ([string]::IsNullOrWhiteSpace($name)) {
        return "Datto device ($DeviceId)"
    }
    return "$($name.Trim()) ($DeviceId)"
}

function New-DbmOwnedDeviceAssetSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int64]$CompanyId,
        [Parameter(Mandatory)][int64]$LayoutId,
        [Parameter(Mandatory)][int64]$DeviceId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Content
    )

    try {
        $created = Set-DbmHuduAsset `
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
                Invoke-DbmWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                    Get-DbmHuduAsset -CompanyId $CompanyId -LayoutId $LayoutId -ErrorAction Stop
                }
            )
        }
        catch {
            throw "The device asset create failed and its result could not be reconciled safely. Create error: $(ConvertTo-DbmBoundedDiagnosticText -Text $createError.Exception.Message) Reconciliation error: $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)"
        }
        $ownedMatches = @(
            $refreshed | Where-Object {
                (Test-DbmOwnedDeviceAsset -Asset $_) -and
                (Get-DbmOwnedDeviceAssetDattoId -Asset $_) -eq $DeviceId
            }
        )
        if ($ownedMatches.Count -eq 1) {
            return [pscustomobject]@{ Asset = $ownedMatches[0]; Reconciled = $true }
        }
        if ($ownedMatches.Count -gt 1) {
            throw "Hudu contains $($ownedMatches.Count) owned device assets for Datto device ID $DeviceId after a failed create. No retry was attempted."
        }
        throw $createError
    }
}

function Sync-DbmCompanyDeviceAssets {
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
        $configuredLayoutId = ConvertTo-DbmAssetLayoutId (Get-DbmConfigProperty $Config 'assetLayoutId')
        if ($null -eq $configuredLayoutId -and -not (@($Summary.Warnings) -contains 'Device assets were skipped because no Hudu asset layout is bound. Use run.ps1 menu option 9 to create or repair the layout.')) {
            $Summary.Warnings.Add('Device assets were skipped because no Hudu asset layout is bound. Use run.ps1 menu option 9 to create or repair the layout.')
        }
        $Summary.AssetsSkipped += @($Devices).Count
        return
    }

    $companyId = Get-DbmMatchingId $HuduCompany.id
    $layoutId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $Layout 'id')
    if ($null -eq $companyId -or $null -eq $layoutId) {
        $Summary.Warnings.Add("Device assets were skipped for '$([string]$HuduCompany.name)' because the Hudu company or layout ID was invalid.")
        return
    }

    try {
        $existing = @(
            Invoke-DbmWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                Get-DbmHuduAsset -CompanyId $companyId -LayoutId $layoutId -ErrorAction Stop
            }
        )
    }
    catch {
        $Summary.Warnings.Add("Device assets were skipped for '$([string]$HuduCompany.name)' because the layout assets could not be listed. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        return
    }

    $ownedByDattoId = @{}
    $ambiguousOwnedIds = [System.Collections.Generic.HashSet[int64]]::new()
    $invalidOwnedAssetIds = [System.Collections.Generic.HashSet[int64]]::new()
    foreach ($asset in $existing) {
        if (-not (Test-DbmOwnedDeviceAsset -Asset $asset)) { continue }
        $assetId = Get-DbmMatchingId (Get-DbmConfigProperty $asset 'id')
        $dattoId = Get-DbmOwnedDeviceAssetDattoId -Asset $asset
        if ($null -eq $dattoId) {
            if ($null -ne $assetId) { $null = $invalidOwnedAssetIds.Add($assetId) }
            $Summary.Errors.Add("Hudu asset ID $(if ($null -eq $assetId) { '<unknown>' } else { $assetId }) on '$([string]$HuduCompany.name)' contains an DATTO-BCDR-MAGIC-DASH ownership prefix without a valid device ID. It was not changed or archived.")
            continue
        }
        if ($ambiguousOwnedIds.Contains($dattoId)) { continue }
        if ($ownedByDattoId.ContainsKey($dattoId)) {
            $ownedByDattoId.Remove($dattoId)
            $null = $ambiguousOwnedIds.Add($dattoId)
            $Summary.Errors.Add("Hudu company '$([string]$HuduCompany.name)' has multiple owned assets for Datto device ID $dattoId. Those assets were left unchanged for manual consolidation.")
        }
        else {
            $ownedByDattoId[$dattoId] = $asset
        }
    }
    $currentDeviceIds = [System.Collections.Generic.HashSet[int64]]::new()
    $statesById = @{}
    $staleBackupHours = ConvertTo-DbmStaleBackupHours (Get-DbmConfigProperty $Config 'staleBackupHours')
    $timeZoneId = ConvertTo-DbmTimeZoneId (Get-DbmConfigProperty $Config 'timeZoneId')
    $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById($timeZoneId)
    $applianceData = if ($null -ne $Client) {
        Get-DbmApplianceData -Client $Client -Summary $Summary
    }
    else {
        [pscustomobject]@{ Available = $false; Items = @() }
    }
    $deviceStates = @(
        Get-DbmDeviceDashboardStates `
            -Devices $Devices `
            -Appliances $applianceData.Items `
            -ApplianceDataAvailable $applianceData.Available `
            -StaleBackupHours $staleBackupHours `
            -NowUtc ([DateTime]::UtcNow) `
            -TimeZone $timeZone
    )
    # The same enrichment the Magic Dash runs, so a device asset and its row on
    # the dashboard cannot tell the operator different things about the machine.
    $null = Add-DbmDeviceContext -DeviceStates $deviceStates -Appliances $applianceData.Items -Summary $Summary
    foreach ($state in $deviceStates) {
        $deviceId = Get-DbmMatchingId (Get-DbmConfigProperty $state.Source 'id')
        if ($null -eq $deviceId) {
            $Summary.Errors.Add("A Datto device for '$([string]$HuduCompany.name)' was skipped because it has no valid ID.")
            continue
        }
        $null = $currentDeviceIds.Add($deviceId)
        $statesById[$deviceId] = $state
    }

    foreach ($deviceId in @($statesById.Keys | Sort-Object)) {
        $state = $statesById[$deviceId]
        $displayName = Get-DbmDeviceDisplayName -Device $state.Source -DeviceId $deviceId
        $html = New-DbmDeviceCardHtml -DeviceState $state -DattoDeviceId $deviceId
        $owned = if ($ownedByDattoId.ContainsKey($deviceId)) { $ownedByDattoId[$deviceId] } else { $null }
        if ($ambiguousOwnedIds.Contains([int64]$deviceId)) {
            $Summary.AssetsSkipped++
            continue
        }
        try {
            if ($null -ne $owned) {
                $assetId = Get-DbmMatchingId $owned.id
                if ($null -eq $assetId) { throw 'Owned Hudu asset is missing a valid ID.' }
                Invoke-DbmWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                    Set-DbmHuduAsset `
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
                        [string](Get-DbmConfigProperty $_ 'name' ''),
                        $displayName,
                        [StringComparison]::OrdinalIgnoreCase
                    ) -and -not (Test-DbmOwnedDeviceAsset -Asset $_)
                }
            )
            $createName = $displayName
            if ($nameCollision.Count -gt 0) {
                $Summary.AssetsSkipped++
                $Summary.Errors.Add("Hudu company '$([string]$HuduCompany.name)' already has an unowned asset named '$displayName'. Rename that asset before syncing Datto device ID $deviceId; DATTO-BCDR-MAGIC-DASH did not create a duplicate.")
                continue
            }
            $createResult = New-DbmOwnedDeviceAssetSafely `
                -CompanyId $companyId `
                -LayoutId $layoutId `
                -DeviceId $deviceId `
                -Name $createName `
                -Content $html
            if ($null -ne $createResult.Asset) { $existing += $createResult.Asset }
            $Summary.AssetsCreated++
        }
        catch {
            $Summary.Errors.Add("Could not publish Datto device '$displayName' to '$([string]$HuduCompany.name)'. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        }
    }

    foreach ($asset in $existing) {
        if (-not (Test-DbmOwnedDeviceAsset -Asset $asset)) { continue }
        $assetId = Get-DbmMatchingId (Get-DbmConfigProperty $asset 'id')
        if ($null -ne $assetId -and $invalidOwnedAssetIds.Contains($assetId)) { continue }
        $dattoId = Get-DbmOwnedDeviceAssetDattoId -Asset $asset
        if ($null -eq $dattoId -or $ambiguousOwnedIds.Contains($dattoId)) { continue }
        if ($currentDeviceIds.Contains($dattoId)) { continue }
        if ($null -eq $assetId) { continue }
        try {
            Invoke-DbmWithRetry -Attempts 2 -DelaySeconds 1 -Operation {
                Archive-DbmHuduAsset -Id $assetId -CompanyId $companyId -Confirm:$false -ErrorAction Stop
            } | Out-Null
            $Summary.AssetsArchived++
        }
        catch {
            $Summary.Errors.Add("Could not archive a retired device asset on '$([string]$HuduCompany.name)'. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        }
    }
}

function Archive-DbmOwnedCompanyDeviceAssets {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Hudu archive is the product operation; delete is intentionally unused.')]
    param(
        [Parameter(Mandatory)][int64]$CompanyId,
        [Parameter(Mandatory)][string]$CompanyName,
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)]$Summary
    )

    $layoutId = ConvertTo-DbmPositiveId (Get-DbmConfigProperty $Layout 'id')
    if ($null -eq $layoutId) { return }
    try {
        $existing = @(Get-DbmHuduAsset -CompanyId $CompanyId -LayoutId $layoutId -ErrorAction Stop)
    }
    catch {
        $Summary.Errors.Add("Owned device assets on '$CompanyName' could not be listed for archive. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        return
    }
    foreach ($asset in $existing) {
        if (-not (Test-DbmOwnedDeviceAsset -Asset $asset)) { continue }
        $dattoId = Get-DbmOwnedDeviceAssetDattoId -Asset $asset
        $assetId = Get-DbmMatchingId $asset.id
        if ($null -eq $dattoId) {
            $Summary.Errors.Add("Hudu asset ID $(if ($null -eq $assetId) { '<unknown>' } else { $assetId }) on '$CompanyName' has a malformed DATTO-BCDR-MAGIC-DASH ownership marker and was not archived.")
            continue
        }
        if ($null -eq $assetId) { continue }
        # Hudu lists archived assets alongside live ones, and archiving one twice
        # fails with "Could not archive". Checking the flag first is precise: it
        # skips work already done without having to treat that error text as
        # benign, which would also swallow a genuine permission failure.
        $alreadyArchived = Get-DbmConfigProperty $asset 'archived' $false
        if ($alreadyArchived -eq $true -or [string]$alreadyArchived -eq 'True') {
            $Summary.AssetsArchived++
            continue
        }
        try {
            Archive-DbmHuduAsset -Id $assetId -CompanyId $CompanyId -Confirm:$false -ErrorAction Stop | Out-Null
            $Summary.AssetsArchived++
        }
        catch {
            # An asset Hudu can no longer find is already gone, which is the state
            # this loop is trying to reach. Reporting it as a failure filled the
            # summary with errors for work that had actually succeeded - observed
            # live, where archiving one company's assets left the rest reporting
            # "Asset not found" while the layout did end up correctly empty.
            if ([string]$_.Exception.Message -match '(?i)asset not found|not found') {
                $Summary.AssetsArchived++
                continue
            }
            $Summary.Errors.Add("Could not archive an owned device asset on '$CompanyName'. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        }
    }
}

function Set-DbmCompanyMagicDash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)]$HuduCompany,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Devices,
        [Parameter(Mandatory)]$Config,
        [AllowNull()]$Summary
    )

    $staleBackupHours = ConvertTo-DbmStaleBackupHours (Get-DbmConfigProperty $Config 'staleBackupHours')
    $timeZoneId = ConvertTo-DbmTimeZoneId (Get-DbmConfigProperty $Config 'timeZoneId')
    $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById($timeZoneId)
    $nowUtc = [DateTime]::UtcNow
    $applianceData = Get-DbmApplianceData -Client $Client -Summary $Summary
    $deviceStates = @(
        Get-DbmDeviceDashboardStates `
            -Devices $Devices `
            -Appliances $applianceData.Items `
            -ApplianceDataAvailable $applianceData.Available `
            -StaleBackupHours $staleBackupHours `
            -NowUtc $nowUtc `
            -TimeZone $timeZone
    )
    # VM restores are fetched per appliance and joined down to the device they
    # are about, so the badge lands on the row the operator is reading rather
    # than in a list they have to cross-reference by hand. Alert rules are
    # collected for their own panel; they carry no asset and cannot be joined.
    # The device assets call the same function, so the two cannot disagree.
    $context = Add-DbmDeviceContext -DeviceStates $deviceStates -Appliances $applianceData.Items -Summary $Summary

    $fleetCounts = Get-DbmFleetCounts -DeviceStates $deviceStates
    $protectionCounts = Get-DbmProtectionCounts -DeviceStates $deviceStates
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
        Merge-DbmTemplate -Template $script:DbmMagicDashWarningSectionTemplate -Values @{
            warning_count   = $fleetCounts.Warning
            warning_summary = ConvertTo-DbmHtml $warningSummary
        }
    }
    $otherDeviceSection = if ($otherDevices.Count -eq 0) {
        ''
    }
    else {
        Merge-DbmTemplate -Template $script:DbmMagicDashOtherDeviceSectionTemplate -Values @{
            other_devices = (New-DbmDeviceTable -DeviceStates $otherDevices -PanelLabel 'Other devices')
        }
    }

    # An unusable client ID drops the link instead of throwing away the whole
    # Magic Dash; ConvertTo-DbmSafeHref turns $null into a neutral '#'.
    $clientId = ConvertTo-DbmNumber $Client.id -AsInt64
    $clientUsage = $null
    if ($null -ne $clientId -and -not [string]::IsNullOrWhiteSpace([string]$Config.dattoAPIKey)) {
        try {
            $clientUsage = @(
                Invoke-DbmWithRetry -Operation {
                    Get-DbmDattoClientUsage -ClientId $clientId -ApiKey ([string]$Config.dattoAPIKey)
                }
            ) | Select-Object -First 1
        }
        catch {
            if ($Summary) {
                $Summary.Warnings.Add("Datto storage usage was unavailable for '$($Client.name)'. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
            }
        }
    }
    $localUsageBytes = if ($clientUsage) { ConvertTo-DbmNumber $clientUsage.local_usage } else { $null }
    # Datto has no private-vault tier, so the Axcient build's "total = private +
    # cloud" could never resolve: private was always $null, which left the headline
    # figure reading Unknown while the cloud number sat beside it fully populated.
    $cloudUsageBytes = if ($clientUsage) { ConvertTo-DbmNumber $clientUsage.cloud_usage } else { $null }
    # Datto has no client-level health field. Clients are built from /bcdr/device
    # records (ConvertFrom-DattoBcdrDeviceClients) and those carry no status, so
    # comparing $Client.health_status to 'NORMAL' was always false and every tile
    # read "Attention needed" no matter how healthy the fleet was. Client health is
    # derived from what IS known: the device rows and the appliances behind them.
    $applianceConcerns = @($applianceData.Items | Where-Object {
            -not [string]::Equals([string]$_.health_status, 'NORMAL', [StringComparison]::OrdinalIgnoreCase)
        })
    $clientHealthy = $fleetCounts.Warning -eq 0 -and
        $fleetCounts.Unknown -eq 0 -and
        $applianceConcerns.Count -eq 0
    $clientHealthStatus = if ($clientHealthy) { 'NORMAL' }
        elseif ($fleetCounts.Warning -gt 0) { 'ATTENTION' }
        elseif ($applianceConcerns.Count -gt 0) { [string]$applianceConcerns[0].health_status }
        else { 'UNKNOWN' }
    $clientHealthReason = if ($clientHealthy) { '' }
        else {
            @(
                if ($fleetCounts.Warning -gt 0) { "$($fleetCounts.Warning) device(s) need attention" }
                if ($fleetCounts.Unknown -gt 0) { "$($fleetCounts.Unknown) device(s) in an unknown state" }
                if ($applianceConcerns.Count -gt 0) { "$($applianceConcerns.Count) appliance(s) not normal" }
            ) -join ' · '
        }
    $templateValues = @{
        client_url          = if ($null -ne $clientId) { ConvertTo-DbmSafeHref "https://auth.datto.com/login" } else { '#' }
        name                = ConvertTo-DbmHtml $Client.name
        health              = New-DbmStatusBadge -Status $clientHealthStatus -Reason $clientHealthReason
        last_update         = ConvertTo-DbmHtml ([TimeZoneInfo]::ConvertTimeFromUtc($nowUtc, $timeZone).ToString('g'))
        time_zone           = ConvertTo-DbmHtml $timeZone.DisplayName
        protection_rows     = New-DbmProtectionRows -Counts $protectionCounts
        fleet_healthy       = $fleetCounts.Healthy
        fleet_warning       = $fleetCounts.Warning
        fleet_unknown       = $fleetCounts.Unknown
        # Shown as "verified of total". A bare count invites reading 15 as good
        # news when the fleet is 40 machines.
        fleet_screenshot    = "$($fleetCounts.ScreenshotVerified) / $($fleetCounts.ScreenshotTotal)"
        cloud_storage       = Format-DbmByteSize $cloudUsageBytes
        local_appliance_usage = Format-DbmByteSize $localUsageBytes
        stale_threshold     = $staleBackupHours
        appliances          = New-DbmApplianceTable -Appliances $applianceData.Items -DataAvailable $applianceData.Available
        vm_restore_count    = $context.RestoreCount
        # The restore panel lists only what could NOT be joined to a device row:
        # repeating the joined ones would say the same thing twice, and a restore
        # with no matching asset is the one that needs its own line. Alert rules
        # are appliance-scoped and never join to a device, so that panel lists
        # every rule.
        vm_restores         = New-DbmVmRestoreTable -Restores $context.UnmatchedRestores -DataAvailable $context.RestoresAvailable -AllJoined ($context.RestoreCount -gt 0)
        alert_rule_count    = $context.AlertRuleCount
        alert_rules         = New-DbmAlertRuleTable -Rules $context.AlertRules -DataAvailable $context.AlertRulesAvailable -TimeZone $timeZone
        warning_section     = $warningSection
        server_devices      = (New-DbmDeviceTable -DeviceStates $serverDevices -PanelLabel 'Servers')
        workstation_devices = (New-DbmDeviceTable -DeviceStates $workstationDevices -PanelLabel 'Workstations')
        other_device_section = $otherDeviceSection
    }
    $content = $script:DbmMagicDashOwnershipMarker + (
        Merge-DbmTemplate -Template $script:DbmMagicDashTemplate -Values $templateValues
    )

    $healthy = $clientHealthy
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
        OwnershipMarker     = $script:DbmMagicDashOwnershipMarker
        Title               = 'Datto BCDR'
        Message             = $dashboardMessage
        Shade               = $shade
        Content             = $content
        Icon                = 'fas fa-shield-alt'
        ImageUrl            = ''
        ErrorAction         = 'Stop'
    }
    try {
        Set-DbmHuduMagicDashForCompany @dashParameters | Out-Null
    }
    catch [ArgumentException] {
        if ($_.Exception.Message -notmatch 'bridge request exceeds the maximum frame size') {
            throw
        }
        $deviceCount = $deviceStates.Count
        $fallbackValues = $templateValues.Clone()
        $fallbackValues.appliances = New-DbmEmptyState -Message 'Appliance detail rows were omitted to keep this very large dashboard within Hudu transfer limits.'
        # These tables sit under the device rows the fallback is already cutting,
        # so they go with them rather than being left to describe rows that are
        # no longer on the page.
        $fallbackValues.vm_restores = New-DbmEmptyState -Message 'VM restore rows were omitted to keep this very large dashboard within Hudu transfer limits.'
        $fallbackValues.alert_rules = New-DbmEmptyState -Message 'Alert rule rows were omitted to keep this very large dashboard within Hudu transfer limits.'
        $fallbackValues.server_devices = if ($serverDevices.Count -gt 0) {
            New-DbmEmptyState -Message "$($serverDevices.Count) server detail row(s) were omitted to keep this very large dashboard within Hudu transfer limits."
        }
        else {
            New-DbmDeviceTable -DeviceStates @() -PanelLabel 'Servers'
        }
        $fallbackValues.workstation_devices = if ($workstationDevices.Count -gt 0) {
            New-DbmEmptyState -Message "$($workstationDevices.Count) workstation detail row(s) were omitted to keep this very large dashboard within Hudu transfer limits."
        }
        else {
            New-DbmDeviceTable -DeviceStates @() -PanelLabel 'Workstations'
        }
        $fallbackValues.other_device_section = if ($otherDevices.Count -gt 0) {
            Merge-DbmTemplate -Template $script:DbmMagicDashOtherDeviceSectionTemplate -Values @{
                other_devices = (New-DbmEmptyState -Message "$($otherDevices.Count) other-device detail row(s) were omitted to keep this very large dashboard within Hudu transfer limits.")
            }
        }
        else { '' }
        $fallbackContent = $script:DbmMagicDashOwnershipMarker + (
            Merge-DbmTemplate -Template $script:DbmMagicDashTemplate -Values $fallbackValues
        )
        $dashParameters.Content = $fallbackContent
        Set-DbmHuduMagicDashForCompany @dashParameters | Out-Null
        if ($Summary) {
            $Summary.Warnings.Add("Hudu company '$($HuduCompany.name)' has $deviceCount devices. Device and appliance detail rows were omitted because the complete Magic Dash exceeded the bridge transfer limit; fleet counts and storage totals were still updated.")
        }
    }
}

function Invoke-DbmMatchOperations {
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
                @(Assert-DbmMagicDashOwnership -CompanyId ([int64]$operation.SourceHuduId) -CompanyName ([string]$operation.SourceHuduName))
            }
            else { @() }
            $layout = $null
            if ($null -ne $Config) {
                $boundLayoutId = ConvertTo-DbmAssetLayoutId (Get-DbmConfigProperty $Config 'assetLayoutId')
                if ($null -ne $boundLayoutId) {
                    $layout = Get-DbmBoundDeviceAssetLayout -Config $Config -Summary $Summary
                }
            }
            if ($operation.Action -eq 'Delete') {
                if ($sourceExists -and $null -ne $layout) {
                    Archive-DbmOwnedCompanyDeviceAssets `
                        -CompanyId ([int64]$operation.SourceHuduId) `
                        -CompanyName ([string]$operation.SourceHuduName) `
                        -Layout $layout `
                        -Summary $Summary
                }
                if ($sourceDashes.Count -gt 0) {
                    foreach ($dash in $sourceDashes) {
                        Remove-DbmHuduMagicDash -Id ([int64]$dash.id) -Confirm:$false -ErrorAction Stop
                    }
                }
                if ($sourceExists) {
                    $Summary.Notes.Add("Removed the DATTO-BCDR-MAGIC-DASH Magic Dash from '$($operation.SourceHuduName)'.")
                }
                else {
                    $Summary.Notes.Add("Removed a stale match for missing Hudu company ID $($operation.SourceHuduId); no Hudu content remained to delete.")
                }
            }
            elseif ($operation.Action -eq 'Move') {
                $targetCompany = @(
                    Resolve-DbmHuduCompanyForNameWrite `
                        -CompanyId ([int64]$operation.TargetHuduId) `
                        -ErrorAction Stop
                )
                $currentTargetName = if ($targetCompany.Count -eq 1) { [string]$targetCompany[0].name } else { '' }
                if ($targetCompany.Count -ne 1 -or
                    (Get-DbmMatchingId $targetCompany[0].id) -ne [int64]$operation.TargetHuduId) {
                    throw "The destination Hudu company ID $($operation.TargetHuduId) is missing or its current name is duplicated. Hudu's Magic Dash API targets company names, so this move was blocked to prevent writing to the wrong company."
                }
                $moveDevices = @()
                $moveClient = $null
                if ($null -ne $layout -and $sourceDashes.Count -gt 0) {
                    try {
                        $dattoClient = @(
                            Get-DbmDattoClient -ErrorAction Stop | Where-Object {
                                (Get-DbmMatchingId $_.id) -eq [int64]$operation.DattoId
                            }
                        )
                        if ($dattoClient.Count -eq 1) {
                            $moveClient = $dattoClient[0]
                            $moveDevices = @(Invoke-DbmWithRetry -Operation { $moveClient | Get-Device -ErrorAction Stop })
                        }
                    }
                    catch {
                        throw "Owned device assets could not be prepared for the move. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)"
                    }
                }
                foreach ($dash in $sourceDashes) {
                    $dashMessage = [string](Get-DbmConfigProperty $dash 'message' '')
                    if ([string]::IsNullOrWhiteSpace($dashMessage)) {
                        # Message is mandatory at the Hudu client boundary. A legacy
                        # or manually edited managed dash can omit it, and passing an
                        # empty string made the queued Move fail binding forever on
                        # every replay, with no recovery path outside config surgery.
                        $dashMessage = 'Datto BCDR'
                    }
                    Set-DbmHuduMagicDashForCompany `
                        -CompanyId ([int64]$operation.TargetHuduId) `
                        -ExpectedCompanyName $currentTargetName `
                        -OwnershipMarker $script:DbmMagicDashOwnershipMarker `
                        -Title 'Datto BCDR' `
                        -Message $dashMessage `
                        -Shade ([string](Get-DbmConfigProperty $dash 'shade' '')) `
                        -Content ([string](Get-DbmConfigProperty $dash 'content' '')) `
                        -ImageUrl ([string](Get-DbmConfigProperty $dash 'image_url' '')) `
                        -ErrorAction Stop | Out-Null
                }
                if ($null -ne $layout -and $sourceDashes.Count -gt 0) {
                    $assetErrorCountBefore = $Summary.Errors.Count
                    Sync-DbmCompanyDeviceAssets `
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
                        Archive-DbmOwnedCompanyDeviceAssets `
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
                    Remove-DbmHuduMagicDash -Id ([int64]$dash.id) -Confirm:$false -ErrorAction Stop
                }
                if ($sourceExists) {
                    $Summary.Notes.Add("Moved the DATTO-BCDR-MAGIC-DASH Magic Dash from '$($operation.SourceHuduName)' to '$currentTargetName'.")
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
            $Summary.Errors.Add("Could not complete the queued '$($operation.Action)' operation for '$($operation.SourceHuduName)'. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        }
        if ($Summary.Errors.Count -gt $errorCountBefore) { $operationSucceeded = $false }
        $Summary.OperationResults.Add([pscustomobject]@{
            Operation = $operation
            Succeeded = $operationSucceeded
        })
    }
    return $Summary
}

function Invoke-DbmPendingOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Summary
    )

    if ($Config.PSObject.Properties.Name -notcontains 'pendingOperations') { return $Summary }
    $pending = @($Config.pendingOperations | Where-Object { $null -ne $_ })
    if ($pending.Count -eq 0) { return $Summary }
    $layoutId = ConvertTo-DbmAssetLayoutId (Get-DbmConfigProperty $Config 'assetLayoutId')
    if ($null -eq $layoutId) {
        $Summary.Notes.Add('Queued matching operations skipped device assets because no Hudu asset layout is bound.')
    }
    else {
        $Summary.Notes.Add('Queued matching operations also archive or move owned device assets.')
    }

    try {
        $currentCompanies = @(Get-DbmHuduCompany -ErrorAction Stop)
        $companySelection = Select-DbmUniqueSyncEndpoints `
            -Items $currentCompanies `
            -ServiceName 'Hudu' `
            -RecordType 'company'
        if ($companySelection.Errors.Count -gt 0) {
            throw "The current Hudu company list is not safe for queued operations. $($companySelection.Errors -join ' ')"
        }
        $currentCompanyIds = $companySelection.Ids
    }
    catch {
        $safeError = ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message
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
        Invoke-DbmMatchOperations -Operations $pending -Summary $Summary -Config $Config | Out-Null
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

function Select-DbmUniqueSyncEndpoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [Parameter(Mandatory)][string]$ServiceName,
        [Parameter(Mandatory)][string]$RecordType
    )

    $groups = @{}
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Items) {
        $id = Get-DbmMatchingId $item.id
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

function Invoke-DbmSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$AlreadyConnected,
        [AllowNull()][string]$ConfigPath
    )

    $summary = New-DbmSyncSummary
    try {
        if (-not $AlreadyConnected) { Connect-DbmServices -Config $Config }
        Invoke-DbmPendingOperations -Config $Config -Summary $summary | Out-Null
    }
    catch {
        $summary.Errors.Add("Initial API connection or pending-operation recovery failed. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        $summary.CompletedUtc = [DateTime]::UtcNow
        return [pscustomobject]@{ Config = $Config; Summary = $summary }
    }
    try {
        $dattoClients = @(Invoke-DbmWithRetry -Operation { Get-Client -ErrorAction Stop })
        $huduCompanies = @(Invoke-DbmWithRetry -Operation { Get-DbmHuduCompany -ErrorAction Stop })
    }
    catch {
        $summary.Errors.Add("Initial API data could not be loaded. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        $summary.CompletedUtc = [DateTime]::UtcNow
        return [pscustomobject]@{ Config = $Config; Summary = $summary }
    }

    # Normalize endpoint IDs immediately after the read so every later phase sees
    # only unambiguous records. Pending operations perform the same validation.
    $clientSelection = Select-DbmUniqueSyncEndpoints `
        -Items $dattoClients `
        -ServiceName 'Datto' `
        -RecordType 'client'
    $companySelection = Select-DbmUniqueSyncEndpoints `
        -Items $huduCompanies `
        -ServiceName 'Hudu' `
        -RecordType 'company'
    foreach ($endpointError in @($clientSelection.Errors) + @($companySelection.Errors)) {
        $summary.Errors.Add($endpointError)
    }
    $dattoClients = @($clientSelection.Items)
    $huduCompanies = @($companySelection.Items)
    $clientIds = $clientSelection.Ids
    $companyIds = $companySelection.Ids

    if ($Config.autoMatch -and @($Config.pendingOperations).Count -eq 0) {
        $matchesBeforeAutoMatch = @($Config.matches)
        $before = $matchesBeforeAutoMatch.Count
        $Config.matches = @(Update-DbmAutomaticMatches -HuduCompanies $huduCompanies -DattoClients $dattoClients -Matches @($Config.matches) -Exclusions @($Config.autoMatchExclusions))
        $summary.AutomaticMatchesAdded = @($Config.matches).Count - $before
        if ($summary.AutomaticMatchesAdded -gt 0) {
            if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
                $Config.matches = $matchesBeforeAutoMatch
                $summary.AutomaticMatchesAdded = 0
                $summary.Errors.Add('Automatic matches were not applied because no durable config.json path was supplied. No Hudu content was written for those unpersisted matches.')
            }
            else {
                try {
                    Save-DbmConfig -Config $Config -Path $ConfigPath | Out-Null
                    $summary.Notes.Add("Persisted $($summary.AutomaticMatchesAdded) automatic match(es) before any Hudu content was written for them.")
                }
                catch {
                    $Config.matches = $matchesBeforeAutoMatch
                    $summary.AutomaticMatchesAdded = 0
                    $summary.Errors.Add("Automatic matches could not be saved before Hudu updates, so they were not applied. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
                }
            }
        }
    }

    foreach ($storedMatch in @($Config.matches)) {
        if (-not $clientIds.Contains([int64]$storedMatch.dattoId)) {
            $summary.Errors.Add("Stored match '$($storedMatch.name)' references missing Datto client ID $($storedMatch.dattoId). Run run.ps1 and remove or replace the stale match.")
        }
    }

    $matchesByDattoId = @{}
    foreach ($storedMatch in @($Config.matches)) {
        $matchesByDattoId[[int64]$storedMatch.dattoId] = $storedMatch
    }
    $companiesById = @{}
    foreach ($huduCompany in $huduCompanies) {
        $huduCompanyId = Get-DbmMatchingId $huduCompany.id
        if ($null -ne $huduCompanyId) {
            $companiesById[$huduCompanyId] = $huduCompany
        }
    }

    $deviceLayout = Get-DbmBoundDeviceAssetLayout -Config $Config -Summary $summary

    foreach ($client in $dattoClients | Sort-Object name, id) {
        $currentClientId = Get-DbmMatchingId $client.id
        if (-not $matchesByDattoId.ContainsKey($currentClientId)) {
            $summary.UnmatchedClients.Add("$($client.name) (Datto ID $($client.id))")
            continue
        }
        $match = $matchesByDattoId[$currentClientId]
        $matchedHuduId = [int64]$match.huduID
        if (-not $companiesById.ContainsKey($matchedHuduId)) {
            $summary.Errors.Add("Datto client '$($client.name)' is matched to missing Hudu company ID $matchedHuduId. Run run.ps1 and repair the stale match.")
            continue
        }
        $company = $companiesById[$matchedHuduId]

        $companyResult = [pscustomobject]@{
            HuduCompany = [string]$company.name
            DattoClient = [string]$client.name
            MagicDashUpdated = $false
            DeviceCount = 0
        }
        try {
            $devices = @()
            $devicesLoaded = $false
            try {
                $devices = @(Invoke-DbmWithRetry -Operation { $client | Get-Device -ErrorAction Stop })
                $devicesLoaded = $true
                $summary.DattoDevicesRetrieved += @($devices).Count
                $companyResult.DeviceCount = @($devices).Count
                Set-DbmCompanyMagicDash -Client $client -HuduCompany $company -Devices $devices -Config $Config -Summary $summary
                $summary.MagicDashesUpdated++
                $companyResult.MagicDashUpdated = $true
            }
            catch {
                $summary.Errors.Add("Could not safely update the name-based Magic Dash for Hudu company ID $($company.id). $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
            }
            if ($devicesLoaded -and $companyResult.MagicDashUpdated) {
                Sync-DbmCompanyDeviceAssets `
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
            $summary.Errors.Add("Sync failed for Datto client '$($client.name)' / Hudu company '$($company.name)'. Other companies continued. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
        }
        $summary.CompanyResults.Add($companyResult)
    }

    $matchedHuduIds = [System.Collections.Generic.HashSet[int64]]::new()
    foreach ($matchItem in @($Config.matches)) {
        if ($clientIds.Contains([int64]$matchItem.dattoId) -and $companyIds.Contains([int64]$matchItem.huduID)) {
            $null = $matchedHuduIds.Add([int64]$matchItem.huduID)
        }
    }
    foreach ($huduCompany in $huduCompanies | Sort-Object name, id) {
        if (-not $matchedHuduIds.Contains([int64]$huduCompany.id)) {
            $summary.UnmatchedHuduCompanies.Add("$($huduCompany.name) (Hudu ID $($huduCompany.id))")
        }
    }
    foreach ($client in $dattoClients) {
        $unmatchedClientId = Get-DbmMatchingId $client.id
        if ($null -eq $unmatchedClientId -or $matchesByDattoId.ContainsKey($unmatchedClientId)) {
            continue
        }
        $clientKey = Convert-DbmComparableCompanyName ([string]$client.name)
        if ([string]::IsNullOrWhiteSpace($clientKey)) { continue }
        foreach ($huduCompany in $huduCompanies) {
            $unmatchedCompanyId = Get-DbmMatchingId $huduCompany.id
            if ($null -eq $unmatchedCompanyId -or $matchedHuduIds.Contains($unmatchedCompanyId)) {
                continue
            }
            $companyKey = Convert-DbmComparableCompanyName ([string]$huduCompany.name)
            if ($clientKey -eq $companyKey) {
                $summary.Warnings.Add("Datto client '$($client.name)' and Hudu company '$($huduCompany.name)' look like the same name except spacing or punctuation. Exact-name automatch did not connect them. Match them in run.ps1 if they should share a Magic Dash.")
            }
        }
    }
    # Direct-to-Cloud is a separate inventory from /bcdr, so a DTC-protected
    # machine appears in no appliance's asset list and would simply be missing
    # from every dashboard. Missing reads as "this client has nothing else",
    # so the gap is stated rather than left silent. Only the count is claimed:
    # the per-asset shape has never been sampled on a live account.
    $dtcCount = -1
    try { $dtcCount = Get-DattoBcdrDtcAssetCount }
    catch { $dtcCount = -1 }
    if ($dtcCount -gt 0) {
        $summary.Warnings.Add("Datto reports $dtcCount Direct-to-Cloud asset(s) on this account. DTC is a separate inventory from the BCDR appliances and is NOT shown on these Magic Dashes or device assets, so those machines are not covered by this sync.")
    }

    if ($summary.MagicDashesUpdated -gt 0 -and [int]$summary.DattoDevicesRetrieved -eq 0) {
        $summary.Warnings.Add('Datto returned 0 devices for every matched client. Magic Dashes were updated with empty device lists, and no Hudu device assets were created. Confirm those Datto clients have protected devices.')
    }
    $reportOrphanedDashes = ConvertTo-DbmBoolean `
        (Get-DbmConfigProperty $Config 'reportOrphanedDashes' $null) `
        -PropertyName 'reportOrphanedDashes' `
        -Default $true
    if ($reportOrphanedDashes -and $companySelection.Errors.Count -eq 0) {
        foreach ($huduCompany in $huduCompanies | Sort-Object name, id) {
            if ($matchedHuduIds.Contains([int64]$huduCompany.id)) { continue }
            try {
                $dashes = @(Get-DbmHuduMagicDash `
                    -CompanyId ([int64]$huduCompany.id) `
                    -Title 'Datto BCDR' `
                    -ErrorAction Stop)
                if (@($dashes | Where-Object { Test-DbmOwnedMagicDash -Dash $_ }).Count -gt 0) {
                    $summary.Warnings.Add("Hudu company '$($huduCompany.name)' has an owned DATTO-BCDR-MAGIC-DASH Magic Dash but is not matched to an available Datto client. Run run.ps1 and unmatch it properly to remove it, or remove the stale dash manually if its Datto client no longer exists.")
                }
            }
            catch {
                $summary.Warnings.Add("Orphaned Magic Dash reporting could not check Hudu company '$($huduCompany.name)'. $(ConvertTo-DbmBoundedDiagnosticText -Text $_.Exception.Message)")
            }
        }
    }

    $summary.CompletedUtc = [DateTime]::UtcNow
    return [pscustomobject]@{ Config = $Config; Summary = $summary }
}

function Show-DbmSyncSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Summary)

    $duration = if ($Summary.CompletedUtc) {
        [math]::Round(($Summary.CompletedUtc - $Summary.StartedUtc).TotalSeconds, 1)
    }
    else { 0 }

    Write-Host "`n============================================================" -ForegroundColor DarkGray
    Write-Host 'DATTO-BCDR-MAGIC-DASH sync summary' -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host "Matched companies:       $($Summary.MatchedCompanies)" -ForegroundColor Green
    Write-Host "Automatic matches added: $($Summary.AutomaticMatchesAdded)" -ForegroundColor Green
    Write-Host "Magic Dashes updated:    $($Summary.MagicDashesUpdated)" -ForegroundColor Green
    $deviceColor = if ([int]$Summary.DattoDevicesRetrieved -eq 0) { 'Yellow' } else { 'Green' }
    Write-Host "Datto devices pulled:  $($Summary.DattoDevicesRetrieved)" -ForegroundColor $deviceColor
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
            Write-Host (ConvertTo-DbmRedactedText "  $($result.HuduCompany) ← $($result.DattoClient): $dash, $deviceCount Datto device(s)")
        }
    }
    if ($Summary.UnmatchedClients.Count -gt 0) {
        Write-Host "`nUnmatched Datto clients" -ForegroundColor Yellow
        $Summary.UnmatchedClients | ForEach-Object { Write-Host (ConvertTo-DbmRedactedText "  - $_") -ForegroundColor Yellow }
    }
    if ($Summary.UnmatchedHuduCompanies.Count -gt 0) {
        Write-Host "`nUnmatched Hudu companies" -ForegroundColor Yellow
        $Summary.UnmatchedHuduCompanies | ForEach-Object { Write-Host (ConvertTo-DbmRedactedText "  - $_") -ForegroundColor Yellow }
    }
    if ($Summary.Notes.Count -gt 0) {
        Write-Host "`nNotes" -ForegroundColor Cyan
        $Summary.Notes | ForEach-Object { Write-Host (ConvertTo-DbmRedactedText "  - $_") -ForegroundColor Cyan }
    }
    if ($Summary.Warnings.Count -gt 0) {
        Write-Host "`nWarnings" -ForegroundColor Yellow
        $Summary.Warnings | ForEach-Object { Write-Host (ConvertTo-DbmRedactedText "  - $_") -ForegroundColor Yellow }
    }
    if ($Summary.Errors.Count -gt 0) {
        Write-Host "`nErrors" -ForegroundColor Red
        $Summary.Errors | ForEach-Object { Write-Host (ConvertTo-DbmRedactedText "  - $_") -ForegroundColor Red }
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
