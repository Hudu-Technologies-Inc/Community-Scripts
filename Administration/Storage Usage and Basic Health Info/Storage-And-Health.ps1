$HuduBaseUrl = "https://yourhuduURL.huducloud.com"
$HuduAPIKey = $HuduAPIKey ?? $null
$UseAZVault = $true
$AzVault_HuduSecretName = "HuduAPIKeySecretName"                 # Name of your secret in AZure Keystore for your Hudu API key
$AzVault_Name           = "MyVaultName"                          # Name of your Azure Keyvault
$PreferredArticleTitle = "Hudu Health Report"
$HuduSetup = @{
    SelfHosted=$false
    HuduImage="hududocker/hudu" #mainline, for beta, use hudubeta/hudu
}

if ($true -eq $UseAZVault) {
  foreach ($module in @('Az.KeyVault')) {if (Get-Module -ListAvailable -Name $module) { Write-Host "Importing module, $module..."; Import-Module $module } else {Write-Host "Installing and importing module $module..."; Install-Module $module -Force -AllowClobber; Import-Module $module }}
  if (-not (Get-AzContext)) { Connect-AzAccount };
  $HuduAPIKey = "$(Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AzVault_HuduSecretName" -AsPlainText)"
}



$HuduSupportResources = @{
    SelfHostedGuide     = @{Description="Hudu Self-Hosted Guide"; URL="https://support.hudu.com/hc/en-us/articles/11475361347607-Getting-Started-With-Hudu-Self-Hosted"}
    UpgradingHudu       = @{Description="Self-Hosted Upgrades"; URL="https://support.hudu.com/hc/en-us/articles/11654689082391-Self-Hosted-Updating-your-Hudu-Version"}
    FileStorage         = @{Description="File Storage Info"; URL="https://support.hudu.com/hc/en-us/articles/11650296848023-Self-Hosted-Setup-File-Storage#guides-0-0"}
}
$stripHtml = { param($s) [regex]::Replace(($s ?? ''), '<[^>]+>', '') }
$toBytes = { param($s) if($m=[regex]::Match($s,'([\d\.]+)\s*(B|KB|MB|GB|TB)','IgnoreCase')){[int64]([double]$m.Groups[1].Value*(@{TB=1TB;GB=1GB;MB=1MB;KB=1KB;B=1}[$m.Groups[2].Value.ToUpper()]))}else{0} }
function Convert-MapToAsciiBarTable {
  param([hashtable]$Map,[string]$Title,[int]$BarWidth=30,[string]$Unit='')
  $enc = [System.Net.WebUtility]::HtmlEncode
  if (-not $Map.Keys.Count) {
    return "<section class='card'><h2>$($enc.Invoke($Title))</h2><p>No data</p></section>"
  }
  $max = ($Map.Values | ForEach-Object {[double]$_} | Measure-Object -Maximum).Maximum
  if (-not $max -or $max -le 0) { $max = 1 }
  $rows = $Map.GetEnumerator() | Sort-Object Key | ForEach-Object {
    $key = $enc.Invoke($_.Key)
    $val = [double]$_.Value
    $n   = [math]::Max(0,[math]::Round($BarWidth * $val / $max))
    $bar = ('█' * $n).PadRight($BarWidth,'·')
    "<tr><td>$key</td><td style='text-align:right'>$val$Unit</td><td><code>$bar</code></td></tr>"
  }
@"
<section class='card'>
  <h2>$($enc.Invoke($Title))</h2>
  <table>
    <thead><tr><th>Key</th><th>Value</th><th>Bar</th></tr></thead>
    <tbody>
      $(($rows -join "`n"))
    </tbody>
  </table>
</section>
"@
}
function Get-BlogURI {
    [CmdletBinding()]
    param([string]$VersionTag)

    $tag = [string]($VersionTag ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($tag)) { return 'https://hudu.com/blog' }
    $norm = $tag.TrimStart('v','V')
    if ($norm -notmatch '^\d+(\.\d+)*$') { return 'https://hudu.com/blog' }
    $uri = "https://hudu.com/blog/release-update-hudu-$norm"
    # if it hasnt been written yet (fresh off the stove), return blog from last release
    [bool]$hasBeenWritten = ($(try { (Invoke-WebRequest "https://hudu.com/blog/release-update-hudu-$norm" -Method Head -UseBasicParsing).StatusCode -eq 200 } catch { $false }))
    if ($true -eq $hasBeenWritten){
      return $uri
    } else {return 'https://hudu.com/blog'}
    return $uri
}

function Get-DockerURI {
    [CmdletBinding()]
    param([string]$VersionTag)

    # require image like "hududocker/hudu" in $HuduSetup.HuduImage
    $image = [string]$HuduSetup.HuduImage
    if ([string]::IsNullOrWhiteSpace($image)) { return 'https://hub.docker.com' }

    $base = "https://hub.docker.com/r/$image"
    $tag  = [string]($VersionTag ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($tag)) { return $base }

    $norm = $tag.TrimStart('v','V')
    if ($norm -notmatch '^[\w\.\-]+$') { return $base }  # conservative
    return "$base/tags?name=$([uri]::EscapeDataString($norm))"
}

function Convert-MapToHtmlTable {
  param(
    [AllowNull()][object]$Map,
    [string]$Title,
    [string[]]$RawHtmlValueKeys = @()   # keys that should NOT be HTML-encoded
  )

  # normalize to hashtable
  if (-not ($Map -is [System.Collections.IDictionary])) {
    $ht=@{}; if ($Map) { foreach($p in $Map.PSObject.Properties){ $ht[$p.Name]=$p.Value } }
    $Map = $ht
  }

  $enc = [System.Net.WebUtility]::HtmlEncode
  if (-not $Map -or $Map.Keys.Count -eq 0) {
    return "<section class='card'><h2>$($enc.Invoke($Title))</h2><p>No data available</p></section>"
  }

  # very light safety check: allow only http/https <a> tags when "raw"
  $isSafeAnchor = {
    param($s)
    if (-not $s) { return $false }
    $m = [regex]::Match([string]$s, '^\s*<a\s+[^>]*href=["'']https?://[^"'']+["''][^>]*>.*</a>\s*$', 'IgnoreCase')
    return $m.Success
  }

  $rows = $Map.GetEnumerator() | Sort-Object Key | ForEach-Object {
    $k = [string]$_.Key
    $v = [string]$_.Value

    $valHtml = if ($RawHtmlValueKeys -contains $k -and (& $isSafeAnchor $v)) {
      $v  # use as-is (clickable)
    } else {
      $enc.Invoke($v)  # encode (not clickable)
    }

    "<tr><td>$($enc.Invoke($k))</td><td>$valHtml</td></tr>"
  }

@"
<section class='card'>
  <h2>$($enc.Invoke($Title))</h2>
  <table>
    <thead><tr><th>Key</th><th>Value</th></tr></thead>
    <tbody>
      $(($rows -join "`n"))
    </tbody>
  </table>
</section>
"@
}
function Get-PhotosUploadsReport_NoJS {
  param(
    [array]$tables,
    [string]$PreferredTitle = "Hudu Uploads & Photos Report",
    [string]$OutFile = $(Join-Path (Get-Location) 'hudu-uploads-photos-report.html'),
    [bool]$WriteFile = $true
  )
  $html = @"
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>$PreferredTitle</title>
<meta name="viewport" content="width=device-width,initial-scale=1">

<style>
  /* everything scoped to .hudu-report so we don't fight the CMS */
  .hudu-report { color: inherit; background: transparent; font: 14px/1.45 system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif; }

  .hudu-report .title { margin: 0 0 12px 0; font-size: 18px; font-weight: 600; }

  .hudu-report .cards {
    display: grid;
    grid-template-columns: 1fr;    /* single column by default */
    gap: 16px;
  }
  /* only go 2-col if the viewport is actually wide */
  @media (min-width: 1280px) {
    .hudu-report .cards { grid-template-columns: 1fr 1fr; }
  }

  .hudu-report .card {
    background: var(--hudu-card, #171b21);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 12px;
    padding: 12px;
  }

  /* headings INSIDE the report; use a class, not <h2> to avoid TOC */
  .hudu-report .section-title {
    font-size: 14px; margin: 0 0 10px 0; opacity: .8; font-weight: 600;
  }

  .hudu-report table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  .hudu-report th, .hudu-report td {
    padding: 6px 8px; border-bottom: 1px solid rgba(255,255,255,0.06); vertical-align: top;
    word-break: break-word; overflow-wrap: anywhere;
  }
  .hudu-report th { text-align: left; font-weight: 600; opacity: .8; }
  .hudu-report td:last-child { text-align: right; } /* value column aligns right */
  .hudu-report a { color: inherit; text-decoration: underline; }
</style>
$($tables -join "`n")


<header><h1>$PreferredTitle</h1></header>
<main>
</main>
</html>
"@
  if ($WriteFile) { Set-Content -Path $OutFile -Value $html -Encoding UTF8 }
  return $html
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

function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.39.3",
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
    return $CurrentHuduVersion
}

function Get-HuduArticleCalculations {
  param ([array]$articles)
  $stats=@()

  $stats = $articles | ForEach-Object {
      $content = [string]($_.article.content ?? $_.content)
      $text    = & $stripHtml $content
      [pscustomobject]@{
          Id        = $_.article.id ?? $_.id
          HtmlLen   = $content.Length
          Link      = "<a href='$($_.article.url ?? $_.url)'>Link to $($_.article.name ?? $_.name)</a>"
          TextLen   = $text.Length
          WordCount = ($text -split '\s+').Count
      }
  }
  return [PSCustomObject]@{
    TextLengthLongest  = $stats | Sort-Object TextLen -Descending | Select-Object -First 1
    TextLengthShortest = $stats | Sort-Object TextLen              | Select-Object -First 1
    WordCountLongest  = $stats | Sort-Object WordCount -Descending | Select-Object -First 1
    WordCountShortest = $stats | Sort-Object WordCount              | Select-Object -First 1  
  }
}
function Get-UploadCalculations {
    param (
        [array]$uploads
    )
    $UploadsCountByMime=@{}; $uploads | Group-Object -Property mime | ForEach-Object { $UploadsCountByMime[$_.Name]=$_.Count }

    # Total storage by MIME (bytes) + pretty strings
    $UploadsBytesByMime=@{}; $uploads | ForEach-Object { $k=$_.mime; $UploadsBytesByMime[$k]=($UploadsBytesByMime[$k]+0)+(& $toBytes $_.size) }
    $UploadsBytesByMimePretty=@{}; $UploadsBytesByMime.GetEnumerator() | ForEach-Object {
    $k=$_.Key; $v=[int64]$_.Value
    $UploadsBytesByMimePretty[$k] = $( if ($v -ge 1GB) { "{0:N2} GB" -f ($v/1GB) } elseif ($v -ge 1MB) { "{0:N2} MB" -f ($v/1MB) } else { "$v B" } )
    }

    # Count by related key: "Type#Id" and by Company
    $UploadsCountByRelated=@{}; $uploads | ForEach-Object { $k="$($_.uploadable_type)#$($_.uploadable_id)"; $UploadsCountByRelated[$k]=($UploadsCountByRelated[$k]+0)+1 }
    $UploadsCountByCompany=@{}; $uploads | Where-Object uploadable_type -eq 'Company' | ForEach-Object { $k="$($_.uploadable_id)"; $UploadsCountByCompany[$k]=($UploadsCountByCompany[$k]+0)+1 }

    # Per-month counts (YYYY-MM)
    $UploadsPerMonth=@{}; $uploads | ForEach-Object { $k=(Get-Date $_.created_date).ToString('yyyy-MM'); $UploadsPerMonth[$k]=($UploadsPerMonth[$k]+0)+1 }

    # Top 10 by size → [ordered] "name (slug)" : "size str"
    $UploadsTop10BySize=[ordered]@{}; $uploads | Sort-Object -Property @{Expression={& $toBytes $_.size}} -Descending |
    Select-Object -First 10 | ForEach-Object { $UploadsTop10BySize["$($_.name) ($($_.slug))"]=$_.size }

    # Extension↔MIME mismatches
    $__mimeMap=@{png='image/png';jpg='image/jpeg';jpeg='image/jpeg';gif='image/gif';pdf='application/pdf'}
    $UploadsExtMimeMismatches=@{}; $uploads | ForEach-Object {
    $ext=[io.path]::GetExtension($_.name).TrimStart('.').ToLower()
    $m=$__mimeMap[$ext]
    if ($m -and $m -ne $_.mime) { $k="$ext=>$($_.mime)"; $UploadsExtMimeMismatches[$k]=($UploadsExtMimeMismatches[$k]+0)+1 }
    }

    # Duplicate filenames (same Name)
    $UploadsDuplicateNames=@{}; $uploads | Group-Object -Property name | Where-Object Count -gt 1 |
    ForEach-Object { $UploadsDuplicateNames[$_.Name]=$_.Count }

    # Storage by related key (bytes)
    $UploadsBytesByRelated=@{}; $uploads | ForEach-Object { $k="$($_.uploadable_type)#$($_.uploadable_id)"; $UploadsBytesByRelated[$k]=($UploadsBytesByRelated[$k]+0)+(& $toBytes $_.size) }

    # Newest file per MIME → "yyyy-MM-dd HH:mm  name"
    $UploadsNewestPerMime=@{}; $uploads | Group-Object -Property mime | ForEach-Object {
    $n=$_.Group | Sort-Object -Property @{Expression={Get-Date $_.created_date}} -Descending | Select-Object -First 1
    $UploadsNewestPerMime[$_.Name]=('{0:yyyy-MM-dd HH:mm}  {1}' -f (Get-Date $n.created_date), $n.name)
    }

    # Percent of storage by MIME (0–100)
    $__uploadsTotal = ($uploads | ForEach-Object { & $toBytes $_.size } | Measure-Object -Sum).Sum; if (-not $__uploadsTotal) { $__uploadsTotal = 1 }
    $UploadsPercentByMime=@{}; $uploads | Group-Object -Property mime | ForEach-Object {
    $bytes = ($_.Group | ForEach-Object { & $toBytes $_.size } | Measure-Object -Sum).Sum
    $UploadsPercentByMime[$_.Name] = [math]::Round((100 * $bytes / $__uploadsTotal), 2)
    }
    return [PSCustomObject]@{
        UploadsCountByMime          = $UploadsCountByMime
        UploadsBytesByMimePretty    = $UploadsBytesByMimePretty
        UploadsCountByRelated       = $UploadsCountByRelated
        UploadsPerMonth             = $UploadsPerMonth
        UploadsTop10BySize          = $UploadsTop10BySize
        UploadsExtMimeMismatches    = $UploadsExtMimeMismatches
        UploadsDuplicateNames       = $UploadsDuplicateNames
        UploadsBytesByRelated       = $UploadsBytesByRelated
        UploadsNewestPerMime        = $UploadsNewestPerMime
        UploadsPercentByMime        = $UploadsPercentByMime
    }
}
### PHOTOS METRICS
function Get-PhotoCalculations {
    param ([array]$photos)
    $PhotosCountByMime=@{}; $photos | Group-Object -Property mime | ForEach-Object { $PhotosCountByMime[$_.Name]=$_.Count }

    # Count by record type
    $PhotosCountByRecordType=@{}; $photos | Group-Object -Property record_type | ForEach-Object { $PhotosCountByRecordType[$_.Name]=$_.Count }

    # Count by related key: "Type#Id"
    $PhotosCountByRelated=@{}; $photos | ForEach-Object { $k="$($_.record_type)#$($_.record_id)"; $PhotosCountByRelated[$k]=($PhotosCountByRelated[$k]+0)+1 }

    # Top 10 most-photographed records
    $PhotosTop10MostPhotographed=[ordered]@{}; $photos |
    Group-Object -Property { "$($_.record_type)#$($_.record_id)" } |
    Sort-Object -Property Count -Descending | Select-Object -First 10 |
    ForEach-Object { $PhotosTop10MostPhotographed[$_.Name]=$_.Count }

    return [PSCustomObject]@{
        PhotosCountByMime           = $PhotosCountByMime
        PhotosCountByRecordType     = $PhotosCountByRecordType
        PhotosCountByRelated        = $PhotosCountByRelated
        PhotosTop10MostPhotographed = $PhotosTop10MostPhotographed
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
        exit 1
    } else {
        Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
    }
}

function New-ConicDonutHtml {
  param(
    [hashtable]$Map,
    [string]$Title = 'Donut'
  )
  $labels = @($Map.Keys)
  if (-not $labels.Count) { return "<section class='card'><h2>$Title</h2><p>No data</p></section>" }

  $sum = ($labels | ForEach-Object { [double]$Map[$_] } | Measure-Object -Sum).Sum
  if ($sum -eq 0) { $sum = 1 }

  # build gradient stops
  $stops = @()
  $acc = 0.0
  foreach ($k in $labels) {
    $val = [double]$Map[$k]
    $pct = 100.0 * $val / $sum
    $start = [math]::Round($acc,2)
    $acc  += $pct
    $end   = [math]::Round($acc,2)
    $stops += "var(--c) $start% $end%"
  }
  $legend = ($labels | ForEach-Object { "<li><span class='dot'></span>$([System.Web.HttpUtility]::HtmlEncode($_))</li>" }) -join ''
  @"
<section class='card'>
  <h2>$([System.Web.HttpUtility]::HtmlEncode($Title))</h2>
  <div class='donut' style='--g: conic-gradient($($stops -join ", "));'></div>
  <ul class='legend'>$legend</ul>
</section>
"@
}


Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance;
#Get Upload Stats
$companies = $(get-huducompanies)
$uploads = $(get-huduuploads)
$photos  = $(Get-HuduPublicPhotos)
$articles = $(Get-HuduArticles)



$CurrentVersion=$(Get-HuduVersionCompatible)
[bool]$ThreeOhOneRedirectBlock=[bool]$(try{
  $null=Invoke-WebRequest -Uri (($u=(Get-HuduBaseURL)) -replace '^https://','http://') -Method Head -MaximumRedirection 0 -ErrorAction Stop; $false
}catch{
  $r=$_.Exception.Response; ($r -and ([int]$r.StatusCode -in 301,302,307,308))
})

$LatestAvailableVersion=$((Invoke-RestMethod "https://hub.docker.com/v2/repositories/$($HuduSetup.HuduImage)/tags/?page_size=100").results.name | Where-Object { $_ -ne 'latest' } | Select-Object -First 1)
if ([version]$($LatestAvailableVersion) -ge [version]$($CurrentVersion)){
    $UpdateAvailable=$true
} else {
    $UpdateAvailable = $false
}

Write-Host "Calculating Total Photos-Uploads Statistics" -ForegroundColor DarkCyan
$UploadStats = Get-UploadCalculations -uploads $uploads
$PhotoStats = Get-PhotoCalculations  -photos  $photos

# (Create/Update) Global Article
$ArticleRequest = @{ Name = $PreferredArticleTitle }
$ExistingArticle = Get-HuduArticles -Name $PreferredArticleTitle | Select-Object -First 1
if ($ExistingArticle) {
    $ArticleRequest.Id = ($ExistingArticle.article.id ?? $ExistingArticle.id)
}

$VariousInfos=@{
    CurrentHuduVersion=$CurrentVersion
    ReportingDate="Hudu Reports Date As $($(Get-HuduAppInfo).date)"
    WebRedirectActive="Web Redirects for HTTP: $(if ($true -eq $ThreeOhOneRedirectBlock) {"Non-TLS requests redirected to HTTPS!"} else {"Warning: Direct HTTP accessability found. Are you hosted on a private LAN?"})"
    UpdateAvailable=$UpdateAvailable; 
    ReleaseNotes="<a href='$($(Get-BlogURI -versionTag $LatestAvailableVersion))'>$LatestAvailableVersion release notes</a>"
    NewestVersion="$LatestAvailableVersion"
    DockerImageLink="<a href='$(Get-DockerURI -versionTag $LatestAvailableVersion)'>$LatestAvailableVersion Docker Image</a>"
    HelpLink=$(if ($true -eq $HuduSetup.SelfHosted) {"<a href='$($HuduSupportResources.UpgradingHudu.URL)'>$($HuduSupportResources.UpgradingHudu.Description)</a>"} else {"An Update $($LatestAvailableVersion) will soon be applied to your instance outside of operating hours. No action required."})
} 
<#
        UploadsCountByMime          = $UploadsCountByMime
        UploadsBytesByMimePretty    = $UploadsBytesByMimePretty
        UploadsCountByRelated       = $UploadsCountByRelated
        UploadsPerMonth             = $UploadsPerMonth
        UploadsTop10BySize          = $UploadsTop10BySize
        UploadsExtMimeMismatches    = $UploadsExtMimeMismatches
        UploadsDuplicateNames       = $UploadsDuplicateNames
        UploadsBytesByRelated       = $UploadsBytesByRelated
        UploadsNewestPerMime        = $UploadsNewestPerMime
        UploadsPercentByMime        = $UploadsPercentByMime
#>

$ArticlesStats = Get-HuduArticleCalculations -articles $articles

$tablesList=@(
                $(Convert-MapToHtmlTable -Map $VariousInfos -Title 'Version Information' -RawHtmlValueKeys @('DockerImageLink','HelpLink','ReleaseNotes')),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsPercentByMime      -Title 'Uploads: Percent of Storage by MIME'),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsBytesByMimePretty  -Title 'Uploads: Total Storage by MIME (Pretty)'),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsCountByMime        -Title 'Uploads: Count by MIME'),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsNewestPerMime        -Title 'Uploads: Newest by MIME'),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsPerMonth        -Title 'Uploads: Uploads per Month'),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsCountByRelated    -Title 'Uploads: Count by Record Type'),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsTop10BySize    -Title 'Uploads: Top Ten by Size'),
                $(Convert-MapToHtmlTable -Map $UploadStats.UploadsDuplicateNames    -Title 'Uploads: Potential Duplicates by Name'),
                $(Convert-MapToHtmlTable -Map $PhotoStats.PhotosCountByRecordType    -Title 'Photos: Count by Record Type'),
                $(Convert-MapToHtmlTable -Map $ArticlesStats.WordCountLongest -Title 'Articles: Most Words' -RawHtmlValueKeys @('Link')),
                $(Convert-MapToHtmlTable -Map $ArticlesStats.WordCountShortest -Title 'Articles: Fewest Words' -RawHtmlValueKeys @('Link')),
                $(Convert-MapToHtmlTable -Map $ArticlesStats.TextLengthLongest -Title 'Articles: Most Text' -RawHtmlValueKeys @('Link')),
                $(Convert-MapToHtmlTable -Map $ArticlesStats.TextLengthShortest -Title 'Articles: Least Text' -RawHtmlValueKeys @('Link'))
)
$ArticleRequest.Content = Get-PhotosUploadsReport_NoJS -Tables $tablesList -PreferredTitle $PreferredArticleTitle

if ($ArticleRequest.Id) { Set-HuduArticle @ArticleRequest } else { New-HuduArticle @ArticleRequest }


$HuduAPIKey = $null
