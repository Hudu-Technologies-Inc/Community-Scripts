# MoveAssetsBetweenCompanies.ps1

## High-level overview

`MoveAssetsBetweenCompanies.ps1` is an interactive PowerShell script that moves **Hudu Assets** from one company to another based on filter criteria you choose (asset name contains text, a specific asset-layout field contains text, or both). It prompts you through selection, previews what will be moved, performs the move, and writes a **CSV log** of results.

---

## Requirements

- **PowerShell 7+ recommended** (works on Windows/macOS/Linux).
- A **Hudu API key** with permission to:
  - List companies
  - List asset layouts
  - List assets
  - Update assets (move them)

> No additional modules required — the script uses direct API calls via `Invoke-RestMethod`.

---

## How it works

### Prompts you will see

1. **Hudu Base URL**
   - Example: `https://yourhudu.domain`

2. **Hudu API Key**
   - Entered securely (not echoed)

3. **Select company to MOVE FROM**
   - Type **2+ characters** of the company name
   - Script shows a filtered picker list

4. **Select company to MOVE TO**
   - Same picker experience, excluding the source company

5. **Choose criteria**
   - **[1] Asset Name contains text**
   - **[2] Specific Asset Layout Field contains text**
   - **[3] Name contains AND Field contains**

6. If you select **[2]** or **[3]**
   - Select an **Asset Layout**
   - Select a **field** from that layout
   - Enter the text the field must contain

7. **Preview**
   - Script shows up to 20 matching assets (name + ID + layout ID)

8. **Confirm**
   - You must type **MOVE** to proceed

---

## Matching logic

### Option 1 — Name contains
Moves assets where:

- `Asset.Name` contains the text you enter (wildcard match)

### Option 2 — Field contains (layout-scoped)
Moves assets where:

- Asset is within the selected layout (to keep field evaluation consistent)
- The selected field’s value contains the text you enter

### Option 3 — Name AND Field
Moves assets only if:

- Name contains the text **AND**
- Selected field contains the text

---

## Output / logging

After running, the script prints:

- Number of assets loaded
- Number of matched assets
- OK vs FAILED move count
- The log file path

A CSV file is written to the working directory with a name like:

- `hudu-asset-move-log-YYYYMMDD-HHMMSS.csv`

The CSV includes:

- `asset_id`
- `asset_name`
- `from_company`
- `to_company`
- `status` (OK / FAILED)
- `message` (error details if failed)

---

## Safety notes

- This is a **bulk operation** — verify the preview before typing `MOVE`.
- Start with narrow criteria first (e.g., a unique naming fragment or specific IP/subnet).
- Keep the CSV log for auditing or rollback planning.

---

## Troubleshooting

### All moves fail (OK: 0) and the log shows 404 Not Found
Your Hudu instance may not support updating assets using the endpoint/method currently in the script.

Typical fix:
- Use the company-scoped asset update endpoint (varies by Hudu version/instance).
- Improve error logging to capture the API response body.

If you paste the failing log row(s) (or the full CSV), it’s usually straightforward to adjust the update call.

### “The property ‘___’ cannot be found on this object”
This commonly occurs when `Set-StrictMode -Version Latest` is enabled and the script references optional properties that aren’t present in the API response.

Fix:
- Use StrictMode-safe property access (`PSObject.Properties[...]`) everywhere the script reads object properties.

### Only the first 25 asset layouts are displayed
Some Hudu endpoints cap page size and require paging until an empty page is returned.

Fix:
- Ensure pagination continues until a page returns **0 items**, not until it returns `< per_page`.

---

## Common use cases

- Fix assets created under the wrong company
- Consolidate assets after mergers/renames
- Move subsets of assets based on naming conventions, site codes, or IP/subnet fields
