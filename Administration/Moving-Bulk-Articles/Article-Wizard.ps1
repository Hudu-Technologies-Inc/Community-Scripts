<#
.SYNOPSIS
Moves Hudu articles between central and company knowledge bases.

.DESCRIPTION
End-user friendly article mover with dry-run-first behavior, a guided wizard,
folder preservation, source filters, CSV reporting, and confirmation gates for
live moves.

Examples:
  .\Moving-Articles.ps1 -Wizard
  .\Moving-Articles.ps1 -Direction ToCentral -SourceCompanyId 123
  .\Moving-Articles.ps1 -Direction ToCompany -DestinationCompanyId 456 -Apply
  .\Moving-Articles.ps1 -Direction CompanyToCompany -SourceCompanyIds 101,102 -DestinationCompanyId 666 -PrefixWithSourceCompany -Apply
  .\Moving-Articles.ps1 -ArticleIds 1001,1002 -Direction ToCompany -DestinationCompanyId 456 -Apply

Safety:
  - Defaults to dry-run mode.
  - Requires -Apply for real moves.
  - Prompts before live moves unless -Force is used.
  - Writes a CSV report for every run.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param (
    [ValidateSet("ToCentral", "ToCompany", "CompanyToCompany")]
    [string]$Direction,

    [switch]$Wizard,
    [switch]$SkipHuduInitialization,

    [int]$SourceCompanyId,
    [int[]]$SourceCompanyIds,
    [int]$DestinationCompanyId,
    [int[]]$ArticleIds,
    [int[]]$SourceFolderIds,

    [string]$DestinationRootFolderName = "",
    [bool]$PreserveFolderPath = $true,
    [bool]$IncludeFolderDescendants = $true,
    [switch]$PrefixWithSourceCompany,

    [int]$MaxArticles = 0,
    [string]$ReportPath,

    [switch]$Apply,
    [switch]$Force,
    [switch]$PassThru
)

function Write-HuduArticleMoveLog {
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ConsoleColor]$Color = "White"
    )

    if (Get-Command Set-PrintAndLog -ErrorAction SilentlyContinue) {
        Set-PrintAndLog -message $Message -Color $Color
        return
    }

    Write-Host $Message -ForegroundColor $Color
}

function Show-HuduArticleMoveHelp {
    Write-HuduArticleMoveLog "Hudu Article Mover" Cyan
    Write-HuduArticleMoveLog ""
    Write-HuduArticleMoveLog "Run the guided wizard:"
    Write-HuduArticleMoveLog "  .\Moving-Articles.ps1 -Wizard" Green
    Write-HuduArticleMoveLog ""
    Write-HuduArticleMoveLog "Common dry-runs:"
    Write-HuduArticleMoveLog "  .\Moving-Articles.ps1 -Direction ToCentral -SourceCompanyId 123"
    Write-HuduArticleMoveLog "  .\Moving-Articles.ps1 -Direction ToCompany -DestinationCompanyId 456"
    Write-HuduArticleMoveLog "  .\Moving-Articles.ps1 -Direction CompanyToCompany -SourceCompanyIds 101,102 -DestinationCompanyId 666 -PrefixWithSourceCompany"
    Write-HuduArticleMoveLog ""
    Write-HuduArticleMoveLog "Add -Apply to make real changes. Add -Force to skip the final live-move prompt." Yellow
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

function Select-ObjectFromList($objects, $message, $inspectObjects = $false, $allowNull = $false, $nullOptionMessage = "None/Custom") {
    $validated = $false
    while (-not $validated) {
        if ($allowNull) { Write-Host "0: $nullOptionMessage" }

        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]
            $displayLine = if ($inspectObjects) {
                "$($i+1): $(Write-InspectObject -object $object)"
            } elseif ($null -ne $object.OptionMessage) {
                "$($i+1): $($object.OptionMessage)"
            } elseif (-not $([string]::IsNullOrEmpty($object.attributes.name))) {
                "$($i+1): $($object.attributes.name)"
            } elseif (-not $([string]::IsNullOrEmpty($object.name))) {
                "$($i+1): $($object.name)"
            } else {
                "$($i+1): $($object)"
            }
            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }

        $raw = Read-Host $message
        if ($null -eq $raw -or [string]::IsNullOrWhiteSpace([string]$raw)) {
            if ($allowNull) { return $null }
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }

        $parsed = 0
        if (-not [int]::TryParse($raw, [ref]$parsed)) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }

        if ($parsed -eq 0 -and $allowNull) { return $null }

        if ($parsed -ge 1 -and $parsed -le $objects.Count) {
            return $objects[$parsed - 1]
        } else {
            Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
        }
    }
}
function Read-HuduArticleMoveText {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$Default = ""
    )

    if ([string]::IsNullOrWhiteSpace($Default)) {
        $answer = Read-Host $Prompt
        if ($null -eq $answer) { return "" }
        return $answer.Trim()
    }

    $answer = Read-Host "$Prompt [$Default]"
    if ($null -eq $answer) { return $Default }
    $answer = $answer.Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

function Read-HuduArticleMoveYesNo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [bool]$Default = $true
    )

    $defaultText = if ($Default) { "Y" } else { "N" }
    while ($true) {
        $answer = Read-Host "$Prompt (Y/N) [$defaultText]"
        if ($null -eq $answer) { return $Default }
        $answer = $answer.Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch ($answer.ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-HuduArticleMoveLog "Please enter Y or N." Yellow }
        }
    }
}

function ConvertFrom-HuduArticleMoveIdList {
    param (
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }

    $ids = [System.Collections.Generic.List[int]]::new()
    foreach ($part in ($Value -split "[,\s]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1) {
            throw "'$part' is not a valid positive numeric ID."
        }
        $ids.Add($number)
    }

    return @($ids | Select-Object -Unique)
}

function Read-HuduArticleMoveIdList {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    while ($true) {
        try {
            return @(ConvertFrom-HuduArticleMoveIdList -Value (Read-HuduArticleMoveText -Prompt $Prompt))
        } catch {
            Write-HuduArticleMoveLog $_.Exception.Message Yellow
        }
    }
}

function Get-HuduArticleMoveObjectId {
    param ($Object)

    return Get-HuduArticleMoveProperty -Object $Object -Names @("id", "Id")
}

function Get-HuduArticleMoveObjectName {
    param ($Object, [string]$Fallback = "")

    $name = [string](Get-HuduArticleMoveProperty -Object $Object -Names @("name", "Name", "title", "Title")
    )
    if ([string]::IsNullOrWhiteSpace($name)) { return $Fallback }
    return $name
}

function Format-HuduArticleMoveCount {
    param (
        [int]$Count,
        [Parameter(Mandatory = $true)]
        [string]$Singular,
        [string]$Plural
    )

    if ([string]::IsNullOrWhiteSpace($Plural)) { $Plural = "$($Singular)s" }
    if ($Count -eq 1) { return "1 $Singular" }
    return "$Count $Plural"
}

function Get-HuduArticleMoveAllCompanies {
    $companies = @(Get-HuduCompanies | ForEach-Object { Get-HuduArticleMoveCompanyObject $_ })
    return @($companies | Sort-Object { Get-HuduArticleMoveObjectName -Object $_ -Fallback "Company $(Get-HuduArticleMoveObjectId $_)" }, { Get-HuduArticleMoveObjectId $_ })
}

$script:HuduArticleMoveKbScopeCache = @{}
$script:HuduArticleMoveAllArticleCache = $null

function Get-HuduArticleMoveAllArticlesCached {
    if ($null -eq $script:HuduArticleMoveAllArticleCache) {
        Write-HuduArticleMoveLog "Loading article information..." Cyan
        $script:HuduArticleMoveAllArticleCache = @(Get-HuduArticles | ForEach-Object {
            Get-HuduArticleMoveArticleObject $_
        } | Where-Object { $null -ne $_ })
        Write-HuduArticleMoveLog "Loaded $($script:HuduArticleMoveAllArticleCache.Count) article record(s)." DarkGray
    }

    return @($script:HuduArticleMoveAllArticleCache)
}

function Get-HuduArticleMoveCachedArticlesForScope {
    param (
        [int]$CompanyId = 0
    )

    $allArticles = @(Get-HuduArticleMoveAllArticlesCached)
    if ($CompanyId -gt 0) {
        return @($allArticles | Where-Object {
            $articleCompanyId = Get-HuduArticleMoveArticleCompanyId $_
            $null -ne $articleCompanyId -and [int]$articleCompanyId -eq $CompanyId
        })
    }

    return @($allArticles | Where-Object {
        $articleCompanyId = Get-HuduArticleMoveArticleCompanyId $_
        $null -eq $articleCompanyId -or [string]::IsNullOrWhiteSpace([string]$articleCompanyId)
    })
}

function Get-HuduArticleMoveKbScopeSummary {
    param (
        [int]$CompanyId = 0
    )

    $cacheKey = [string]$CompanyId
    if ($script:HuduArticleMoveKbScopeCache.ContainsKey($cacheKey)) {
        return $script:HuduArticleMoveKbScopeCache[$cacheKey]
    }

    $folders = @(Get-HuduArticleMoveFoldersForScope -CompanyId $CompanyId)
    $articles = @(Get-HuduArticleMoveCachedArticlesForScope -CompanyId $CompanyId)

    $summary = [PSCustomObject]@{
        CompanyId     = $CompanyId
        FolderCount   = $folders.Count
        ArticleCount  = $articles.Count
        HasFolders    = $folders.Count -gt 0
        HasArticles   = $articles.Count -gt 0
        HasKnowledgeBase = ($folders.Count -gt 0 -or $articles.Count -gt 0)
    }

    $script:HuduArticleMoveKbScopeCache[$cacheKey] = $summary
    return $summary
}

function New-HuduArticleMoveCompanyOption {
    param (
        $Company,
        [switch]$Central,
        [switch]$IncludeCounts
    )

    if ($Central) {
        $centralMessage = "Central KB"
        if ($IncludeCounts) {
            $summary = Get-HuduArticleMoveKbScopeSummary -CompanyId 0
            $centralMessage = "Central KB ($(Format-HuduArticleMoveCount -Count $summary.ArticleCount -Singular 'article'), $(Format-HuduArticleMoveCount -Count $summary.FolderCount -Singular 'folder'))"
        }

        return [PSCustomObject]@{
            Id            = 0
            Name          = "Central KB"
            OptionMessage = $centralMessage
            Object        = $null
        }
    }

    $id = [int](Get-HuduArticleMoveObjectId $Company)
    $name = Get-HuduArticleMoveObjectName -Object $Company -Fallback "Company $id"
    $message = "$name [company ID $id]"
    if ($IncludeCounts) {
        $summary = Get-HuduArticleMoveKbScopeSummary -CompanyId $id
        $message = "$name ($(Format-HuduArticleMoveCount -Count $summary.ArticleCount -Singular 'article'), $(Format-HuduArticleMoveCount -Count $summary.FolderCount -Singular 'folder')) [company ID $id]"
    }

    return [PSCustomObject]@{
        Id            = $id
        Name          = $name
        OptionMessage = $message
        Object        = $Company
    }
}

function Select-HuduArticleMoveCompany {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$AllowCentral,
        [switch]$RequireKnowledgeBase
    )

    $companyOptions = @(Get-HuduArticleMoveAllCompanies | ForEach-Object {
        New-HuduArticleMoveCompanyOption -Company $_ -IncludeCounts
    })

    if ($RequireKnowledgeBase) {
        $companyOptions = @($companyOptions | Where-Object {
            (Get-HuduArticleMoveKbScopeSummary -CompanyId ([int]$_.Id)).HasKnowledgeBase
        })
        if ($companyOptions.Count -lt 1) {
            throw "No company KBs with articles or folders were found."
        }
    }

    if ($AllowCentral) {
        $selected = Select-ObjectFromList -objects $companyOptions -message $Message -allowNull $true -nullOptionMessage "Central KB"
        if ($null -eq $selected) { return (New-HuduArticleMoveCompanyOption -Central -IncludeCounts) }
        return $selected
    }

    return (Select-ObjectFromList -objects $companyOptions -message $Message -allowNull $false)
}

function Select-HuduArticleMoveCompanies {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$AllowCentral,
        [switch]$RequireKnowledgeBase
    )

    $companyOptions = @(Get-HuduArticleMoveAllCompanies | ForEach-Object {
        New-HuduArticleMoveCompanyOption -Company $_ -IncludeCounts
    })

    if ($RequireKnowledgeBase) {
        $companyOptions = @($companyOptions | Where-Object {
            (Get-HuduArticleMoveKbScopeSummary -CompanyId ([int]$_.Id)).HasKnowledgeBase
        })
        if ($companyOptions.Count -lt 1 -and -not $AllowCentral) {
            throw "No company KBs with articles or folders were found."
        }
    }

    if ($AllowCentral) {
        $companyOptions = @((New-HuduArticleMoveCompanyOption -Central -IncludeCounts)) + $companyOptions
    }

    $selectedCompanies = [System.Collections.Generic.List[object]]::new()
    $selectedIds = [System.Collections.Generic.HashSet[int]]::new()

    while ($true) {
        $remaining = @($companyOptions | Where-Object { -not $selectedIds.Contains([int]$_.Id) })
        if ($remaining.Count -lt 1) { break }

        $selected = Select-ObjectFromList -objects $remaining -message $Message -allowNull $true -nullOptionMessage "Done"
        if ($null -eq $selected) { break }

        [void]$selectedIds.Add([int]$selected.Id)
        $selectedCompanies.Add($selected)
        Write-HuduArticleMoveLog "Selected: $($selected.OptionMessage)" Green
    }

    return @($selectedCompanies)
}

function Get-HuduArticleMoveFoldersForScope {
    param (
        [int]$CompanyId = 0
    )

    if ($CompanyId -gt 0) {
        return @(Get-HuduFolders -CompanyId $CompanyId)
    }

    return @(Get-HuduFolders | Where-Object { $null -eq (Get-HuduArticleMoveFolderCompanyId $_) })
}

function Get-HuduArticleMoveFolderSubtreeIds {
    param (
        [Parameter(Mandatory = $true)]
        $FolderId,

        [Parameter(Mandatory = $true)]
        $FolderIndex
    )

    $ids = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue([string]$FolderId)

    while ($queue.Count -gt 0) {
        $currentId = $queue.Dequeue()
        if (-not $ids.Add($currentId)) { continue }
        if (-not $FolderIndex.ChildrenByParent.ContainsKey($currentId)) { continue }

        foreach ($child in @($FolderIndex.ChildrenByParent[$currentId])) {
            $childId = [string](Get-HuduArticleMoveObjectId $child)
            if (-not [string]::IsNullOrWhiteSpace($childId)) {
                $queue.Enqueue($childId)
            }
        }
    }

    return $ids
}

function New-HuduArticleMoveFolderOptions {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Scopes
    )

    $options = [System.Collections.Generic.List[object]]::new()

    foreach ($scope in @($Scopes)) {
        $scopeId = [int]$scope.Id
        $scopeName = [string]$scope.Name
        $folders = @(Get-HuduArticleMoveFoldersForScope -CompanyId $scopeId)
        $index = New-HuduArticleMoveFolderIndex -Folders $folders
        $articles = @(Get-HuduArticleMoveCachedArticlesForScope -CompanyId $scopeId)

        foreach ($folder in @($folders)) {
            $folderId = [int](Get-HuduArticleMoveObjectId $folder)
            $path = @(Get-HuduArticleMoveFolderPath -Folder $folder -FolderById $index.FolderById)
            $pathText = if ($path.Count -gt 0) { $path -join " > " } else { Get-HuduArticleMoveFolderName $folder }
            $folderSubtreeIds = Get-HuduArticleMoveFolderSubtreeIds -FolderId $folderId -FolderIndex $index
            $articleCount = @($articles | Where-Object {
                $articleFolderId = Get-HuduArticleMoveFolderId $_
                $articleFolderId -and $folderSubtreeIds.Contains([string]$articleFolderId)
            }).Count
            $options.Add([PSCustomObject]@{
                Id            = $folderId
                CompanyId     = if ($scopeId -gt 0) { $scopeId } else { $null }
                CompanyName   = $scopeName
                FolderName    = Get-HuduArticleMoveFolderName $folder
                FolderPath    = $pathText
                ArticleCount  = $articleCount
                OptionMessage = "$scopeName > $pathText ($(Format-HuduArticleMoveCount -Count $articleCount -Singular 'article')) [folder ID $folderId]"
                Object        = $folder
            })
        }
    }

    return @($options | Sort-Object CompanyName, FolderPath, Id)
}

function Select-HuduArticleMoveFolders {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Scopes,

        [string]$Message = "Select a source folder"
    )

    $folderOptions = @(New-HuduArticleMoveFolderOptions -Scopes $Scopes)
    if ($folderOptions.Count -lt 1) {
        Write-HuduArticleMoveLog "No folders found for the selected source." Yellow
        return @()
    }

    $selectedFolders = [System.Collections.Generic.List[object]]::new()
    $selectedIds = [System.Collections.Generic.HashSet[int]]::new()

    while ($true) {
        $remaining = @($folderOptions | Where-Object { -not $selectedIds.Contains([int]$_.Id) })
        if ($remaining.Count -lt 1) { break }

        $selected = Select-ObjectFromList -objects $remaining -message $Message -allowNull $true -nullOptionMessage "Done"
        if ($null -eq $selected) { break }

        [void]$selectedIds.Add([int]$selected.Id)
        $selectedFolders.Add($selected)
        Write-HuduArticleMoveLog "Selected: $($selected.OptionMessage)" Green
    }

    return @($selectedFolders)
}

function New-HuduArticleMoveArticleOptions {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Scopes
    )

    $options = [System.Collections.Generic.List[object]]::new()

    foreach ($scope in @($Scopes)) {
        $scopeId = [int]$scope.Id
        $scopeName = [string]$scope.Name
        $folders = @(Get-HuduArticleMoveFoldersForScope -CompanyId $scopeId)
        $folderIndex = New-HuduArticleMoveFolderIndex -Folders $folders
        $articles = @(Get-HuduArticleMoveCachedArticlesForScope -CompanyId $scopeId)

        foreach ($article in @($articles)) {
            $articleId = [int](Get-HuduArticleMoveArticleId $article)
            $articleName = Get-HuduArticleMoveObjectName -Object $article -Fallback "Article $articleId"
            $folderId = Get-HuduArticleMoveFolderId $article
            $folderPath = ""
            if ($folderId -and $folderIndex.FolderById.ContainsKey([string]$folderId)) {
                $folderPath = (@(Get-HuduArticleMoveFolderPath -Folder $folderIndex.FolderById[[string]$folderId] -FolderById $folderIndex.FolderById) -join " > ")
            }

            $contextText = if ([string]::IsNullOrWhiteSpace($folderPath)) { $scopeName } else { "$scopeName > $folderPath" }
            $options.Add([PSCustomObject]@{
                Id            = $articleId
                CompanyId     = if ($scopeId -gt 0) { $scopeId } else { $null }
                CompanyName   = $scopeName
                FolderId      = $folderId
                FolderPath    = $folderPath
                ArticleName   = $articleName
                OptionMessage = "$contextText > $articleName [article ID $articleId]"
                Object        = $article
            })
        }
    }

    return @($options | Sort-Object CompanyName, FolderPath, ArticleName, Id)
}

function Select-HuduArticleMoveArticles {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Scopes,

        [string]$Message = "Select an article"
    )

    $articleOptions = @(New-HuduArticleMoveArticleOptions -Scopes $Scopes)
    if ($articleOptions.Count -lt 1) {
        Write-HuduArticleMoveLog "No articles found for the selected source." Yellow
        return @()
    }

    $selectedArticles = [System.Collections.Generic.List[object]]::new()
    $selectedIds = [System.Collections.Generic.HashSet[int]]::new()

    while ($true) {
        $remaining = @($articleOptions | Where-Object { -not $selectedIds.Contains([int]$_.Id) })
        if ($remaining.Count -lt 1) { break }

        $selected = Select-ObjectFromList -objects $remaining -message $Message -allowNull $true -nullOptionMessage "Done"
        if ($null -eq $selected) { break }

        [void]$selectedIds.Add([int]$selected.Id)
        $selectedArticles.Add($selected)
        Write-HuduArticleMoveLog "Selected: $($selected.OptionMessage)" Green
    }

    return @($selectedArticles)
}

function Get-HuduArticleMoveDestinationPreviewPath {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Params,

        $SourceScope,

        [string]$SourcePath = ""
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace([string]$Params.DestinationRootFolderName)) {
        $parts.Add([string]$Params.DestinationRootFolderName)
    }

    if ($Params.Direction -eq "CompanyToCompany" -and $Params.PrefixWithSourceCompany -and $SourceScope -and [int]$SourceScope.Id -gt 0) {
        $parts.Add([string]$SourceScope.Name)
    }

    if ($Params.PreserveFolderPath -and -not [string]::IsNullOrWhiteSpace($SourcePath)) {
        foreach ($part in @($SourcePath -split " > ")) {
            if (-not [string]::IsNullOrWhiteSpace($part)) { $parts.Add($part) }
        }
    }

    if ($parts.Count -lt 1) { return "<destination KB root>" }
    return ($parts -join "\")
}

function Write-HuduArticleMoveWizardSummary {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Params,

        [Parameter(Mandatory = $true)]
        [object[]]$SourceScopes,

        $DestinationCompany,
        [string]$SourceMode,
        [object[]]$SelectedFolders = @(),
        [object[]]$SelectedArticles = @(),
        [int[]]$ManualArticleIds = @()
    )

    $destinationLabel = if ($Params.Direction -eq "ToCentral") {
        "Central KB"
    } elseif ($DestinationCompany) {
        "$($DestinationCompany.Name) [company ID $($DestinationCompany.Id)]"
    } elseif ($Params.DestinationCompanyId) {
        "Company KB $($Params.DestinationCompanyId)"
    } else {
        "Destination KB"
    }

    Write-HuduArticleMoveLog ""
    Write-HuduArticleMoveLog "Move Preview" Cyan
    Write-HuduArticleMoveLog "+-- Direction: $($Params.Direction)"
    Write-HuduArticleMoveLog "+-- Destination: $destinationLabel"
    Write-HuduArticleMoveLog "+-- Destination root: $(if ([string]::IsNullOrWhiteSpace([string]$Params.DestinationRootFolderName)) { '<KB root>' } else { $Params.DestinationRootFolderName })"
    Write-HuduArticleMoveLog "+-- Preserve folder path: $($Params.PreserveFolderPath)"
    if ($Params.Direction -eq "CompanyToCompany") {
        Write-HuduArticleMoveLog "+-- Prefix with source company: $($Params.PrefixWithSourceCompany)"
    }
    if ($Params.MaxArticles) {
        Write-HuduArticleMoveLog "+-- Max articles: $($Params.MaxArticles)"
    }

    Write-HuduArticleMoveLog "+-- Source selection: $SourceMode"

    switch ($SourceMode) {
        "All" {
            foreach ($scope in @($SourceScopes)) {
                $summary = Get-HuduArticleMoveKbScopeSummary -CompanyId ([int]$scope.Id)
                $destinationPath = Get-HuduArticleMoveDestinationPreviewPath -Params $Params -SourceScope $scope
                Write-HuduArticleMoveLog "|   +-- $($scope.Name) ($(Format-HuduArticleMoveCount -Count $summary.ArticleCount -Singular 'article'))"
                Write-HuduArticleMoveLog "|       +-- to: $destinationPath"
            }
        }
        "Folders" {
            foreach ($folder in @($SelectedFolders)) {
                $scope = @($SourceScopes | Where-Object {
                    if ($null -eq $folder.CompanyId) { [int]$_.Id -eq 0 } else { [int]$_.Id -eq [int]$folder.CompanyId }
                } | Select-Object -First 1)
                if (-not $scope) { $scope = [PSCustomObject]@{ Id = 0; Name = $folder.CompanyName } }
                $destinationPath = Get-HuduArticleMoveDestinationPreviewPath -Params $Params -SourceScope $scope -SourcePath $folder.FolderPath
                Write-HuduArticleMoveLog "|   +-- $($folder.CompanyName) > $($folder.FolderPath) ($(Format-HuduArticleMoveCount -Count $folder.ArticleCount -Singular 'article')) [folder ID $($folder.Id)]"
                Write-HuduArticleMoveLog "|       +-- to: $destinationPath"
            }
        }
        "Articles" {
            foreach ($article in @($SelectedArticles)) {
                $scope = @($SourceScopes | Where-Object {
                    if ($null -eq $article.CompanyId) { [int]$_.Id -eq 0 } else { [int]$_.Id -eq [int]$article.CompanyId }
                } | Select-Object -First 1)
                if (-not $scope) { $scope = [PSCustomObject]@{ Id = 0; Name = $article.CompanyName } }
                $destinationPath = Get-HuduArticleMoveDestinationPreviewPath -Params $Params -SourceScope $scope -SourcePath $article.FolderPath
                $folderText = if ([string]::IsNullOrWhiteSpace([string]$article.FolderPath)) { "<KB root>" } else { $article.FolderPath }
                Write-HuduArticleMoveLog "|   +-- $($article.CompanyName) > $folderText > $($article.ArticleName) [article ID $($article.Id)]"
                Write-HuduArticleMoveLog "|       +-- to: $destinationPath"
            }
        }
        "Manual" {
            Write-HuduArticleMoveLog "|   +-- Manual article IDs ($(Format-HuduArticleMoveCount -Count @($ManualArticleIds).Count -Singular 'ID'))"
            foreach ($articleId in @($ManualArticleIds)) {
                Write-HuduArticleMoveLog "|       +-- article ID $articleId"
            }
        }
    }

    Write-HuduArticleMoveLog ""
}

function Start-HuduArticleMoveWizard {
    Write-HuduArticleMoveLog "Hudu Article Move Wizard" Cyan
    Write-HuduArticleMoveLog "Tip: the wizard defaults to a dry-run preview. Nothing moves unless you choose Apply." DarkGray

    $allArticles = @(Get-HuduArticleMoveAllArticlesCached)
    if ($allArticles.Count -lt 1) {
        Write-HuduArticleMoveLog "No articles found anywhere. The mover packed a lunch, showed up early, and has absolutely nothing to carry." Yellow
        return $null
    }

    $centralArticleCount = @(Get-HuduArticleMoveCachedArticlesForScope -CompanyId 0).Count
    $companyKbCount = @((Get-HuduArticleMoveAllCompanies | ForEach-Object {
        $companyId = [int](Get-HuduArticleMoveObjectId $_)
        if ((Get-HuduArticleMoveKbScopeSummary -CompanyId $companyId).HasKnowledgeBase) { $companyId }
    }) | Where-Object { $null -ne $_ }).Count

    $directionOption = Select-ObjectFromList -objects @(
        [PSCustomObject]@{ Direction = "ToCentral"; OptionMessage = "Move company KB articles to central KB ($(Format-HuduArticleMoveCount -Count $companyKbCount -Singular 'company' -Plural 'companies'))" },
        [PSCustomObject]@{ Direction = "ToCompany"; OptionMessage = "Move central KB articles to a company KB ($(Format-HuduArticleMoveCount -Count $centralArticleCount -Singular 'article'))" },
        [PSCustomObject]@{ Direction = "CompanyToCompany"; OptionMessage = "Move company KB articles to another company KB ($(Format-HuduArticleMoveCount -Count $companyKbCount -Singular 'company' -Plural 'companies'))" }
    ) -message "Choose a move type" -allowNull $false

    $direction = [string]$directionOption.Direction

    $params = @{
        Direction                = $direction
        PreserveFolderPath       = $true
        IncludeFolderDescendants = $true
    }

    $sourceScopes = @()
    $destinationCompany = $null
    $selectedFolders = @()
    $selectedArticles = @()
    $manualArticleIds = @()

    if ($direction -eq "ToCompany") {
        $sourceScopes = @((New-HuduArticleMoveCompanyOption -Central -IncludeCounts))
    } elseif ($direction -eq "ToCentral") {
        $sourceCompany = Select-HuduArticleMoveCompany -Message "Select the source company KB" -RequireKnowledgeBase
        $params.SourceCompanyId = [int]$sourceCompany.Id
        $sourceScopes = @($sourceCompany)
    } else {
        $sourceScopes = @(Select-HuduArticleMoveCompanies -Message "Select a source company KB, or 0 when done" -RequireKnowledgeBase)
        if ($sourceScopes.Count -lt 1) {
            throw "Select at least one source company."
        }
        $params.SourceCompanyIds = @($sourceScopes | ForEach-Object { [int]$_.Id })
    }

    if ($direction -in @("ToCompany", "CompanyToCompany")) {
        $destinationCompany = Select-HuduArticleMoveCompany -Message "Select the destination company KB"
        $params.DestinationCompanyId = [int]$destinationCompany.Id
        if ($direction -eq "CompanyToCompany" -and @($sourceScopes | ForEach-Object { [int]$_.Id }) -contains [int]$destinationCompany.Id) {
            Write-HuduArticleMoveLog "Destination company was also selected as a source. It will be skipped as a source." Yellow
            $sourceScopes = @($sourceScopes | Where-Object { [int]$_.Id -ne [int]$destinationCompany.Id })
            $params.SourceCompanyIds = @($sourceScopes | ForEach-Object { [int]$_.Id })
            if ($sourceScopes.Count -lt 1) {
                throw "No source companies remain after removing the destination company."
            }
        }
    }

    $sourceNames = @($sourceScopes | ForEach-Object { $_.Name }) -join ", "
    $sourceKbSummaries = @($sourceScopes | ForEach-Object {
        Get-HuduArticleMoveKbScopeSummary -CompanyId ([int]$_.Id)
    })
    $sourceArticleCount = 0
    foreach ($summary in @($sourceKbSummaries)) {
        $sourceArticleCount += [int]$summary.ArticleCount
    }

    $sourceFolderOptions = @(New-HuduArticleMoveFolderOptions -Scopes $sourceScopes)
    $sourceModeOptions = [System.Collections.Generic.List[object]]::new()

    if ($sourceArticleCount -gt 0) {
        $sourceModeOptions.Add([PSCustomObject]@{ Mode = "All"; OptionMessage = "Move all articles from the selected source ($(Format-HuduArticleMoveCount -Count $sourceArticleCount -Singular 'article'))" })
    } else {
        Write-HuduArticleMoveLog "No listable articles were found for $sourceNames. You can still type article IDs manually." Yellow
    }

    if ($sourceFolderOptions.Count -gt 0 -and $sourceArticleCount -gt 0) {
        $sourceModeOptions.Add([PSCustomObject]@{ Mode = "Folders"; OptionMessage = "Move all articles in selected folders ($(Format-HuduArticleMoveCount -Count $sourceFolderOptions.Count -Singular 'folder'))" })
    } elseif ($sourceFolderOptions.Count -lt 1) {
        Write-HuduArticleMoveLog "No KB folders were found for $sourceNames. Folder selection will be skipped." Yellow
    } else {
        Write-HuduArticleMoveLog "KB folders exist for $sourceNames, but no articles were found to move from those folders. Folder selection will be skipped." Yellow
    }

    if ($sourceArticleCount -gt 0) {
        $sourceModeOptions.Add([PSCustomObject]@{ Mode = "Articles"; OptionMessage = "Choose individual articles from an alphabetized list ($(Format-HuduArticleMoveCount -Count $sourceArticleCount -Singular 'article'))" })
    }
    $sourceModeOptions.Add([PSCustomObject]@{ Mode = "Manual"; OptionMessage = "Type article IDs manually" })

    $sourceMode = Select-ObjectFromList -objects $sourceModeOptions -message "How would you like to choose source articles?" -allowNull $false

    switch ([string]$sourceMode.Mode) {
        "Folders" {
            $selectedFolders = @(Select-HuduArticleMoveFolders -Scopes $sourceScopes -Message "Select a source folder, or 0 when done")
            if ($selectedFolders.Count -lt 1) {
                throw "Select at least one source folder."
            }
            $params.SourceFolderIds = @($selectedFolders | ForEach-Object { [int]$_.Id })
            $params.IncludeFolderDescendants = Read-HuduArticleMoveYesNo -Prompt "Include child folders too?" -Default $true
        }
        "Articles" {
            $selectedArticles = @(Select-HuduArticleMoveArticles -Scopes $sourceScopes -Message "Select an article, or 0 when done")
            if ($selectedArticles.Count -lt 1) {
                throw "Select at least one article."
            }
            $params.ArticleIds = @($selectedArticles | ForEach-Object { [int]$_.Id })
        }
        "Manual" {
        $articleIds = Read-HuduArticleMoveIdList -Prompt "Article IDs to move, comma-separated"
        if ($articleIds.Count -lt 1) {
            throw "Enter at least one article ID."
        }
        $params.ArticleIds = $articleIds
        $manualArticleIds = $articleIds
        }
    }

    $rootFolder = Read-HuduArticleMoveText -Prompt "Destination root folder name. Leave blank for no extra root"
    if (-not [string]::IsNullOrWhiteSpace($rootFolder)) {
        $params.DestinationRootFolderName = $rootFolder
    }

    $params.PreserveFolderPath = Read-HuduArticleMoveYesNo -Prompt "Preserve the source folder path?" -Default $true

    if ($direction -eq "CompanyToCompany") {
        $params.PrefixWithSourceCompany = Read-HuduArticleMoveYesNo -Prompt "Prefix destination folders with the source company name?" -Default $true
    }

    $maxArticlesText = Read-HuduArticleMoveText -Prompt "Maximum articles to process. Leave blank for no limit"
    if (-not [string]::IsNullOrWhiteSpace($maxArticlesText)) {
        $maxArticles = 0
        if (-not [int]::TryParse($maxArticlesText, [ref]$maxArticles) -or $maxArticles -lt 1) {
            throw "Maximum articles must be a positive number."
        }
        $params.MaxArticles = $maxArticles
    }

    $reportPath = Read-HuduArticleMoveText -Prompt "CSV report path. Leave blank for the default logs folder"
    if (-not [string]::IsNullOrWhiteSpace($reportPath)) {
        $params.ReportPath = $reportPath
    }

    Write-HuduArticleMoveWizardSummary `
        -Params $params `
        -SourceScopes $sourceScopes `
        -DestinationCompany $destinationCompany `
        -SourceMode ([string]$sourceMode.Mode) `
        -SelectedFolders $selectedFolders `
        -SelectedArticles $selectedArticles `
        -ManualArticleIds $manualArticleIds

    if (Read-HuduArticleMoveYesNo -Prompt "Apply real changes now? Choose N for dry-run preview" -Default $false) {
        $params.Apply = $true
    }

    return $params
}

function ConvertTo-HuduArticleMoveKey {
    param ($Value)

    if ($null -eq $Value) { return "" }

    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    $text = ([string]$Value).Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant()
    $text = $text -replace '\p{Mn}', ''
    $text = [System.Web.HttpUtility]::HtmlDecode($text)
    $text = $text -replace '&', ' and '
    $text = $text -replace '[^a-z0-9]+', ' '
    return ($text -replace '\s+', ' ').Trim()
}

function Get-HuduArticleMoveObject {
    param ($Object, [string]$WrapperName)

    if ($null -eq $Object) { return $null }
    if ($WrapperName -and $Object.PSObject.Properties[$WrapperName]) { return $Object.$WrapperName }
    return $Object
}

function Get-HuduArticleMoveArticleObject {
    param ($Article)

    $object = Get-HuduArticleMoveObject -Object $Article -WrapperName "article"
    if ($object -and $object.PSObject.Properties["Article"]) { return $object.Article }
    return $object
}

function Get-HuduArticleMoveCompanyObject {
    param ($Company)

    $object = Get-HuduArticleMoveObject -Object $Company -WrapperName "company"
    if ($object -and $object.PSObject.Properties["Company"]) { return $object.Company }
    return $object
}

function Get-HuduArticleMoveProperty {
    param (
        $Object,
        [string[]]$Names
    )

    if ($null -eq $Object) { return $null }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties[$name]) { return $Object.$name }
    }
    return $null
}

function Get-HuduArticleMoveArticleId {
    param ($Article)

    return Get-HuduArticleMoveProperty -Object (Get-HuduArticleMoveArticleObject $Article) -Names @("id", "Id")
}

function Get-HuduArticleMoveArticleCompanyId {
    param ($Article)

    return Get-HuduArticleMoveProperty -Object (Get-HuduArticleMoveArticleObject $Article) -Names @("company_id", "CompanyId")
}

function Get-HuduArticleMoveFolderId {
    param ($Object)

    $folderId = Get-HuduArticleMoveProperty -Object $Object -Names @("folder_id", "FolderId")
    if ($folderId) { return $folderId }

    $folder = Get-HuduArticleMoveProperty -Object $Object -Names @("folder", "Folder")
    return Get-HuduArticleMoveProperty -Object $folder -Names @("id", "Id")
}

function Get-HuduArticleMoveFolderParentId {
    param ($Folder)

    return Get-HuduArticleMoveProperty -Object $Folder -Names @("parent_folder_id", "ParentFolderId")
}

function Get-HuduArticleMoveFolderCompanyId {
    param ($Folder)

    return Get-HuduArticleMoveProperty -Object $Folder -Names @("company_id", "CompanyId")
}

function Get-HuduArticleMoveFolderName {
    param ($Folder)

    return [string](Get-HuduArticleMoveProperty -Object $Folder -Names @("name", "Name"))
}

function Get-HuduArticleMoveCompanyName {
    param (
        [Parameter(Mandatory = $true)]
        [int]$CompanyId
    )

    if (Get-Command Get-HuduCompanies -ErrorAction SilentlyContinue) {
        try {
            $company = Get-HuduArticleMoveCompanyObject (Get-HuduCompanies -Id $CompanyId)
            $name = [string](Get-HuduArticleMoveProperty -Object $company -Names @("name", "Name"))
            if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }
        } catch {
            Write-HuduArticleMoveLog "Could not resolve company $CompanyId name. Using the ID as the folder prefix. $($_.Exception.Message)" Yellow
        }
    }

    return "Company $CompanyId"
}

function Get-HuduArticleMoveFolderPath {
    param (
        $Folder,

        [Parameter(Mandatory = $true)]
        [hashtable]$FolderById
    )

    if (-not $Folder) { return @() }

    $path = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $current = $Folder

    while ($current) {
        $currentId = [string](Get-HuduArticleMoveProperty -Object $current -Names @("id", "Id"))
        if ($currentId -and -not $seen.Add($currentId)) { break }

        $name = Get-HuduArticleMoveFolderName $current
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $path.Insert(0, $name)
        }

        $parentId = Get-HuduArticleMoveFolderParentId $current
        if (-not $parentId -or -not $FolderById.ContainsKey([string]$parentId)) { break }
        $current = $FolderById[[string]$parentId]
    }

    return @($path)
}

function New-HuduArticleMoveFolderIndex {
    param ($Folders)

    $folderById = @{}
    $childrenByParent = @{}

    foreach ($folder in @($Folders)) {
        $id = [string](Get-HuduArticleMoveProperty -Object $folder -Names @("id", "Id"))
        if ($id) { $folderById[$id] = $folder }

        $parentId = [string](Get-HuduArticleMoveFolderParentId $folder)
        if ([string]::IsNullOrWhiteSpace($parentId)) { $parentId = "" }

        if (-not $childrenByParent.ContainsKey($parentId)) {
            $childrenByParent[$parentId] = [System.Collections.Generic.List[object]]::new()
        }
        $childrenByParent[$parentId].Add($folder)
    }

    [PSCustomObject]@{
        FolderById       = $folderById
        ChildrenByParent = $childrenByParent
    }
}

function Find-HuduArticleMoveChildFolder {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$ChildrenByParent,

        $ParentId,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $parentKey = if ($ParentId) { [string]$ParentId } else { "" }
    if (-not $ChildrenByParent.ContainsKey($parentKey)) { return $null }

    $nameKey = ConvertTo-HuduArticleMoveKey $Name
    return @($ChildrenByParent[$parentKey] | Where-Object {
        (ConvertTo-HuduArticleMoveKey (Get-HuduArticleMoveFolderName $_)) -eq $nameKey
    } | Select-Object -First 1)
}

function Add-HuduArticleMoveFolderToIndex {
    param (
        [Parameter(Mandatory = $true)]
        $Folder,

        [Parameter(Mandatory = $true)]
        [hashtable]$FolderById,

        [Parameter(Mandatory = $true)]
        [hashtable]$ChildrenByParent
    )

    $id = [string](Get-HuduArticleMoveProperty -Object $Folder -Names @("id", "Id"))
    if ($id) { $FolderById[$id] = $Folder }

    $parentId = [string](Get-HuduArticleMoveFolderParentId $Folder)
    if ([string]::IsNullOrWhiteSpace($parentId)) { $parentId = "" }

    if (-not $ChildrenByParent.ContainsKey($parentId)) {
        $ChildrenByParent[$parentId] = [System.Collections.Generic.List[object]]::new()
    }
    $ChildrenByParent[$parentId].Add($Folder)
}

function Ensure-HuduArticleMoveFolderPath {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$DestinationFolderById,

        [Parameter(Mandatory = $true)]
        [hashtable]$DestinationChildrenByParent,

        [int]$DestinationCompanyId = 0,
        [switch]$DryRun
    )

    if (@($Path).Count -lt 1) { return $null }

    $parentId = $null
    $lastFolder = $null
    $pathSoFar = [System.Collections.Generic.List[string]]::new()

    foreach ($folderName in @($Path)) {
        if ([string]::IsNullOrWhiteSpace($folderName)) { continue }
        $pathSoFar.Add($folderName)

        $existing = Find-HuduArticleMoveChildFolder -ChildrenByParent $DestinationChildrenByParent -ParentId $parentId -Name $folderName
        if ($existing) {
            $lastFolder = $existing
            $parentId = Get-HuduArticleMoveProperty -Object $existing -Names @("id", "Id")
            continue
        }

        if ($DryRun) {
            $createdFolder = [PSCustomObject]@{
                id               = "dryrun:$(@($pathSoFar) -join '/')"
                name             = $folderName
                parent_folder_id = $parentId
                company_id       = if ($DestinationCompanyId -gt 0) { $DestinationCompanyId } else { $null }
            }
        } else {
            $newFolderParams = @{ Name = $folderName }
            if ($parentId) { $newFolderParams.ParentFolderId = $parentId }
            if ($DestinationCompanyId -gt 0) { $newFolderParams.CompanyId = $DestinationCompanyId }

            $created = New-HuduFolder @newFolderParams
            $createdFolder = Get-HuduArticleMoveObject -Object $created -WrapperName "folder"
        }

        Add-HuduArticleMoveFolderToIndex -Folder $createdFolder -FolderById $DestinationFolderById -ChildrenByParent $DestinationChildrenByParent
        $lastFolder = $createdFolder
        $parentId = Get-HuduArticleMoveProperty -Object $createdFolder -Names @("id", "Id")
    }

    return $lastFolder
}

function Invoke-HuduArticleMoveRequest {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Get", "Put")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Resource,

        [string]$Body
    )

    if (Get-Command Invoke-HuduRequest -ErrorAction SilentlyContinue) {
        if ($Body) {
            return Invoke-HuduRequest -Method $Method.ToLowerInvariant() -Resource $Resource -Body $Body
        }
        return Invoke-HuduRequest -Method $Method.ToLowerInvariant() -Resource $Resource
    }

    $baseUrl = [string](Get-HuduBaseURL)
    $apiKeyValue = Get-HuduApiKey
    $apiKey = if ($apiKeyValue -is [securestring]) {
        (New-Object PSCredential "user", $apiKeyValue).GetNetworkCredential().Password
    } else {
        [string]$apiKeyValue
    }

    if ([string]::IsNullOrWhiteSpace($baseUrl) -or [string]::IsNullOrWhiteSpace($apiKey)) {
        throw "Hudu base URL/API key are not initialized."
    }

    $params = @{
        Method      = $Method
        Uri         = "{0}{1}" -f $baseUrl.TrimEnd('/'), $Resource
        Headers     = @{ "x-api-key" = $apiKey }
        ErrorAction = "Stop"
    }

    if ($Body) {
        $params.Body = $Body
        $params.ContentType = "application/json"
    }

    Invoke-RestMethod @params
}

function Set-HuduArticleMoveArticle {
    param (
        [Parameter(Mandatory = $true)]
        [int]$ArticleId,

        [int]$DestinationCompanyId = 0,
        $FolderId
    )

    $object = Invoke-HuduArticleMoveRequest -Method Get -Resource "/api/v1/articles/$ArticleId"
    $article = Get-HuduArticleMoveArticleObject $object
    if (-not $article) { throw "Hudu article $ArticleId was not returned." }

    $article.company_id = if ($DestinationCompanyId -gt 0) { $DestinationCompanyId } else { $null }
    $article.folder_id = if ($FolderId) { $FolderId } else { $null }

    $body = @{ article = $article } | ConvertTo-Json -Depth 20
    Invoke-HuduArticleMoveRequest -Method Put -Resource "/api/v1/articles/$ArticleId" -Body $body
}

function Assert-HuduArticleMovePrerequisites {
    param (
        [bool]$WillApply,
        [bool]$MayCreateFolders
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($commandName in @("Get-HuduArticles", "Get-HuduFolders")) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            $missing.Add($commandName)
        }
    }

    if ($WillApply -and $MayCreateFolders -and -not (Get-Command New-HuduFolder -ErrorAction SilentlyContinue)) {
        $missing.Add("New-HuduFolder")
    }

    if ($WillApply -and -not (Get-Command Invoke-HuduRequest -ErrorAction SilentlyContinue)) {
        foreach ($commandName in @("Get-HuduBaseURL", "Get-HuduApiKey")) {
            if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
                $missing.Add($commandName)
            }
        }
    }

    if ($missing.Count -gt 0) {
        throw "Missing required Hudu command(s): $(@($missing | Select-Object -Unique) -join ', '). Connect/load the Hudu module before running this tool."
    }
}

function Resolve-HuduArticleMoveReportPath {
    param (
        [string]$ReportPath,
        [string]$Direction
    )

    $root = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $PSScriptRoot
    } else {
        (Get-Location).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        if ([System.IO.Path]::IsPathRooted($ReportPath)) {
            return [System.IO.Path]::GetFullPath($ReportPath)
        }
        return [System.IO.Path]::GetFullPath((Join-Path $root $ReportPath))
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName = switch ($Direction) {
        "ToCompany" { "hudu-article-move-central-to-company-$stamp.csv" }
        "CompanyToCompany" { "hudu-article-move-company-to-company-$stamp.csv" }
        default { "hudu-article-move-company-to-central-$stamp.csv" }
    }

    return (Join-Path (Join-Path $root "logs") $fileName)
}

function Move-HuduArticleTree {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("ToCentral", "ToCompany", "CompanyToCompany")]
        [string]$Direction,

        [int]$SourceCompanyId,
        [int[]]$SourceCompanyIds,
        [int]$DestinationCompanyId,
        [int[]]$ArticleIds,
        [int[]]$SourceFolderIds,

        [string]$DestinationRootFolderName = "",
        [bool]$PreserveFolderPath = $true,
        [bool]$IncludeFolderDescendants = $true,
        [switch]$PrefixWithSourceCompany,

        [int]$MaxArticles = 0,
        [string]$ReportPath,

        [switch]$Apply,
        [switch]$Force,
        [switch]$PassThru
    )

    if ($MaxArticles -lt 0) { throw "MaxArticles cannot be negative." }
    if ($SourceCompanyId -lt 0 -or $DestinationCompanyId -lt 0) { throw "Company IDs cannot be negative." }

    $effectiveArticleIds = @($ArticleIds | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    $effectiveSourceFolderIds = @($SourceFolderIds | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    $effectiveSourceCompanyIds = @(
        if ($SourceCompanyIds) {
            $SourceCompanyIds | Where-Object { $_ -gt 0 }
        } elseif ($SourceCompanyId -gt 0) {
            $SourceCompanyId
        }
    ) | Select-Object -Unique

    if ($Direction -eq "ToCentral" -and $SourceCompanyId -lt 1 -and $effectiveArticleIds.Count -lt 1) {
        throw "For ToCentral moves, provide -SourceCompanyId or -ArticleIds."
    }

    if ($Direction -in @("ToCompany", "CompanyToCompany") -and $DestinationCompanyId -lt 1) {
        throw "For moves into a company KB, provide -DestinationCompanyId."
    }

    if ($Direction -eq "CompanyToCompany" -and $effectiveSourceCompanyIds.Count -lt 1 -and $effectiveArticleIds.Count -lt 1) {
        throw "For CompanyToCompany moves, provide -SourceCompanyIds or -ArticleIds."
    }

    if ($Direction -eq "CompanyToCompany" -and $effectiveSourceCompanyIds -contains $DestinationCompanyId) {
        Write-HuduArticleMoveLog "Source list includes destination company $DestinationCompanyId. That source will be skipped." Yellow
        $effectiveSourceCompanyIds = @($effectiveSourceCompanyIds | Where-Object { $_ -ne $DestinationCompanyId })
    }

    if ($Direction -eq "CompanyToCompany" -and $effectiveSourceCompanyIds.Count -lt 1 -and $effectiveArticleIds.Count -lt 1) {
        throw "No source company KBs remain after filtering out the destination company."
    }

    $dryRun = -not $Apply -or $WhatIfPreference
    $effectiveReportPath = Resolve-HuduArticleMoveReportPath -ReportPath $ReportPath -Direction $Direction
    $reportDir = Split-Path -Parent $effectiveReportPath
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $reportDir -Force
    }

    Assert-HuduArticleMovePrerequisites `
        -WillApply:(-not $dryRun) `
        -MayCreateFolders:($PreserveFolderPath -or -not [string]::IsNullOrWhiteSpace($DestinationRootFolderName))

    $sourceScopeName = switch ($Direction) {
        "ToCompany" { "central KB" }
        "CompanyToCompany" { "$($effectiveSourceCompanyIds.Count) company KB(s)" }
        default {
            if ($SourceCompanyId -gt 0) { "company KB $SourceCompanyId" } else { "selected articles" }
        }
    }

    $destinationScopeName = if ($Direction -in @("ToCompany", "CompanyToCompany")) {
        "company KB $DestinationCompanyId"
    } else {
        "central KB"
    }

    Write-HuduArticleMoveLog "Planning Hudu article move: $sourceScopeName -> $destinationScopeName" Cyan
    Write-HuduArticleMoveLog "DryRun=$dryRun; PreserveFolderPath=$PreserveFolderPath; DestinationRoot='$DestinationRootFolderName'; Report='$effectiveReportPath'." DarkGray

    $destinationFolders = if ($Direction -in @("ToCompany", "CompanyToCompany")) {
        @(Get-HuduFolders -CompanyId $DestinationCompanyId)
    } else {
        @(Get-HuduFolders | Where-Object { $null -eq (Get-HuduArticleMoveFolderCompanyId $_) })
    }
    $destinationIndex = New-HuduArticleMoveFolderIndex -Folders $destinationFolders

    $sourceContexts = [System.Collections.Generic.List[object]]::new()

    if ($effectiveArticleIds.Count -gt 0) {
        $articles = @($effectiveArticleIds | ForEach-Object {
            Get-HuduArticleMoveArticleObject (Get-HuduArticles -Id $_)
        })

        $articlesByCompany = @($articles | Group-Object {
            $companyId = Get-HuduArticleMoveArticleCompanyId $_
            if ($null -eq $companyId) { "" } else { [string]$companyId }
        })

        foreach ($group in @($articlesByCompany)) {
            $sourceCompanyIdForGroup = if ([string]::IsNullOrWhiteSpace($group.Name)) { 0 } else { [int]$group.Name }
            $sourceFolders = if ($sourceCompanyIdForGroup -gt 0) {
                @(Get-HuduFolders -CompanyId $sourceCompanyIdForGroup)
            } else {
                @(Get-HuduFolders | Where-Object { $null -eq (Get-HuduArticleMoveFolderCompanyId $_) })
            }

            $sourceContexts.Add([PSCustomObject]@{
                SourceCompanyId       = $sourceCompanyIdForGroup
                SourceCompanyRootName = if ($sourceCompanyIdForGroup -gt 0) { "$(Get-HuduArticleMoveCompanyName -CompanyId $sourceCompanyIdForGroup) ($sourceCompanyIdForGroup)" } else { "" }
                SourceIndex           = New-HuduArticleMoveFolderIndex -Folders $sourceFolders
                Articles              = @($group.Group)
            })
        }
    } elseif ($Direction -eq "ToCompany") {
        $sourceFolders = @(Get-HuduFolders | Where-Object { $null -eq (Get-HuduArticleMoveFolderCompanyId $_) })
        $sourceContexts.Add([PSCustomObject]@{
            SourceCompanyId       = 0
            SourceCompanyRootName = ""
            SourceIndex           = New-HuduArticleMoveFolderIndex -Folders $sourceFolders
            Articles              = @(Get-HuduArticles | ForEach-Object { Get-HuduArticleMoveArticleObject $_ } | Where-Object {
                $null -eq (Get-HuduArticleMoveArticleCompanyId $_)
            })
        })
    } elseif ($Direction -eq "CompanyToCompany") {
        foreach ($sourceCompany in @($effectiveSourceCompanyIds)) {
            Write-HuduArticleMoveLog "Loading company KB $sourceCompany..." DarkCyan
            $sourceFolders = @(Get-HuduFolders -CompanyId $sourceCompany)
            $sourceContexts.Add([PSCustomObject]@{
                SourceCompanyId       = $sourceCompany
                SourceCompanyRootName = "$(Get-HuduArticleMoveCompanyName -CompanyId $sourceCompany) ($sourceCompany)"
                SourceIndex           = New-HuduArticleMoveFolderIndex -Folders $sourceFolders
                Articles              = @(Get-HuduArticles -CompanyId $sourceCompany | ForEach-Object { Get-HuduArticleMoveArticleObject $_ })
            })
        }
    } else {
        $sourceFolders = @(Get-HuduFolders -CompanyId $SourceCompanyId)
        $sourceContexts.Add([PSCustomObject]@{
            SourceCompanyId       = $SourceCompanyId
            SourceCompanyRootName = "$(Get-HuduArticleMoveCompanyName -CompanyId $SourceCompanyId) ($SourceCompanyId)"
            SourceIndex           = New-HuduArticleMoveFolderIndex -Folders $sourceFolders
            Articles              = @(Get-HuduArticles -CompanyId $SourceCompanyId | ForEach-Object { Get-HuduArticleMoveArticleObject $_ })
        })
    }

    $totalArticles = 0
    foreach ($context in @($sourceContexts)) {
        $loadedArticleCount = @($context.Articles).Count
        $sourceLabel = if ([int]$context.SourceCompanyId -gt 0) { "company KB $($context.SourceCompanyId)" } else { "central KB" }
        Write-HuduArticleMoveLog "Loaded $loadedArticleCount article(s) from $sourceLabel before filters." DarkGray

        if ($effectiveSourceFolderIds.Count -gt 0) {
            $folderIdsToInclude = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($folderId in @($effectiveSourceFolderIds)) {
                [void]$folderIdsToInclude.Add([string]$folderId)
                if ($IncludeFolderDescendants) {
                    $queue = [System.Collections.Generic.Queue[string]]::new()
                    $queue.Enqueue([string]$folderId)
                    while ($queue.Count -gt 0) {
                        $currentId = $queue.Dequeue()
                        if (-not $context.SourceIndex.ChildrenByParent.ContainsKey($currentId)) { continue }
                        foreach ($child in @($context.SourceIndex.ChildrenByParent[$currentId])) {
                            $childId = [string](Get-HuduArticleMoveProperty -Object $child -Names @("id", "Id"))
                            if ($childId -and $folderIdsToInclude.Add($childId)) {
                                $queue.Enqueue($childId)
                            }
                        }
                    }
                }
            }

            $context.Articles = @($context.Articles | Where-Object {
                $folderId = Get-HuduArticleMoveFolderId $_
                $folderId -and $folderIdsToInclude.Contains([string]$folderId)
            })
        }

        $totalArticles += @($context.Articles).Count
    }

    if ($MaxArticles -gt 0 -and $totalArticles -gt $MaxArticles) {
        $remaining = $MaxArticles
        foreach ($context in @($sourceContexts)) {
            if ($remaining -le 0) {
                $context.Articles = @()
                continue
            }

            $context.Articles = @($context.Articles | Select-Object -First $remaining)
            $remaining -= @($context.Articles).Count
        }
        $totalArticles = $MaxArticles
    }

    Write-HuduArticleMoveLog "Selected $totalArticles article(s) for this run." Cyan

    if (-not $dryRun -and -not $Force) {
        $target = "$totalArticles article(s): $sourceScopeName -> $destinationScopeName"
        if (-not $PSCmdlet.ShouldProcess($target, "Move Hudu articles")) {
            Write-HuduArticleMoveLog "Live move cancelled before any article changes." Yellow
            return
        }
    } elseif ($dryRun) {
        Write-HuduArticleMoveLog "Dry-run mode: no Hudu articles or folders will be changed." Yellow
    }

    $report = [System.Collections.Generic.List[object]]::new()
    $moved = 0
    $dryRunMoves = 0
    $failed = 0
    $skipped = 0
    $articleIndex = 0
    $startedAt = Get-Date

    foreach ($context in @($sourceContexts)) {
        $sourceIndex = $context.SourceIndex
        $contextArticles = @($context.Articles)

        if ($contextArticles.Count -lt 1) {
            $skipped++
            $report.Add([PSCustomObject]@{
                Status               = "NoArticles"
                Direction            = $Direction
                ArticleId            = $null
                ArticleName          = $null
                SourceCompanyId      = if ([int]$context.SourceCompanyId -gt 0) { [int]$context.SourceCompanyId } else { $null }
                SourceFolderId       = $null
                SourceFolderPath     = $null
                DestinationCompanyId = if ($DestinationCompanyId -gt 0) { $DestinationCompanyId } else { $null }
                DestinationFolderId  = $null
                DestinationPath      = $null
                DryRun               = $dryRun
                Error                = "No articles were selected for this source."
            })
            continue
        }

        foreach ($article in @($contextArticles)) {
            $articleIndex++
            $articleId = Get-HuduArticleMoveArticleId $article
            $articleName = [string](Get-HuduArticleMoveProperty -Object $article -Names @("name", "Name", "title", "Title"))
            if ([string]::IsNullOrWhiteSpace($articleName)) { $articleName = "Untitled Article" }

            $sourceCompanyId = [int]$context.SourceCompanyId
            $sourceFolderId = Get-HuduArticleMoveFolderId $article
            $sourceFolder = if ($sourceFolderId -and $sourceIndex.FolderById.ContainsKey([string]$sourceFolderId)) {
                $sourceIndex.FolderById[[string]$sourceFolderId]
            } else {
                $null
            }

            $sourcePath = @(Get-HuduArticleMoveFolderPath -Folder $sourceFolder -FolderById $sourceIndex.FolderById)
            $destinationPath = [System.Collections.Generic.List[string]]::new()
            if (-not [string]::IsNullOrWhiteSpace($DestinationRootFolderName)) {
                $destinationPath.Add($DestinationRootFolderName)
            }
            if ($Direction -eq "CompanyToCompany" -and $PrefixWithSourceCompany -and -not [string]::IsNullOrWhiteSpace([string]$context.SourceCompanyRootName)) {
                $destinationPath.Add([string]$context.SourceCompanyRootName)
            }
            if ($PreserveFolderPath) {
                foreach ($part in @($sourcePath)) { $destinationPath.Add($part) }
            }

            $destinationFolderId = $null
            $status = $null
            $errorMessage = $null

            try {
                if (-not $articleId) {
                    throw "Article ID was not detected."
                }

                if ($destinationPath.Count -gt 0) {
                    $destinationCompanyForFolder = 0
                    if ($Direction -in @("ToCompany", "CompanyToCompany")) { $destinationCompanyForFolder = $DestinationCompanyId }

                    $destinationFolder = Ensure-HuduArticleMoveFolderPath `
                        -Path $destinationPath.ToArray() `
                        -DestinationFolderById $destinationIndex.FolderById `
                        -DestinationChildrenByParent $destinationIndex.ChildrenByParent `
                        -DestinationCompanyId $destinationCompanyForFolder `
                        -DryRun:$dryRun
                    $destinationFolderId = Get-HuduArticleMoveProperty -Object $destinationFolder -Names @("id", "Id")
                }

                if ($dryRun) {
                    $status = "DryRunMove"
                    $dryRunMoves++
                } else {
                    $destinationCompanyForArticle = 0
                    if ($Direction -in @("ToCompany", "CompanyToCompany")) { $destinationCompanyForArticle = $DestinationCompanyId }

                    Set-HuduArticleMoveArticle `
                        -ArticleId $articleId `
                        -DestinationCompanyId $destinationCompanyForArticle `
                        -FolderId $destinationFolderId | Out-Null
                    $status = "Moved"
                    $moved++
                    Write-HuduArticleMoveLog "Moved $articleIndex/$totalArticles '$articleName' -> $destinationScopeName '$(@($destinationPath) -join '\')'." Green
                }
            } catch {
                $status = "Failed"
                $errorMessage = $_.Exception.Message
                $failed++
                Write-HuduArticleMoveLog "Failed '$articleName' ($articleId): $errorMessage" Red
            }

            if (-not $status) {
                $status = "Skipped"
                $skipped++
            }

            $report.Add([PSCustomObject]@{
                Status               = $status
                Direction            = $Direction
                ArticleId            = $articleId
                ArticleName          = $articleName
                SourceCompanyId      = if ($sourceCompanyId -gt 0) { $sourceCompanyId } else { $null }
                SourceFolderId       = $sourceFolderId
                SourceFolderPath     = (@($sourcePath) -join '\')
                DestinationCompanyId = if ($DestinationCompanyId -gt 0) { $DestinationCompanyId } else { $null }
                DestinationFolderId  = $destinationFolderId
                DestinationPath      = (@($destinationPath) -join '\')
                DryRun               = $dryRun
                Error                = $errorMessage
            })
        }
    }

    $report | Export-Csv -LiteralPath $effectiveReportPath -NoTypeInformation -Encoding UTF8

    $summary = [PSCustomObject]@{
        Direction   = $Direction
        Source      = $sourceScopeName
        Destination = $destinationScopeName
        Selected    = $totalArticles
        Moved       = $moved
        DryRunMoves = $dryRunMoves
        Skipped     = $skipped
        Failed      = $failed
        DryRun      = $dryRun
        ReportPath  = $effectiveReportPath
        StartedAt   = $startedAt
        CompletedAt = Get-Date
    }

    Write-HuduArticleMoveLog "Complete: $moved moved, $dryRunMoves dry-run move(s), $skipped skipped, $failed failed." Cyan
    Write-HuduArticleMoveLog "Report: $effectiveReportPath" Cyan

    if ($PassThru) { return $summary }
}

Set-Alias -Name Move-ArticleTree -Value Move-HuduArticleTree -Scope Script

function Set-HuduInstance {
    param(
        [string]$HuduBaseURL,
        [string]$HuduAPIKey
    )
 
    while ([string]::IsNullOrWhiteSpace($HuduBaseURL)) {
        $HuduBaseURL = (Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g. https://myinstance.huducloud.com)').Trim()
    }

    $HuduBaseURL = $HuduBaseURL.Trim()
    $HuduBaseURL = $HuduBaseURL -replace '[\\/]+$', ''
    $HuduBaseURL = $HuduBaseURL -replace '^(?!https?://)', 'https://'
 
    while ([string]::IsNullOrWhiteSpace($HuduAPIKey) -or $HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API key from $HuduBaseURL/admin/api_keys" -MaskInput).Trim()
 
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
 
    $script:HuduBaseURL = $HuduBaseURL
    $script:HuduAPIKey = $HuduAPIKey
    $global:HuduBaseURL = $HuduBaseURL
    $global:HuduAPIKey = $HuduAPIKey

    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
        [bool]$use_hudu_fork = $true
    )

    Set-HuduModuleInitialized -HAPImodulePath $HAPImodulePath -use_hudu_fork $use_hudu_fork
}

function Get-HuduArticleMoveVersionValue {
    param ($AppInfo)

    if ($null -eq $AppInfo) { return $null }

    foreach ($name in @("version", "Version")) {
        if ($AppInfo.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$AppInfo.$name)) {
            return [string]$AppInfo.$name
        }
    }

    foreach ($wrapper in @("app_info", "AppInfo", "data", "Data")) {
        if ($AppInfo.PSObject.Properties[$wrapper]) {
            $nestedVersion = Get-HuduArticleMoveVersionValue -AppInfo $AppInfo.$wrapper
            if (-not [string]::IsNullOrWhiteSpace($nestedVersion)) { return $nestedVersion }
        }
    }

    return $null
}

function Get-HuduVersionCompatible {
    param (
        [string]$requiredVersion = "2.46.0"
    )

    $requiredHuduVersion = [version]$requiredVersion
    Write-HuduArticleMoveLog "Required Hudu version: $requiredHuduVersion" Blue

    try {
        $huduAppInfo = Get-HuduAppInfo -ErrorAction Stop
        $currentHuduVersionText = Get-HuduArticleMoveVersionValue -AppInfo $huduAppInfo

        if ([string]::IsNullOrWhiteSpace($currentHuduVersionText)) {
            throw "Get-HuduAppInfo did not return a readable version."
        }

        $currentHuduVersion = [version]$currentHuduVersionText
        if ($currentHuduVersion -lt $requiredHuduVersion) {
            throw "This script requires at least Hudu version $requiredHuduVersion and cannot run with version $currentHuduVersion. Please update Hudu."
        }

        Write-HuduArticleMoveLog "Hudu version $currentHuduVersion is compatible." Green
        return $currentHuduVersion
    } catch {
        $baseUrl = try { Get-HuduBaseURL } catch { "<unknown Hudu URL>" }
        throw "Error checking Hudu version for $baseUrl. $($_.Exception.Message)"
    }
}

function Get-HuduArticleMoveExistingVariable {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($scope in @("Script", "Global")) {
        foreach ($name in $Names) {
            $value = Get-Variable -Name $name -Scope $scope -ValueOnly -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return $value
            }
        }
    }

    return $null
}
 
function Set-HuduModuleInitialized {
    param (
            [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
            [bool]$use_hudu_fork = $true,
            [string]$HuduApiRepositoryUrl = $($env:HUDUAPI_REPOSITORY_URL ?? "https://github.com/Hudu-Technologies-Inc/HuduAPI.git"),
            [string]$HuduApiBranch = $($env:HUDUAPI_REPOSITORY_BRANCH ?? "master"),
            [string]$HuduApiZipUrl = $env:HUDUAPI_ZIP_URL,
            [string]$BundledHuduApiZipPath = (
                Join-Path (
                    $(if ($PSScriptRoot) { $PSScriptRoot } else { (Resolve-Path .).Path })
                ) 'HAPI.zip'
            )
        )
    $AllowHuduGalleryFallback = $false
 
    function Test-HuduApiModuleLayout {
        param([Parameter(Mandatory)][string]$ModulePath)
 
        if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
            return $false
        }
 
        $moduleDirectory = Split-Path -Path $ModulePath -Parent
        return (
            (Test-Path -LiteralPath (Join-Path $moduleDirectory "Public") -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $moduleDirectory "Private") -PathType Container)
        )
    }
 
    function Get-GitHubRepositoryParts {
        param([Parameter(Mandatory)][string]$RepositoryUrl)
 
        if ($RepositoryUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$') {
            return $null
        }
 
        [PSCustomObject]@{
            Owner = $matches.owner
            Repo  = ($matches.repo -replace '\.git$', '')
        }
    }
 
    function New-HuduApiStagingRoot {
        $tempRoot = Join-Path $env:TEMP "HuduAPI-Fork-$([guid]::NewGuid().Guid)"
        New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction Stop | Out-Null
        return (Join-Path $tempRoot "HuduAPI")
    }
 
    function Unblock-HuduApiPath {
        param([Parameter(Mandatory)][string]$Path)
 
        try {
            if (Test-Path -LiteralPath $Path) {
                Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                    Unblock-File -ErrorAction SilentlyContinue
                Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
            }
        } catch {}
    }
 
    function Expand-HuduApiZipToStaging {
        param(
            [Parameter(Mandatory)][string]$ZipPath,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )
 
        $stagingParent = Split-Path -Path $StagingRepoRoot -Parent
        $extractRoot = Join-Path $stagingParent "zip-extract"
 
        Unblock-HuduApiPath -Path $ZipPath
        Expand-Archive -Path $ZipPath -DestinationPath $extractRoot -Force -ErrorAction Stop
        Unblock-HuduApiPath -Path $extractRoot
 
        $candidateRoots = @((Get-Item -LiteralPath $extractRoot -ErrorAction Stop))
        $candidateRoots += @(Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse -ErrorAction Stop)
        $extracted = $candidateRoots |
            Where-Object { Test-HuduApiModuleLayout -ModulePath (Join-Path $_.FullName "HuduAPI\HuduAPI.psm1") } |
            Select-Object -First 1
 
        if (-not $extracted) {
            throw "Archive did not contain a complete HuduAPI module layout."
        }
 
        Move-Item -LiteralPath $extracted.FullName -Destination $StagingRepoRoot -Force -ErrorAction Stop
    }
 
    function Install-HuduApiForkSamuraiStyle {
        param(
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )
 
        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) {
            throw "git was not found on this machine."
        }
 
        $oldGitPrompt = $env:GIT_TERMINAL_PROMPT
        $oldGitSshCommand = $env:GIT_SSH_COMMAND
        try {
            $env:GIT_TERMINAL_PROMPT = "0"
            $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes"
            & $git.Source clone --depth 1 --branch $Branch $RepositoryUrl $StagingRepoRoot 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "git clone exited with code $LASTEXITCODE."
            }
        } finally {
            $env:GIT_TERMINAL_PROMPT = $oldGitPrompt
            $env:GIT_SSH_COMMAND = $oldGitSshCommand
        }
    }
 
    function Install-HuduApiForkAshigaruStyle {
        param(
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [Parameter(Mandatory)][string]$StagingRepoRoot,
            [string]$ZipUrl
        )
 
        if ([string]::IsNullOrWhiteSpace($ZipUrl)) {
            $repoParts = Get-GitHubRepositoryParts -RepositoryUrl $RepositoryUrl
            if (-not $repoParts) {
                throw "Ashigaru-Warrior-Style install only supports github.com repository URLs unless HuduApiZipUrl is set."
            }
            $ZipUrl = "https://codeload.github.com/$($repoParts.Owner)/$($repoParts.Repo)/zip/refs/heads/$Branch"
        }
 
        $stagingParent = Split-Path -Path $StagingRepoRoot -Parent
        $zip = Join-Path $stagingParent "HuduAPI.zip"
        $headers = @{ "User-Agent" = "ITGlue-Hudu-Migration" }
 
        Invoke-WebRequest -Uri $ZipUrl -Headers $headers -OutFile $zip -ErrorAction Stop | Out-Null
        Expand-HuduApiZipToStaging -ZipPath $zip -StagingRepoRoot $StagingRepoRoot
    }
 
    function Install-HuduApiForkBundledZipStyle {
        param(
            [Parameter(Mandatory)][string]$ZipPath,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )
 
        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
            throw "Bundled HuduAPI zip was not found at $ZipPath."
        }
 
        Expand-HuduApiZipToStaging -ZipPath $ZipPath -StagingRepoRoot $StagingRepoRoot
    }
 
    function Install-HuduApiFork {
        param(
            [Parameter(Mandatory)][string]$ModulePath,
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [string]$ZipUrl,
            [string]$BundledZipPath
        )
 
        $targetRepoRoot = Split-Path -Path (Split-Path -Path $ModulePath -Parent) -Parent
        $targetParent = Split-Path -Path $targetRepoRoot -Parent
        $stagingRepoRoot = $null
        $successfulMethod = $null
 
        $installMethods = @(
            @{
                Name = "Ashigaru-Warrior-Style"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl)
                    Install-HuduApiForkAshigaruStyle -RepositoryUrl $repoUrl -Branch $branchName -StagingRepoRoot $stagingRoot -ZipUrl $directZipUrl
                }
            },
            @{
                Name = "Samurai-Style"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl)
                    Install-HuduApiForkSamuraiStyle -RepositoryUrl $repoUrl -Branch $branchName -StagingRepoRoot $stagingRoot
                }
            },
            @{
                Name = "Bundled-Zip"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl, $localZipPath)
                    Install-HuduApiForkBundledZipStyle -ZipPath $localZipPath -StagingRepoRoot $stagingRoot
                }
            }
        )
 
        foreach ($method in $installMethods) {
            $stagingRepoRoot = New-HuduApiStagingRoot
            $stagingContainer = Split-Path -Path $stagingRepoRoot -Parent
 
            try {
                $methodSource = if ($method.Name -eq "Bundled-Zip") { $BundledZipPath } else { "$RepositoryUrl ($Branch)" }
                Write-Host "Trying HuduAPI fork install via $($method.Name) from $methodSource." -ForegroundColor Cyan
                & $method.Script $RepositoryUrl $Branch $stagingRepoRoot $ZipUrl $BundledZipPath
 
                $stagedModulePath = Join-Path $stagingRepoRoot "HuduAPI\HuduAPI.psm1"
                if (-not (Test-HuduApiModuleLayout -ModulePath $stagedModulePath)) {
                    throw "Downloaded fork did not include a complete HuduAPI module layout."
                }
 
                $successfulMethod = $method.Name
                break
            } catch {
                Write-Warning "$($method.Name) HuduAPI fork install failed: $($_.Exception.Message)"
                if (Test-Path -LiteralPath $stagingContainer) {
                    Remove-Item -LiteralPath $stagingContainer -Recurse -Force -ErrorAction SilentlyContinue
                }
                $stagingRepoRoot = $null
            }
        }
 
        if (-not $successfulMethod) {
            throw "Unable to install HuduAPI fork from $RepositoryUrl ($Branch)."
        }
 
        New-Item -ItemType Directory -Path $targetParent -Force -ErrorAction Stop | Out-Null
        if (Test-Path -LiteralPath $targetRepoRoot) {
            $backupPath = "$targetRepoRoot.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
            Move-Item -LiteralPath $targetRepoRoot -Destination $backupPath -Force -ErrorAction Stop
            Write-Warning "Existing incomplete HuduAPI path was moved to $backupPath."
        }
 
        $stagingGitPath = Join-Path $stagingRepoRoot ".git"
        if (Test-Path -LiteralPath $stagingGitPath) {
            Remove-Item -LiteralPath $stagingGitPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Unblock-HuduApiPath -Path $stagingRepoRoot
 
        $stagingContainer = Split-Path -Path $stagingRepoRoot -Parent
        New-Item -ItemType Directory -Path $targetRepoRoot -Force -ErrorAction Stop | Out-Null
        Get-ChildItem -LiteralPath $stagingRepoRoot -Force -ErrorAction Stop |
            Copy-Item -Destination $targetRepoRoot -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $stagingContainer) {
            Remove-Item -LiteralPath $stagingContainer -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Installed HuduAPI fork via $successfulMethod to $targetRepoRoot." -ForegroundColor Green
    }
 
    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
        Write-Host "Process execution policy set to Bypass for this PowerShell session." -ForegroundColor DarkGray
    } catch {
        Write-Warning "Could not set process execution policy to Bypass: $($_.Exception.Message)"
    }
 
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warning "Could not force TLS 1.2 for this PowerShell session: $($_.Exception.Message)"
    }
    $ProgressPreference = 'SilentlyContinue'
 
    if ([string]::IsNullOrWhiteSpace($BundledHuduApiZipPath) -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $BundledHuduApiZipPath = Join-Path $repoRoot "ExternalModules\HuduAPI.zip"
    }
 
    if ($true -eq $use_hudu_fork) {
        if (-not (Test-HuduApiModuleLayout -ModulePath $HAPImodulePath)) {
            Write-Host "Using latest $HuduApiBranch branch of HuduAPI fork." -ForegroundColor Cyan
            Install-HuduApiFork -ModulePath $HAPImodulePath -RepositoryUrl $HuduApiRepositoryUrl -Branch $HuduApiBranch -ZipUrl $HuduApiZipUrl -BundledZipPath $BundledHuduApiZipPath
        }
    } else {
        Write-Host "HuduAPI fork loading is disabled. PSGallery will only be used if AllowHuduGalleryFallback is true."
    }
 
    Remove-Module HuduAPI -Force -ErrorAction SilentlyContinue
    if (Test-HuduApiModuleLayout -ModulePath $HAPImodulePath) {
        $huduApiManifestPath = [System.IO.Path]::ChangeExtension($HAPImodulePath, ".psd1")
        $huduApiImportPath = if (Test-Path -LiteralPath $huduApiManifestPath -PathType Leaf) { $huduApiManifestPath } else { $HAPImodulePath }
        Import-Module $huduApiImportPath -Force -ErrorAction Stop
        Write-Host "Module imported from $huduApiImportPath"
    } elseif (-not $AllowHuduGalleryFallback) {
        write-host "Sorry, it seems we weren't able to load the Hudu-Fork of HuduAPI module, which is required for the latest features that this fork provides."
        write-host "You can manually download this project https://github.com/Hudu-Technologies-Inc/HuduAPI and extract it to Documents/GitHub folder."
        throw "HuduAPI fork was requested, but no complete fork module was available at $HAPImodulePath. PSGallery fallback is disabled."
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'3.1.1') {
        Import-Module HuduAPI -ErrorAction Stop
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 3.1.1 -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module HuduAPI -ErrorAction Stop
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}
function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSversion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Version
    Write-Host "Required PowerShell version: $RequiredPSversion" -ForegroundColor Blue

    if ($currentPSVersion -lt $RequiredPSversion) {
        Write-Host "PowerShell $RequiredPSversion or higher is required. You have $currentPSVersion." -ForegroundColor Red
        return $false
    } else {
        return $true
    }
}
function Initialize-HuduArticleMoveEnvironment {
    if (-not (Get-PSVersionCompatible)) {
        throw "Incompatible PowerShell version. Exiting script."
    }
    Write-HuduArticleMoveLog "PowerShell version is compatible." Green

    Get-HuduModule

    $resolvedHuduBaseUrl = Get-HuduArticleMoveExistingVariable -Names @("HuduBaseURL", "HuduBaseUrl", "huduBaseurl")
    $resolvedHuduApiKey = Get-HuduArticleMoveExistingVariable -Names @("HuduAPIKey", "HuduApiKey", "huduApikey")

    Set-HuduInstance -HuduBaseURL $resolvedHuduBaseUrl -HuduAPIKey $resolvedHuduApiKey
    Get-HuduVersionCompatible | Out-Null
}

$scriptParameters = @{}
foreach ($key in $PSBoundParameters.Keys) {
    if ($key -notin @("Wizard", "SkipHuduInitialization")) {
        $scriptParameters[$key] = $PSBoundParameters[$key]
    }
}

if ($PSBoundParameters.Count -eq 0) {
    Show-HuduArticleMoveHelp
    return
}

if (-not $SkipHuduInitialization) {
    Initialize-HuduArticleMoveEnvironment
}

if ($Wizard) {
    $wizardParameters = Start-HuduArticleMoveWizard
    if ($null -eq $wizardParameters) { return }
    Move-HuduArticleTree @wizardParameters
    return
}

if (-not $scriptParameters.ContainsKey("Direction")) {
    throw "Provide -Direction ToCentral, -Direction ToCompany, -Direction CompanyToCompany, or run -Wizard."
}

Move-HuduArticleTree @scriptParameters
