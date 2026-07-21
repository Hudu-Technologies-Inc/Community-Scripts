# ConnectWise PSA Magic Dash Connector

This community script creates Hudu Magic Dash tiles from ConnectWise Manage service tickets. V1 focuses on open tickets, while the script structure keeps the Hudu client, PSA provider, company mapping, and Magic Dash rendering separate so other PSAs can be added later.

## What V1 Does

- Connects to Hudu through direct REST API calls.
- Connects to ConnectWise Manage through direct REST API calls.
- Matches Hudu companies to ConnectWise companies.
- Pulls ConnectWise service tickets per matched company.
- Creates or updates one Magic Dash tile per company titled `ConnectWise - Open Tickets`.
- Shows a configurable ticket table. The default view includes ticket number, summary, status, priority, owner, due date, and configurations.
- Sets Magic Dash shade based on ticket health:
  - `success`: no open tickets or no overdue/SLA-risk tickets
  - `warning`: at least one overdue/SLA-risk ticket
  - `danger`: multiple overdue/SLA-risk tickets
- Supports dry-run and PowerShell `-WhatIf` behavior before writing Magic Dash tiles.

## What V1 Does Not Do Yet

- It does not fully implement Autotask, Halo, Syncro, Kaseya BMS, or other PSAs yet.
- It does not automatically create Hudu asset layouts or fields.
- It does not perform ticket write-back during the normal Magic Dash run.
- It includes guarded write-back helper functions, but they require explicit `-EnableWriteBack` and are not called by the default workflow.

## Requirements

- PowerShell 7 or later.
- Hudu API access.
- ConnectWise Manage API member keys.
- A ConnectWise developer `clientId`.

For Hudu, use the least-privileged API key that works for your use case. If you are only updating Magic Dash tiles, a Magic Dash scoped key is preferred. If you use `-UseHuduAssetConfig`, the key also needs access to companies, asset layouts, and assets.

For ConnectWise, the API member needs at least:

- Companies: Inquire
- Service Tickets: Inquire

Optional write-back testing requires additional ConnectWise permissions:

- Service Tickets: Add for ticket creation
- Service Tickets: Edit for ticket updates

## Configuration Options

The script resolves configuration from parameters first, then environment variables. If values are still missing, run with `-InteractiveSetup` to be prompted.

| Purpose | Parameter | Environment Variable |
| --- | --- | --- |
| Hudu base URL | `-HuduBaseUrl` | `HUDU_BASE_URL` |
| Hudu API key | `-HuduApiKey` | `HUDU_API_KEY` |
| ConnectWise API server | `-ConnectWiseServer` | `CW_SERVER` |
| ConnectWise company ID | `-ConnectWiseCompanyId` | `CW_COMPANY_ID` |
| ConnectWise public key | `-ConnectWisePublicKey` | `CW_PUBLIC_KEY` |
| ConnectWise private key | `-ConnectWisePrivateKey` | `CW_PRIVATE_KEY` |
| ConnectWise client ID | `-ConnectWiseClientId` | `CW_CLIENT_ID` |
| Global ticket conditions | `-TicketConditions` | `CW_TICKET_CONDITIONS` |
| Board names | `-BoardNames` | `CW_BOARD_NAMES` |
| Ticket table fields | `-TicketFields` | `CW_TICKET_FIELDS` |
| Ticket column widths | `-TicketColumnWidths` | `CW_TICKET_COLUMN_WIDTHS` |
| Ticket URL template | `-ConnectWiseTicketUrlTemplate` | `CW_TICKET_URL_TEMPLATE` |

Example:

```powershell
.\ConnectWise-Hudu-MagicDash.ps1 `
  -HuduBaseUrl "https://yourcompany.huducloud.com" `
  -HuduApiKey "hudu-api-key" `
  -ConnectWiseServer "api-na.myconnectwise.net" `
  -ConnectWiseCompanyId "your-cw-company-id" `
  -ConnectWisePublicKey "public-key" `
  -ConnectWisePrivateKey "private-key" `
  -ConnectWiseClientId "developer-client-id" `
  -BoardNames "Help Desk","NOC" `
  -TicketFields "Ticket","Summary","Status","Priority","Owner","Due","Configurations" `
  -TicketColumnWidths "Ticket=74px","Summary=360px","Configurations=220px" `
  -DryRun
```

## ConnectWise Ticket Conditions

By default, the script uses:

```text
closedFlag = False
```

You can override this globally:

```powershell
-TicketConditions 'closedFlag = False AND board/name = "Help Desk"'
```

Or use `-BoardNames` to append board filters without hand-writing the full condition:

```powershell
-BoardNames "Help Desk","NOC"
```

ConnectWise condition strings are case-sensitive and must quote string values with double quotes.

## Optional Hudu Asset Configuration

The script can read per-company settings from a `Company Details` asset. This matches common Hudu community Magic Dash patterns.

Enable this behavior with:

```powershell
-UseHuduAssetConfig
```

Suggested fields on the `Company Details` asset layout:

| Field | Type | Purpose |
| --- | --- | --- |
| `CW Manage:ENABLED` | CheckBox | Set to false to skip a company. |
| `CW Manage:URL` | Text | Link to that company's ConnectWise page. |
| `CW Manage:CompanyId` | Text | Strong company mapping to ConnectWise company ID. |
| `CW Manage:BoardNames` | Text | Comma-separated board names for this company. |
| `CW Manage:TicketConditions` | Text | Per-company ConnectWise ticket conditions. |
| `CW Manage:NOTE` | Text | Optional note shown above the ticket table. |

Company matching uses this order:

1. Hudu integration metadata/sync ID, when exposed by the Hudu API.
2. `CW Manage:CompanyId` from the `Company Details` asset.
3. Normalized company name matching.

## Ticket Links

Ticket numbers link to ConnectWise Manage. By default, the script builds a common ConnectWise Manage service ticket URL from `-ConnectWiseServer`. If your ConnectWise Manage UI URL differs from the API server, pass a URL template:

```powershell
-ConnectWiseTicketUrlTemplate "https://manage.example.com/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid={id}"
```

The script replaces `{id}` with the ConnectWise ticket ID and `{number}` with the ticket number.

## Ticket Table Fields

The default fields are:

```text
Ticket, Summary, Status, Priority, Owner, Due, Configurations
```

Use `-TicketFields` or `CW_TICKET_FIELDS` to control the table. Supported values are:

```text
Ticket, Summary, Board, Status, Priority, Owner, Age, Due, Configurations
```

Example:

```powershell
-TicketFields "Ticket","Summary","Board","Status","Priority","Age"
```

If `Configurations` is enabled, the script checks ConnectWise ticket configuration associations at `/service/tickets/{id}/configurations`. It then searches all Hudu assets for the matched company, regardless of asset layout, and renders real Hudu asset links when it can match by ConnectWise sync/id metadata or normalized asset name.

## Ticket Column Widths

Use `-TicketColumnWidths` or `CW_TICKET_COLUMN_WIDTHS` to tune the table without relying on JavaScript resizing inside Magic Dash.

```powershell
-TicketColumnWidths "Ticket=74px","Summary=360px","Status=95px","Priority=125px","Configurations=220px"
```

Environment variable form:

```text
CW_TICKET_COLUMN_WIDTHS=Ticket=74px,Summary=360px,Configurations=220px
```

Supported fields match `-TicketFields`. Supported width values are `auto`, `px`, `%`, `rem`, `em`, and `ch`.

## Safe Testing Flow

1. Confirm credentials only:

```powershell
.\ConnectWise-Hudu-MagicDash.ps1 -InteractiveSetup -TestConnectionOnly
```

2. Run a dry run for one Hudu company:

```powershell
.\ConnectWise-Hudu-MagicDash.ps1 -InteractiveSetup -CompanyName "Example Company" -DryRun
```

3. Run a real update for one Hudu company:

```powershell
.\ConnectWise-Hudu-MagicDash.ps1 -InteractiveSetup -CompanyName "Example Company"
```

4. Run all matched companies:

```powershell
.\ConnectWise-Hudu-MagicDash.ps1 -InteractiveSetup
```

You can also use PowerShell `-WhatIf`:

```powershell
.\ConnectWise-Hudu-MagicDash.ps1 -InteractiveSetup -WhatIf
```

## Write-Back Guardrails

The default script path is read-only against ConnectWise and only writes Magic Dash tiles in Hudu.

The script includes `New-ProviderTicket` and `Update-ProviderTicket` helper functions for future write-back work. They throw unless `-EnableWriteBack` is supplied, and they still honor `-DryRun` and `-WhatIf`.

Do not enable write-back until you have verified:

- The ConnectWise API member permissions.
- The exact board, status, company, contact, source, type, and priority requirements in your ConnectWise instance.
- The desired behavior for notifications.

## Future PSA Support

The provider contract is intentionally small:

- `Get-ProviderConnection`
- `Test-ProviderConnection`
- `Get-ProviderCompanies`
- `Get-ProviderTickets`
- `New-ProviderTicket`
- `Update-ProviderTicket`

Future providers should return the same normalized ticket shape used by the renderer. Once ConnectWise is tested, the next PSAs can plug into the provider functions without rewriting the Hudu client or Magic Dash renderer.

Suggested next providers:

- Autotask
- HaloPSA
- Syncro
- Kaseya BMS

## Troubleshooting

- `Missing required setting`: provide the parameter, environment variable, or use `-InteractiveSetup`.
- `No ConnectWise company match`: add `CW Manage:CompanyId` to the `Company Details` asset or align company names.
- `ConnectWise 401`: verify `{companyId}+{publicKey}:{privateKey}` credentials and the `clientId`.
- `No tickets returned`: test the ConnectWise conditions in the ConnectWise developer docs or reduce filters to `closedFlag = False`.
- `Magic Dash not appearing`: confirm the Hudu API key can create Magic Dash tiles and that the Hudu company name matches exactly.
