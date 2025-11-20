# =============================================================================
# HUDU MAGIC DASH SCRIPT - MULTI-INTEGRATION ASSET COUNTER
# Created by: David Kniskern
# Created on: 2025-09-25
# Updated on: 2025-09-25
# Updated by: David Kniskern
# Updated for: Hudu Magic Dash
# Updated for: Hudu API
# Updated for: Hudu API Key Vault
# Updated for: Hudu API Key Vault Name
# Updated for: Hudu API Key Vault Secret Names
# Updated for: Hudu API Key Vault Secret Names
# =============================================================================
# 
# PURPOSE:
# This script automatically counts assets from multiple integrations in Hudu
# and creates Magic Dash tiles showing the asset counts for each company.
#
# SUPPORTED INTEGRATIONS (11 total):
# 1. HaloPSA     - Devices, Locations, Contacts
# 2. DattoRMM    - Devices only
# 3. CW Manage   - Configurations, Locations, Contacts  
# 4. AutoTask    - Devices, Locations, Contacts
# 5. Atera       - Devices, Contacts
# 6. Addigy      - Devices only
# 7. Syncro      - Devices, Contacts
# 8. NinjaOne    - Devices, Locations
# 9. Domotz      - Assets only
# 10. N-Central  - Devices, Locations
# 11. PulsewayRMM - Assets only
#
# INTEGRATION STRUCTURE:
# Each integration uses the following pattern:
# - integrator_name: "service_name" (e.g., "halo", "dattormm", "cw_manage", "autotask", "atera", "addigy", "syncro", "ninja", "domotz", "ncentral", "pulseway_rmm")
# - sync_type: "device", "configuration", "site", "contact" (varies by integration)
# - archived: boolean flag for asset status
#
# ASSET LAYOUT REQUIREMENTS:
# Each integration needs these fields in the "Company Details" asset layout:
# - ServiceName:ENABLED (Checkbox) - Controls Magic Dash tile creation
# - ServiceName:NOTE (Text) - Custom message (optional)
# - ServiceName:URL (Text) - Custom URL (optional)  
# - ServiceName:DeviceCount (Text) - Auto-populated device count
# - ServiceName:LocationCount (Text) - Auto-populated location count (if applicable)
# - ServiceName:ContactCount (Text) - Auto-populated contact count (if applicable)
# - ServiceName:ConfigurationCount (Text) - Auto-populated config count (if applicable)
#
# TO ADD A NEW INTEGRATION:
# 1. Add counting logic after line ~220 (follow existing pattern)
# 2. Add to $ourIntegrators array (line ~220)
# 3. Add to debug output (line ~250)
# 4. Add to $fieldUpdates hashtable (line ~270)
# 5. Add to $noteUpdates hashtable (line ~310)
# 6. Add to $noteFieldsToAdd hashtable (line ~360)
# 7. Add to $IntegrationServices array (line ~380)
# 8. Add case to calculated message switch (line ~400)
# 9. Update this documentation header
#
# =============================================================================

$VaultName = "hudu-pshell-learning"
#### Hudu Settings ####
# =============================================================================
# CREDENTIAL VALIDATION WITH RETRY LOGIC
# =============================================================================
# Validate Hudu credentials and allow 3 attempts before exiting
# This ensures the script fails gracefully with helpful error messages

$maxAttempts = 3
$attempt = 0
$credentialsValid = $false

Write-Host "Validating Hudu credentials..."

do {
    $attempt++
    Write-Host "Attempt $attempt of $maxAttempts..."
    
    try {
        # Get Hudu API Key and Base Domain from Azure Key Vault
$HuduAPIKey = Get-AzKeyVaultSecret -vaultName $VaultName -name "HuduAPIKey" -AsPlainText
$HuduBaseDomain = Get-AzKeyVaultSecret -vaultName $VaultName -name "HuduBaseDomain" -AsPlainText
        
        # Validate that we got non-empty values
        if ([string]::IsNullOrWhiteSpace($HuduAPIKey) -or [string]::IsNullOrWhiteSpace($HuduBaseDomain)) {
            throw "Empty credentials retrieved from Key Vault"
        }
        
        # Import HuduAPI module
        import-module HuduAPI
        
        # Test credentials by making a simple API call
        Write-Host "  Testing API connection..."
        $testResponse = Invoke-RestMethod -Uri "$HuduBaseDomain/api/v1/api_info" -Headers @{ "x-api-key" = $HuduAPIKey } -Method GET
        
        # If we get here, credentials are valid
        $credentialsValid = $true
        Write-Host "  ✓ Credentials validated successfully"
        
        # Initialize HuduAPI module
        New-HuduAPIKey $HuduAPIKey
        New-HuduBaseUrl $HuduBaseDomain
        Write-Host "  ✓ HuduAPI module initialized successfully"
        
    } catch {
        Write-Warning "  ✗ Credential validation failed: $_"
        
        if ($attempt -lt $maxAttempts) {
            Write-Host "  Please check your credentials, key vault name, secret names, etc. in Entra ID"
            Write-Host "  Retrying in 3 seconds..."
            Start-Sleep -Seconds 3
        } else {
            Write-Host ""
            Write-Host "============================================================================="
            Write-Host "CREDENTIAL VALIDATION FAILED"
            Write-Host "============================================================================="
            Write-Host "Your credentials, key vault name, secret names, etc. in Entra ID are incorrect."
            Write-Host "Please review them and try again."
            Write-Host ""
            Write-Host "Common issues to check:"
            Write-Host "  - Key Vault name: '$VaultName'"
            Write-Host "  - Secret names: 'HuduAPIKey' and 'HuduBaseDomain'"
            Write-Host "  - Entra ID permissions to access Key Vault"
            Write-Host "  - Hudu API key validity"
            Write-Host "  - Hudu base domain format (should not include trailing slash)"
            Write-Host ""
            Write-Host "Exiting script, please try again with correct credentials."
            Write-Host "============================================================================="
            exit 1
        }
    }
} while (-not $credentialsValid -and $attempt -lt $maxAttempts)

Write-Host "✓ Credential validation completed successfully"
Write-Host ""

# =============================================================================
# CUSTOM/AUTOMATION MODE DETECTION
# =============================================================================
# The script will check the Custom Fields:ENABLED field for each company to determine mode:
# - Custom Fields:ENABLED = True  → DELETE all Magic Dash tiles (custom mode)
# - Custom Fields:ENABLED = False → UPDATE existing tiles (automation mode)

Write-Host ""
Write-Host "============================================================================="
Write-Host "MAGIC DASH MODE DETECTION"
Write-Host "============================================================================="
Write-Host "Mode will be determined by Custom Fields:ENABLED field for each company:"
Write-Host "  - Custom Fields:ENABLED = True  → DELETE all Magic Dash tiles (custom mode)"
Write-Host "  - Custom Fields:ENABLED = False → UPDATE existing tiles (automation mode)"
Write-Host "============================================================================="
Write-Host ""

$DetailsLayoutName = 'Company Details'
$SplitChar = ':'

# Allowed field actions for asset layout parsing
$AllowedActions = @('ENABLED', 'NOTE', 'URL', 'DeviceCount', 'LocationCount', 'ContactCount', 'ConfigurationCount')

# Get the Asset Layout using direct API call
try {
    $AllLayouts = Invoke-RestMethod -Uri "$HuduBaseDomain/api/v1/asset_layouts" -Headers @{ "x-api-key" = $HuduAPIKey }
    Write-Host "=== AVAILABLE ASSET LAYOUTS ==="
    foreach ($layout in $AllLayouts.asset_layouts) {
        Write-Host "  Layout: '$($layout.name)' (ID: $($layout.id), Active: $($layout.active))"
    }
    Write-Host "============================="
    
    $DetailsLayout = $AllLayouts.asset_layouts | Where-Object { $_.name -eq $DetailsLayoutName }
} catch {
    Write-Error "Failed to get asset layouts: $_"
    exit 1
}

        # Check we found the layout
        if (($DetailsLayout | measure-object).count -ne 1) {
            Write-Error "No / multiple layout(s) found with name $DetailsLayoutName"
    Write-Host "Available layouts: $($AllLayouts.asset_layouts.name -join ', ')"
    Write-Host "Please check the exact name of your Company Details asset layout and update the script."
        } else {
            # Debug: Show all field labels in the asset layout
            Write-Host "=== ASSET LAYOUT FIELDS ==="
            foreach ($field in $DetailsLayout.asset_layout.fields) {
                Write-Host "  Field: '$($field.label)' (ID: $($field.id), Type: $($field.field_type))"
            }
            Write-Host "========================="
    
    # Get all the detail assets and loop using direct API call
    try {
        $DetailsAssets = Invoke-RestMethod -Uri "$HuduBaseDomain/api/v1/assets?asset_layout_id=$($DetailsLayout.id)" -Headers @{ "x-api-key" = $HuduAPIKey }
        Write-Host "Debug - API Response structure:"
        Write-Host "  Response type: $($DetailsAssets.GetType().Name)"
        if ($DetailsAssets.assets) {
            Write-Host "  Found $($DetailsAssets.assets.Count) assets"
            if ($DetailsAssets.assets.Count -gt 0) {
                Write-Host "  First asset properties: $($DetailsAssets.assets[0].PSObject.Properties.Name -join ', ')"
            }
        } else {
            Write-Host "  No 'assets' property found. Available properties: $($DetailsAssets.PSObject.Properties.Name -join ', ')"
        }
    } catch {
        Write-Error "Failed to get assets: $_"
        exit 1
    }
    
    # Handle different API response structures
    if ($DetailsAssets.assets) {
        $CompanyIds = $DetailsAssets.assets | Select-Object -ExpandProperty company_id -Unique
    } else {
    $CompanyIds = $DetailsAssets | Select-Object -ExpandProperty company_id -Unique
    }
    
    # =============================================================================
    # CUSTOM/AUTOMATION MODE DETECTION AND TILE MANAGEMENT
    # =============================================================================
    # This section will be handled per-company in the main processing loop
    # based on each company's Custom Fields:ENABLED setting

    # Check for companies with multiple Company Details assets
    $CompaniesWithMultipleAssets = @()
    $AssetsToProcess = if ($DetailsAssets.assets) { $DetailsAssets.assets } else { $DetailsAssets }
    
    foreach ($companyId in $CompanyIds) {
        $companyAssets = $AssetsToProcess | Where-Object { $_.company_id -eq $companyId }
        if ($companyAssets.Count -gt 1) {
            $CompaniesWithMultipleAssets += @{
                CompanyId = $companyId
                CompanyName = $companyAssets[0].company_name
                AssetCount = $companyAssets.Count
                AssetIds = $companyAssets.id
            }
        }
    }

    # Report companies with multiple assets
    if ($CompaniesWithMultipleAssets.Count -gt 0) {
        Write-Host "`n=== COMPANIES WITH MULTIPLE COMPANY DETAILS ASSETS ==="
        foreach ($company in $CompaniesWithMultipleAssets) {
            Write-Host "Company: $($company.CompanyName) (ID: $($company.CompanyId))"
            Write-Host "  Has $($company.AssetCount) Company Details assets (IDs: $($company.AssetIds -join ', '))"
            Write-Host "  ACTION REQUIRED: Delete $($company.AssetCount - 1) of these assets - this script requires exactly 1 Company Details asset per company"
        }
        Write-Host "=====================================================`n"
    }

    foreach ($companyId in $CompanyIds) {
        $companyAssets = $AssetsToProcess | Where-Object { $_.company_id -eq $companyId }
        
        # Skip companies with multiple Company Details assets
        if ($companyAssets.Count -gt 1) {
            Write-Host ">>> SKIPPING company: $($companyAssets[0].company_name) (ID: $companyId) - has $($companyAssets.Count) Company Details assets"
            continue
        }
        
        # Skip companies with no Company Details assets
        if ($companyAssets.Count -eq 0) {
            Write-Host ">>> SKIPPING company: ID $companyId - has 0 Company Details assets"
            continue
        }
        
        $Asset = $companyAssets[0]
        Write-Host ">>> Processing company: $($Asset.company_name) (ID: $companyId) - has exactly 1 Company Details asset"
        
        # Wrap entire company processing in error handling to prevent script failure
        try {

        # Loop through all the fields on the Asset
        Write-Host "  Debug - Asset fields found:"
        foreach ($field in $Asset.fields) {
            Write-Host "    Field: '$($field.label)' = '$($field.value)'"
        }
        
        $Fields = foreach ($field in $Asset.fields) {
            # Split the field name and trim spaces
            $SplitField = ($Field.label.Trim()) -split $SplitChar

            # Check if field has a valid format and allowed action
            if ($SplitField.Count -ge 2 -and $SplitField[1].Trim() -in $AllowedActions) {
                # Format an object to work with
                $parsedField = [PSCustomObject]@{
                    ServiceName   = $SplitField[0].Trim()
                    ServiceAction = $SplitField[1].Trim()
                    Value         = $field.value
                    Label         = $field.label.Trim()
                }
                Write-Host "    Parsed field: $($parsedField.ServiceName):$($parsedField.ServiceAction) = '$($parsedField.Value)'"
                $parsedField
            }
        }

        # Check if we should include archived assets (gracefully handle missing field)
        try {
        $IncludeArchived = $Fields | Where-Object { $_.Label -eq "IncludeArchivedAssets:ENABLED" }
            $IncludeArchivedFlag = $IncludeArchived -and ($IncludeArchived.Value -eq $true -or $IncludeArchived.Value -eq "True" -or $IncludeArchived.Value -eq "true")
        } catch {
            Write-Host "  Warning: IncludeArchivedAssets:ENABLED field not found, defaulting to exclude archived assets"
            $IncludeArchivedFlag = $false
        }
        
        # Debug: Show archived flag status
        Write-Host "  Debug - IncludeArchivedAssets:ENABLED = $($IncludeArchived.Value), IncludeArchivedFlag = $IncludeArchivedFlag"

        # =============================================================================
        # CUSTOM/AUTOMATION MODE DETECTION FOR THIS COMPANY
        # =============================================================================
        # Check Custom Fields:ENABLED to determine if we should delete all tiles or update them
        try {
            $CustomFieldsEnabled = $Fields | Where-Object { $_.ServiceName -eq "Custom Fields" -and $_.ServiceAction -eq 'ENABLED' }
            $isCustomMode = $CustomFieldsEnabled -and ($CustomFieldsEnabled.value -eq $true -or $CustomFieldsEnabled.value -eq "True" -or $CustomFieldsEnabled.value -eq "true")
        } catch {
            Write-Host "  Warning: Custom Fields:ENABLED field not found, defaulting to automation mode"
            $isCustomMode = $false
        }
        
        if ($isCustomMode) {
            Write-Host "  Custom Fields:ENABLED = True → DELETING all Magic Dash tiles, then creating new ones (custom mode)"
            
            # Delete all existing Magic Dash tiles for this company
            try {
                $existingTilesResponse = Invoke-RestMethod -Uri "$HuduBaseDomain/api/v1/magic_dash?company_id=$companyId" -Headers @{ "x-api-key" = $HuduAPIKey }
                $existingTiles = if ($existingTilesResponse.magic_dash) { $existingTilesResponse.magic_dash } else { $existingTilesResponse }
                
                if ($existingTiles -and $existingTiles.Count -gt 0) {
                    # Only delete tiles created by this script (pattern: "Company Name - Service Name")
                    $scriptTiles = $existingTiles | Where-Object { $_.title -match "^$([regex]::Escape($Asset.company_name)) - (HaloPSA|DattoRMM|CW Manage|AutoTask|Atera|Addigy|Syncro|NinjaOne|Domotz|N-Central|PulsewayRMM)$" }
                    
                    if ($scriptTiles -and $scriptTiles.Count -gt 0) {
                        Write-Host "    Deleting $($scriptTiles.Count) script-created tiles for $($Asset.company_name)"
                        foreach ($tile in $scriptTiles) {
                            try {
                                $deleteBody = "title=$([System.Web.HttpUtility]::UrlEncode($tile.title))&company_name=$([System.Web.HttpUtility]::UrlEncode($Asset.company_name))"
                                Invoke-RestMethod -Uri "$HuduBaseDomain/api/v1/magic_dash" -Method DELETE -Headers @{ "x-api-key" = $HuduAPIKey; "Content-Type" = "application/x-www-form-urlencoded" } -Body $deleteBody
                                Write-Host "      Deleted: $($tile.title)"
                            } catch {
                                Write-Warning "      Failed to delete tile $($tile.title): $_"
                            }
                        }
                    }
                }
                Write-Host "  ✓ All Magic Dash tiles deleted for $($Asset.company_name)"
            } catch {
                Write-Warning "  Failed to delete Magic Dash tiles for $($Asset.company_name): $_"
            }
            
            # Continue with normal processing to create new tiles
            Write-Host "  Now creating new Magic Dash tiles for $($Asset.company_name) (custom mode)"
        } else {
            Write-Host "  Custom Fields:ENABLED = False → UPDATING existing tiles (automation mode)"
        }

        # Pull all assets for this company
        try {
            $allAssets = Invoke-RestMethod -Uri "$HuduBaseDomain/api/v1/assets?company_id=$companyId" -Headers @{ "x-api-key" = $HuduAPIKey }
        } catch {
            Write-Warning "Failed to pull assets for $($Asset.company_name): $_"
            continue
        }

        # Count assets for each integration using correct integrator names and archived logic
        # =============================================================================
        # INTEGRATION ASSET COUNTING SECTION
        # =============================================================================
        # This section counts assets for each supported integration.
        # Each integration follows the same pattern:
        # 1. Filter by integrator_name (e.g., "halo", "dattormm", etc.)
        # 2. Filter by sync_type (e.g., "device", "contact", "site", "configuration")
        # 3. Respect archived status based on IncludeArchivedAssets:ENABLED flag
        # 4. Count matching assets
        #
        # TO ADD NEW INTEGRATION: Copy an existing integration block and modify:
        # - Change integrator_name to your service name
        # - Adjust sync_type values as needed
        # - Update variable names to match your service
        # =============================================================================

        # HaloPSA Integration - Devices, Locations, Contacts
        # integrator_name: "halo", sync_types: "asset", "site", "contact"
        # Count HaloPSA assets that have the appropriate cards
        $HaloDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "halo" -and $_.sync_type -eq "asset" }))
        }
        $HaloLocations = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "halo" -and $_.sync_type -eq "site" }))
        }
        $HaloContacts = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "halo" -and $_.sync_type -eq "contact" }))
        }

        # DattoRMM Integration - Devices only
        # integrator_name: "dattormm", sync_type: "device"
        # Count DattoRMM assets that have device cards
        $DattoDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "dattormm" -and $_.sync_type -eq "device" }))
        }

        # Debug: Show detailed DattoRMM counting
        Write-Host "  Debug - DattoRMM counting details:"
        Write-Host "    Total assets for company: $($allAssets.assets.Count)"
        Write-Host "    Assets with DattoRMM device cards: $($DattoDevices.Count)"
        if ($DattoDevices.Count -gt 0) {
            Write-Host "    DattoRMM device asset names: $($DattoDevices.name -join ', ')"
        }

        # CW Manage Integration - Configurations, Locations, Contacts
        # integrator_name: "cw_manage", sync_types: "configuration", "site", "contact"
        # Count CW Manage assets that have the appropriate cards
        $CWConfigurations = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "cw_manage" -and $_.sync_type -eq "configuration" }))
        }
        $CWLocations = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "cw_manage" -and $_.sync_type -eq "site" }))
        }
        $CWContacts = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "cw_manage" -and $_.sync_type -eq "contact" }))
        }

        # AutoTask Integration - Devices, Locations, Contacts
        # integrator_name: "autotask", sync_types: "configuration", "site", "contact"
        # Count AutoTask assets that have the appropriate cards
        $AutoTaskDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "autotask" -and $_.sync_type -eq "configuration" }))
        }
        $AutoTaskLocations = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "autotask" -and $_.sync_type -eq "site" }))
        }
        $AutoTaskContacts = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "autotask" -and $_.sync_type -eq "contact" }))
        }

        # Atera Integration - Devices, Contacts
        # integrator_name: "atera", sync_types: "device", "contact"
        # Count Atera assets that have the appropriate cards
        $AteraDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "atera" -and $_.sync_type -eq "device" }))
        }
        $AteraContacts = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "atera" -and $_.sync_type -eq "contact" }))
        }

        # Addigy Integration - Devices only
        # integrator_name: "addigy", sync_type: "device"
        # Count Addigy assets that have device cards
        $AddigyDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "addigy" -and $_.sync_type -eq "device" }))
        }

        # Syncro Integration - Devices, Contacts
        # integrator_name: "syncro", sync_types: "asset", "contact"
        # Count Syncro assets that have the appropriate cards
        $SyncroDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "syncro" -and $_.sync_type -eq "asset" }))
        }
        $SyncroContacts = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "syncro" -and $_.sync_type -eq "contact" }))
        }

        # NinjaOne Integration - Devices, Locations
        # integrator_name: "ninja", sync_types: "device", "location"
        # Count NinjaOne assets that have the appropriate cards
        $NinjaOneDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "ninja" -and $_.sync_type -eq "device" }))
        }
        $NinjaOneLocations = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "ninja" -and $_.sync_type -eq "location" }))
        }

        # Domotz Integration - Assets only
        # integrator_name: "domotz", sync_types: "asset"
        # Count Domotz assets that have asset cards
        $DomotzAssets = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "domotz" -and $_.sync_type -eq "asset" }))
        }

        # N-Central Integration - Devices, Locations
        # integrator_name: "ncentral", sync_types: "device", "location"
        # Count N-Central assets that have the appropriate cards
        $NCentralDevices = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "ncentral" -and $_.sync_type -eq "device" }))
        }
        $NCentralLocations = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "ncentral" -and $_.sync_type -eq "location" }))
        }
        
        # PulsewayRMM Integration - Assets only
        # integrator_name: "pulseway_rmm", sync_type: "asset"
        # Count PulsewayRMM assets that have asset cards
        $PulsewayRMMAssets = $allAssets.assets | Where-Object {
            ($IncludeArchivedFlag -or -not $_.archived) -and
            ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "pulseway_rmm" -and $_.sync_type -eq "asset" }))
        }

        # Debug: Show integrator names for our 11 integrations only
        $ourIntegrators = @("halo", "dattormm", "cw_manage", "autotask", "atera", "addigy", "syncro", "ninja", "domotz", "ncentral", "pulseway_rmm")
        $foundIntegrators = $allAssets.assets | Where-Object { $_.cards } | ForEach-Object { $_.cards } | Where-Object { $_.integrator_name -in $ourIntegrators } | Select-Object -ExpandProperty integrator_name -Unique
        Write-Host "  Debug - Found our integrators: $($foundIntegrators -join ', ')"
        
        # Debug: Show counts for each of our integrations
        foreach ($integrator in $ourIntegrators) {
            $cards = $allAssets.assets | Where-Object { $_.cards } | ForEach-Object { $_.cards } | Where-Object { $_.integrator_name -eq $integrator }
            if ($cards.Count -gt 0) {
                $syncTypes = $cards | Select-Object -ExpandProperty sync_type -Unique
                Write-Host "  Debug - $integrator`: $($cards.Count) cards, sync types: $($syncTypes -join ', ')"
                
                # Show detailed breakdown for each sync type
                foreach ($syncType in $syncTypes) {
                    $count = ($cards | Where-Object { $_.sync_type -eq $syncType }).Count
                    Write-Host "    - $syncType`: $count assets"
                }
            } else {
                Write-Host "  Debug - $integrator`: 0 cards found"
            }
        }

        Write-Host "  [HaloPSA] Devices: $($HaloDevices.Count) | Locations: $($HaloLocations.Count) | Contacts: $($HaloContacts.Count)"
        
        # Debug: Show what count field values are being set for Magic Dash
        Write-Host "  Debug - Integration count field values for Magic Dash:"
        Write-Host "    HaloPSA:DeviceCount = $($HaloDevices.Count) (assets)"
        Write-Host "    HaloPSA:LocationCount = $($HaloLocations.Count) (assets)"
        Write-Host "    HaloPSA:ContactCount = $($HaloContacts.Count) (assets)"
        Write-Host "    DattoRMM:DeviceCount = $($DattoDevices.Count) (assets)"
        Write-Host "    CW Manage:ConfigurationCount = $($CWConfigurations.Count) (assets)"
        Write-Host "    CW Manage:LocationCount = $($CWLocations.Count) (assets)"
        Write-Host "    CW Manage:ContactCount = $($CWContacts.Count) (assets)"
        Write-Host "    AutoTask:DeviceCount = $($AutoTaskDevices.Count) (assets)"
        Write-Host "    AutoTask:LocationCount = $($AutoTaskLocations.Count) (assets)"
        Write-Host "    AutoTask:ContactCount = $($AutoTaskContacts.Count) (assets)"
        Write-Host "    Atera:DeviceCount = $($AteraDevices.Count) (assets)"
        Write-Host "    Atera:ContactCount = $($AteraContacts.Count) (assets)"
        Write-Host "    Addigy:DeviceCount = $($AddigyDevices.Count) (assets)"
        Write-Host "    Syncro:DeviceCount = $($SyncroDevices.Count) (assets)"
        Write-Host "    Syncro:ContactCount = $($SyncroContacts.Count) (assets)"
        Write-Host "    NinjaOne:DeviceCount = $($NinjaOneDevices.Count) (assets)"
        Write-Host "    NinjaOne:LocationCount = $($NinjaOneLocations.Count) (assets)"
        Write-Host "    Domotz:AssetCount = $($DomotzAssets.Count) (assets)"
        Write-Host "    N-Central:DeviceCount = $($NCentralDevices.Count) (assets)"
        Write-Host "    N-Central:LocationCount = $($NCentralLocations.Count) (assets)"
        Write-Host "    PulsewayRMM:AssetCount = $($PulsewayRMMAssets.Count) (assets)"
        Write-Host "  [DattoRMM] Devices: $($DattoDevices.Count)"
        Write-Host "  [CW Manage] Configurations: $($CWConfigurations.Count) | Locations: $($CWLocations.Count) | Contacts: $($CWContacts.Count)"
        Write-Host "  [AutoTask] Devices: $($AutoTaskDevices.Count) | Locations: $($AutoTaskLocations.Count) | Contacts: $($AutoTaskContacts.Count)"
        Write-Host "  [Atera] Devices: $($AteraDevices.Count) | Contacts: $($AteraContacts.Count)"
        Write-Host "  [Addigy] Devices: $($AddigyDevices.Count)"
        Write-Host "  [Syncro] Devices: $($SyncroDevices.Count) | Contacts: $($SyncroContacts.Count)"
        Write-Host "  [NinjaOne] Devices: $($NinjaOneDevices.Count) | Locations: $($NinjaOneLocations.Count)"
        Write-Host "  [Domotz] Assets: $($DomotzAssets.Count)"
        Write-Host "  [N-Central] Devices: $($NCentralDevices.Count) | Locations: $($NCentralLocations.Count)"
        Write-Host "  [PulsewayRMM] Assets: $($PulsewayRMMAssets.Count)"
        
        # Debug: Show count field values that will be used for Magic Dash
        Write-Host "  Debug - Count field values for Magic Dash:"
        Write-Host "    HaloPSA: DeviceCount=$($HaloDevices.Count), LocationCount=$($HaloLocations.Count), ContactCount=$($HaloContacts.Count)"
        Write-Host "    DattoRMM: DeviceCount=$($DattoDevices.Count)"
        Write-Host "    CW Manage: DeviceCount=$($CWConfigurations.Count), LocationCount=$($CWLocations.Count), ContactCount=$($CWContacts.Count)"
        Write-Host "    AutoTask: DeviceCount=$($AutoTaskDevices.Count), LocationCount=$($AutoTaskLocations.Count), ContactCount=$($AutoTaskContacts.Count)"
        Write-Host "    Atera: DeviceCount=$($AteraDevices.Count), ContactCount=$($AteraContacts.Count)"
        Write-Host "    Addigy: DeviceCount=$($AddigyDevices.Count)"
        Write-Host "    Syncro: DeviceCount=$($SyncroDevices.Count), ContactCount=$($SyncroContacts.Count)"
        Write-Host "    NinjaOne: DeviceCount=$($NinjaOneDevices.Count), LocationCount=$($NinjaOneLocations.Count)"
        Write-Host "    Domotz: AssetCount=$($DomotzAssets.Count)"
        Write-Host "    N-Central: DeviceCount=$($NCentralDevices.Count), LocationCount=$($NCentralLocations.Count)"
        Write-Host "    PulsewayRMM: AssetCount=$($PulsewayRMMAssets.Count)"

        # Update the Company Details asset with the calculated counts
        Write-Host "  Updating asset fields with counts..."
        try {
            $fieldsToSend = @()
            
            # Update count fields
            $fieldUpdates = @{
                "HaloPSA:DeviceCount"          = $HaloDevices.Count
                "HaloPSA:LocationCount"        = $HaloLocations.Count
                "HaloPSA:ContactCount"         = $HaloContacts.Count
                "DattoRMM:DeviceCount"         = $DattoDevices.Count
                "CW Manage:ConfigurationCount" = $CWConfigurations.Count
                "CW Manage:LocationCount"      = $CWLocations.Count
                "CW Manage:ContactCount"       = $CWContacts.Count
                "AutoTask:DeviceCount"         = $AutoTaskDevices.Count
                "AutoTask:LocationCount"       = $AutoTaskLocations.Count
                "AutoTask:ContactCount"        = $AutoTaskContacts.Count
                "Atera:DeviceCount"            = $AteraDevices.Count
                "Atera:ContactCount"           = $AteraContacts.Count
                "Addigy:DeviceCount"           = $AddigyDevices.Count
                "Syncro:DeviceCount"           = $SyncroDevices.Count
                "Syncro:ContactCount"          = $SyncroContacts.Count
                "NinjaOne:DeviceCount"         = $NinjaOneDevices.Count
                "NinjaOne:LocationCount"       = $NinjaOneLocations.Count
                "Domotz:AssetCount"            = $DomotzAssets.Count
                "N-Central:DeviceCount"        = $NCentralDevices.Count
                "N-Central:LocationCount"      = $NCentralLocations.Count
                "PulsewayRMM:AssetCount"       = $PulsewayRMMAssets.Count
            }

            # Add count fields
            foreach ($fieldName in $fieldUpdates.Keys) {
                $layoutField = $DetailsLayout.asset_layout.fields | Where-Object { $_.label -eq $fieldName }
                if ($layoutField) {
                    $fieldsToSend += @{
                        asset_layout_field_id = $layoutField.id
                        value = $fieldUpdates[$fieldName]
                    }
                }
            }

            if ($fieldsToSend.Count -gt 0) {
                $updateBody = @{ asset = @{ fields = $fieldsToSend } } | ConvertTo-Json -Depth 5
                Invoke-RestMethod -Uri "$HuduBaseDomain/api/v1/companies/$companyId/assets/$($Asset.id)" -Method PUT -Headers @{ "x-api-key" = $HuduAPIKey; "Content-Type" = "application/json" } -Body $updateBody
                Write-Host "  Updated $($fieldsToSend.Count) count fields"
            }
        } catch {
            Write-Warning "  Failed to update count fields: $_"
        }

        # NOTE: NOTE fields are now available for user customization
        # The script no longer populates NOTE fields automatically
        # Users can fill NOTE fields with custom messages to override automation

        # Update the Fields array with the new count values for Magic Dash creation
        $UpdatedFields = $Fields
        
        # Add count field values to UpdatedFields for Magic Dash creation
        $countFieldUpdates = @{
            "HaloPSA:DeviceCount"          = $HaloDevices.Count
            "HaloPSA:LocationCount"        = $HaloLocations.Count
            "HaloPSA:ContactCount"         = $HaloContacts.Count
            "DattoRMM:DeviceCount"         = $DattoDevices.Count
            "CW Manage:ConfigurationCount" = $CWConfigurations.Count
            "CW Manage:LocationCount"      = $CWLocations.Count
            "CW Manage:ContactCount"       = $CWContacts.Count
            "AutoTask:DeviceCount"         = $AutoTaskDevices.Count
            "AutoTask:LocationCount"       = $AutoTaskLocations.Count
            "AutoTask:ContactCount"        = $AutoTaskContacts.Count
            "Atera:DeviceCount"            = $AteraDevices.Count
            "Atera:ContactCount"           = $AteraContacts.Count
            "Addigy:DeviceCount"           = $AddigyDevices.Count
            "Syncro:DeviceCount"           = $SyncroDevices.Count
            "Syncro:ContactCount"          = $SyncroContacts.Count
            "NinjaOne:DeviceCount"         = $NinjaOneDevices.Count
            "NinjaOne:LocationCount"       = $NinjaOneLocations.Count
            "Domotz:AssetCount"            = $DomotzAssets.Count
            "N-Central:DeviceCount"        = $NCentralDevices.Count
            "N-Central:LocationCount"      = $NCentralLocations.Count
            "PulsewayRMM:AssetCount"       = $PulsewayRMMAssets.Count
        }
        
        # Update existing fields or add new ones
        foreach ($fieldName in $countFieldUpdates.Keys) {
            $existingField = $UpdatedFields | Where-Object { $_.Label -eq $fieldName }
            if ($existingField) {
                $existingField.Value = $countFieldUpdates[$fieldName]
            } else {
                $UpdatedFields += [PSCustomObject]@{
                    ServiceName   = $fieldName.Split(':')[0]
                    ServiceAction = $fieldName.Split(':')[1]
                    Value         = $countFieldUpdates[$fieldName]
                    Label         = $fieldName
                }
            }
        }

        # =============================================================================
        # MAGIC DASH CREATION LOGIC - DO NOT MODIFY WITHOUT UNDERSTANDING
        # =============================================================================
        # 
        # ⚠️  CRITICAL: This section creates Magic Dash tiles in Hudu.
        # ⚠️  DO NOT modify this logic unless you fully understand the implications.
        # ⚠️  Changes here can break Magic Dash functionality for all companies.
        #
        # HOW IT WORKS:
        # 1. Loops through each enabled integration service
        # 2. Checks if the service is enabled (ServiceName:ENABLED = true)
        # 3. Creates Magic Dash tile with:
        #    - Title: "Company Name - Service Name"
        #    - Message: Asset counts or custom NOTE field value
        #    - URL: Custom URL if provided
        #    - Shade: Always "success" (green) for enabled services
        #
        # INTEGRATION SERVICES ARRAY:
        # This array controls which services get Magic Dash tiles created.
        # To add a new service, add it to this array AND follow the integration template.
        # =============================================================================

        # Only create Magic Dash tiles for actual integrations, not IncludeArchivedAssets
        $IntegrationServices = @("HaloPSA", "DattoRMM", "CW Manage", "AutoTask", "Atera", "Addigy", "Syncro", "NinjaOne", "Domotz", "N-Central", "PulsewayRMM")
        
        # =============================================================================
        # MAGIC DASH TILE CREATION LOOP - CRITICAL SECTION
        # =============================================================================
        # This loop creates Magic Dash tiles for each enabled integration.
        # Each iteration:
        # 1. Finds the ENABLED, NOTE, and URL fields for the service
        # 2. Checks if service is enabled (ENABLED field = true)
        # 3. Creates Magic Dash tile with appropriate message and URL
        # 4. Uses Hudu API to create the tile
        #
        # ⚠️  DO NOT MODIFY THE CORE LOGIC BELOW ⚠️
        # ⚠️  Only add new services by following the integration template ⚠️
        # =============================================================================
        
        Foreach ($Service in $IntegrationServices){
            try {
                # Safely get fields with error handling
                $EnabledField = $UpdatedFields | Where-Object {$_.ServiceName -eq $Service -and $_.ServiceAction -eq 'ENABLED'}
                $NoteField = $UpdatedFields | Where-Object {$_.ServiceName -eq $Service -and $_.ServiceAction -eq 'NOTE'}
                $URLField = $UpdatedFields | Where-Object {$_.ServiceName -eq $Service -and $_.ServiceAction -eq 'URL'}
                
                # Get count fields for this service (gracefully handle missing fields)
                $DeviceCountField = $UpdatedFields | Where-Object {$_.ServiceName -eq $Service -and $_.ServiceAction -eq 'DeviceCount'}
                $LocationCountField = $UpdatedFields | Where-Object {$_.ServiceName -eq $Service -and $_.ServiceAction -eq 'LocationCount'}
                $ContactCountField = $UpdatedFields | Where-Object {$_.ServiceName -eq $Service -and $_.ServiceAction -eq 'ContactCount'}
                $AssetCountField = $UpdatedFields | Where-Object {$_.ServiceName -eq $Service -and $_.ServiceAction -eq 'AssetCount'}
                
                # Check for Custom Fields override (gracefully handle missing field)
                $CustomFieldsEnabled = $UpdatedFields | Where-Object {$_.ServiceName -eq "Custom Fields" -and $_.ServiceAction -eq 'ENABLED'}
                
                Write-Host "  Debug - $Service`: Enabled=$($EnabledField.value), Note='$($NoteField.value)', URL='$($URLField.value)'"
                Write-Host "    Count Fields - Device: $($DeviceCountField.value), Location: $($LocationCountField.value), Contact: $($ContactCountField.value), Asset: $($AssetCountField.value)"
                Write-Host "    Custom Fields Override: $($CustomFieldsEnabled.value)"
                
                # Debug: Show what values are being used for HaloPSA specifically
                if ($Service -eq "HaloPSA") {
                    Write-Host "    HaloPSA Debug - DeviceCountField exists: $($DeviceCountField -ne $null)"
                    Write-Host "    HaloPSA Debug - LocationCountField exists: $($LocationCountField -ne $null)"
                    Write-Host "    HaloPSA Debug - ContactCountField exists: $($ContactCountField -ne $null)"
                    if ($DeviceCountField) { Write-Host "    HaloPSA Debug - DeviceCountField value: '$($DeviceCountField.value)'" }
                    if ($LocationCountField) { Write-Host "    HaloPSA Debug - LocationCountField value: '$($LocationCountField.value)'" }
                    if ($ContactCountField) { Write-Host "    HaloPSA Debug - ContactCountField value: '$($ContactCountField.value)'" }
                }
                
                # Show missing fields for debugging (non-critical)
                if (-not $EnabledField) {
                    Write-Host "    INFO: $Service`:ENABLED field not found in Asset Layout - skipping this service"
                    continue
                }
            } catch {
                Write-Warning "  Error processing fields for $Service`: $_ - skipping this service"
                continue
            }
            
            # =============================================================================
            # ENABLED SERVICE CHECK - CRITICAL LOGIC
            # =============================================================================
            # This check determines if a Magic Dash tile should be created.
            # Only creates tiles for services where ENABLED field = true.
            # ⚠️  DO NOT MODIFY THIS LOGIC - IT CONTROLS TILE CREATION ⚠️
            # =============================================================================
            
            if ($EnabledField -and ($EnabledField.value -eq $true -or $EnabledField.value -eq "True" -or $EnabledField.value -eq "true")){
                $Colour = 'success'
                
                $DashTitle = "$($Asset.company_name) - $Service"
                
                $Param = @{
                    Title = $DashTitle
                    CompanyName = $Asset.company_name
                    Shade = $Colour
                }
                
                # =============================================================================
                # MESSAGE GENERATION LOGIC - CRITICAL SECTION
                # =============================================================================
                # This section determines what message appears on the Magic Dash tile.
                # Priority: Custom NOTE field value > Calculated counts > Default message
                # 
                # ⚠️  CRITICAL: This logic ensures Magic Dash tiles always show meaningful data
                # ⚠️  DO NOT modify the core message generation without understanding the impact
                # ⚠️  Changes here affect what users see on their Magic Dash tiles
                # =============================================================================
                
                # Check if Custom Fields override is enabled
                if ($CustomFieldsEnabled -and ($CustomFieldsEnabled.value -eq $true -or $CustomFieldsEnabled.value -eq "True" -or $CustomFieldsEnabled.value -eq "true") -and $NoteField.value -and $NoteField.value.Trim() -ne ""){
                    # Custom Fields override enabled AND NOTE field has content - use custom message
                    $Param['Message'] = $NoteField.value
                    $Param | Add-Member -MemberType NoteProperty -Name 'Message' -Value $NoteField.value
                    Write-Host "    Using custom NOTE field value (Custom Fields override): '$($NoteField.value)'"
                } else {
                    # Custom Fields override disabled OR NOTE field empty - use automation logic (count fields)
                    # =============================================================================
                    # CALCULATED MESSAGE SWITCH - CRITICAL LOGIC
                    # =============================================================================
                    # This switch generates messages based on count field values from automation.
                    # Each service has its own message format based on available asset types.
                    # 
                    # ⚠️  TO ADD NEW SERVICE: Add case to this switch following the pattern
                    # ⚠️  DO NOT modify existing cases without understanding the impact
                    # ⚠️  Message format: "Assets: X | Locations: Y | Contacts: Z"
                    # =============================================================================
                    
                    $calculatedMessage = switch ($Service) {
                        "HaloPSA" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            $locationCount = if ($LocationCountField.value) { $LocationCountField.value } else { "0" }
                            $contactCount = if ($ContactCountField.value) { $ContactCountField.value } else { "0" }
                            "Assets: $deviceCount | Locations: $locationCount | Contacts: $contactCount"
                        }
                        "DattoRMM" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            "Assets: $deviceCount"
                        }
                        "CW Manage" { 
                            $configCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            $locationCount = if ($LocationCountField.value) { $LocationCountField.value } else { "0" }
                            $contactCount = if ($ContactCountField.value) { $ContactCountField.value } else { "0" }
                            "Assets: $configCount | Locations: $locationCount | Contacts: $contactCount"
                        }
                        "AutoTask" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            $locationCount = if ($LocationCountField.value) { $LocationCountField.value } else { "0" }
                            $contactCount = if ($ContactCountField.value) { $ContactCountField.value } else { "0" }
                            "Assets: $deviceCount | Locations: $locationCount | Contacts: $contactCount"
                        }
                        "Atera" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            $contactCount = if ($ContactCountField.value) { $ContactCountField.value } else { "0" }
                            "Assets: $deviceCount | Contacts: $contactCount"
                        }
                        "Addigy" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            "Assets: $deviceCount"
                        }
                        "Syncro" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            $contactCount = if ($ContactCountField.value) { $ContactCountField.value } else { "0" }
                            "Assets: $deviceCount | Contacts: $contactCount"
                        }
                        "NinjaOne" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            $locationCount = if ($LocationCountField.value) { $LocationCountField.value } else { "0" }
                            "Assets: $deviceCount | Locations: $locationCount"
                        }
                        "Domotz" { 
                            $assetCount = if ($AssetCountField.value) { $AssetCountField.value } else { "0" }
                            "Assets: $assetCount"
                        }
                        "N-Central" { 
                            $deviceCount = if ($DeviceCountField.value) { $DeviceCountField.value } else { "0" }
                            $locationCount = if ($LocationCountField.value) { $LocationCountField.value } else { "0" }
                            "Assets: $deviceCount | Locations: $locationCount"
                        }
                        "PulsewayRMM" { 
                            $assetCount = if ($AssetCountField.value) { $AssetCountField.value } else { "0" }
                            "Assets: $assetCount"
                        }
                        default { "Customer has $Service" }
                    }
                    $Param['Message'] = $calculatedMessage
                    Write-Host "    Using automation logic (count fields): '$calculatedMessage'"
                }

                if ($URLField.value){
                    $Param['ContentLink'] = $URLField.value
                }
                
                # =============================================================================
                # MAGIC DASH API CREATION - CRITICAL SECTION
                # =============================================================================
                # This section makes the actual API call to create the Magic Dash tile in Hudu.
                # 
                # CRITICAL: This is the actual Magic Dash creation - DO NOT MODIFY
                # Changes here can break Magic Dash functionality entirely
                # The API call structure is specific to Hudu's Magic Dash endpoint
                # 
                # API ENDPOINT: POST /api/v1/magic_dash
                # REQUIRED FIELDS: title, company_name, shade, message
                # OPTIONAL FIELDS: content_link (URL)
                # =============================================================================
                
                try {
                    # Create Magic Dash tile using HuduAPI module
                    Set-HuduMagicDash @Param
                    Write-Host "  Created Magic Dash tile for $Service"
                } catch {
                    Write-Warning "  Failed to create Magic Dash tile for $Service`: $_"
                    # Continue processing other services even if one fails
                    continue
                }
            } else {
                Write-Host "  Skipping $Service - not enabled or no enabled field found"
            }
        }
        
        # =============================================================================
        # END OF MAGIC DASH CREATION LOGIC
        # =============================================================================
        # 
        # CRITICAL: The Magic Dash creation logic ends here.
        # All code above this point is responsible for creating Magic Dash tiles.
        # DO NOT modify the Magic Dash logic without fully understanding the impact.
        # 
        # WHAT HAPPENS NEXT:
        # - Script continues to next company
        # - Magic Dash tiles are now created in Hudu
        # - Users can see asset counts on their Magic Dash
        # =============================================================================

        } catch {
            Write-Warning "  Error processing company $($Asset.company_name) (ID: $companyId): $_"
            Write-Host "  Continuing with next company..."
            # Continue to next company even if this one fails
        }

    }

    Write-Host "`n=== SUMMARY ==="
    $processedCount = 0
    $skippedCount = 0
    
    foreach ($companyId in $CompanyIds) {
        $companyAssets = $AssetsToProcess | Where-Object { $_.company_id -eq $companyId }
        if ($companyAssets.Count -eq 1) {
            $processedCount++
        } elseif ($companyAssets.Count -gt 1) {
            $skippedCount++
        }
    }
    
    Write-Host "Total companies with Company Details assets: $($CompanyIds.Count)"
    Write-Host "Companies processed (exactly 1 asset): $processedCount"
    Write-Host "Companies skipped (multiple assets): $skippedCount"
    Write-Host "Script completed successfully"

# =============================================================================
# INTEGRATION TEMPLATE FOR FUTURE ADDITIONS
# =============================================================================
#
# CRITICAL WARNING: MAGIC DASH LOGIC PROTECTION
# 
# This script contains protected Magic Dash creation logic (lines ~440-600).
# The Magic Dash logic is marked with CRITICAL warnings and should NOT be modified
# unless you fully understand the implications. Changes to this logic can break
# Magic Dash functionality for all companies.
#
# To add a new integration to this script, follow these exact steps:
#
# 1. ADD COUNTING LOGIC (after line ~280):
#    # NewService Integration - [Device Types]
#    # integrator_name: "newservice", sync_types: "device", "contact", etc.
#    $NewServiceDevices = $allAssets.assets | Where-Object {
#        ($IncludeArchivedFlag -or -not $_.archived) -and
#        ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "newservice" -and $_.sync_type -eq "device" }))
#    }
#    $NewServiceContacts = $allAssets.assets | Where-Object {
#        ($IncludeArchivedFlag -or -not $_.archived) -and
#        ($_.cards -and ($_.cards | Where-Object { $_.integrator_name -eq "newservice" -and $_.sync_type -eq "contact" }))
#    }
#
# 2. ADD TO INTEGRATOR LIST (line ~290):
#    $ourIntegrators = @("halo", "dattormm", "cw_manage", "autotask", "atera", "addigy", "syncro", "ninja", "domotz", "ncentral", "newservice")
#
# 3. ADD TO DEBUG OUTPUT (line ~320):
#    Write-Host "  [NewService] Devices: $($NewServiceDevices.Count) | Contacts: $($NewServiceContacts.Count)"
#
# 4. ADD TO NOTE FIELD DEBUG (line ~330):
#    Write-Host "    NewService:NOTE = 'Assets: $($NewServiceDevices.Count) | Contacts: $($NewServiceContacts.Count)'"
#
# 5. ADD TO FIELD UPDATES (line ~350):
#    "NewService:DeviceCount" = $NewServiceDevices.Count
#    "NewService:ContactCount" = $NewServiceContacts.Count
#
# 6. ADD TO NOTE UPDATES (line ~380):
#    "NewService:NOTE" = "Assets: $($NewServiceDevices.Count) | Contacts: $($NewServiceContacts.Count)"
#
# 7. ADD TO NOTE FIELDS TO ADD (line ~430):
#    "NewService:NOTE" = "Assets: $($NewServiceDevices.Count) | Contacts: $($NewServiceContacts.Count)"
#
# 8. ADD TO INTEGRATION SERVICES (line ~450):
#    $IntegrationServices = @("HaloPSA", "DattoRMM", "CW Manage", "AutoTask", "Atera", "Addigy", "Syncro", "NinjaOne", "Domotz", "N-Central", "NewService")
#
# 9. ADD TO CALCULATED MESSAGE SWITCH (line ~540):
#    "NewService" { "Assets: $($NewServiceDevices.Count) | Contacts: $($NewServiceContacts.Count)" }
#    ⚠️  CRITICAL: This is inside the Magic Dash creation logic - be very careful!
#
# 10. UPDATE DOCUMENTATION HEADER (line ~15):
#    Add your integration to the SUPPORTED INTEGRATIONS list
#
# 11. UPDATE ASSET LAYOUT REQUIREMENTS:
#    Add the required fields to your "Company Details" asset layout:
#    - NewService:ENABLED (Checkbox)
#    - NewService:NOTE (Text)
#    - NewService:URL (Text)
#    - NewService:DeviceCount (Text)
#    - NewService:ContactCount (Text) [if applicable]
#
# INTEGRATION PATTERNS BY TYPE:
# - Device-only: DattoRMM, Addigy, Domotz
# - Device + Contact: Atera, Syncro
# - Device + Location + Contact: HaloPSA, AutoTask
# - Device + Location: NinjaOne, N-Central
# - Configuration + Location + Contact: CW Manage
#
# COMMON SYNC TYPES:
# - "device" - Physical devices/computers
# - "contact" - People/contacts
# - "site" - Locations/offices
# - "configuration" - Config items/assets
# - "asset" - Generic assets (HaloPSA, Syncro, Domotz specific)
# - "location" - Physical locations (NinjaOne, N-Central specific)
#
# =============================================================================

    # Cleanup
    $HuduAPIKey = $null
    $HuduBaseDomain = $null
    [System.GC]::Collect()
}