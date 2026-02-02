# Authentication 
$AzVault_HuduSecretName = "HuduAPIKeySecretName"                 # Name of your secret in AZure Keystore for your Hudu API key
$AzVault_Name           = "MyVaultName"                          # Name of your Azure Keyvault
$UseAZVault = $false

# Hudu Instance
$HuduBaseURL            = "https://YourHuduUrl.huducloud.com"    # URL of your Hudu Instance

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
$ActiveDeviceColor = "#00ea4aff"
$reservedColor = "#ffff00"
$InactiveColor = "#ff0000"
$iconsArticleName = "Network Maps Icons"

$OpenLinksInNewWindow = $false # Open links to assets, networks, vlans, zones, or addresses in new window or same window

$IncludeExtendedNetworkMeta = $true #Show 'Type','LocationId','Description','VLAN ID' in Networks

$IncludeExtendedAssetMeta = $true # Show 'Name','Manufacturer','Model','Serial' Properties in Assets

$IncludeAddressMeta = $true  # Show 'Status','FQDN','Description' properties in Address

$ShowDetails = $true # Add additional relationships and entity details during page generation

$CurvyEdges = $true # Use Bézier curves or straight lines when drawing relationship lines

$SaveHTML=$false # Save a copy of network HTML to local directory

$NetworkArticleNamingPrefix = "Network-"
$NetworkArticleNamingSuffix = "-Article"

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

function Get-NetworkContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Network,
    [AllowNull()][object[]] $AllVlans,
    [AllowNull()][object[]] $AllVlanZones,
    [AllowNull()][object[]] $AllIpAddresses = $null,
    $NetworkRoleList = $null,
    $NetworkStatusList = $null,
    [string] $HuduBaseUrl = $null,
    [bool] $IncludeExtendedNetworkMeta = $true,
    [bool] $IncludeExtendedAssetMeta = $true,
    [bool] $IncludeAddressMeta = $true
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
  }
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


Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible;
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
$AllLists = Get-HuduLists
if ($AllLists -and $AllLists.count -gt 1){
    $NetworkRoleList = $($AllLists | where-object {Test-Equiv -A $_.name -B "$networkRolesListName"} | select-object -first 1)
    $NetworkRoleList = $NetworkRoleList ?? $(Select-ObjectFromList -objects $AllLists -allowNull $false -message "Which list is for your network roles?")
    $NetworkStatusList = $($AllLists | where-object {Test-Equiv -A $_.name -B "$networkStatusesListName"} | select-object -first 1)
    $NetworkStatusList = $NetworkStatusList ?? $(Select-ObjectFromList -objects $($AllLists | Where-Object {-not $_.id -eq $($NetworkStatusList.id ?? 0)}) -allowNull $false -message "Which list is for your network statuses?")
} else {
    $NetworkRoleList = $(new-hudulist -name "$networkRolesListName" -items @("LAN","WAN","DMZ","C25 VPN","S2S VPN"))
    $NetworkStatusList = $(new-hudulist -name "$networkStatusesListName" -items @("Active","Reserved","Deprecated"))
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
$assetNodeById = @{}


foreach ($network in $allNetworks) {

  $articleName = Get-SafeFilename "$NetworkArticleNamingPrefix$($network.description ?? "Network $($network.id)")"

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
      HuduBaseUrl                = $HuduBaseURL
      IncludeExtendedNetworkMeta = $IncludeExtendedNetworkMeta
      IncludeExtendedAssetMeta   = $IncludeExtendedAssetMeta
      IncludeAddressMeta         = $IncludeAddressMeta
    }
    Get-NetworkContext @ctxArgs
  }

  $html = New-NetworkMapSvgHtml `
    -Contexts $ctxs `
    -ShowDetails:$ShowDetails `
    -CurvyEdges:$CurvyEdges `
    -MaxAddressesPerNetwork 50 `
    -IconHrefByType $IconHrefByType `
    -OpenLinksInNewWindow $OpenLinksInNewWindow `
    -ColorByStatus $ColorByStatus `
    -ColorByType $ColorByType `
    -ReturnOnly `
    -NodeWidth 240 -NodeHeight 52 -HGap 420 -VPad 48

  if ($SaveHTML) {
    $htmlPath = Join-Path $workdir (Get-SafeFilename -Name "$articleName.html")
    $html | Out-File $htmlPath -Encoding UTF8
    Write-Host "Wrote $articleName to $htmlPath"
  }

  $article = Get-HuduArticles -companyId $network.company_id -name "$articleName"
  $articleRequest = @{
    Name      = $articleName
    Content   = $html
    CompanyId = $network.company_id
  }
  try {
    if ($article) {
      $articleRequest["id"] = $($article.article.id ?? $article.id)
      Set-HuduArticle @articleRequest
    } else {
      New-HuduArticle @articleRequest
    }
  } catch {
    Write-Error "$(if ($article) {"Error Updating Article $($article.id) $_"} else {"Error creating article $articleName $_"})"
  }
}
$HuduAPIKey = $null

