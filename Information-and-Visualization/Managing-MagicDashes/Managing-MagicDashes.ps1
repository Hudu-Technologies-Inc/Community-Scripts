# =============================================================================
# HUDU MAGIC DASH MANAGER
# =============================================================================
# Created by: David Kniskern
# Created on: 2025-01-27
# Updated on: 2025-01-27
# =============================================================================
# 
# PURPOSE:
# This script provides an interactive management interface for Hudu Magic Dash tiles.
# It allows users to create, update, delete, and manage Magic Dash tiles across
# all companies in their Hudu instance.
#
# FEATURES:
# - Interactive menu-driven interface
# - Create new Magic Dash tiles for any company
# - Update existing Magic Dash tiles (URL, description)
# - Delete individual or all Magic Dash tiles for a company
# - Visual feedback with emojis and color coding
# - Comprehensive error handling and debugging
#
# REQUIREMENTS:
# - PowerShell 7.5.1 or higher
# - HuduAPI module (installed automatically)
# - Azure Key Vault access for credentials
# - Hudu instance with Magic Dash functionality
#
# USAGE:
# 1. Ensure your Azure Key Vault contains:
#    - HuduAPIKey: Your Hudu API key (24 characters)
#    - HuduBaseDomain: Your Hudu instance URL (without trailing slash)
# 2. Run the script: .\interactive_magic_dash_manager.ps1
# 3. Follow the interactive prompts
#
# =============================================================================

# =============================================================================
# CONFIGURATION AND INITIALIZATION
# =============================================================================

# Azure Key Vault configuration
$VaultName = "my-az-keyvault-name"
$ApiKeySecretName = "my-secret-in-az.keystore"
$HuduBaseDomain="hudubaseurl.huducloud.com"
#### Hudu Settings ####
# Retrieve Hudu credentials from Azure Key Vault
# This ensures secure credential management without hardcoding sensitive data
if (-not (Get-Command -Name Get-AzKeyVaultSecret -ErrorAction SilentlyContinue)) { write-host "please wait, ensuring az.keystore module"; install-module AZ.Keystore -Force; import-module AZ.Keystore; }
$HuduBaseDomain = $(if ($HuduBaseDomain -ieq "hudubaseurl.huducloud.com" -or ([string]::IsNullOrWhiteSpace($HuduBaseDomain))){Read-Host "Please enter your hudu base url 'yourinstance.huducloud.com"} else {$HuduBaseDomain})
$HuduAPIKey = $(try {Get-AzKeyVaultSecret -vaultName $VaultName -name "$ApiKeySecretName" -AsPlainText -ErrorAction Stop} catch {$(read-host "couldn't fetch hudu api key from secret named $ApiKeySecretName in vault $VaultName, please enter your hudu API key")}); clear-host;
# Import HuduAPI module for Hudu integration
import-module HuduAPI

# Initialize Hudu API connection
# This establishes the connection to your Hudu instance using the retrieved credentials
New-HuduAPIKey $HuduAPIKey
New-HuduBaseUrl $HuduBaseDomain

Write-Host "Connected to Hudu instance: $HuduBaseDomain" -ForegroundColor Green

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to clear sensitive data from memory
function Clear-SensitiveData {
    Write-Host "Clearing sensitive data from memory..." -ForegroundColor Yellow
    $script:HuduAPIKey = $null
    $script:HuduBaseDomain = $null
    $script:VaultName = $null
    [System.GC]::Collect()
    Write-Host "Sensitive data cleared from memory." -ForegroundColor Green
}

# Function to test API connectivity
function Test-HuduAPIConnection {
    try {
        Write-Host "Testing Hudu API connection..." -ForegroundColor Yellow
        $uri = "$HuduBaseDomain/api/v1/magic_dash?page_size=1"
        if (-not $uri.StartsWith("https://")) {
            $uri = "https://$uri"
        }
        $headers = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
        }
        
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        Write-Host "API connection successful!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "API connection failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to validate yes/no input with case-insensitive support
# This function ensures consistent user input validation across the script
# Supports: Yes/No, Y/N, yes/no, y/n, and any case combination
# "No" always means go back (returns null), "Yes" means continue (returns true)
function Get-YesNoInput {
    param([string]$Prompt)
    
    do {
        $input = Read-Host $Prompt
        $normalizedInput = $input.Trim().ToLower()
        
        if ($normalizedInput -eq "yes" -or $normalizedInput -eq "y") {
            return $true
        } elseif ($normalizedInput -eq "no" -or $normalizedInput -eq "n") {
            return $false
        } else {
            Write-Host "Please enter Yes/No or Y/N (any case combination accepted)" -ForegroundColor Red
        }
    } while ($true)
}

# =============================================================================
# HUDU API FUNCTIONS
# =============================================================================

# Function to retrieve all Magic Dash tiles from Hudu
# This function makes a direct API call to get all Magic Dash tiles
# Uses the GET request with proper parameters as specified in the API documentation
# Returns an array of tile objects or null on error
function Get-AllMagicDashTiles {
    try {
        Write-Host "Retrieving all magic dash tiles..." -ForegroundColor Yellow
        
        # Construct API endpoint URL with proper parameters as per API documentation
        $uri = "$HuduBaseDomain/api/v1/magic_dash?page_size=1000"
        if (-not $uri.StartsWith("https://")) {
            $uri = "https://$uri"
        }
        
        # Set up API headers for authentication
        $headers = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
        }
        
        # Make API call to retrieve all Magic Dash tiles using GET method
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        
        # Handle different response structures
        if ($response -is [array]) {
            $magicDashTiles = $response
        } elseif ($response -and $response.magic_dash) {
            $magicDashTiles = $response.magic_dash
        } elseif ($response -and $response.data) {
            $magicDashTiles = $response.data
        } elseif ($null -eq $response) {
            $magicDashTiles = @()
        } else {
            $magicDashTiles = @($response)
        }
        
        # Ensure we always return an array, even if empty
        if ($null -eq $magicDashTiles) {
            $magicDashTiles = @()
        }
        
        Write-Host "Found $($magicDashTiles.Count) magic dash tiles" -ForegroundColor Cyan
        return $magicDashTiles
    }
    catch {
        Write-Error "Failed to retrieve magic dash tiles: $($_.Exception.Message)"
        return $null
    }
}

# Function to retrieve Magic Dash tiles by company ID
# This function uses the company_id parameter for more reliable filtering
# Parameters:
#   - CompanyId: The ID of the company to get tiles for
# Returns: Array of tile objects for the company
function Get-MagicDashTilesByCompanyId {
    param([int]$CompanyId)
    
    try {
        Write-Host "Retrieving magic dash tiles for company ID: $CompanyId..." -ForegroundColor Yellow
        
        # Construct API endpoint URL with company_id filter
        $uri = "$HuduBaseDomain/api/v1/magic_dash?company_id=$CompanyId&page_size=1000"
        if (-not $uri.StartsWith("https://")) {
            $uri = "https://$uri"
        }
        
        # Set up API headers for authentication
        $headers = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
        }
        
        # Make API call to retrieve Magic Dash tiles for specific company
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        
        # Handle different response structures
        if ($response -is [array]) {
            $magicDashTiles = $response
        } elseif ($response -and $response.magic_dash) {
            $magicDashTiles = $response.magic_dash
        } elseif ($response -and $response.data) {
            $magicDashTiles = $response.data
        } else {
            $magicDashTiles = @($response)
        }
        
        Write-Host "Found $($magicDashTiles.Count) magic dash tiles for company ID $CompanyId" -ForegroundColor Cyan
        return $magicDashTiles
    }
    catch {
        Write-Error "Failed to retrieve magic dash tiles for company ID $CompanyId : $($_.Exception.Message)"
        return $null
    }
}

# Function to retrieve all companies from Hudu
# This function makes a direct API call to get all companies
# Returns an array of company objects or null on error
function Get-AllCompanies {
    try {
        Write-Host "Retrieving all companies..." -ForegroundColor Yellow
        
        # Construct API endpoint URL
        $uri = "$HuduBaseDomain/api/v1/companies?page_size=1000"
        if (-not $uri.StartsWith("https://")) {
            $uri = "https://$uri"
        }
        
        # Set up API headers for authentication
        $headers = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
        }
        
        # Make API call to retrieve all companies
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        
        
        # Handle different response structures - companies are in the 'companies' property
        if ($response -and $response.companies) {
            $allCompanies = $response.companies
        } elseif ($response -is [array]) {
            $allCompanies = $response
        } elseif ($response -and $response.data) {
            $allCompanies = $response.data
        } elseif ($null -eq $response) {
            $allCompanies = @()
        } else {
            $allCompanies = @($response)
        }
        
        # Ensure we always return an array, even if empty
        if ($null -eq $allCompanies) {
            $allCompanies = @()
        }
        
        Write-Host "Found $($allCompanies.Count) companies" -ForegroundColor Cyan
        return $allCompanies
    }
    catch {
        Write-Error "Failed to retrieve companies: $($_.Exception.Message)"
        return $null
    }
}

# Function to identify companies that have Magic Dash tiles
# This function groups all Magic Dash tiles by company name
# Returns a hashtable where keys are company names and values are arrays of tiles
function Get-CompaniesWithMagicDash {
    param([array]$AllTiles, [array]$AllCompanies)
    
    $companiesWithTiles = @{}
    $processedTiles = @()
    
    # First pass: process all tiles and get full company names
    foreach ($tile in $AllTiles) {
        # Skip tiles with null or empty company names
        if ([string]::IsNullOrWhiteSpace($tile.company_name)) {
            Write-Host "WARNING: Skipping tile with null/empty company name: $($tile.title)" -ForegroundColor Yellow
            continue
        }
        
        $originalCompanyName = $tile.company_name
        
        $companyName = $originalCompanyName
        
        # ALWAYS try to find the full company name by matching with company ID first
        if ($tile.company_id) {
            $company = $AllCompanies | Where-Object { $_.id -eq $tile.company_id } | Select-Object -First 1
            if ($company) {
                $companyName = $company.name
                # Update the tile object to have the full company name
                $tile.company_name = $companyName
            } else {
                Write-Host "WARNING: Company ID $($tile.company_id) not found in companies list for tile: $($tile.title)" -ForegroundColor Yellow
            }
        } else {
            # Fallback to name matching if no company_id
            $fullCompanyName = $AllCompanies | Where-Object { $_.name.StartsWith($companyName) } | Select-Object -First 1 -ExpandProperty name
            if ($fullCompanyName) {
                $companyName = $fullCompanyName
                # Update the tile object to have the full company name
                $tile.company_name = $fullCompanyName
            } else {
                Write-Host "WARNING: Could not find full company name for truncated name '$companyName' for tile: $($tile.title)" -ForegroundColor Yellow
            }
        }
        
        # Store the processed tile with full company name
        $processedTiles += $tile
    }
    
    # Second pass: group tiles by their full company names
    foreach ($tile in $processedTiles) {
        $companyName = $tile.company_name
        if (-not $companiesWithTiles.ContainsKey($companyName)) {
            $companiesWithTiles[$companyName] = @()
        }
        $companiesWithTiles[$companyName] += $tile
    }
    
    return $companiesWithTiles
}

# Function to refresh companies with Magic Dash tiles from server
# This function retrieves fresh data from the server and rebuilds the companies list
# Returns a hashtable where keys are company names and values are arrays of tiles
function Refresh-CompaniesWithMagicDash {
    Write-Host "Refreshing companies with Magic Dash tiles from server..." -ForegroundColor Yellow
    
    # Get fresh data from server
    $allTiles = Get-AllMagicDashTiles
    $allCompanies = Get-AllCompanies
    
    if ($allTiles -eq $null -or $allCompanies -eq $null) {
        Write-Host "Failed to refresh data from server." -ForegroundColor Red
        return $null
    }
    
    # Rebuild companies with tiles
    $companiesWithTiles = Get-CompaniesWithMagicDash -AllTiles $allTiles -AllCompanies $allCompanies
    
    Write-Host "Found $($companiesWithTiles.Count) companies with Magic Dash tiles." -ForegroundColor Green
    
    return @{
        AllTiles = $allTiles
        AllCompanies = $allCompanies
        CompaniesWithTiles = $companiesWithTiles
    }
}

# Function to find a company by exact name match (case sensitive)
# This function searches through all companies to find an exact name match
# Returns the company object if found, null otherwise
function Find-CompanyByName {
    param([string]$CompanyName, [array]$AllCompanies)
    
    foreach ($company in $AllCompanies) {
        if ($company.name -eq $CompanyName) {
            return $company
        }
    }
    return $null
}

# Function to retrieve Magic Dash tiles for a specific company
# This function uses company ID for more reliable filtering
# Returns an array of tile objects for the company
function Get-MagicDashTilesForCompany {
    param([string]$CompanyName, [array]$AllTiles, [array]$AllCompanies)
    
    # First, find the company by name to get its ID
    $company = Find-CompanyByName -CompanyName $CompanyName -AllCompanies $AllCompanies
    if ($company -eq $null) {
        Write-Host "Company '$CompanyName' not found." -ForegroundColor Red
        return @()
    }
    
    # Use the new company ID-based function for more reliable results
    $tilesForCompany = Get-MagicDashTilesByCompanyId -CompanyId $company.id
    
    if ($tilesForCompany -eq $null) {
        Write-Host "Failed to retrieve tiles for company '$CompanyName' (ID: $($company.id))" -ForegroundColor Red
        return @()
    }
    
    return $tilesForCompany
}

# Function to display company selection menu
function Show-CompanySelectionMenu {
    param([hashtable]$CompaniesWithTiles)
    
    Write-Host "`n" -NoNewline
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "                    Companies with Magic Dash Tiles                    " -ForegroundColor White
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $companyList = @{}
    $index = 1
    
    foreach ($companyName in $CompaniesWithTiles.Keys | Sort-Object) {
        $tileCount = $CompaniesWithTiles[$companyName].Count
        $tileText = if ($tileCount -eq 1) { "tile" } else { "tiles" }
        Write-Host "  " -NoNewline
        Write-Host "[ " -NoNewline -ForegroundColor DarkCyan
        Write-Host "$($index). " -NoNewline -ForegroundColor Yellow
        Write-Host "$companyName " -NoNewline -ForegroundColor White
        Write-Host "($tileCount $tileText)" -ForegroundColor Gray
        $companyList[$index] = $companyName
        $index++
    }
    
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "[ " -NoNewline -ForegroundColor DarkRed
    Write-Host "0. " -NoNewline -ForegroundColor Red
    Write-Host "Exit" -ForegroundColor Red
    Write-Host ""
    
    return $companyList
}

# Function to display tile management menu
function Show-TileManagementMenu {
    param([string]$CompanyName, [array]$Tiles)
    
    Write-Host "`n" -NoNewline
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "                    Magic Dash Management for: $CompanyName" -ForegroundColor White
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor DarkRed
    Write-Host "1. " -NoNewline -ForegroundColor Red
    Write-Host "Mass delete ALL magic dash tiles for this company" -ForegroundColor Red
    Write-Host ""
    
    Write-Host "  " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor DarkYellow
    Write-Host "2. " -NoNewline -ForegroundColor Yellow
    Write-Host "Individually delete magic dash tiles" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "  " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor DarkBlue
    Write-Host "3. " -NoNewline -ForegroundColor Blue
    Write-Host "Update magic dash tiles" -ForegroundColor Blue
    Write-Host ""
    
    Write-Host "  " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor DarkGreen
    Write-Host "4. " -NoNewline -ForegroundColor Green
    Write-Host "Create a new magic dash tile" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "  " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor DarkMagenta
    Write-Host "5. " -NoNewline -ForegroundColor Magenta
    Write-Host "Delete tile by ID" -ForegroundColor Magenta
    Write-Host ""
    
    Write-Host "  " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor DarkRed
    Write-Host "0. " -NoNewline -ForegroundColor Red
    Write-Host "Back to company selection" -ForegroundColor Red
    Write-Host ""
}

# Function to display tiles for individual selection
function Show-TilesForSelection {
    param([array]$Tiles, [bool]$IsUpdateMode = $false)
    
    Write-Host "`n" -NoNewline
    Write-Host "===============================================================" -ForegroundColor Cyan
    if ($IsUpdateMode) {
        Write-Host "" -NoNewline -ForegroundColor Cyan
        Write-Host "                    Available Magic Dash Tiles to Update                    " -NoNewline -ForegroundColor White
        Write-Host "" -ForegroundColor Cyan
        Write-Host "" -NoNewline -ForegroundColor Yellow
        Write-Host "  WARNING: Changing the title will CREATE a new tile instead of updating!  " -NoNewline -ForegroundColor Red
        Write-Host "" -ForegroundColor Yellow
    } else {
        Write-Host "" -NoNewline -ForegroundColor Cyan
        Write-Host "                    Available Magic Dash Tiles                    " -NoNewline -ForegroundColor White
        Write-Host "" -ForegroundColor Cyan
    }
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $tileList = @()
    $index = 1
    
    foreach ($tile in $Tiles) {
        $tileTitle = $tile.title
        if ($tileTitle.Length -gt 45) {
            $tileTitle = $tileTitle.Substring(0, 42) + "..."
        }
        Write-Host "  " -NoNewline
        Write-Host "[  " -NoNewline -ForegroundColor DarkCyan
        Write-Host "$($index). " -NoNewline -ForegroundColor Yellow
        Write-Host "LINK: $tileTitle" -ForegroundColor White
        $tileList += $tile
        $index++
    }
    
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor DarkRed
    Write-Host "0. " -NoNewline -ForegroundColor Red
    Write-Host "Back to management menu" -ForegroundColor Red
    Write-Host ""
    
    return $tileList
}

function Write-InspectObject {
    param (
        [object]$object,
        [int]$Depth = 32,
        [int]$MaxLines = 16
    )

    $stringifiedObject = $null

    if ($null -eq $object) {
        return "Unreadable Object (null input)"
    }
    # Try JSON
    $stringifiedObject = try {
        $json = $object | ConvertTo-Json -Depth $Depth -ErrorAction Stop
        "# Type: $($object.GetType().FullName)`n$json"
    } catch { $null }

    # Try Format-Table
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-Table -Force | Out-String
        } catch { $null }
    }

    # Try Format-List
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-List -Force | Out-String
        } catch { $null }
    }

    # Fallback to manual property dump
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $props = $object | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            $lines = foreach ($p in $props) {
                try {
                    "$p = $($object.$p)"
                } catch {
                    "$p = <unreadable>"
                }
            }
            "# Type: $($object.GetType().FullName)`n" + ($lines -join "`n")
        } catch {
            "Unreadable Object"
        }
    }

    if (-not $stringifiedObject) {
        $stringifiedObject =  try {"$($($object).ToString())"} catch {$null}
    }
    # Truncate to max lines if necessary
    $lines = $stringifiedObject -split "`r?`n"
    if ($lines.Count -gt $MaxLines) {
        $lines = $lines[0..($MaxLines - 1)] + "... (truncated)"
    }

    return $lines -join "`n"
}

function Select-ObjectFromList($objects, $message, $inspectObjects = $false, $allowNull = $false) {
    $validated = $false
    while (-not $validated) {
        if ($allowNull) {
            Write-Host "0: None/Custom"
        }

        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]

            $displayLine = if ($inspectObjects) {
                "$($i+1): $(Write-InspectObject -object $object)"
            } elseif ($null -ne $object.OptionMessage) {
                "$($i+1): $($object.OptionMessage)"
            } elseif ($null -ne $object.name) {
                "$($i+1): $($object.name)"
            } else {
                "$($i+1): $($object)"
            }

            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }

        $choice = Read-Host $message

        if (-not ($choice -as [int])) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }

        $choice = [int]$choice

        if ($choice -eq 0 -and $allowNull) {
            return $null
        }

        if ($choice -ge 1 -and $choice -le $objects.Count) {
            return $objects[$choice - 1]
        } else {
            Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
        }
    }
}


# =============================================================================
# MAGIC DASH TILE MANAGEMENT FUNCTIONS
# =============================================================================

# Function to delete a Magic Dash tile by ID
# This function deletes a single tile using its ID
# Parameters:
#   - TileId: The ID of the tile to delete
# Returns: Boolean indicating success/failure
function Remove-MagicDashTileById {
    param([int]$TileId)
    
    try {
        Write-Host "  " -NoNewline
        Write-Host "Deleting tile ID: " -NoNewline -ForegroundColor Yellow
        Write-Host "$TileId" -ForegroundColor White
        
        $uri = "$HuduBaseDomain/api/v1/magic_dash/$TileId"
        if (-not $uri.StartsWith("https://")) {
            $uri = "https://$uri"
        }
        
        $headers = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
        }
        
        Write-Host "    " -NoNewline
        Write-Host "API Call: DELETE $uri" -ForegroundColor Gray
        
        $result = Invoke-RestMethod -Uri $uri -Method Delete -Headers $headers
        
        Write-Host "    " -NoNewline
        Write-Host "Successfully deleted tile ID $TileId" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "    " -NoNewline
        Write-Host "Error deleting tile ID $TileId : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to delete Magic Dash tiles with confirmation
# This function handles the deletion of one or more Magic Dash tiles
# Includes user confirmation and detailed progress reporting
# Parameters:
#   - TilesToDelete: Array of tile objects to delete
#   - CompanyName: Name of the company (for display purposes)
function Remove-MagicDashTiles {
    param(
        [array]$TilesToDelete,
        [string]$CompanyName
    )
    
    if ($TilesToDelete -eq $null -or $TilesToDelete.Count -eq 0) {
        Write-Host "No tiles selected for deletion." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n" -NoNewline
    Write-Host "===============================================================" -ForegroundColor Red
    Write-Host "" -NoNewline -ForegroundColor Red
    Write-Host "                    DELETION WARNING                     " -NoNewline -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Red
    Write-Host "===============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "The following tiles will be deleted from " -NoNewline -ForegroundColor Red
    Write-Host "${CompanyName}" -ForegroundColor White
    Write-Host ""
    
    foreach ($tile in $TilesToDelete) {
        Write-Host "  " -NoNewline
        Write-Host "- " -NoNewline -ForegroundColor Red
        Write-Host "$($tile.title)" -ForegroundColor White
    }
    Write-Host ""
    
        $confirmation = Get-YesNoInput "`nAre you sure you want to delete these $($TilesToDelete.Count) tiles? (Yes/No)"
        if (-not $confirmation) {
            Write-Host "Deletion cancelled by user." -ForegroundColor Yellow
            return
        }
    
    $deletedCount = 0
    $errorCount = 0
    
    Write-Host "`nStarting deletion process..." -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($tile in $TilesToDelete) {
        $success = $false
        
        # Try deletion by ID first (if tile has an ID)
        if ($tile.id -and $tile.id -gt 0) {
            Write-Host "  " -NoNewline
            Write-Host "Deleting: " -NoNewline -ForegroundColor Yellow
            Write-Host "$($tile.title)" -ForegroundColor White
            Write-Host "    " -NoNewline
            Write-Host "Company: $($tile.company_name)" -ForegroundColor Cyan
            Write-Host "    " -NoNewline
            Write-Host "Tile ID: $($tile.id)" -ForegroundColor Cyan
            
            $success = Remove-MagicDashTileById -TileId $tile.id
        }
        
        # If ID deletion failed or no ID available, try title/company method
        if (-not $success) {
        try {
            Write-Host "  " -NoNewline
                Write-Host "Deleting (by title/company): " -NoNewline -ForegroundColor Yellow
            Write-Host "$($tile.title)" -ForegroundColor White
            Write-Host "    " -NoNewline
            Write-Host "Company: $($tile.company_name)" -ForegroundColor Cyan
            
            $uri = "$HuduBaseDomain/api/v1/magic_dash"
            if (-not $uri.StartsWith("https://")) {
                $uri = "https://$uri"
            }
            $headers = @{
                "x-api-key" = $HuduAPIKey
                "Accept" = "application/json"
                "Content-Type" = "application/x-www-form-urlencoded"
            }
            # Use the full company name for deletion
            $encodedTitle = [System.Web.HttpUtility]::UrlEncode($tile.title)
            $encodedCompany = [System.Web.HttpUtility]::UrlEncode($tile.company_name)
            $body = "title=$encodedTitle&company_name=$encodedCompany"
            
            Write-Host "    " -NoNewline
            Write-Host "API Call: DELETE $uri" -ForegroundColor Gray
            Write-Host "    " -NoNewline
            Write-Host "Body: $body" -ForegroundColor Gray
            
            $result = Invoke-RestMethod -Uri $uri -Method Delete -Headers $headers -Body $body
                $success = $true
            Write-Host "    " -NoNewline
                Write-Host "Successfully deleted" -ForegroundColor Green
        }
        catch {
            Write-Host "    " -NoNewline
                Write-Host "Error deleting: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "    " -NoNewline
            Write-Host "Response: $($_.Exception.Response)" -ForegroundColor Red
            }
        }
        
        if ($success) {
            $deletedCount++
        } else {
            $errorCount++
        }
    }
    
    Write-Host "`n" -NoNewline
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "" -NoNewline -ForegroundColor Cyan
    Write-Host "                      DELETION SUMMARY                     " -NoNewline -ForegroundColor White
    Write-Host "" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "Successfully deleted: " -NoNewline -ForegroundColor Green
    Write-Host "$deletedCount" -ForegroundColor White
    Write-Host "  " -NoNewline
    Write-Host "Errors: " -NoNewline -ForegroundColor Red
    Write-Host "$errorCount" -ForegroundColor White
    Write-Host "  " -NoNewline
    Write-Host "Total processed: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($TilesToDelete.Count)" -ForegroundColor White
    Write-Host ""
    
    # Show final result
    if ($deletedCount -gt 0) {
        Write-Host "DELETION COMPLETED! $deletedCount tile(s) successfully removed from $CompanyName" -ForegroundColor Green
    } else {
        Write-Host "DELETION FAILED! No tiles were deleted. Check the error messages above." -ForegroundColor Red
    }
    Write-Host ""
}

# Function to create a new Magic Dash tile via Hudu API
# This function creates a new Magic Dash tile for the specified company
# Parameters:
#   - CompanyName: Name of the company to create the tile for
#   - Title: Title of the Magic Dash tile
#   - Url: URL that the tile will link to (content_link field)
#   - Description: Optional description text (message field)
# Returns: Boolean indicating success/failure
function New-MagicDashTile {
    param(
        [string]$CompanyName,
        [string]$Title,
        [string]$Url,
        [string]$Description = ""
    )
    
    try {
        Write-Host "  " -NoNewline
        Write-Host "Creating Magic Dash tile: " -NoNewline -ForegroundColor Yellow
        Write-Host "$Title" -ForegroundColor White
        
        $uri = "$HuduBaseDomain/api/v1/magic_dash"
        if (-not $uri.StartsWith("https://")) {
            $uri = "https://$uri"
        }
        $headers = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        $body = @{
            "title" = $Title
            "company_name" = $CompanyName
            "content_link" = $Url
            "message" = $Description
            "shade" = "success"
        } | ConvertTo-Json
        
        $result = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        
        Write-Host "    " -NoNewline
        Write-Host "Successfully created Magic Dash tile" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "    " -NoNewline
        Write-Host "Error creating tile: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to update an existing Magic Dash tile
# This function attempts to update a Magic Dash tile using POST method
# If POST fails, it falls back to delete + create method
# Parameters:
#   - Tile: The existing tile object to update
#   - NewTitle: New title for the tile
#   - NewUrl: New URL for the tile (content_link field)
#   - NewDescription: New description for the tile (message field)
# Returns: Boolean indicating success/failure
function Update-MagicDashTile {
    param(
        [object]$Tile,
        [string]$NewTitle,
        [string]$NewUrl,
        [string]$NewDescription = ""
    )
    
    try {
        Write-Host "  " -NoNewline
        Write-Host "Updating Magic Dash tile: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($Tile.title)" -ForegroundColor White
        
        # Try to update using POST method (Magic Dash tiles use POST for updates)
        try {
            Write-Host "    " -NoNewline
            Write-Host "Updating via API..." -NoNewline -ForegroundColor Yellow
            
            $updateUri = "$HuduBaseDomain/api/v1/magic_dash"
            if (-not $updateUri.StartsWith("https://")) {
                $updateUri = "https://$updateUri"
            }
            $updateHeaders = @{
                "x-api-key" = $HuduAPIKey
                "Accept" = "application/json"
                "Content-Type" = "application/json"
            }
            
            $updateBody = @{
                "title" = $NewTitle
                "company_name" = $Tile.company_name
                "content_link" = $NewUrl
                "message" = $NewDescription
                "shade" = "success"
            } | ConvertTo-Json
            
            
            $updateResult = Invoke-RestMethod -Uri $updateUri -Method Post -Headers $updateHeaders -Body $updateBody
            Write-Host " Success" -ForegroundColor Green
            
            Write-Host "    " -NoNewline
            Write-Host "Successfully updated Magic Dash tile" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host " Failed" -ForegroundColor Red
            Write-Host "    " -NoNewline
            Write-Host "API update failed, trying delete + create method..." -ForegroundColor Yellow
        }
        
        # Fallback: Delete + Create method
        Write-Host "    " -NoNewline
        Write-Host "Deleting old tile..." -NoNewline -ForegroundColor Yellow
        
        $deleteUri = "$HuduBaseDomain/api/v1/magic_dash"
        if (-not $deleteUri.StartsWith("https://")) {
            $deleteUri = "https://$deleteUri"
        }
        $deleteHeaders = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
            "Content-Type" = "application/x-www-form-urlencoded"
        }
        $deleteBody = "title=$([System.Web.HttpUtility]::UrlEncode($Tile.title))&company_name=$([System.Web.HttpUtility]::UrlEncode($Tile.company_name))"
        
        
        $deleteResult = Invoke-RestMethod -Uri $deleteUri -Method Delete -Headers $deleteHeaders -Body $deleteBody
        Write-Host " Success" -ForegroundColor Green
        
        # Then, create the new tile
        Write-Host "    " -NoNewline
        Write-Host "Creating updated tile..." -NoNewline -ForegroundColor Yellow
        
        $createUri = "$HuduBaseDomain/api/v1/magic_dash"
        if (-not $createUri.StartsWith("https://")) {
            $createUri = "https://$createUri"
        }
        $createHeaders = @{
            "x-api-key" = $HuduAPIKey
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        $createBody = @{
            "title" = $NewTitle
            "company_name" = $Tile.company_name
            "content_link" = $NewUrl
            "message" = $NewDescription
            "shade" = "success"
        } | ConvertTo-Json
        
        
        $createResult = Invoke-RestMethod -Uri $createUri -Method Post -Headers $createHeaders -Body $createBody
        Write-Host " Success" -ForegroundColor Green
        
        Write-Host "    " -NoNewline
        Write-Host "Successfully updated Magic Dash tile" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "    " -NoNewline
        Write-Host "Error updating tile: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to handle deletion by ID
function Start-DeleteById {
    param([string]$CompanyName)
    
    Write-Host "`n" -NoNewline
    Write-Host "===============================================================" -ForegroundColor Magenta
    Write-Host "                    DELETE TILE BY ID                    " -NoNewline -ForegroundColor White
    Write-Host "" -ForegroundColor Magenta
    Write-Host "===============================================================" -ForegroundColor Magenta
    Write-Host ""
    
    do {
        $tileIdInput = Read-Host "Enter the Magic Dash tile ID to delete (or 'back' to return to menu)"
        
        if ($tileIdInput.ToLower() -eq "back") {
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($tileIdInput)) {
            Write-Host "Tile ID cannot be empty. Please enter a valid ID." -ForegroundColor Red
            continue
        }
        
        if ($tileIdInput -match '^\d+$') {
            $tileId = [int]$tileIdInput
            
            Write-Host "`n" -NoNewline
            Write-Host "===============================================================" -ForegroundColor Red
            Write-Host "                    DELETION WARNING                     " -NoNewline -ForegroundColor Yellow
            Write-Host "" -ForegroundColor Red
            Write-Host "===============================================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "You are about to delete Magic Dash tile ID: " -NoNewline -ForegroundColor Red
            Write-Host "$tileId" -ForegroundColor White
            Write-Host ""
            
            $confirmation = Get-YesNoInput "Are you sure you want to delete this tile? (Yes/No)"
            
            if ($confirmation) {
                $success = Remove-MagicDashTileById -TileId $tileId
                
                if ($success) {
                    Write-Host "`nTile ID $tileId successfully deleted!" -ForegroundColor Green
                } else {
                    Write-Host "`nFailed to delete tile ID $tileId" -ForegroundColor Red
                }
                
                $deleteAnother = Get-YesNoInput "`nDelete another tile by ID? (Yes/No)"
                if (-not $deleteAnother) {
                    return
                }
            } else {
                Write-Host "Deletion cancelled by user." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Invalid ID format. Please enter a valid number." -ForegroundColor Red
        }
    } while ($true)
}

# Function to handle individual tile deletion with continuous workflow
# This function allows users to delete tiles one by one and asks if they want to continue
# Parameters:
#   - Tiles: Array of tile objects for the company
#   - CompanyName: Name of the company being managed
# Returns: Updated array of remaining tiles
function Start-IndividualDeletion {
    param([array]$Tiles, [string]$CompanyName)
    
    $currentTiles = $Tiles
    
    do {
        # Check if there are any tiles left
        if ($currentTiles.Count -eq 0) {
            Write-Host "`n" -NoNewline
            Write-Host "===============================================================" -ForegroundColor Yellow
            Write-Host "" -NoNewline -ForegroundColor Yellow
            Write-Host "                    ALL TILES DELETED!                    " -NoNewline -ForegroundColor White
            Write-Host "" -ForegroundColor Yellow
            Write-Host "" -NoNewline -ForegroundColor Yellow
            Write-Host "        No more Magic Dash tiles found for this company        " -NoNewline -ForegroundColor Cyan
            Write-Host "" -ForegroundColor Yellow
            Write-Host "===============================================================" -ForegroundColor Yellow
            Write-Host ""
            return $currentTiles
        }
        
        $tileList = Show-TilesForSelection -Tiles $currentTiles -IsUpdateMode $false
        
        $tileChoice = Read-Host "`nSelect tiles to delete (0 to go back, or comma-separated numbers)"
        
        if ($tileChoice -eq "0") {
            return $currentTiles
        }
        elseif ($tileChoice -match '^[\d,\s]+$') {
            $selectedIndices = $tileChoice -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $tileList.Count }
            
            if ($selectedIndices.Count -gt 0) {
                $tilesToDelete = @()
                foreach ($index in $selectedIndices) {
                    $tilesToDelete += $tileList[[int]$index - 1]
                }
                
                Remove-MagicDashTiles -TilesToDelete $tilesToDelete -CompanyName $CompanyName
                
                # Update the tile list
                $currentTiles = $currentTiles | Where-Object { $tilesToDelete -notcontains $_ }
                
                # Ask if user wants to delete another tile
                if ($currentTiles.Count -gt 0) {
                    Write-Host "`n" -NoNewline
                    Write-Host "===============================================================" -ForegroundColor Green
                    Write-Host "" -NoNewline -ForegroundColor Green
                    Write-Host "                    DELETION SUCCESSFUL!                    " -NoNewline -ForegroundColor White
                    Write-Host "" -ForegroundColor Green
                    Write-Host "" -NoNewline -ForegroundColor Green
                    Write-Host "        $($tilesToDelete.Count) tile(s) deleted successfully        " -NoNewline -ForegroundColor Cyan
                    Write-Host "" -ForegroundColor Green
                    Write-Host "===============================================================" -ForegroundColor Green
                    Write-Host ""
                    
                    $deleteAnother = Get-YesNoInput "Delete another tile? (Yes/No)"
                    if (-not $deleteAnother) {
                        return $currentTiles
                    }
                } else {
                    # All tiles deleted, will be handled by the check at the top of the loop
                    continue
                }
            } else {
                Write-Host "Invalid selection. Please enter valid numbers." -ForegroundColor Red
            }
        }
        else {
            Write-Host "Invalid selection. Please enter numbers or '0' to go back." -ForegroundColor Red
        }
    } while ($true)
}

# =============================================================================
# WORKFLOW FUNCTIONS
# =============================================================================

# Function to handle the tile update workflow
# This function provides an interactive interface for updating Magic Dash tiles
# Parameters:
#   - Tiles: Array of tile objects for the company
#   - CompanyName: Name of the company being managed
function Start-TileUpdate {
    param([array]$Tiles, [string]$CompanyName)
    
    do {
        $tileList = Show-TilesForSelection -Tiles $Tiles -IsUpdateMode $true
        
        $tileChoice = Read-Host "`nSelect a tile to update (0 to go back)"
        
        if ($tileChoice -eq "0") {
        return
    }
    
        if ($tileChoice -match '^\d+$' -and [int]$tileChoice -ge 1 -and [int]$tileChoice -le $tileList.Count) {
            $selectedTile = $tileList[[int]$tileChoice - 1]
            
            
            Write-Host "`n" -NoNewline
            Write-Host "===============================================================" -ForegroundColor Yellow
            Write-Host "" -NoNewline -ForegroundColor Yellow
            Write-Host "                      Current Tile Details                      " -NoNewline -ForegroundColor White
            Write-Host "" -ForegroundColor Yellow
            Write-Host "===============================================================" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  " -NoNewline
            Write-Host "Title: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($selectedTile.title)" -ForegroundColor White
            Write-Host "  " -NoNewline
            Write-Host "URL: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($selectedTile.content_link)" -ForegroundColor White
            Write-Host "  " -NoNewline
            Write-Host "Description: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($selectedTile.message)" -ForegroundColor White
            Write-Host ""
            
            Write-Host "  IMPORTANT: Changing the title will create a new tile (Magic Dash uses POST for updates)!" -ForegroundColor Red
            Write-Host ""
            
            $newTitle = Read-Host "Enter new title (or press Enter to keep current, '0' to go back)"
            if ($newTitle -eq "0") {
                continue
            }
            if ([string]::IsNullOrWhiteSpace($newTitle)) {
                $newTitle = $selectedTile.title
            }
            
            $newUrl = Read-Host "Enter new URL (optional - press Enter to keep current, '0' to go back)"
            if ($newUrl -eq "0") {
                continue
            }
            if ([string]::IsNullOrWhiteSpace($newUrl)) {
                $newUrl = $selectedTile.content_link
            } else {
                # If URL is provided, validate format
                try {
                    $uri = [System.Uri]::new($newUrl)
                }
                catch {
                    Write-Host "Invalid URL format. Please enter a valid URL (e.g., https://example.com)" -ForegroundColor Red
                    continue
                }
            }
            
            $newDescription = Read-Host "Enter new description (or press Enter to keep current, '0' to go back)"
            if ($newDescription -eq "0") {
                continue
            }
            if ([string]::IsNullOrWhiteSpace($newDescription)) {
                $newDescription = $selectedTile.message
            }
            
            Write-Host "`n" -NoNewline
            Write-Host "===============================================================" -ForegroundColor Green
            Write-Host "" -NoNewline -ForegroundColor Green
            Write-Host "                      Updated Tile Details                      " -NoNewline -ForegroundColor White
            Write-Host "" -ForegroundColor Green
            Write-Host "===============================================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "  " -NoNewline
            Write-Host "Title: " -NoNewline -ForegroundColor Cyan
            Write-Host "$newTitle" -ForegroundColor White
            Write-Host "  " -NoNewline
            Write-Host "URL: " -NoNewline -ForegroundColor Cyan
            if ([string]::IsNullOrWhiteSpace($newUrl)) {
                Write-Host "(No URL - tile will not be clickable)" -ForegroundColor Gray
            } else {
                Write-Host "$newUrl" -ForegroundColor White
            }
            Write-Host "  " -NoNewline
            Write-Host "Description: " -NoNewline -ForegroundColor Cyan
            Write-Host "$newDescription" -ForegroundColor White
            Write-Host ""
            
            $confirm = Get-YesNoInput "`nUpdate this tile? (Yes/No)"
            
            if ($confirm -eq $null) {
                continue
            }
            if ($confirm) {
                $success = Update-MagicDashTile -Tile $selectedTile -NewTitle $newTitle -NewUrl $newUrl -NewDescription $newDescription
                
                if ($success) {
                    $updateAnother = Get-YesNoInput "`nUpdate another tile? (Yes/No)"
                    if (-not $updateAnother) {
                        return
                    }
                } else {
                    $retry = Get-YesNoInput "`nWould you like to try again? (Yes/No)"
                    if (-not $retry) {
                        return
                    }
                }
            } else {
                $retry = Get-YesNoInput "`nWould you like to try again with different details? (Yes/No)"
                if (-not $retry) {
                    return
                }
            }
        }
        else {
            Write-Host "Invalid selection. Please enter a valid number." -ForegroundColor Red
        }
    } while ($true)
}

# Function to handle the tile creation workflow
# This function provides an interactive interface for creating new Magic Dash tiles
# Parameters:
#   - CompanyName: Name of the company to create tiles for
function Start-TileCreation {
    param([string]$CompanyName)
    
    Write-Host "`n" -NoNewline
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host "" -NoNewline -ForegroundColor Green
    Write-Host "                    CREATING NEW TILE                    " -NoNewline -ForegroundColor White
    Write-Host "" -ForegroundColor Green
    Write-Host "" -NoNewline -ForegroundColor Green
    Write-Host "                    Company: $CompanyName                    " -NoNewline -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    
    do {
        $title = Read-Host "Enter tile title (or '0' to go back)"
        
        if ($title -eq "0") {
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($title)) {
            Write-Host "Title cannot be empty. Please enter a valid title." -ForegroundColor Red
            continue
        }
        
        $url = Read-Host "Enter tile URL (optional - press Enter to skip, or '0' to go back)"
        
        if ($url -eq "0") {
            return
        }
        
        # If URL is provided, validate format
        if (-not [string]::IsNullOrWhiteSpace($url)) {
        try {
            $uri = [System.Uri]::new($url)
        }
        catch {
            Write-Host "Invalid URL format. Please enter a valid URL (e.g., https://example.com)" -ForegroundColor Red
            continue
        }
        } else {
            $url = ""  # Set to empty string if skipped
        }
        
        $description = Read-Host "Enter tile description (optional, or '0' to go back)"
        
        if ($description -eq "0") {
            return
        }
        
        Write-Host "`n" -NoNewline
        Write-Host "===============================================================" -ForegroundColor Yellow
        Write-Host "" -NoNewline -ForegroundColor Yellow
        Write-Host "                      TILE PREVIEW                      " -NoNewline -ForegroundColor White
        Write-Host "" -ForegroundColor Yellow
        Write-Host "===============================================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  " -NoNewline
        Write-Host "Company: " -NoNewline -ForegroundColor Cyan
        Write-Host "$CompanyName" -ForegroundColor White
        Write-Host "  " -NoNewline
        Write-Host "Title: " -NoNewline -ForegroundColor Cyan
        Write-Host "$title" -ForegroundColor White
        Write-Host "  " -NoNewline
        Write-Host "URL: " -NoNewline -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($url)) {
            Write-Host "(No URL - tile will not be clickable)" -ForegroundColor Gray
        } else {
            Write-Host "$url" -ForegroundColor White
        }
        Write-Host "  " -NoNewline
        Write-Host "Description: " -NoNewline -ForegroundColor Cyan
        Write-Host "$description" -ForegroundColor White
        Write-Host ""
        
        $confirm = Get-YesNoInput "`nCreate this Magic Dash tile? (Yes/No)"
        
        if ($confirm) {
            $success = New-MagicDashTile -CompanyName $CompanyName -Title $title -Url $url -Description $description
            
            if ($success) {
                $createAnother = Get-YesNoInput "`nCreate another tile for this company? (Yes/No)"
                if (-not $createAnother) {
                    return
                }
            } else {
                $retry = Get-YesNoInput "`nWould you like to try again? (Yes/No)"
                if (-not $retry) {
                    return
                }
            }
        } else {
            $retry = Get-YesNoInput "`nWould you like to try again with different details? (Yes/No)"
            if (-not $retry) {
                return
            }
        }
    } while ($true)
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main script execution with comprehensive error handling
# This section initializes the application, retrieves data from Hudu,
# and runs the main interactive loop

# Test API connection
if (-not (Test-HuduAPIConnection)) {
    Write-Host "API connection test failed. Please check your credentials and try again." -ForegroundColor Red
    exit 1
}

try {
    Write-Host "`n" -NoNewline
    Write-Host "=================================================================================" -ForegroundColor Cyan
    Write-Host "                     WELCOME TO THE MAGIC DASH MANAGER                     " -ForegroundColor White
    Write-Host "              Please read the options below, then select the option that applies.              " -ForegroundColor Gray
    Write-Host "=================================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Get all data
    $allTiles = Get-AllMagicDashTiles
    $allCompanies = Get-AllCompanies
    
    # Find companies with magic dash tiles
    $companiesWithTiles = Get-CompaniesWithMagicDash -AllTiles $allTiles -AllCompanies $allCompanies
    
    if ($companiesWithTiles.Count -eq 0) {
        Write-Host "`nNo companies found with Magic Dash tiles." -ForegroundColor Yellow
        Write-Host "You can still create new tiles for any company." -ForegroundColor White
    } else {
        Write-Host "`nFound $($companiesWithTiles.Count) companies with Magic Dash tiles." -ForegroundColor Green
    }
    
    # Main application loop
    do {
        Write-Host "`n" -NoNewline
        Write-Host "=================================================================================" -ForegroundColor Cyan
        Write-Host "                        MAGIC DASH MANAGER                        " -ForegroundColor White
        Write-Host "=================================================================================" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "  " -NoNewline
        Write-Host "[1] " -NoNewline -ForegroundColor Cyan
        Write-Host "Select a company with existing Magic Dash tiles" -ForegroundColor White
        Write-Host ""
        
        Write-Host "  " -NoNewline
        Write-Host "[2] " -NoNewline -ForegroundColor Yellow
        Write-Host "Enter company name manually to create, delete, or update Magic Dash tiles" -ForegroundColor White
        Write-Host ""
        
        Write-Host "  " -NoNewline
        Write-Host "[3] " -NoNewline -ForegroundColor Magenta
        Write-Host "Test API connection and show debug info" -ForegroundColor Magenta
        Write-Host ""
        
        Write-Host "  " -NoNewline
        Write-Host "[0] " -NoNewline -ForegroundColor Red
        Write-Host "Exit" -ForegroundColor Red
        Write-Host ""
        
        Write-Host "Tip: Type '0' or 'No' at any prompt to go back to the previous page" -ForegroundColor Yellow
        Write-Host ""
        
        $mainChoice = Read-Host "Select an option"
        
        switch ($mainChoice) {
            "1" {
                if ($companiesWithTiles.Count -eq 0) {
                    Write-Host "No companies with Magic Dash tiles found." -ForegroundColor Yellow
                    continue
                }
                
                $companyList = Show-CompanySelectionMenu -CompaniesWithTiles $companiesWithTiles
                
                $companyChoice = Read-Host "`nSelect a company"
                
                if ($companyChoice -eq "0") {
                    continue
                }
                
                if ($companyChoice -match '^\d+$' -and [int]$companyChoice -ge 1 -and $companyList.ContainsKey([int]$companyChoice)) {
                    $selectedCompany = $companyList[[int]$companyChoice]
                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $selectedCompany -AllTiles $allTiles -AllCompanies $allCompanies
                    
                    # Tile management loop
                    do {
                        Show-TileManagementMenu -CompanyName $selectedCompany -Tiles $companyTiles
                        
                        $managementChoice = Read-Host "`nSelect an option"
                        
                        switch ($managementChoice) {
                            "1" {
                                # Mass delete all tiles
                                Remove-MagicDashTiles -TilesToDelete $companyTiles -CompanyName $selectedCompany
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $selectedCompany -AllTiles $allTiles -AllCompanies $allCompanies
                                    if ($companyTiles.Count -eq 0) {
                                        break
                                    }
                                } else {
                                    break
                                }
                            }
                            "2" {
                                # Individual deletion
                                $companyTiles = Start-IndividualDeletion -Tiles $companyTiles -CompanyName $selectedCompany
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $selectedCompany -AllTiles $allTiles -AllCompanies $allCompanies
                                    if ($companyTiles.Count -eq 0) {
                                        break
                                    }
                                } else {
                                    break
                                }
                            }
                            "3" {
                                # Update tiles
                                Start-TileUpdate -Tiles $companyTiles -CompanyName $selectedCompany
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $selectedCompany -AllTiles $allTiles -AllCompanies $allCompanies
                                }
                            }
                            "4" {
                                # Create new tile
                                Start-TileCreation -CompanyName $selectedCompany
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $selectedCompany -AllTiles $allTiles -AllCompanies $allCompanies
                                }
                            }
                            "5" {
                                # Delete by ID
                                Start-DeleteById -CompanyName $selectedCompany
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $selectedCompany -AllTiles $allTiles -AllCompanies $allCompanies
                                }
                            }
                            "0" {
                                break
                            }
                            default {
                                Write-Host "Invalid selection. Please enter 1, 2, 3, 4, 5, or 0." -ForegroundColor Red
                            }
                        }
                    } while ($managementChoice -ne "0")
                }
                else {
                    Write-Host "Invalid selection. Please enter a valid number." -ForegroundColor Red
                }
            }
            "2" {
                
                $company = Select-ObjectFromList -objects $allCompanies -message "Select Company Please." -allowNull $false
                $companyName = $company.name
                Write-Host "Company '$companyName' found!" -ForegroundColor Green
                
                $companyTiles = Get-MagicDashTilesForCompany -CompanyName $companyName -AllTiles $allTiles -AllCompanies $allCompanies
                
                if ($companyTiles.Count -eq 0) {
                    Write-Host "No Magic Dash tiles found for this company." -ForegroundColor Yellow
                    $createNew = Get-YesNoInput "Would you like to create a new Magic Dash tile for this company? (Yes/No)"
                    if ($createNew) {
                        Start-TileCreation -CompanyName $companyName
                        # Refresh all data from server to get accurate counts
                        $refreshData = Refresh-CompaniesWithMagicDash
                        if ($refreshData -ne $null) {
                            $allTiles = $refreshData.AllTiles
                            $allCompanies = $refreshData.AllCompanies
                            $companiesWithTiles = $refreshData.CompaniesWithTiles
                        }
                    }
                } else {
                    Write-Host "Found $($companyTiles.Count) Magic Dash tiles for this company." -ForegroundColor Green
                    
                    # Tile management loop
                    do {
                        Show-TileManagementMenu -CompanyName $companyName -Tiles $companyTiles
                        
                        $managementChoice = Read-Host "`nSelect an option"
                        
                        switch ($managementChoice) {
                            "1" {
                                # Mass delete all tiles
                                Remove-MagicDashTiles -TilesToDelete $companyTiles -CompanyName $companyName
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $companyName -AllTiles $allTiles -AllCompanies $allCompanies
                                    if ($companyTiles.Count -eq 0) {
                                        break
                                    }
                                } else {
                                    break
                                }
                            }
                            "2" {
                                # Individual deletion
                                $companyTiles = Start-IndividualDeletion -Tiles $companyTiles -CompanyName $companyName
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $companyName -AllTiles $allTiles -AllCompanies $allCompanies
                                    if ($companyTiles.Count -eq 0) {
                                        break
                                    }
                                } else {
                                    break
                                }
                            }
                            "3" {
                                # Update tiles
                                Start-TileUpdate -Tiles $companyTiles -CompanyName $companyName
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $companyName -AllTiles $allTiles -AllCompanies $allCompanies
                                }
                            }
                            "4" {
                                # Create new tile
                                Start-TileCreation -CompanyName $companyName
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $companyName -AllTiles $allTiles -AllCompanies $allCompanies
                                }
                            }
                            "5" {
                                # Delete by ID
                                Start-DeleteById -CompanyName $companyName
                                # Refresh all data from server to get accurate counts
                                $refreshData = Refresh-CompaniesWithMagicDash
                                if ($refreshData -ne $null) {
                                    $allTiles = $refreshData.AllTiles
                                    $allCompanies = $refreshData.AllCompanies
                                    $companiesWithTiles = $refreshData.CompaniesWithTiles
                                    $companyTiles = Get-MagicDashTilesForCompany -CompanyName $companyName -AllTiles $allTiles -AllCompanies $allCompanies
                                }
                            }
                            "0" {
                                break
                            }
                            default {
                                Write-Host "Invalid selection. Please enter 1, 2, 3, 4, 5, or 0." -ForegroundColor Red
                            }
                        }
                    } while ($managementChoice -ne "0")
                }
            }
            "3" {
                Write-Host "`n" -NoNewline
                Write-Host "=================================================================================" -ForegroundColor Magenta
                Write-Host "                    DEBUG INFORMATION                    " -ForegroundColor White
                Write-Host "=================================================================================" -ForegroundColor Magenta
                Write-Host ""
                
                Write-Host "Hudu Base Domain: $HuduBaseDomain" -ForegroundColor Cyan
                Write-Host "API Key (first 8 chars): $($HuduAPIKey.Substring(0,8))..." -ForegroundColor Cyan
                Write-Host ""
                
                # Test API connection
                if (Test-HuduAPIConnection) {
                    Write-Host "API is working correctly!" -ForegroundColor Green
                    
                    # Show some sample data
                    Write-Host "`nSample Magic Dash tiles:" -ForegroundColor Yellow
                    if ($allTiles.Count -gt 0) {
                        $allTiles | Select-Object -First 3 | ForEach-Object {
                            Write-Host "  - $($_.title) (Company: $($_.company_name))" -ForegroundColor White
                        }
                    } else {
                        Write-Host "  No Magic Dash tiles found." -ForegroundColor Gray
                    }
                } else {
                    Write-Host "API connection failed!" -ForegroundColor Red
                }
                
                Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "0" {
                Write-Host "`n" -NoNewline
                Write-Host "=================================================================================" -ForegroundColor Green
                Write-Host "                    THANK YOU FOR USING MAGIC DASH MANAGER!                    " -ForegroundColor White
                Write-Host "=================================================================================" -ForegroundColor Green
                Write-Host ""
                
                # Clear sensitive data from memory before exiting
                Clear-SensitiveData
                
                Write-Host "`nScript exiting..." -ForegroundColor Yellow
                exit 0
            }
            default {
                Write-Host "Invalid selection. Please enter 1, 2, or 0." -ForegroundColor Red
            }
        }
    } while ($true)
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    
    # Clear sensitive data from memory before exiting on error
    Clear-SensitiveData
    
    exit 1
}

# Clear sensitive data from memory before normal completion
Clear-SensitiveData

Write-Host "`nMagic Dash Manager completed successfully!" -ForegroundColor Green
