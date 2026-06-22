# Standardizing Text Fields into List Select Fields

Have you ever encountered a text field that *almost* works—but suffers from inconsistent values, spelling variations, or formatting differences? In many cases, these scenarios are better served by a **List Select** field, which enforces consistency and improves data quality across assets.

This guide walks through two friendly, community-maintained ways to listify those fields while safely preserving the original data:

- `Listify-Text-Field.ps1` handles one Asset Layout at a time.
- `Consolidate-ListifyTextField.ps1` handles the same field across multiple Asset Layouts and points them all at one shared list.

---

## Overview

Both scripts are built to be safe and interactive. They add a new **List Select** field, populate it from existing Text values, and leave the original Text field alone so you can verify everything before doing any cleanup.

### Prerequisites

- PowerShell 7.5.1 or newer
- HuduAPI PowerShell module 2.4.5 or newer
- A Hudu API key with permission to modify Asset Layouts, Lists, and Assets
- One or more Asset Layouts containing the Text field you want to standardize

---

## Single-Layout Conversion

Use this when one Asset Layout has a Text field you want to turn into a layout-specific List Select field.

```powershell
pwsh ./Listify-Text-Field.ps1
```

### How It Works

#### 1. Select an Asset Layout

You’ll first be prompted to choose the Asset Layout that contains the Text field you want to standardize. Any layouts that do not contain at least one Text field are omitted.

#### 2. Choose the Source Field

Next, select the specific **Text** field you’d like to convert.
Don’t worry—**all existing values are preserved** during the process.

- Every unique value found in the field will be collected
- These values will be used to populate a new or existing List

#### 3. Review and Confirm

Before any changes are applied, you’ll be asked to confirm your selection.

- If anything doesn’t look correct, you can safely abort the process at this stage using **Ctrl + C**
- No changes are made until confirmation is provided

#### 4. Automatic Conversion

Once confirmed, the script will:

- Identify all unique values used in the selected Text field
- Create or update a List named like `Computer Assets - Manufacturers`
- Add a new **List Select** field named like `Manufacturer List`
- Migrate all existing asset values from the Text field to the new List Select field

---

## Cross-Layout Consolidation ✨

Use this when the same Text field exists on multiple Asset Layouts and you want **one shared list** instead of one list per layout.

For example, if `Manufacturer` exists on Computer Assets, Server Assets, and Printers, this script can create one `Manufacturers` list and apply `Manufacturer List` to each matching layout.

Example:

```powershell
pwsh ./Consolidate-ListifyTextField.ps1 -FieldLabel "Manufacturer"
```

To limit the run to specific layouts:

```powershell
pwsh ./Consolidate-ListifyTextField.ps1 -FieldLabel "Manufacturer" -LayoutNames @("Computer Assets", "Server Assets")
```

To create or update the list and layout fields without migrating asset values:

```powershell
pwsh ./Consolidate-ListifyTextField.ps1 -FieldLabel "Manufacturer" -SkipAssetUpdate
```

You can also omit `-FieldLabel` and choose from discovered Text fields interactively:

```powershell
pwsh ./Consolidate-ListifyTextField.ps1
```

### How It Works

#### 1. Pick the Field

You can pass the field directly with `-FieldLabel`, or let the script show you common Text fields it found across your layouts.

#### 2. Find Matching Layouts

The script scans Asset Layouts for a matching **Text** field. If you supplied `-LayoutNames`, only those layouts are considered.

#### 3. Gather the Good Stuff

Every non-empty value from every matching layout is collected, trimmed, deduplicated, and sorted. Duplicate values across layouts only appear once in the final list.

#### 4. Create One Shared List

The script creates or updates one consolidated Hudu list named like `Manufacturers`. If the list already exists, it adds only the missing values.

#### 5. Add List Fields and Migrate Assets

Each matching layout gets a new List Select field named like `Manufacturer List` if it does not already have one. Then, unless `-SkipAssetUpdate` is used, assets with existing Text values are updated to use the new List Select field.

---

## Safety Notes 🛟

This is designed to be repeatable and non-destructive:

- The original Text field is preserved.
- Existing lists are reused and updated instead of duplicated.
- Existing `Field Name List` fields are reused and not duplicated.
- Empty Text values are skipped during migration.
- Per-asset update failures are logged as warnings and do not stop the full run.
- Before layout or asset changes, the script prints a summary and waits for confirmation.

---

## Final Steps

After completion, review the affected Asset Layouts and spot-check a few assets from each layout.

Once you’ve confirmed the new List Select field is populated correctly, you can decide whether to keep or remove the original Text field.

---

## Summary

Whether you’re cleaning up one layout or wrangling the same field across a whole fleet of layouts, these scripts give you a safe, repeatable way to bring order to free-form text fields.

Happy listifying! 🎉
