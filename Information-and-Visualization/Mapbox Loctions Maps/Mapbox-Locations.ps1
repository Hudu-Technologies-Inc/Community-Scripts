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
$preferredStyle = "mapbox/satellite-v9"
# available styles: any custom ones in your mapbox account can be used,
# mapbox/standard-satellite, mapbox/dark-v11, mapbox/navigation-night-v1, mapbox/navigation-day-v1, mapbox/outdoors-v12 are but a few examples of styles you can use!

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


$workdir = $PSScriptRoot

function Build-MapboxStaticUrl {
  param(
    [Parameter(Mandatory)] [string] $Style,      # e.g. 'mapbox/light-v11'
    [Parameter(Mandatory)] [double] $CenterLon,
    [Parameter(Mandatory)] [double] $CenterLat,
    [Parameter(Mandatory)] [double] $Zoom,       # fractional ok
    [Parameter(Mandatory)] [int]    $Width,
    [Parameter(Mandatory)] [int]    $Height,
    [Parameter(Mandatory)] [string] $AccessToken,
    [object[]] $Pins = @()                       # ignored on purpose (no pins)
  )
  $lonC = '{0:F6}' -f $CenterLon
  $latC = '{0:F6}' -f $CenterLat
  return ('https://api.mapbox.com/styles/v1/{0}/static/{1},{2},{3}/{4}x{5}?access_token={6}' -f `
    $Style, $lonC, $latC, $Zoom, $Width, $Height, $AccessToken)
}
function Sanitize-Hex([string]$hex,[string]$fallback='#ff4e4e') {
  if ([string]::IsNullOrWhiteSpace($hex)) { return $fallback }
  $h = $hex.Trim()
  if ($h.StartsWith('#')) { $h = $h.Substring(1) }
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
    [Parameter(Mandatory)] [string]   $BackgroundUrl,
    [Parameter(Mandatory)] [double]   $CenterLon,
    [Parameter(Mandatory)] [double]   $CenterLat,
    [Parameter(Mandatory)] [double]   $Zoom,
    [int] $Width = 1200,
    [int] $Height = 800,
    [ValidateSet(256,512)] [int] $TileSize = 512,
    [switch] $ShowLabels,
    [switch] $AsDocument,
    [switch] $DotShadow,
    [switch] $ShowSidebar,
    [int]    $SidebarWidth = 300    # px
  )

  # ---- projection helpers ----
  $worldPx = $TileSize * [math]::Pow(2, $Zoom)
  $cPx = ((($CenterLon + 180.0) / 360.0) * $worldPx)
  $radC = [math]::PI * $CenterLat / 180.0
  $cPy = ((1.0 - [math]::Log([math]::Tan($radC) + 1.0/[math]::Cos($radC)) / [math]::PI) / 2.0) * $worldPx

  function Project([double]$lon,[double]$lat){
    $px = ((($lon + 180.0) / 360.0) * $worldPx)
    $rad = [math]::PI * $lat / 180.0
    $py = ((1.0 - [math]::Log([math]::Tan($rad) + 1.0/[math]::Cos($rad)) / [math]::PI) / 2.0) * $worldPx
    [pscustomobject]@{ X=[math]::Round(($px-$cPx)+($Width/2.0),2); Y=[math]::Round(($py-$cPy)+($Height/2.0),2) }
  }
  function Get-Prop { param($o,[string[]]$names)
    foreach ($n in $names) {
      if ($o -is [hashtable]) { if ($o.ContainsKey($n)) { return $o[$n] } }
      else { $p=$o.PSObject.Properties | Where-Object { $_.Name -ieq $n } | Select-Object -First 1; if ($p){ return $p.Value } }
    }; $null
  }

  # ---- build the SVG map (left column) ----
  $svg = New-Object Text.StringBuilder
  $null = $svg.AppendLine("<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='$Width' height='$Height' viewBox='0 0 $Width $Height'>")
  $null = $svg.AppendLine(@"
  <defs>
    <style>
      .lbl { font:12px/1.2 -apple-system,Segoe UI,Roboto,sans-serif; fill:#$(if ($preferredStyle -ilike "*dark*"){"fff"} else {"111"}); paint-order:stroke; stroke:#fff; stroke-width:.8px }
      a { cursor:pointer }
    </style>
    <filter id="textShadow" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="0" dy="0" stdDeviation="2.2" flood-color="#000000" flood-opacity="0.55"/>
    </filter>
    <filter id="dotShadow" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="0" dy="1" stdDeviation="1.4" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
  </defs>
"@)
  $null = $svg.AppendLine("  <image x='0' y='0' width='$Width' height='$Height' href='$BackgroundUrl'/>")
  $null = $svg.AppendLine('  <g id="points">')

  # also build sidebar rows while we loop
  $rows = New-Object System.Collections.Generic.List[string]

  foreach ($p in $Points) {
    $lon=[double]($p.Lon ?? $p['lon']); $lat=[double]($p.Lat ?? $p['lat'])
    $pt = Project $lon $lat
    $titleRaw = [string](Get-Prop $p @('Name','name','title','label'))
    $title = [System.Security.SecurityElement]::Escape($titleRaw)
    $hrefV = (Get-Prop $p @('Url','url','href','link'))
    $href  = [System.Security.SecurityElement]::Escape([string]($hrefV ?? "https://www.google.com/maps/search/?api=1&query=$lat,$lon"))

    $isMain = $false
    if ($p.PSObject -and $p.PSObject.Properties['isMain']) { $isMain = [bool]$p.isMain }
    elseif ($p -is [hashtable] -and $p.ContainsKey('isMain')) { $isMain = [bool]$p['isMain'] }

    $rawHex = [string](Get-Prop $p @('Color','color','Hex','hex','colour','markerColor'))
    $defaultFill = ($isMain ? '#ffd000ff' : '#ff4e4e')
    $fill   = Sanitize-Hex $rawHex $defaultFill
    $stroke = Darken-Hex  $fill 0.55

    $radius = $isMain ? 7 : 5
    $dotFilter = ($DotShadow ? " filter='url(#dotShadow)'" : "")
    $label  = if ($ShowLabels) {
      "<text class='lbl' filter='url(#textShadow)' x='$([math]::Round($pt.X+8,2))' y='$([math]::Round($pt.Y-8,2))'>$title</text>"
    } else { "" }

    # Map marker
    $null = $svg.AppendLine(
      "    <a xlink:href='$href' target='_blank' rel='noopener'>" +
      "<circle cx='$($pt.X)' cy='$($pt.Y)' r='$radius' fill='$fill' stroke='$stroke' stroke-width='1.4'$dotFilter><title>$title</title></circle>" +
      $label + "</a>"
    )

    # Sidebar row (small bullet + truncated label)
    if ($ShowSidebar) {
      $shortTitle = if ($titleRaw.Length -gt 60) { $titleRaw.Substring(0,57) + '…' } else { $titleRaw }
      $safeShort  = [System.Security.SecurityElement]::Escape($shortTitle)
      $row = "<a class='row' href='$href' target='_blank' rel='noopener'>" +
             "<span class='dot' style='background:$fill;border-color:$stroke'></span>" +
             "<span class='txt'>$safeShort</span></a>"
      [void]$rows.Add($row)
    }
  }

  $null = $svg.AppendLine('  </g></svg>')
  $svgStr = $svg.ToString()

  # ---- layout: map + sidebar ----
  $sidebarHtml = if ($ShowSidebar) {
@"
  <aside class="side">
    <div class="side-head">Locations</div>
    <div class="side-list">
      $( ($rows -join "`n") )
    </div>
  </aside>
"@
  } else { "" }

  $layoutCss = @"
  <style>
    .wrap { display:flex; gap:16px; align-items:flex-start; }
    .map { flex:1 1 auto; min-width:0; }
    .map svg { width:100%; height:auto; display:block; }
    .side { flex:0 0 ${SidebarWidth}px; max-width:${SidebarWidth}px; font:13px/1.3 -apple-system,Segoe UI,Roboto,sans-serif; }
    .side-head { font-weight:600; margin-bottom:8px; }
    .side-list { max-height:${Height}px; overflow:auto; border:1px solid #e5e5e5; border-radius:10px; padding:6px; background:#fff }
    .row { display:flex; align-items:center; gap:8px; text-decoration:none; color:#111; padding:6px 8px; border-radius:8px; }
    .row:hover { background:#f5f7fb; }
    .dot { width:10px; height:10px; border-radius:50%; border:1px solid transparent; display:inline-block; }
    .txt { display:inline-block; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width:${SidebarWidth - 40}px; }
    @media (max-width: 900px) {
      .wrap { flex-direction:column; }
      .side { width:100%; max-width:100%; }
      .txt { max-width: calc(100% - 40px); }
    }
  </style>
"@

  $content = "<div class='wrap'><div class='map'>$svgStr</div>$sidebarHtml</div>"

  if ($AsDocument) {
    return "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>$layoutCss</head><body>$content</body></html>"
  } else {
    return "$layoutCss$content"
  }
}


function Get-RandomHexString { param([int]$bytes=8)
  [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes($bytes)).ToLowerInvariant()
}
function ProcessLocationsTOHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [object[]] $Points,
    [string] $Style = 'mapbox/light-v11',
    [int]    $Width = 1200,
    [int]    $Height = 800,
    [int]    $PaddingPx = 60,
    [int]    $SinglePointZoom = 12,
    [double] $ZoomBias = 0.0,
    [ValidateSet(256,512)] [int] $TileSize = 512,
    [switch] $Retina,
    [int]    $CompanyId,
    [switch] $ShowLabels,
    [switch] $VerboseUrl
  )

  if (-not $Points) { throw "No points provided." }
  if ([string]::IsNullOrWhiteSpace($MapboxAccessToken)) { throw "MapboxAccessToken is empty." }

  # --- normalize points into $pts ---
  function Get-Prop { param($o,[string[]]$names)
    foreach ($n in $names) {
      if ($o -is [hashtable]) { if ($o.ContainsKey($n)) { return $o[$n] } }
      else { $p=$o.PSObject.Properties | Where-Object { $_.Name -ieq $n } | Select-Object -First 1; if ($p){ return $p.Value } }
    }; $null
  }
  function Normalize-Point { param([double]$Lon,[double]$Lat)
    if ([math]::Abs($Lat) -gt 90 -and [math]::Abs($Lon) -le 90) { $t=$Lon; $Lon=$Lat; $Lat=$t }
    if ($Lat -gt 85.05112878) { $Lat = 85.05112878 }
    if ($Lat -lt -85.05112878) { $Lat = -85.05112878 }
    [pscustomobject]@{ Lon=$Lon; Lat=$Lat }
  }
  function LonToMX([double]$lon) { ($lon + 180.0) / 360.0 }
  function LatToMY([double]$lat) {
    $rad = [math]::PI/180.0 * $lat
    (1.0 - [math]::Log([math]::Tan($rad) + 1.0/[math]::Cos($rad)) / [math]::PI) / 2.0
  }
  function MYToLat([double]$my) {
    $n = [math]::PI * (1 - 2*$my)
    (180.0 / [math]::PI) * [math]::Atan([math]::Sinh($n))
  }

  $pts = foreach ($p in $Points) {
    $lonRaw = Get-Prop $p @('lon','longitude','x')
    $latRaw = Get-Prop $p @('lat','latitude','y')
    if ($lonRaw -ne $null -and $latRaw -ne $null) {
      $lon=[double]::Parse("$lonRaw",[Globalization.CultureInfo]::InvariantCulture)
      $lat=[double]::Parse("$latRaw",[Globalization.CultureInfo]::InvariantCulture)
      $n = Normalize-Point -Lon $lon -Lat $lat
      [pscustomobject]@{
        Name = (Get-Prop $p @('name','title','label'))
        Url  = (Get-Prop $p @('url','href','link'))
        Lon  = $n.Lon
        Lat  = $n.Lat
      }
    }
  }

  # ---- fit center & fractional zoom using THIS $pts/$Width/$Height ----
  $mx = @(); $my = @()
  foreach ($p in $pts) { $mx += LonToMX $p.Lon; $my += LatToMY $p.Lat }

  $minMX = ($mx | Measure-Object -Minimum).Minimum
  $maxMX = ($mx | Measure-Object -Maximum).Maximum
  $minMY = ($my | Measure-Object -Minimum).Minimum
  $maxMY = ($my | Measure-Object -Maximum).Maximum

  $innerW = [math]::Max($Width  - 2*$PaddingPx, 1)
  $dMX = [math]::Max($maxMX - $minMX, 1e-12)
  $dMY = [math]::Max($maxMY - $minMY, 1e-12)

  if ($pts.Count -eq 1) {
    $z = [double][int]$SinglePointZoom
  } else {
    $zX = [math]::Log(($innerW / ($TileSize * $dMX)), 2)
    $zY = [math]::Log(($innerH / ($TileSize * $dMY)), 2)
    $z  = [math]::Min($zX, $zY)
    if ($PSBoundParameters.ContainsKey('ZoomBias')) { $z -= $ZoomBias }
  }


  
  $cMX = ($minMX + $maxMX) / 2.0
  $cMY = ($minMY + $maxMY) / 2.0
  $centerLon = $cMX * 360.0 - 180.0
  $centerLat = MYToLat $cMY

  # Inner viewport after padding
  $innerW = [math]::Max($Width  - 2*$PaddingPx, 1)
  $innerH = [math]::Max($Height - 2*$PaddingPx, 1)

  # BBox span in normalized mercator; avoid 0 with a tiny epsilon
  $eps  = 1e-9
  $dMX  = [math]::Max($maxMX - $minMX, $eps)
  $dMY  = [math]::Max($maxMY - $minMY, $eps)

  # Ratios for zoom fit; clamp floors so Log never sees 0
  $ratioX = [math]::Max($innerW / ($TileSize * $dMX), $eps)
  $ratioY = [math]::Max($innerH / ($TileSize * $dMY), $eps)

  $zX = [math]::Log($ratioX, 2)
  $zY = [math]::Log($ratioY, 2)
  $z  = [math]::Min($zX, $zY)   # fractional zoom OK

  # Optional zoom-out bias
  if ($PSBoundParameters.ContainsKey('ZoomBias')) { $z -= $ZoomBias }

  # Fallbacks if anything went weird
  if ([double]::IsNaN($z) -or [double]::IsInfinity($z)) { $z = [double][int]$SinglePointZoom }

  # Clamp to Mapbox’s sane range (0–22)
  $z = [math]::Min([math]::Max($z, 0), 22)

  # Format invariant for the URL
  $zStr = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:0.####}', $z)


  # --- build URL using ONLY locals ---
  $u = Build-MapboxStaticUrl `
        -Style $Style `
        -CenterLon $centerLon -CenterLat $centerLat -Zoom $zStr `
        -Width $Width -Height $Height `
        -AccessToken $MapboxAccessToken `
        -Pins $pts

  Write-Host "STATIC URL: $u" -ForegroundColor Cyan
  $pts | ForEach-Object { Write-Host (" pin lon={0:F6} lat={1:F6} name='{2}'" -f $_.Lon,$_.Lat,($_.Name)) }

  if ($true -eq $DownloadTiles){
    $pngPath ="$workdir\$(get-random -Minimum 1111111 -Maximum 9999999)-geodata.png"
    write-host "map downloaded uploaded as $($pngPath)"
    Invoke-WebRequest -Uri "$u" -OutFile "$pngPath" -TimeoutSec 60

    $publicphoto = $(New-HuduPublicPhoto -FilePath $pngPath).public_photo
    $u = $publicphoto.url ?? $u
    write-host "using $u for static image URL"
  }

    # --- render SVG using the SAME locals ---
  $html = New-MapHtml `
    -Points $points `
    -BackgroundUrl $u `
    -CenterLon $centerLon -CenterLat $centerLat -Zoom $zStr `
    -Width $Width -Height $height -TileSize $TileSize `
    -ShowLabels -ShowSidebar -SidebarWidth 280 -DotShadow -AsDocument

  return $html
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
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
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
        [string]$requiredVersion = "2.39.2",
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
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
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


Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible;

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
    $existingCompanyArticle = $(Get-HuduArticles -CompanyId $c.id -name $articleName | Select-Object -First 1); $existingCompanyArticle = $existingCompanyArticle.article ?? $existingCompanyArticle;
    if (-not $companyAddresses -or $companyAddresses.count -lt 1){write-host "No geodata to map for company $($c.name)."; continue}
    $articleGeodata = Get-GeocodeCollection -MapboxAccessToken $MapboxAccessToken -Addresses $companyAddresses
    if (-not $articleGeodata -or $articleGeodata.count -lt 1){write-host "No geodata to map for company $($c.name)."; continue}

    $htmlbody  = ProcessLocationsTOHtml -Points $articleGeodata -ShowLabels -Style $preferredStyle
    
    if ($htmlbody) {
        if ($existingCompanyArticle){
            Set-HuduArticle -companyId $c.id -id $existingCompanyArticle.id -name $articleName -content "$htmlbody"
        } else {
            New-HuduArticle  -companyId $c.id -name $articleName -content "$htmlbody"
        }
    }
}
$globalArticleName = $GeoArticleNaming -replace "#COMPANYNAME", "Global"

$existingGlobalArticle = $(Get-HuduArticles -name $globalArticleName | Select-Object -First 1); $existingGlobalArticle = $existingGlobalArticle.article ?? $existingGlobalArticle;
$globalGeoData = Get-GeocodeCollection -MapboxAccessToken $MapboxAccessToken -Addresses $AllAddresses
$htmlbody  = ProcessLocationsTOHtml -Points $globalGeoData -ShowLabels  -Style $preferredStyle

if ($existingGlobalArticle){
    Write-Host "updating article for global KB Map with $($AllAddresses.count) company addresses"
    $r = Set-HuduArticle -id $existingGlobalArticle.id -name $globalArticleName -Content "$htmlbody"
} else {
    Write-Host "Creating global article global KB Map with $($AllAddresses.count) company addresses"
    $r = New-HuduArticle -name $globalArticleName -Content "$htmlbody"
}

$HuduApikey = $null
$MapboxAccessToken = $null
