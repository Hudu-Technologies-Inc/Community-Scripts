# Resolves which Hudu company (if any) each checklist document maps to,
# according to the chosen DestinationStrategy.

# Cache of all Hudu companies for fuzzy matching.
function Get-AllHuduCompaniesCached {
    if (-not $script:AllCompaniesCache) {
        $script:AllCompaniesCache = @(Get-HuduCompanies)
        Set-PrintAndLog -message "Loaded $($script:AllCompaniesCache.Count) Hudu companies for matching." -Color DarkGray
    }
    return $script:AllCompaniesCache
}

# Prompt the operator to choose a company (or global) for one document.
function Select-CompanyForDoc {
    param([string]$Context)
    $companies = Get-AllHuduCompaniesCached
    Write-Host ""
    Set-PrintAndLog -message "Choose a destination for: $Context" -Color Cyan
    $picked = Select-ObjectFromList -objects $companies -message "Select a company number (0 = global template)" -AllowNull
    if ($null -eq $picked) { return @{ CompanyId = $null; CompanyName = "(global)"; Skip = $false } }
    return @{ CompanyId = [int]$picked.id; CompanyName = $picked.name; Skip = $false }
}

# Returns @{ CompanyId; CompanyName; Skip }
function Resolve-Destination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][ValidateSet("GlobalTemplate","SingleCompany","VariousCompanies","ByFolderName","ByFileName")]
        [string]$Strategy,
        [Nullable[int]]$SingleCompanyId,
        [string]$SingleCompanyName,
        [double]$Threshold = 0.90,
        [ValidateSet("Prompt","Skip","Global")]
        [string]$OnNoMatch = "Prompt"
    )

    switch ($Strategy) {
        "GlobalTemplate"   { return @{ CompanyId = $null; CompanyName = "(global)"; Skip = $false } }
        "SingleCompany"    { return @{ CompanyId = $SingleCompanyId; CompanyName = $SingleCompanyName; Skip = $false } }
        "VariousCompanies" { return (Select-CompanyForDoc -Context ([System.IO.Path]::GetFileName($FilePath))) }
        default {
            # ByFolderName / ByFileName
            $candidate = if ($Strategy -eq "ByFolderName") {
                Split-Path (Split-Path -LiteralPath $FilePath -Parent) -Leaf
            } else {
                Get-CleanProcessName -Raw ([System.IO.Path]::GetFileName($FilePath)) -IsFileName
            }
            $companies = Get-AllHuduCompaniesCached
            $match = Find-BestByName -Name $candidate -choices $companies -prop 'name' -Threshold $Threshold
            if ($match) {
                return @{ CompanyId = [int]$match.id; CompanyName = $match.name; Skip = $false }
            }
            Set-PrintAndLog -message "No company match for '$candidate' (from $([System.IO.Path]::GetFileName($FilePath)))." -Color Yellow
            switch ($OnNoMatch) {
                "Skip"   { return @{ CompanyId = $null; CompanyName = $null; Skip = $true } }
                "Global" { return @{ CompanyId = $null; CompanyName = "(global)"; Skip = $false } }
                default  { return (Select-CompanyForDoc -Context "$candidate (no auto-match)") }
            }
        }
    }
}
