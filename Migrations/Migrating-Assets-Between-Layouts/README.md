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

> Photo relinking requires Hudu `2.41.0` or later.

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
- Network access to refresh the HuduAPI fork from GitHub during initialization; Git is an optional fallback if the repository archive cannot be downloaded

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

The initializer is embedded in `Start-HuduAssetLayoutTransfer.ps1`, so the main script can run on its own. `Build.ps1` packages that same script in the single-file executable.

<img width="404" height="169" alt="Launch screen" src="https://github.com/user-attachments/assets/732b0873-4c1c-42f2-b202-5cc362bdd6f8" />

The tool opens a GUI window and a terminal window. The terminal is mainly there for logging and troubleshooting.

### 2. Enter your Hudu connection details

Provide your Hudu URL and API key.

The `Set-HuduModuleInitialized` function in the main script refreshes the HuduAPI fork on each initialization, validates the downloaded module, imports it, configures the connection, and confirms the server version. It tries the repository archive first and Git clone second. Initialization stops if neither method succeeds. There is no bundled HAPI ZIP or PowerShell Gallery fallback.

The default fork is `https://github.com/Hudu-Technologies-Inc/HuduAPI.git` on `master`. `HUDUAPI_REPOSITORY_URL`, `HUDUAPI_REPOSITORY_BRANCH`, and `HUDUAPI_ZIP_URL` can override the download source. Programmatic calls to `Set-HuduModuleInitialized` can set `-HAPImodulePath` or opt into an existing complete fork with `-RefreshHuduApiForkEachRun $false`.

<img width="399" height="170" alt="Connection prompt" src="https://github.com/user-attachments/assets/32d62e27-dde5-4957-897c-5c7c6a9628e9" />

### 3. Choose the source and destination layouts, transfer mode, source-archival strategy, and merge strategy

Pick the layout you are moving **from** and the layout you are moving **to**.


If you are confident with your source/dest selection, it's generally a good idea to archive source data afterwards.


### 4-A Transfer mode, match, merge, and archive strategy

You will then get a confirmation step to review or change the selection.

<img width="1488" height="772" alt="image" src="https://github.com/user-attachments/assets/335ff802-1529-4d93-ab08-3d24d09b5532" />

If an incoming source asset appears to match an existing destination asset, you can choose how the tool should behave.

You can also enable custom matching criteria in the transfer options. After field mapping is complete, the wizard will ask for primary, secondary, and tertiary criteria from the mapped `destination <= source` field pairs, plus asset name. Each criterion can use direct case-insensitive matching or broader contains-either-way matching. During transfer, the criteria are checked in order against destination assets in the same company, and later criteria can narrow multiple earlier matches.

If you select `Only modify existing assets`, match/merge behavior and custom matching are disabled because the tool is moving the selected source assets themselves into the destination layout instead of looking for separate destination assets to merge into. The GUI labels these unavailable controls directly while this mode is selected.

### 4-B (optional) filtering

If you would like to filter the source assets you are enqueueing, you can do so by selecting a field to select for an a value to match on. 
You can match on any source field and any source field type. Dates, ListSelects, Text, etc.

The form will hint the number of assets that fall under your chosen filter.

<img width="1520" height="724" alt="image" src="https://github.com/user-attachments/assets/7bc9709a-799d-459d-83a6-fc7c395faff7" />

### 4-C Set final strategies for fields, 'smoosh' application, and relations

<img width="1610" height="738" alt="image" src="https://github.com/user-attachments/assets/b91add5c-12c1-4fba-9423-2784c5e81a40" />

pretty straightforward, Including blank values in smoosh and keeping HTML intact is usually not desirable [depending on circumstances] and will be disabled if no smoosh source/target was selected. 

Including relations for archived objects is also generally good to do.

### 5. Review field mappings

If the source and destination layouts already line up closely and neither layout has Number fields, the tool may offer a direct transfer path. Number fields use the mapping workflow so subtype validation is applied. Select `Only modify existing assets` there when asset IDs need to be preserved.

<img width="904" height="158" alt="Direct transfer prompt" src="https://github.com/user-attachments/assets/f10aadba-25c0-4ab2-8669-29499d0577f6" />

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

`InstructionBlock` fields are skipped on both layouts. They contain static layout instructions, so they are excluded from source choices, destination review, and transferred asset values.

Field choices and destination type details show Number subtypes (`Plain`, `Currency`, or `Percentage`), currency codes where applicable, and any configured minimum or maximum. The same details appear in source filtering, custom match choices, and the final mapping review. Field pickers use the original field labels when saving mappings.

The mapping editor also shows a live snapshot of:

- Configured destination fields
- Pending destination fields
- Skipped destination fields
- Mapped source fields
- Unmapped source fields

Use `Back` and `Next` to move through the review loop. `Back` discards any in-progress edits for the current field unless that field was already saved earlier.

### Standard Source Mapping

This is the most common path: pick a source field and optionally enable `Strip HTML`.

<img width="677" height="622" alt="Standard source mapping" src="https://github.com/user-attachments/assets/89487473-75f9-4cad-9cd8-98506d3d916e" />

Use `Strip HTML` when moving from rich text or embed-like source fields into plain text destination fields.

### Number Destinations

Number conversion uses the saved destination field's `number_type`, `currency_code`, `min`, and `max`, following the [ConvertTo-HuduNumber methodology](https://github.com/Hudu-Technologies-Inc/ITGlue-Hudu-Migration/blob/main/Public/ConvertTo-HuduNumber.ps1). The helpers are embedded in the main script so the standalone script and packaged executable share the same behavior.

| Destination subtype | Conversion policy for Hudu 2.48.0 and later |
| --- | --- |
| Number | Preserve zero, signs, and decimal precision as numeric strings; reject values outside -9223372036854775807 through 9223372036854775807. |
| Currency | Accept matching currency markers and round USD, EUR, or AUD to two decimal places, with midpoints away from zero. For example, USD `12.345` becomes `12.35`. Unknown currency precision is omitted. |
| Percentage | Keep percentage points: `12.5%` becomes `12.5`, and `0.125` stays `0.125`. Negative values are allowed; values above 100 are omitted. |

Destination bounds are checked after conversion and rounding. `min` and `max` are independent and inclusive: either bound can be set by itself, blank bounds are ignored, and zero is a valid bound. For plain Number fields (`number_type = number`), a returned `currency_code = USD` does not enable currency rounding. Unambiguous grouping, decimal separators, and scientific notation are supported. Ambiguous values such as `1,234`, arbitrary text such as `Asset #12`, booleans, collections, invalid metadata, and out-of-range values are omitted. Empty or invalid required Number fields do not receive a placeholder or null value. A valid constant or existing destination value can still supply the field under the selected merge policy.

These checks apply to source mappings, constants, and existing values used during merges. Warnings report omissions, currency rounding, and values that already arrived as floating-point numbers with potentially lost precision. Numeric strings retain precision through JSON serialization.

The transfer reads the Hudu server version before processing numeric fields. Older or unknown versions use the helper's conservative Int32 integer policy without rounding fractional input; percentage limits and destination bounds still apply. Programmatic calls to `New-NonInteractiveLayoutTransfer` can supply `-CurrentVersion` when the server version is already known.

### Constant Mapping

Use this when a destination field should always receive the same value.

<img width="650" height="300" alt="Constant mapping" src="https://github.com/user-attachments/assets/407175b1-2ca3-4ba2-8d30-eff61b7045b0" />

This is especially useful for required destination fields that have no good source equivalent.

### ListSelect Mapping

For `ListSelect` destination fields, choose a source field and define which source values should map to which destination list items.

##### ListMapping Examples

<img width="658" height="345" alt="ListSelect mapping" src="https://github.com/user-attachments/assets/8022ecd1-6761-4461-8a32-5cd1f665b021" />

---

<img width="2104" height="1410" alt="image" src="https://github.com/user-attachments/assets/a1d6c22a-53cd-43fb-b404-d3bc7390d697" />



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

<img width="684" height="630" alt="SMOOSH mapping" src="https://github.com/user-attachments/assets/6f5f6dc6-9441-494d-b40e-9cfbe2dd419f" />

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

<img width="1816" height="672" alt="image" src="https://github.com/user-attachments/assets/aecf94b3-b436-41c0-89b6-7845e2a353cb" />

This matching logic helps prevent accidental duplicates while still allowing flexible merge behavior.

<img width="1584" height="324" alt="image" src="https://github.com/user-attachments/assets/35716e18-2a86-480a-a4e9-9dd41b75885d" />

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
