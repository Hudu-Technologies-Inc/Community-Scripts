using namespace System.Text.RegularExpressions
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}
$Script:PDFToHTMLTempBinLocation=$null
# Regex objects used by the rewriter (local; no $Script: scope needed)
$rxTag       = [Regex]::new('<(img|embed|a|iframe|source|video|audio)\b(?<attrs>[^>]*)>', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)
$rxAttr      = [Regex]::new('\b(?<name>src|href|data|poster)\s*=\s*(?<q>["''])(?<val>.*?)\k<q>', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)
$rxStyleAttr = [Regex]::new('\bstyle\s*=\s*(["''])(?<style>.*?)\1', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)
$rxCssUrl    = [Regex]::new('url\(\s*(["'']?)(?<u>[^)"'']+)\1\s*\)', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)

$huduapikey = $huduapikey ?? $(read-host "Please enter hudu api key")
$hudubaseurl = $hudubaseurl ?? $(read-host "please enter hudu instance url")
function Set-HuduInstance {
    param ($HuduBaseURL, $HuduAPIKey)
    $HuduBaseURL = $HuduBaseURL ?? 
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($HuduBaseURL)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Get-EnsureModule {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber `
            -ErrorAction SilentlyContinue *> $null
    }
    try {
        Import-Module -Name $Name -Force -ErrorAction Stop *> $null
    } catch {
        Write-Warning "Failed to import module '$Name': $($_.Exception.Message)"
    }
}
function Unset-Vars {
    param (
        [string]$varname,
        [string[]]$scopes = @('Local', 'Script', 'Global', 'Private')
    )

    foreach ($scope in $scopes) {
        if (Get-Variable -Name $varname -Scope $scope -ErrorAction SilentlyContinue) {
            Remove-Variable -Name $varname -Scope $scope -Force -ErrorAction SilentlyContinue
            Write-Host "Unset `$${varname} from scope: $scope"
        }
    }
}

function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
        [bool]$use_hudu_fork = $true
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
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'4.1.0') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 4.1.0 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}
function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.43.1",
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

function Get-NormalizedTitle([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  ([System.Web.HttpUtility]::HtmlDecode($s) -replace '\s+', ' ').Trim().ToLowerInvariant()
}
function Get-TitleSlug([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  ($s -replace '[^\p{L}\p{Nd}]+','-').Trim('-').ToLowerInvariant()
}
function Get-ObjectPropertyValue {
  param(
    [object]$InputObject,
    [Parameter(Mandatory)][string[]]$Names
  )
  if ($null -eq $InputObject) { return $null }
  foreach ($name in $Names) {
    $property = $InputObject.PSObject.Properties[$name]
    if ($null -ne $property) {
      return $property.Value
    }
  }
  return $null
}
function Unwrap-HuduResultObject {
  param(
    [object]$InputObject,
    [string[]]$WrapperNames = @('company', 'article', 'upload', 'public_photo', 'PublicPhoto', 'HuduArticle')
  )
  $current = $InputObject
  foreach ($wrapperName in $WrapperNames) {
    $wrapped = Get-ObjectPropertyValue -InputObject $current -Names @($wrapperName)
    if ($null -ne $wrapped) {
      $current = $wrapped
    }
  }
  return $current
}
function Get-HuduObjectName {
  param([object]$InputObject)
  return Get-ObjectPropertyValue -InputObject $InputObject -Names @('name', 'Name', 'file_name', 'fileName', 'FileName')
}
function Get-HuduObjectId {
  param([object]$InputObject)
  return Get-ObjectPropertyValue -InputObject $InputObject -Names @('id', 'Id')
}
function Get-HuduPublicPhotoDownloadId {
  param([object]$InputObject)
  $numericId = Get-ObjectPropertyValue -InputObject $InputObject -Names @('numeric_id', 'numericId', 'NumericId')
  if ($numericId) { return $numericId }
  return Get-HuduObjectId -InputObject $InputObject
}
function Test-HuduPublicPhotoRasterImage {
  param([Parameter(Mandatory)][string]$Path)
  $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  return ($extension -in @('.gif', '.png', '.jpeg', '.jpg'))
}
function Get-HuduEmbeddableUploadMediaKind {
  param([Parameter(Mandatory)][string]$Path)
  $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($extension -in @('.mp4', '.m4v', '.webm', '.ogv', '.mov', '.mkv')) { return 'Video' }
  if ($extension -in @('.mp3', '.m4a', '.aac', '.wav', '.ogg', '.oga', '.opus', '.flac', '.weba')) { return 'Audio' }
  return $null
}
function Test-HuduEmbeddableUploadMediaFile {
  param([Parameter(Mandatory)][string]$Path)
  return -not [string]::IsNullOrWhiteSpace((Get-HuduEmbeddableUploadMediaKind -Path $Path))
}
function Get-HuduEmbedHtmlForLocalMedia {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Title
  )

  $kind = Get-HuduEmbeddableUploadMediaKind -Path $Path
  if ([string]::IsNullOrWhiteSpace($kind)) { return $null }

  $leaf = [System.Net.WebUtility]::HtmlEncode([IO.Path]::GetFileName($Path))
  $encodedTitle = [System.Net.WebUtility]::HtmlEncode($Title)
  if ($kind -eq 'Video') {
    return "<video src='$leaf' controls='controls' width='640'>$encodedTitle</video>"
  }

  return "<audio src='$leaf' controls='controls'>$encodedTitle</audio>"
}
function Test-HuduObjectArticleAssociation {
  param(
    [object]$InputObject,
    [Parameter(Mandatory)][int]$ArticleId,
    [Parameter(Mandatory)][ValidateSet('Upload','PublicPhoto')][string]$MediaKind
  )

  if ($MediaKind -eq 'Upload') {
    return (
      (Get-ObjectPropertyValue -InputObject $InputObject -Names @('uploadable_type', 'uploadableType', 'UploadableType')) -eq 'Article' -and
      (Get-ObjectPropertyValue -InputObject $InputObject -Names @('uploadable_id', 'uploadableId', 'UploadableId')) -eq $ArticleId
    )
  }

  return (
    (Get-ObjectPropertyValue -InputObject $InputObject -Names @('record_type', 'recordType', 'RecordType')) -eq 'Article' -and
    (Get-ObjectPropertyValue -InputObject $InputObject -Names @('record_id', 'recordId', 'RecordId')) -eq $ArticleId
  )
}
function Convert-HuduMediaUrlToRelative {
  param(
    [AllowNull()][string]$Url,
    [AllowNull()][string]$HuduBaseUrl
  )

  if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
  $trimmedUrl = $Url.Trim()
  if ($trimmedUrl.StartsWith('/')) { return $trimmedUrl }
  if ($trimmedUrl -notmatch '^(?i)https?://') { return $trimmedUrl }

  try {
    $uri = [uri]$trimmedUrl
  } catch {
    return $trimmedUrl
  }

  $baseHosts = @()
  foreach ($candidateBase in @($HuduBaseUrl, $script:Int_HuduBaseURL, $script:hudubaseurl, $hudubaseurl)) {
    if ([string]::IsNullOrWhiteSpace([string]$candidateBase)) { continue }
    try {
      $baseHosts += ([uri]$candidateBase).Host
    } catch {}
  }
  try {
    if (Get-Command -Name Get-HuduBaseURL -ErrorAction SilentlyContinue) {
      $moduleBaseUrl = Get-HuduBaseURL
      if (-not [string]::IsNullOrWhiteSpace([string]$moduleBaseUrl)) {
        $baseHosts += ([uri]$moduleBaseUrl).Host
      }
    }
  } catch {}
  $baseHosts = @($baseHosts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

  $isHuduHost = ($baseHosts.Count -eq 0 -and $uri.AbsolutePath -match '^/(file|public_photo)/') -or ($uri.Host -in $baseHosts)
  if ($isHuduHost -and $uri.AbsolutePath -match '^/(file|public_photo)/') {
    return $uri.PathAndQuery
  }

  return $trimmedUrl
}
function New-DocImageMap {
  param(
    [object[]]$HuduImages,
    [string]$HuduBaseUrl
  )
  $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($h in $HuduImages) {
    $orig = [string]$h.OriginalFilename
    $url  = $h.UsingImage.url ?? $h.UsingImage.public_url ?? $h.UsingImage.file_url ?? $h.UsingImage.cdn_url
    if (-not $url -and $h.MediaKind -eq 'PublicPhoto') {
      $publicPhotoId = Get-HuduObjectId -InputObject $h.UsingImage
      if ($publicPhotoId) { $url = "/public_photo/$publicPhotoId" }
    }
    $url = Convert-HuduMediaUrlToRelative -Url $url -HuduBaseUrl $HuduBaseUrl
    if (-not $orig -or -not $url) { continue }
    $leaf = Split-Path -Leaf $orig
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
    foreach ($k in @(
        $leaf,
        $base,
        [uri]::EscapeDataString($leaf),
        [uri]::EscapeDataString($base)
    )) {
        if ($k -and -not $map.ContainsKey($k)) { $map[$k] = $url }
    }
  }
  $map
}

function Rewrite-DocLinks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Html,
    [Parameter(Mandatory)][scriptblock]$ImageResolver, # param([string]$src,[hashtable]$ctx)->string/$null
    [Parameter(Mandatory)][scriptblock]$LinkResolver,  # param([string]$href,[hashtable]$ctx)->string/$null
    [hashtable]$Context = @{}
  )
  if ([string]::IsNullOrEmpty($Html)) {
    return [pscustomobject]@{ Html=''; Rewrites=@(); Unresolved=@() }
  }
  $rewrites  = New-Object System.Collections.Generic.List[object]
  $unresolved = New-Object System.Collections.Generic.List[object]

  $html1 = $rxTag.Replace($Html, {
    param([Match]$m)
    $tagName = $m.Groups[1].Value.ToLowerInvariant()
    $attrs   = $m.Groups['attrs'].Value
    $newAttrs = $rxAttr.Replace($attrs, {
      param([Match]$ma)
      $name = $ma.Groups['name'].Value.ToLowerInvariant()
      $q    = $ma.Groups['q'].Value
      $val  = $ma.Groups['val'].Value
      $newVal = if ($name -eq 'href') { & $LinkResolver  $val $Context } else { & $ImageResolver $val $Context }
      if ($newVal -and $newVal -ne $val) {
        $rewrites.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; From=$val; To=$newVal }) | Out-Null
        return "$name=$q$newVal$q"
      } else {
        if (-not $newVal) { $unresolved.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; Value=$val }) | Out-Null }
        return $ma.Value
      }
    })
    "<$tagName$newAttrs>"
  })

  $html2 = $rxStyleAttr.Replace($html1, {
    param([Match]$m)
    $q     = $m.Groups[1].Value
    $style = $m.Groups['style'].Value
    $newStyle = $rxCssUrl.Replace($style, {
      param([Match]$mu)
      $u = $mu.Groups['u'].Value
      $newU = & $ImageResolver $u $Context
      if ($newU -and $newU -ne $u) {
        $rewrites.Add([pscustomobject]@{ Tag='style'; Attr='url'; From=$u; To=$newU }) | Out-Null
        return "url($newU)"
      } else {
        if (-not $newU) { $unresolved.Add([pscustomobject]@{ Tag='style'; Attr='url'; Value=$u }) | Out-Null }
        return $mu.Value
      }
    })
    " style=$q$newStyle$q"
  })

  [pscustomobject]@{ Html=$html2; Rewrites=$rewrites; Unresolved=$unresolved }
}

function Set-HuduArticleFromHtml {
  [CmdletBinding()]
  param(
    [string[]]$ImagesArray = @(),   # flat list of absolute local media paths referenced by the HTML
    [string]$CompanyName = "",                     # optional → global KB if ''
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$HtmlContents,
    [switch]$CreateCompanyIfMissing = $false,
    [bool]$CalculateHashes = $true,
    [string]$HuduBaseUrl
  )
    $null = Get-EnsuredPath -Path $DocConversionTempDir

    if (-not (Get-Variable -Name CurrentHuduVersion -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:CurrentHuduVersion) {
        $appInfo = Get-HuduAppInfo
        $script:CurrentHuduVersion = [version]$appInfo.version
    }

    if (-not (Get-Variable -Name DateCompareJitterHours -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:DateCompareJitterHours) {
        $script:DateCompareJitterHours = [timespan]::FromHours(12)
    }
      $embedInfo = @()
  # 1) Resolve company (optional)
  $matchedCompany = $null
  if ($CompanyName) {
    $huduCompanies = Get-HuduCompanies
    $matchedCompany = $huduCompanies | Where-Object { (Get-HuduObjectName -InputObject $_) -eq $CompanyName } | Select-Object -First 1
    if (-not $matchedCompany) {
      $matchedCompany = $huduCompanies | Where-Object {
        (Test-Equiv -A (Get-HuduObjectName -InputObject $_) -B $CompanyName) -or
        (Test-Equiv -A (Get-ObjectPropertyValue -InputObject $_ -Names @('nickname', 'Nickname')) -B $CompanyName)
      } | Select-Object -First 1
    }
    if (-not $matchedCompany -and $CreateCompanyIfMissing) {
      $created = New-HuduCompany -Name $CompanyName
      $matchedCompany = Unwrap-HuduResultObject -InputObject $created -WrapperNames @('company')
    }
    $matchedCompany = Unwrap-HuduResultObject -InputObject $matchedCompany -WrapperNames @('company')
  }
  # 2. resolve or create article
  $allHududocuments = Get-HuduArticles
  $matchedDocument = if ($matchedCompany) {
    $matchedCompanyId = Get-HuduObjectId -InputObject $matchedCompany
    $allHududocuments | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -Names @('company_id', 'companyId', 'CompanyId')) -eq $matchedCompanyId -and (Test-Equiv -A (Get-HuduObjectName -InputObject $_) -B $Title) } | Select-Object -First 1
  } else {
    $allHududocuments | Where-Object { Test-Equiv -A (Get-HuduObjectName -InputObject $_) -B $Title } | Select-Object -First 1
  }
  if (-not $matchedDocument) {
    $matchedDocument = if ($matchedCompany) {
      (Get-HuduArticles -CompanyId (Get-HuduObjectId -InputObject $matchedCompany) -Name $Title | Select-Object -First 1)
    } else {
      (Get-HuduArticles -Name $Title | Select-Object -First 1)
    }
  }
  $matchedDocument = Unwrap-HuduResultObject -InputObject $matchedDocument -WrapperNames @('article')
  $newDocument = $null
  if (-not $matchedDocument) {
    $newDocument = if ($matchedCompany) {
      New-HuduArticle -Name $Title -Content '[transfer in-progress]' -CompanyId (Get-HuduObjectId -InputObject $matchedCompany)
    } else {
      New-HuduArticle -Name $Title -Content '[transfer in-progress]'
    }
    $newDocument = Unwrap-HuduResultObject -InputObject $newDocument -WrapperNames @('article')
  }
  $articleUsed = $matchedDocument ?? $newDocument
  $articleUsedId = Get-HuduObjectId -InputObject $articleUsed
  if (-not $articleUsed -or -not $articleUsedId) {
    throw "Could not match or create article: '$Title' (Company: '$CompanyName')"
  }

  # 2) Idempotent article-local media. Public photos are used for raster article embeds.
  $existingRelatedUploads = Get-HuduUploads | Where-Object { Test-HuduObjectArticleAssociation -InputObject $_ -ArticleId $articleUsedId -MediaKind Upload }
  $existingRelatedPublicPhotos = @()
  if (@($ImagesArray | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) -and (Test-HuduPublicPhotoRasterImage -Path $_) }).Count -gt 0) {
    if (-not (Get-Command -Name Get-HuduPublicPhotos -ErrorAction SilentlyContinue) -or -not (Get-Command -Name New-HuduPublicPhoto -ErrorAction SilentlyContinue)) {
      throw "Raster article images require HuduAPI public photo cmdlets: Get-HuduPublicPhotos and New-HuduPublicPhoto."
    }
    $existingRelatedPublicPhotos = @(Get-HuduPublicPhotos | Where-Object { Test-HuduObjectArticleAssociation -InputObject $_ -ArticleId $articleUsedId -MediaKind PublicPhoto })
  }

  $ImagesArray = @(@($ImagesArray) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
  Write-Verbose "Processing $($ImagesArray.Count) embedded media files for article '$Title'..."
  $HuduImages = @()
  foreach ($ImageFile in $ImagesArray) {
    if (-not (Test-Path -LiteralPath $ImageFile -PathType Leaf)) { continue }
    $existingUpload = $null; $uploaded = $null; $existingPublicPhoto = $null; $uploadedPublicPhoto = $null; $comparison = $null; $existingUploadModifiedDate = $null;
    $imageFileName = ([IO.Path]::GetFileName($ImageFile)).Trim()
    $imageMetadata = Get-Item -LiteralPath $ImageFile -ErrorAction silentlycontinue
    $usePublicPhoto = Test-HuduPublicPhotoRasterImage -Path $ImageFile

    if ($usePublicPhoto) {
      $publicPhotoCandidates = @($existingRelatedPublicPhotos | Where-Object { (Get-HuduObjectName -InputObject $_) -eq $imageFileName })
      if ($publicPhotoCandidates.Count -eq 0) {
        $publicPhotoCandidates = @($existingRelatedPublicPhotos | Where-Object { Test-Equiv -A (Get-HuduObjectName -InputObject $_) -B $imageFileName })
      }

      if ($true -eq $CalculateHashes) {
        foreach ($candidate in $publicPhotoCandidates) {
          $candidate = Unwrap-HuduResultObject -InputObject $candidate -WrapperNames @('public_photo', 'PublicPhoto')
          $publicPhotoDownloadId = Get-HuduPublicPhotoDownloadId -InputObject $candidate
          if (-not $publicPhotoDownloadId) { continue }
          try {
            $comparison = Compare-PublicPhotoHashWithFile -PublicPhotoId $publicPhotoDownloadId -LocalFile $ImageFile
            if ($true -eq $comparison.SameFile) {
              $existingPublicPhoto = $candidate
              $embedInfo += "Existing article public photo '$(Get-HuduObjectName -InputObject $candidate)' with id $(Get-HuduObjectId -InputObject $candidate) matches file '$ImageFile' by hash. Reusing current-article public photo."; Write-Verbose $embedInfo[-1];
              break
            }
          } catch {
            Write-Warning "Could not compare existing public photo hash for '$imageFileName': $($_.Exception.Message)"
          }
        }
      } else {
        $existingPublicPhoto = Unwrap-HuduResultObject -InputObject ($publicPhotoCandidates | Select-Object -First 1) -WrapperNames @('public_photo', 'PublicPhoto')
      }

      if (-not $existingPublicPhoto) {
        if ($publicPhotoCandidates.Count -gt 0 -and $true -eq $CalculateHashes) {
          $embedInfo += "Found same-article public photo candidate(s) for '$imageFileName', but none matched the local hash. Creating a new public photo for this article."; Write-Verbose $embedInfo[-1];
        }
        $uploadedPublicPhoto = New-HuduPublicPhoto -FilePath $ImageFile -RecordType 'Article' -RecordId $articleUsedId
        $uploadedPublicPhoto = Unwrap-HuduResultObject -InputObject $uploadedPublicPhoto -WrapperNames @('public_photo', 'PublicPhoto')
        if ($uploadedPublicPhoto) {
          $existingRelatedPublicPhotos += $uploadedPublicPhoto
        }
      }

      $usingImage = $existingPublicPhoto ?? $uploadedPublicPhoto
      if ($usingImage) {
        $HuduImages += @{ OriginalFilename = $ImageFile; UsingImage = $usingImage; MediaKind = 'PublicPhoto' }
      }
      continue
    }

    $existingUpload = $existingRelatedUploads | Where-Object { (Get-HuduObjectName -InputObject $_) -eq $imageFileName } | Select-Object -First 1
    if (-not $existingUpload) {
      $existingUpload = $existingRelatedUploads | Where-Object { Test-Equiv -A (Get-HuduObjectName -InputObject $_) -B $imageFileName } | Select-Object -First 1
    }
    $existingUpload = Unwrap-HuduResultObject -InputObject $existingUpload -WrapperNames @('upload')
    $existingUploadId = Get-HuduObjectId -InputObject $existingUpload
    $existingUploadName = Get-HuduObjectName -InputObject $existingUpload
    if ($null -ne $existingUpload -and $true -eq $CalculateHashes -and $existingUploadId -gt 0) {
      $comparison = Compare-UploadHashWithFile -UploadID $existingUploadId -LocalFile $ImageFile
      $existingUploadDate = Get-HuduObjectDateUtc -InputObject $existingUpload
      $existingUploadModifiedDate = $existingUploadDate ?? [datetime]::MinValue
      if ($true -eq $comparison.SameFile) {
        $embedInfo += "Existing embed '$existingUploadName' with id $existingUploadId matches file '$ImageFile' by hash. Reusing current-article upload."; Write-Verbose $embedInfo[-1];
      } else {
        $embedInfo += "Local file hash: $($comparison.LocalHash) is not the same as remote file hash $($comparison.UploadHash)"; Write-Verbose $embedInfo[-1];
        if ($imagemetadata.LastWriteTimeUtc -gt $existingUploadModifiedDate.Add($script:DateCompareJitterHours)) {
          $embedinfo += "Existing article embed with id $existingUploadId modified at $existingUploadModifiedDate; local file last write time is $($imagemetadata.LastWriteTimeUtc). replace with new (local) version."; Write-Verbose $embedInfo[-1];
          $embedInfo += "Existing article embed '$existingUploadName' with id $existingUploadId does NOT match file '$ImageFile' by hash and local file appears newer."; Write-Verbose $embedInfo[-1];
          try {remove-huduupload -id $existingUploadId -confirm:$false} catch { $embedInfo += "Failed to remove older existing upload with id ${existingUploadId}: $($_.Exception.Message)"; write-warning $embedInfo[-1] }
          $existingUpload = $null
        } else {
          $embedInfo += "Existing article embed with id $existingUploadId modified at $existingUploadModifiedDate; local file last write time is $($imagemetadata.LastWriteTimeUtc). keeping existing upload."; Write-Verbose $embedInfo[-1];
          $embedInfo += "Existing article embed '$existingUploadName' with id $existingUploadId does NOT match file '$ImageFile' by hash but local file appears older. keeping existing upload."; Write-Verbose $embedInfo[-1];
        }
      }
    }

    if (-not $existingUpload) {
        $uploaded = New-HuduUpload -FilePath $ImageFile -Uploadable_Type 'Article' -Uploadable_Id $articleUsedId
        $uploaded = Unwrap-HuduResultObject -InputObject $uploaded -WrapperNames @('upload')
        if ($uploaded) {
          $existingRelatedUploads += $uploaded
        }
    }

    $usingImage = $existingUpload ?? $uploaded
    if ($usingImage) {
      $HuduImages += @{ OriginalFilename = $ImageFile; UsingImage = $usingImage; MediaKind = 'Upload' }
    }
  }

  # 3) Match or create article (company or global)


  # 4) Build maps for rewriting
  $imageMap   = New-DocImageMap -HuduImages $HuduImages -HuduBaseUrl $HuduBaseUrl


  $articleUsed = Unwrap-HuduResultObject -InputObject $articleUsed -WrapperNames @('article')
  $articleUsedId = Get-HuduObjectId -InputObject $articleUsed
  $thisUrl = Get-ObjectPropertyValue -InputObject $articleUsed -Names @('url', 'Url')
  $articleMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  if ($thisUrl) {
    $norm = Get-NormalizedTitle $Title; $slug = Get-TitleSlug $Title
    foreach ($k in @($Title,$norm,$slug,"$Title.html","$Title.htm","$slug.html","$slug.htm", ($Title -replace '\s+','_') + '.html')) {
      if ($k -and -not $articleMap.ContainsKey($k)) { $articleMap[$k] = $thisUrl }
    }
  }

  # 5) Resolvers
  $ImageResolver = {
    param([string]$src, [hashtable]$ctx)
    if ([string]::IsNullOrWhiteSpace($src)) { return $null }
    if ($src -match '^(?i)data:') { return $src }
    if ($src -match '^(?i)https?:') { return Convert-HuduMediaUrlToRelative -Url $src -HuduBaseUrl $ctx.HuduBaseUrl }
    $raw = ($src -split '#')[0].Split('?')[0]
    $dec = [System.Web.HttpUtility]::UrlDecode($raw)
    if ($dec -match '^(?i)file:///') { $dec = $dec -replace '^file:///', '' -replace '/', '\' }
    $leaf = Split-Path -Leaf $dec
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
    foreach ($k in @($leaf,$base)) { if ($k -and $ctx.ImageMap.ContainsKey($k)) { return $ctx.ImageMap[$k] } }
    # last try with undecoded leaf
    $leaf2 = Split-Path -Leaf $raw; $base2 = [IO.Path]::GetFileNameWithoutExtension($leaf2)
    foreach ($k in @($leaf2,$base2)) { if ($k -and $ctx.ImageMap.ContainsKey($k)) { return $ctx.ImageMap[$k] } }
    return $null
  }
  $LinkResolver = {
    param([string]$href, [hashtable]$ctx)
    if ([string]::IsNullOrWhiteSpace($href)) { return $null }
    if ($href -match '^(?i)https?:') { return Convert-HuduMediaUrlToRelative -Url $href -HuduBaseUrl $ctx.HuduBaseUrl }
    if ($href.StartsWith('#')) { return $null }
    $raw  = $href.Split('#')[0].Split('?')[0]
    $leaf = Split-Path -Leaf ([System.Web.HttpUtility]::UrlDecode($raw))
    $leafNoEx = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $norm = Get-NormalizedTitle $leafNoEx; $slug = Get-TitleSlug $leafNoEx
    foreach ($k in @($leaf,$leafNoEx,$norm,$slug,"$leafNoEx.html","$leafNoEx.htm","$slug.html","$slug.htm")) {
      if ($k -and $ctx.ArticleMap.ContainsKey($k)) { return $ctx.ArticleMap[$k] }
    }
    return $null
  }

  $ctx = @{ ImageMap = $imageMap; ArticleMap = $articleMap; HuduBaseUrl = $HuduBaseUrl }
  $r = Rewrite-DocLinks -Html $HtmlContents -ImageResolver $ImageResolver -LinkResolver $LinkResolver -Context $ctx
  $articleUpdateParams = @{
    Id = $articleUsedId
    Content = [string]($r.Html ?? '')
  }
  $articleCompanyId = Get-ObjectPropertyValue -InputObject $articleUsed -Names @('company_id', 'companyId', 'CompanyId')
  if ($articleCompanyId) {
    $articleUpdateParams.CompanyId = [int]$articleCompanyId
  }
  $updatedArticle = Set-HuduArticle @articleUpdateParams
  $updatedArticle = Unwrap-HuduResultObject -InputObject $updatedArticle -WrapperNames @('article')
  [pscustomobject]@{
    Title       = $Title
    Article     = $r.Html
    HuduArticle = $updatedArticle
    HuduImages  = $HuduImages
    HuduCompany = $matchedCompany
    EmbedInfo   = $embedInfo
    Rewrites    = $r.Rewrites
    Unresolved  = $r.Unresolved
  }
}

function Invoke-WebRequestThrottled {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Uri,
    [int]$TimeoutSec = 60,
    [hashtable]$Headers,
    [ValidateSet('GET','POST','HEAD','PUT','DELETE','PATCH','OPTIONS','TRACE')][string]$Method = 'GET',
    [int]$DelayMs = 250,
    [int]$Retry = 2,
    [int]$RetryDelayMs = 750,
    [string]$Referer,
    [string]$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/7 PlainFetcher/1.0',
    [switch]$AddDefaultHeaders
  )

  # --- Normalize URI ---
  $u = $Uri.Trim()
  if ($u -notmatch '^(?i)(https?|file)://') {
    Write-Warning "No protocol was specified, adding https:// to the beginning of the specified hostname"
    $u = "https://$u"
  }
  try {
    $uriObj = [Uri]$u
    if (-not $uriObj.IsAbsoluteUri) { throw "URI is not absolute" }
  } catch {
    throw "Invalid Uri '$u' : $($_.Exception.Message)"
  }

  # --- Clean headers: drop null/empty; stringify arrays ---
  $cleanHeaders = @{}
  if ($Headers) {
    foreach ($k in $Headers.Keys) {
      $v = $Headers[$k]
      if ($null -eq $v) { continue }
      if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
        $v = ($v | ForEach-Object { "$_" }) -join ', '
      }
      $vs = "$v".Trim()
      if ($vs -ne '') { $cleanHeaders[$k] = $vs }
    }
  }
  # Ensure non-empty UA even if caller passed null/empty
  if ([string]::IsNullOrWhiteSpace($UserAgent)) {
    $UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/7 PlainFetcher/1.0'
  }
  # Optional: add plain defaults if caller didn’t provide them
  if ($AddDefaultHeaders) {
    if (-not $cleanHeaders.ContainsKey('Accept')) {
      $cleanHeaders['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    }
    if (-not $cleanHeaders.ContainsKey('Accept-Language')) {
      $cleanHeaders['Accept-Language'] = 'en-US,en;q=0.9'
    }
  }

  # --- Build param splat ---

  $params = @{
    Uri                = $uriObj.AbsoluteUri
    Method             = $Method
    TimeoutSec         = $TimeoutSec
    MaximumRedirection = 5
    ErrorAction        = 'Stop'
    UseBasicParsing    = $true
  }
  if ($cleanHeaders.Count -gt 0) { $params.Headers = $cleanHeaders }
  if (-not [string]::IsNullOrWhiteSpace($UserAgent)) { $params.UserAgent = $UserAgent }

  # Referer: only if valid absolute URL
  if ($Referer) {
    try {
      $refObj = [Uri]$Referer
      if ($refObj.IsAbsoluteUri) {
        if (-not $params.ContainsKey('Headers')) { $params.Headers = @{} }
        $params.Headers['Referer'] = $refObj.AbsoluteUri
      }
    } catch { } # ignore bad referer
  }

  # --- Retry loop ---
  for ($i = 0; $i -le $Retry; $i++) {
    try {
      $resp = Invoke-WebRequest @params
      if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
      return $resp
    } catch {
      $msg = $_.Exception.Message
      # Only blame headers if we actually sent some
      $hadHeaders = ($params.ContainsKey('Headers') -and $params.Headers.Count -gt 0)
      if ($hadHeaders -and $msg -match "format of value '' is invalid") {
        $hdrList = ($params.Headers.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key,$_.Value }) -join '; '
        throw "Invalid header value detected. Headers: $hdrList"
      }
      if ($i -lt $Retry) {
        Start-Sleep -Milliseconds $RetryDelayMs
      } else {
        throw
      }
    }
  }
}

function Resolve-Url([string]$BaseUrl, [string]$MaybeRelative) {
  if ([string]::IsNullOrWhiteSpace($MaybeRelative)) { return $null }
  if ($MaybeRelative -match '^(?i)(https?|file|data):') { return $MaybeRelative }
  if (-not $BaseUrl) { return $MaybeRelative }
  try { return (New-Object Uri([Uri]$BaseUrl, $MaybeRelative)).AbsoluteUri } catch { return $MaybeRelative }
}

function Get-PlainHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Html,
    [string]$BaseUrl
  )
  $rxComments = [Regex]::new('<!--.*?-->', 'Singleline')
  $rxScript   = [Regex]::new('<script\b[^>]*>.*?</script>', 'IgnoreCase, Singleline')
  $rxStyleTag = [Regex]::new('<style\b[^>]*>.*?</style>', 'IgnoreCase, Singleline')
  $rxLinkCss  = [Regex]::new('<link\b[^>]*rel=["'']?stylesheet["'']?[^>]*>', 'IgnoreCase, Singleline')
  $rxNoscript = [Regex]::new('<noscript\b[^>]*>.*?</noscript>', 'IgnoreCase, Singleline')

  $rxHref = [Regex]::new('(<a\b[^>]*\bhref\s*=\s*)(["''])(?<u>[^"''#>]+)\2', 'IgnoreCase')
  $rxSrc  = [Regex]::new('(<(?:img|source|video|audio|iframe)\b[^>]*\bsrc\s*=\s*)(["''])(?<u>[^"''>]+)\2', 'IgnoreCase')
  $rxCssUrl = [Regex]::new('url\(\s*(["'']?)(?<u>[^)"'']+)\1\s*\)', 'IgnoreCase')

  $h = $Html
  $h = $rxComments.Replace($h,'')
  $h = $rxScript.Replace($h,'')
  $h = $rxStyleTag.Replace($h,'')
  $h = $rxLinkCss.Replace($h,'')
  $h = $rxNoscript.Replace($h,'')

  # absolutize href/src and CSS url(...)
  $h = $rxHref.Replace($h, { param($m) $pre=$m.Groups[1].Value; $q=$m.Groups[2].Value; $u=$m.Groups['u'].Value; "$pre$q$(Resolve-Url $BaseUrl $u)$q" })
  $h = $rxSrc.Replace($h,  { param($m) $pre=$m.Groups[1].Value; $q=$m.Groups[2].Value; $u=$m.Groups['u'].Value; "$pre$q$(Resolve-Url $BaseUrl $u)$q" })
  $h = $rxCssUrl.Replace($h, { param($m) "url($(Resolve-Url $BaseUrl $m.Groups['u'].Value))" })

  # minimal skeleton if needed
  if (-not ($h -match '<html')) {
    $h = "<!doctype html><html><head><meta charset=""utf-8""></head><body>$h</body></html>"
  }
  $h
}

function Get-HtmlImageUrls {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Html
  )
  $rxImgSrc = [Regex]::new('<img\b[^>]*?\bsrc\s*=\s*(["''])(?<u>.*?)\1', 'IgnoreCase, Singleline')
  $rxSrcset = [Regex]::new('\bsrcset\s*=\s*(["''])(?<s>.*?)\1', 'IgnoreCase, Singleline')
  $rxCssUrl = [Regex]::new('url\(\s*(["'']?)(?<u>[^)"'']+)\1\s*\)', 'IgnoreCase, Singleline')

  $urls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in $rxImgSrc.Matches($Html)) { [void]$urls.Add($m.Groups['u'].Value) }
  foreach ($m in $rxSrcset.Matches($Html)) {
    foreach ($part in ($m.Groups['s'].Value -split ',')) {
      $u = ($part -split '\s+')[0].Trim(); if ($u) { [void]$urls.Add($u) }
    }
  }
  foreach ($m in $rxCssUrl.Matches($Html)) { [void]$urls.Add($m.Groups['u'].Value) }
  $urls
}

function Save-DataUriImage {
  param([string]$DataUri, [string]$OutputDir, [string]$FileBase = 'inline')
  if ($DataUri -notmatch '^data:(?<mime>[^;]+);base64,(?<b64>.+)$') { return $null }
  $mime = $Matches['mime']; $b64 = $Matches['b64']
  $ext  = switch -regex ($mime) {
    '^image/png'  { '.png'  ; break }
    '^image/jpeg' { '.jpg'  ; break }
    '^image/gif'  { '.gif'  ; break }
    '^image/webp' { '.webp' ; break }
    '^image/svg'  { '.svg'  ; break }
    default       { '.bin'  }
  }
  $bytes = [Convert]::FromBase64String($b64)
  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null
  $path = Join-Path $OutputDir ($FileBase + $ext)
  $i=1; while (Test-Path $path) { $path = Join-Path $OutputDir ("{0}_{1}{2}" -f $FileBase,$i,$ext); $i++ }
  [IO.File]::WriteAllBytes($path, $bytes)
  return $path
}


function Get-PlainPageAndImages {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$OutputDir,
    [hashtable]$Headers,        # e.g. @{ Authorization = "Bearer xxx"; Cookie = "..." }
    [int]$DelayMs = 250,        # throttle
    [int]$TimeoutSec = 60,
    [string]$UserAgent
  )

  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null

  # 1) fetch
  if ($Headers -and $Headers.Keys.count -gt 0){
    $resp = Invoke-WebRequestThrottled -Uri $Url -Headers $Headers -DelayMs $DelayMs -TimeoutSec $TimeoutSec -UserAgent $UserAgent
  } else {
    $resp = Invoke-WebRequestThrottled -Uri $Url -AddDefaultHeaders -DelayMs $DelayMs -TimeoutSec $TimeoutSec -UserAgent $UserAgent
  }
  $origHtml = $resp.Content
  $baseUrl  = $resp.BaseResponse.ResponseUri.AbsoluteUri

  # 2) normalize to plain-jane html
  $plainHtml = Get-PlainHtml -Html $origHtml -BaseUrl $baseUrl

  # 3) collect & download images (respect same headers & throttle)
  $urls = Get-HtmlImageUrls -Html $plainHtml
  $downloads = New-Object System.Collections.Generic.List[object]

  foreach ($raw in $urls) {
    $u = Resolve-Url $baseUrl $raw
    $saved = $null; $ok=$false; $err=$null
    try {
      if ($u -match '^(?i)data:image/') {
        $saved = Save-DataUriImage -DataUri $u -OutputDir $OutputDir -FileBase 'inline'
        $ok = [bool]$saved
      }
      elseif ($u -match '^(?i)file://') {
        $src = ($u -replace '^file:///?','') -replace '/','\'
        $leaf = Split-Path -Leaf $src; $dest = Join-Path $OutputDir $leaf
        $i=1; while (Test-Path $dest) { $dest = Join-Path $OutputDir ("{0}_{1}{2}" -f ([IO.Path]::GetFileNameWithoutExtension($leaf)),$i,[IO.Path]::GetExtension($leaf)); $i++ }
        Copy-Item -LiteralPath $src -Destination $dest -Force
        $saved = $dest; $ok = $true
      }
      else {
        $leaf = ($u -as [uri]).Segments[-1]; if (-not $leaf) { $leaf = 'image' }
        $tmp = Join-Path $OutputDir ([IO.Path]::GetRandomFileName())
        $respImg = Invoke-WebRequestThrottled -Uri $u -Headers $Headers -DelayMs $DelayMs -TimeoutSec $TimeoutSec -Referer $baseUrl
        [IO.File]::WriteAllBytes($tmp, $respImg.Content)

        $ext = [IO.Path]::GetExtension($leaf)
        if (-not $ext -and $respImg.Headers.'Content-Type') {
          $ext = switch -regex ($respImg.Headers.'Content-Type') {
            'image/png'  { '.png' } 'image/jpeg' { '.jpg' } 'image/gif' { '.gif' }
            'image/webp' { '.webp'} 'image/svg'  { '.svg' } default { '.img' }
          }
        }
        if (-not $ext) { $ext = '.img' }
        $name = ([IO.Path]::GetFileNameWithoutExtension($leaf)); if (-not $name) { $name = 'image' }
        $dest = Join-Path $OutputDir ($name + $ext)
        $i=1; while (Test-Path $dest) { $dest = Join-Path $OutputDir ("{0}_{1}{2}" -f $name,$i,$ext); $i++ }
        Move-Item -LiteralPath $tmp -Destination $dest -Force
        $saved = $dest; $ok=$true
      }
    } catch { $err = $_.Exception.Message }
    $downloads.Add([pscustomobject]@{ Url=$u; SavedPath=$saved; Success=$ok; Error=$err }) | Out-Null
  }

  # 4) save the normalized HTML too (optional)
  $htmlPath = Join-Path $OutputDir 'page.plain.html'
  Set-Content -LiteralPath $htmlPath -Encoding UTF8 -Value $plainHtml
  $images = Get-ChildItem -LiteralPath $OutputDir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tif|tiff)$' } |
            Select-Object -ExpandProperty FullName

  [pscustomobject]@{
    Url        = $baseUrl
    HtmlPath   = $htmlPath
    Html       = $plainHtml
    Images     = $images
    ImagesDir  = $OutputDir
    Downloads  = $downloads
  }
}

function Get-HTMLAndImagesArrayFromPDF {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$InputPdfPath,
    [string]$PdfToHtmlPath
  )

  if (-not (Test-Path -LiteralPath $InputPdfPath -PathType Leaf)) {
    throw "PDF not found: $InputPdfPath"
  }

  # Make a unique temp dir for output
  $OutputDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null

  # Ensure pdftohtml exists; if not, fetch Poppler and point to Library\bin\pdftohtml.exe
  if (-not $PdfToHtmlPath -or -not (Test-Path -LiteralPath $PdfToHtmlPath)) {
    $cachedPdfToHtmlPath = if (Get-Variable -Name PDFToHTMLTempBinLocation -Scope Script -ErrorAction SilentlyContinue) {
      $Script:PDFToHTMLTempBinLocation
    } else {
      $null
    }
    if (-not $cachedPdfToHtmlPath -or -not (Test-Path -LiteralPath $cachedPdfToHtmlPath)) {

    $url  = 'https://github.com/oschwartz10612/poppler-windows/releases/download/v25.07.0-0/Release-25.07.0-0.zip'
    $root = Join-Path $env:TEMP ("poppler-" + [guid]::NewGuid())
    $zip  = Join-Path $root 'poppler.zip'
    [IO.Directory]::CreateDirectory($root) | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $root -Force
    $bin = Get-ChildItem -Recurse -Directory $root -Filter bin |
           Where-Object { $_.FullName -match '\\Library\\bin$' } |
           Select-Object -First 1 -ExpandProperty FullName
    if (-not $bin) { throw "Could not find Library\bin in downloaded Poppler zip." }
    $PdfToHtmlPath = Join-Path $bin 'pdftohtml.exe'
    } else {
      Write-Host "Reusing Script-Temp PDFtoHTML location $cachedPdfToHtmlPath"
      $PdfToHtmlPath = $cachedPdfToHtmlPath
    }
  }

  if (-not (Test-Path -LiteralPath $PdfToHtmlPath)) {
    throw "pdftohtml not found at: $PdfToHtmlPath"
  } else {
    $Script:PDFToHTMLTempBinLocation = $PdfToHtmlPath
  }

    $base       = [IO.Path]::GetFileNameWithoutExtension($InputPdfPath)
    $OutputDir  = $OutputDir ?? (Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName()))
    [IO.Directory]::CreateDirectory($OutputDir) | Out-Null
    $htmlOutput = Join-Path $OutputDir ($base + '.html')

    $argumentsArray = @(
    '-s',                 # single HTML file
    '-noframes',
    '-enc','UTF-8',
    '-c',                 # complex layout
    '-fmt','png',         # normalize images
    $InputPdfPath,        # <-- use the function param, not $doc.FullName
    $htmlOutput
    )

    Write-Host "Using pdftohtml: $PdfToHtmlPath"
    Write-Host "Args: $($argumentsArray -join ' ')"
    & $PdfToHtmlPath @argumentsArray 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $htmlOutput)) {
    throw "pdftohtml failed (exit $LASTEXITCODE) or output missing: $htmlOutput"
    }

  # Collect images that pdftohtml emitted next to the HTML
  $images = Get-ChildItem -LiteralPath $OutputDir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tif|tiff)$' } |
            Select-Object -ExpandProperty FullName

  # Read HTML as a single string
  $html = Get-Content -LiteralPath $htmlOutput -Raw -Encoding UTF8

  [pscustomobject]@{
    HtmlPath  = $htmlOutput
    Html      = $html
    Images    = $images
    OutputDir = $OutputDir
    ToolPath  = $PdfToHtmlPath
  }
}

function Get-HTMLFromPDFPlainText {
  param(
    [Parameter(Mandatory)][string]$InputPdfPath,
    [string]$PdfToTextPath
  )

  if (-not (Test-Path -LiteralPath $InputPdfPath -PathType Leaf)) {
    throw "PDF not found: $InputPdfPath"
  }

  $OutputDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null

  if (-not $PdfToTextPath -or -not (Test-Path -LiteralPath $PdfToTextPath)) {
    $cachedPdfToTextPath = if (Get-Variable -Name PDFToTextTempBinLocation -Scope Script -ErrorAction SilentlyContinue) {
      $Script:PDFToTextTempBinLocation
    } else {
      $null
    }
    if (-not $cachedPdfToTextPath -or -not (Test-Path -LiteralPath $cachedPdfToTextPath)) {
      $url  = 'https://github.com/oschwartz10612/poppler-windows/releases/download/v25.07.0-0/Release-25.07.0-0.zip'
      $root = Join-Path $env:TEMP ("poppler-" + [guid]::NewGuid())
      $zip  = Join-Path $root 'poppler.zip'
      [IO.Directory]::CreateDirectory($root) | Out-Null
      Invoke-WebRequest -Uri $url -OutFile $zip
      Expand-Archive -Path $zip -DestinationPath $root -Force
      $bin = Get-ChildItem -Recurse -Directory $root -Filter bin |
             Where-Object { $_.FullName -match '\\Library\\bin$' } |
             Select-Object -First 1 -ExpandProperty FullName
      if (-not $bin) { throw "Could not find Library\bin in downloaded Poppler zip." }
      $PdfToTextPath = Join-Path $bin 'pdftotext.exe'
    } else {
      Write-Host "Reusing Script-Temp PDFtoText location $cachedPdfToTextPath"
      $PdfToTextPath = $cachedPdfToTextPath
    }
  }

  if (-not (Test-Path -LiteralPath $PdfToTextPath)) {
    throw "pdftotext not found at: $PdfToTextPath"
  } else {
    $Script:PDFToTextTempBinLocation = $PdfToTextPath
  }

  $base = [IO.Path]::GetFileNameWithoutExtension($InputPdfPath)
  $textOutput = Join-Path $OutputDir ($base + '.txt')
  $argumentsArray = @(
    '-layout',
    '-enc', 'UTF-8',
    $InputPdfPath,
    $textOutput
  )

  Write-Host "Using pdftotext: $PdfToTextPath"
  Write-Host "Args: $($argumentsArray -join ' ')"
  & $PdfToTextPath @argumentsArray 2>&1 | Write-Host
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $textOutput)) {
    throw "pdftotext failed (exit $LASTEXITCODE) or output missing: $textOutput"
  }

  $plainText = Get-Content -LiteralPath $textOutput -Raw -Encoding UTF8
  $encodedText = [System.Net.WebUtility]::HtmlEncode($plainText)
  $encodedName = [System.Net.WebUtility]::HtmlEncode([IO.Path]::GetFileName($InputPdfPath))
  $html = "<h2>$encodedName</h2><pre><code>$encodedText</code></pre>$(Get-MetadataArticleBlock -filePath $InputPdfPath)"

  [pscustomobject]@{
    HtmlPath  = $textOutput
    Html      = $html
    Images    = @()
    OutputDir = $OutputDir
    ToolPath  = $PdfToTextPath
  }
}

function Get-HTMLFromPDFRasterized {
  param(
    [Parameter(Mandatory)][string]$InputPdfPath,
    [string]$PdfToPpmPath,
    [int]$ResolutionDpi = 144
  )

  if (-not (Test-Path -LiteralPath $InputPdfPath -PathType Leaf)) {
    throw "PDF not found: $InputPdfPath"
  }

  $OutputDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null

  if (-not $PdfToPpmPath -or -not (Test-Path -LiteralPath $PdfToPpmPath)) {
    $cachedPdfToPpmPath = if (Get-Variable -Name PDFToPpmTempBinLocation -Scope Script -ErrorAction SilentlyContinue) {
      $Script:PDFToPpmTempBinLocation
    } else {
      $null
    }
    if (-not $cachedPdfToPpmPath -or -not (Test-Path -LiteralPath $cachedPdfToPpmPath)) {
      $url  = 'https://github.com/oschwartz10612/poppler-windows/releases/download/v25.07.0-0/Release-25.07.0-0.zip'
      $root = Join-Path $env:TEMP ("poppler-" + [guid]::NewGuid())
      $zip  = Join-Path $root 'poppler.zip'
      [IO.Directory]::CreateDirectory($root) | Out-Null
      Invoke-WebRequest -Uri $url -OutFile $zip
      Expand-Archive -Path $zip -DestinationPath $root -Force
      $bin = Get-ChildItem -Recurse -Directory $root -Filter bin |
             Where-Object { $_.FullName -match '\\Library\\bin$' } |
             Select-Object -First 1 -ExpandProperty FullName
      if (-not $bin) { throw "Could not find Library\bin in downloaded Poppler zip." }
      $PdfToPpmPath = Join-Path $bin 'pdftoppm.exe'
    } else {
      Write-Host "Reusing Script-Temp PDFtoPPM location $cachedPdfToPpmPath"
      $PdfToPpmPath = $cachedPdfToPpmPath
    }
  }

  if (-not (Test-Path -LiteralPath $PdfToPpmPath)) {
    throw "pdftoppm not found at: $PdfToPpmPath"
  } else {
    $Script:PDFToPpmTempBinLocation = $PdfToPpmPath
  }

  $outputPrefix = Join-Path $OutputDir 'page'
  $argumentsArray = @(
    '-png',
    '-r', $ResolutionDpi,
    $InputPdfPath,
    $outputPrefix
  )

  Write-Host "Using pdftoppm: $PdfToPpmPath"
  Write-Host "Args: $($argumentsArray -join ' ')"
  & $PdfToPpmPath @argumentsArray 2>&1 | Write-Host
  if ($LASTEXITCODE -ne 0) {
    throw "pdftoppm failed (exit $LASTEXITCODE)."
  }

  $imageFiles = @(Get-ChildItem -LiteralPath $OutputDir -File -Filter "page*.png" -ErrorAction SilentlyContinue |
    Sort-Object @{ Expression = { if ($_.BaseName -match '(\d+)$') { [int]$matches[1] } else { 0 } } }, Name)
  if ($imageFiles.Count -eq 0) {
    throw "pdftoppm did not create any rasterized page images in: $OutputDir"
  }

  $encodedName = [System.Net.WebUtility]::HtmlEncode([IO.Path]::GetFileName($InputPdfPath))
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine("<h2>$encodedName</h2>")
  [void]$sb.AppendLine('<div class="pdf-raster-document">')
  $pageNumber = 1
  foreach ($imageFile in $imageFiles) {
    $leaf = [System.Net.WebUtility]::HtmlEncode($imageFile.Name)
    [void]$sb.AppendLine("<figure class=`"pdf-raster-page`" style=`"margin:0 0 2rem 0;`">")
    [void]$sb.AppendLine("<img src=`"$leaf`" alt=`"$encodedName page $pageNumber`" style=`"max-width:100%;height:auto;display:block;margin:0 auto;`" />")
    [void]$sb.AppendLine("<figcaption style=`"color:#667085;font-size:0.875rem;margin-top:0.5rem;text-align:center;`">Page $pageNumber</figcaption>")
    [void]$sb.AppendLine('</figure>')
    $pageNumber += 1
  }
  [void]$sb.AppendLine('</div>')
  [void]$sb.AppendLine((Get-MetadataArticleBlock -filePath $InputPdfPath))

  [pscustomobject]@{
    HtmlPath  = $null
    Html      = $sb.ToString()
    Images    = @($imageFiles | Select-Object -ExpandProperty FullName)
    OutputDir = $OutputDir
    ToolPath  = $PdfToPpmPath
  }
}

function Set-HuduArticleFromPDF {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$PdfPath,
    [string]$CompanyName,
    [string]$Title,
    [bool]$includeOriginal=$true, # include original pdf attached to converted article
    [bool]$CalculateHashes = $true,
    [int]$MaxHtmlCharacters = 0,
    [bool]$PlainTextConversion = $true,
    [AllowEmptyString()]
    [ValidateSet('','plaintext','html','rasterized')]
    [string]$PdfMigrationStrategy = ''
  )

    $null = Get-EnsuredPath -Path $DocConversionTempDir

    if (-not (Get-Variable -Name CurrentHuduVersion -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:CurrentHuduVersion) {
        $appInfo = Get-HuduAppInfo
        $script:CurrentHuduVersion = [version]$appInfo.version
    }

    if (-not (Get-Variable -Name DateCompareJitterHours -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:DateCompareJitterHours) {
        $script:DateCompareJitterHours = [timespan]::FromHours(12)
    }
  if (-not (Test-Path -LiteralPath $PdfPath -PathType Leaf)) { write-warning "NO PDF, $($PdfPath)"; return $null }

  $pdfBaseName = [IO.Path]::GetFileNameWithoutExtension($PdfPath)

  $effectivePdfMigrationStrategy = if ([string]::IsNullOrWhiteSpace($PdfMigrationStrategy)) {
    if ($PlainTextConversion) { 'plaintext' } else { 'html' }
  } else {
    $PdfMigrationStrategy
  }
  Write-Host "PDF migration strategy: $effectivePdfMigrationStrategy"

  $pdfData = switch ($effectivePdfMigrationStrategy) {
    'plaintext' { Get-HTMLFromPDFPlainText -InputPdfPath $PdfPath; break }
    'html' { Get-HTMLAndImagesArrayFromPDF -InputPdfPath $PdfPath; break }
    'rasterized' { Get-HTMLFromPDFRasterized -InputPdfPath $PdfPath; break }
    default { throw "Unsupported PDF migration strategy: $effectivePdfMigrationStrategy" }
  }

  $displayTitle = if ($Title) { $Title } else { $pdfBaseName }

  if ($MaxHtmlCharacters -gt 0 -and $pdfData.Html.Length -gt $MaxHtmlCharacters) {
    $matchedCompany = $null
    if ($CompanyName) {
      $matchedCompany = ChoseBest-ByName -Name $CompanyName -choices (Get-HuduCompanies)
    }

    $articleUsed = if ($matchedCompany) {
      Get-HuduArticles -CompanyId $matchedCompany.id -Name $displayTitle | Select-Object -First 1
    } else {
      Get-HuduArticles -Name $displayTitle | Where-Object { $null -eq $_.company_id } | Select-Object -First 1
    }
    $articleUsed = Unwrap-HuduResultObject -InputObject $articleUsed -WrapperNames @('article')

    if (-not $articleUsed) {
      $articleUsed = if ($matchedCompany) {
        New-HuduArticle -Name $displayTitle -Content "Attaching Upload" -CompanyId $matchedCompany.id
      } else {
        New-HuduArticle -Name $displayTitle -Content "Attaching Upload"
      }
      $articleUsed = Unwrap-HuduResultObject -InputObject $articleUsed -WrapperNames @('article')
    }

    $uploadInfo = Ensure-HuduArticleUploadForFile `
      -ArticleId $articleUsed.id `
      -FilePath $PdfPath `
      -CalculateHashes ([bool]$($CalculateHashes -and $script:CurrentHuduVersion -ge [version]'2.41.0'))
    $upload = $uploadInfo.Upload

    $content = "<h2>$([System.Net.WebUtility]::HtmlEncode([IO.Path]::GetFileName($PdfPath)))</h2><p>Converted HTML was $($pdfData.Html.Length) characters, over limit $MaxHtmlCharacters. Original file attached instead.</p><p><a href='$($upload.url)'>See attached document</a></p>"
    $updatedArticle = if ($matchedCompany) {
      Set-HuduArticle -Id $articleUsed.id -CompanyId $matchedCompany.id -Content $content
    } else {
      Set-HuduArticle -Id $articleUsed.id -Content $content
    }
    $updatedArticle = Unwrap-HuduResultObject -InputObject $updatedArticle -WrapperNames @('article')

    return [pscustomobject]@{
      Title       = $displayTitle
      Article     = $content
      HuduArticle = $updatedArticle
      HuduImages  = @()
      HuduCompany = $matchedCompany
      EmbedInfo   = @("PDF converted HTML was $($pdfData.Html.Length) characters, over limit $MaxHtmlCharacters. Used attachment-only fallback.")
      Rewrites    = @()
      Unresolved  = @()
      OriginalUpload = $upload
      OriginalUploadInfo = $uploadInfo
    }
  }

  $newDoc = Set-HuduArticleFromHtml `
              -ImagesArray  ($pdfData.Images ?? @()) `
              -CompanyName  $CompanyName `
              -Title        $displayTitle `
              -HtmlContents $pdfData.Html `
              -HuduBaseUrl  (Get-HuduBaseURL) -calculatehashes ([bool]$($CalculateHashes -and $script:CurrentHuduVersion -ge [version]'2.41.0'))

  if ($true -eq $includeOriginal){
    $uploadInfo = Ensure-HuduArticleUploadForFile `
      -ArticleId $newDoc.HuduArticle.Id `
      -FilePath $PdfPath `
      -CalculateHashes ([bool]$($CalculateHashes -and $script:CurrentHuduVersion -ge [version]'2.41.0'))
    $newDoc | Add-Member -MemberType NoteProperty -Name OriginalUpload -Value $uploadInfo.Upload -Force
    $newDoc | Add-Member -MemberType NoteProperty -Name OriginalUploadInfo -Value $uploadInfo -Force
  }

  return $newDoc
}

function Set-HuduArticleFromWebPage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Uri,
    [hashtable]$AddtlHeaders = @{},
    [string]$CompanyName,
    [string]$Title
  )

  $uuid = [guid]::NewGuid().ToString()
  $dest = Join-Path $env:TEMP ("grab-" + $uuid)

  $web = Get-PlainPageAndImages -Url $Uri -OutputDir $dest -Headers $AddtlHeaders -DelayMs 300

  # flat list of saved image paths
  $imagePaths = @()
  if ($web -and $web.Downloads) {
    $imagePaths = $web.Downloads | Where-Object Success | Select-Object -ExpandProperty SavedPath
  }
  $displayTitle = if ($Title) { $Title } else { "Captured page ($uuid)" }

  $newDoc = Set-HuduArticleFromHtml `
              -ImagesArray  ($imagePaths ?? @()) `
              -CompanyName  $CompanyName `
              -Title        $displayTitle `
              -HtmlContents $web.Html `
              -HuduBaseUrl  (Get-HuduBaseURL)

  return $newDoc
}

function Set-HuduArticleFromResourceFolder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ResourcesFolder,
    [string]$CompanyName,
    [string]$Title
  )

  if (-not (Test-Path -LiteralPath $ResourcesFolder -PathType Container)) {
    Write-Warning "NO FOLDER, $ResourcesFolder"; return $null
  }

  try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}

  $uuid    = [guid]::NewGuid().ToString()
  $htmlDoc = Get-ChildItem -LiteralPath $ResourcesFolder -File -Filter '*.html' | Select-Object -First 1

  $images = Get-ChildItem -LiteralPath $ResourcesFolder -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tif|tiff|webp|svg)$' } |
            Select-Object -ExpandProperty FullName

  $other  = Get-ChildItem -LiteralPath $ResourcesFolder -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(pdf|docx?|xlsx?|pptx?|txt|csv|md|zip)$' } |
            Select-Object -ExpandProperty FullName

  $html = ''

  if ($htmlDoc) {
    Write-Verbose "Using existing HTML file: $($htmlDoc.FullName)"
    $html = Get-Content -LiteralPath $htmlDoc.FullName -Raw -Encoding UTF8
  }

  # If no HTML file, or it was empty/whitespace, scaffold a simple gallery/list page
  if ([string]::IsNullOrWhiteSpace($html)) {
    if (-not $htmlDoc) {
      Write-Verbose ("No .html found in {0}{1}. Generating basic HTML from resources." -f $ResourcesFolder, $(if ($CompanyName) { " for $CompanyName" } else { "" }))
    } else {
      Write-Verbose "Existing HTML was empty; generating scaffold."
    }

    if ((-not $images -or $images.Count -lt 1) -and (-not $other -or $other.Count -lt 1)) {
      throw "No .html and no supported resources present in '$ResourcesFolder'."
    }

    $parentFolder = [IO.Path]::GetFileName($ResourcesFolder.TrimEnd('\','/'))
    $dispTitle    = if ($Title) { $Title } else { "Directory Listing from $parentFolder" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html>')
    [void]$sb.AppendLine('<html><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<style>body{font-family:sans-serif} .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px} figure{margin:0;border:1px solid #ddd;padding:8px;border-radius:8px} figcaption{font-size:12px;color:#555;margin-top:6px;word-break:break-word}</style>')
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine(('<h1>{0}</h1>' -f ([System.Web.HttpUtility]::HtmlEncode($dispTitle))))

    if ($images -and $images.Count -gt 0) {
      [void]$sb.AppendLine('<h2>Images</h2><div class="grid">')
      foreach ($p in $images) {
        $leaf = [IO.Path]::GetFileName($p)
        $alt  = [System.Web.HttpUtility]::HtmlEncode($leaf)
        [void]$sb.AppendLine(('<figure><img src="{0}" alt="{1}" loading="lazy" style="max-width:100%;height:auto"><figcaption>{1}</figcaption></figure>' -f $leaf,$alt))
      }
      [void]$sb.AppendLine('</div>')
    }

    if ($other -and $other.Count -gt 0) {
      [void]$sb.AppendLine('<h2>Other Files</h2><ul>')
    }

    [void]$sb.AppendLine('</body></html>')
    $html = $sb.ToString()
  }

  if ([string]::IsNullOrWhiteSpace($html)) {
    Write-Verbose "HTML still empty after scaffold; inserting minimal stub."
    $safeTitle = [System.Web.HttpUtility]::HtmlEncode($(if ($Title) { $Title } else { $uuid }))
    $html = "<!doctype html><html><head><meta charset=""utf-8""></head><body><h1>$safeTitle</h1></body></html>"
  }

  $displayTitle = if ($Title) {
    $Title
  } elseif ($dispTitle){
    $dispTitle
  } elseif ($htmlDoc) {
    [IO.Path]::GetFileNameWithoutExtension($htmlDoc.Name)
  } else {
    $uuid
  }

  Write-Verbose ("Scaffold complete: htmlLen={0}, images={1}, other={2}" -f ($html.Length), ($images?.Count ?? 0), ($other?.Count ?? 0))

  if ($other -and $other.count -gt 0){
    $newDoc = Set-HuduArticleFromHtml `
                -ImagesArray  ($images ?? @()) `
                -CompanyName  $CompanyName `
                -Title        $displayTitle `
                -HtmlContents $html `
                -uploadsAsResources $other `
                -HuduBaseUrl  (Get-HuduBaseURL)
  } else {
    $newDoc = Set-HuduArticleFromHtml `
                -ImagesArray  ($images ?? @()) `
                -CompanyName  $CompanyName `
                -Title        $displayTitle `
                -HtmlContents $html `
                -HuduBaseUrl  (Get-HuduBaseURL)    
  }

  return $newDoc
}


function Write-Info {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )
    $VerbosePreference = 'Continue'
    write-verbose $Message
    $VerbosePreference = 'SilentlyContinue'
}
function Test-DocumentSetSafety {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo[]]$Items,

        [int]$MaxItems,
        [long]$MaxTotalBytes,
        [long]$MaxItemBytes
    )

    if (-not $Items -or $Items.Count -eq 0) {
        Write-Warning "No source items found after filtering."
        return $false
    }

    $files = $Items | Where-Object { -not $_.PSIsContainer }

    $count       = $Items.Count
    $fileCount   = $files.Count
    $totalBytes  = ($files | Measure-Object Length -Sum).Sum
    $largestItem = ($files  | Measure-Object Length -Maximum).Maximum

    $tooMany      = $count      -gt $MaxItems
    $tooLargeTotal= $totalBytes -gt $MaxTotalBytes
    $tooLargeItem = $largestItem -gt $MaxItemBytes

    Write-Info -Message "Selected items: $count (files: $fileCount)"
    Write-Info -Message ("Total size   : {0:N0} bytes" -f $totalBytes)
    Write-Info -Message ("Largest item : {0:N0} bytes" -f $largestItem)

    if (-not ($tooMany -or $tooLargeTotal -or $tooLargeItem)) {
        return $true
    }

    Write-Warning "One or more safety limits were exceeded:"
    if ($tooMany) {
        Write-Warning " - Item count $count exceeds MaxItems $MaxItems"
    }
    if ($tooLargeTotal) {
        Write-Warning (" - Total size {0:N0} exceeds MaxTotalBytes {1:N0}" -f $totalBytes, $MaxTotalBytes)
    }
    if ($tooLargeItem) {
        Write-Warning (" - Largest item {0:N0} exceeds MaxItemBytes {1:N0}" -f $largestItem, $MaxItemBytes)
    }


    $answer = Read-Host "Type 'YES' to proceed anyway (anything else will abort)"
    if ($answer -eq 'YES') {
        Write-Warning "Proceeding despite safety warnings."
        return $true
    } else {
        Write-Info -Message "Aborting per user choice."
        return $false
    }
}

function Test-ShouldUpdateUpload {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][bool]$UpdateOnMatch,
    [Parameter(Mandatory)][ValidateSet('date','filehash','none')][string]$Strategy,

    [Parameter(Mandatory)][datetime]$SourceMTimeUtc,
    [string]$SourceSha256,

    # destination (may be $null if no upload yet)
    [object]$DestUpload
  )

  if (-not $UpdateOnMatch) { return $false }
  if ($Strategy -eq 'none') { return $false }
  if ($null -eq $DestUpload) { return $true } # nothing exists yet => upload

  # normalize dest updated time to UTC
  $destUpdatedUtc = $null
  if ($DestUpload.PSObject.Properties.Name -contains 'created_at' -and $DestUpload.updated_at) {
    try { $destUpdatedUtc = ([datetime]$DestUpload.updated_at).ToUniversalTime() } catch {}
  }

  switch ($Strategy) {
    'date' {
      if ($null -eq $destUpdatedUtc) { return $true }           # can’t compare => choose update
      return ($SourceMTimeUtc -gt $destUpdatedUtc)
    }

    'filehash' {
      if ([string]::IsNullOrWhiteSpace($SourceSha256)) { return $true } # can’t compare => update

      $destHash = $null
      foreach ($p in @('sha256','checksum','hash')) {
        if ($DestUpload.PSObject.Properties.Name -contains $p -and $DestUpload.$p) { $destHash = $DestUpload.$p; break }
      }

      # fallback if no hash (as in folder / dir upload strategy) is to compare by date if available, otherwise update
      if ([string]::IsNullOrWhiteSpace($destHash)) {
        if ($null -ne $destUpdatedUtc) { return ($SourceMTimeUtc -gt $destUpdatedUtc) }
        return $true
      }

      return ($SourceSha256.ToUpperInvariant() -ne $destHash.ToUpperInvariant())
    }
  }
}

function Test-ShouldUpdateUpload {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][bool]$UpdateOnMatch,
    [Parameter(Mandatory)][ValidateSet('date','filehash','none')][string]$Strategy,
    # local
    [Parameter(Mandatory)][datetime]$SourceMTimeUtc,
    [string]$SourceSha256,
    [object]$DestUpload
  )

  if (-not $UpdateOnMatch) { return $false }
  if ($Strategy -eq 'none') { return $false }
  if ($null -eq $DestUpload) { return $true }

  # normalize dest updated time to UTC
  $destUpdatedUtc = $null
  if ($DestUpload.PSObject.Properties.Name -contains 'updated_at' -and $DestUpload.updated_at) {
    try { $destUpdatedUtc = ([datetime]$DestUpload.updated_at).ToUniversalTime() } catch {}
  }

  switch ($Strategy) {
    'date' {
      if ($null -eq $destUpdatedUtc) { return $true }           # can’t compare => choose update
      return ($SourceMTimeUtc -gt $destUpdatedUtc)
    }

    'filehash' {
      if ([string]::IsNullOrWhiteSpace($SourceSha256)) { return $true } # can’t compare => update

      # If your Hudu upload object includes a hash/checksum field, use it here.
      $destHash = $null
      foreach ($p in @('sha256','checksum','hash')) {
        if ($DestUpload.PSObject.Properties.Name -contains $p -and $DestUpload.$p) { $destHash = $DestUpload.$p; break }
      }

      # fall back to date if no hash is available (folder) 
      if ([string]::IsNullOrWhiteSpace($destHash)) {
        if ($null -ne $destUpdatedUtc) { return ($SourceMTimeUtc -gt $destUpdatedUtc) }
        return $true
      }

      return ($SourceSha256.ToUpperInvariant() -ne $destHash.ToUpperInvariant())
    }
  }
}
function Normalize-ArticleContentForHash {
  param([AllowNull()][string]$Content)
  if ($null -eq $Content) { return "" }
  return (($Content -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}
function Get-StringSha256 {
  param([AllowNull()][string]$Text)
  $normalized = Normalize-ArticleContentForHash -Content $Text
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "")
  } finally {
    $sha.Dispose()
  }
}
function Get-HuduObjectDateUtc {
  param([object]$InputObject)
  foreach ($name in @('updated_at', 'updated_date', 'updatedAt', 'created_at', 'created_date', 'createdAt')) {
    $value = Get-ObjectPropertyValue -InputObject $InputObject -Names @($name)
    if ($value) {
      try { return ([datetime]$value).ToUniversalTime() } catch {}
    }
  }
  return $null
}
function Test-ShouldUpdateArticleContent {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$NewContent,
    [Parameter(Mandatory)][object]$MatchedArticle,
    [Parameter(Mandatory)][datetime]$SourceMTimeUtc,
    [timespan]$Jitter = [timespan]::FromHours(12)
  )

  $existingContent = Get-ObjectPropertyValue -InputObject $MatchedArticle -Names @('content', 'Content')
  $newHash = Get-StringSha256 -Text $NewContent
  $existingHash = Get-StringSha256 -Text $existingContent
  $remoteUpdatedUtc = Get-HuduObjectDateUtc -InputObject $MatchedArticle
  $sameContent = $newHash -eq $existingHash
  $localNewer = if ($remoteUpdatedUtc) { $SourceMTimeUtc -gt $remoteUpdatedUtc.Add($Jitter) } else { $true }

  [pscustomobject]@{
    SameContent      = $sameContent
    ShouldUpdate     = (-not $sameContent) -and $localNewer
    LocalNewer       = $localNewer
    LocalHash        = $newHash
    RemoteHash       = $existingHash
    RemoteUpdatedUtc = $remoteUpdatedUtc
  }
}
function New-HuduArticleFromLocalResource {
  param (
    [string]$resourceLocation,
    [string]$companyName=$null,
    [array]$companyDocs=$null,
    [bool]$updateOnMatch=$true,
    [ValidateSet('date','filehash','none')][string]$UpdateStrategy='filehash',
    [bool]$includeOriginals=$true,
    [bool]$PlainTextPdfConversion=$true,
    [AllowEmptyString()]
    [ValidateSet('','plaintext','html','rasterized')]
    [string]$PdfMigrationStrategy = '',
    [int]$MaxHtmlCharacters=254000,
    [Parameter(Mandatory)][string]$DocConversionTempDir,
    [array]$EmbeddableImageExtensions=@(".jpg", ".jpeg",".png",".gif",".bmp",".webp",".svg",".apng",".avif",".ico",".jfif",".pjpeg",".pjp"),
    [System.Collections.ArrayList]$DisallowedForConvert=[System.Collections.ArrayList]@(".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma", ".m4a",".dll", ".so", ".lib", ".bin", ".class", ".pyc",".rdp",".pjpg",".pfile",".ptxt",".ppt",".pptx", ".pyo", ".o", ".obj",".exe", ".msi", ".bat", ".cmd", ".sh", ".jar", ".app", ".apk", ".dmg", ".iso", ".img",".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz", ".tgz", ".lz",".mp4", ".avi", ".mov", ".wmv", ".mkv", ".webm",".pdf", ".flv",".psd", ".ai", ".eps", ".indd", ".sketch", ".fig", ".xd", ".blend", ".vsdx",".ds_store", ".thumbs", ".lnk", ".heic", ".eml", ".msg", ".esx", ".esxm")
  )
    $VerbosePreference = 'Continue'

    $null = Get-EnsuredPath -Path $DocConversionTempDir

    if (-not (Get-Variable -Name CurrentHuduVersion -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:CurrentHuduVersion) {
        $appInfo = Get-HuduAppInfo
        $script:CurrentHuduVersion = [version]$appInfo.version
    }

    if (-not (Get-Variable -Name DateCompareJitterHours -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:DateCompareJitterHours) {
        $script:DateCompareJitterHours = [timespan]::FromHours(12)
    }
    $MatchedDocs = $null; $exactMatch = $null;
    $results = [pscustomobject]@{
        RequestParams = @{DisallowedForConvert=$DisallowedForConvert; EmbeddableImageExtensions = $EmbeddableImageExtensions; includeOriginals=$includeOriginals; updateOnMatch=$updateOnMatch; companyName=$companyName; UpdateStrategy = $UpdateStrategy; MaxHtmlCharacters = $MaxHtmlCharacters; PlainTextPdfConversion = $PlainTextPdfConversion; PdfMigrationStrategy = $PdfMigrationStrategy;}
        Company=$null; Result=$null; Action=$null; Error=$null; Global=$null; IsPDF = $null; IsImage = $null; IsEmbedUploadMedia = $null; EmbedUploadMediaKind = $null; Results = $null; FileHash = $null; AllowedToConvertFile = $null; OriginalName = $null; ShouldConvert = $null; MatchedDoc = $null; IsGlobalKB = $null; ArticleResult = $null; Strategy = $null; SourceLastModified = $null; IsDirectory=$null; Images = @(); OriginalEXT = $null; loggedMessages = @(); OutputDir = $null; HTMLPath = $null; HtmlCharacterCount = $null; isScript =$null;
        attachmentStatus = "No attachment info yet."; AttachmentHashInfo = $null; LocalAttachmentNewer = $null; RemoteAttachmentUTCdate = $null; ContentHashInfo = $null; ContentHash = $null; RemoteContentHash = $null; LocalContentNewer = $null; RemoteArticleUTCdate = $null;
        NewDoc = $null; OriginalDoc = $null; Upload = $null; CalculateEmbedHashes = ([bool]($script:CurrentHuduVersion -ge [version]("2.41.0")))
    }

    if (([string]::IsNullOrWhiteSpace($resourceLocation)) -or -not $(test-path $resourceLocation)){
        $results.Error= "resource location $resourceLocation does not appear to be a valid path"; Write-Warning $results.Error; 
        return $results
    }
    if (-not ([string]::IsNullOrEmpty($companyName))){
        $results.Company = Unwrap-HuduResultObject -InputObject ($(ChoseBest-ByName -Name $companyName -choices $(get-huducompanies -name $companyName)) ?? $null) -WrapperNames @('company')
    }
    $results.IsGlobalKB = [bool]$($null -eq $results.Company)
    $targetCompanyName = if ($results.IsGlobalKB) { $null } else { Get-HuduObjectName -InputObject $results.Company }
    $targetCompanyId = if ($results.IsGlobalKB) { $null } else { Get-HuduObjectId -InputObject $results.Company }
    if (-not $results.IsGlobalKB -and [string]::IsNullOrWhiteSpace([string]$targetCompanyName)) {
        $targetCompanyName = $companyName
    }
    Write-Info "$(if ($results.IsGlobalKB) {'Global KB'} else {"Company '$targetCompanyName' KB"}) will be target for this article"

    $companyDocs = $companyDocs ?? $(if ($true -eq $results.IsGlobalKB) {Get-HuduArticles} else {Get-HuduArticles -companyId $targetCompanyId})
    $results.OriginalDoc = Get-Item -LiteralPath $resourceLocation
    $results.originalExt  = [IO.Path]::GetExtension($results.OriginalDoc.Name).ToLowerInvariant()
    $results.originalName = [IO.Path]::GetFileNameWithoutExtension($results.OriginalDoc.Name)    
    $results.SourceLastModified = $results.OriginalDoc.LastWriteTimeUtc; Write-Verbose "source document $($results.originalName) last modified (UTC): $($results.SourceLastModified)";
    # determine if we're looking at a file or directory and set strategy
    if ($results.OriginalDoc.PSIsContainer) {
        $results.isDirectory = $true
        $results.Strategy = "user-supplied path appears to be a directory. proccing it as a resource itself (gallery of photos, index of files)"; Write-Info -Message $results.Strategy
        try {
            $results.NewDoc = if ($null -ne $results.Company) {
                Set-HuduArticleFromResourceFolder -resourcesFolder $results.OriginalDoc -companyName $targetCompanyName
            } else {
                Set-HuduArticleFromResourceFolder -resourcesFolder $results.OriginalDoc
            }
            $results.Result = Unwrap-HuduResultObject -InputObject $results.NewDoc -WrapperNames @('HuduArticle', 'article')
            return $results
        } catch {
            $results.Error="Error creating article from resource folder $_"
            return $results 
        }
    } else {$results.isDirectory = $false}

    $results.Strategy = "user-supplied path appears to be a file. determining strategy for single-file"; Write-Info -Message $results.Strategy
    $results.AllowedToConvertFile = -not ($DisallowedForConvert -contains $results.originalExt)
    $results.isPdf        = ($results.originalExt -eq '.pdf')
    $results.isImage      = ($results.originalExt -in $EmbeddableImageExtensions)
    $results.EmbedUploadMediaKind = Get-HuduEmbeddableUploadMediaKind -Path $results.OriginalDoc.FullName
    $results.IsEmbedUploadMedia = -not [string]::IsNullOrWhiteSpace($results.EmbedUploadMediaKind)
    $results.isScript     = ($results.originalExt -in @(".sh", ".expect", ".ps1", ".bat", ".cmd", ".py", ".js", ".vbs", ".wsf", ".psm1", ".psd1"))
    $results.FileHash     = "$($(Get-FileHash -LiteralPath $results.OriginalDoc.FullName -Algorithm SHA256).Hash)"

    function Test-ArticleNeedsContentRebuild {
        param([object]$Article)

        $currentPolicyCreatesArticleContent = (
            $true -eq $results.isPdf -or
            $true -eq $results.isImage -or
            $true -eq $results.IsEmbedUploadMedia -or
            $true -eq $results.isScript -or
            $true -eq $results.AllowedToConvertFile
        )
        if (-not $currentPolicyCreatesArticleContent) { return $false }

        $content = "$(Get-ObjectPropertyValue -InputObject $Article -Names @('content', 'Content'))"
        return ($content -match '(?i)Attaching Upload|See Attached Document')
    }
    function Test-GeneratedContentUpdate {
        param(
            [Parameter(Mandatory)][string]$Content,
            [Parameter(Mandatory)][string]$ContentKind
        )

        if ($UpdateStrategy -ine 'filehash' -or $null -eq $results.MatchedDoc) {
            return $true
        }

        $results.ContentHashInfo = Test-ShouldUpdateArticleContent `
            -NewContent $Content `
            -MatchedArticle $results.MatchedDoc `
            -SourceMTimeUtc $results.SourceLastModified `
            -Jitter $script:DateCompareJitterHours
        $results.ContentHash = $results.ContentHashInfo.LocalHash
        $results.RemoteContentHash = $results.ContentHashInfo.RemoteHash
        $results.LocalContentNewer = $results.ContentHashInfo.LocalNewer
        $results.RemoteArticleUTCdate = $results.ContentHashInfo.RemoteUpdatedUtc

        if ($results.ContentHashInfo.SameContent) {
            $results.Action = "Matched existing article content hash for $ContentKind; skipping update."
            Write-Info -Message $results.Action
            $results.NewDoc = $results.MatchedDoc
            $results.Result = $results.MatchedDoc
            return $false
        }

        if (-not $results.ContentHashInfo.LocalNewer) {
            $results.Action = "Generated $ContentKind content differs, but local file is not newer than the matched article; skipping update."
            Write-Info -Message $results.Action
            $results.NewDoc = $results.MatchedDoc
            $results.Result = $results.MatchedDoc
            return $false
        }

        $results.Action = "Generated $ContentKind content hash differs and local file is newer; updating article."
        Write-Info -Message $results.Action
        return $true
    }

    $exactMatch = $exactMatch ?? $($companyDocs | Where-Object {
        $docName = Get-HuduObjectName -InputObject $_
        $docName -ieq $results.originalName -or $docName -ieq $results.OriginalDoc.Name
    } | Select-Object -First 1)
    $exactMatch = $exactMatch ?? $(if ($true -eq $results.IsGlobalKB) {
        get-huduarticles -name $results.originalName | where-object {
            $null -eq (Get-ObjectPropertyValue -InputObject $_ -Names @('company_id', 'companyId', 'CompanyId'))
        }
    } else {
        $companyDocs | Where-Object { (Get-HuduObjectName -InputObject $_) -ieq $results.originalName } | Select-Object -First 1
    })

    if ($exactMatch) {
        $results.MatchedDoc = Unwrap-HuduResultObject -InputObject $exactMatch -WrapperNames @('article')
            write-info "Exact match for $(if ($true -eq $results.IsGlobalKB) {"Global KB"} else {"Company '$targetCompanyName' KB"}) article found with name '$(Get-HuduObjectName -InputObject $results.MatchedDoc)'. This will be the matched document used for update comparison and potential update if updateOnMatch is enabled."
    } else {
        $MatchedDocs = $companyDocs | Where-Object {
            $docName = Get-HuduObjectName -InputObject $_
            (Test-Equiv -A $docName -B $results.originalName) -or
            (Test-Equiv -A $docName -B $results.OriginalDoc.Name)
        }
        if ($MatchedDocs) {
            $results.MatchedDoc = ($MatchedDocs | Select-Object -First 1)
            $results.MatchedDoc = Unwrap-HuduResultObject -InputObject $results.MatchedDoc -WrapperNames @('article')
        }
    }
    if ($null -ne $results.MatchedDoc) {
        if (-not $updateOnMatch) {
            $results.Action = "SkippedMatch(updateOnMatch=false)"; Write-Info -Message $results.Action
            $results.NewDoc = $results.MatchedDoc
            $results.Result = $results.MatchedDoc
            return $results
        } 
        $matchedSourceUpload = Get-HuduUploads |
            Where-Object {
                $_.uploadable_id -eq (Get-HuduObjectId -InputObject $results.MatchedDoc) -and
                $_.uploadable_type -eq 'Article' -and
                ((Get-HuduObjectName -InputObject $_) -ieq $results.OriginalDoc.Name -or (Get-HuduObjectName -InputObject $_) -ieq $results.originalName)
            } |
            Select-Object -First 1
        $matchedSourceUpload = Unwrap-HuduResultObject -InputObject $matchedSourceUpload -WrapperNames @('upload')
        $matchedDocName = Get-HuduObjectName -InputObject $results.MatchedDoc

        if ($UpdateStrategy -ieq 'date') {
            $destUpload = $matchedSourceUpload ?? @((Get-ObjectPropertyValue -InputObject $results.MatchedDoc -Names @('attachments', 'Attachments')))[0]

            if (-not $destUpload) {
                Write-Info "Matched article '$matchedDocName' has no existing attachment metadata; proceeding with update."
                $shouldUpdate = $true
            } else {
                $shouldUpdate = Test-ShouldUpdateUpload `
                    -UpdateOnMatch $updateOnMatch `
                    -Strategy $UpdateStrategy `
                    -SourceMTimeUtc $results.SourceLastModified `
                    -DestUpload $destUpload
            }
            $matchedArticleNeedsContentRebuild = Test-ArticleNeedsContentRebuild -Article $results.MatchedDoc
            if (-not $shouldUpdate -and $matchedArticleNeedsContentRebuild) {
                $shouldUpdate = $true
            }

            $results.Action = if ($shouldUpdate) {
                if ($matchedArticleNeedsContentRebuild) {
                    "Matched existing article '$matchedDocName' but it is attachment-only and current policy creates article content; proceeding with update."
                } else {
                    "Matched existing article '$matchedDocName' but source is newer or no dest upload exists; proceeding with update."
                }
            } else {
                "Matched existing article '$matchedDocName' and source is not newer; skipping update."
            }

            Write-Info -Message $results.Action
            if (-not $shouldUpdate) {
                $results.NewDoc = $results.MatchedDoc
                $results.Result = $results.MatchedDoc
                return $results
            }
        }
        elseif ($UpdateStrategy -ieq 'filehash') {
            $destUpload = $matchedSourceUpload ?? @((Get-ObjectPropertyValue -InputObject $results.MatchedDoc -Names @('attachments', 'Attachments')))[0]

            if (-not $destUpload) {
                Write-Info "Matched article '$matchedDocName' has no existing attachment metadata; proceeding with update."
                $shouldUpdate = $true
            } elseif ($matchedSourceUpload -and (Get-HuduObjectId -InputObject $matchedSourceUpload) -and $true -eq $results.CalculateEmbedHashes) {
                try {
                    $results.AttachmentHashInfo = Compare-UploadHashWithFile -UploadId (Get-HuduObjectId -InputObject $matchedSourceUpload) -LocalFile $results.OriginalDoc.FullName
                    if ($true -eq $results.AttachmentHashInfo.SameFile) {
                        $shouldUpdate = $false
                    } else {
                        $matchedUploadDate = Get-HuduObjectDateUtc -InputObject $matchedSourceUpload
                        if ($matchedUploadDate) {
                            $results.RemoteAttachmentUTCdate = $matchedUploadDate.Add($script:DateCompareJitterHours)
                            $results.LocalAttachmentNewer = $results.SourceLastModified -gt $results.RemoteAttachmentUTCdate
                        } else {
                            $results.LocalAttachmentNewer = $true
                        }
                        $shouldUpdate = $true -eq $results.LocalAttachmentNewer
                    }
                } catch {
                    Write-Warning "Could not compare existing upload hash for '$($results.OriginalDoc.Name)': $($_.Exception.Message). Falling back to metadata comparison."
                    $shouldUpdate = Test-ShouldUpdateUpload `
                        -UpdateOnMatch $updateOnMatch `
                        -Strategy $UpdateStrategy `
                        -SourceMTimeUtc $results.SourceLastModified `
                        -SourceSha256 $results.FileHash `
                        -DestUpload $destUpload
                }
            } else {
                $shouldUpdate = Test-ShouldUpdateUpload `
                    -UpdateOnMatch $updateOnMatch `
                    -Strategy $UpdateStrategy `
                    -SourceMTimeUtc $results.SourceLastModified `
                    -SourceSha256 $results.FileHash `
                    -DestUpload $destUpload
            }
            $matchedArticleNeedsContentRebuild = Test-ArticleNeedsContentRebuild -Article $results.MatchedDoc
            if (-not $shouldUpdate -and $matchedArticleNeedsContentRebuild) {
                $shouldUpdate = $true
            }

            $results.Action = if ($shouldUpdate) {
                if ($matchedArticleNeedsContentRebuild) {
                    "Matched existing article '$matchedDocName' but it is attachment-only and current policy creates article content; proceeding with update."
                } else {
                    "Matched existing article '$matchedDocName' but file hash differs or no dest upload exists; proceeding with update."
                }
            } elseif ($results.AttachmentHashInfo -and $false -eq $results.AttachmentHashInfo.SameFile -and $false -eq $results.LocalAttachmentNewer) {
                "Matched existing article '$matchedDocName' and file hash differs, but local file is not newer than the matched upload; skipping update."
            } else {
                "Matched existing article '$matchedDocName' and file hash matches; skipping update."
            }

            Write-Info -Message $results.Action
            if (-not $shouldUpdate) {
                $results.NewDoc = $results.MatchedDoc
                $results.Result = $results.MatchedDoc
                return $results
            }
        }        
    } else {Write-Info "No existing article match found for $(if ($true -eq $results.IsGlobalKB) {"Global KB"} else {"Company '$targetCompanyName' KB"}) with name matching '$($results.originalName)'. A new article will be created."}

      
    try {

    if ($true -eq $results.isScript) {
        $safeName = ($results.originalName -replace '[^\w\.-]', '_')
        $results.HtmlPath = [IO.Path]::Combine($DocConversionTempDir,"$safeName-$(Get-Date -Format 'yyyyMMddHHmmss').html")
        $html = Get-HTMLTemplatedScriptContent -FilePath $results.OriginalDoc.FullName -Heading $results.originalName -OutputPath $results.HtmlPath
        Write-Verbose "HTML from script generated at $($results.HtmlPath) with contents $($html | Out-String)"
        if (-not (Test-GeneratedContentUpdate -Content $html -ContentKind 'script')) {
            return $results
        }
        $results.NewDoc = Set-HuduArticleFromHtml -ImagesArray @() -CompanyName $(if ($results.IsGlobalKB) { '' } else { $targetCompanyName }) -Title $results.originalName -HtmlContents $html -CalculateHashes $results.CalculateEmbedHashes
    } elseif ($true -eq $results.isImage) {
        $results.Strategy = "Processing as single-informatic image, to be embedded in Article"; Write-Info -Message $results.Strategy
        $results.NewDoc = $(Set-HuduArticleFromHtml -ImagesArray @($results.OriginalDoc.FullName) -Title $results.originalName -CompanyName $(if ($results.IsGlobalKB) { '' } else { $targetCompanyName }) -HtmlContents "<img src='$($results.OriginalDoc.Name)' alt='$results.originalName' />")
    } elseif ($true -eq $results.IsEmbedUploadMedia) {
        $results.Strategy = "Processing as single $($results.EmbedUploadMediaKind.ToLowerInvariant()) file, to be embedded in Article"; Write-Info -Message $results.Strategy
        $mediaHtml = Get-HuduEmbedHtmlForLocalMedia -Path $results.OriginalDoc.FullName -Title $results.originalName
        if (-not (Test-GeneratedContentUpdate -Content $mediaHtml -ContentKind "$($results.EmbedUploadMediaKind.ToLowerInvariant()) embed")) {
            return $results
        }
        $results.NewDoc = Set-HuduArticleFromHtml -ImagesArray @($results.OriginalDoc.FullName) -Title $results.originalName -CompanyName $(if ($results.IsGlobalKB) { '' } else { $targetCompanyName }) -HtmlContents $mediaHtml -CalculateHashes $results.CalculateEmbedHashes
    }  elseif ($true -eq $results.isPdf) {
        $results.Strategy = "Processing as singular PDF to convert and attach as Article."; Write-Info -Message $results.Strategy
    # conversion process - pdf [convert to html and attach graphics]
        $pdfArticleResult = Set-HuduArticleFromPDF -PdfPath $results.OriginalDoc.FullName -CompanyName $(if ($true -eq $results.IsGlobalKB) {''} else {$CompanyName}) -Title $results.originalName -includeOriginal $includeOriginals -CalculateHashes $results.CalculateEmbedHashes -MaxHtmlCharacters $MaxHtmlCharacters -PlainTextConversion $PlainTextPdfConversion -PdfMigrationStrategy $PdfMigrationStrategy
        $pdfUploadInfo = Get-ObjectPropertyValue -InputObject $pdfArticleResult -Names @('OriginalUploadInfo')
        if ($pdfUploadInfo) {
            $results.Upload = $pdfUploadInfo.Upload
            $results.attachmentStatus = $pdfUploadInfo.Status
            $results.AttachmentHashInfo = $pdfUploadInfo.HashInfo
            $results.LocalAttachmentNewer = $pdfUploadInfo.LocalAttachmentNewer
            $results.RemoteAttachmentUTCdate = $pdfUploadInfo.RemoteAttachmentUTCdate
        }
        $results.NewDoc = $pdfArticleResult
        $results.NewDoc = Unwrap-HuduResultObject -InputObject $results.NewDoc -WrapperNames @('HuduArticle', 'article')
    } elseif ($true -eq $results.AllowedToConvertFile) {
    # conversion process - non-pdf [but convertable]
        $results.Strategy = "Processing as singular file to convert to and attach as Article."; Write-Info -Message $results.Strategy
            $results.outputDir = Join-Path $DocConversionTempDir ([guid]::NewGuid().ToString())
            $null = New-Item -ItemType Directory -Path $results.outputDir -Force
            $localIn = Join-Path $results.outputDir $results.OriginalDoc.Name
            Copy-Item -LiteralPath $results.OriginalDoc.FullName -Destination $localIn -Force
            $VerbosePreference = 'Continue'
            $results.htmlpath = Convert-WithLibreOffice -InputFile $localIn -OutputDir $results.outputDir -SofficePath $sofficePath
            $VerbosePreference = 'SilentlyContinue'
            if ([string]::IsNullOrWhiteSpace($results.htmlpath) -or -not (Test-Path -LiteralPath $results.htmlpath)) {
                $results.htmlpath = get-childitem -Path $results.outputDir -Filter "*.xhtml" -File | Select-Object -First 1
                $results.htmlpath = $results.htmlpath ?? $(get-childitem -Path $results.outputDir -Filter "*.html" -File | Select-Object -First 1)
            }
            if ([string]::IsNullOrWhiteSpace($results.htmlpath)) {
                $results.Error = "Conversion to HTML failed for $($results.OriginalDoc.FullName); no HTML output found. Falling back to attachment-only article.";
                $results.Action = "ConversionFailedAttachmentFallback"
                $results.AllowedToConvertFile = $false
                Write-Warning $results.Error
                if ($null -ne $results.MatchedDoc) {
                    $results.NewDoc = $results.MatchedDoc
                } else {
                    $results.NewDoc = if ($results.IsGlobalKB) {
                        New-HuduArticle -name $results.originalName -content "Attaching Upload"
                    } else {
                        New-HuduArticle -name $results.originalName -companyId $targetCompanyId -content "Attaching Upload"
                    }
                }
            } else {
                $htmlContents = Get-Content -Encoding utf8 -Raw $results.htmlpath
                $results.HtmlCharacterCount = $htmlContents.Length
                if ($MaxHtmlCharacters -gt 0 -and $results.HtmlCharacterCount -gt $MaxHtmlCharacters) {
                    $results.Action = "HtmlTooLargeAttachmentFallback"
                    $results.AllowedToConvertFile = $false
                    $message = "Converted HTML for $($results.OriginalDoc.FullName) is $($results.HtmlCharacterCount) characters, over limit $MaxHtmlCharacters. Falling back to attachment-only article."
                    $results.LoggedMessages += $message
                    Write-Warning $message
                    if ($null -ne $results.MatchedDoc) {
                        $results.NewDoc = $results.MatchedDoc
                    } else {
                        $results.NewDoc = if ($results.IsGlobalKB) {
                            New-HuduArticle -name $results.originalName -content "Attaching Upload"
                        } else {
                            New-HuduArticle -name $results.originalName -companyId $targetCompanyId -content "Attaching Upload"
                        }
                    }
                } else {
                    $results.Images = @(Get-ChildItem -LiteralPath $results.outputDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tif|tiff)$' -or (Test-HuduEmbeddableUploadMediaFile -Path $_.FullName) } | Select-Object -ExpandProperty FullName)
                    $results.LoggedMessages += "$($results.Images.Count) embedded media files extracted during conversion."
                    if (-not (Test-GeneratedContentUpdate -Content $htmlContents -ContentKind 'converted HTML')) {
                        return $results
                    }
                    $results.NewDoc = Set-HuduArticleFromHtml -ImagesArray ($results.Images ?? @()) -CompanyName $(if ($true -eq $results.IsGlobalKB) {''} else {$CompanyName}) -Title $results.originalName -HtmlContents $htmlContents -CalculateHashes $results.CalculateEmbedHashes
                }
            }
    # standalone article-as-attachment process [not pdf or convertable]
      } else {
        $results.Strategy = "Processing as Attachment to Reference Article, as file cannot be converted and $(if ($null -ne $results.MatchedDoc){"Article with id $(Get-HuduObjectId -InputObject $results.MatchedDoc) will be updated"} else {"a new article will be created"})."; Write-Info -Message $results.Strategy
        if ($null -ne $results.MatchedDoc){
            $existingUpload = get-huduuploads | where-object {$_.uploadable_id -eq (Get-HuduObjectId -InputObject $results.MatchedDoc) -and $_.uploadable_type -eq 'Article' -and (Get-HuduObjectName -InputObject $_) -ieq $results.OriginalDoc.Name} | select-object -first 1; $existingUpload = Unwrap-HuduResultObject -InputObject $existingUpload -WrapperNames @('upload')
            $results.NewDoc = $results.MatchedDoc
        }
        if (-not $results.NewDoc) {
            $results.NewDoc = if ($results.IsGlobalKB) {
                New-HuduArticle -name $results.originalName -content "Attaching Upload"
            } else {
                New-HuduArticle -name $results.originalName -companyId $targetCompanyId -content "Attaching Upload"
            }
        }
    }
    # make sure results are unwrapped correctly irrespective of the path taken to get here
    $results.ArticleResult = $results.NewDoc
    $results.NewDoc = Unwrap-HuduResultObject -InputObject $results.NewDoc -WrapperNames @('HuduArticle', 'article')

    $newDocId = Get-HuduObjectId -InputObject $results.NewDoc
    if ($null -eq $results.NewDoc -or -not $newDocId) {
        $results.Error = "New Document object $($results.NewDoc | Out-String) unexpectedly came back empty"
        Write-Error $results.Error
        return $results
    }

    # process uploads if required
    $originalUploadAlreadyHandled = (($true -eq $results.isPdf -and $null -ne $results.Upload) -or $true -eq $results.IsEmbedUploadMedia)
    if (($true -eq $includeOriginals -or $true -eq $results.isScript -or $false -eq $results.AllowedToConvertFile) -and -not $originalUploadAlreadyHandled) {
        $uploadInfo = Ensure-HuduArticleUploadForFile `
            -ArticleId $newDocId `
            -FilePath $results.OriginalDoc.FullName `
            -CalculateHashes $results.CalculateEmbedHashes `
            -SourceLastModifiedUtc $results.SourceLastModified `
            -MatchNames @($results.OriginalDoc.Name, $results.originalName)
        $results.Upload = $uploadInfo.Upload
        $results.attachmentStatus = $uploadInfo.Status
        $results.AttachmentHashInfo = $uploadInfo.HashInfo
        $results.LocalAttachmentNewer = $uploadInfo.LocalAttachmentNewer
        $results.RemoteAttachmentUTCdate = $uploadInfo.RemoteAttachmentUTCdate
    }
    if ($false -eq $results.AllowedToConvertFile -and $true -ne $results.IsEmbedUploadMedia){
        $uploadUrl = Get-ObjectPropertyValue -InputObject $results.Upload -Names @('url', 'Url', 'file_url', 'public_url')
        $uploadUrl = Convert-HuduMediaUrlToRelative -Url $uploadUrl -HuduBaseUrl $HuduBaseUrl
        $results.NewDoc = if ($true -eq $results.IsGlobalKB) {
            Set-HuduArticle -id $newDocId -content "<h2>$($results.OriginalDoc.Name)</h2><br><a href='$uploadUrl'>See Attached Document, $($results.OriginalDoc.Name)</a> $(Get-MetadataArticleBlock -filePath $results.OriginalDoc.FullName)"
        } else {
            Set-HuduArticle -id $newDocId -companyId $targetCompanyId -content "<a href='$uploadUrl'>See Attached Document, $($results.OriginalDoc.Name)</a>"
        }        
        $results.NewDoc = Unwrap-HuduResultObject -InputObject $results.NewDoc -WrapperNames @('article')
    }
    $results.Result = $results.NewDoc
    return $results
    } catch {
        $results.Error =  "Article from Resource Error-- $_. $($_.Exception.Message) $($_.ScriptStackTrace)"; Write-Error $results.Error
        return $results
    } finally {
        $VerbosePreference = 'SilentlyContinue'
    }
}
    
function Convert-WithLibreOffice {
    [CmdletBinding()]
    param (
        [string]$inputFile,
        [string]$outputDir,
        [string]$sofficePath
    )
    if (-not (Test-Path -LiteralPath $inputFile)) {
        throw "Input path does not exist: $inputFile"
    }

    $item = Get-Item -LiteralPath $inputFile -ErrorAction Stop
    if ($item.PSIsContainer) {
        throw "Convert-WithLibreOffice expected a file but received a directory: $inputFile"
    }

    $null = New-Item -ItemType Directory -Path $outputDir -Force
    $loProfileBase = Join-Path ([System.IO.Path]::GetTempPath()) "itp-libreoffice-profiles"
    $null = New-Item -ItemType Directory -Path $loProfileBase -Force

    function Get-FileHeaderBytes {
        param(
            [Parameter(Mandatory)][string]$Path,
            [int]$Count = 8
        )

        $buffer = New-Object byte[] $Count
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $read = $stream.Read($buffer, 0, $Count)
            if ($read -lt $Count) {
                $shortBuffer = New-Object byte[] $read
                [Array]::Copy($buffer, $shortBuffer, $read)
                return $shortBuffer
            }
            return $buffer
        }
        finally {
            $stream.Dispose()
        }
    }

    function Test-CompoundOfficeFile {
        param([byte[]]$Bytes)
        return ($Bytes.Length -ge 8 -and
            $Bytes[0] -eq 0xD0 -and $Bytes[1] -eq 0xCF -and
            $Bytes[2] -eq 0x11 -and $Bytes[3] -eq 0xE0 -and
            $Bytes[4] -eq 0xA1 -and $Bytes[5] -eq 0xB1 -and
            $Bytes[6] -eq 0x1A -and $Bytes[7] -eq 0xE1)
    }

    function Test-ZipOfficeFile {
        param([byte[]]$Bytes)
        return ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x50 -and $Bytes[1] -eq 0x4B)
    }

    function Get-LibreOfficeInputPath {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Directory
        )

        $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $header = Get-FileHeaderBytes -Path $Path

        if (Test-CompoundOfficeFile -Bytes $header) {
            $compoundExt = switch ($ext) {
                { $_ -in @(".doc", ".docx", ".docm", ".dot", ".dotx", ".dotm") } { ".doc"; break }
                { $_ -in @(".xls", ".xlsx", ".xlsm", ".xlt", ".xltx", ".xltm") } { ".xls"; break }
                { $_ -in @(".ppt", ".pptx", ".pptm", ".pot", ".potx", ".potm") } { ".ppt"; break }
                default { $ext }
            }

            if ($compoundExt -and $compoundExt -ne $ext) {
                $correctedPath = Join-Path $Directory "$base$compoundExt"
                Copy-Item -LiteralPath $Path -Destination $correctedPath -Force
                Write-Verbose "Input file has legacy Office compound-file signature but extension '$ext'. Using temporary '$compoundExt' copy for LibreOffice: $correctedPath"
                return $correctedPath
            }
        } elseif (($ext -in @(".docx", ".xlsx", ".pptx", ".docm", ".xlsm", ".pptm")) -and -not (Test-ZipOfficeFile -Bytes $header)) {
            Write-Verbose "Input extension '$ext' suggests OOXML, but file does not have a ZIP/OOXML signature."
        }

        return $Path
    }

    function Get-LoUserProfileUri {
        param([Parameter(Mandatory)][string]$ProfilePath)
        $resolvedProfile = [System.IO.Path]::GetFullPath($ProfilePath)
        return ([System.Uri]$resolvedProfile).AbsoluteUri
    }

    function Find-LibreOfficeOutput {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [Parameter(Mandatory)][string]$BaseName,
            [Parameter(Mandatory)][string[]]$Extensions,
            [Parameter(Mandatory)][hashtable]$KnownFiles
        )

        $allOutputs = @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
            Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() })

        $newOutputs = @($allOutputs | Where-Object { -not $KnownFiles.ContainsKey($_.FullName) })
        $candidates = if ($newOutputs.Count -gt 0) { $newOutputs } else { $allOutputs }

        $exact = $candidates |
            Where-Object { $_.BaseName -ieq $BaseName } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($exact) { return $exact.FullName }

        return ($candidates |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1).FullName
    }

    function Invoke-LibreOfficeConvert {
        param(
            [Parameter(Mandatory)][string]$SourcePath,
            [Parameter(Mandatory)][string]$Format,
            [Parameter(Mandatory)][string[]]$ExpectedExtensions,
            [Parameter(Mandatory)][string]$Description
        )

        $sourceItem = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
        $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourceItem.Name)
        $knownFiles = @{}
        Get-ChildItem -LiteralPath $outputDir -File -ErrorAction SilentlyContinue | ForEach-Object {
            $knownFiles[$_.FullName] = $true
        }

        $profilePath = Join-Path $loProfileBase ("lo-profile-" + [guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $profilePath -Force
        $profileUri = Get-LoUserProfileUri -ProfilePath $profilePath

        $args = @(
            "--headless",
            "--invisible",
            "--nodefault",
            "--nolockcheck",
            "--nologo",
            "--nofirststartwizard",
            "-env:UserInstallation=$profileUri",
            "--convert-to",
            $Format,
            "--outdir",
            $outputDir,
            $SourcePath
        )

        Write-Verbose "LibreOffice $Description`: $([System.IO.Path]::GetFileName($SourcePath)) -> $Format"

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $sofficePath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        foreach ($arg in $args) {
            [void]$psi.ArgumentList.Add($arg)
        }

        $process = [System.Diagnostics.Process]::Start($psi)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(180000)) {
            try { $process.Kill($true) } catch {}
            try { Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            Write-Verbose "LibreOffice $Description timed out after 180 seconds."
            return $null
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        $converted = Find-LibreOfficeOutput -Directory $outputDir -BaseName $sourceBaseName -Extensions $ExpectedExtensions -KnownFiles $knownFiles
        if ($converted -and (Test-Path -LiteralPath $converted)) {
            Write-Verbose "LibreOffice $Description produced $converted"
            try { Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            return $converted
        }

        Write-Verbose "LibreOffice $Description produced no expected output. ExitCode=$($process.ExitCode)"
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Verbose "LibreOffice stdout: $stdout" }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Verbose "LibreOffice stderr: $stderr" }
        try { Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        return $null
    }

    try {
        $inputFile = Get-LibreOfficeInputPath -Path $inputFile -Directory $outputDir
        $extension = [System.IO.Path]::GetExtension($inputFile).ToLowerInvariant()
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)

        switch ($extension.ToLowerInvariant()) {
            # Word processors
            ".doc"      { $intermediateExt = "odt" }
            ".docx"     { $intermediateExt = "odt" }
            ".docm"     { $intermediateExt = "odt" }
            ".rtf"      { $intermediateExt = "odt" }
            ".txt"      { $intermediateExt = "odt" }
            ".md"       { $intermediateExt = "odt" }
            ".wpd"      { $intermediateExt = "odt" }

            # Spreadsheets
            ".xls"      { $intermediateExt = "ods" }
            ".xlsx"     { $intermediateExt = "ods" }
            ".csv"      { $intermediateExt = "ods" }

            # Presentations
            ".ppt"      { $intermediateExt = "odp" }
            ".pptx"     { $intermediateExt = "odp" }
            ".pptm"     { $intermediateExt = "odp" }

            # Already OpenDocument
            ".odt"      { $intermediateExt = $null }
            ".ods"      { $intermediateExt = $null }
            ".odp"      { $intermediateExt = $null }

            default { $intermediateExt = $null }
        }

        $directXhtml = Invoke-LibreOfficeConvert `
            -SourcePath $inputFile `
            -Format "xhtml" `
            -ExpectedExtensions @(".xhtml", ".html", ".htm") `
            -Description "direct XHTML conversion"
        if ($directXhtml) { return $directXhtml }

        $directHtml = Invoke-LibreOfficeConvert `
            -SourcePath $inputFile `
            -Format "html" `
            -ExpectedExtensions @(".html", ".htm", ".xhtml") `
            -Description "direct HTML conversion"
        if ($directHtml) { return $directHtml }

        if ($intermediateExt) {
            $intermediatePath = Join-Path $outputDir "$baseName.$intermediateExt"
            Write-Verbose "Step 1 fallback: Converting to .$intermediateExt..."

            $intermediateOutput = Invoke-LibreOfficeConvert `
                -SourcePath $inputFile `
                -Format $intermediateExt `
                -ExpectedExtensions @(".$intermediateExt") `
                -Description "intermediate .$intermediateExt conversion"

            if ($intermediateOutput -and (Test-Path -LiteralPath $intermediateOutput)) {
                $intermediatePath = $intermediateOutput
            } else {
                Write-Verbose "$intermediateExt conversion failed for $inputFile"
                return $null
            }
        } else {
            # No conversion needed
            $intermediatePath = $inputFile
        }

        Write-Verbose "Step $(if ($intermediateExt) {'2 fallback'} else {'1 fallback'}): Converting intermediate to XHTML..."

        $fallbackXhtml = Invoke-LibreOfficeConvert `
            -SourcePath $intermediatePath `
            -Format "xhtml" `
            -ExpectedExtensions @(".xhtml", ".html", ".htm") `
            -Description "intermediate XHTML conversion"
        if ($fallbackXhtml) { return $fallbackXhtml }

        $fallbackHtml = Invoke-LibreOfficeConvert `
            -SourcePath $intermediatePath `
            -Format "html" `
            -ExpectedExtensions @(".html", ".htm", ".xhtml") `
            -Description "intermediate HTML conversion"
        if ($fallbackHtml) { return $fallbackHtml }

        Write-Verbose "LibreOffice conversion failed for $inputFile; no HTML output found."
        return $null
    }
    catch {
       Write-Verbose $_
        return $null
    }
}

function Get-EmbeddedFilesFromHtml {
    param (
        [string]$htmlPath,
        [int32]$resolution=5
    )

    if (-not (Test-Path $htmlPath)) {
        Write-Warning "HTML file not found: $htmlPath"
        return @{}
    }

    $htmlContent = Get-Content $htmlPath -Raw
    $baseDir = Split-Path -Path $htmlPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($htmlPath)
    $trimmedBaseName = if ($baseName.Length -gt $resolution) {
        $baseName.Substring(0, $baseName.Length - $resolution).ToLower()
    } else {
        $baseName.ToLower()
    }
    $results = @{
        ExternalFiles        = @()
        Base64Images         = @()
        Base64ImagesWritten  = @()
        UpdatedHTMLContent   = $null
    }

    $guid = [guid]::NewGuid().ToString()
    $uuidSuffix = ($guid -split '-')[0]

    $counter = 0
    $htmlContent = [regex]::Replace($htmlContent, '(?i)<img([^>]+?)src\s*=\s*["'']data:image/(?<type>[a-z]+);base64,(?<b64data>[^"'']+)["'']', {
        param($match)

        $type = $match.Groups["type"].Value
        $b64  = $match.Groups["b64data"].Value

        $ext = switch ($type) {
            'png'  { 'png' }
            'jpeg' { 'jpg' }
            'jpg'  { 'jpg' }
            'gif'  { 'gif' }
            'svg'  { 'svg' }
            'bmp'  { 'bmp' }
            default { 'bin' }
        }

        $counter++
        $filename = "${baseName}_embedded_${uuidSuffix}_$counter.$ext"
        $filepath = Join-Path $baseDir $filename

        try {
            [IO.File]::WriteAllBytes($filepath, [Convert]::FromBase64String($b64))
            $results.ExternalFiles += $filepath
            $results.Base64Images  += "data:image/$type;base64,..."
            $results.Base64ImagesWritten += $filepath

            return "<img$($match.Groups[1].Value)src='$filename'"
        } catch {
            Write-Warning "Failed to decode embedded image: $($_.Exception.Message)"
            return "<img$($match.Groups[1].Value)src='$filename'"
        }
    })
    $skipExts = @(
        ".doc", ".docx", ".docm", ".rtf", ".txt", ".md", ".wpd",
        ".xls", ".xlsx", ".csv", ".ppt", ".pptx", ".pptm",
        ".odt", ".ods", ".odp", ".xhtml", ".xml", ".html", ".json", ".htm"
    )

    $allFiles = Get-ChildItem -Path $baseDir -File
    foreach ($file in $allFiles) {
        $fullFilePath = [IO.Path]::GetFullPath($file.FullName).ToLowerInvariant()
        $htmlPathNormalized = [IO.Path]::GetFullPath($htmlPath).ToLowerInvariant()

        if ($fullFilePath -eq $htmlPathNormalized) {
            continue
        }

        if ($file.Extension.ToLowerInvariant() -in $skipExts) {
            continue
        }

        $otherBaseName = $file.BaseName.ToLower()
        if ($otherBaseName.StartsWith($trimmedBaseName)) {
            $results.ExternalFiles += "$fullFilePath"
        }
    }
        
        
    $results.UpdatedHTMLContent = $htmlContent
    return $results
}

function Convert-PdfXmlToHtml {
    param (
        [Parameter(Mandatory)][string]$XmlPath,
        [string]$OutputHtmlPath = "$XmlPath.html"
    )

    if (-not (Test-Path $XmlPath)) {
        throw "Input XML not found: $XmlPath"
    }

    [xml]$doc = Get-Content $XmlPath
    $html = @()
    $html += '<!DOCTYPE html>'
    $html += '<html><head><meta charset="UTF-8">'
    $html += '<style>body{font-family:sans-serif;font-size:12pt;line-height:1.4}</style></head><body>'

    foreach ($page in $doc.pdf2xml.page) {
        $html += "<div class='page' style='margin-bottom:2em'>"
        foreach ($text in $page.text) {
            $content = ($text.'#text' -replace '\s+', ' ').Trim()
            if ($content) {
                $html += "<p>$content</p>"
            }
        }
        $html += "</div>"
    }

    $html += '</body></html>'
    Set-Content -Path $OutputHtmlPath -Value ($html -join "`n") -Encoding UTF8
    Set-PrintAndLog -message  "Generated slim HTML: $OutputHtmlPath"
}
function Convert-PdfToHtml {
    param (
        [string]$inputPath,
        [string]$outputDir = (Split-Path $inputPath),
        [string]$pdftohtmlPath = "C:\tools\poppler\bin\pdftohtml.exe",
        [bool]$includeHiddenText = $true,
        [bool]$complexLayoutMode = $true
    )

    $filename = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
    $outputHtml = Join-Path $outputDir "$filename.html"

    $popplerArgs = @()

    # Preserve layout with less nesting
    if ($complexLayoutMode) {
        $popplerArgs += "-c"            # complex layout mode
    }

    # Enable image extraction
    $popplerArgs += "-p"                # extract images
    $popplerArgs += "-zoom 1.0"         # avoid automatic zoom bloat

    # Output options
    $popplerArgs += "-noframes"        # single HTML file instead of one per page
    $popplerArgs += "-nomerge"         # don't merge text blocks (more control)
    $popplerArgs += "-enc UTF-8"       # UTF-8 encoding
    $popplerArgs += "-nodrm"           # ignore any DRM restrictions

    if ($includeHiddenText) {
        $popplerArgs += "-hidden"
    }

    # Wrap file paths
    $popplerArgs += "`"$inputPath`""
    $popplerArgs += "`"$outputHtml`""

    Start-Process -FilePath $pdftohtmlPath `
        -ArgumentList $popplerArgs -Wait -NoNewWindow

    return (Test-Path $outputHtml) ? $outputHtml : $null
}


function Save-Base64ToFile {
    param (
        [Parameter(Mandatory)]
        [string]$Base64String,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Remove data URI prefix if present (e.g., "data:image/png;base64,...")
    if ($Base64String -match '^data:.*?;base64,') {
        $Base64String = $Base64String -replace '^data:.*?;base64,', ''
    }

    $bytes = [System.Convert]::FromBase64String($Base64String)
    [System.IO.File]::WriteAllBytes($OutputPath, $bytes)

    Set-PrintAndLog -message  "Saved Base64 content to: $OutputPath"
}


function Get-FileMagicBytes {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$Count = 16
    )

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] $Count
        $fs.Read($buffer, 0, $Count) | Out-Null
        return $buffer
    }
    finally {
        $fs.Dispose()
    }
}
function Test-IsPdf {
    param($Bytes)

    # %PDF-
    return ($Bytes[0] -eq 0x25 -and
            $Bytes[1] -eq 0x50 -and
            $Bytes[2] -eq 0x44 -and
            $Bytes[3] -eq 0x46 -and
            $Bytes[4] -eq 0x2D)
}
function Test-IsDocx {
    param([string]$Path, $Bytes)

    # ZIP header
    if (-not ($Bytes[0] -eq 0x50 -and $Bytes[1] -eq 0x4B)) {
        return $false
    }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $found = $zip.Entries | Where-Object { $_.FullName -ieq 'word/document.xml' }
        return [bool]$found
    }
    catch {
        return $false
    }
    finally {
        if ($zip) { $zip.Dispose() }
    }
}
function Test-IsPlainText {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    # Reject if NULL bytes found
    if ($bytes -contains 0) { return $false }

    try {
        [System.Text.Encoding]::UTF8.GetString($bytes) | Out-Null
        return $true
    }
    catch {
        return $false
    }
}
function Get-FileType {
    param([string]$Path)

    $magic = Get-FileMagicBytes $Path

    if (Test-IsPdf $magic) {
        return 'PDF'
    }

    if (Test-IsDocx $Path $magic) {
        return 'DOCX'
    }

    if (Test-IsPlainText $Path) {
        return 'PlainText'
    }

    return 'UnknownBinary'
}


function Normalize-Text {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s = $s.Trim().ToLowerInvariant()
    $s = [regex]::Replace($s, '[\s_-]+', ' ')  # "primary_email" -> "primary email"
    # strip diacritics (prénom -> prenom)
    $formD = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()){
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    ($sb.ToString()).Normalize([System.Text.NormalizationForm]::FormC)
}

function Remove-NullHashtableValues {
    param([hashtable]$Hashtable)

    foreach ($key in $Hashtable.Keys.Clone()) {
        if ($null -eq $Hashtable[$key]) {
            $Hashtable.Remove($key)
        }
    }

    return $Hashtable
}

function Remove-EmptyPSObjectProperties {
    param(
        [Parameter(Mandatory)]
        [psobject]$InputObject
    )

    $out = [pscustomobject]@{}

    foreach ($prop in $InputObject.PSObject.Properties) {
        $value = $prop.Value

        $isEmpty = (
            $null -eq $value -or
            ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) -or
            ($value -is [System.Collections.ICollection] -and $value.Count -eq 0)
        )

        if (-not $isEmpty) {
            $out | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $value
        }
    }

    return $out
}

function Get-MetadataArticleBlock {
    param ([string]$filePath)
    $file = Get-Item -LiteralPath $filePath
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $html = @"
<div>
<b>Metadata</b>
<ul>
  <li>Original Filename: $($file.Name)</li>
  <li>Source Directory: $($file.DirectoryName)</li>
  <li>FileHash (SHA256): $hash</li>
  <li>Last Modified (UTC): $($file.LastWriteTimeUtc)</li>
</ul>
</div>
"@
    return $html
}

function Write-ObjectNonNullProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$InputObject,

        [string]$Title = $null
    )

    if ($Title) {
        Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    }

    foreach ($prop in $InputObject.PSObject.Properties) {
        $value = $prop.Value

        $isEmpty = (
            $null -eq $value -or
            ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) -or
            ($value -is [System.Collections.ICollection] -and $value.Count -eq 0)
        )

        if (-not $isEmpty) {
            Write-Host ("{0,-24}: {1}" -f $prop.Name, $value) -ForegroundColor Gray
        }
    }
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
function Get-HTMLTemplatedScriptContent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$FilePath,

        [string]$Heading,

        [string]$OutputPath
    )

    $file = Get-Item -LiteralPath $FilePath -ErrorAction Stop

    if (-not $Heading) {
        $Heading = "$($file.Name) - $($file.Extension) Script"
    }

    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $encoded = [System.Net.WebUtility]::HtmlEncode($content)

    $html = @"
<h2>$Heading</h2>
<pre><code>$encoded</code></pre>
<hr>
$(Get-MetadataArticleBlock -filePath $file.FullName)
"@

    if ($OutputPath) {

        $dir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        [IO.File]::WriteAllText($OutputPath, $html, [Text.UTF8Encoding]::new($false))
    }

    return $html
}

function Compare-HuduRemoteFileHashWithFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RemoteId,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [Alias('path','file','localpath','filepath')]
        [string]$LocalFile,

        [Parameter(Mandatory)]
        [ValidateSet('Upload','PublicPhoto')]
        [string]$MediaKind
    )

    $tempDir = (Get-EnsuredPath -Path (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())))

    try {
        $remoteEntry = if ($MediaKind -eq 'PublicPhoto') {
            Get-HuduPublicPhotos -Download -Id $RemoteId -OutDir $tempDir
        } else {
            Get-HuduUploads -Download -Id ([int]$RemoteId) -OutDir $tempDir
        }
        $remoteEntry = Unwrap-HuduResultObject -InputObject $remoteEntry -WrapperNames @('Upload', 'upload', 'public_photo', 'PublicPhoto')
        $localHash  = (Get-FileHash -LiteralPath (Resolve-Path $LocalFile).Path       -Algorithm SHA256).Hash
        $remoteLocalPath = Get-ObjectPropertyValue -InputObject $remoteEntry -Names @('LocalPath', 'local_path', 'localPath')
        if ([string]::isnullorempty($remoteLocalPath) -or [string]::isnullorempty($localHash)){
            return @{SameFile = $false; LocalHash = $localHash; RemoteHash = $null; UploadHash = $null }
        }

        $remoteHash = (Get-FileHash -LiteralPath (Resolve-Path $remoteLocalPath).Path -Algorithm SHA256).Hash
        $samefile = [bool]$("$remoteHash" -ieq "$localHash")
        if ($false -eq $samefile) {
            write-verbose "Hash mismatch between local file and existing $MediaKind (RemoteId: $RemoteId). Local: $localHash, Remote: $remoteHash"
        }


        @{
            SameFile   = $samefile
            RemoteHash = $remoteHash
            UploadHash = $remoteHash
            LocalHash  = $localHash
        }
    }
    finally {
        if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Compare-UploadHashWithFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$UploadId,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [Alias('path','file','localpath','filepath')]
        [string]$LocalFile
    )

    Compare-HuduRemoteFileHashWithFile -MediaKind Upload -RemoteId $UploadId -LocalFile $LocalFile
}

function Compare-PublicPhotoHashWithFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$PublicPhotoId,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [Alias('path','file','localpath','filepath')]
        [string]$LocalFile
    )

    Compare-HuduRemoteFileHashWithFile -MediaKind PublicPhoto -RemoteId $PublicPhotoId -LocalFile $LocalFile
}

function Ensure-HuduArticleUploadForFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ArticleId,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [Alias('path','file','localpath')]
        [string]$FilePath,

        [bool]$CalculateHashes = $true,
        [datetime]$SourceLastModifiedUtc,
        [string[]]$MatchNames = @()
    )

    if (-not (Get-Variable -Name CurrentHuduVersion -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:CurrentHuduVersion) {
        $appInfo = Get-HuduAppInfo
        $script:CurrentHuduVersion = [version]$appInfo.version
    }

    if (-not (Get-Variable -Name DateCompareJitterHours -Scope Script -ErrorAction SilentlyContinue) -or $null -eq $script:DateCompareJitterHours) {
        $script:DateCompareJitterHours = [timespan]::FromHours(12)
    }

    $localFile = Get-Item -LiteralPath $FilePath -ErrorAction Stop
    if ($SourceLastModifiedUtc -eq [datetime]::MinValue) {
        $SourceLastModifiedUtc = $localFile.LastWriteTimeUtc
    }

    $candidateNames = @(
        @($MatchNames)
        $localFile.Name
        [IO.Path]::GetFileNameWithoutExtension($localFile.Name)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $existingUpload = Get-HuduUploads |
        Where-Object {
            $_.uploadable_id -eq $ArticleId -and
            $_.uploadable_type -eq 'Article' -and
            ((Get-HuduObjectName -InputObject $_) -in $candidateNames)
        } |
        Select-Object -First 1
    $existingUpload = Unwrap-HuduResultObject -InputObject $existingUpload -WrapperNames @('upload')

    $status = $null
    $hashInfo = $null
    $remoteAttachmentUtcDate = $null
    $localAttachmentNewer = $null
    $replacedUpload = $false

    if ($null -ne $existingUpload) {
        Write-Verbose "An existing upload (attachment) was found."
        $existingUploadId = Get-HuduObjectId -InputObject $existingUpload

        if ($script:CurrentHuduVersion -lt [version]("2.41.0") -or $false -eq $CalculateHashes) {
            $status = "Existing attachment upload found for article, but hash comparison is not available. Using existing attachment/upload as-is."
            Write-Verbose $status
        } else {
            $hashInfo = Compare-UploadHashWithFile -UploadId $existingUploadId -LocalFile $localFile.FullName
            $existingUploadDate = Get-HuduObjectDateUtc -InputObject $existingUpload
            if ($existingUploadDate) {
                $remoteAttachmentUtcDate = $existingUploadDate.Add($script:DateCompareJitterHours)
                $localAttachmentNewer = $SourceLastModifiedUtc -gt $remoteAttachmentUtcDate
            } else {
                $localAttachmentNewer = $true
            }

            if ($true -eq $hashInfo.SameFile) {
                $status = "Hashes match, skipping upload or replace"
                Write-Verbose $status
            } elseif ($true -eq $localAttachmentNewer) {
                $status = "Existing attachment upload is older $remoteAttachmentUtcDate and has different hash ($($hashInfo.LocalHash) vs $($hashInfo.UploadHash)). Deleting existing upload to replace with new version."
                Write-Verbose $status
                Remove-HuduUpload -Id $existingUploadId -Confirm:$false
                $existingUpload = $null
                $replacedUpload = $true
            } else {
                $status = "Existing attachment upload appears newest. No need to replace."
                Write-Verbose $status
            }
        }
    } else {
        $status = "No existing upload found. Proceeding to upload new file."
        Write-Verbose $status
    }

    $upload = $existingUpload ?? $(New-HuduUpload -Uploadable_Id $ArticleId -Uploadable_Type 'Article' -FilePath $localFile.FullName)
    $upload = Unwrap-HuduResultObject -InputObject $upload -WrapperNames @('upload')

    [pscustomobject]@{
        Upload                  = $upload
        Status                  = $status
        HashInfo                = $hashInfo
        LocalAttachmentNewer    = $localAttachmentNewer
        RemoteAttachmentUTCdate = $remoteAttachmentUtcDate
        ReplacedUpload          = $replacedUpload
    }
}

function Compare-StringsIgnoring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$A,
        [Parameter(Mandatory)] [string]$B,
        $ignore = @(
                '\bthe\b',
                '\borg\b',
                '\binc\b',
                '\bpc\b',
                '\band\b',
                '\bltd\b',
                '[\.,/&]'
            ))
    function _Normalize($s) {

        if (-not $s) { return '' }
        $t = Normalize-Text $s
        $t = $t -replace '\p{P}+', ''

        foreach ($pattern in $ignore) {
            $t = $t -replace $pattern, ''
        }
        $t = ($t -replace '\s+', ' ').Trim()
        return $t
    }

    $normA = _Normalize $A
    $normB = _Normalize $B

    return ($normA -eq $normB)
}

function Get-Similarity {
    param([string]$A, [string]$B)

    $a = [string](Normalize-Text $A)
    $b = [string](Normalize-Text $B)
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 1.0 }
    if ([string]::IsNullOrEmpty($a) -or  [string]::IsNullOrEmpty($b))  { return 0.0 }

    $n = [int]$a.Length
    $m = [int]$b.Length
    if ($n -eq 0) { return [double]($m -eq 0) }
    if ($m -eq 0) { return 0.0 }

    $d = New-Object 'int[,]' ($n+1), ($m+1)
    for ($i = 0; $i -le $n; $i++) { $d[$i,0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0,$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $im1 = ([int]$i) - 1
        $ai  = $a[$im1]
        for ($j = 1; $j -le $m; $j++) {
            $jm1 = ([int]$j) - 1
            $cost = if ($ai -eq $b[$jm1]) { 0 } else { 1 }

            $del = [int]$d[$i,  $j]   + 1
            $ins = [int]$d[$i,  $jm1] + 1
            $sub = [int]$d[$im1,$jm1] + $cost

            $d[$i,$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }

    $dist   = [double]$d[$n,$m]
    $maxLen = [double][Math]::Max($n,$m)
    return 1.0 - ($dist / $maxLen)
}
function Get-SimilaritySafe { param([string]$A,[string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0.0 }
    $score = Get-Similarity $A $B
    write-verbose "$a ... $b SCORED $score"
    return $score
}

function ChoseBest-ByName {
    param ([string]$Name,[array]$choices,[string]$prop='name')
    $validChoices = $choices | Where-Object {
        $value = Get-ObjectPropertyValue -InputObject (Unwrap-HuduResultObject -InputObject $_ -WrapperNames @('company', 'article', 'upload')) -Names @($prop)
        -not [string]::IsNullOrEmpty([string]$value)
    }
    $match = $validChoices | ForEach-Object {
        $choice = Unwrap-HuduResultObject -InputObject $_ -WrapperNames @('company', 'article', 'upload')
        $value = Get-ObjectPropertyValue -InputObject $choice -Names @($prop)
        [pscustomobject]@{
            Choice = $choice
            Score  = $(Get-SimilaritySafe -a "$Name" -b $value)
        }
    } | Where-Object { $_.Score -ge 0.97 } | Sort-Object Score -Descending | Select-Object -First 1
    if ($match) { return $match.Choice }
    return $null
}
function Export-DocPropertyJson {
    param (
        [Parameter(Mandatory)][PSCustomObject]$Doc,
        [Parameter(Mandatory)][string]$Property,
        [int]$Depth = 45
    )

    if (-not ($Doc.PSObject.Properties.Name -contains $Property)) {
        throw "Property '$Property' does not exist on the provided document object."
    }

    $value = $Doc.$Property

    $dir  = [System.IO.Path]::GetDirectoryName($Doc.LocalPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Doc.LocalPath)
    $outPath = [System.IO.Path]::Combine($dir, "$base-$($Property.ToLower()).json")

    $value | ConvertTo-Json -Depth $Depth | Out-File -FilePath $outPath -Encoding UTF8

    return $outPath
}
function Get-EnsuredPath {
    param([string]$path)
    $outpath = if (-not $path -or [string]::IsNullOrWhiteSpace($path)) { $(join-path $(Resolve-Path .).path "debug") } else {$path}
    if (-not (Test-Path $outpath)) {
        Get-ChildItem -Path "$outpath" -File -Recurse -Force | Remove-Item -Force
        New-Item -ItemType Directory -Path $outpath -Force -ErrorAction Stop | Out-Null
        write-verbose "path is now present: $outpath"
    } else {write-verbose "path is present: $outpath"}
    return $outpath
}

function Write-ErrorObjectsToFile {
    param (
        [Parameter(Mandatory)]
        [object]$ErrorObject,

        [Parameter()]
        [string]$Name = "unnamed",

        [Parameter()]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )

    $stringOutput = try {
        $ErrorObject | Format-List -Force | Out-String
    } catch {
        "Failed to stringify object: $_"
    }

    $propertyDump = try {
        $props = $ErrorObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $lines = foreach ($p in $props) {
            try {
                "$p = $($ErrorObject.$p)"
            } catch {
                "$p = <unreadable>"
            }
        }
        $lines -join "`n"
    } catch {
        "Failed to enumerate properties: $_"
    }

    $logContent = @"
==== OBJECT STRING ====
$stringOutput

==== PROPERTY DUMP ====
$propertyDump
"@

    if ($ErroredItemsFolder -and (Test-Path $ErroredItemsFolder)) {
        $SafeName = ($Name -replace '[\\/:*?"<>|]', '_') -replace '\s+', ''
        if ($SafeName.Length -gt 60) {
            $SafeName = $SafeName.Substring(0, 60)
        }
        $filename = "${SafeName}_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $fullPath = Join-Path $ErroredItemsFolder $filename
        Set-Content -Path $fullPath -Value $logContent -Encoding UTF8
        if ($Color) {
            write-verbose "Error written to $fullPath"
        } else {
            write-verbose "Error written to $fullPath"
        }
    }

        write-verbose "$logContent"
}


function Save-HtmlSnapshot {
    param (
        [Parameter(Mandatory)][string]$PageId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Suffix,
        [Parameter(Mandatory)][string]$OutDir
    )

    $safeTitle = ($Title -replace '[^\w\d\-]', '_') -replace '_+', '_'
    $filename = "${PageId}_${safeTitle}_${Suffix}.html"
    $path = Join-Path -Path $OutDir -ChildPath $filename

    try {
        $Content | Out-File -FilePath $path -Encoding UTF8
        write-verbose "Saved HTML snapshot: $path"
    } catch {
        Write-ErrorObjectsToFile -Name "$($_.safeTitle ?? "unnamed")" -ErrorObject @{
            Error       = $_
            PageId      = $PageId 
            Content     = $Content
            Message     ="Error Saving HTML Snapshot"
            OutDir      = $OutDir
        }
    }
}
function Get-PercentDone {
    param (
        [int]$Current,
        [int]$Total
    )
    if ($Total -eq 0) {
        return 100}
    $percentDone = ($Current / $Total) * 100
    if ($percentDone -gt 100){
        return 100
    }
    $rounded = [Math]::Round($percentDone, 2)
    return $rounded
}   
function Set-PrintAndLog {
    param (
        [string]$message,
        [Parameter()]
        [Alias("ForegroundColor")]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )
    $logline = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    if ($Color) {
        write-verbose $logline
    } else {
        write-verbose $logline
    }
    Add-Content -Path $LogFile -Value $logline
}
function Select-ObjectFromList($objects, $message, $inspectObjects = $false, $allowNull = $false) {
    $items = @($objects)
    $validated = $false
    while (-not $validated) {
        if ($allowNull) {
            Write-Host "0: None/Custom"
        }

        for ($i = 0; $i -lt $items.Count; $i++) {
            $object = $items[$i]
            $optionMessage = $null
            $name = $null
            if ($null -ne $object) {
                $optionMessageProperty = $object.PSObject.Properties['OptionMessage']
                if ($null -ne $optionMessageProperty) {
                    $optionMessage = $optionMessageProperty.Value
                }
                $nameProperty = $object.PSObject.Properties['name']
                if ($null -ne $nameProperty) {
                    $name = $nameProperty.Value
                }
            }

            $displayLine = if ($inspectObjects) {
                "$($i+1): $(Write-InspectObject -object $object)"
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$optionMessage)) {
                "$($i+1): $optionMessage"
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                "$($i+1): $name"
            } else {
                "$($i+1): $($object)"
            }

            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }

        $choice = Read-Host $message

        $parsedChoice = 0
        if (-not [int]::TryParse([string]$choice, [ref]$parsedChoice)) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }

        $choice = $parsedChoice

        if ($choice -eq 0 -and $allowNull) {
            return $null
        }

        if ($choice -ge 1 -and $choice -le $items.Count) {
            return $items[$choice - 1]
        } else {
            Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
        }
    }
}
function Get-YesNoResponse($message) {
    do {
        $response = Read-Host "$message (y/n)"
        $response = if($null -ne $response) {$response.ToLower()} else {""}
        if ($response -eq 'y' -or $response -eq 'yes') {
            return $true
        } elseif ($response -eq 'n' -or $response -eq 'no') {
            return $false
        } else {
            Set-PrintAndLog -message "Invalid input. Please enter 'y' for Yes or 'n' for No."
        }
    }
    while ($true)
}

function Get-ArticlePreviewBlock {
    param (
        [string]$Title,
        [string]$docId,
        [string]$Content,
        [int]$MaxLength = 200
    )
    $descriptor = "ID: $docId, titled $Title"
    $snippet = if ($Content.Length -gt $MaxLength) {
        $Content.Substring(0, $MaxLength) + "..."
    } else {
        $Content
    }

@"
Mapping Sharepoint Page $descriptor ---
Title: $Title
Snippet: $snippet
"@
}


function Get-SafeFilename {
    param([string]$Name,
        [int]$MaxLength=25
    )

    # If there's a '?', take only the part before it
    $BaseName = $Name -split '\?' | Select-Object -First 1

    # Extract extension (including the dot), if present
    $Extension = [System.IO.Path]::GetExtension($BaseName)
    $NameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseName)

    # Sanitize name and extension
    $SafeName = $NameWithoutExt -replace '[\\\/:*?"<>|]', '_'
    $SafeExt = $Extension -replace '[\\\/:*?"<>|]', '_'

    # Truncate base name to 25 chars
    if ($SafeName.Length -gt $MaxLength) {
        $SafeName = $SafeName.Substring(0, $MaxLength)
    }

    return "$SafeName$SafeExt"
}
function New-HuduStubArticle {
    param (
        [string]$Title,
        [string]$Content,
        [nullable[int]]$CompanyId,
        [nullable[int]]$FolderId
    )

    $params = @{
        Name    = $Title
        Content = $Content
    }

    if ($CompanyId -ne $null -and $CompanyId -ne -1) {
        $params.CompanyId = $CompanyId
    }

    if ($FolderId -ne $null -and $FolderId -ne 0) {
        $params.FolderId = $FolderId
    }

    return (New-HuduArticle @params).article
}

function Get-SafeTitle {
    param ([string]$Name)

    if (-not $Name) {
        return "untitled"
    }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $decoded = [uri]::UnescapeDataString($baseName)
    $safe = $decoded -replace '[\\/:*?"<>|]', ' '
    $safe = ($safe -replace '\s{2,}', ' ').Trim()
    return $safe
}

function Test-Equiv {
    param([string]$A, [string]$B)
    $a = Normalize-Text $A; $b = Normalize-Text $B
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    $reA = "(^| )$([regex]::Escape($a))( |$)"
    $reB = "(^| )$([regex]::Escape($b))( |$)"
    if ($b -match $reA -or $a -match $reB) { return $true } 
    if ($a.Replace(' ', '') -eq $b.Replace(' ', '')) { return $true }
    return $false
}
function Get-Similarity {
    param([string]$A, [string]$B)

    $a = [string](Normalize-Text $A)
    $b = [string](Normalize-Text $B)
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 1.0 }
    if ([string]::IsNullOrEmpty($a) -or  [string]::IsNullOrEmpty($b))  { return 0.0 }

    $n = [int]$a.Length
    $m = [int]$b.Length
    if ($n -eq 0) { return [double]($m -eq 0) }
    if ($m -eq 0) { return 0.0 }

    $d = New-Object 'int[,]' ($n+1), ($m+1)
    for ($i = 0; $i -le $n; $i++) { $d[$i,0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0,$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $im1 = ([int]$i) - 1
        $ai  = $a[$im1]
        for ($j = 1; $j -le $m; $j++) {
            $jm1 = ([int]$j) - 1
            $cost = if ($ai -eq $b[$jm1]) { 0 } else { 1 }

            $del = [int]$d[$i,  $j]   + 1
            $ins = [int]$d[$i,  $jm1] + 1
            $sub = [int]$d[$im1,$jm1] + $cost

            $d[$i,$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }

    $dist   = [double]$d[$n,$m]
    $maxLen = [double][Math]::Max($n,$m)
    return 1.0 - ($dist / $maxLen)
}

function Get-LatestLibreURI {
    [CmdletBinding()]
    param([string]$BaseUri = 'https://mirror.usi.edu/pub/tdf/libreoffice/stable/')

    $index = Invoke-WebRequest -Uri $BaseUri -UseBasicParsing
    $versions = $index.Links | Where-Object { $_.href -match '^\d+\.\d+\.\d+\/$' } |
        ForEach-Object {
            $v = $_.href.TrimEnd('/')
            [pscustomobject]@{
                Version = [version]$v
                Href    = $_.href
            }} | Sort-Object Version

    if (-not $versions) {
        throw "No LibreOffice versions found at $BaseUri"
    }

    $latest = $versions[-1]
    $latestUri = "$BaseUri$($latest.Href)"

    Write-Verbose "Latest version directory: $latestUri"
    $archUri = "$latestUri/win/x86_64/"
    $archIndex = Invoke-WebRequest -Uri $archUri -UseBasicParsing
    $pattern = '^LibreOffice_.*_Win_x86-64\.msi$'
    $msi = $archIndex.Links | Where-Object { $_.href -match $pattern } | Select-Object -First 1
    
    if (-not $msi) {throw "Could not locate any LibreOffice MSI matching $pattern at $archUri"}

    return "$archUri$($msi.href)"
}


function Stop-LibreOffice {
    Get-Process | Where-Object { $_.Name -like "soffice*" } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Get-LibreMSI {
    param ([string]$tmpfolder)
    if ([string]::IsNullOrEmpty($tmpfolder)) {
        $tmpfolder = [System.IO.Path]::GetTempPath()
    }
    if (Test-Path "C:\Program Files\LibreOffice\program\soffice.exe") {
        return "C:\Program Files\LibreOffice\program\soffice.exe"
    }
    $downloadUrl = $(Get-LatestLibreURI) ?? "https://mirror.usi.edu/pub/tdf/libreoffice/stable/25.8.3/win/x86_64/LibreOffice_25.8.3_Win_x86-64.msi"
    $downloadPath = Join-Path $tmpfolder "LibreOffice.msi"

    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath

    # Attempt to install
    Start-Process msiexec.exe -ArgumentList "/i `"$downloadPath`"" -Wait

    # Look for default install path
    $sofficePath = "C:\Program Files\LibreOffice\program\soffice.exe"
    if (Test-Path $sofficePath) {
        return $sofficePath
    } else {
        $sofficePath=$(read-host "Sorry, but we couldnt find libreoffice install. What we need is soffice.exe, usually at '$sofficePath'. Please enter the path for this manually now.")
    }
    return $sofficePath
}
function Get-LibrePortable {
    param (
        [string]$tmpfolder
    )

    $downloadUrl = "$LibrePortaInstall"
    $downloadPath = Join-Path $tmpfolder "LibreOfficePortable.paf.exe"
    $extractPath = Join-Path $tmpfolder "LibreOfficePortable"

    if (!(Test-Path $extractPath)) {
        New-Item -ItemType Directory -Path $extractPath | Out-Null
    }

    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath

    Start-Process -FilePath $downloadPath -ArgumentList "/SILENT", "/NORESTART", "/SUPPRESSMSGBOXES", "/DIR=`"$extractPath`"" -Wait

    $sofficePath = Join-Path $extractPath "App\libreoffice\program\soffice.exe"
    if (Test-Path $sofficePath) {
        return $sofficePath
    } else {
        $sofficePath=$(read-host "Sorry, but we couldnt find your poratable libreoffice install. What we need is soffice.exe, usually at $sofficePath")
        $env:PATH = "$(Split-Path $sofficePath);$env:PATH"
    }
    return $sofficePath
}

Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance -HuduBaseURL $hudubaseurl -HuduAPIKey $huduapikey; Get-HuduVersionCompatible;

Write-Host @"
You're all ready to go and create any articles you'd like, from
- webpages
- pdfs
- local directory resources

Examples:
# from a web page
Set-HuduArticleFromWebPage -uri "https://en.wikipedia.org/wiki/Special:Random" -companyname "$($env:USERNAME)'s company" -title "website synced from $($env:COMPUTERNAME)"

# from a PDF file
Set-HuduArticleFromPDF -pdfPath "$($(Get-ChildItem $(join-path -Path $HOME -ChildPath "Downloads") -File -Filter "*.pdf" | select-object -First 1) ?? "c:\tmp\somepdf.pdf")" -companyname "$($env:USERNAME)'s company" -title "new article from pdf"

# From a folder containing any type of files
Set-HuduArticleFromResourceFolder -resourcesFolder "$(join-path -Path $HOME -ChildPath "Desktop") " -companyname "$($env:USERNAME)'s company" -title "$($env:USERNAME)'s Desktop Contents"

# From a local folder containing a webpage and images
Set-HuduArticleFromResourceFolder -resourcesFolder "$(join-path -Path $HOME -ChildPath "Pictures")" -companyname "$($env:USERNAME)'s company" -title "local pictures in $(join-path -Path $HOME -ChildPath "Pictures")"

"@


