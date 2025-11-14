$HuduBaseUrl = $HuduBaseUrl ?? $(read-host "please enter your Hudu instance url")
$HuduApikey = $HuduApikey ?? $(read-host "please enter your Hudu instance api key")
clear-host
function Unset-Vars {
  param(
    [string[]]$Names,
    [ValidateSet('Local','Script','Global','Private')]
    [string[]]$Scopes = @('Local','Script')
  )
  foreach ($s in $Scopes) {foreach ($n in $Names) {Remove-Variable -Name $n -Scope $s -Force -ErrorAction SilentlyContinue}}
}
function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
        [bool]$use_hudu_fork = $false
        )

    if ($true -eq $use_hudu_fork) {
        if (-not $(Test-Path $HAPImodulePath)) {
            $dst = Split-Path -Path (Split-Path -Path $HAPImodulePath -Parent) -Parent
            Write-Host "Using Lastest Master Branch of Hudu Fork for HuduAPI"
            $zip = "$env:TEMP\huduapi.zip"
            Invoke-WebRequest -Uri "https://github.com/Hudu-Technologies-Inc/HuduAPI/archive/refs/heads/master.zip" -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force 
            $extracted = Join-Path $env:TEMP "HuduAPI-master" 
            if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
            Move-Item -Path $extracted -Destination $dst 
            Remove-Item $zip -Force
        }
    } else {
        Write-Host "Assuming PSGallery Module if not already locally cloned at $HAPImodulePath"
    }

    if (Test-Path $HAPImodulePath) {
        Import-Module $HAPImodulePath -Force
        Write-Host "Module imported from $HAPImodulePath"
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}
function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.37.1",
        $DisallowedVersions = @([version]"2.37.0")
    )
    Write-Host "Required Hudu version: $requiredversion" -ForegroundColor Blue
    try {
        $HuduAppInfo = Get-HuduAppInfo
        $CurrentHuduVersion = $HuduAppInfo.version

        if ([version]$CurrentHuduVersion -lt [version]$RequiredHuduVersion) {
            Write-Host "This script requires at least version $RequiredHuduVersion and cannot run with version $CurrentHuduVersion. Please update your version of Hudu." -ForegroundColor Red
            exit 1
        }
    } catch {
        write-host "error encountered when checking hudu version for $(Get-HuduBaseURL) - $_"
    }
    Write-Host "Hudu Version $CurrentHuduVersion is compatible"  -ForegroundColor Green
}

function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSversion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Version
    Write-Host "Required PowerShell version: $RequiredPSversion" -ForegroundColor Blue

    if ($currentPSVersion -lt $RequiredPSversion) {
        Write-Host "PowerShell $RequiredPSversion or higher is required. You have $currentPSVersion." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
    }
}
function Set-HuduInstance {
    param ([string]$HuduBaseURL,[string]$HuduAPIKey)
    $HuduBaseURL = $HuduBaseURL ?? 
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Set-HuduInstance {
    $HuduBaseURL = $HuduBaseURL ?? 
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}


try {
    Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance -HuduBaseUrl $HuduBaseURL -HuduApikey $huduapikey; Get-HuduVersionCompatible;

    $users   = Get-HuduUsers
    $groups  = Get-HuduGroups
    $folders = Get-HuduPasswordFolders
    $articles = Get-HuduArticles
    $passwords = Get-HuduPasswords
    $companies = Get-HuduCompanies 

    $CompaniesById = @{}
    $FoldersById = @{}
    $GroupById = @{}
    $UserById = @{}
    $CountsByEmail = @{}
    $companies | ForEach-Object {$CompaniesById[[int]$_.id] = $_.name}
    $folders | ForEach-Object {$FoldersById[[int]$_.id] = $_}
    $AdminUsers = $users | Where-Object {  $_.security_level -in @('admin','super_admin')}
    foreach ($g in $groups) { $GroupById[[int]$g.id] = $g }
    foreach ($u in $users)  { $UserById[[int]$u.id] = $u }
    $PublicArticles = $articles |
    Where-Object { $_.enable_sharing -eq $true -or -not [string]::IsNullOrEmpty($_.share_url) } |
    Select-Object Name,
        @{n='PublicUrl';e={$_.share_url}},
        @{n='Company';e={$CompaniesById[[int]$_.company_id]}}

    $ActiveNonPortalUsers = $users |
    Where-Object { $_.security_level -ne 'portal_member' -and ($_.disabled -ne $true) }

    # GroupId -> [user objects]
    $GroupMembersById = @{}
    foreach ($g in $groups) {
    $GroupMembersById[[int]$g.id] = @($g.members ?? @())
    }

    # Folder scope helper (global if company_id null or 0)
    function Get-FolderScope {
    param([object]$Folder)
    if (($null -eq $Folder.company_id) -or ([int]$Folder.company_id -eq 0)) { 'global' } else { 'company' }
    }

    # --- Build FolderAccessIndex: FolderId -> { Users:[userIds], Groups:[groupIds], Security:'specific'|'everyone', Scope:'global'|'company' } ---
    $FolderAccessIndex = @{}
    foreach ($f in $folders) {
    $fid = [int]$f.id
    $security = ($f.security -eq 'specific') ? 'specific' : 'default'
    $scope = Get-FolderScope $f

    $userIdSet = New-Object 'System.Collections.Generic.HashSet[int]'
    $groupIdSet = New-Object 'System.Collections.Generic.HashSet[int]'

    if ($security -eq 'specific') {
        foreach ($gid in ($f.allowed_groups ?? @())) {
        $g = $GroupById[[int]$gid]
        if (-not $g) { continue }
        [void]$groupIdSet.Add([int]$g.id)
        foreach ($m in ($GroupMembersById[[int]$gid] ?? @())) {
            [void]$userIdSet.Add([int]$m.id)
        }
        }
    } else {
        # everyone = all active non-portal members
        foreach ($u in $ActiveNonPortalUsers) { [void]$userIdSet.Add([int]$u.id) }
    }

    $FolderAccessIndex[$fid] = [pscustomobject]@{
        FolderId  = $fid
        Security  = $security
        Scope     = $scope
        Users     = [int[]]$userIdSet
        Groups    = [int[]]$groupIdSet
    }
    }


    $PasswordsWithAccess = foreach ($p in ($passwords | Where-Object { $_.password_folder_id -ne $null })) {
    $fid = [int]$p.password_folder_id
    $f   = $FoldersById[$fid]
    $fa  = $FolderAccessIndex[$fid]

    if (-not $f) {
        # Orphaned: folder not found
        [pscustomobject]@{
        PasswordId          = [int]$p.id
        PasswordName        = $p.name
        Username            = $p.username
        CompanyId           = [int]$p.company_id
        CompanyName         = $CompaniesById[[int]$p.company_id]
        FolderId            = $fid
        FolderName          = '(missing folder)'
        FolderSecurity      = '(unknown)'
        FolderScope         = '(unknown)'
        Archived            = [bool]$p.archived
        AccessUserEmails    = @()
        AccessViaGroups     = @()
        AccessUserCount     = 0
        }
        continue
    }

    $emails = @()
    foreach ($uid in ($fa.Users ?? @())) {
        $u = $UserById[[int]$uid]
        if ($u) { $emails += $u.email }
    }

    $groupNames = @()
    foreach ($gid in ($fa.Groups ?? @())) {
        $g = $GroupById[[int]$gid]
        if ($g) { $groupNames += $g.name }
    }

    [pscustomobject]@{
        PasswordId          = [int]$p.id
        PasswordName        = $p.name
        Username            = $p.username
        CompanyId           = [int]$p.company_id
        CompanyName         = $CompaniesById[[int]$p.company_id]
        FolderId            = [int]$f.id
        FolderName          = $f.name
        FolderSecurity      = $fa.Security          # 'specific' | 'everyone'
        FolderScope         = $fa.Scope             # 'global'   | 'company'
        Archived            = [bool]$p.archived
        AccessUserEmails    = $emails | Sort-Object -Unique
        AccessViaGroups     = $groupNames | Sort-Object -Unique
        AccessUserCount     = ($emails | Select-Object -Unique).Count
    }
    }
    $DefaultPasswordRows = foreach ($p in ($passwords | Where-Object { $null -eq $_.password_folder_id })) {
    [pscustomobject]@{
        PasswordId       = [int]$p.id
        PasswordName     = $p.name
        Username         = $p.username
        CompanyId        = [int]$p.company_id
        CompanyName      = $CompaniesById[[int]$p.company_id]
        FolderId         = $null
        FolderName       = '(none - default)'
        FolderSecurity   = 'default'
        FolderScope      = 'company-default'
        Archived         = [bool]$p.archived
        AccessUserEmails = @()          # not derived from folder RBAC
        AccessViaGroups  = @()
        AccessUserCount  = $null
        HasRBAC          = $false
    }
    }

    # --- Tag RBAC rows and keep them separate from default rows ---
    $RBACPasswordRows = $PasswordsWithAccess | ForEach-Object {
    $_ | Add-Member -NotePropertyName HasRBAC -NotePropertyValue $true -PassThru
    }

    # --- Useful views ---
    $AllPasswordRows = @($RBACPasswordRows) + @($DefaultPasswordRows)
    $TotalPasswords = ($passwords | Measure-Object).Count


    # 1) Per-password who can access (flattened rows)
    $PasswordAccessRows =
    foreach ($row in $PasswordsWithAccess) {
        if (($row.AccessUserEmails ?? @()).Count -eq 0) {
        [pscustomobject]@{
            PasswordId      = $row.PasswordId
            PasswordName    = $row.PasswordName
            CompanyName     = $row.CompanyName
            FolderName      = $row.FolderName
            FolderSecurity  = $row.FolderSecurity
            FolderScope     = $row.FolderScope
            UserEmail       = '(none)'
            ViaGroups       = ($row.AccessViaGroups -join ', ')
            Archived        = $row.Archived
        }
        continue
        }
        foreach ($email in $row.AccessUserEmails) {
        [pscustomobject]@{
            PasswordId      = $row.PasswordId
            PasswordName    = $row.PasswordName
            CompanyName     = $row.CompanyName
            FolderName      = $row.FolderName
            FolderSecurity  = $row.FolderSecurity
            FolderScope     = $row.FolderScope
            UserEmail       = $email
            ViaGroups       = ($row.AccessViaGroups -join ', ')
            Archived        = $row.Archived
        }
        }
    }

    # 2) Per-user how many passwords they can access
    $UserPasswordCounts =
    $PasswordAccessRows |
    Group-Object UserEmail |
    ForEach-Object {
        [pscustomobject]@{
        UserEmail           = $_.Name
        AccessiblePasswords = ($_.Group | Select-Object -ExpandProperty PasswordId -Unique).Count
        }
    } | Sort-Object -Property AccessiblePasswords -Descending
    foreach ($row in $UserPasswordCounts) {
    $CountsByEmail[$row.UserEmail] = [pscustomobject]@{
        UserEmail           = $row.UserEmail
        AccessiblePasswords = $row.AccessiblePasswords
        IsAdmin             = $false
    }
    }

    foreach ($au in $AdminUsers) {
    $email = $au.email
    $CountsByEmail[$email] = [pscustomobject]@{
        UserEmail           = $email
        AccessiblePasswords = $TotalPasswords
        IsAdmin             = $true
    }
    }    

    # 3) Per-folder summary
    $FolderPasswordCounts =
    $PasswordsWithAccess |
    Group-Object FolderId |
    ForEach-Object {
        $first = $_.Group | Select-Object -First 1
        [pscustomobject]@{
        FolderId       = $_.Name
        FolderName     = $first.FolderName
        FolderSecurity = $first.FolderSecurity
        FolderScope    = $first.FolderScope
        Passwords      = $_.Count
        UniqueUsers    = ($_.Group.AccessUserEmails | Select-Object -ExpandProperty * -Unique).Count
        }
    } | Sort-Object -Property FolderName

    # 4) Per-company quick look (only passwords in folders)
    $CompanyPasswordCounts =
    $PasswordsWithAccess |
    Group-Object CompanyName |
    ForEach-Object {
        [pscustomobject]@{
        CompanyName = if ([string]::IsNullOrWhiteSpace($_.Name)) { '(No company)' } else { $_.Name }
        Passwords   = $_.Count
        Folders     = ($_.Group.FolderId | Select-Object -Unique).Count
        }
    } | Sort-Object CompanyName

    $PasswordsByFolder_RBAC =
    $RBACPasswordRows |
    Group-Object FolderName |
    Select-Object @{n='FolderName';e={$_.Name}}, @{n='Count';e={$_.Count}} |
    Sort-Object Count -Descending


    Write-host "RBAC-only summaries" -ForegroundColor DarkCyan
    $PasswordAccessRows  | Sort-Object CompanyName,FolderName,PasswordName,UserEmail | Format-Table -Auto

    $UserPasswordCounts = $CountsByEmail.Values | Sort-Object -Property AccessiblePasswords -Descending
    $UserPasswordCounts | Format-Table -auto
    $FolderPasswordCounts    | Format-Table -Auto
    $CompanyPasswordCounts   | Format-Table -Auto
    $PasswordsByFolder_RBAC  | Format-Table -Auto
    Write-Host "RBAC per-company split" -ForegroundColor DarkCyan
    $CompanyCounts_All =
    $AllPasswordRows |
    Group-Object CompanyName |
    ForEach-Object {
        [pscustomobject]@{
        CompanyName      = if ([string]::IsNullOrWhiteSpace($_.Name)) { '(No company)' } else { $_.Name }
        TotalPasswords   = $_.Count
        RBACPasswords    = ($_.Group | Where-Object { $_.HasRBAC }      | Measure-Object).Count
        DefaultPasswords = ($_.Group | Where-Object { -not $_.HasRBAC } | Measure-Object).Count
        RBACFolders      = ($_.Group | Where-Object { $_.HasRBAC } | Select-Object -Expand FolderId -Unique | Measure-Object).Count
        }
    } | Sort-Object CompanyName

    Write-Host "ALL passwords (RBAC + default)" -ForegroundColor DarkCyan
    $AllPasswordRows | Select-Object PasswordId, PasswordName, CompanyName, FolderName, FolderSecurity, FolderScope, AccessUserCount, HasRBAC, Archived |
    Sort-Object CompanyName, FolderName, PasswordName | Format-Table -Auto

    $CompanyCounts_All | Format-Table -Auto

    Write-Host "Global folders" -ForegroundColor DarkCyan
    $globalfolders = $folders | Where-Object { -not $_.company_id -or [int]$_.company_id -eq 0 } | Select-Object id,name,security,allowed_groups
    $globalfolders | Format-Table -Auto

    Write-Host "Public Articles"
    $PublicArticles | Format-Table -Auto


    Write-Host "Exporting CSV files for more-granular review"
    # timestamped output dir
    $currentTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outputLocation = Join-Path -Path (Get-Location) -ChildPath "hudu-audit-$currentTimestamp"
    $null = New-Item -ItemType Directory -Path $outputLocation -Force

    # helpers to coerce arrays to strings for CSV
    $Join = { param($v) if ($null -eq $v) { '' } elseif ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) { ($v | ForEach-Object {[string]$_}) -join '; ' } else { [string]$v } }

    # 1) RBAC “who can access what” (already one row per user)
    $PasswordAccessRows |
        Select-Object PasswordId,PasswordName,CompanyName,FolderName,FolderSecurity,FolderScope,UserEmail,ViaGroups,Archived |
        Export-Csv (Join-Path $outputLocation 'password_access_rows.csv') -NoTypeInformation -Encoding utf8BOM

    # 2) Per-user counts
    $UserPasswordCounts |
        Select-Object UserEmail,AccessiblePasswords |
        Export-Csv (Join-Path $outputLocation 'user_password_counts.csv') -NoTypeInformation -Encoding utf8BOM

    # 3) Per-folder summary (RBAC-only)
    $FolderPasswordCounts |
        Select-Object FolderId,FolderName,FolderSecurity,FolderScope,Passwords,UniqueUsers |
        Export-Csv (Join-Path $outputLocation 'folder_password_counts.csv') -NoTypeInformation -Encoding utf8BOM

    # 4) Per-company (RBAC-only)
    $CompanyPasswordCounts |
    Select-Object CompanyName,Passwords,Folders |
    Export-Csv (Join-Path $outputLocation 'company_password_counts_rbac_only.csv') -NoTypeInformation -Encoding utf8BOM

    # 5) RBAC-only: passwords per folder (grouped)
    $PasswordsByFolder_RBAC |
    Select-Object FolderName,Count |
    Export-Csv (Join-Path $outputLocation 'passwords_by_folder_rbac.csv') -NoTypeInformation -Encoding utf8BOM

    # 6) ALL passwords: per-company split (RBAC vs default)
    $CompanyCounts_All |
    Select-Object CompanyName,TotalPasswords,RBACPasswords,DefaultPasswords,RBACFolders |
    Export-Csv (Join-Path $outputLocation 'company_counts_all.csv') -NoTypeInformation -Encoding utf8BOM

    # 7) Global folders
    $globalfolders |
    Select-Object id,name,security,
                    @{n='allowed_groups';e={ & $Join $_.allowed_groups }} |
    Export-Csv (Join-Path $outputLocation 'global_folders.csv') -NoTypeInformation -Encoding utf8BOM

    # 8) Public articles
    $PublicArticles |
    Select-Object Name,Company,PublicUrl |
    Export-Csv (Join-Path $outputLocation 'public_articles.csv') -NoTypeInformation -Encoding utf8BOM

    Write-Host "Wrote CSVs to: $outputLocation" -ForegroundColor Green    


} catch {
    Write-Error "Tabulation Error: $_"
} finally {
    Unset-Vars -Names @(
        'users','groups','folders','articles','passwords','companies',
        'PublicArticles','globalfolders','CompanyCounts_All','AllPasswordRows',
        'PasswordsByFolder_RBAC','CompanyPasswordCounts','FolderPasswordCounts',
        'UserPasswordCounts','PasswordAccessRows','PasswordsWithAccess',
        'DefaultPasswordRows','RBACPasswordRows',
        'FolderAccessIndex','GroupMembersById','GroupById','UserById',
        'ActiveNonPortalUsers','CompaniesById','FoldersById',
        'huduapikey','hudubaseurl'
    )
    try {remove-module huduapi -force}catch{}
}

