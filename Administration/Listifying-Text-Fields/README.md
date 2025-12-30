# Standardizing Text Fields into List Select Fields

Have you ever encountered a text field that *almost* works—but suffers from inconsistent values, spelling variations, or formatting differences? In many cases, these scenarios are better served by a **List Select** field, which enforces consistency and improves data quality across assets.

This guide walks through a simple, community‑maintained script that converts an existing **Text** field into a **List Select** field—while safely preserving all existing data.

---

## Overview

The conversion process is straightforward and interactive, requiring only a single command to get started.

### Prerequisites

- An existing Asset Layout containing at least one **Text** field
- Permission to modify Asset Layouts and Lists

---

## How It Works

### 1. Select an Asset Layout

You’ll first be prompted to choose the Asset Layout that contains the Text field you want to standardize.

### 2. Choose the Source Field

Next, select the specific **Text** field you’d like to convert.  
Don’t worry—**all existing values are preserved** during the process.

- Every unique value found in the field will be collected
- These values will be used to populate a new (or existing) List

### 3. Review and Confirm

Before any changes are applied, you’ll be asked to confirm your selection.

- If anything doesn’t look correct, you can safely abort the process at this stage using **Ctrl + C**
- No changes are made until confirmation is provided

### 4. Automatic Conversion

Once confirmed, the script will:

- Identify all unique values used in the selected Text field
- Create or update a List containing those values
- Add a new **List Select** field to the Asset Layout
- Migrate all existing asset values from the Text field to the new List Select field

---

## Final Steps

After completion, the script conveniently opens:

- The **Asset Layout administration page**
- The **global asset view** for the selected layout

This makes it easy to verify the results and, if desired, remove the original Text field once you’ve confirmed everything looks correct.

---

## Summary

This approach provides a safe, repeatable way to improve data consistency without manual cleanup or re-entry. It’s ideal for normalizing legacy data and enforcing better structure going forward.

Happy list‑ifying! 🎉
