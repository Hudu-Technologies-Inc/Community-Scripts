# Usual Secrets Setup
$HuduBaseURL = $HuduBaseURL ?? "https://your_domain.hudu.app"
$AzVault_HuduSecretName = "yourhuduapikey"
$AzVault_Name = "yourkeyvault01"

# Enable Http Event Collector
# This is the name of your splunk subdomain where you have a HTTP Event Collector (HEC) Configured
$Splunk_Subdomain="prd-p-e4tyq"

#this is the name of your splunk token in azure vault
$AZVault_SplunkTokenName = "splunk-token"

#this is the name of your data source as named in splunk HEC
$Splunk_sourcename="hudu_logs"

#usually, this is main, archive, history, lastchance, etc.
$Splunk_sourcetype="history"

# Number of days ago to fetch logs for
$DaysAgo = 99

# Turn on/off filtering of log items to specific verb/noun scope
# If action is in excluded noun/verbs list or is not in included noun/verbs list, it will be excluded otherwise
$AllowFiltering=$false


# Objects/Nouns in excluded_objects will be omitted from reporting if AllowFiltering is true
$excluded_objects =@(

)
# Objects/Nouns in excluded_objects will be allowed for reporting. Overrides excluded objects
$observable_objects = @(
    "account",
    "agreement",
    "alert",
    "api",
    "application",
    "article",
    "asset",
    "attachment",
    "product",
    "comment",
    "company",
    "template",
    "type",
    "variable",
    "configuration",
    "sync",
    "dns",
    "domain",
    "duo",
    "job",
    "expiration",
    "export",
    "flag",
    "folder",
    "standard",
    "group",
    "hit",
    "import",
    "record",
    "integration",
    "integrator",
    "invitation",
    "ip",
    "list",
    "log",
    "matcher",
    "name",
    "network",
    "otp",
    "password",
    "photo",
    "pin",
    "portal",
    "procedure",
    "note",
    "recording",
    "relation",
    "restriction",
    "rule",
    "settings",
    "share",
    "sidebar",
    "slug",
    "ssl",
    "tag",
    "time",
    "upload",
    "user",
    "website",
    "whois"
)

#to exclude any actions/verbs, add to excluded_actions. these will be excluded if AllowFiltering is True
$excluded_actions = @(

)
#to include any actions/verbs and override exclusions, you can add them to this list.
$observable_actions = @(
    "signed in",
    "viewed",
    "updated",
    "created",
    "archived",
    "moved",
    "reverted",    
    "deleted",
    "viewed",
    "completed",
    "shared",
    "changed",
    "commented",
    "unarchived"
)

# Initialize Modules
Write-Host "Installing and/or Importing Modules, signing into Hudu with API key from Key Vault"
foreach ($module in @('Az.KeyVault', 'HuduAPI')) {if (Get-Module -ListAvailable -Name $module) 
    { Write-Host "Importing module, $module..."; Import-Module $module } else {Write-Host "Installing and importing module $module..."; Install-Module $module -Force -AllowClobber; Import-Module $module }
}
if (-not (Get-AzContext)) { Write-Host "AZContext not yet set. Connecting AZ Account... $(Connect-AzAccount)" } else {Write-Host "AZContext already set. Skipping Sign-on."};
Write-Host "Authenticating to Hudu instance @$HuduBaseURL..."

# Authenticate to Hudu
$SplunkToken= $SplunkToken ?? "$(Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AZVault_SplunkTokenName" -AsPlainText)"
$SplunkURL = "https://${Splunk_Subdomain}.splunkcloud.com:8088/services/collector"
$HuduAPIKey= $HuduAPIKey ?? "$(Get-AzKeyVaultSecret -VaultName "$AzVault_Name" -Name "$AzVault_HuduSecretName" -AsPlainText)"
New-HuduAPIKey $HuduAPIKey
New-HuduBaseUrl $HuduBaseURL

Write-Host "Getting Splunk Token from azure vault for ${SplunkURL}..."

# Calculate the StartDate and EndDate in ISO 8601 format
$fetch_date=Get-Date
$fetch_date_timestamp=$(Get-Date -UFormat %s)
$StartDate = ($fetch_date).AddDays(-$DaysAgo).ToString("yyyy-MM-ddTHH:mm:ssZ")
$EndDate = ($fetch_date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$localhost_name = $env:COMPUTERNAME
$localhost_ip = [System.Net.Dns]::GetHostAddresses("$($env:COMPUTERNAME)") | Where-Object AddressFamily -eq "InterNetwork" | Select-Object -ExpandProperty IPAddressToString
Write-Host "Fetching Hudu logs from $HuduBaseURL from $DaysAgo days ago until now ($StartDate - $EndDate). Please be patient..."

$activitylogs = Get-HuduActivityLogs -StartDate $StartDate -EndDate $EndDate | `
    ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name FetchedBy -Value $localhost_name -PassThru } | `
    ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name FetchedByIP -Value $localhost_ip -PassThru } | `
    ForEach-Object {
        $user        = $_.user_name ?? (($_.user_initials ?? $_.user_short_name) ?? 'someone')
        $action      = $_.action ?? 'did something'
        $recordType  = $_.record_type ?? 'an object'
        $recordName  = $_.record_name ?? ''
        $ipAddress   = "with source IP $($_.ip_address)" ?? ''
        $company     = if ($_.company_name) { "from company: $($_.company_name)" } else { '' }
        $friendlyDate = if ($_.created_at) {
            (Get-Date $_.created_at).ToString("dddd, dd 'of' MMMM, yyyy")
        } else {
            ''
        }
        $browser = if ($_.agent_string -match "Chrome/([\d\.]+)") {
            "Chrome $($Matches[1])"
        } elseif ($_.agent_string -match "Firefox/([\d\.]+)") {
            "Firefox $($Matches[1])"
        } elseif ($_.agent_string -match "Safari/([\d\.]+)") {
            "Safari $($Matches[1])"
        } else {
            "Unknown"
        }
        $appType     = if ($_.app_type) { "via $($_.app_type)" } else { $browser }        
        $statement = "$user $action $recordType, $recordName, $company $appType $ipAddress" `
                    -replace ',\s*,', '' `
                    -replace ',\s*$', '' `
                    -replace '\s{2,}', ' ' `
                    -replace 'app_main', 'main Hudu app'
                    | ForEach-Object { $_.Trim() }

        $_ | Add-Member -MemberType NoteProperty -Name ActionStatement -Value $statement -PassThru
        $_ | Add-Member -MemberType NoteProperty -Name FriendlyDate -Value $friendlyDate -PassThru
        $_ | Add-Member -MemberType NoteProperty -Name Browser -Value $browser -PassThru
    }

$Headers = @{
    "Authorization" = "Splunk $SplunkToken"
    "Content-Type"  = "application/json"
}
# Loop through each log entry and send it to Splunk
foreach ($Log in $activitylogs) {
    if ($Log -and $Log.PSObject.Properties.Count -gt 0) {

        $action = $Log.action.ToLower()
        $object = if ($Log.record_type) {
            $Log.record_type.ToLower()
        } elseif ($Log.action -and ($Log.action -split ' ').Count -gt 1) {
            ($Log.action -split ' ')[1].ToLower()
        } else {
            'object'
        }
        $skip_entry = $false

        if ($excluded_actions -contains $action) {
            Write-Host "action in excluded list: $action"
            $skip_entry = $AllowFiltering
        } elseif (-not ($observable_actions -contains $action)) {
            Write-Host "action not in observable list: $action"
            $skip_entry = $false
        }

        if ($excluded_objects -contains $object) {
            Write-Host "object in excluded list: $object"
            $skip_entry = $AllowFiltering
        } elseif (-not ($observable_objects -contains $object)) {
            Write-Host "object not in observable list: $object"
            $skip_entry = $false
        }

        if ($true -eq $skip_entry) {
            Write-Host "skipping: $($Log.ActionStatement)"
            continue
        }

        # Build the payload with the event string
        $payload = @{
            host       = $env:COMPUTERNAME
            source     = "$Splunk_sourcename"
            sourcetype = "$Splunk_sourcetype"
            event       = $($Log | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        } | ConvertTo-Json -Depth 10
        Write-Output $payload

        try {
            # Invoke-RestMethod -Uri $SplunkURL -Method Post -Headers $Headers -Body $payload -SkipCertificateCheck
            Invoke-RestMethod -Uri $SplunkURL -Method Post -Headers $Headers -Body $payload -SkipCertificateCheck
            Write-Host "Sent log ID $($Log.id) to Splunk successfully."
        } catch {
            Write-Host "Failed to send log ID $($Log.id): $_"
        }
    }
}
remove-variable HuduAPIKey
remove-variable SplunkToken
