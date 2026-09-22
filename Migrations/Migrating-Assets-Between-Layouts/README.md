# Hudu Asset Layout Transfer

Move assets from one Hudu asset layout to another with a guided GUI workflow. The tool helps you map fields, fill required values, combine multiple source fields with `SMOOSH`, handle merge-on-match behavior, and relink supported related objects.

> **Quick summary**
> 1. Run `HuduAssetLayoutTransfer.exe`, double-click `Start-HuduAssetLayoutTransfer.cmd`, or run `Start-HuduAssetLayoutTransfer.ps1` with PowerShell 7
> 2. Choose the source and destination layouts
> 3. Pick the transfer mode and merge behavior
> 4. Review each destination field in the mapping wizard
> 5. Confirm the final plan and run the transfer

---

## What This Tool Does

- Transfers asset data from one Hudu layout into another
- Supports field-by-field mapping through the GUI
- Lets you use constant values for required destination fields
- Supports `SMOOSH` to combine multiple source fields into one destination field
- Can normalize or strip HTML from rich text when needed
- Supports structured `AddressData` destination mapping
- Supports `ListSelect` destination mapping, including optional creation of missing list items
- Can merge or skip when a likely matching asset already exists in the destination
- Relinks supported related records such as passwords, uploads, articles, and photos
- Can optionally move existing assets in place to the new layout, preserving the same asset IDs

## What Gets Carried Over

In the default transfer mode, the tool creates or updates destination-layout assets, transforms the mapped fields, and copies or relinks supported related items.

- Any source asset fields you choose to map
- AssetTag relations, converted into direct relations where applicable
- Related passwords
- Related procedures
- Related articles
- Attached uploads
- Public photos
- Related photos

> Photo relinking requires Hudu `2.45.0` or later.

## Transfer Modes

### Default: create, transform, and relink

This is the safest general-purpose workflow. The tool creates a new destination-layout asset or updates a matched destination asset, transforms fields into the target layout, then copies or relinks supported related records.

Use this mode when you want the old source-layout assets to remain as a cleaner rollback point, or when you need match/merge behavior against assets that already exist in the destination layout.

### Only modify existing assets

This option moves each existing source asset directly into the destination layout, then updates that same asset with the transformed field values. Because the asset ID does not change, Hudu keeps the asset's own history and direct associations attached to the same record.

This can be a strong fit when:

- The assets have many process runs or other activity/history that should stay on the same asset record
- You want to keep asset history intact instead of creating a replacement asset
- Assets may be tied to integrators, integration cards, or other ID-sensitive associations
- The asset already has passwords, photos, uploads, public photos, or relations that you want to keep attached without copy/relink work

Important tradeoffs:

- This mode is less reversible than the default copy-and-relink workflow
- Destination matching, merge behavior, custom matching criteria, and auxiliary relinking are not available in this mode
- Source layout rename and source asset archival settings remain available
- The run logs and `transferresults_*.json` record the selected transfer mode

---

## Requirements

- PowerShell `7.5.1` or later
- A Hudu base URL
- A Hudu API key
- An existing source layout and destination layout

For best results, use a full-permission API key rather than a narrowly scoped company-only key.

---

## Quick Start

### 1. Launch the tool

Run `HuduAssetLayoutTransfer.exe`.

For a standalone PowerShell launch without building or distributing an EXE, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Start-HuduAssetLayoutTransfer.ps1
```

To launch from Explorer, double-click `Start-HuduAssetLayoutTransfer.cmd`. The command launcher finds PowerShell 7 and starts the GUI script with `pwsh.exe`.

<img width="808" height="338" alt="image" src="https://github.com/user-attachments/assets/4478221e-9087-49d1-98cf-0e976ac926f5" />

The tool opens a GUI window and a terminal window. The terminal is mainly there for logging and troubleshooting.

### 2. Enter your Hudu connection details

Provide your Hudu URL and API key.

<img width="798" height="340" alt="image" src="https://github.com/user-attachments/assets/daa8f0ca-cb67-4c47-9139-3446ecfe6c52" />

### 3. Choose the source and destination layouts, transfer mode, source-archival strategy, and merge strategy

Pick the layout you are moving **from** and the layout you are moving **to**.


If you are confident with your source/dest selection, it's generally a good idea to archive source data afterwards.


### 4-A Transfer mode, match, merge, and archive strategy

You will then get a confirmation step to review or change the selection.

<img width="740" height="486" alt="image" src="https://github.com/user-attachments/assets/17817303-d7fe-4b8b-b691-ac784655c909" />

If an incoming source asset appears to match an existing destination asset, you can choose how the tool should behave.

You can also enable custom matching criteria in the transfer options. After field mapping is complete, the wizard will ask for primary, secondary, and tertiary criteria from the mapped `destination <= source` field pairs, plus asset name. Each criterion can use direct case-insensitive matching or broader contains-either-way matching. During transfer, the criteria are checked in order against destination assets in the same company, and later criteria can narrow multiple earlier matches.

If you select `Only modify existing assets`, match/merge behavior and custom matching are disabled because the tool is moving the selected source assets themselves into the destination layout instead of looking for separate destination assets to merge into. The GUI labels these unavailable controls directly while this mode is selected.

### 4-B (optional) filtering

If you would like to filter the source assets you are enqueueing, you can do so by selecting a field to select for an a value to match on. 
You can match on any source field and any source field type. Dates, ListSelects, Text, etc.

The form will hint the number of assets that fall under your chosen filter.

<img width="1520" height="724" alt="image" src="https://github.com/user-attachments/assets/e5ceb71f-c724-4caa-9675-9fce6be468d1" />


### 4-C Set final strategies for fields, 'smoosh' application, and relations

<img width="1610" height="738" alt="image" src="https://github.com/user-attachments/assets/589f8904-0a20-4446-82fc-43d91c0a6dba" />

pretty straightforward, Including blank values in smoosh and keeping HTML intact is usually not desirable [depending on circumstances] and will be disabled if no smoosh source/target was selected. 

Including relations for archived objects is also generally good to do.

### 5. Review Transfer Plan / Mappings / Strategy

If the source and destination layouts already line up closely, the tool may offer a direct transfer path.

<img width="1808" height="316" alt="image" src="https://github.com/user-attachments/assets/2d921d60-2436-412c-8a33-64b8e607aa51" />

<img width="900" height="686" alt="image" src="https://github.com/user-attachments/assets/5bf150ea-82b3-4488-a2d8-a98d42f7f857" />


Otherwise, you will work through the field mapping wizard one destination field at a time.

---

## Merge Modes

When a source asset appears to match a destination asset, choose one of these behaviors:

- `Merge-FillBlanks`: destination wins; source only fills missing values
- `Merge-PreferSource`: source wins; destination acts as fallback
- `Merge-Concat`: keeps both values for text-like fields and chooses a winner for non-text fields
- `Skip`: do not transfer the source asset if a match is found

Use `Merge-Concat` when you want to preserve both sets of notes or descriptive text. Use `Merge-FillBlanks` when the destination is already your source of truth.

Merge modes apply to the default transfer workflow. They are not used when `Only modify existing assets` is selected.

**tip*- Use custom matching criteria when matched objects are the expectation in order to achieve fewer cleanup tasks and higher accuracy*

---

## Field Mapping Workflow

Each destination field is reviewed in the GUI. For every field, choose one mapping mode:

- `Source Field`: map from one source field
- `Constant Value`: always write the same literal value
- `SMOOSH`: combine multiple source fields into one destination field
- `Skip`: leave the destination field unmapped

The mapping editor also shows a live snapshot of:

- Configured destination fields
- Pending destination fields
- Skipped destination fields
- Mapped source fields
- Unmapped source fields

Use `Back` and `Next` to move through the review loop. `Back` discards any in-progress edits for the current field unless that field was already saved earlier.

### Standard Source Mapping

This is the most common path: pick a source field and optionally enable `Strip HTML`.

<img width="1354" height="1244" alt="image" src="https://github.com/user-attachments/assets/97caf0d8-3aa9-4954-87c5-d3aad8be98e5" />


Use `Strip HTML` when moving from rich text or embed-like source fields into plain text destination fields.

### Constant Mapping

Use this when a destination field should always receive the same value.

<img width="1300" height="600" alt="image" src="https://github.com/user-attachments/assets/a33d3b14-bbac-437c-8486-10e1c919e890" />


This is especially useful for required destination fields that have no good source equivalent.

### ListSelect Mapping

For `ListSelect` destination fields, choose a source field and define which source values should map to which destination list items.

##### ListMapping Examples

<img width="1316" height="690" alt="image" src="https://github.com/user-attachments/assets/d0171f07-01bf-4526-ab57-912642338b65" />

---

<img width="2104" height="1410" alt="image" src="https://github.com/user-attachments/assets/87a98a24-8103-4063-b243-357870636e60" />

This is helpful when the source data is inconsistent and needs to be normalized into one controlled list.

Example:

- Source values like `floor`, `ground`, or `dirt` can map to destination option `ground stuff`
- Source values like `sunny` or `sunshine` can map to `solar stuff`

Matching is case-insensitive and uses first-match-wins behavior.

If the destination list may be missing values, enabling `Add missing list items` is usually the right choice.

### AddressData Mapping

`AddressData` fields can be mapped by parts:

- `address_line_1`
- `address_line_2`
- `city`
- `state`
- `zip`
- `country_name`

The tool builds the destination address object only when at least one address component is present.

### SMOOSH Mapping

`SMOOSH` lets you combine multiple source fields into one destination field. It is usually most useful for `RichText`, `Heading`, or other notes-style destinations.

<img width="1368" height="1260" alt="image" src="https://github.com/user-attachments/assets/d206bb01-9aa7-4148-b0b1-ed4e50dfa75a" />

Example rich text output:

```text
Serial Number:
9JD2NLAL4
Notes:
This is a good computer
```

Example plain text output:

```text
9JD2NLAL4; This is a good computer; John https://huduurl.huducloud.com/a/johnsslug
```

---

## Per-Job Settings

After field mapping, the tool asks a few follow-up questions depending on how your plan is configured.

| Variable | Default | Description |
|---|---:|---|
| `$includeblanksduringsmoosh` | `$false` | Includes empty values when building SMOOSH output. |
| `$includeLabelInSmooshedValues` | `$true` | Prepends the source field label before each SMOOSHed value. |
| `$excludeHTMLinSMOOSH` | `$false` | Strips HTML and flattens SMOOSH output into cleaner plain text. |
| `$includeRelationsForArchived` | `$true` | Preserves relations even when the related object is archived. |

---

## How Matching Works

Before creating a destination asset, the tool checks whether a likely match already exists.

A source asset is treated as a likely match when:

- It belongs to the same company as a destination asset, and
- The names are the same, or the destination name starts with or ends with the source name

Very short names are intentionally not matched too aggressively.

When custom matching criteria are enabled, those configured criteria replace the default name matcher. The transfer checks the primary criterion first, then secondary, then tertiary; blank source values are skipped for that criterion. Direct matching compares trimmed text case-insensitively, while the broader option matches when either value contains the other. If a criterion narrows the result to multiple destination assets, the next criterion is used to keep narrowing.

<img width="1816" height="672" alt="image" src="https://github.com/user-attachments/assets/3cc213f5-d7cb-4054-9998-0694ac3c54c4" />


This matching logic helps prevent accidental duplicates while still allowing flexible merge behavior.

<img width="1584" height="324" alt="image" src="https://github.com/user-attachments/assets/f989ea5c-7879-4007-9505-5aaa8189d863" />


Matching is skipped when `Only modify existing assets` is selected, because the source asset itself is moved to the destination layout and keeps its existing asset ID.

---

## Review, Outputs, and Logs

Before the transfer runs, the tool shows a final summary of the mapping plan, including:

- Direct mappings
- Constants
- SMOOSH target and source count
- Skipped fields
- Merge behavior
- Archive preference
- Transfer mode

After the transfer, the tool writes a timestamped JSON results file such as:

- `transferresults_YYYYMMDD_HHMMSS.json`

The console output also includes field-level and relation-level progress messages to help with troubleshooting. For `Only modify existing assets` runs, the logs and results mark the mode explicitly because the workflow changes existing asset records in place.

---

## Troubleshooting Tips

### Plain text fields showing HTML

Enable `Strip HTML` on the specific field mapping, especially when the source field is `RichText`, `Heading`, or `Embed`-like content.

### ListSelect values not landing where expected

Double-check the `whenvalues` mapping and remember that matching is case-insensitive and uses the first matching destination option.

### Email fields look messy

Make sure the destination field is typed or labeled as an email field so the email cleanup logic can normalize the value correctly.

### Address casing looks odd

The helper logic normalizes common US state names and country variants such as `US`, `USA`, and `United States`.

---

## Advanced Example

If you are working with the underlying mapping structure programmatically, a plan can look like this:

```powershell
$CONSTANTS = @(
  @{ literal = 'Vonage'; to_label = 'VOIP Service Provider' }
)

$SMOOSHLABELS = @('Serial Number','Notes')

$mapping = @(
  @{ from='Model Name'         ; to='Model'               ; dest_type='Text'     ; required='True'  ; striphtml='False' },
  @{ from='Primary IP'         ; to='IP Address'          ; dest_type='Website'  ; required='False' ; striphtml='False' },
  @{ from='Warranty Expires At'; to='Warranty Expiration' ; dest_type='Date'     ; required='False' ; striphtml='False' },
  @{ from='SMOOSH'             ; to='Notes'               ; dest_type='RichText' ; required='False' ; striphtml='False' }
)

$includeblanksduringsmoosh    = $false
$includeRelationsForArchived  = $true
$excludeHTMLinSMOOSH          = $false
$describeRelatedInSmoosh      = $true
$includeLabelInSmooshedValues = $true
```

---

## Tips

- Prefer matching destination field types when possible
- Use constants to satisfy required destination fields that have no good source value
- Use `SMOOSH` for notes-style destinations rather than trying to cram several inputs into a single normal field
- Use `Only modify existing assets` when keeping process runs, asset history, or integrator-linked asset IDs intact matters more than having a separate copied asset as a rollback point
- For plain text destinations, consider both `Strip HTML` and `excludeHTMLinSMOOSH=$true`
- Start with a small test layout or a small company subset before running a large migration

---

## Changelog

- `v0.3` - Initial public draft of the layout-switching documentation, November 19, 2025
- `v0.5` - Added merge-on-match options, February 23, 2026
- `v0.6` - Added constant fallback values and combined relation handling on match, March 3, 2026
- `v0.8` - Added password, photo, public photo, and upload reattribution, March 4, 2026
- `v1.0` - Finalized GUI, added forward,back buttons, and field indicator panel.
- `v1.2` - Consolidated forms for easier review / navigation, added source-data filter for mapped or L2L migrations
- `v1.3` - Addition of Custom Matching Criteria and Conditions, Matching behavior customization, May 28, 2026
- `v1.4` - Added `Only modify existing assets` mode for preserving asset IDs, process history, and integrator-linked associations, September 22, 2026
- `v1.5` - Added direct-transfer option, which keeps integrator cards/matches and process runs intact, as well as asset history (but is more difficult to reverse when a mistake is made)
