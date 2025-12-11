# Hudu KB Folder Standardization Script
# Interactive script to create standardized folder structures across companies

param(
    [Parameter(Mandatory=$false)]
    [string]$FolderStructureFile = ""
)

# -------------------------------------------------------------------------
# Configuration Variables - SET THESE VALUES
# -------------------------------------------------------------------------
# Set your Azure Key Vault name (the name you gave your Key Vault in Azure Portal)
# Example: "MyCompany-KeyVault" or "hudu-kv-prod"
$AzVault_Name = "Azure Key Vault Name Here"

# Set the name of the secret that stores your Hudu API key (the name you gave the secret in Key Vault)
# Example: "HuduAPIKey" or "Hudu-API-Key-Production"
$AzVault_HuduSecretName = "Key-vault-secret-name-here"

# Set the name of the secret that stores your Hudu instance URL (the name you gave the secret in Key Vault)
# Example: "HuduURL" or "Hudu-Base-URL"
# The URL can be stored with or without https:// prefix (e.g., "support.hudu.technology" or "https://support.hudu.technology")
$AzVault_HuduURLSecretName = "Key-vault-secret-name-here"

# -------------------------------------------------------------------------
# Init Azure Module and Sign-In
# -------------------------------------------------------------------------
if (Get-Module -ListAvailable -Name 'Az') { 
    Write-Host "Importing module, Az..." -ForegroundColor Gray
    Import-Module Az 
} else {
    Write-Host "Installing and importing module Az..." -ForegroundColor Yellow
    Install-Module Az -Force -AllowClobber
    Import-Module Az 
}

if (-not (Get-AzContext)) { 
    Connect-AzAccount 
}

# Retrieve API key from Azure Key Vault
$HuduAPIKey = Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AzVault_HuduSecretName" -AsPlainText

# Retrieve Hudu URL from Azure Key Vault and normalize it
$HuduBaseURLRaw = Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AzVault_HuduURLSecretName" -AsPlainText

# Normalize URL: add https:// if missing, remove trailing slashes, trim whitespace
$HuduBaseURL = $HuduBaseURLRaw.Trim()
if (-not $HuduBaseURL.StartsWith("http://") -and -not $HuduBaseURL.StartsWith("https://")) {
    $HuduBaseURL = "https://" + $HuduBaseURL
}
$HuduBaseURL = $HuduBaseURL.TrimEnd('/')

# Set TLS to 1.2 for secure connections
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Base API URL
$BaseApiUrl = "$HuduBaseURL/api/v1"

# Headers for API requests
$Headers = @{
    "x-api-key" = $HuduAPIKey
    "Content-Type" = "application/json"
}

# Function to make API requests
function Invoke-HuduApi {
    param(
        [string]$Method,
        [string]$Endpoint,
        [object]$Body = $null
    )
    
    $Uri = "$BaseApiUrl$Endpoint"
    
    try {
        $params = @{
            Method = $Method
            Uri = $Uri
            Headers = $Headers
            ErrorAction = "Stop"
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-RestMethod @params
        return $response
    }
    catch {
        $errorMessage = "API Error: $_"
        Write-Host $errorMessage -ForegroundColor Red
        
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                Write-Host "API Response: $responseBody" -ForegroundColor Red
                
                # Check for common API errors
                if ($_.Exception.Response.StatusCode -eq 401) {
                    Write-Host "ERROR: Authentication failed. Please check your API key." -ForegroundColor Red
                } elseif ($_.Exception.Response.StatusCode -eq 403) {
                    Write-Host "ERROR: Access forbidden. Please check your API key permissions." -ForegroundColor Red
                } elseif ($_.Exception.Response.StatusCode -eq 404) {
                    Write-Host "ERROR: Resource not found. Please check the API endpoint." -ForegroundColor Red
                } elseif ($_.Exception.Response.StatusCode -eq 500) {
                    Write-Host "ERROR: Server error. Please try again later." -ForegroundColor Red
                }
            } catch {
                Write-Host "Could not read error response details." -ForegroundColor Red
            }
        }
        return $null
    }
}

# Function to get all companies
function Get-AllCompanies {
    $allCompanies = @()
    $page = 1
    $pageSize = 25
    
    do {
        $response = Invoke-HuduApi -Method "GET" -Endpoint "/companies?page=$page&page_size=$pageSize"
        if ($response -and $response.companies) {
            $allCompanies += $response.companies
            $page++
        } else {
            break
        }
    } while ($response.companies.Count -eq $pageSize)
    
    return $allCompanies
}

# Function to get existing folders for a company
function Get-CompanyFolders {
    param([int]$CompanyId)
    
    $folders = @()
    $page = 1
    $pageSize = 25
    
    do {
        $response = Invoke-HuduApi -Method "GET" -Endpoint "/folders?company_id=$CompanyId&page=$page&page_size=$pageSize"
        if ($response -and $response.folders) {
            $folders += $response.folders
            $page++
        } else {
            break
        }
    } while ($response.folders.Count -eq $pageSize)
    
    return $folders
}

# Function to create a folder
function New-HuduFolder {
    param(
        [string]$Name,
        [int]$CompanyId,
        [string]$Icon = "",
        [string]$Description = "",
        [int]$ParentFolderId = 0
    )
    
    $folderBody = @{
        folder = @{
            name = $Name
            company_id = $CompanyId
        }
    }
    
    if ($Icon) {
        $folderBody.folder.icon = $Icon
    }
    
    if ($Description) {
        $folderBody.folder.description = $Description
    }
    
    if ($ParentFolderId -gt 0) {
        $folderBody.folder.parent_folder_id = $ParentFolderId
    }
    
    $response = Invoke-HuduApi -Method "POST" -Endpoint "/folders" -Body $folderBody
    
    return $response
}

# Function to find folder by name in existing folders
function Find-FolderByName {
    param(
        [string]$Name,
        [array]$ExistingFolders,
        [int]$ParentFolderId = 0
    )
    
    if ($ParentFolderId -eq 0) {
        return $ExistingFolders | Where-Object { $_.name -eq $Name -and (-not $_.parent_folder_id -or $_.parent_folder_id -eq $null) }
    } else {
        return $ExistingFolders | Where-Object { $_.name -eq $Name -and $_.parent_folder_id -eq $ParentFolderId }
    }
}

# Function to create folder structure recursively
function New-FolderStructure {
    param(
        [object]$Structure,
        [int]$CompanyId,
        [int]$ParentFolderId = 0,
        [ref]$Stats,
        [ref]$CreatedFolders
    )
    
    foreach ($item in $Structure) {
        # Properly access hashtable properties
        if ($item -is [hashtable] -or $item -is [System.Collections.Hashtable]) {
            $folderName = $item['name']
            $icon = if ($item.ContainsKey('icon')) { $item['icon'] } else { "" }
            $description = if ($item.ContainsKey('description')) { $item['description'] } else { "" }
            $children = if ($item.ContainsKey('children') -and $item['children']) { $item['children'] } else { $null }
        } elseif ($item.PSObject.Properties.Name -contains "name") {
            $folderName = $item.name
            $icon = if ($item.PSObject.Properties.Name -contains "icon") { $item.icon } else { "" }
            $description = if ($item.PSObject.Properties.Name -contains "description") { $item.description } else { "" }
            $children = if ($item.PSObject.Properties.Name -contains "children" -and $item.children) { $item.children } else { $null }
        } else {
            Write-Host "    ERROR: Invalid folder item structure" -ForegroundColor Red
            $Stats.Value.Errors++
            $Stats.Value.ErrorDetails += "Invalid folder item: $item"
            continue
        }
        
        if (-not $folderName) {
            Write-Host "    ERROR: Folder name is empty" -ForegroundColor Red
            $Stats.Value.Errors++
            $Stats.Value.ErrorDetails += "Folder name is empty"
            continue
        }
        
        # Create folder
        Write-Host "    Creating folder: '$folderName'..." -ForegroundColor Yellow -NoNewline
        $result = New-HuduFolder -Name $folderName -CompanyId $CompanyId -Icon $icon -Description $description -ParentFolderId $ParentFolderId
        
        if ($result -and $result.folder) {
            Write-Host " ✓ Created (ID: $($result.folder.id))" -ForegroundColor Green
            $Stats.Value.Created++
            $currentFolderId = $result.folder.id
            # Track created folder
            $CreatedFolders.Value += @{
                Name = $folderName
                Id = $result.folder.id
                ParentId = $ParentFolderId
            }
        } else {
            Write-Host " ✗ Failed" -ForegroundColor Red
            $Stats.Value.Errors++
            $Stats.Value.ErrorDetails += "Failed to create folder '$folderName'"
            continue
        }
        
        # Handle nested folders
        if ($children) {
            New-FolderStructure -Structure $children -CompanyId $CompanyId -ParentFolderId $currentFolderId -Stats $Stats -CreatedFolders $CreatedFolders
        }
    }
}

# Function to get folder structure interactively
function Get-FolderStructureInteractive {
    Write-Host ""
    Write-Host "=== Folder Structure Definition ===" -ForegroundColor Cyan
    Write-Host "Enter folder names. Use leading spaces to create nested folders."
    Write-Host "Each leading space increases the nesting level by 1."
    Write-Host ""
    Write-Host "Rules:" -ForegroundColor Yellow
    Write-Host "  - 0 spaces = Top-level folder (root)" -ForegroundColor Gray
    Write-Host "  - 1 space = Nested under the closest folder above with 0 spaces" -ForegroundColor Gray
    Write-Host "  - 2 spaces = Nested under the closest folder above with 1 space" -ForegroundColor Gray
    Write-Host "  - And so on..." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Example (copy this format exactly):" -ForegroundColor Yellow
    Write-Host "testing 0" -ForegroundColor Gray
    Write-Host " testing 1" -ForegroundColor Gray
    Write-Host " testing 2" -ForegroundColor Gray
    Write-Host " testing 3" -ForegroundColor Gray
    Write-Host "  testing 4" -ForegroundColor Gray
    Write-Host "  testing 5" -ForegroundColor Gray
    Write-Host "   testing 6" -ForegroundColor Gray
    Write-Host "    testing 7" -ForegroundColor Gray
    Write-Host "    testing 8" -ForegroundColor Gray
    Write-Host "testing 9" -ForegroundColor Gray
    Write-Host " testing 10" -ForegroundColor Gray
    Write-Host "  testing 11" -ForegroundColor Gray
    Write-Host " testing 12" -ForegroundColor Gray
    Write-Host "  testing 13" -ForegroundColor Gray
    Write-Host ""
    Write-Host "This creates:" -ForegroundColor Cyan
    Write-Host "  testing 0 (root)" -ForegroundColor White
    Write-Host "    ├─ testing 1" -ForegroundColor White
    Write-Host "    ├─ testing 2" -ForegroundColor White
    Write-Host "    └─ testing 3" -ForegroundColor White
    Write-Host "         ├─ testing 4" -ForegroundColor White
    Write-Host "         ├─ testing 5" -ForegroundColor White
    Write-Host "         └─ testing 6" -ForegroundColor White
    Write-Host "              ├─ testing 7" -ForegroundColor White
    Write-Host "              └─ testing 8" -ForegroundColor White
    Write-Host "  testing 9 (root)" -ForegroundColor White
    Write-Host "    ├─ testing 10" -ForegroundColor White
    Write-Host "    │  └─ testing 11" -ForegroundColor White
    Write-Host "    └─ testing 12" -ForegroundColor White
    Write-Host "       └─ testing 13" -ForegroundColor White
    Write-Host ""
    Write-Host "Enter folder structure (type 'DONE' on a new line when finished):" -ForegroundColor Yellow
    
    $lines = @()
    do {
        try {
            $line = Read-Host
            $trimmedLine = $line.Trim()
            
            # Check for DONE (case-insensitive)
            if ($trimmedLine -eq "DONE" -or $trimmedLine -eq "done" -or $trimmedLine -eq "Done") {
                if ($lines.Count -eq 0) {
                    Write-Host "Please enter at least one folder before typing DONE." -ForegroundColor Yellow
                    continue
                }
                break
            }
            
            # Add non-empty lines
            if ($trimmedLine -ne "") {
                $lines += $line
            } elseif ($lines.Count -gt 0) {
                # Single empty line after content also ends input
                break
            }
        }
        catch {
            # Handle Ctrl+C or EOF (Ctrl+Z)
            if ($lines.Count -eq 0) {
                Write-Error "No folder structure entered."
                return @()
            }
            break
        }
    } while ($true)
    
    if ($lines.Count -eq 0) {
        Write-Error "No folder structure entered."
        return @()
    }
    
    # Debug output - visible to user
    Write-Host ""
    Write-Host "=== DEBUG: Parsing Folder Structure ===" -ForegroundColor Magenta
    Write-Host "DEBUG: Processing $($lines.Count) lines" -ForegroundColor Magenta
    
    # Parse indentation to create nested structure based on leading spaces only
    $structure = @()
    $allFolders = @()  # Track all folders in order to find parents
    $lineNum = 0
    
    foreach ($line in $lines) {
        $lineNum++
        
        # Count leading spaces only (ignore tabs)
        $leadingSpaces = 0
        for ($i = 0; $i -lt $line.Length; $i++) {
            if ($line[$i] -eq ' ') {
                $leadingSpaces++
            } elseif ($line[$i] -eq "`t") {
                # Skip tabs - user wants spaces only
                continue
            } else {
                break
            }
        }
        
        # Level = number of leading spaces
        $level = $leadingSpaces
        
        # Trim only leading spaces, preserve internal spaces in folder name
        $folderName = $line.TrimStart(' ')
        
        # Debug output
        Write-Host "DEBUG [Line $lineNum]: Original='$line' | Leading spaces=$leadingSpaces | Level=$level | Name='$folderName'" -ForegroundColor Cyan
        
        # Find parent: closest folder above with level = (current level - 1)
        $parent = $null
        if ($level -gt 0) {
            # Look backwards through all folders to find the closest parent
            for ($i = $allFolders.Count - 1; $i -ge 0; $i--) {
                if ($allFolders[$i].level -eq ($level - 1)) {
                    $parent = $allFolders[$i]
                    Write-Host "DEBUG [Line $lineNum]: Found parent '$($parent.name)' at level $($parent.level)" -ForegroundColor Yellow
                    break
                }
            }
            
            if (-not $parent) {
                Write-Host "DEBUG [Line $lineNum]: WARNING - No parent found for level $level, treating as top-level" -ForegroundColor Red
            }
        }
        
        # Create folder object
        $folderObj = @{
            name = $folderName
            level = $level
        }
        
        if ($level -eq 0 -or -not $parent) {
            # Top-level folder (no parent, goes in base directory)
            $structure += $folderObj
            Write-Host "DEBUG [Line $lineNum]: Added top-level folder: '$folderName' (level: $level)" -ForegroundColor Green
        } else {
            # Nested folder - add to parent's children
            if (-not $parent.children) {
                $parent.children = @()
            }
            $parent.children += $folderObj
            Write-Host "DEBUG [Line $lineNum]: Added nested folder '$folderName' under parent '$($parent.name)' (parent level: $($parent.level), child level: $level)" -ForegroundColor Green
        }
        
        # Add to all folders list for parent lookup
        $allFolders += $folderObj
        Write-Host "DEBUG [Line $lineNum]: Total folders tracked: $($allFolders.Count)" -ForegroundColor Gray
    }
    
    # Validate structure
    Write-Host ""
    Write-Host "DEBUG: Parsing complete. Structure has $($structure.Count) top-level folders" -ForegroundColor Magenta
    
    if ($structure.Count -eq 0) {
        Write-Error "Failed to parse folder structure - no top-level folders found."
        return @()
    }
    
    # Debug: Show final structure summary
    Write-Host "DEBUG: Final structure summary:" -ForegroundColor Magenta
    function Show-DebugStructure {
        param([object]$Structure, [int]$Indent = 0)
        foreach ($item in $Structure) {
            # Properly access hashtable properties
            if ($item -is [hashtable] -or $item -is [System.Collections.Hashtable]) {
                $name = $item['name']
                $level = if ($item.ContainsKey('level')) { $item['level'] } else { 0 }
                $children = if ($item.ContainsKey('children') -and $item['children']) { $item['children'] } else { $null }
            } elseif ($item.PSObject.Properties.Name -contains "name") {
                $name = $item.name
                $level = if ($item.PSObject.Properties.Name -contains "level") { $item.level } else { 0 }
                $children = if ($item.PSObject.Properties.Name -contains "children" -and $item.children) { $item.children } else { $null }
            } else {
                $name = $item.ToString()
                $level = 0
                $children = $null
            }
            $prefix = "  " * $Indent
            Write-Host "DEBUG: $prefix- $name (level: $level)" -ForegroundColor DarkGray
            if ($children) {
                Show-DebugStructure -Structure $children -Indent ($Indent + 1)
            }
        }
    }
    Show-DebugStructure -Structure $structure
    Write-Host "=== END DEBUG ===" -ForegroundColor Magenta
    Write-Host ""
    
    return $structure
}

# Function to load folder structure from JSON file
function Get-FolderStructureFromFile {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return $null
    }
    
    try {
        $content = Get-Content $FilePath -Raw | ConvertFrom-Json
        return $content
    }
    catch {
        Write-Error "Failed to parse JSON file: $_"
        return $null
    }
}

# Main execution
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Hudu KB Folder Standardization Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test API connection
Write-Host "Testing API connection..." -ForegroundColor Yellow

try {
    $apiInfo = Invoke-HuduApi -Method "GET" -Endpoint "/api_info"
    if (-not $apiInfo) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "ERROR: Failed to connect to Hudu API" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host "  1. Invalid API key" -ForegroundColor Yellow
        Write-Host "  2. Incorrect API URL" -ForegroundColor Yellow
        Write-Host "  3. Network connectivity issues" -ForegroundColor Yellow
        Write-Host "  4. Hudu server is down" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please check your API key and URL settings." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  ✓ Connected successfully" -ForegroundColor Green
    Write-Host "  API Version: $($apiInfo.version)" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR: API Connection Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please verify:" -ForegroundColor Yellow
    Write-Host "  - API Key is correct in Azure Key Vault" -ForegroundColor Yellow
    Write-Host "  - API URL is correct: $HuduBaseURL" -ForegroundColor Yellow
    Write-Host "  - You have network connectivity" -ForegroundColor Yellow
    Write-Host "  - Azure Key Vault access is configured correctly" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Get companies
Write-Host "Fetching companies..." -ForegroundColor Yellow
$allCompanies = Get-AllCompanies
$activeCompanies = $allCompanies | Where-Object { -not $_.archived } | Sort-Object { $_.name }

Write-Host ""
Write-Host "=== Available Companies ===" -ForegroundColor Cyan
Write-Host "ID`tName" -ForegroundColor Yellow
Write-Host ("-" * 60)
foreach ($company in $activeCompanies) {
    Write-Host "$($company.id)`t$($company.name)"
}

Write-Host ""
Write-Host "=== Company Selection ===" -ForegroundColor Cyan
Write-Host "1. Process ALL companies"
Write-Host "2. Select specific companies by ID"
Write-Host ""
$selection = Read-Host "Enter your choice (1 or 2)"

$targetCompanies = @()

if ($selection -eq "1") {
    $targetCompanies = $activeCompanies
    Write-Host "Selected: ALL companies ($($targetCompanies.Count) companies)" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Enter company IDs (comma-separated, e.g., 1,5,10):" -ForegroundColor Yellow
    $companyIdsInput = Read-Host
    $companyIds = $companyIdsInput -split ',' | ForEach-Object { [int]($_.Trim()) }
    $targetCompanies = $activeCompanies | Where-Object { $_.id -in $companyIds }
    
    if ($targetCompanies.Count -eq 0) {
        Write-Error "No matching companies found."
        exit 1
    }
    
    Write-Host "Selected companies:" -ForegroundColor Green
    foreach ($company in $targetCompanies) {
        Write-Host "  - $($company.name) (ID: $($company.id))" -ForegroundColor White
    }
}

# Get folder structure
Write-Host ""
Write-Host "DEBUG: About to get folder structure..." -ForegroundColor Magenta
if ($FolderStructureFile) {
    Write-Host "Loading folder structure from file: $FolderStructureFile" -ForegroundColor Yellow
    $folderStructure = Get-FolderStructureFromFile -FilePath $FolderStructureFile
    if (-not $folderStructure) {
        exit 1
    }
} else {
    Write-Host "DEBUG: Calling Get-FolderStructureInteractive..." -ForegroundColor Magenta
    $folderStructure = Get-FolderStructureInteractive
    Write-Host "DEBUG: Get-FolderStructureInteractive returned. Count: $($folderStructure.Count)" -ForegroundColor Magenta
}

Write-Host "DEBUG: Validating folder structure..." -ForegroundColor Magenta
if (-not $folderStructure -or $folderStructure.Count -eq 0) {
    Write-Error "No folder structure defined."
    Write-Host "DEBUG: Validation failed - structure is null or empty" -ForegroundColor Red
    exit 1
}

Write-Host "DEBUG: Validation passed. Generating preview..." -ForegroundColor Magenta

# Show preview
Write-Host ""
Write-Host "DEBUG: About to show preview..." -ForegroundColor Magenta
Write-Host "=== Folder Structure Preview ===" -ForegroundColor Cyan
function Show-StructurePreview {
    param([object]$Structure, [int]$Indent = 0)
    
    Write-Host "DEBUG: Show-StructurePreview called with $($Structure.Count) items at indent $Indent" -ForegroundColor DarkMagenta
    foreach ($item in $Structure) {
        # Properly access hashtable properties
        if ($item -is [hashtable] -or $item -is [System.Collections.Hashtable]) {
            $name = $item['name']
        } elseif ($item.PSObject.Properties.Name -contains "name") {
            $name = $item.name
        } else {
            $name = $item.ToString()
        }
        
        $prefix = "  " * $Indent
        Write-Host "$prefix- $name" -ForegroundColor White
        
        # Check for children
        $children = $null
        if ($item -is [hashtable] -or $item -is [System.Collections.Hashtable]) {
            if ($item.ContainsKey('children') -and $item['children']) {
                $children = $item['children']
            }
        } elseif ($item.PSObject.Properties.Name -contains "children" -and $item.children) {
            $children = $item.children
        }
        
        if ($children) {
            Write-Host "DEBUG: Item '$name' has $($children.Count) children" -ForegroundColor DarkMagenta
            Show-StructurePreview -Structure $children -Indent ($Indent + 1)
        }
    }
}
Write-Host "DEBUG: Calling Show-StructurePreview..." -ForegroundColor Magenta
Show-StructurePreview -Structure $folderStructure
Write-Host "DEBUG: Show-StructurePreview completed" -ForegroundColor Magenta

Write-Host ""
$confirm = Read-Host "Proceed with creating these folders? (y/n)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# Process each company
$stats = @{
    Processed = 0
    Created = 0
    Errors = 0
    ErrorDetails = @()
}

$companyResults = @()

Write-Host ""
Write-Host "=== Processing Companies ===" -ForegroundColor Cyan
Write-Host ""

foreach ($company in $targetCompanies) {
    $stats.Processed++
    Write-Host "[$($stats.Processed)/$($targetCompanies.Count)] Processing: $($company.name) (ID: $($company.id))" -ForegroundColor Cyan
    
    $companyCreatedFolders = @()
        $companyStats = @{
            Created = 0
            Errors = 0
            ErrorDetails = @()
        }
    
    try {
        # Create folder structure
        New-FolderStructure -Structure $folderStructure -CompanyId $company.id -ParentFolderId 0 -Stats ([ref]$companyStats) -CreatedFolders ([ref]$companyCreatedFolders)
        
        # Update global stats
        $stats.Created += $companyStats.Created
        $stats.Errors += $companyStats.Errors
        $stats.ErrorDetails += $companyStats.ErrorDetails
        
        # Store company results
        $companyResults += @{
            CompanyName = $company.name
            CompanyId = $company.id
            CreatedFolders = $companyCreatedFolders
            Created = $companyStats.Created
            Errors = $companyStats.Errors
            ErrorDetails = $companyStats.ErrorDetails
        }
    }
    catch {
        Write-Host "  ERROR processing $($company.name): $_" -ForegroundColor Red
        $stats.Errors++
        $stats.ErrorDetails += "Error processing $($company.name): $_"
        $companyResults += @{
            CompanyName = $company.name
            CompanyId = $company.id
            CreatedFolders = @()
            Created = 0
            Errors = 1
            ErrorDetails = @("Error: $_")
        }
    }
    
    Write-Host ""
}

# Detailed Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Show results per company
foreach ($result in $companyResults) {
    Write-Host "Company: $($result.CompanyName) (ID: $($result.CompanyId))" -ForegroundColor White
    Write-Host "  Folders Created: $($result.Created)" -ForegroundColor $(if ($result.Created -gt 0) { "Green" } else { "Gray" })
    
    if ($result.CreatedFolders.Count -gt 0) {
        Write-Host "  Created Folders:" -ForegroundColor Green
        foreach ($folder in $result.CreatedFolders) {
            Write-Host "    - $($folder.Name) (ID: $($folder.Id))" -ForegroundColor Green
        }
    }
    
    if ($result.Errors -gt 0) {
        Write-Host "  Errors: $($result.Errors)" -ForegroundColor Red
        foreach ($error in $result.ErrorDetails) {
            Write-Host "    - $error" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# Overall Summary
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Overall Statistics:" -ForegroundColor Cyan
Write-Host "  Companies processed: $($stats.Processed)" -ForegroundColor White
Write-Host "  Total folders created: $($stats.Created)" -ForegroundColor Green
Write-Host "  Total errors: $($stats.Errors)" -ForegroundColor $(if ($stats.Errors -gt 0) { "Red" } else { "Green" })
Write-Host ""

# Show detailed errors if any
if ($stats.Errors -gt 0 -and $stats.ErrorDetails.Count -gt 0) {
    Write-Host "Error Details:" -ForegroundColor Red
    foreach ($error in $stats.ErrorDetails) {
        Write-Host "  - $error" -ForegroundColor Red
    }
    Write-Host ""
}

# Success or failure message
if ($stats.Errors -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "✓ SUCCESSFULLY COMPLETED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "All folders have been created successfully for all companies." -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "⚠ COMPLETED WITH ERRORS" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "Some operations completed, but errors occurred. Please review the error details above." -ForegroundColor Yellow
}
Write-Host ""

# -------------------------------------------------------------------------
# Cleanup - Remove sensitive data from memory silently
# -------------------------------------------------------------------------
$HuduAPIKey = $null
$HuduBaseURLRaw = $null
$AzVault_Name = $null
$AzVault_HuduSecretName = $null
$AzVault_HuduURLSecretName = $null
$HuduBaseURL = $null
$BaseApiUrl = $null
$Headers = $null
[System.GC]::Collect()
