# Checklists → Hudu Processes

Convert numbered Microsoft Word **checklist** documents into Hudu **Processes**
(called *Procedures* in the Hudu API). Point the script at a local folder of
`.docx` files — for example a SharePoint or OneDrive library synced into
Windows Explorer — and each document becomes one Hudu process, with each
numbered/bulleted item becoming an ordered task and indented sub-items becoming
subtasks.

This tool follows the same local-files approach as
[Files-Hudu-Migration](../Files-Hudu-Migration): you sync the SharePoint
library locally, then run against the folder. No Azure app registration or
SharePoint Graph credentials are required.

## How a document maps to a process

| Word document | Hudu process |
|---|---|
| Document title (Title/Heading 1 style, or first line, or file name) | Process **name** (leading numbers like `01 - ` stripped) |
| Intro paragraph(s) before the first list item | Process **description** |
| Top-level numbered/bulleted item | **Task** (in document order) |
| Indented sub-item / multi-level number (`1.1`, `a.`) | **Subtask** under the task above it |

Example — `01 - Server Onboarding.docx`:

```
01 - Server Onboarding Checklist        (Title style)
Follow these steps when provisioning…   (intro → description)
1. Rack and cable the server            → Task
2. Install operating system             → Task
   a. Apply latest patches              → Subtask of "Install operating system"
   b. Set hostname                      → Subtask
3. Join the domain                      → Task
   3.1 Verify DNS resolution            → Subtask of "Join the domain"
```

becomes a process **"Server Onboarding Checklist"** with 3 tasks and 3 subtasks.

## Requirements

| Component | Required |
|---|---|
| PowerShell | 7.5.1+ |
| Hudu | **2.41.0+** (needs the process template/run model) |
| Hudu API Key | — |
| Documents | `.docx` / `.docm` |

No LibreOffice needed — `.docx` files are parsed natively (Open-XML). Legacy
binary `.doc` files are **not** supported and are skipped.

On first run the script downloads Hudu's [`HuduAPI` module fork](https://github.com/Hudu-Technologies-Inc/HuduAPI)
(which provides the Process/Procedure cmdlets) and caches it under `.huduapi/`
for subsequent runs — no manual install needed. It tries a GitHub zip download
first, then `git clone`. Override the source with the `HUDUAPI_REPOSITORY_URL`,
`HUDUAPI_REPOSITORY_BRANCH`, or `HUDUAPI_ZIP_URL` environment variables if your
environment is locked down.

## Usage

```powershell
# Simplest: prompts for folder, Hudu URL/key, and scoping
. .\Checklists-To-Processes.ps1

# Global templates from a synced folder
. .\Checklists-To-Processes.ps1 -TargetDocumentDir 'C:\Sync\Team Checklists' -DestinationStrategy GlobalTemplate

# Recurse a client tree, map each doc to a company by its parent folder name,
# and add any new tasks to processes that already exist
. .\Checklists-To-Processes.ps1 -TargetDocumentDir 'X:\Clients' -Recurse `
    -DestinationStrategy ByFolderName -OnExisting Update

# Preview only — parse and report, write nothing to Hudu
. .\Checklists-To-Processes.ps1 -TargetDocumentDir 'C:\Sync\Checklists' -DryRun
```

### Parameters

| Parameter | Description |
|---|---|
| `-TargetDocumentDir` | Folder containing the checklist `.docx` files. Prompted if omitted. |
| `-Filter` | File-name wildcard (e.g. `"*.docx"`, `"1*"`). Default: docs whose **name starts with a number** (see `config.ps1`). |
| `-Recurse` | Search subdirectories (depth `-MaxDepth`, default 5). |
| `-DestinationStrategy` | `GlobalTemplate`, `SingleCompany`, `VariousCompanies`, `ByFolderName`, `ByFileName`. Prompted if omitted. |
| `-SubItemHandling` | `Subtask` (default), `Description`, `TopLevel`. How indented sub-items are mapped. |
| `-OnExisting` | `Skip` (default), `Update`, `Replace`, `Recreate`. Behaviour when a process of the same name already exists in the target scope. |
| `-OnNoCompanyMatch` | `Prompt` (default), `Skip`, `Global`. Used by `ByFolderName`/`ByFileName` when no company name matches. |
| `-MaxItems` | Cap on documents processed in one run. Default 1000. |
| `-DryRun` | Parse and report without writing to Hudu. |
| `-HuduBaseURL` / `-HuduAPIKey` | Provide non-interactively; otherwise prompted. |

## Scoping strategies

- **GlobalTemplate** — one reusable global template per checklist (`company_id = null`), available to all companies. Best for standard team SOPs.
- **SingleCompany** — every document goes to one company you pick at the start.
- **VariousCompanies** — you choose a company (or global) for each document at runtime.
- **ByFolderName** — the document's **parent folder name** is fuzzy-matched to a Hudu company name.
- **ByFileName** — the document's **file name** (numbers stripped) is fuzzy-matched to a company name.

Fuzzy matching threshold and behaviour-on-no-match are configurable in
`config.ps1` / via `-OnNoCompanyMatch`.

## Idempotency

Re-running is safe at the **process** level: a process is matched by name within
its scope (global vs a specific company).

- `Skip` *(default)* — existing processes are left untouched.
- `Update` — adds only tasks/subtasks that don't already exist (matched by name).
- `Replace` — deletes the existing process's tasks and recreates them from the doc.
- `Recreate` — always creates a new process (may produce duplicates).

> Task matching for `Update` is by **name**. Renaming a step in the source doc
> will add a new task rather than rename the old one. Use `Replace` if you want
> the document to be the single source of truth for the task list.

## Output

Each run writes to `runs\<timestamp>\`:
- `run.log` — full activity log
- `summary.json` — per-document result (action, process id, tasks/subtasks created, errors)

## Configuration

Edit `config.ps1` to change supported extensions, the "numbered name" pattern,
default sub-item handling, default `OnExisting`/`OnNoCompanyMatch`, the company
match threshold, and which Word styles are treated as the document title.

## Layout

```
Checklists-To-Processes.ps1   # entry point / orchestration
config.ps1                    # defaults & tunables
helpers/
  init.ps1                    # PowerShell/Hudu checks + HuduAPI module download/bootstrap
  general.ps1                 # logging, prompts, fuzzy name matching, name cleaning
  docx.ps1                    # native Open-XML checklist parser
  processes.ps1               # create/update Hudu processes & tasks (incl. subtasks)
  destination.ps1             # company-scoping strategies
.huduapi/                     # (gitignored) HuduAPI module fork, downloaded on first run
```
