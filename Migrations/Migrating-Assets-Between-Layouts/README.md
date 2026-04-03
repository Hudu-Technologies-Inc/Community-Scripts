# Hudu Asset Layout Transfer

Move assets from one Hudu asset layout to another with a guided GUI workflow. The tool helps you map fields, fill required values, combine multiple source fields with `SMOOSH`, handle merge-on-match behavior, and relink supported related objects.

> **Quick summary**
> 1. Run `HuduAssetLayoutTransfer.exe`
> 2. Choose the source and destination layouts
> 3. Pick merge behavior for matching assets
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

## What Gets Carried Over

- Any source asset fields you choose to map
- AssetTag relations, converted into direct relations where applicable
- Related passwords
- Related procedures
- Related articles
- Attached uploads
- Public photos
- Related photos

> Photo relinking requires Hudu `2.41.0` or later.

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

<img width="808" height="338" alt="image" src="https://github.com/user-attachments/assets/3d783a2e-bfd0-4428-99fd-e7c8d5cec0a2" />

The tool opens a GUI window and a terminal window. The terminal is mainly there for logging and troubleshooting.

### 2. Enter your Hudu connection details

Provide your Hudu URL and API key.

<img width="798" height="340" alt="image" src="https://github.com/user-attachments/assets/01cbb8ba-ee21-4e31-b542-7b121ac1a33f" />

### 3. Choose the source and destination layouts

Pick the layout you are moving **from** and the layout you are moving **to**.

<img width="814" height="450" alt="image" src="https://github.com/user-attachments/assets/52fd730b-1e25-4216-ac4f-f00b312c597c" />

You will then get a confirmation step to review or change the selection.

<img width="808" height="444" alt="image" src="https://github.com/user-attachments/assets/73eafd51-fd87-4d85-bf29-f416db2b21a6" />

### 4. Choose merge behavior for matches

If an incoming source asset appears to match an existing destination asset, you can choose how the tool should behave.

<img width="804" height="552" alt="image" src="https://github.com/user-attachments/assets/9346a982-5838-4ffd-a7c1-26487e252621" />

You can also optionally rename the source layout after the transfer is complete.

<img width="814" height="368" alt="image" src="https://github.com/user-attachments/assets/0423cd7f-25c4-4231-b881-8948ed7a211f" />

### 5. Decide whether to archive the original source assets

This is usually recommended once you are confident the transfer plan is correct.

<img width="828" height="322" alt="image" src="https://github.com/user-attachments/assets/568e9eca-4336-4b0d-8263-ef4f9c55269a" />

### 6. Review field mappings

If the source and destination layouts already line up closely, the tool may offer a direct transfer path.

<img width="1808" height="316" alt="image" src="https://github.com/user-attachments/assets/766bcb25-89b2-44ca-bdc8-17bf273cc9fd" />

Otherwise, you will work through the field mapping wizard one destination field at a time.

---

## Merge Modes

When a source asset appears to match a destination asset, choose one of these behaviors:

- `Merge-FillBlanks`: destination wins; source only fills missing values
- `Merge-PreferSource`: source wins; destination acts as fallback
- `Merge-Concat`: keeps both values for text-like fields and chooses a winner for non-text fields
- `Skip`: do not transfer the source asset if a match is found

Use `Merge-Concat` when you want to preserve both sets of notes or descriptive text. Use `Merge-FillBlanks` when the destination is already your source of truth.

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

<img width="1046" height="697" alt="image" src="https://github.com/user-attachments/assets/b29c33d0-287e-4b3a-a353-b5efcb05a5b6" />

Use `Strip HTML` when moving from rich text or embed-like source fields into plain text destination fields.

### Constant Mapping

Use this when a destination field should always receive the same value.

<img width="1035" height="687" alt="image" src="https://github.com/user-attachments/assets/c28599a7-0de2-4fb3-b3fc-c8db54518800" />


This is especially useful for required destination fields that have no good source equivalent.

### ListSelect Mapping

For `ListSelect` destination fields, choose a source field and define which source values should map to which destination list items.

<img width="1316" height="690" alt="image" src="https://github.com/user-attachments/assets/5577c8a1-ea53-4aef-bac2-80bf68dcb422" />

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

<img width="1368" height="1260" alt="image" src="https://github.com/user-attachments/assets/f05ba500-0c23-4921-bb7f-8d640e0695df" />


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

This matching logic helps prevent accidental duplicates while still allowing flexible merge behavior.

---

## Review, Outputs, and Logs

Before the transfer runs, the tool shows a final summary of the mapping plan, including:

- Direct mappings
- Constants
- SMOOSH target and source count
- Skipped fields
- Merge behavior
- Archive preference

After the transfer, the tool writes a timestamped JSON results file such as:

- `transferresults_YYYYMMDD_HHMMSS.json`

The console output also includes field-level and relation-level progress messages to help with troubleshooting.

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
- For plain text destinations, consider both `Strip HTML` and `excludeHTMLinSMOOSH=$true`
- Start with a small test layout or a small company subset before running a large migration

---

## Changelog

- `v0.3` - Initial public draft of the layout-switching documentation, November 19, 2025
- `v0.5` - Added merge-on-match options, February 23, 2026
- `v0.6` - Added constant fallback values and combined relation handling on match, March 3, 2026
- `v0.8` - Added password, photo, public photo, and upload reattribution, March 4, 2026
- 'v1.0' - Finalized GUI, added forward,back buttons, and field indicator panel.
