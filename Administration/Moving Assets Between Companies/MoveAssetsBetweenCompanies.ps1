<#
Move Hudu Assets between Companies (interactive)

Prompts:
- Source company (pick from list)
- Destination company (pick from list)
- Criteria:
  1) Asset Name contains <text>
  2) Asset Layout Field contains <text>
  3) Name contains <text> AND Field contains <text>

Notes:
- Uses direct Hudu API calls (works even if the HuduAPI module isn’t installed).
- Requires an API Key with permission to read assets/companies and update assets.
- Creates a CSV log of attempted moves in the current directory.

Tested style: PowerShell 7+ recommended.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-NonEmpty {
  param(
    [Parameter(Mandatory)][string]$Prompt,
    [switch]$AsSecure
  )
  while ($true) {
    if ($AsSecure) {
      $v = Read-Host -Prompt $Prompt -AsSecureString
      if ($null -ne $v -and ($v.Length -gt 0)) { return $v }
    } else {
      $v = Read-Host -Prompt $Prompt
      if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
    }
    Write-Host "Value required." -ForegroundColor Yellow
  }
}

function ConvertFrom-SecureStringToPlainText {
  param([Parameter(Mandatory)][securestring]$Secure)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Select-FromList {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][object[]]$Items,
    [Parameter(Mandatory)][scriptblock]$Display,
    [switch]$AlternatingColors,
    [ConsoleColor]$EvenColor = [ConsoleColor]::Cyan,   # blue-ish
    [ConsoleColor]$OddColor  = [ConsoleColor]::Green   # native green
  )

  if ($Items.Count -eq 0) { throw "No items to select for: $Title" }

  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan

  for ($i = 0; $i -lt $Items.Count; $i++) {
    $label = & $Display $Items[$i]
    $line  = ("[{0}] {1}" -f ($i + 1), $label)

    if ($AlternatingColors) {
      $c = if (($i % 2) -eq 0) { $EvenColor } else { $OddColor }
      Write-Host $line -ForegroundColor $c
    } else {
      Write-Host $line
    }
  }

  while ($true) {
    $raw = Read-Host -Prompt "Enter selection (1-$($Items.Count))"
    $n = 0
    if ([int]::TryParse($raw, [ref]$n)) {
      if ($n -ge 1 -and $n -le $Items.Count) { return $Items[$n - 1] }
    }
    Write-Host "Invalid selection." -ForegroundColor Yellow
  }
}



function Select-CompanyByPrefix {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][object[]]$Companies,
    [int]$MinChars = 2
  )

  if ($Companies.Count -eq 0) { throw "No companies returned by API." }

  while ($true) {
    $prefix = Read-Host -Prompt "Type the first $MinChars+ letters of the company name"
    $prefix = ($prefix ?? "").Trim()

    # 2 OR MORE chars (enforced by MinChars)
    if ($prefix.Length -lt $MinChars) {
      Write-Host "Please enter at least $MinChars characters." -ForegroundColor Yellow
      continue
    }

    $filtered = $Companies | Where-Object {
      ($_.name -as [string]) -like "$prefix*"
    } | Sort-Object name

    # Fallback: if no "starts with" matches, try "contains"
    if (-not $filtered -or $filtered.Count -eq 0) {
      $filtered = $Companies | Where-Object {
        ($_.name -as [string]) -like "*$prefix*"
      } | Sort-Object name
    }

    if (-not $filtered -or $filtered.Count -eq 0) {
      Write-Host "No matches for '$prefix'. Try again." -ForegroundColor Yellow
      continue
    }

    # If too many matches, force more typing so the list stays usable
    if ($filtered.Count -gt 40) {
      Write-Host ("{0} matches. Type more characters to narrow it down." -f $filtered.Count) -ForegroundColor Yellow
      continue
    }

    return Select-FromList -Title $Title -Items $filtered -Display {
      param($c) ("{0} (ID: {1})" -f $c.name, $c.id)
    }
  }
}



function Invoke-HuduApi {
  param(
    [Parameter(Mandatory)][string]$BaseUrl,
    [Parameter(Mandatory)][string]$ApiKey,
    [Parameter(Mandatory)][ValidateSet("GET","POST","PATCH","PUT","DELETE")][string]$Method,
    [Parameter(Mandatory)][string]$Path,
    [hashtable]$Query,
    [object]$Body
  )

  $BaseUrl = $BaseUrl.TrimEnd("/")
  $uri = "$BaseUrl$Path"

  if ($Query) {
    $qs = ($Query.GetEnumerator() | ForEach-Object {
      "{0}={1}" -f [Uri]::EscapeDataString($_.Key), [Uri]::EscapeDataString([string]$_.Value)
    }) -join "&"
    $uri = "$uri`?$qs"
  }

  $headers = @{
    "X-Api-Key"     = $ApiKey
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
  }

  $params = @{
    Method  = $Method
    Uri     = $uri
    Headers = $headers
  }
  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 20)
  }

  Invoke-RestMethod @params
}

function Get-HuduCompanies {
  param(
    [Parameter(Mandatory)][string]$BaseUrl,
    [Parameter(Mandatory)][string]$ApiKey,
    [string]$Search = $null
  )

  # Try server-side search first
  if (-not [string]::IsNullOrWhiteSpace($Search)) {
    try {
      $resp = Invoke-HuduApi -BaseUrl $BaseUrl -ApiKey $ApiKey -Method "GET" -Path "/api/v1/companies" -Query @{
        search   = $Search
        per_page = 100
        page     = 1
      }

      $items = @()
        $prop = $resp.PSObject.Properties["companies"]
            if ($null -ne $prop -and $null -ne $prop.Value) { $items = $prop.Value }

      if ($items -and $items.Count -gt 0) { return ,$items }
    } catch {
      # ignore and fall back
    }
  }

  # Fallback: page through ALL companies
  $all = New-Object System.Collections.Generic.List[object]
  $page = 1
  $perPage = 100

  while ($true) {
    $resp = Invoke-HuduApi -BaseUrl $BaseUrl -ApiKey $ApiKey -Method "GET" -Path "/api/v1/companies" -Query @{
      per_page = $perPage
      page     = $page
    }

    $items = @()
    $items = @()
if ($null -ne $resp) {
  $prop = $resp.PSObject.Properties["companies"]
  if ($null -ne $prop -and $null -ne $prop.Value) {
    $items = $prop.Value
  } elseif ($resp -is [System.Collections.IEnumerable] -and $resp -isnot [string]) {
    $items = $resp
  }
}
 elseif ($resp -is [System.Collections.IEnumerable] -and $resp -isnot [string]) {
      $items = $resp
    }

    if (-not $items) { $items = @() }
    foreach ($it in $items) { [void]$all.Add($it) }

    if ($items.Count -lt $perPage) { break }
    $page++
    if ($page -gt 5000) { throw "Safety stop: too many pages paging companies." }
  }

  return ,$all.ToArray()
}

function Select-CompanyByPrefix {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$BaseUrl,
    [Parameter(Mandatory)][string]$ApiKey,
    [object[]]$ExcludeCompanies = @(),
    [int]$MinChars = 2
  )

  $excludeIds = @{}
  foreach ($c in $ExcludeCompanies) { if ($c -and $c.id) { $excludeIds["$($c.id)"] = $true } }

  while ($true) {
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan

    $prefix = Read-Host -Prompt "Type $MinChars+ letters of the company name"
    $prefix = ($prefix ?? "").Trim()
    if ($prefix.Length -lt $MinChars) {
      Write-Host "Please enter at least $MinChars characters." -ForegroundColor Yellow
      continue
    }

    # Server-side search if available; otherwise falls back to full paging.
    $companies = Get-HuduCompanies -BaseUrl $BaseUrl -ApiKey $ApiKey -Search $prefix

    $candidates = $companies | Where-Object { -not $excludeIds.ContainsKey("$($_.id)") }

    $filtered = $candidates | Where-Object { ($_.name -as [string]) -like "$prefix*" } | Sort-Object name
    if (-not $filtered -or $filtered.Count -eq 0) {
      $filtered = $candidates | Where-Object { ($_.name -as [string]) -like "*$prefix*" } | Sort-Object name
    }

    if (-not $filtered -or $filtered.Count -eq 0) {
      Write-Host "No matches for '$prefix'. Try more characters." -ForegroundColor Yellow
      continue
    }

    if ($filtered.Count -gt 40) {
      Write-Host ("{0} matches. Type more characters to narrow it down." -f $filtered.Count) -ForegroundColor Yellow
      continue
    }

    return Select-FromList -Title "Pick one" -Items $filtered -Display {
      param($c) ("{0} (ID: {1})" -f $c.name, $c.id)
    }
  }
}

function Get-HuduPaged {
  param(
    [Parameter(Mandatory)][string]$BaseUrl,
    [Parameter(Mandatory)][string]$ApiKey,
    [Parameter(Mandatory)][string]$Path,
    [hashtable]$Query = @{},
    [int]$PerPage = 25,
    [string[]]$WrapperKeys = @("companies","assets","asset_layouts")
  )

  $all  = New-Object System.Collections.Generic.List[object]
  $page = 1

  while ($true) {
    $q = @{} + $Query
    $q["page"]     = $page
    $q["per_page"] = $PerPage

    $resp = Invoke-HuduApi -BaseUrl $BaseUrl -ApiKey $ApiKey -Method "GET" -Path $Path -Query $q

    # StrictMode-safe wrapper detection
    $items = $null
    if ($null -ne $resp) {
      foreach ($k in $WrapperKeys) {
        $p = $resp.PSObject.Properties[$k]
        if ($null -ne $p) { $items = $p.Value; break }
      }
    }
    if ($null -eq $items) { $items = $resp }

    if ($null -eq $items) { $items = @() }
    if ($items -isnot [System.Collections.IEnumerable] -or $items -is [string]) { $items = @($items) }

    # Key fix: keep paging until the API returns an empty page
    if ($items.Count -eq 0) { break }

    foreach ($it in $items) { [void]$all.Add($it) }

    $page++
    if ($page -gt 5000) { throw "Safety stop: too many pages paging $Path" }
  }

  return ,$all.ToArray()
}




function Normalize-FieldValueToString {
  param([object]$Value)

  if ($null -eq $Value) { return "" }
  if ($Value -is [string]) { return $Value }
  if ($Value -is [ValueType]) { return [string]$Value }

  # Arrays / lists
  if ($Value -is [System.Collections.IEnumerable]) {
    $parts = @()
    foreach ($v in $Value) {
      if ($null -ne $v) { $parts += [string]$v }
    }
    return ($parts -join ", ")
  }

  return ($Value | ConvertTo-Json -Depth 10 -Compress)
}

function Get-AssetFieldString {
  param(
    [Parameter(Mandatory)]$Asset,
    [Parameter(Mandatory)][string]$FieldName
  )

  # StrictMode-safe property getter (reuse if you already have one; don’t duplicate)
  if (-not (Get-Command Get-PropValue -ErrorAction SilentlyContinue)) {
    function Get-PropValue {
      param(
        [Parameter(Mandatory)]$Obj,
        [Parameter(Mandatory)][string[]]$Names
      )
      foreach ($n in $Names) {
        $p = $Obj.PSObject.Properties[$n]
        if ($null -ne $p) { return $p.Value }
      }
      return $null
    }
  }

  $fields = Get-PropValue -Obj $Asset -Names @("fields")
  if ($null -eq $fields) { return "" }

  # Normalize to array
  if ($fields -isnot [System.Collections.IEnumerable] -or $fields -is [string]) {
    $fields = @($fields)
  }

  $target = $FieldName.Trim().ToLowerInvariant()

  foreach ($f in $fields) {
    $n = Get-PropValue -Obj $f -Names @("name","label","field_name","title")
    if ($null -eq $n) { continue }

    $nNorm = ([string]$n).Trim().ToLowerInvariant()
    if ($nNorm -ne $target) { continue }

    $val = Get-PropValue -Obj $f -Names @("value","field_value","raw_value")
    return (Normalize-FieldValueToString -Value $val)
  }

  return ""
}


# -----------------------------
# Start
# -----------------------------

$baseUrl = Read-NonEmpty -Prompt "Hudu Base URL (e.g., https://yourhudu.domain)"
$apiKeySecure = Read-NonEmpty -Prompt "Hudu API Key" -AsSecure
$apiKey = ConvertFrom-SecureStringToPlainText $apiKeySecure


$sourceCompany = Select-CompanyByPrefix -Title "Select company to MOVE FROM" -BaseUrl $baseUrl -ApiKey $apiKey -MinChars 2
$destCompany   = Select-CompanyByPrefix -Title "Select company to MOVE TO"   -BaseUrl $baseUrl -ApiKey $apiKey -ExcludeCompanies @($sourceCompany) -MinChars 2



Write-Host ""
Write-Host "Criteria options:" -ForegroundColor Cyan
Write-Host "[1] Asset Name contains text"
Write-Host "[2] Specific Asset Layout Field contains text"
Write-Host "[3] Name contains AND Field contains"

$mode = $null
while ($true) {
  $raw = Read-Host -Prompt "Choose criteria (1-3)"
  if ($raw -in @("1","2","3")) { $mode = [int]$raw; break }
  Write-Host "Invalid choice." -ForegroundColor Yellow
}

$nameContains = $null
$fieldContains = $null
$selectedLayout = $null
$selectedFieldName = $null

if ($mode -in @(1,3)) {
  $nameContains = Read-NonEmpty -Prompt "Enter text that the Asset Name must contain"
}

if ($mode -in @(2,3)) {
  Write-Host "`nLoading asset layouts..." -ForegroundColor Gray
  $layouts = Get-HuduPaged -BaseUrl $baseUrl -ApiKey $apiKey -Path "/api/v1/asset_layouts"

  $selectedLayout = Select-FromList `
  -Title "Select the Asset Layout (used to list fields and filter assets)" `
  -Items $layouts `
  -AlternatingColors `
  -Display { param($l) ("{0} (ID: {1})" -f $l.name, $l.id) }


  # Get full layout to ensure we have fields
  $layoutDetail = Invoke-HuduApi -BaseUrl $baseUrl -ApiKey $apiKey -Method "GET" -Path ("/api/v1/asset_layouts/{0}" -f $selectedLayout.id)
  $layoutObj =
    if ($layoutDetail.asset_layout) { $layoutDetail.asset_layout }
    else { $layoutDetail }

  $layoutFields = $layoutObj.fields
  if ($null -eq $layoutFields -or $layoutFields.Count -eq 0) {
    throw "No fields found for layout '$($selectedLayout.name)'."
  }

  # Helper: StrictMode-safe property getter
function Get-PropValue {
  param(
    [Parameter(Mandatory)]$Obj,
    [Parameter(Mandatory)][string[]]$Names
  )
  foreach ($n in $Names) {
    $p = $Obj.PSObject.Properties[$n]
    if ($null -ne $p -and $null -ne $p.Value -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) {
      return $p.Value
    }
  }
  return $null
}

$selectedField = Select-FromList -Title "Select field to evaluate" -Items $layoutFields -AlternatingColors -Display {
  param($f)

  $fname = Get-PropValue -Obj $f -Names @("name","label","field_name","title")
  if (-not $fname) { $fname = "<unnamed>" }

  $ftype = Get-PropValue -Obj $f -Names @("field_type","type")
  if (-not $ftype) { $ftype = "" }

  if ($ftype) {
    ("{0} (Type: {1})" -f $fname, $ftype)
  } else {
    ("{0}" -f $fname)
  }
}

$selectedFieldName = Get-PropValue -Obj $selectedField -Names @("name","label","field_name","title")
if (-not $selectedFieldName) { throw "Selected field has no usable name/label." }
$selectedFieldName = [string]$selectedFieldName


  $fieldContains = Read-NonEmpty -Prompt "Enter text that the selected field must contain"
}

Write-Host "`nLoading assets from '$($sourceCompany.name)'..." -ForegroundColor Gray
$assets = Get-HuduPaged -BaseUrl $baseUrl -ApiKey $apiKey -Path "/api/v1/assets" -Query @{ company_id = $sourceCompany.id }

# If using a field criterion, limit to that layout (keeps evaluation consistent)
function Get-PropValue {
  param(
    [Parameter(Mandatory)]$Obj,
    [Parameter(Mandatory)][string[]]$Names
  )
  foreach ($n in $Names) {
    $p = $Obj.PSObject.Properties[$n]
    if ($null -ne $p) { return $p.Value }
  }
  return $null
}

if ($mode -in @(2,3) -and $null -ne $selectedLayout) {
  $selectedLayoutId = [string]$selectedLayout.id

  $assets = $assets | Where-Object {
    $alid = Get-PropValue -Obj $_ -Names @("asset_layout_id")
    if ($null -ne $alid -and [string]$alid -eq $selectedLayoutId) { return $true }

    $alObj = Get-PropValue -Obj $_ -Names @("asset_layout")
    if ($null -ne $alObj) {
      $nestedId = Get-PropValue -Obj $alObj -Names @("id")
      if ($null -ne $nestedId -and [string]$nestedId -eq $selectedLayoutId) { return $true }
    }

    return $false
  }
}


Write-Host ("Total assets loaded: {0}" -f $assets.Count) -ForegroundColor Gray

$matches = foreach ($a in $assets) {
  $ok = $true

  if ($mode -in @(1,3)) {
    $n = [string]$a.name
    if ($n -notlike ("*{0}*" -f $nameContains)) { $ok = $false }
  }

  if ($ok -and $mode -in @(2,3)) {
    $valString = Get-AssetFieldString -Asset $a -FieldName $selectedFieldName
    if ($valString -notlike ("*{0}*" -f $fieldContains)) { $ok = $false }
  }

  if ($ok) { $a }
}

Write-Host ""
Write-Host ("Matched assets to move: {0}" -f ($matches.Count)) -ForegroundColor Green

if ($matches.Count -gt 0) {
  Write-Host "`nPreview (up to 20):" -ForegroundColor Cyan
  $matches | Select-Object -First 20 | ForEach-Object {
    $layoutId = if ($_.asset_layout_id) { $_.asset_layout_id } elseif ($_.asset_layout?.id) { $_.asset_layout.id } else { "" }
    Write-Host ("- {0} (ID: {1}, LayoutID: {2})" -f $_.name, $_.id, $layoutId)
  }
}

$confirm = Read-Host -Prompt ("`nType MOVE to confirm moving {0} assets from '{1}' to '{2}'" -f $matches.Count, $sourceCompany.name, $destCompany.name)
if ($confirm -ne "MOVE") {
  Write-Host "Cancelled." -ForegroundColor Yellow
  return
}

$log = New-Object System.Collections.Generic.List[object]
$okCount = 0
$failCount = 0

foreach ($a in $matches) {
  $id = $a.id
  try {
    # PATCH asset with new company_id
    $null = Invoke-HuduApi -BaseUrl $baseUrl -ApiKey $apiKey -Method "PATCH" -Path ("/api/v1/assets/{0}" -f $id) -Body @{
      company_id = $destCompany.id
    }

    $okCount++
    [void]$log.Add([pscustomobject]@{
      asset_id    = $id
      asset_name  = $a.name
      from_company= $sourceCompany.name
      to_company  = $destCompany.name
      status      = "OK"
      message     = ""
    })
  }
  catch {
    $failCount++
    [void]$log.Add([pscustomobject]@{
      asset_id    = $id
      asset_name  = $a.name
      from_company= $sourceCompany.name
      to_company  = $destCompany.name
      status      = "FAILED"
      message     = $_.Exception.Message
    })
  }

  # small throttle (adjust/remove if desired)
  Start-Sleep -Milliseconds 150
}

Write-Host ""
Write-Host ("Done. OK: {0} | FAILED: {1}" -f $okCount, $failCount) -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path -Path (Get-Location) -ChildPath ("hudu-asset-move-log-{0}.csv" -f $timestamp)
$log | Export-Csv -NoTypeInformation -Path $logPath -Encoding UTF8

Write-Host ("Log written: {0}" -f $logPath) -ForegroundColor Gray
