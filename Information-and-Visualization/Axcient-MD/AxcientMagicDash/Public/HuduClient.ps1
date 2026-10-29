function Connect-AmdHudu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$InstanceUrl,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ApiKey
    )

    Set-AmdSensitiveValues -Values @($ApiKey) -Add
    Start-AmdHuduBridge -InstanceUrl $InstanceUrl -ApiKey $ApiKey
}

function Disconnect-AmdHudu {
    [CmdletBinding()]
    param()

    Stop-AmdHuduBridge
}

function Get-AmdHuduAppInfo {
    [CmdletBinding()]
    param()

    Invoke-AmdHuduOp -Operation app_info
}

function Get-AmdHuduCompany {
    [CmdletBinding()]
    param()

    Invoke-AmdHuduOp -Operation companies.list
}

function Resolve-AmdHuduCompanyForNameWrite {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$CompanyId)

    Invoke-AmdHuduOp -Operation companies.resolve_for_name_write -Arguments @{
        company_id = $CompanyId
    }
}

function Get-AmdHuduMagicDash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$CompanyId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Title
    )

    Invoke-AmdHuduOp -Operation magic_dash.list -Arguments @{
        company_id = $CompanyId
        title      = $Title
    }
}

function Set-AmdHuduMagicDash {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Title,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CompanyName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Message,
        [AllowEmptyString()][string]$Icon = '',
        [AllowEmptyString()][string]$ImageUrl = '',
        [AllowEmptyString()][string]$ContentLink = '',
        [AllowEmptyString()][string]$Content = '',
        [AllowEmptyString()][string]$Shade = ''
    )

    if (-not [string]::IsNullOrEmpty($Icon) -and -not [string]::IsNullOrEmpty($ImageUrl)) {
        throw [ArgumentException]::new('Only one of Icon or ImageUrl can be supplied.')
    }
    if (-not [string]::IsNullOrEmpty($ContentLink) -and -not [string]::IsNullOrEmpty($Content)) {
        throw [ArgumentException]::new('Only one of Content or ContentLink can be supplied.')
    }
    if ($PSCmdlet.ShouldProcess("$CompanyName - $Title", 'Create or update Hudu Magic Dash')) {
        # The bridge resolves this legacy name-only API to one company ID, repeats
        # that validation immediately before the POST, and verifies the response.
        Invoke-AmdHuduOp -Operation magic_dash.upsert -Arguments @{
            payload = @{
                title        = $Title
                company_name = $CompanyName
                message      = $Message
                icon         = $Icon
                image_url    = $ImageUrl
                content_link = $ContentLink
                content      = $Content
                shade        = $Shade
            }
        }
    }
}

function Set-AmdHuduMagicDashForCompany {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$CompanyId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedCompanyName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OwnershipMarker,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Title,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Message,
        [AllowEmptyString()][string]$Icon = '',
        [AllowEmptyString()][string]$ImageUrl = '',
        [AllowEmptyString()][string]$ContentLink = '',
        [AllowEmptyString()][string]$Content = '',
        [AllowEmptyString()][string]$Shade = ''
    )

    if (-not [string]::IsNullOrEmpty($Icon) -and -not [string]::IsNullOrEmpty($ImageUrl)) {
        throw [ArgumentException]::new('Only one of Icon or ImageUrl can be supplied.')
    }
    if (-not [string]::IsNullOrEmpty($ContentLink) -and -not [string]::IsNullOrEmpty($Content)) {
        throw [ArgumentException]::new('Only one of Content or ContentLink can be supplied.')
    }
    if ($PSCmdlet.ShouldProcess("Hudu company ID $CompanyId - $Title", 'Create or update scoped Hudu Magic Dash')) {
        Invoke-AmdHuduOp -Operation magic_dash.upsert_for_company -Arguments @{
            company_id           = $CompanyId
            expected_company_name = $ExpectedCompanyName
            ownership_marker     = $OwnershipMarker
            payload              = @{
                title        = $Title
                message      = $Message
                icon         = $Icon
                image_url    = $ImageUrl
                content_link = $ContentLink
                content      = $Content
                shade        = $Shade
            }
        }
    }
}

function Remove-AmdHuduMagicDash {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$Id)

    if ($PSCmdlet.ShouldProcess("Hudu Magic Dash $Id", 'Delete')) {
        Invoke-AmdHuduOp -Operation magic_dash.delete -Arguments @{ id = $Id }
    }
}

function Get-AmdHuduAssetLayout {
    [CmdletBinding()]
    param([long]$Id)

    if ($PSBoundParameters.ContainsKey('Id')) {
        if ($Id -lt 1) { throw 'Asset layout get requires a positive Hudu layout ID.' }
        try {
            Invoke-AmdHuduOp -Operation asset_layouts.get -Arguments @{ id = $Id }
        }
        catch {
            if ($_.Exception.Message -match '^Hudu asset layout ID \d+ was not found\.$') {
                throw [Management.Automation.ItemNotFoundException]::new($_.Exception.Message)
            }
            throw
        }
    }
    else {
        Invoke-AmdHuduOp -Operation asset_layouts.list
    }
}

function New-AmdHuduAssetLayout {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Fields
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Create Hudu asset layout')) {
        Invoke-AmdHuduOp -Operation asset_layouts.create -Arguments @{
            payload = @{
                name             = $Name
                icon             = 'fas fa-hdd'
                color            = '#6136ff'
                icon_color       = '#ffffff'
                include_passwords = $true
                include_photos   = $true
                include_comments = $true
                include_files    = $true
                fields           = @($Fields)
            }
        }
    }
}

function ConvertTo-AmdHuduAssetLayoutUpdatePayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Layout,
        [switch]$AddDetailsField
    )

    $payload = [ordered]@{ active = $true }
    foreach ($propertyName in @(
            'name'
            'icon'
            'color'
            'icon_color'
            'include_passwords'
            'include_photos'
            'include_comments'
            'include_files'
            'password_types'
        )) {
        $value = Get-AmdConfigProperty $Layout $propertyName
        if ($null -ne $value) {
            $payload[$propertyName] = $value
        }
    }

    $sourceFields = @(Get-AmdConfigProperty $Layout 'fields' @())
    if ($sourceFields.Count -eq 0 -and -not $AddDetailsField) {
        throw 'The Hudu asset layout has no existing fields to preserve during activation.'
    }
    $payloadFields = [Collections.Generic.List[object]]::new()
    $compatibleDetailsFields = 0
    foreach ($field in $sourceFields) {
        $fieldId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $field 'id')
        if ($null -eq $fieldId) {
            throw 'The Hudu asset layout contains an existing field without a positive ID; the update was stopped to prevent duplicate fields.'
        }
        $fieldLabel = [string](Get-AmdConfigProperty $field 'label' '')
        $fieldType = [string](Get-AmdConfigProperty $field 'field_type' '')
        if ([string]::Equals($fieldLabel, 'Asset Details', [StringComparison]::OrdinalIgnoreCase)) {
            if (-not [string]::Equals($fieldType, 'RichText', [StringComparison]::OrdinalIgnoreCase)) {
                throw "The selected Hudu layout already has an Asset Details field with an incompatible field type '$fieldType'. Select a different layout; customer fields were not changed."
            }
            $compatibleDetailsFields++
        }
        $fieldPayload = [ordered]@{ id = $fieldId }
        foreach ($fieldPropertyName in @(
                'label'
                'field_type'
                'required'
                'show_in_list'
                'position'
                'hint'
                'min'
                'max'
                'options'
                'expiration'
                'linkable_id'
                'multiple_options'
                'list_id'
            )) {
            $fieldValue = Get-AmdConfigProperty $field $fieldPropertyName
            if ($null -ne $fieldValue) {
                $fieldPayload[$fieldPropertyName] = $fieldValue
            }
        }
        $payloadFields.Add($fieldPayload)
    }
    if ($compatibleDetailsFields -gt 1) {
        throw 'The selected Hudu layout has multiple RichText Asset Details fields. Select a different layout; customer fields were not changed.'
    }
    if ($AddDetailsField -and $compatibleDetailsFields -eq 0) {
        $payloadFields.Add([ordered]@{
            label        = 'Asset Details'
            field_type   = 'RichText'
            required     = $false
            show_in_list = $false
            position     = $sourceFields.Count + 1
        })
    }
    $payload.fields = @($payloadFields)
    return $payload
}

function Set-AmdHuduAssetLayoutActive {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$Id)

    if ($PSCmdlet.ShouldProcess("Hudu asset layout $Id", 'Activate')) {
        $layout = Get-AmdHuduAssetLayout -Id $Id -ErrorAction Stop
        $returnedId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $layout 'id')
        if ($null -eq $returnedId -or $returnedId -ne $Id) {
            throw "Hudu did not return asset layout ID $Id before activation."
        }

        $payload = ConvertTo-AmdHuduAssetLayoutUpdatePayload -Layout $layout

        Invoke-AmdHuduOp -Operation asset_layouts.update -Arguments @{
            id      = $Id
            payload = $payload
        }
    }
}

function Add-AmdHuduAssetLayoutDetailsField {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$Id)

    if ($PSCmdlet.ShouldProcess("Hudu asset layout $Id", 'Connect and add the AXCIENT-MAGIC-DASH field if missing')) {
        $layout = Get-AmdHuduAssetLayout -Id $Id -ErrorAction Stop
        $returnedId = ConvertTo-AmdPositiveId (Get-AmdConfigProperty $layout 'id')
        if ($null -eq $returnedId -or $returnedId -ne $Id) {
            throw "Hudu did not return asset layout ID $Id before connection."
        }
        $payload = ConvertTo-AmdHuduAssetLayoutUpdatePayload -Layout $layout -AddDetailsField
        Invoke-AmdHuduOp -Operation asset_layouts.connect_existing -Arguments @{
            id      = $Id
            payload = $payload
        }
    }
}

function Get-AmdHuduAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$CompanyId,
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$LayoutId
    )

    Invoke-AmdHuduOp -Operation assets.list -Arguments @{
        company_id      = $CompanyId
        asset_layout_id = $LayoutId
    }
}

function Set-AmdHuduAsset {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$CompanyId,
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$LayoutId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [AllowEmptyString()][string]$PrimarySerial = '',
        [AllowEmptyString()][string]$Content = '',
        [long]$Id
    )

    if ($PSBoundParameters.ContainsKey('Id') -and $Id -lt 1) {
        throw 'Asset update requires a positive Hudu asset ID.'
    }

    $customFields = @(@{ 'Asset Details' = $Content })
    if ($PSBoundParameters.ContainsKey('Id')) {
        if ($PSCmdlet.ShouldProcess("Hudu asset $Id", 'Update')) {
            Invoke-AmdHuduOp -Operation assets.update -Arguments @{
                id         = $Id
                company_id = $CompanyId
                payload    = @{
                    name          = $Name
                    custom_fields = $customFields
                }
            }
        }
    }
    elseif ($PSCmdlet.ShouldProcess("$Name on Hudu company $CompanyId", 'Create Hudu asset')) {
        Invoke-AmdHuduOp -Operation assets.create -Arguments @{
            company_id = $CompanyId
            payload    = @{
                name            = $Name
                primary_serial  = $PrimarySerial
                asset_layout_id = $LayoutId
                custom_fields   = $customFields
            }
        }
    }
}

function Archive-AmdHuduAsset {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Hudu archive is the product operation; delete is intentionally unused.')]
    param(
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$Id,
        [Parameter(Mandatory)][ValidateRange(1, [long]::MaxValue)][long]$CompanyId
    )

    if ($PSCmdlet.ShouldProcess("Hudu asset $Id", 'Archive')) {
        Invoke-AmdHuduOp -Operation assets.archive -Arguments @{
            id         = $Id
            company_id = $CompanyId
        }
    }
}
