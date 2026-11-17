function Set-SessionCulture {
    param(
        [Parameter(Mandatory)]
        [string]$Culture
    )
    $ci = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
    [System.Globalization.CultureInfo]::CurrentCulture   = $ci
}
Set-SessionCulture "en-US"
$HuduApikey = $HuduApikey ?? $(read-host "Enter Hudu API key")
$HuduBaseURL = $HuduBaseURL ?? $(read-host "Enter Hudu Base URL")
$MapboxAccessToken = $MapboxAccessToken ?? $(read-host "Enter Mapbox Public API key")
$GeoArticleNaming = "#COMPANYNAME Locations"
$DownloadTiles = $true
$preferredStyle = "mapbox/dark-v11"
# available styles: any custom ones in your mapbox account can be used,
# mapbox/satellite-v9, mapbox/dark-v11, mapbox/navigation-night-v1, mapbox/navigation-day-v1, mapbox/outdoors-v12 are but a few examples of styles you can use!
# Articles use standard images with numbered markers rendered by Mapbox, plus a linked location list.

######################### Location Layout
# your hudu asset layout should have a name like one of these [case-insensitive]. if you dont have a location-type layout, we can 
# only grab addresses from company objects (main addresses)
$LocationLayoutNames = @('location','locations','branch','office','site','building','sucursal','standort','filiale','vestiging')

######################### labels
<# either you must have a matching label in your location layout or have fields closely matching these potential field names [case-insensitive]
#>
$Address1Names = @('address line 1','address 1','address1','addr1','street','street address','line 1')
$Address2Names = @('address line 2','address 2','address2','addr2','line 2','apt','suite','unit')
$CityNames = @('city','town','locality','municipality','ciudad','ville','ort','gemeente')
$StateNames =  @('region','state','province','county','departement','bundesland','estado','provincia')
$ZipNames =  @('postal code','zip code','zipcode','zip','postcode','cp','code postal','plz','código postal','cap')
$CountryNames = @('country','country name','nation','país','pais','land','paese')


function Build-MapboxStaticUrl {
  param(
    [Parameter(Mandatory)] [string] $Style,      # e.g. 'mapbox/light-v11'
    [Parameter(Mandatory)] [double] $CenterLon,
    [Parameter(Mandatory)] [double] $CenterLat,
    [Parameter(Mandatory)] [double] $Zoom,       # fractional ok
    [Parameter(Mandatory)] [int]    $Width,
    [Parameter(Mandatory)] [int]    $Height,
    [Parameter(Mandatory)] [string] $AccessToken,
    [object[]] $Pins = @(),
    [switch] $Retina
  )
  if ($Pins.Count -gt 99) { throw 'A static map can contain at most 99 numbered markers. Split the locations into batches.' }
  $culture = [Globalization.CultureInfo]::InvariantCulture
  $overlays = for ($i = 0; $i -lt $Pins.Count; $i++) {
    $pin = $Pins[$i]
    $color = (Sanitize-Hex ([string]$pin.Color)).TrimStart('#')
    $size = if ($pin.IsMain) { 'l' } else { 's' }
    [string]::Format($culture, 'pin-{0}-{1}+{2}({3:F6},{4:F6})', $size, ($i + 1), $color, [double]$pin.Lon, [double]$pin.Lat)
  }
  $overlayPath = if ($overlays) { ($overlays -join ',') + '/' } else { '' }
  $scale = if ($Retina) { '@2x' } else { '' }
  $url = [string]::Format($culture, 'https://api.mapbox.com/styles/v1/{0}/static/{1}{2:F6},{3:F6},{4:0.####}/{5}x{6}{7}.png?access_token={8}',
    $Style, $overlayPath, $CenterLon, $CenterLat, $Zoom, $Width, $Height, $scale, [Uri]::EscapeDataString($AccessToken))
  if ($url.Length -gt 8192) { throw 'The Mapbox static image URL exceeds the 8,192-character limit.' }
  return $url
}
function Sanitize-Hex([string]$hex,[string]$fallback='#ff4e4e') {
  if ([string]::IsNullOrWhiteSpace($hex)) { return $fallback }
  $h = $hex.Trim()
  if ($h.StartsWith('#')) { $h = $h.Substring(1) }
  if ($h -match '^[0-9A-Fa-f]{8}$') { $h = $h.Substring(0,6) }
  if ($h.Length -eq 3) { $h = "$($h[0])$($h[0])$($h[1])$($h[1])$($h[2])$($h[2])" }
  if ($h.Length -ne 6 -or ($h -notmatch '^[0-9A-Fa-f]{6}$')) { return $fallback }
  "#$h"
}

function Darken-Hex([string]$hex,[double]$factor=0.65) {
  # factor 0..1 (lower = darker)
  $h = Sanitize-Hex $hex
  $r = [Convert]::ToInt32($h.Substring(1,2),16)
  $g = [Convert]::ToInt32($h.Substring(3,2),16)
  $b = [Convert]::ToInt32($h.Substring(5,2),16)
  $r = [int]([math]::Clamp([math]::Floor($r*$factor),0,255))
  $g = [int]([math]::Clamp([math]::Floor($g*$factor),0,255))
  $b = [int]([math]::Clamp([math]::Floor($b*$factor),0,255))
  '#{0:X2}{1:X2}{2:X2}' -f $r,$g,$b
}


function New-MapHtml {
  param(
    [Parameter(Mandatory)] [object[]] $Points,
    [Parameter(Mandatory)] [string] $BackgroundUrl,
    [int] $Width = 1200,
    [int] $Height = 800
  )

  # Use normal article blocks. Inline SVG and style blocks are not preserved by every editor schema.
  $imageUrl = [Net.WebUtility]::HtmlEncode($BackgroundUrl)
  $html = [Text.StringBuilder]::new()
  [void]$html.AppendLine("<img src='$imageUrl' alt='Locations map with numbered markers' width='$Width' height='$Height' />")
  [void]$html.AppendLine("<p><a href='$imageUrl'>Open full-size map</a></p>")
  [void]$html.AppendLine('<h3>Locations</h3><ol>')
  foreach ($point in $Points) {
    $name = [Net.WebUtility]::HtmlEncode([string]$point.Name)
    $url = [string]$point.Url
    if ([string]::IsNullOrWhiteSpace($url)) {
      $url = [string]::Format([Globalization.CultureInfo]::InvariantCulture,
        'https://www.google.com/maps/search/?api=1&query={0},{1}', $point.Lat, $point.Lon)
    }
    $href = [Net.WebUtility]::HtmlEncode($url)
    [void]$html.AppendLine("<li><p><a href='$href'>$name</a></p></li>")
  }
  [void]$html.AppendLine('</ol>')
  return $html.ToString()
}


function Get-RandomHexString { param([int]$bytes=8)
  [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes($bytes)).ToLowerInvariant()
}
function ProcessLocationsTOHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [object[]] $Points,
    [Parameter(Mandatory)] [ValidateRange(1,2147483647)] [int] $ArticleId,
    [string] $Style = 'mapbox/light-v11',
    [ValidateRange(1,1280)] [int] $Width = 1200,
    [ValidateRange(1,1280)] [int] $Height = 800,
    [int] $PaddingPx = 60,
    [int] $SinglePointZoom = 12,
    [double] $ZoomBias = 0.0,
    [ValidateSet(256,512)] [int] $TileSize = 512,
    [switch] $Retina,
    [int] $CompanyId,
    [switch] $ShowLabels,
    [switch] $VerboseUrl
  )

  if (-not $Points) { throw 'No points provided.' }
  if ([string]::IsNullOrWhiteSpace($MapboxAccessToken)) { throw 'MapboxAccessToken is empty.' }

  function Get-Prop {
    param($Object, [string[]]$Names)
    foreach ($name in $Names) {
      if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($name)) { return $Object[$name] }
      } else {
        $property = $Object.PSObject.Properties[$name]
        if ($property) { return $property.Value }
      }
    }
    return $null
  }
  function LonToMX([double]$Lon) { ($Lon + 180.0) / 360.0 }
  function LatToMY([double]$Lat) {
    $rad = [math]::PI / 180.0 * $Lat
    (1.0 - [math]::Log([math]::Tan($rad) + 1.0 / [math]::Cos($rad)) / [math]::PI) / 2.0
  }

  $culture = [Globalization.CultureInfo]::InvariantCulture
  $pts = @(foreach ($point in $Points) {
    $lonRaw = Get-Prop $point @('lon','longitude','x')
    $latRaw = Get-Prop $point @('lat','latitude','y')
    if ($null -eq $lonRaw -or $null -eq $latRaw) { continue }
    $normalized = Normalize-Point -Lon ([double]::Parse("$lonRaw", $culture)) -Lat ([double]::Parse("$latRaw", $culture))
    $isMain = [bool](Get-Prop $point @('isMain','main'))
    $defaultColor = if ($isMain) { '#ffd000' } else { '#ff4e4e' }
    [pscustomobject]@{
      Name = [string](Get-Prop $point @('name','title','label'))
      Url = Get-Prop $point @('url','href','link')
      Lon = $normalized.Lon
      Lat = $normalized.Lat
      IsMain = $isMain
      Color = Sanitize-Hex ([string](Get-Prop $point @('color','hex','colour','markerColor'))) $defaultColor
    }
  })
  if (-not $pts.Count) { throw 'No valid coordinates provided.' }

  # Mapbox supports numeric marker labels 1-99. Each map has its own matching location list.
  $mapCount = [int][math]::Ceiling($pts.Count / 99.0)
  $fragments = [Collections.Generic.List[string]]::new()
  for ($offset = 0; $offset -lt $pts.Count; $offset += 99) {
    $last = [math]::Min($offset + 98, $pts.Count - 1)
    $batch = @($pts[$offset..$last])
    $mapNumber = [int]($offset / 99) + 1
    $mx = @($batch | ForEach-Object { LonToMX $_.Lon })
    $my = @($batch | ForEach-Object { LatToMY $_.Lat })
    $boundsX = $mx | Measure-Object -Minimum -Maximum
    $boundsY = $my | Measure-Object -Minimum -Maximum
    $dMX = $boundsX.Maximum - $boundsX.Minimum
    $dMY = $boundsY.Maximum - $boundsY.Minimum
    $centerLon = (($boundsX.Minimum + $boundsX.Maximum) / 2.0) * 360.0 - 180.0
    $centerMY = ($boundsY.Minimum + $boundsY.Maximum) / 2.0
    $centerLat = (180.0 / [math]::PI) * [math]::Atan([math]::Sinh([math]::PI * (1 - 2 * $centerMY)))

    if ($batch.Count -eq 1 -or ($dMX -lt 1e-12 -and $dMY -lt 1e-12)) {
      $zoom = [double]$SinglePointZoom
    } else {
      $innerW = [math]::Max($Width - 2 * $PaddingPx, 1)
      $innerH = [math]::Max($Height - 2 * $PaddingPx, 1)
      $zX = [math]::Log($innerW / ($TileSize * [math]::Max($dMX, 1e-12)), 2)
      $zY = [math]::Log($innerH / ($TileSize * [math]::Max($dMY, 1e-12)), 2)
      $zoom = [math]::Min($zX, $zY)
    }
    $zoom = [math]::Min([math]::Max($zoom - $ZoomBias, 0), 22)
    $url = Build-MapboxStaticUrl -Style $Style -CenterLon $centerLon -CenterLat $centerLat -Zoom $zoom `
      -Width $Width -Height $Height -AccessToken $MapboxAccessToken -Pins $batch -Retina:$Retina
    if ($VerboseUrl) { Write-Host "STATIC URL: $($url -replace '(access_token=)[^&]+', '${1}[redacted]')" -ForegroundColor Cyan }

    $pngPath = Join-Path ([IO.Path]::GetTempPath()) "$([guid]::NewGuid().ToString('N'))-geodata.png"
    try {
      Write-Host "Article ${ArticleId}: downloading map $mapNumber/$mapCount with $($batch.Count) markers (zoom $($zoom.ToString('0.##', $culture)))..."
      Invoke-WebRequest -Uri $url -OutFile $pngPath -TimeoutSec 60 -ErrorAction Stop | Out-Null
      $bytes = [IO.File]::ReadAllBytes($pngPath)
      if ($bytes.Length -lt 24 -or [Convert]::ToHexString([byte[]]$bytes[0..7]) -ne '89504E470D0A1A0A') {
        throw "Mapbox did not return a PNG image for article $ArticleId."
      }
      Write-Host "Article ${ArticleId}: downloaded $($bytes.Length) bytes; uploading public photo..."
      $photo = New-HuduPublicPhoto -FilePath $pngPath -RecordType 'Article' -RecordId $ArticleId -ErrorAction Stop
      $photo = $photo.public_photo ?? $photo
      $photoId = [string]($photo.slug ?? $photo.id)
      if ([string]::IsNullOrWhiteSpace($photoId)) { throw "No public photo ID returned for article $ArticleId." }
      $photoUrl = "/public_photo/$([Uri]::EscapeDataString($photoId))"
      Write-Host "Article ${ArticleId}: uploaded map $mapNumber/$mapCount to $photoUrl"
    } finally {
      Remove-Item -LiteralPath $pngPath -ErrorAction SilentlyContinue
    }

    if ($mapCount -gt 1) { $fragments.Add("<h2>Map $mapNumber of $mapCount</h2>") }
    $fragments.Add((New-MapHtml -Points $batch -BackgroundUrl $photoUrl -Width $Width -Height $Height))
  }
  return $fragments -join "`n"
}

function Set-HuduLocationMapArticle {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [object[]] $Points,
    [string] $Style = 'mapbox/light-v11',
    [Nullable[int]] $CompanyId
  )

  $articleRequest = @{ Name = $Name }
  if ($null -ne $CompanyId) { $articleRequest.CompanyId = $CompanyId }
  $articles = @(Get-HuduArticles @articleRequest -ErrorAction Stop | ForEach-Object { $_.article ?? $_ })
  if ($null -eq $CompanyId) {
    $articles = @($articles | Where-Object { -not $_.company_id })
  }
  $article = $articles | Select-Object -First 1

  # Existing articles keep their content until the replacement map is ready.
  if (-not $article) {
    $article = New-HuduArticle @articleRequest -Content '<p>Generating location map...</p>' -ErrorAction Stop
    $article = $article.article ?? $article
    Write-Host "Created placeholder article '$Name' (id $($article.id))."
  } else {
    Write-Host "Updating map for '$Name' (article $($article.id))."
  }
  if (-not $article.id) { throw "No article ID returned for '$Name'." }

  # Resolve embedded image sources locally, then send only the final content.
  $htmlBody = ProcessLocationsTOHtml -Points $Points -ArticleId $article.id -ShowLabels -Style $Style
  if ([string]::IsNullOrWhiteSpace($htmlBody)) { throw "No map content generated for '$Name'." }
  $imageCount = [regex]::Matches($htmlBody, '<img\b').Count
  Write-Host "Article $($article.id): saving final content with $imageCount map image(s)..."
  $result = Set-HuduArticle @articleRequest -Id $article.id -Content $htmlBody -ErrorAction Stop
  $savedArticle = $result.article ?? $result
  if ($null -ne $savedArticle.content -and [regex]::Matches([string]$savedArticle.content, '<img\b').Count -ne $imageCount) {
    throw "Article $($article.id) was updated, but Hudu's response did not retain all $imageCount map image(s)."
  }
  Write-Host "Article $($article.id): final content saved."
  return $result
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

function Get-HuduVersionCompatible {
    param (
        [string]$requiredVersion = "2.45.0",
        $DisallowedVersions = @(([version]"2.37.0"))
    )
    $RequiredHuduVersion = $([version]$requiredVersion)
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

function Invoke-MapboxForwardGeocode {
  param(
    [string] $Query,
    [string] $AccessToken,
    [string] $country = "us"
  )
      $place = $query -replace " ","+"

    $ub = [System.UriBuilder]::new("https://api.mapbox.com/search/geocode/v6/forward?q=$place&access_token=$AccessToken")
    $url=$ub.Uri.AbsoluteUri
  try {
    $resp = $(Invoke-RestMethod -Method GET -Uri $url)
  } catch { write-host "Error $_" }
  return $resp.Features[0] ?? $null
  #   if ($resp.Features[0]) {
#     return $(Normalize-Point $resp.Features[0])
#   } else {return $null}
}

function Normalize-Point {
  param([double]$Lon,[double]$Lat)
  # auto-swap if clearly reversed
  if ([math]::Abs($Lat) -gt 90 -and [math]::Abs($Lon) -le 90) { $t=$Lon; $Lon=$Lat; $Lat=$t }
  # clamp to Web Mercator supported latitude
  if ($Lat -gt 85.05112878) { $Lat = 85.05112878 }
  if ($Lat -lt -85.05112878) { $Lat = -85.05112878 }
  [pscustomobject]@{ Lon=$Lon; Lat=$Lat }
}

function Get-GeocodeCollection {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][array] $Addresses,          # each item has .address and optional .url
    [Parameter(Mandatory)][string]$MapboxAccessToken
  )

  $out = New-Object System.Collections.Generic.List[object]
  foreach ($address in $Addresses) {
    $res = Invoke-MapboxForwardGeocode -Query "$($address.address)" -AccessToken "$MapboxAccessToken"
    # if it returns a FeatureCollection, grab [0]
    $coords = $res.geometry.coordinates
    if (-not $coords -and $res.features) { $coords = $res.features[0].geometry.coordinates }

    if ($coords -and $coords.Count -ge 2 -and $null -ne $coords[0] -and $null -ne $coords[1]) {
      # Mapbox: [lon, lat]
      $lon = [double]::Parse("$($coords[0])",[Globalization.CultureInfo]::InvariantCulture)
      $lat = [double]::Parse("$($coords[1])",[Globalization.CultureInfo]::InvariantCulture)
      $n = Normalize-Point -Lon $lon -Lat $lat

      $out.Add([pscustomobject]@{
        name = "$($address.name)"
        lon  = $n.Lon
        lat  = $n.Lat
        url  = $address.url ?? $null
        main = $address.isMain ?? $false
        color = $address.color ?? "#81c415ff"
      })
    }
  }
  return ,$out  # returns a collection; OK for 1 or many
}
function Get-ValueInLabelSet {
  param (
    [array]$asset,
    [array]$labelSet
  )
  foreach ($potentialLabel in $labelSet){
    $match = $null
    $match = $asset.fields | where-object {$true -eq $(Test-Equiv -A $_.label -B $potentialLabel)} | Select-Object -First 1
    if ($null -ne $match -and $null -ne $match.Value){ return $match.Value }
  }
  return $null
}

function get-FieldLabelAddressType {
  param (
    [array]$fields,
    [array]$labelSet
  )
  foreach ($field in $fields){
    foreach ($label in $labelset) {
      if (test-equiv -A $field.label -B $label){
        return $field
      }
    }
  }
  return $null
}
function Get-LocationLayout {
  param ([array]$LocationLayoutNames)
  foreach ($layout in $(get-huduassetlayouts)){
    foreach ($label in $LocationLayoutNames){
      if ($true -eq $(Test-Equiv -A $label -$layout.name)){
        return $layout
      }
    }
  }
  Write-Host "No location layout found. Ensure your location layout name is in LocationLayoutNames array ($LocationLayoutNames)"
  exit 1
}


Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance -HuduBaseURL $huduBaseURL -HuduAPIKey $HuduAPIKey; Get-HuduVersionCompatible;

$companyColors = @{}
foreach ($c in $allCompanies){
  $companyColors[$c.id]=$($bytes = New-Object byte[] 3; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes); '#{0:X2}{1:X2}{2:X2}' -f $bytes[0],$bytes[1],$bytes[2])
}

$addresses = @{}
Write-Host "Fetching companies from $(Get-HuduBaseURL)"; $AllCompanies = Get-HuduCompanies
$LocationLayout = Get-LocationLayout -LocationLayoutNames $LocationLayoutNames; $LocationLayout.asset_layout ?? $LocationLayout;
Write-Host "Location Asset Layout seems to be $($LocationLayout.name) with id $($LocationLayout.id)"
$AddressLayoutField = $null

if ($locationLayout.fields.field_type -contains "AddressData"){
    "Layout $($LocationLayout.name) seems to contain AddressData Field. Using this for Subsequent locations."
    $AddressLayoutField = $locationLayout.fields | Where-Object {$_.field_type -eq 'AddressData'} | select-object -first 1
} else {
    "Determining Layout $($LocationLayout.name) fields for Address data parsing (subsequent/child/asset locations)"
    $addr1Field = get-FieldLabelAddressType -fields $LocationLayout.fields -labelset $Address1Names
    $addr2Field = get-FieldLabelAddressType -fields $LocationLayout.fields -labelset $Address2Names
    $cityField = get-FieldLabelAddressType -fields $LocationLayout.fields -labelset $CityNames
    $StateField = get-FieldLabelAddressType -fields $LocationLayout.fields -labelset $StateNames
    $CountryField = get-FieldLabelAddressType -fields $LocationLayout.fields -labelset $CountryNames
    $ZipField = get-FieldLabelAddressType -fields $LocationLayout.fields -labelset $ZipNames
}

$AllAddresses = [System.Collections.ArrayList]@()

if ($null -ne $AddressLayoutField){
    $LocationBuilder = @("address_line_1","address_line_2","city","state","zip","country")
} else {
    $LocationBuilder = @("$($Addr1Field.label)","$($Addr2Field.label)","$($CityField.label)","$($StateField.label)","$($CountryField.label)","$($ZipField.label)")
}
foreach ($c in $($AllCompanies | Where-Object {-not ([string]::IsNullOrWhiteSpace($_.address_line_1)) -and (-not ([string]::IsNullOrWhiteSpace($_.city))) -or ([string]::IsNullOrWhiteSpace($_.state))})){
    $companyAddresses = [System.Collections.ArrayList]@()
    $MainAddress = ""
    foreach ($prop in @("address_line_1","address_line_2","city","state","zip","country")){
        if ([string]::IsNullOrWhiteSpace($c.$prop)){continue}
        $MainAddress+=" $($c.$prop)"
    }
    if (-not $([string]::IsNullOrWhiteSpace($MainAddress))){
        $companyAddresses += @{address=$MainAddress; name="$($c.name) - Main"; url=$c.full_url; isMain = $true; color=$companyColors[$c.id]}
        $AllAddresses+=@{address=$MainAddress; name="$($c.name) - Main"; url=$c.full_url; isMain = $true; color=$companyColors[$c.id]}

    }   


    $locations = Get-HuduAssets -CompanyId $c.id -AssetLayoutId $LocationLayout.id
    foreach ($l in $locations){
        Write-Host "Processing Location $($l.name) for company: $($c.name)"
            $location = ""
            foreach ($locName in $LocationBuilder){
                if ($null -ne $AddressLayoutField){
                    write-host "processing addressdata field $locName"
                    $value = $($l.fields["$($AddressLayoutField.label)"].$locname)
                    write-host "$value"
                } else {
                    write-host "processing address field $locName"
                    $value = $($l.fields | where-object {$_.label -eq $locName} | select-object -first 1).Value
                    write-host "$value"
                }
                
                if ([string]::IsNullOrWhiteSpace($value)){continue}
                $location+=" $value"
            }
            if (-not $([string]::IsNullOrWhiteSpace($location))){
                $cleansedQuery = $("$location" -replace '\s+', ' ' ).Trim()
                

                $companyAddresses+=@{address=$cleansedQuery;  name="$($c.name)- $($l.name)"; url=$c.full_url; isMain=$false; color=$companyColors[$c.id]}
                $AllAddresses+=@{address=$cleansedQuery;  name="$($c.name)- $($l.name)"; url=$c.full_url; isMain=$false; color=$companyColors[$c.id]}
            }   
        
    }
    $articleName = $GeoArticleNaming -replace "#COMPANYNAME", "$($c.name)"
    if (-not $companyAddresses -or $companyAddresses.count -lt 1){write-host "No geodata to map for company $($c.name)."; continue}
    $articleGeodata = Get-GeocodeCollection -MapboxAccessToken $MapboxAccessToken -Addresses $companyAddresses
    if (-not $articleGeodata -or $articleGeodata.count -lt 1){write-host "No geodata to map for company $($c.name)."; continue}

    $r = Set-HuduLocationMapArticle -Name $articleName -CompanyId $c.id -Points $articleGeodata -Style $preferredStyle
}
$globalArticleName = $GeoArticleNaming -replace "#COMPANYNAME", "Global"

$globalGeoData = Get-GeocodeCollection -MapboxAccessToken $MapboxAccessToken -Addresses $AllAddresses
if ($globalGeoData -and $globalGeoData.Count -gt 0) {
    Write-Host "Saving global KB map with $($AllAddresses.count) company addresses"
    $r = Set-HuduLocationMapArticle -Name $globalArticleName -Points $globalGeoData -Style $preferredStyle
} else {
    Write-Host 'No geodata to map for the global KB.'
}

$HuduApikey = $null
$MapboxAccessToken = $null
