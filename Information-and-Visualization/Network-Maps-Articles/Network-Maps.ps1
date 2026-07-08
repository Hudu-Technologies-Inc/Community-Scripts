# Authentication 
$AzVault_HuduSecretName = "HuduAPIKeySecretName"                 # Name of your secret in AZure Keystore for your Hudu API key
$AzVault_Name           = "MyVaultName"                          # Name of your Azure Keyvault
$UseAZVault = $false

# Hudu Instance
$HuduBaseURL            =  $HuduBaseURL ?? `
                          "https://myinstance.huducloud.com"     # Hudu Instance URL (no trailing slashes)

# Customization
$networkRolesListName = "Network Roles"
$networkStatusesListName = "Network Statuses"

$BackgroundColor = '#b8eedaff'
$TextColor       = '#13004aff'
$EdgeColor       = '#6b7280'
$NetworkColor    = '#00ffdd'
$VlanColor       = '#6aa9ff'
$ZoneColor       = '#ffaa6a'
$AssetColor      = '#f7e55ba0'
$AddressColor    = '#9aa0a6'
$WebsiteColor    = '#c084fc'
$ActiveDeviceColor = "#00ea4aff"
$reservedColor = "#ffff00"
$InactiveColor = "#ff0000"
$iconsArticleName = "Network Maps Icons"

$OpenLinksInNewWindow = $false # Open links to assets, networks, vlans, zones, or addresses in new window or same window

$IncludeExtendedNetworkMeta = $true #Show 'Type','LocationId','Description','VLAN ID' in Networks

$IncludeExtendedAssetMeta = $true # Show 'Name','Manufacturer','Model','Serial' Properties in Assets

$IncludeAddressMeta = $true  # Show 'Status','FQDN','Description' properties in Address

$IncludeWebsiteLinks = $true # Link IP address FQDN/public DNS matches to Hudu Website records
$ResolvePublicWebsiteDns = $true # Resolve Hudu website DNS for IP matches on Public networks only
$MaxWebsitesPerAddress = 3 # Avoid crowding the diagram when multiple websites resolve to the same IP

$ShowDetails = $true # Add additional relationships and entity details during page generation

$NetworkMapOutputFormat = "Mermaid" # Mermaid uses Hudu's native diagram renderer. SvgHtml keeps the original generated SVG/HTML output.

$MaxAddressesPerNetwork = 200

$CurvyEdges = $true # Use Bézier curves or straight lines when drawing relationship lines

$SaveHTML=$false # Save a copy of network HTML to local directory

$NetworkArticleNamingPrefix = ""
$NetworkArticleNamingSuffix = "$NetworkMapOutputFormat Chart"
$NetworkArticleTitleMaxLength = 120
$NetworkArticleIncludeId = $true

$ColorByStatus = @{
  'Active'    = $ActiveDeviceColor
  'Assigned'    = $ActiveDeviceColor
  'Reserved'  = $ReservedColor
  'DHCP'  = $ReservedColor
  'Deprecated' = $InactiveColor
  'Inactive'  = $InactiveColor
  'Unassigned'  = $InactiveColor
}
$ColorByType = @{
  Network = $ActiveDeviceColor
  VLAN    = $VlanColor
  Zone    = $ZoneColor
  Asset   = $AssetColor
  Address = $AddressColor
  Website = $WebsiteColor
}

$AvailableIcons = @(
    @{Name="Router"; UploadID = $null; Type="svg"; Icon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGNsYXNzPSJsdWNpZGUgbHVjaWRlLXJvdXRlci1pY29uIGx1Y2lkZS1yb3V0ZXIiPjxyZWN0IHdpZHRoPSIyMCIgaGVpZ2h0PSI4IiB4PSIyIiB5PSIxNCIgcng9IjIiLz48cGF0aCBkPSJNNi4wMSAxOEg2Ii8+PHBhdGggZD0iTTEwLjAxIDE4SDEwIi8+PHBhdGggZD0iTTE1IDEwdjQiLz48cGF0aCBkPSJNMTcuODQgNy4xN2E0IDQgMCAwIDAtNS42NiAwIi8+PHBhdGggZD0iTTIwLjY2IDQuMzRhOCA4IDAgMCAwLTExLjMxIDAiLz48L3N2Zz4="},
    @{Name="Switch"; UploadID = $null; Type="svg"; Icon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGNsYXNzPSJsdWNpZGUgbHVjaWRlLWNoZXZyb25zLWxlZnQtcmlnaHQtZWxsaXBzaXMtaWNvbiBsdWNpZGUtY2hldnJvbnMtbGVmdC1yaWdodC1lbGxpcHNpcyI+PHBhdGggZD0iTTEyIDEyaC4wMSIvPjxwYXRoIGQ9Ik0xNiAxMmguMDEiLz48cGF0aCBkPSJtMTcgNyA1IDUtNSA1Ii8+PHBhdGggZD0ibTcgNy01IDUgNSA1Ii8+PHBhdGggZD0iTTggMTJoLjAxIi8+PC9zdmc+"},
    @{Name="Endpoint"; UploadID = $null; Type="svg"; Icon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGNsYXNzPSJsdWNpZGUgbHVjaWRlLWxhcHRvcC1taW5pbWFsLWljb24gbHVjaWRlLWxhcHRvcC1taW5pbWFsIj48cmVjdCB3aWR0aD0iMTgiIGhlaWdodD0iMTIiIHg9IjMiIHk9IjQiIHJ4PSIyIiByeT0iMiIvPjxsaW5lIHgxPSIyIiB4Mj0iMjIiIHkxPSIyMCIgeTI9IjIwIi8+PC9zdmc+"}
    @{Name="Container"; UploadID = $null; Type="svg"; Icon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGNsYXNzPSJsdWNpZGUgbHVjaWRlLWNvbnRhaW5lci1pY29uIGx1Y2lkZS1jb250YWluZXIiPjxwYXRoIGQ9Ik0yMiA3LjdjMC0uNi0uNC0xLjItLjgtMS41bC02LjMtMy45YTEuNzIgMS43MiAwIDAgMC0xLjcgMGwtMTAuMyA2Yy0uNS4yLS45LjgtLjkgMS40djYuNmMwIC41LjQgMS4yLjggMS41bDYuMyAzLjlhMS43MiAxLjcyIDAgMCAwIDEuNyAwbDEwLjMtNmMuNS0uMy45LTEgLjktMS41WiIvPjxwYXRoIGQ9Ik0xMCAyMS45VjE0TDIuMSA5LjEiLz48cGF0aCBkPSJtMTAgMTQgMTEuOS02LjkiLz48cGF0aCBkPSJNMTQgMTkuOHYtOC4xIi8+PHBhdGggZD0iTTE4IDE3LjVWOS40Ii8+PC9zdmc+"}
    @{Name="Wireless"; UploadID = $null; Type="svg"; Icon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGNsYXNzPSJsdWNpZGUgbHVjaWRlLXdpZmktaWNvbiBsdWNpZGUtd2lmaSI+PHBhdGggZD0iTTEyIDIwaC4wMSIvPjxwYXRoIGQ9Ik0yIDguODJhMTUgMTUgMCAwIDEgMjAgMCIvPjxwYXRoIGQ9Ik01IDEyLjg1OWExMCAxMCAwIDAgMSAxNCAwIi8+PHBhdGggZD0iTTguNSAxNi40MjlhNSA1IDAgMCAxIDcgMCIvPjwvc3ZnPg=="}
    @{Name="DMZ"; UploadID = $null; Type="svg"; Icon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGNsYXNzPSJsdWNpZGUgbHVjaWRlLWJldHdlZW4tdmVydGljYWwtc3RhcnQtaWNvbiBsdWNpZGUtYmV0d2Vlbi12ZXJ0aWNhbC1zdGFydCI+PHJlY3Qgd2lkdGg9IjciIGhlaWdodD0iMTMiIHg9IjMiIHk9IjgiIHJ4PSIxIi8+PHBhdGggZD0ibTE1IDItMyAzLTMtMyIvPjxyZWN0IHdpZHRoPSI3IiBoZWlnaHQ9IjEzIiB4PSIxNCIgeT0iOCIgcng9IjEiLz48L3N2Zz4="}
    @{Name="VPN"; UploadID = $null; Type="svg"; Icon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9ImN1cnJlbnRDb2xvciIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiIGNsYXNzPSJsdWNpZGUgbHVjaWRlLWdsb2JlLWxvY2staWNvbiBsdWNpZGUtZ2xvYmUtbG9jayI+PHBhdGggZD0iTTE1LjY4NiAxNUExNC41IDE0LjUgMCAwIDEgMTIgMjJhMTQuNSAxNC41IDAgMCAxIDAtMjAgMTAgMTAgMCAxIDAgOS41NDIgMTMiLz48cGF0aCBkPSJNMiAxMmg4LjUiLz48cGF0aCBkPSJNMjAgNlY0YTIgMiAwIDEgMC00IDB2MiIvPjxyZWN0IHdpZHRoPSI4IiBoZWlnaHQ9IjUiIHg9IjE0IiB5PSI2IiByeD0iMSIvPjwvc3ZnPg=="}
<#
// Icons: Lucide (https://lucide.dev)
// Copyright (c) 2020 Lucide Contributors — MIT
// Full license in LICENSE.
#>
    )


# END OF CUSTOMIZATION OPTIONS
function Set-SessionCulture {
    param(
        [Parameter(Mandatory)]
        [string]$Culture
    )
    $ci = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
    [System.Globalization.CultureInfo]::CurrentCulture   = $ci
}
$Workdir = $(resolve-path .\)
Set-SessionCulture "en-US"

function Get-UploadUrlById([int]$id){
  if (-not $id) { return $null }
  $u = $AllUploads | Where-Object id -eq $id | Select-Object -First 1
  if (-not $u) { return $null }
  return $u.url
}

$HuduBaseURL = $HuduBaseURL ?? $(read-host "Enter hudu URL")
$HuduAPIKey = $HuduAPIKey ?? $(read-host "Enter hudu api key")
# Clear-Host
  function Get-StatusColor {
    param([string]$Status,[hashtable]$ColorByStatus)
    if ([string]::IsNullOrWhiteSpace($Status)) { return $InactiveColor }
    if ($ColorByStatus -and $ColorByStatus.ContainsKey($Status)) { return $ColorByStatus[$Status] }
    return $FallbackColor
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


function Get-Mask32 {
  param([Parameter(Mandatory)][int]$Prefix)
  if ($Prefix -le 0) { return [uint32]0 }
  if ($Prefix -ge 32){ return [uint32]0xFFFFFFFF }
  $mask = [uint32]0
  # set the first $Prefix bits to 1 (big-endian bit positions 31..0)
  for($i = 0; $i -lt $Prefix; $i++){
    $mask = $mask -bor ([uint32]1 -shl (31 - $i))
  }
  return $mask
}

function Convert-IPv4ToUInt32 {
  param([Parameter(Mandatory)][string]$Ip)
  $bytes = [System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
  if ($bytes.Length -ne 4) { throw "IPv4 only: $Ip" }
  [Array]::Reverse($bytes)
  [BitConverter]::ToUInt32($bytes, 0)
}

function Parse-Cidr {
  param([Parameter(Mandatory)][string]$Cidr) # e.g. "10.0.33.0/24"
  $ip, $prefix = $Cidr -split '/', 2
  $prefix = [int]$prefix
  if ($prefix -lt 0 -or $prefix -gt 32) { throw "Bad prefix: $prefix in $Cidr" }

  $netU = Convert-IPv4ToUInt32 $ip

  if ($prefix -eq 0) {
    $mask = [uint32]0
  } else {
    $rightZeros = 32 - $prefix
    # Build a mask of top $prefix 1-bits by inverting $rightZeros low 1-bits.
    $lowOnes = ([uint32]1 -shl $rightZeros) - 1      # 0…00011111111
    $mask    = -bnot $lowOnes                        # 1…11100000000
  }

  $start = $netU -band $mask
  $end   = $start -bor ((-bnot $mask) -band 0xFFFFFFFF)

  [pscustomobject]@{
    Cidr   = $Cidr
    Prefix = $prefix
    Start  = $start
    End    = $end
  }
}

function Test-CidrContains {
  param([Parameter(Mandatory)][string]$Outer,
        [Parameter(Mandatory)][string]$Inner)
  try {
    $o = Parse-Cidr $Outer
    $i = Parse-Cidr $Inner
    ($i.Start -ge $o.Start -and $i.End -le $o.End)
  } catch { $false }
}


function Get-NetworkChain {
  param(
    [Parameter(Mandatory)]$Network,
    [Parameter(Mandatory)][object[]]$AllNetworks
  )
  $chain = New-Object System.Collections.Generic.List[object]
  $chain.Add($Network) | Out-Null

  if ($Network.ancestry) {
    $ids = $Network.ancestry -split '/' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    foreach ($parentId in $ids) {
      $p = $AllNetworks | Where-Object id -eq $parentId | Select-Object -First 1
      if ($p) { $chain.Add($p) | Out-Null }
    }
  } else {
    foreach ($p in $AllNetworks) {
      if ($p.id -ne $Network.id -and $p.address -and (Test-CidrContains -Outer $p.address -Inner $Network.address)) {
        $chain.Add($p) | Out-Null
      }
    }
  }

  $chain | Sort-Object { (Parse-Cidr $_.address).Prefix } -Descending
}
function Build-NetworkIndex {
  param([Parameter(Mandatory)][object[]]$Networks)
  $rows = @()
  foreach ($n in @($Networks)) {
    $cidrObj = if ($n.address) { Parse-Cidr $n.address } else { $null }
    if ($cidrObj) {
      $rows += [pscustomobject]@{ Network = $n; Cidr = $cidrObj }
    } else {
      # Log once but do not throw
      Write-Host "Skip bad network address: $($n.address)" -ForegroundColor Yellow
    }
  }
  # Always return an array (possibly empty), never $null
  @($rows | Sort-Object { $_.Cidr.Prefix } -Descending)
}

function Find-NetworkForIp {
  param(
    [Parameter(Mandatory)][string]$Ip,
    [Parameter(Mandatory)][object[]]$NetworkIndex,
    [int]$CompanyId = $null
  )
  if (-not $NetworkIndex) { return $null }   # guard
  $ipU = Convert-IPv4ToUInt32 $Ip
  if ($null -eq $ipU) { return $null }

  foreach ($row in $NetworkIndex) {
    $n = $row.Network
    if ($CompanyId -and $n.company_id -ne $CompanyId) { continue }
    $c = $row.Cidr
    if ($ipU -ge $c.Start -and $ipU -le $c.End) { return $n }
  }
  $null
}
function Group-IpAddressesByNetwork {
  param(
    [Parameter(Mandatory)][object[]]$IpAddresses,
    [Parameter(Mandatory)][object[]]$Networks,
    [int]$CompanyId = $null
  )

  $idx = Build-NetworkIndex -Networks $Networks
  if ($null -eq $idx) { $idx = @() }  # harden

  $groups = @{}
  foreach ($ip in @($IpAddresses)) {
    if (-not $ip.address) { continue }
    if ($CompanyId -and $ip.company_id -ne $CompanyId) { continue }

    $net = Find-NetworkForIp -Ip $ip.address -NetworkIndex $idx -CompanyId $CompanyId
    $key = if ($net) { "net:$($net.id)" } else { "unmatched" }

    if (-not $groups.ContainsKey($key)) {
      $groups[$key] = [pscustomobject]@{ Network = $net; IPs = New-Object System.Collections.Generic.List[object] }
    }
    $groups[$key].IPs.Add($ip) | Out-Null
  }

  $groups.Values
}

function Get-NormalizedWebsiteHost {
  param([AllowNull()][string]$Website)
  if ([string]::IsNullOrWhiteSpace($Website)) { return $null }

  $s = $Website.Trim()
  if ($s -notmatch '^\w+://') { $s = "http://$s" }

  try {
    $uri = [Uri]$s
    $remoteHostName = $uri.IdnHost
    if ($remoteHostName.StartsWith('[') -and $remoteHostName.EndsWith(']')) { $remoteHostName = $remoteHostName.Trim('[',']') }
    return $remoteHostName.TrimEnd('.').ToLowerInvariant()
  } catch {
    $t = $Website.Trim()
    $t = $t -replace '^\w+://',''
    $t = $t -replace '^[^@/]*@',''
    $t = $t.TrimStart('[').TrimEnd(']')
    $t = $t -replace '[:/].*$',''
    return $t.TrimEnd('.').ToLowerInvariant()
  }
}

function Get-HuduWebsiteRecordUrl {
  param(
    [Parameter(Mandatory)]$Website,
    [AllowNull()][string]$HuduBaseUrl
  )
  if ($Website.url) {
    if ($Website.url -match '^https?://') { return $Website.url }
    if ($HuduBaseUrl) { return "$($HuduBaseUrl.TrimEnd('/'))$($Website.url)" }
  }
  if ($Website.slug -and $HuduBaseUrl) {
    return "$($HuduBaseUrl.TrimEnd('/'))/websites/$($Website.slug)"
  }
  return $null
}

function Resolve-WebsiteIPv4Addresses {
  param([Alias('HostName')][AllowNull()][string]$remoteHostName)
  if ([string]::IsNullOrWhiteSpace($remoteHostName)) { return @() }
  if (-not $script:WebsiteDnsCache) { $script:WebsiteDnsCache = @{} }

  $key = $remoteHostName.TrimEnd('.').ToLowerInvariant()
  if ($script:WebsiteDnsCache.ContainsKey($key)) { return @($script:WebsiteDnsCache[$key]) }

  $resolved = @()
  try {
    if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
      $resolved = @(Resolve-DnsName -Name $key -Type A -ErrorAction Stop |
        Where-Object { $_.IPAddress -and $_.IPAddress -match '^\d{1,3}(\.\d{1,3}){3}$' } |
        Select-Object -ExpandProperty IPAddress -Unique)
    } else {
      $resolved = @([System.Net.Dns]::GetHostAddresses($key) |
        Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
        ForEach-Object { $_.IPAddressToString } |
        Select-Object -Unique)
    }
  } catch {
    $resolved = @()
  }

  $script:WebsiteDnsCache[$key] = @($resolved)
  return @($resolved)
}

function Get-NetworkContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Network,
    [AllowNull()][object[]] $AllVlans,
    [AllowNull()][object[]] $AllVlanZones,
    [AllowNull()][object[]] $AllIpAddresses = $null,
    [AllowNull()][object[]] $AllWebsites = $null,
    $NetworkRoleList = $null,
    $NetworkStatusList = $null,
    [string] $HuduBaseUrl = $null,
    [bool] $IncludeExtendedNetworkMeta = $true,
    [bool] $IncludeExtendedAssetMeta = $true,
    [bool] $IncludeAddressMeta = $true,
    [bool] $IncludeWebsiteLinks = $false,
    [bool] $ResolvePublicWebsiteDns = $true,
    [int] $MaxWebsitesPerAddress = 3
  )

  # local helpers so this function is self-contained
  function Add-MetaIf([hashtable]$ht,[string]$key,$value,[string]$label=$null){
    if ($null -ne $value -and "$value" -ne '') { $ht[$($label ?? $key)] = $value }
  }
  function Map-NetworkType($t){
    if ($null -eq $t) { return $null }
    switch ([int]$t) {
      0 { 'Private' }
      1 { 'Public'  }
      default { "$t" }
    }
  }

  $AllVlans     = @($AllVlans)     | Where-Object { $_ }
  $AllVlanZones = @($AllVlanZones) | Where-Object { $_ }

  # VLAN/Zone (id-type-agnostic)
  $vlan = $null
  if ($null -ne $Network -and ($Network.PSObject.Properties.Name -contains 'vlan_id') -and $Network.vlan_id) {
    $nid = "$($Network.vlan_id)"
    $vlan = @($AllVlans) | Where-Object { "$($_.id)" -eq $nid } | Select-Object -First 1
  }

  $zone = $null
  if ($vlan -and ($vlan.PSObject.Properties.Name -contains 'vlan_zone_id') -and $vlan.vlan_zone_id) {
    $vlan = $null; $zone = $null
    if ($Network.vlan_id) {
      $vlan = $AllVlans | Where-Object { $_.id -eq $Network.vlan_id } | Select-Object -First 1
      if ($vlan -and $vlan.vlan_zone_id) { $zone = $AllVlanZones | Where-Object { $_.id -eq $vlan.vlan_zone_id } | Select-Object -First 1 }
    } else {
      # Inherit from nearest ancestor with vlan_id (pass $AllNetworks from your main loop)
      if ($PSBoundParameters.ContainsKey('AllNetworks') -and $AllNetworks) {
        $r = Resolve-VlanAndZone -Network $Network -AllNetworks $AllNetworks -AllVlans $AllVlans -AllVlanZones $AllVlanZones
        $vlan = $r.Vlan; $zone = $r.Zone
      }
    }
  }

  # Addresses: prefer caller-supplied list; else try API
  $addresses = @()
  try {
    if ($AllIpAddresses) {
      $addresses = @($AllIpAddresses)  # trust caller
    } else {
      if (Get-Command -Name Get-HuduIPAddresses -ErrorAction SilentlyContinue) {
        $addresses = @(Get-HuduIPAddresses -NetworkId $Network.id) | Where-Object { $_ }
      } else {
        $raw = Invoke-HuduRequest -Resource "/api/v1/ip_addresses?network_id=$($Network.id)"
        $addresses = @($raw.data) + @($raw.ip_addresses) | Where-Object { $_ }
      }
    }
  } catch {}

  # Assets via addresses (best-effort, unique by id)
  $assets = @()
  foreach ($ip in $addresses) {
    if ($ip.asset_id) {
      try {
        $asset = Get-HuduAssets -Id $ip.asset_id
        if ($asset) { $assets += $asset }
      } catch {}
    }
  }
  $assets = $assets | Sort-Object id -Unique

  # URL fallbacks (if objects have slug/relative)
  if ($HuduBaseUrl) {
    $base = $HuduBaseUrl.TrimEnd('/')

    if (-not $Network.url -and $Network.slug) { $Network | Add-Member url "$base/networks/$($Network.slug)" -Force }
    if ($vlan -and -not $vlan.url -and $vlan.slug) { $vlan | Add-Member url "$base/vlans/$($vlan.slug)" -Force }
    if ($zone -and -not $zone.url -and $zone.slug) { $zone | Add-Member url "$base/vlan_zones/$($zone.slug)" -Force }

    foreach ($a in $assets) {
      if (-not $a.url -and $a.slug) { $a | Add-Member url "$base/assets/$($a.slug)" -Force }
    }
    foreach ($ip in $addresses) {
      if ($ip.url -and $ip.url -like '/a/*') { $ip.url = "$base$($ip.url)" }
      elseif (-not $ip.url -and $ip.id)     { $ip | Add-Member url "$base/ip_addresses/$($ip.id)" -Force }
    }
  }

  # Extended meta
  $NetworkExtraMeta = @{}
  if ($IncludeExtendedNetworkMeta) {
    Add-MetaIf $NetworkExtraMeta 'Type' (Map-NetworkType ($Network.network_type))
    Add-MetaIf $NetworkExtraMeta 'LocationId' $Network.location_id 'Location ID'
    Add-MetaIf $NetworkExtraMeta 'Description' $Network.description
    Add-MetaIf $NetworkExtraMeta 'VLAN_ID' $Network.vlan_id 'VLAN ID'
  }

  $AssetExtraMetaById = @{}
  if ($IncludeExtendedAssetMeta) {
    foreach ($a in $assets) {
      $m = @{}
      Add-MetaIf $m 'Name' $a.name
      Add-MetaIf $m 'Manufacturer' $a.primary_manufacturer
      Add-MetaIf $m 'Model' $a.primary_model
      Add-MetaIf $m 'Serial' $a.primary_serial
      if ($m.Count -gt 0) { $AssetExtraMetaById["$($a.id)"] = $m }
    }
  }

  $AddrExtraMetaByKey = @{}
  if ($IncludeAddressMeta) {
    foreach ($ip in $addresses) {
      $m = @{}
      Add-MetaIf $m 'Status' $ip.status
      Add-MetaIf $m 'FQDN' $ip.fqdn
      Add-MetaIf $m 'Description' $ip.description
      $key = "$($ip.id ?? $ip.address)"
      if ($m.Count -gt 0) { $AddrExtraMetaByKey[$key] = $m }
    }
  }

  $WebsiteMatchesByAddressKey = @{}
  if ($IncludeWebsiteLinks -and $AllWebsites) {
    $companyWebsites = @($AllWebsites | Where-Object { $_ -and $_.company_id -eq $Network.company_id })
    $websiteRows = foreach ($site in $companyWebsites) {
      $remoteHost = Get-NormalizedWebsiteHost $site.name
      if (-not $remoteHost) { continue }
      [pscustomobject]@{
        Website = $site
        Host    = $remoteHost
        Url     = Get-HuduWebsiteRecordUrl -Website $site -HuduBaseUrl $HuduBaseUrl
      }
    }

    $isPublicNetwork = $false
    try { $isPublicNetwork = ([int]$Network.network_type -eq 1) } catch {}
    $websiteRowsByHost = @{}
    foreach ($row in @($websiteRows)) {
      if (-not $websiteRowsByHost.ContainsKey($row.Host)) {
        $websiteRowsByHost[$row.Host] = New-Object System.Collections.Generic.List[object]
      }
      $websiteRowsByHost[$row.Host].Add($row) | Out-Null
    }

    foreach ($ip in $addresses) {
      $matches = New-Object System.Collections.Generic.List[object]
      $addrKey = "$($ip.id ?? $ip.address)"
      $fqdnHost = Get-NormalizedWebsiteHost $ip.fqdn

      if ($fqdnHost -and $websiteRowsByHost.ContainsKey($fqdnHost)) {
        foreach ($row in $websiteRowsByHost[$fqdnHost]) {
          $matches.Add([pscustomobject]@{
            Website = $row.Website
            Host = $row.Host
            Url = $row.Url
            MatchReason = 'FQDN'
          }) | Out-Null
        }
      }

      if ($isPublicNetwork -and $ResolvePublicWebsiteDns -and $ip.address) {
        foreach ($row in @($websiteRows)) {
          if ($fqdnHost -and $row.Host -eq $fqdnHost) { continue }
          $resolvedIps = Resolve-WebsiteIPv4Addresses -HostName $row.Host
          if ($resolvedIps -contains "$($ip.address)") {
            $alreadyMatched = @($matches | Where-Object { $_.Website.id -eq $row.Website.id } | Select-Object -First 1)
            if (-not $alreadyMatched) {
              $matches.Add([pscustomobject]@{
                Website = $row.Website
                Host = $row.Host
                Url = $row.Url
                MatchReason = 'DNS'
              }) | Out-Null
            }
          }
        }
      }

      if ($matches.Count -gt 0) {
        $WebsiteMatchesByAddressKey[$addrKey] = @($matches | Select-Object -First $MaxWebsitesPerAddress)
      }
    }
  }

  # Role/Status names
  $roleName   = if ($Network.role_list_item_id -and $NetworkRoleList)   { ($NetworkRoleList.list_items | Where-Object id -eq $Network.role_list_item_id | Select-Object -First 1).name } else { '' }
  $statusName = if ($Network.status_list_item_id -and $NetworkStatusList){ ($NetworkStatusList.list_items | Where-Object id -eq $Network.status_list_item_id | Select-Object -First 1).name } else { '' }

  Write-Host ("Context → {0}  IPs:{1}  Assets:{2}" -f $Network.address, $addresses.Count, $assets.Count) -ForegroundColor DarkCyan
  Write-Host ("Context → Vlans:{0}  Zones:{1}" -f $vlan.count, $Zone.Count) -ForegroundColor DarkCyan

  [pscustomobject]@{
    Network          = $Network
    Vlan             = $vlan
    Zone             = $zone
    Addresses        = $addresses
    Assets           = $assets
    RoleName         = $roleName
    StatusName       = $statusName
    NetworkMeta      = $NetworkExtraMeta
    AssetMetaById    = $AssetExtraMetaById
    AddressMetaByKey = $AddrExtraMetaByKey
    WebsiteMatchesByAddressKey = $WebsiteMatchesByAddressKey
  }
}


function Get-SafeFilename {
    param([string]$Name,
        [int]$MaxLength=40
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

function Normalize-ArticleTitle {
  param([AllowNull()][string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
  return (($Name.Trim() -replace '\s+', ' ').ToLowerInvariant())
}

function Get-NetworkDisplayName {
  param([Parameter(Mandatory)]$Network)
  $name = $Network.name ?? $Network.description ?? $Network.address ?? "Network $($Network.id)"
  $name = "$name".Trim()
  if ([string]::IsNullOrWhiteSpace($name)) { return "Network $($Network.id)" }
  return $name
}

function Get-NetworkArticleTitle {
  param(
    [Parameter(Mandatory)]$Network,
    [AllowNull()][string]$Prefix,
    [AllowNull()][string]$Suffix,
    [int]$MaxLength = 120,
    [bool]$IncludeId = $true
  )

  $parts = @($Prefix, (Get-NetworkDisplayName -Network $Network), $Suffix) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $title = (($parts -join ' ') -replace '\s+', ' ').Trim()
  if ($IncludeId) {
    $idSuffix = " [Network $($Network.id)]"
    $allowedBaseLength = [Math]::Max(1, $MaxLength - $idSuffix.Length)
    if ($title.Length -gt $allowedBaseLength) {
      $title = $title.Substring(0, $allowedBaseLength).TrimEnd()
    }
    $title = "$title$idSuffix"
  } elseif ($title.Length -gt $MaxLength) {
    $title = $title.Substring(0, $MaxLength).TrimEnd()
  }
  return $title
}

function Get-LegacyNetworkArticleTitles {
  param(
    [Parameter(Mandatory)]$Network,
    [AllowNull()][string]$Prefix,
    [AllowNull()][string]$Suffix
  )

  $names = New-Object System.Collections.Generic.List[string]
  $currentLegacy = Get-SafeFilename "$Prefix $($($($Network.name ?? $Network.address) -split'/')[0] ?? 'Network') $Suffix"
  $currentLegacy = ($currentLegacy -replace '\s+', ' ').Trim()
  if ($currentLegacy) { $names.Add($currentLegacy) | Out-Null }

  $olderLegacy = Get-SafeFilename "$Prefix$($Network.description ?? "Network $($Network.id)")"
  $olderLegacy = ($olderLegacy -replace '\s+', ' ').Trim()
  if ($olderLegacy) { $names.Add($olderLegacy) | Out-Null }

  $plainParts = @($Prefix, (Get-NetworkDisplayName -Network $Network), $Suffix) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $plain = (($plainParts -join ' ') -replace '\s+', ' ').Trim()
  if ($plain) { $names.Add($plain) | Out-Null }

  return @($names | Select-Object -Unique)
}

function Get-NetworkMapArticleMarker {
  param([Parameter(Mandatory)]$Network)
  return "hudu-network-map network_id=$($Network.id)"
}

function Add-NetworkMapArticleMarker {
  param(
    [Parameter(Mandatory)][string]$Content,
    [Parameter(Mandatory)]$Network,
    [Parameter(Mandatory)][string]$Format
  )
  $marker = Get-NetworkMapArticleMarker -Network $Network
  return "<!-- $marker format=$Format -->`n$Content"
}

function Get-HuduArticleCore {
  param($Article)
  if ($null -eq $Article) { return $null }
  return $Article.article ?? $Article
}

function Get-CachedHuduCompanyArticles {
  param(
    [Parameter(Mandatory)][int]$CompanyId,
    [Parameter(Mandatory)][hashtable]$Cache
  )
  $key = "$CompanyId"
  if (-not $Cache.ContainsKey($key)) {
    $Cache[$key] = @(Get-HuduArticles -CompanyId $CompanyId | ForEach-Object { Get-HuduArticleCore $_ } | Where-Object { $_ })
  }
  return @($Cache[$key])
}

function Update-CachedHuduCompanyArticle {
  param(
    [Parameter(Mandatory)][int]$CompanyId,
    [Parameter(Mandatory)][hashtable]$Cache,
    [Parameter(Mandatory)]$Article
  )
  $core = Get-HuduArticleCore $Article
  if (-not $core) { return }
  $key = "$CompanyId"
  $existing = @($Cache[$key] | Where-Object { $_.id -ne $core.id })
  $Cache[$key] = @($existing + $core)
}

function Find-HuduNetworkMapArticle {
  param(
    [Parameter(Mandatory)]$Network,
    [Parameter(Mandatory)][string]$ArticleName,
    [Parameter(Mandatory)][object[]]$CompanyArticles,
    [AllowNull()][string[]]$LegacyNames = @()
  )

  $normalizedArticleName = Normalize-ArticleTitle $ArticleName
  $matches = @($CompanyArticles | Where-Object { (Normalize-ArticleTitle $_.name) -eq $normalizedArticleName })

  if (-not $matches) {
    $marker = Get-NetworkMapArticleMarker -Network $Network
    $matches = @($CompanyArticles | Where-Object { "$($_.content)" -like "*$marker*" })
  }

  if (-not $matches) {
    $normalizedLegacyNames = @($LegacyNames | ForEach-Object { Normalize-ArticleTitle $_ } | Where-Object { $_ } | Select-Object -Unique)
    $matches = @($CompanyArticles | Where-Object { $normalizedLegacyNames -contains (Normalize-ArticleTitle $_.name) })
  }

  $matches = @($matches | Sort-Object updated_at -Descending)
  if ($matches.Count -gt 1) {
    Write-Warning "Multiple candidate network map articles found for Network $($Network.id): $($matches.name -join ', '). Updating article id $($matches[0].id)."
  }

  return ($matches | Select-Object -First 1)
}

function Ensure-FadeTextGradient {
  param([System.Text.StringBuilder]$Sb,[double]$Keep=1.2)
  if (-not $script:_fadeGradAdded) {
    $null = $Sb.AppendLine(@"
  <defs>
    <linearGradient id="fadeTextGrad" x1="0" y1="0" x2="1.3" y2="0">
      <stop offset="0"     stop-color="white"/>
      <stop offset="$Keep" stop-color="white"/>
      <stop offset="1.2"     stop-color="black"/>
    </linearGradient>
  </defs>
"@)
    $script:_fadeGradAdded = $true
  }
}

function New-TextLaneMask {
  param(
    [System.Text.StringBuilder]$Sb,
    [int]$LaneX,[int]$LaneY,[int]$LaneW,[int]$LaneH
  )
  if (-not $script:_maskSeq) { $script:_maskSeq = 0 }
  $script:_maskSeq++
  $id = "fadeTextMask-$($script:_maskSeq)"
  $null = $Sb.AppendLine("  <mask id='$id' maskUnits='userSpaceOnUse'><rect x='$LaneX' y='$LaneY' width='$LaneW' height='$LaneH' fill='url(#fadeTextGrad)'/></mask>")
  return $id
}

function New-NetworkMapSvgHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Contexts,
    [bool] $OpenLinksInNewWindow = $true,
    [bool] $ShowDetails = $true,
    [bool] $CurvyEdges = $true,
    [ValidateSet('NetworkCentric','Columnar')]
    [string] $Layout = 'Columnar',
    [int] $MaxAddressesPerNetwork = 0,
    [hashtable] $IconHrefByType = @{},   # type => icon URL (http(s) or data:)
    [hashtable]$ColorByStatus,
    [hashtable]$ColorByType,
    [switch] $ReturnOnly,
    [int] $NodeWidth = 220,
    [int] $NodeHeight = 48,
    [int] $HGap = 360,     # bump this to spread columns
    [int] $VPad = 36,      # bump this to add vertical breathing room
    [int] $BaseX = 80,  
    [string] $OutFile
  )



  # ---------- helpers ----------
  function _H($s){ if($null -eq $s){''} else {("$s" -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&#39;')} }
  function _NodeId($type,$id){ "$type`:$id" }

  function _LinesForNode($n){
    $L = New-Object System.Collections.Generic.List[string]
    $m = $n.meta
    switch ($n.type) {
      'Network' {
        if ($m.Role)                        { [void]$L.Add("Role: $($m.Role)") }
        if ($m.Status)                      { [void]$L.Add("Status: $($m.Status)") }
        if ($m.Type)                        { [void]$L.Add("Type: $($m.Type)") }
        if ($m.'VLAN ID')                   { [void]$L.Add("VLAN ID: $($m.'VLAN ID')") }
        if ($m.'Location ID' -or $m.LocationId) {
          $loc = $m.'Location ID'; if (-not $loc) { $loc = $m.LocationId }
          [void]$L.Add("Location: $loc")
        }
        if ($m.Description)                 { [void]$L.Add("Desc: $($m.Description)") }
      }
      'VLAN' {
        if ($m.VLAN_ID)                     { [void]$L.Add("VLAN ID: $($m.VLAN_ID)") }
        if ($m.Description)                 { [void]$L.Add("Desc: $($m.Description)") }
      }
      'Zone' {
        if ($m.VLAN_Range)                  { [void]$L.Add("Range: $($m.VLAN_Range)") }
        if ($m.Description)                 { [void]$L.Add("Desc: $($m.Description)") }
      }
      'Asset' {
        if ($m.Manufacturer)                { [void]$L.Add("Mfr: $($m.Manufacturer)") }
        if ($m.Model)                       { [void]$L.Add("Model: $($m.Model)") }
        if ($m.Serial)                      { [void]$L.Add("Serial: $($m.Serial)") }
      }
      'Address' {
        if ($m.Status)                      { [void]$L.Add("Status: $($m.Status)") }
        if ($m.Hostname)                    { [void]$L.Add("Host: $($m.Hostname)") }
        if ($m.FQDN)                        { [void]$L.Add("FQDN: $($m.FQDN)") }
        if ($m.Description)                 { [void]$L.Add("Desc: $($m.Description)") }
      }
    }
    return $L | Select-Object -First 4
  }

  # normalize input to array
  $ctxs = @($Contexts)

  # Build a unified list of nodes/links for all contexts (no JS; just precomputed positions)
  $nodes = @{}
  $links = New-Object System.Collections.Generic.List[object]
  function AddNode($id,$label,$type,$url,$fill,[hashtable]$meta){
    if (-not $nodes.ContainsKey($id)){
      $nodes[$id] = [pscustomobject]@{
        id=$id; label=$label; type=$type; url=$url; fill=$fill; meta=$meta
        x=0; y=0; w=$NodeWidth; h=$NodeHeight   # <— was 180 / 40
        extraLines=@()
      }
    }
  }
  function AddLink($src,$dst){
    $links.Add([pscustomobject]@{ source=$src; target=$dst }) | Out-Null
  }

  foreach($ctx in $ctxs){
    $net  = $ctx.Network
    $vlan = $ctx.Vlan
    $zone = $ctx.Zone

    $nid  = _NodeId 'Network' $net.id
    $vid  = if($vlan){ _NodeId 'VLAN' $vlan.id }
    $zid  = if($zone){ _NodeId 'Zone' $zone.id }

    # --- Network (merge extended meta) ---
    $netMeta = @{
      CIDR      = $net.address
      Role      = $ctx.RoleName
      Status    = $ctx.StatusName
      CompanyId = $net.company_id
    }
    if ($ctx.NetworkMeta) { foreach ($k in $ctx.NetworkMeta.Keys) { $netMeta[$k] = $ctx.NetworkMeta[$k] } }
    AddNode $nid $net.name 'Network' $net.url $NetworkColor $netMeta

    # --- VLAN ---
    if($vlan){
      AddNode $vid $vlan.name 'VLAN' $vlan.url $VlanColor @{
        VLAN_ID=$vlan.vlan_id; Description=$vlan.description
      }
      AddLink $vid $nid
    }
    # --- Zone ---
    if($zone){
      AddNode $zid $zone.name 'Zone' $zone.url $ZoneColor @{
        VLAN_Range=$zone.vlan_id_ranges; Description=$zone.description
      }
      if($vid){ AddLink $zid $vid } else { AddLink $zid $nid }
    }

    # --- Assets (merge per-asset extra meta) ---
    foreach($a in $ctx.Assets){
      $aid = _NodeId 'Asset' $a.id
      $astMeta = @{
        CompanyId = $a.company_id
        LayoutId  = $a.asset_layout_id
        AssetId   = $a.id
      }
      $extra = $ctx.AssetMetaById["$($a.id)"]
      if ($extra) { foreach ($k in $extra.Keys) { $astMeta[$k] = $extra[$k] } }

      AddNode $aid $a.name 'Asset' $a.url $AssetColor $astMeta
      AddLink $nid $aid
      $assetNodeById["$($a.id)"] = $aid   # <— remember it for IP linking
    }

    # --- Addresses (merge per-address extra meta) ---
    $assetIds = @($ctx.Assets | ForEach-Object { $_.id }) 
    if($MaxAddressesPerNetwork -gt 0 -and $ctx.Addresses){
    foreach($ip in $ctx.Addresses | Select-Object -First $MaxAddressesPerNetwork){
      $ipid = _NodeId 'Address' ($ip.id ?? $ip.address)
      $ipMeta = @{
        Hostname    = $ip.hostname
        Status      = $ip.status
        Description = $ip.description
        FQDN        = $ip.fqdn
      }
      $akey  = "$($ip.id ?? $ip.address)"
      $extra = $ctx.AddressMetaByKey[$akey]
      if ($extra) { foreach ($k in $extra.Keys) { $ipMeta[$k] = $extra[$k] } }

      AddNode $ipid ($ip.address) 'Address' $ip.url $AddressColor $ipMeta

      $src = $nid
      if ($ip.asset_id -and $assetNodeById.ContainsKey("$($ip.asset_id)")) {
        $src = $assetNodeById["$($ip.asset_id)"]   # link from asset → IP
      }
      AddLink $src $ipid
    }
  }}
  if ($ShowDetails) {
    foreach ($n in $nodes.Values) {
      $baseH = 40; $pad = 8; $lineH = 14
      $lines = _LinesForNode $n

      if (-not ($n.PSObject.Properties.Name -contains 'extraLines')) {
        Add-Member -InputObject $n -NotePropertyName extraLines -NotePropertyValue $lines -Force
      } else {
        $n.extraLines = $lines
      }

      if ($lines -and $lines.Count -gt 0) {
        $n.h = $baseH + $pad + ($lines.Count * $lineH) + $pad
      } else {
        $n.h = $baseH
      }
    }
  }
  # ---------- layout (no JS): compute positions ----------



  $colX = @{
    Zone    = $BaseX + (0 * $HGap)
    VLAN    = $BaseX + (1 * $HGap)
    Network = $BaseX + (2 * $HGap)
    Asset   = $BaseX + (3 * $HGap)
    Address = $BaseX + (4 * $HGap)
  }  
  $vPad = $VPad
  $yCursor = @{ Zone=80; VLAN=80; Network=80; Asset=80; Address=80 }
  if ($Layout -eq 'NetworkCentric') {
    # keep this layout, but still respect NodeWidth/Height and VPad
    $colX = @{ Network=$BaseX + (1 * $HGap); VLAN=$BaseX + (1 * $HGap); Zone=$BaseX + (1 * $HGap); Asset=$BaseX + (2 * $HGap); Address=$BaseX + (3 * $HGap) }
    $yCursor = @{ Network=80; VLAN=80; Zone=80; Asset=80; Address=80 }
  }
  $byType = $nodes.Values | Group-Object type
  foreach($bucket in $byType){
    foreach($n in $bucket.Group){
      $n.x = $colX[$n.type]
      $n.y = $yCursor[$n.type]
      $yCursor[$n.type] = $yCursor[$n.type] + $n.h + $vPad
    }
  }

    # ---------- SVG builder ----------
  $width  = [Math]::Max( ($BaseX + 4*$HGap + $NodeWidth + 200), 1200 )
  $height = [Math]::Max( ($yCursor.Values | Measure-Object -Maximum).Maximum + 120, 800 )


  $sb = New-Object System.Text.StringBuilder

  $null = $sb.AppendLine(@"
<!doctype html>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Network Map</title>
<style>
  :root{
    --bg:$BackgroundColor; --fg:$TextColor; --edge:$EdgeColor;
    --card:rgba(255,255,255,.04); --bd:rgba(255,255,255,.12);
  }
  body{margin:0;background:var(--bg);color:var(--fg);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Inter,Arial}
  .wrap{padding:8px}
  .legend{display:flex;gap:10px;align-items:center;padding:8px 12px}
  .key{display:flex;align-items:center;gap:8px;border:1px solid var(--bd);padding:6px 10px;border-radius:10px;background:var(--card)}
  .sw{width:12px;height:12px;border-radius:50%}
  svg{width:100%;height:auto;display:block;background:linear-gradient(180deg,rgba(255,255,255,.02),rgba(255,255,255,0))}
  .edge{stroke:var(--edge);stroke-width:1.4px;opacity:.85}
  .node rect{rx:10; ry:10; stroke:rgba(0,0,0,.35); stroke-width:.8px}
  .node:hover rect{filter:drop-shadow(0 2px 10px rgba(0,0,0,.45))}
  .label{font-size:13px;dominant-baseline:middle}
  .meta{font-size:11px;opacity:.78}
  a{cursor:pointer}
  .hot:hover{opacity:.95}
</style>
<div class="wrap">
  <div class="legend">
    <div class="key"><span class="sw" style="background:$ZoneColor"></span> Zone</div>
    <div class="key"><span class="sw" style="background:$VlanColor"></span> VLAN</div>
    <div class="key"><span class="sw" style="background:$NetworkColor"></span> Network</div>
    <div class="key"><span class="sw" style="background:$AssetColor"></span> Asset</div>
    <div class="key"><span class="sw" style="background:$AddressColor"></span> Address</div>
  </div>
  <svg viewBox="0 0 $width $height" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
    <defs>
      <marker id="arrow" viewBox="0 -5 10 10" refX="14" refY="0" markerWidth="6" markerHeight="6" orient="auto">
        <path d="M0,-5L10,0L0,5" fill="$EdgeColor"/>
      </marker>
      <!-- Text fade mask: keeps left 85% fully visible, fades last 15% -->
      <linearGradient id="fadeTextGrad" x1="0" y1="0" x2="1" y2="0" gradientUnits="objectBoundingBox">
        <stop offset="0"   stop-color="white"/>
        <stop offset="0.98" stop-color="white"/>
        <stop offset="1"   stop-color="black"/>
      </linearGradient>
      <mask id="fadeTextMask" maskUnits="objectBoundingBox" maskContentUnits="objectBoundingBox">
        <rect x="0" y="0" width="1" height="1" fill="url(#fadeTextGrad)"/>
      </mask>
      <marker id="arrow" viewBox="0 -5 10 10" refX="14" refY="0" markerWidth="6" markerHeight="6" orient="auto">
        <path d="M0,-5L10,0L0,5" fill="$EdgeColor"/>
      </marker>
    </defs>
"@)
  Ensure-FadeTextGradient -Sb $sb -Keep 0.90   # keep left 90%


  # edges (curvy or straight)
$edgeIndex = 0
foreach($e in $links){
  $s = $nodes[$e.source]; $t = $nodes[$e.target]
  if(-not $s -or -not $t){ continue }

  # small padding so arrowheads don't hide under cards
  $x1Pad = 6    # start a bit inside source
  $x2Pad = 10   # end a bit before target

  # prefer left->right; choose sensible ports either way
  $x1 = $s.x + $s.w - $x1Pad
  $y1 = $s.y + ($s.h/2)
  $x2 = $t.x + 0 + $x2Pad   # draw to just left of target edge
  $y2 = $t.y + ($t.h/2)

  if ($CurvyEdges) {
    $edgeIndex++
    $dx = [Math]::Max(40, [Math]::Abs($x2 - $x1) * 0.35)
    $jitter = ((($edgeIndex % 5) - 2) * 3)
    $c1x = $x1 + $dx; $c1y = $y1 + $jitter
    $c2x = $x2 - $dx; $c2y = $y2 - $jitter
    $null = $sb.AppendLine("<path class='edge' d='M $x1 $y1 C $c1x $c1y, $c2x $c2y, $x2 $y2' marker-end='url(#arrow)' fill='none'/>")
  } else {
    $null = $sb.AppendLine("<line class='edge' x1='$x1' y1='$y1' x2='$x2' y2='$y2' marker-end='url(#arrow)'/>")
  }
}

  $targetAttr = if ($OpenLinksInNewWindow) { ' target="_blank" rel="noopener noreferrer"' } else { '' }

  # nodes
  foreach($n in $nodes.Values){
    $x=$n.x; $y=$n.y; $w=$n.w; $h=$n.h
    $fill = $n.fill
    $title = "$($n.type) · $($n.label)"

    # tooltip text
    $tool = @()
    if($n.meta){
      foreach($k in $n.meta.Keys){
        $v = if($n.meta[$k]) { "$($n.meta[$k])" } else { '' }
        if($v){ $tool += "$($k): $v" }
      }
    }
    $tt = _H(($title + "`n" + ($tool -join "`n")).Trim())

    # icon
    $iconHref  = if ($IconHrefByType.ContainsKey($n.type)) { $IconHrefByType[$n.type] } else { $null }
    $hasIcon   = [bool]$iconHref
    $paddingX  = 12
    $iconSize  = 24
    $ix        = $x + $paddingX
    $iy        = $y + [int](($h - [Math]::Min($h-8,$iconSize))/2)

    # text placement
    $labelLeftX   = $x + $paddingX + ($hasIcon ? ($iconSize + 10) : 0)
    $labelCenterX = [int]($x + $w/2)
    $labelYTop    = $y + 18
    $labelYCenter = [int]($y + $h/2)
    # build a mask that covers the card’s text area (from label-left to card right)
    $laneX = $labelLeftX
    $laneY = $y
    $laneW = ($x + $w) - $labelLeftX
    $laneH = $h
    $maskId = New-TextLaneMask -Sb $sb -LaneX $laneX -LaneY $laneY -LaneW $laneW -LaneH $laneH

    $useBlockLayout = [bool]$ShowDetails
    $textAnchor = if ($useBlockLayout -or $hasIcon) { 'start' } else { 'middle' }
    $textX      = if ($useBlockLayout -or $hasIcon) { $labelLeftX } else { $labelCenterX }
    $textY      = if ($useBlockLayout) { $labelYTop } else { $labelYCenter }

    $null = $sb.AppendLine("<g class='node'>")
    if ($n.url) { $null = $sb.AppendLine("<a href='$(_H $n.url)' class='hot'$targetAttr>") }

    $null = $sb.AppendLine("  <text class='label' x='$textX' y='$textY' text-anchor='$textAnchor' mask='url(#$maskId)'>$(_H $n.label)</text>")
    $null = $sb.AppendLine("  <rect x='$x' y='$y' width='$w' height='$h' fill='$fill'/>")

    if ($hasIcon) {
      $href = _H $iconHref
      $null = $sb.AppendLine("  <image href='$href' xlink:href='$href' x='$ix' y='$iy' width='$iconSize' height='$iconSize' preserveAspectRatio='xMidYMid meet' pointer-events='none'/>")
    }



    # title label
    $maskId = "textmask-$($n.id)"
    # left edge where text starts (skip icon & padding)
    $textLaneX = $textX             # already accounts for icon/block layout
    $textLaneY = $y
    $textLaneW = ($x + $w) - $textLaneX
    $textLaneH = $h

    # define a user-space mask that spans the full text lane width
    $null = $sb.AppendLine(@"
      <mask id="$maskId" maskUnits="userSpaceOnUse">
        <rect x="$textLaneX" y="$textLaneY" width="$textLaneW" height="$textLaneH" fill="url(#fadeTextGrad)"/>
      </mask>
"@
    )    
    $null = $sb.AppendLine("  <text class='label' x='$textX' y='$textY' text-anchor='$textAnchor' mask='url(#fadeTextMask)'>$(_H $n.label)</text>")

    # meta under network when details OFF
    if (-not $ShowDetails -and $n.type -eq 'Network' -and $n.meta.CIDR){
      $mx = [int]($x+$w/2); $my = [int]($y+$h+14)
      $null = $sb.AppendLine("  <text class='meta' x='$mx' y='$my' text-anchor='middle' mask='url(#$maskId)'>$(_H $n.meta.CIDR)</text>")
    }

    # details block (inside card)
    if ($ShowDetails) {
      $lines  = @($n.extraLines)
      $startY = $textY + 16
      $lh     = 13
      if ($n.type -eq 'Network' -and $n.meta.CIDR) {
        $null = $sb.AppendLine("  <text class='meta' x='$labelLeftX' y='$startY' text-anchor='start' mask='url(#$maskId)'>$(_H ("CIDR: $($n.meta.CIDR)"))</text>")
        $startY += $lh
      }
      foreach($ln in $lines){
        $null = $sb.AppendLine("  <text class='meta' x='$labelLeftX' y='$startY' text-anchor='start' mask='url(#$maskId)'>$(_H $ln)</text>")
        $startY += $lh
      }
    }
    # status dot (any node with .meta.Status)
    $status = $n.status ?? $n.statusName ?? $n.meta.Status
    if ($status) {
      $defaultTypeColor = if ($ColorByType -and $ColorByType.ContainsKey($status)) { $ColorByType[$status] } else { "#ffff00" }
      $circleColor = Get-StatusColor -Status $($status) -ColorByStatus $ColorByStatus
      # write-host "Status $status for $($n.type) gets color $circleColor"
      $cx = $x + $w - 10; $cy = $y + 10
      $null = $sb.AppendLine("  <circle cx='$cx' cy='$cy' r='5' fill='$circleColor' stroke='rgba(0,0,0,.35)' stroke-width='0.8'/>")
    }    
    if ($n.url) { $null = $sb.AppendLine("</a>") }
    $null = $sb.AppendLine("</g>")
  }

  $null = $sb.AppendLine("</svg></div>")
  $html = $sb.ToString()

  if($OutFile){
    $dir = [IO.Path]::GetDirectoryName($OutFile)
    if($dir -and -not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
    Set-Content -Path $OutFile -Value $html -Encoding UTF8
  }
  if($ReturnOnly -or -not $OutFile){ return $html }
}

function ConvertTo-HtmlText {
  param([AllowNull()][string]$Text)
  if ($null -eq $Text) { return '' }
  return "$Text" -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
}

function ConvertTo-HtmlAttribute {
  param([AllowNull()][string]$Text)
  if ($null -eq $Text) { return '' }
  return "$Text" -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function ConvertTo-MermaidCssColor {
  param(
    [AllowNull()][string]$Color,
    [string]$Fallback = '#d1d5db'
  )
  if ([string]::IsNullOrWhiteSpace($Color)) { return $Fallback }
  $trimmed = $Color.Trim()
  if ($trimmed -match '^#(?<rgb>[0-9a-fA-F]{6})[0-9a-fA-F]{2}$') {
    return "#$($Matches.rgb)"
  }
  return $trimmed
}

function New-MermaidNodeId {
  param(
    [Parameter(Mandatory)][string]$Type,
    [AllowNull()]$Id
  )
  $safe = "$Type`_$Id" -replace '[^A-Za-z0-9_]', '_'
  if ($safe -notmatch '^[A-Za-z_]') { $safe = "n_$safe" }
  return $safe
}

function ConvertTo-MermaidLabelText {
  param([AllowNull()]$Text)
  if ($null -eq $Text) { return '' }
  return "$Text" `
    -replace '&','&amp;' `
    -replace '<','&lt;' `
    -replace '>','&gt;' `
    -replace '"',"'"`
    -replace '\r?\n',' '
}

function New-NetworkMapMermaidArticle {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Contexts,
    [bool] $OpenLinksInNewWindow = $true,
    [bool] $ShowDetails = $true,
    [int] $MaxAddressesPerNetwork = 50,
    [hashtable] $ColorByType = @{},
    [hashtable] $ColorByStatus = @{},
    [bool] $CurvyEdges = $true,
    [string] $Direction = 'LR'
  )

  function _NodeShape {
    param([string]$Id,[string]$Type,[string]$Label)
    switch ($Type) {
      'Zone'    { return "$Id([`"$Label`"])" }
      'VLAN'    { return "$Id[[`"$Label`"]]" }
      'Network' { return "$Id[`"$Label`"]" }
      'Asset'   { return "$Id[`"$Label`"]" }
      'Address' { return "$Id([`"$Label`"])" }
      'Website' { return "$Id[[`"$Label`"]]" }
      default   { return "$Id[`"$Label`"]" }
    }
  }

  function _AddMetaLine {
    param(
      [System.Collections.Generic.List[string]]$Lines,
      [string]$Label,
      [AllowNull()]$Value
    )
    if ($null -ne $Value -and "$Value" -ne '') {
      [void]$Lines.Add("$Label`: $(ConvertTo-MermaidLabelText $Value)")
    }
  }

  function _BuildLabel {
    param(
      [string]$Type,
      [string]$Name,
      [hashtable]$Meta
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $title = if ([string]::IsNullOrWhiteSpace($Name)) { $Type } else { $Name }
    [void]$lines.Add((ConvertTo-MermaidLabelText "$Type`: $title"))

    if ($ShowDetails) {
      switch ($Type) {
        'Network' {
          _AddMetaLine -Lines $lines -Label 'CIDR' -Value $Meta.CIDR
          _AddMetaLine -Lines $lines -Label 'Role' -Value $Meta.Role
          _AddMetaLine -Lines $lines -Label 'Status' -Value $Meta.Status
          _AddMetaLine -Lines $lines -Label 'Type' -Value $Meta.Type
          _AddMetaLine -Lines $lines -Label 'VLAN ID' -Value ($Meta.'VLAN ID' ?? $Meta.VLAN_ID)
        }
        'VLAN' {
          _AddMetaLine -Lines $lines -Label 'VLAN ID' -Value ($Meta.VLAN_ID ?? $Meta.'VLAN ID')
          _AddMetaLine -Lines $lines -Label 'Description' -Value $Meta.Description
        }
        'Zone' {
          _AddMetaLine -Lines $lines -Label 'Range' -Value $Meta.VLAN_Range
          _AddMetaLine -Lines $lines -Label 'Description' -Value $Meta.Description
        }
        'Asset' {
          _AddMetaLine -Lines $lines -Label 'Manufacturer' -Value $Meta.Manufacturer
          _AddMetaLine -Lines $lines -Label 'Model' -Value $Meta.Model
          _AddMetaLine -Lines $lines -Label 'Serial' -Value $Meta.Serial
        }
        'Address' {
          _AddMetaLine -Lines $lines -Label 'Status' -Value $Meta.Status
          _AddMetaLine -Lines $lines -Label 'FQDN' -Value $Meta.FQDN
          _AddMetaLine -Lines $lines -Label 'Description' -Value $Meta.Description
        }
        'Website' {
          _AddMetaLine -Lines $lines -Label 'Host' -Value $Meta.Host
          _AddMetaLine -Lines $lines -Label 'Match' -Value $Meta.Match
          _AddMetaLine -Lines $lines -Label 'Status' -Value $Meta.Status
        }
      }
    } elseif ($Type -eq 'Network' -and $Meta.CIDR) {
      _AddMetaLine -Lines $lines -Label 'CIDR' -Value $Meta.CIDR
    }

    return ($lines | Select-Object -First 6) -join '<br/>'
  }

  $nodes = @{}
  $links = New-Object System.Collections.Generic.List[object]
  $assetNodeById = @{}

  function AddNode {
    param(
      [string]$Id,
      [string]$Label,
      [string]$Type,
      [AllowNull()][string]$Url,
      [hashtable]$Meta
    )
    if (-not $nodes.ContainsKey($Id)) {
      $nodes[$Id] = [pscustomobject]@{
        Id = $Id
        Label = $Label
        Type = $Type
        Url = $Url
        Meta = $Meta
        Status = $Meta.Status
      }
    }
  }

  function AddLink {
    param([string]$Source,[string]$Target,[string]$Label = $null)
    if ($Source -and $Target) {
      [void]$links.Add([pscustomobject]@{ Source = $Source; Target = $Target; Label = $Label })
    }
  }

  foreach ($ctx in @($Contexts)) {
    $net  = $ctx.Network
    $vlan = $ctx.Vlan
    $zone = $ctx.Zone

    $nid = New-MermaidNodeId -Type 'Network' -Id $net.id
    $netName = $net.description ?? $net.name ?? $net.address ?? "Network $($net.id)"
    $netMeta = @{
      CIDR      = $net.address
      Role      = $ctx.RoleName
      Status    = $ctx.StatusName
      CompanyId = $net.company_id
    }
    if ($ctx.NetworkMeta) {
      foreach ($k in $ctx.NetworkMeta.Keys) { $netMeta[$k] = $ctx.NetworkMeta[$k] }
    }
    AddNode -Id $nid -Label $netName -Type 'Network' -Url $net.url -Meta $netMeta

    $vid = $null
    if ($vlan) {
      $vid = New-MermaidNodeId -Type 'VLAN' -Id $vlan.id
      AddNode -Id $vid -Label ($vlan.name ?? "VLAN $($vlan.id)") -Type 'VLAN' -Url $vlan.url -Meta @{
        VLAN_ID = $vlan.vlan_id
        Description = $vlan.description
      }
      AddLink -Source $vid -Target $nid
    }

    if ($zone) {
      $zid = New-MermaidNodeId -Type 'Zone' -Id $zone.id
      AddNode -Id $zid -Label ($zone.name ?? "Zone $($zone.id)") -Type 'Zone' -Url $zone.url -Meta @{
        VLAN_Range = $zone.vlan_id_ranges
        Description = $zone.description
      }
      AddLink -Source $zid -Target ($vid ?? $nid)
    }

    foreach ($asset in @($ctx.Assets)) {
      $aid = New-MermaidNodeId -Type 'Asset' -Id $asset.id
      $assetMeta = @{
        CompanyId = $asset.company_id
        LayoutId  = $asset.asset_layout_id
        AssetId   = $asset.id
      }
      if ($ctx.AssetMetaById -and $ctx.AssetMetaById.ContainsKey("$($asset.id)")) {
        foreach ($k in $ctx.AssetMetaById["$($asset.id)"].Keys) {
          $assetMeta[$k] = $ctx.AssetMetaById["$($asset.id)"][$k]
        }
      }
      AddNode -Id $aid -Label ($asset.name ?? "Asset $($asset.id)") -Type 'Asset' -Url $asset.url -Meta $assetMeta
      AddLink -Source $nid -Target $aid
      $assetNodeById["$($asset.id)"] = $aid
    }

    foreach ($ip in @($ctx.Addresses | Select-Object -First $MaxAddressesPerNetwork)) {
      $ipKey = $ip.id ?? $ip.address
      $ipid = New-MermaidNodeId -Type 'Address' -Id $ipKey
      $ipMeta = @{
        Hostname    = $ip.hostname
        Status      = $ip.status
        Description = $ip.description
        FQDN        = $ip.fqdn
      }
      $addrKey = "$ipKey"
      if ($ctx.AddressMetaByKey -and $ctx.AddressMetaByKey.ContainsKey($addrKey)) {
        foreach ($k in $ctx.AddressMetaByKey[$addrKey].Keys) {
          $ipMeta[$k] = $ctx.AddressMetaByKey[$addrKey][$k]
        }
      }

      AddNode -Id $ipid -Label ($ip.address ?? "Address $ipKey") -Type 'Address' -Url $ip.url -Meta $ipMeta
      $src = $nid
      if ($ip.asset_id -and $assetNodeById.ContainsKey("$($ip.asset_id)")) {
        $src = $assetNodeById["$($ip.asset_id)"]
      }
      AddLink -Source $src -Target $ipid

      if ($ctx.WebsiteMatchesByAddressKey -and $ctx.WebsiteMatchesByAddressKey.ContainsKey($addrKey)) {
        foreach ($match in @($ctx.WebsiteMatchesByAddressKey[$addrKey])) {
          $site = $match.Website
          $wid = New-MermaidNodeId -Type 'Website' -Id $site.id
          $siteMeta = @{
            Host = $match.Host
            Match = $match.MatchReason
            Status = $site.status
            Paused = $site.paused
          }
          AddNode -Id $wid -Label ($site.name ?? "Website $($site.id)") -Type 'Website' -Url $match.Url -Meta $siteMeta
          AddLink -Source $ipid -Target $wid
        }
      }
    }
  }

  $diagram = New-Object System.Text.StringBuilder
  $curve = if ($CurvyEdges) { 'basis' } else { 'linear' }
  [void]$diagram.AppendLine("%%{init: {`"flowchart`": {`"htmlLabels`": true, `"curve`": `"$curve`"}, `"theme`": `"base`", `"themeVariables`": {`"lineColor`": `"$(ConvertTo-MermaidCssColor $EdgeColor)`", `"primaryTextColor`": `"$(ConvertTo-MermaidCssColor $TextColor '#111827')`", `"fontFamily`": `"Inter, Segoe UI, Arial, sans-serif`"}}}%%")
  [void]$diagram.AppendLine("flowchart $Direction")

  $typeLabels = @{
    Zone = 'Zones'
    VLAN = 'VLANs'
    Network = 'Networks'
    Asset = 'Assets'
    Address = 'Addresses'
    Website = 'Websites'
  }
  foreach ($type in @('Zone','VLAN','Network','Asset','Address','Website')) {
    $typedNodes = @($nodes.Values | Where-Object { $_.Type -eq $type } | Sort-Object Label)
    if (-not $typedNodes) { continue }
    [void]$diagram.AppendLine("  subgraph $($type)Column[`"$($typeLabels[$type])`"]")
    [void]$diagram.AppendLine("    direction TB")
    foreach ($node in $typedNodes) {
      $label = _BuildLabel -Type $node.Type -Name $node.Label -Meta $node.Meta
      [void]$diagram.AppendLine("    $(_NodeShape -Id $node.Id -Type $node.Type -Label $label)")
    }
    [void]$diagram.AppendLine("  end")
  }

  foreach ($link in $links) {
    $edge = if ($link.Label) {
      "-->|$(ConvertTo-MermaidLabelText $link.Label)|"
    } else {
      "-->"
    }
    [void]$diagram.AppendLine("  $($link.Source) $edge $($link.Target)")
  }

  foreach ($type in @('Zone','VLAN','Network','Asset','Address','Website')) {
    $fill = if ($ColorByType -and $ColorByType.ContainsKey($type)) { $ColorByType[$type] } else {
      switch ($type) {
        'Zone'    { $ZoneColor }
        'VLAN'    { $VlanColor }
        'Network' { $NetworkColor }
        'Asset'   { $AssetColor }
        'Address' { $AddressColor }
        'Website' { $WebsiteColor }
      }
    }
    $fill = ConvertTo-MermaidCssColor $fill
    [void]$diagram.AppendLine("  classDef $type fill:$fill,stroke:$(ConvertTo-MermaidCssColor $EdgeColor),stroke-width:1px,color:$(ConvertTo-MermaidCssColor $TextColor '#111827');")
    $ids = @($nodes.Values | Where-Object { $_.Type -eq $type } | ForEach-Object { $_.Id })
    if ($ids.Count -gt 0) {
      [void]$diagram.AppendLine("  class $($ids -join ',') $type;")
    }
  }

  foreach ($node in $nodes.Values) {
    $fill = if ($ColorByType -and $ColorByType.ContainsKey($node.Type)) { $ColorByType[$node.Type] } else {
      switch ($node.Type) {
        'Zone'    { $ZoneColor }
        'VLAN'    { $VlanColor }
        'Network' { $NetworkColor }
        'Asset'   { $AssetColor }
        'Address' { $AddressColor }
        'Website' { $WebsiteColor }
      }
    }
    $status = $node.Status
    $stroke = if ($status -and $ColorByStatus -and $ColorByStatus.ContainsKey($status)) {
      $ColorByStatus[$status]
    } else {
      $EdgeColor
    }
    $strokeWidth = if ($status) { '4px' } else { '1px' }
    [void]$diagram.AppendLine("  style $($node.Id) fill:$(ConvertTo-MermaidCssColor $fill),stroke:$(ConvertTo-MermaidCssColor $stroke),stroke-width:$strokeWidth,color:$(ConvertTo-MermaidCssColor $TextColor '#111827')")
  }

  $target = if ($OpenLinksInNewWindow) { '_blank' } else { '_self' }
  foreach ($node in @($nodes.Values | Where-Object { $_.Url })) {
    $tooltip = ConvertTo-MermaidLabelText "$($node.Type): $($node.Label)"
    [void]$diagram.AppendLine("  click $($node.Id) `"$($node.Url)`" `"$tooltip`" $target")
  }

  $mermaid = $diagram.ToString().Trim()
  $typeLegendItems = foreach ($type in @('Zone','VLAN','Network','Asset','Address','Website')) {
    if (-not @($nodes.Values | Where-Object { $_.Type -eq $type })) { continue }
    $fill = if ($ColorByType -and $ColorByType.ContainsKey($type)) { $ColorByType[$type] } else {
      switch ($type) {
        'Zone'    { $ZoneColor }
        'VLAN'    { $VlanColor }
        'Network' { $NetworkColor }
        'Asset'   { $AssetColor }
        'Address' { $AddressColor }
        'Website' { $WebsiteColor }
      }
    }
    "<span style=`"display:inline-flex;align-items:center;gap:6px;margin:0 8px 8px 0;padding:5px 9px;border:1px solid $(ConvertTo-HtmlAttribute (ConvertTo-MermaidCssColor $EdgeColor));border-radius:7px;background:#ffffff;color:$(ConvertTo-HtmlAttribute (ConvertTo-MermaidCssColor $TextColor '#111827'));font-size:12px;`"><span style=`"width:11px;height:11px;border-radius:3px;background:$(ConvertTo-HtmlAttribute (ConvertTo-MermaidCssColor $fill));display:inline-block;`"></span>$type</span>"
  }

  $statusValues = @($nodes.Values | Where-Object { $_.Status } | ForEach-Object { $_.Status } | Sort-Object -Unique)
  $statusLegendItems = foreach ($status in $statusValues) {
    $color = if ($ColorByStatus -and $ColorByStatus.ContainsKey($status)) { $ColorByStatus[$status] } else { $EdgeColor }
    "<span style=`"display:inline-flex;align-items:center;gap:6px;margin:0 8px 8px 0;padding:5px 9px;border:1px solid $(ConvertTo-HtmlAttribute (ConvertTo-MermaidCssColor $EdgeColor));border-radius:7px;background:#ffffff;color:$(ConvertTo-HtmlAttribute (ConvertTo-MermaidCssColor $TextColor '#111827'));font-size:12px;`"><span style=`"width:11px;height:11px;border-radius:999px;background:$(ConvertTo-HtmlAttribute (ConvertTo-MermaidCssColor $color));display:inline-block;`"></span>$(ConvertTo-HtmlText $status)</span>"
  }

  $counts = @($nodes.Values | Group-Object Type | Sort-Object Name | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ' &middot; '
  $generated = Get-Date -Format 'yyyy-MM-dd HH:mm'
  $legend = @"
<div style="border:1px solid rgba(107,114,128,.35);border-radius:8px;padding:12px 14px;margin:0 0 12px 0;background:linear-gradient(180deg,rgba(255,255,255,.88),rgba(255,255,255,.72));color:$(ConvertTo-HtmlAttribute (ConvertTo-MermaidCssColor $TextColor '#111827'));font-family:Inter,Segoe UI,Arial,sans-serif;">
  <div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap;">
    <div>
      <div style="font-size:18px;font-weight:700;line-height:1.2;">Network Map</div>
      <div style="font-size:12px;opacity:.72;margin-top:4px;">$counts &middot; Generated $generated</div>
    </div>
    <div style="font-size:12px;opacity:.72;">Fill = entity type &middot; border = status</div>
  </div>
  <div style="margin-top:12px;">$($typeLegendItems -join '')</div>
  $(if ($statusLegendItems) { "<div style=`"margin-top:2px;`">$($statusLegendItems -join '')</div>" } else { "" })
</div>
"@

  return "$legend`n<pre class=`"mermaid`">$(ConvertTo-HtmlText $mermaid)</pre>"
}


function Test-IpInCidr {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Ip,
    [Parameter(Mandatory)][string]$Cidr  # e.g. "10.0.33.0/24"
  )
  try {
    $parts = $Cidr -split '/'
    $netIp = [System.Net.IPAddress]::Parse($parts[0])
    $prefix = [int]$parts[1]

    $ipAddr = [System.Net.IPAddress]::Parse($Ip)

    $netBytes = $netIp.GetAddressBytes()
    $ipBytes  = $ipAddr.GetAddressBytes()
    if ($netBytes.Length -ne 4 -or $ipBytes.Length -ne 4) { return $false } # simple v4 guard

    $mask = [uint32]0
    if ($prefix -lt 0 -or $prefix -gt 32) { return $false }
    if ($prefix -eq 0) { $mask = 0 } else { $mask = ([uint32]0xFFFFFFFF) -shl (32 - $prefix) }

    function ToUInt32($bytes){
      [Array]::Reverse($bytes)
      return [BitConverter]::ToUInt32($bytes,0)
    }

    $netU = ToUInt32($netBytes)
    $ipU  = ToUInt32($ipBytes)

    return (($netU -band $mask) -eq ($ipU -band $mask))
  } catch { return $false }
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

function Set-HuduInstance {
    param ([string]$HuduBaseURL, [string]$HuduAPIKey)
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
function WriteB64ToFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DataUrl,
        [Parameter(Mandatory)] [string] $OutFile,
        [switch] $Force
    )

    if ([string]::IsNullOrWhiteSpace($DataUrl)) { return $null }

    $dir = [IO.Path]::GetDirectoryName($OutFile)
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

    if ((Test-Path $OutFile) -and -not $Force) {
        return (Resolve-Path $OutFile).Path
    }

    if ($DataUrl -match '^data:(?<mime>[^;]+);base64,(?<data>.+)$') {
        $b64 = $Matches['data']
    } else {
        $b64 = $DataUrl
    }

    $bytes = [Convert]::FromBase64String($b64)
    [IO.File]::WriteAllBytes($OutFile, $bytes) | Out-Null
    return (Resolve-Path $OutFile).Path
}


if ($true -eq $UseAZVault) {
  foreach ($module in @('Az.KeyVault')) {if (Get-Module -ListAvailable -Name $module) { Write-Host "Importing module, $module..."; Import-Module $module } else {Write-Host "Installing and importing module $module..."; Install-Module $module -Force -AllowClobber; Import-Module $module }}
  if (-not (Get-AzContext)) { Connect-AzAccount };
  $HuduAPIKey = "$(Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AzVault_HuduSecretName" -AsPlainText)"
}
if ($HuduBaseURL -eq "https://YourHuduUrl.huducloud.com"){
  Write-Warning "It doesnt look like you set your Hudu base url, unsetting var so you will be asked"
  $HuduBaseURL = $null
}


Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey; Get-HuduVersionCompatible -requiredVersion $(if ($NetworkMapOutputFormat -eq "Mermaid") { "2.43.0" } else { "2.39.2" });
$IconHrefByType = @{}
if ($NetworkMapOutputFormat -eq "SvgHtml") {
  $attributableArticle = Get-HuduArticles -name "Network Maps Icons" | select-object -first 1
  if (-not $attributableArticle) {
      Write-Host "Creating '$iconsArticleName' article to hold network icons..." -ForegroundColor Yellow
      $attributableArticle = New-HuduArticle -name $iconsArticleName -content "This article '$iconsArticleName' holds the reusable SVG icons used by the Network Maps script."; $attributableArticle = $attributableArticle.article ?? $attributableArticle;
  }
  $Alluploads = Get-HuduUploads
  foreach ($item in $AvailableIcons) {
      $fileLeaf  = "$($NetworkArticleNamingPrefix)$($item.Name)$($NetworkArticleNamingSuffix).$($item.Type)"
      $filePath  = Join-Path $WorkDir $fileLeaf
      $basename  = Split-Path -Leaf $filePath

      if (-not $item.UploadId) {
          WriteB64ToFile -DataUrl $item.Icon -OutFile $filePath

          $existing = $AllUploads | Where-Object { $_.name -eq $basename } | Select-Object -First 1

          if (-not $existing) {
              Write-Host "Uploading $($item.type), $($Item.name) from $($filepath) to $(get-hudubaseurl)"
              $upload = New-HuduUpload -FilePath $filePath -uploadable_id $attributableArticle.id -uploadable_type "Article"; $upload = $upload.upload ?? $upload;
              $item.UploadId = $upload.id


          } else {
              $item.UploadId = $existing.id
          }
          write-host "$($Item.type) is at $($item.UploadID)"

          try { Remove-Item -LiteralPath $filePath -ErrorAction SilentlyContinue } catch {}
      }
  }
  $IconByType = @{
    Network = ($AvailableIcons | ? Name -eq 'Switch'   | select -First 1).UploadId
    VLAN    = ($AvailableIcons | ? Name -eq 'Container'| select -First 1).UploadId
    Zone    = ($AvailableIcons | ? Name -eq 'DMZ'      | select -First 1).UploadId
    Asset   = ($AvailableIcons | ? Name -eq 'Endpoint' | select -First 1).UploadId
    Address = $null
  }
  $IconHrefByType = @{
    Network = Get-UploadUrlById $IconByType.Network
    VLAN    = Get-UploadUrlById $IconByType.VLAN
    Zone    = Get-UploadUrlById $IconByType.Zone
    Asset   = Get-UploadUrlById $IconByType.Asset
    Address = Get-UploadUrlById $IconByType.Address
  }
}
$AllLists = Get-HuduLists
$NetworkRoleList = $null; $NetworkStatusList = $null
if ($AllLists -and $AllLists.count -gt 1){
    $NetworkRoleList = $($AllLists | where-object {Test-Equiv -A $_.name -B "$networkRolesListName"} | select-object -first 1)
    $NetworkStatusList = $($AllLists | where-object {Test-Equiv -A $_.name -B "$networkStatusesListName"} | select-object -first 1)
}
if ($null -eq $NetworkRoleList) {
    $NetworkRoleList = $(new-hudulist -name "$networkRolesListName" -items @("LAN","WAN","DMZ","C25 VPN","S2S VPN"))
    $NetworkRoleList = get-hudulists -id $NetworkRoleList.id; $NetworkRoleList = $NetworkRoleList.list ?? $NetworkRoleList;
}
if ($null -eq $NetworkStatusList) { 
  $NetworkStatusList = $(new-hudulist -name "$networkStatusesListName" -items @("Active","Reserved","Deprecated"))
  $NetworkStatusList = get-hudulists -id $NetworkStatusList.id; $NetworkStatusList = $NetworkStatusList.list ?? $NetworkStatusList;
}


Write-Host "Getting available networks..."
$allNetworks = Get-HuduNetworks;
$CompaniesWithNetworks = @()
foreach ($companyid in $($allNetworks.company_id | select-object -unique)){
    $CompaniesWithNetworks+=Get-HuduCompanies -id $companyid
}
Write-host "$($allNetworks.count) Network(s) found from $($companiesWithNetworks.count) Companies."
Write-Host "Getting available vlans..."
try {$allVLans = Get-HuduVLANs} catch {$allVLans = @()}
Write-host "$($allVLans.count) VLANS(s) found from $($($allVLans.company_id | select-object -unique).count) Companies."
Write-Host "Getting available vlan zones..."
try {$allVlanZones = Get-HuduVLANZones} catch {$allVlanZones=@()}
Write-host "$($allVlanZones.count) VLAN Zones(s) found from $($($allVlanZones.company_id | select-object -unique).count) Companies."
  $allIPs = Get-HuduIPAddresses
if ($IncludeWebsiteLinks) {
  Write-Host "Getting available websites..."
  try { $allWebsites = @(Get-HuduWebsites) } catch { $allWebsites = @(); Write-Warning "Unable to load Hudu websites for network map linking: $_" }
  Write-Host "$($allWebsites.count) Website(s) found from $($($allWebsites.company_id | Select-Object -Unique).count) Companies."
} else {
  $allWebsites = @()
}
$assetNodeById = @{}
$ArticlesByCompanyId = @{}


foreach ($network in $allNetworks) {

  $articleName = Get-NetworkArticleTitle `
    -Network $network `
    -Prefix $NetworkArticleNamingPrefix `
    -Suffix $NetworkArticleNamingSuffix `
    -MaxLength $NetworkArticleTitleMaxLength `
    -IncludeId:$NetworkArticleIncludeId
  $legacyArticleNames = Get-LegacyNetworkArticleTitles `
    -Network $network `
    -Prefix $NetworkArticleNamingPrefix `
    -Suffix $NetworkArticleNamingSuffix

  $netsForCompany = $allNetworks | Where-Object {$_.company_id -eq $network.company_id}
  $grouped = Group-IpAddressesByNetwork -IpAddresses $allIPs -Networks $netsForCompany -CompanyId $network.company_id

  $chain = Get-NetworkChain -Network $network -AllNetworks $netsForCompany

  $ctxs = foreach ($n in $chain) {
    $ipsForN = ($grouped | Where-Object { $_.Network -and $_.Network.id -eq $n.id } | Select-Object -ExpandProperty IPs)
    $ctxArgs = @{
      Network                    = $n
      AllVlans                   = $allVlans
      AllVlanZones               = $allVlanZones
      AllIpAddresses             = $ipsForN
      AllWebsites                = $allWebsites
      NetworkRoleList            = $NetworkRoleList
      NetworkStatusList          = $NetworkStatusList
      HuduBaseUrl                = $HuduBaseURL
      IncludeExtendedNetworkMeta = $IncludeExtendedNetworkMeta
      IncludeExtendedAssetMeta   = $IncludeExtendedAssetMeta
      IncludeAddressMeta         = $IncludeAddressMeta
      IncludeWebsiteLinks        = $IncludeWebsiteLinks
      ResolvePublicWebsiteDns    = $ResolvePublicWebsiteDns
      MaxWebsitesPerAddress      = $MaxWebsitesPerAddress
    }
    Get-NetworkContext @ctxArgs
  }

  $html = switch ($NetworkMapOutputFormat) {
    "Mermaid" {
      New-NetworkMapMermaidArticle `
        -Contexts $ctxs `
        -ShowDetails:$ShowDetails `
        -MaxAddressesPerNetwork $MaxAddressesPerNetwork `
        -OpenLinksInNewWindow $OpenLinksInNewWindow `
        -ColorByType $ColorByType `
        -ColorByStatus $ColorByStatus `
        -CurvyEdges:$CurvyEdges
    }
    "SvgHtml" {
      New-NetworkMapSvgHtml `
        -Contexts $ctxs `
        -ShowDetails:$ShowDetails `
        -CurvyEdges:$CurvyEdges `
        -MaxAddressesPerNetwork $MaxAddressesPerNetwork `
        -IconHrefByType $IconHrefByType `
        -OpenLinksInNewWindow $OpenLinksInNewWindow `
        -ColorByStatus $ColorByStatus `
        -ColorByType $ColorByType `
        -ReturnOnly `
        -NodeWidth 240 -NodeHeight 52 -HGap 420 -VPad 48
    }
    default {
      throw "Unsupported NetworkMapOutputFormat '$NetworkMapOutputFormat'. Use 'Mermaid' or 'SvgHtml'."
    }
  }
  $html = Add-NetworkMapArticleMarker -Content $html -Network $network -Format $NetworkMapOutputFormat

  if ($SaveHTML) {
    $htmlPath = Join-Path $workdir (Get-SafeFilename -Name "$articleName.html")
    $html | Out-File $htmlPath -Encoding UTF8
    Write-Host "Wrote $articleName to $htmlPath"
  }

  $companyArticles = Get-CachedHuduCompanyArticles -CompanyId $network.company_id -Cache $ArticlesByCompanyId
  $article = Find-HuduNetworkMapArticle `
    -Network $network `
    -ArticleName $articleName `
    -LegacyNames $legacyArticleNames `
    -CompanyArticles $companyArticles

  $articleRequest = @{
    Name      = $articleName
    Content   = $html
    CompanyId = $network.company_id
  }
  try {
    if ($article) {
      $articleRequest["id"] = $article.id
      $updatedArticle = Set-HuduArticle @articleRequest
      Update-CachedHuduCompanyArticle -CompanyId $network.company_id -Cache $ArticlesByCompanyId -Article $updatedArticle
    } else {
      $newArticle = New-HuduArticle @articleRequest
      Update-CachedHuduCompanyArticle -CompanyId $network.company_id -Cache $ArticlesByCompanyId -Article $newArticle
    }
  } catch {
    Write-Error "$(if ($article) {"Error Updating Article $($article.id) $_"} else {"Error creating article $articleName $_"})"
  }
}
$HuduAPIKey = $null

