$preferredDateFormat = 'MM/dd/yyyy hh:mm:ss'
$flagDate = '26 Jan 2026 15:56'

$HuduAPIKey = $HuduAPIKey ?? $(read-host "Please Enter Hudu API Key")
$HuduBaseURL = $HuduBaseURL ?? $(read-host "Please Enter Hudu Base URL (e.g. https://myinstance.huducloud.com)")

function ConvertTo-DateTimeOffset {
    [CmdletBinding()]
        param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputString
    )

    $s = $InputString.Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }

    $formats = @(
        # --- International day-first ---
        'dd/MM/yyyy HH:mm:ss',
        'dd/MM/yyyy H:mm:ss',
        'dd/MM/yyyy H:mm:ss',
        'dd/MM/yyyy HH:mm',
        'dd/MM/yyyy H:mm',
        'dd/MM/yyyy hh:mm:ss tt',
        'dd/MM/yyyy h:mm:ss tt',
        'dd/MM/yyyy hh:mm tt',
        'dd/MM/yyyy h:mm tt',

        # --- US month-first ---
        'MM/dd/yyyy HH:mm:ss',
        'MM/dd/yyyy H:mm:ss',
        'MM/dd/yyyy HH:mm',
        'MM/dd/yyyy H:mm',
        'MM/dd/yyyy hh:mm:ss tt',
        'MM/dd/yyyy h:mm:ss tt',
        'MM/dd/yyyy hh:mm tt',
        'MM/dd/yyyy h:mm tt',

        # --- Hyphen day-first
        'dd-MM-yyyy HH:mm:ss',
        'd-M-yyyy HH:mm:ss',
        'dd-MM-yyyy HH:mm',
        'd-M-yyyy HH:mm',

        # --- ISO-ish
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd H:mm:ss',
        'yyyy-MM-dd HH:mm',
        'yyyy-MM-dd H:mm',
        'yyyy-MM-ddTHH:mm:ss',
        'yyyy-MM-ddTHH:mm:ssK',
        'yyyy-MM-ddTHH:mm:ss.fff',
        'yyyy-MM-ddTHH:mm:ss.fffK',


        # --- RFC-ish / log formats you’ll see a lot ---
        'ddd, dd MMM yyyy HH:mm:ss K', # e.g. Tue, 26 Jan 2026 15:56:51 -0700
        'ddd, dd MMM yyyy HH:mm:ss GMT', # e.g. Tue, 26 Jan 2026 15:56:51 GMT
        'dd MMM yyyy HH:mm:ss', # e.g. 26 Jan 2026 15:56:51
        'dd MMM yyyy HH:mm', # e.g. 26 Jan 2026 15:56

        # --- Date-only (assume midnight) ---
        'MM/dd/yyyy',
        'dd/MM/yyyy',
        'dd.MM.yyyy',
        'yyyy-MM-dd',

        # --- Roundtrip ---
        'o'
    )

    $dto = [datetimeoffset]::MinValue


    foreach ($f in $formats) {
        if ([datetimeoffset]::TryParseExact(
            $s, $f,
            [Globalization.CultureInfo]::InvariantCulture,
            ([Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [Globalization.DateTimeStyles]::AssumeLocal),
            [ref]$dto
        )) { return $dto }
    }


    # ISO fallback
    if ([datetimeoffset]::TryParse(
        $s,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$dto
    )) { return $dto }


    # Last resort: whatever the current culture thinks (avoid if you can)
    if ([datetimeoffset]::TryParse($s, [ref]$dto)) { return $dto }

    throw "Unrecognized datetime string: '$InputString'"
}


function Compare-DateStrings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$a,[Parameter(Mandatory)][string]$b)

    $da = ConvertTo-DateTimeOffset $a
    $db = ConvertTo-DateTimeOffset $b

    if ($null -eq $da -or $null -eq $db) { return $false }
    return $da -lt $db
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

function Get-HuduModule {
    param ([string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",[bool]$use_hudu_fork = $true)
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

function Select-OrCreateFlagType {
    param (
        [string]$description
    )
    $flagTypes = Get-HuduFlagTypes

    if ($null -ne $flagtypes -and $flagtypes.count -gt 0){
        $selectedFlagType = Select-ObjectFromList -objects $flagtypes -message "Select a flag type to apply for the purpose of '$description'" -inspectObjects $true -allowNull $true;
    } else {
        $selectedFlagType = $null
    }

    while ($null -eq $selectedFlagType) {
        $flagName = $null; $flagName = Read-Host "Enter a name for the new flag type to be applied to assets for the purpose of '$description'";
        $flagColor = $null; $flagColor = Select-ObjectFromList -message "Select the color to use for a new flag type. First we create flag types, then we attribute flag types to the objects that you'd like. Select a Color or Enter '0' or 1-'None' to skip creating FlagTypes if you already created some in Hudu." -objects @('None', 'red', 'crimson', 'scarlet', 'rot', 'karminrot', 'scharlachrot', 'rouge', 'cramoisi', 'écarlate', 'rosso', 'cremisi', 'scarlatto', 'rojo', 'carmesí', 'escarlata', 'blue', 'navy', 'blau', 'marineblau', 'bleu', 'bleu marine', 'blu', 'blu navy', 'azul', 'azul marino', 'green', 'lime', 'grün', 'limettengrün', 'vert', 'vert citron', 'verde', 'verde lime', 'verde lima', 'yellow', 'gold', 'gelb', 'jaune', 'or', 'giallo', 'oro', 'amarillo', 'purple', 'violet', 'lila', 'violett', 'pourpre', 'viola', 'porpora', 'púrpura', 'violeta', 'orange', 'arancione', 'naranja', 'light pink', 'pink', 'baby pink', 'hellrosa', 'rosa', 'rose clair', 'rose', 'rosa chiaro', 'rosa claro', 'light blue', 'baby blue', 'sky blue', 'hellblau', 'babyblau', 'himmelblau', 'bleu clair', 'bleu ciel', 'azzurro', 'blu chiaro', 'azul claro', 'celeste', 'light green', 'mint', 'hellgrün', 'mintgrün', 'vert clair', 'menthe', 'verde chiaro', 'menta', 'verde claro', 'light purple', 'lavender', 'helllila', 'lavendel', 'violet clair', 'lavande', 'viola chiaro', 'lavanda', 'morado claro', 'light orange', 'peach', 'hellorange', 'pfirsich', 'orange clair', 'pêche', 'arancione chiaro', 'pesca', 'naranja claro', 'melocotón', 'light yellow', 'cream', 'hellgelb', 'creme', 'jaune clair', 'crème', 'giallo chiaro', 'crema', 'amarillo claro', 'white', 'weiß', 'blanc', 'bianco', 'blanco', 'grey', 'gray', 'silver', 'grau', 'silber', 'gris', 'argent', 'grigio', 'argento', 'plateado', 'lightpink', 'lightblue', 'lightgreen', 'lightpurple', 'lightorange', 'lightyellow') -allowNull $false;
        $selectedFlagType = New-HuduFlagType -name $flagName -color $flagColor
        write-host "Created new flag type '$($selectedFlagType.name)' with id $($selectedFlagType.id)"
    }    
    return $selectedFlagType
}

Get-HuduModule; Set-HuduInstance -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey;
if (-not (Get-Command -Name Get-HuduFlagTypes -ErrorAction SilentlyContinue)) { Write-Host "Huduapi module not loaded with a version that supports flags." -ForegroundColor Yellow; exit 1;}
if (-not ( [version]($(Get-HuduAppInfo).version) -ge [version]("2.40.0"))){ Write-Host "Hudu instance does not support flags. Please upgrade to at least version 2.40.0" -ForegroundColor Yellow; exit 1;}
write-host "HuduAPI Module and Hudu Instance verified to support Flags and Flag Types." -ForegroundColor Green