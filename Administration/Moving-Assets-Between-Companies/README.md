# MoveAssetsBetweenCompanies.ps1

## High-level overview

`MoveAssetsBetweenCompanies.ps1` is an interactive PowerShell will help you move **Hudu Assets** from one company to another based on filter criteria you choose (asset name contains text, a specific asset-layout field contains text, or both). It prompts you through selection, previews what will be moved, performs the move, and writes a **JSON log** of results.

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

## Quick-Start Oneliners

Open a new pwsh7 session on your windows device and perform one of the following:

### the Ninja-Oneliner [Ninja-Style]

```powershell
irm 'https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/refs/heads/main/Administration/Moving-Assets-Between-Companies/MoveAssetsBetweenCompanies.ps1' | iex
```

### Clone+Start [Samurai-Style] (requires git scm installed)

```powershell
git clone https://github.com/Hudu-Technologies-Inc/Community-Scripts; cd .\Community-Scripts\Administration\Moving-Assets-Between-Companies; . .\MoveAssetsBetweenCompanies.ps1;
```

### Download-Extract-Run [Ashigaru-Warrior-Style]

```powershell
Invoke-WebRequest https://codeload.github.com/Hudu-Technologies-Inc/Community-Scripts/zip/refs/heads/main -OutFile Community-Scripts.zip; Expand-Archive -Path .\Community-Scripts.zip; cd .\Community-Scripts\Community-Scripts-main\Administration\Moving-Assets-Between-Companies; . .\MoveAssetsBetweenCompanies.ps1;
```

### Prompts you will see

1. **Enter required Variables (Hudu Base URL and API Key)**
2. **Select company to MOVE FROM**
   - Type **2+ characters** of the company name
   - Script shows a filtered picker list

3. **Select company to MOVE TO**
   - Same picker experience, excluding the source company

4. **Choose criteria**
   - **[1] Asset Name contains text**
   - **[2] Specific Asset Layout Field contains text**
   - **[3] Name contains AND Field contains**

5. If you select **[2]** or **[3]**
   - Select an **Asset Layout**
   - Select a **field** from that layout
   - Enter the text the field must contain

6. **Preview**
   - Script shows up to 20 matching assets (name + ID + layout ID)

7. **Confirm**
   - You must type **MOVE** to proceed

---

## Matching logic

### Option 1 — Name contains (layout-scoped)
Moves assets where:

- `Asset` Name contains the text you enter (wildcard match, case-insensitive)

### Option 2 — Field contains (layout-scoped)
Moves assets where:

- Asset is within the selected layout (to keep field evaluation consistent)
- The selected field’s value contains the text you enter

### Option 3 — Name AND Field (layout-scoped)
Moves assets only if:

- Name contains the text **AND**
- Selected field contains the text

---

## Output / logging

After running, the script prints the output and path to logfile
