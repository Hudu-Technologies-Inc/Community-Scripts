# Central Hudu Audit Report

=========================================================

###### **From: David Knistern**

---------------------

WHAT THIS SCRIPT DOES

---------------------

The script signs in to Microsoft Azure, reads your Hudu API key and Hudu site URL from Azure Key Vault, calls the Hudu API, and builds one Central Knowledge Base article with inventory counts. Each run refreshes that article's HTML content.

The KB article includes:

- Executive Global Summary: fixed list of resource types (companies, assets, layouts, KB articles, passwords, expirations, folders, password folders, procedures, networks, websites, IP addresses, rack storages/items, VLANs, VLAN zones) with Active / Archived / Total where the API supports it.

- Per-company totals and a full Company Resource Breakdown (every company, every listed resource type, zeros included), plus per-company archived sum and grand total rows.

- Asset detail sections (by layout globally, by company, by layout per company).

- Data Retrieval Errors: any API/list failures and notes (for example duplicate KB article titles).

- Article selection: the script looks up the KB article whose title exactly matches $CentralReportArticleName (default "Central Audit Report"). If found, it updates that article. If several articles share the title, it updates the one with the latest updated_at timestamp (tie-break: higher article id) and records a warning in Data Retrieval Errors listing the other ids. If not found, it creates a new article with that title.

- Documentation, that lives in the comment block at the top of: hudu_central_audit_report.ps1

REQUIREMENTS (READ CAREFULLY PLEASE)

-----------------------------

1) PowerShell 7 or newer is required. Do not use Windows PowerShell 5.1 for this script. The script file includes #Requires -Version 7.0 so it will refuse to run on 5.1.

2) Run PowerShell 7 "As Administrator" for the session where you will execute the script. Some environments need this for module installs or policy; use an elevated window for consistency.

3) Entra ID + Azure Key Vault secrets. This script does not embed your Hudu API key or URL in plain text. You sign in with the Azure Az PowerShell modules; the script then calls Get-AzKeyVaultSecret.

Note: "Entra ID" (Azure AD) is only how your admin may sign you into Azure. The script itself reads named secrets from a Key Vault. In Entra you can create secrets under: Azure Portal(Entra ID) → Key vaults → your vault → Objects → Secrets.

4) Your Azure account (or the account you use with Connect-AzAccount) needs at least Get and List on the secrets used for Hudu URL and Hudu API key. The script does not write any Key Vault secrets for the report.

CONFIGURATION YOU MUST EDIT (IN THE SCRIPT)

--------------------------------------------

Open hudu_central_audit_report.ps1 and find the section:

CONFIGURATION - EDIT THESE VALUES

Set these to match your Key Vault and secret names:

$AzVault_Name = "your-key-vault-name"

$AzVault_HuduApiKeySecretName = "AUDITAPI"

(Secret value = your Hudu x-api-key. ~ You can get this in your Hudu instance as a Super-Admin from Admin > API Key.)

$AzVault_HuduBaseDomainSecretName = "AUDITURL"

(Secret value = your Hudu base URL or hostname. Examples that all work after normalization: hudu.com | https://hudu.com | https://hudu.com/ )

$CentralReportArticleName = "Central Audit Report"

(Exact KB article title the script creates or updates. Must match the article name you want in Hudu.)

-ReportDetailLevel

Controls how much data the script includes in the KB article.

You can choose from:

Executive (default)

Includes global summary and data retrieval errors only.

Smallest payload. Use if the KB article fails to render (500 error) due to size.

Full

Includes all tables: global summary, company totals, company resource breakdown, assets by layout, assets by company, assets by layout per company.

Best for complete auditing. May hit Hudu HTML size limits on very large instances (500+ companies).

Compact

Includes global summary, company grand totals, assets by layout (global), and assets by company.

Skips heavy per-company breakdown tables. Good balance of detail and size.

Example usage: -ReportDetailLevel Compact

Full audit example: -ReportDetailLevel Full

CREATING KEY VAULT SECRETS (ENTRA ID STEPS)

------------------------------------------

1) Azure Portal → Key vaults → select your vault.

2) Objects → Secrets → Generate/Import.

3) Name: use the same name as in the script (e.g. AUDITAPI, AUDITURL).

4) Secret value: paste the Hudu API key or URL/domain as appropriate.

5) Save.

DUPLICATE KB ARTICLE TITLES

----------------------------

Avoid duplicate titles. If more than one article uses $CentralReportArticleName, the script updates the most recently updated article (see Article selection above) and logs a warning with the other article ids. Consolidate or rename duplicates in Hudu so only one central report article remains.

OPTIONAL SWITCHES

-----------------

-DryRun

Connects and gathers data but does not POST or PUT the KB article. Prints what it would do.

-VerifyEndpoints

After validating Hudu credentials, calls each API path the report uses and prints row counts. Does not update the KB article. Use this to confirm API access and pagination behavior.

-ReportDetailLevel

Controls how much data the script includes in the KB article. Choose from:

Executive (default):

Smallest payload. Use if the KB article fails to render (500 error) due to size.

Includes global summary and data retrieval errors only.

Full:

Includes all tables: global summary, company totals, company resource breakdown, assets by layout, assets by company, assets by layout per company.

Best for complete auditing. May hit Hudu HTML size limits on very large instances (500+ companies).

Compact:

Includes global summary, company grand totals, assets by layout (global), and assets by company.

Skips heavy per-company breakdown tables. Good balance of detail and size.

Examples -ReportDetailLevel Compact

Full audit: -ReportDetailLevel Full

NORMAL RUN (UPDATE OR CREATE THE ARTICLE)

-----------------------------------------



---

1) Install PowerShell 7+.

2) Open PowerShell 7 as Administrator.

3) Install Az modules if prompted (script may install Az.Accounts and Az.KeyVault for the current user).

4) Edit the CONFIGURATION section in hudu_central_audit_report.ps1.

5) Run:

pwsh -File "C:\path\to\hudu_central_audit_report.ps1"

For a full (largest) report in one run:

pwsh -File "C:\path\to\hudu_central_audit_report.ps1" -ReportDetailLevel Full

(Use your actual path to the script folder.)

6) Sign in to Azure if Connect-AzAccount appears.

7) Wait for "Updated central KB article" or "Created central KB article" action in Hudu.

EDGE CASES AND TROUBLESHOOTING

------------------------------

- Empty or wrong AUDITURL: fix the secret value; the script normalizes scheme and trailing slashes but must end with a resolvable host.

- Empty AUDITAPI: validation fails with a clear error.

- Access denied on Key Vault: grant your identity Secret Get and List on the vault (or on those secrets via RBAC).

- "Endpoint verification" failures: run with -VerifyEndpoints and read which path failed; often, pagination or permissions on a specific resource type.

- If you rename the central article in Hudu but not in the script, the script will create a new article using $CentralReportArticleName.

- If the KB article fails to render (500 error) on very large instances, try -ReportDetailLevel Compact or Executive to reduce payload size. Try increasing your rate limit if you run into this issue. Additional resources may be required if the API rate limit change does not address your issues.

