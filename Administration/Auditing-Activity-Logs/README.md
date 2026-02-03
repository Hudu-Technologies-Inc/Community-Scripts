# Activity Log Drilldown Helper  
*Interactive Filter + Human‑Readable Formatter*

This script is a small **activity log explorer** for **Hudu**.

Instead of writing individual `Where-Object` filters every time you want to answer questions like:

- *“Show me everything where `record_type` is Article”*
- *“Which user did update actions?”*
- *“What activity happened from this IP?”*
- *“What details were included in those events?”*

…it pulls a sample of activity logs, lets you **pick an attribute**, then **pick a value**, and prints the matching logs back out in a readable, **story‑like format**.

<img width="1561" height="602" alt="image" src="https://github.com/user-attachments/assets/0155a824-b66e-4b8b-a90e-129838191ec8" />

---

## How to Run

Open a new pwsh7 session on your windows device and perform one of the following:

### the Ninja-Oneliner [Ninja-Style]

```powershell
irm 'https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/refs/heads/main/Administration/Auditing-Activity-Logs/Audit-ActivityLogs.ps1' | iex
```

### Clone+Start [Samurai-Style] (requires git scm installed)

```powershell
git clone https://github.com/Hudu-Technologies-Inc/Community-Scripts; cd .\Community-Scripts\Administration\Auditing-Activity-Logs; . .\Audit-ActivityLogs.ps1;
```

### Download-Extract-Run [Ashigaru-Warrior-Style]

```powershell
Invoke-WebRequest https://codeload.github.com/Hudu-Technologies-Inc/Community-Scripts/zip/refs/heads/main -OutFile Community-Scripts.zip; Expand-Archive -Path .\Community-Scripts.zip; cd .\Community-Scripts\Community-Scripts-main\Administration\Auditing-Activity-Logs; . .\Audit-ActivityLogs.ps1;
```

---

## Common Use Cases

- **Audit a single action type**  
  *“Show me all delete actions”*

- **Track changes to a specific record type**  
  *“Only Passwords activity”*

- **Investigate suspicious behavior**  
  *“Everything from IP x.x.x.x”*

- **User troubleshooting**  
  *“What did this user do around that time?”*

- **Client / company review**  
  *“What activity happened under company X?”*

---

## How It Works

### 1. Pulls Activity Logs

You start with a set of activity log records  
(whatever `Get-HuduActivityLogs` returns in your environment).

---

### 2. Builds Drilldown Attributes + Values

The script scans **all properties** present across the returned objects and builds a lookup table like:

- `action` → `{ create, update, delete, … }`
- `record_type` → `{ Article, Asset, Password, … }`
- `user_name` → `{ Mason, Cameron, … }`
- `company_name` → `{ Acme Inc, Contoso, … }`
- `ip_address` → `{ 10.0.0.5, 203.0.113.42, … }`

This lets you **browse the dataset** without memorizing field names.

---

### 3. Interactive Selection

You are prompted to choose:

1. **An attribute** to filter by  
2. **A value** for that attribute

No manual filtering required.

---

### 4. Human‑Readable Output

For each matching activity log entry, the script prints a friendly summary including:

- **Who** did it (name → email fallback logic)
- **What** action occurred
- **Which record** (type + name)
- **Company context**
- **Source** (browser / app + OS)
- **IP address**
- **Details** (if present)
- **Timestamp** (`formatted_datetime`)

The result reads more like an **audit trail** than raw JSON.

After submitting required infos, You’ll see:

1. A numbered list of **attributes** → pick one  
2. A numbered list of **values** → pick one  
3. Matching activity entries printed in **green**

---

## Menu Reference

### Attribute Selection

This answers the question:

> *“Which field do you want to filter on?”*

Common examples:

- `record_type` — Article vs Asset vs Password
- `action` — create / update / delete
- `user_email` / `user_name`
- `company_name`
- `ip_address`
- `app_type`

---

## Why This Exists

Hudu activity logs are powerful — but digging through them manually gets old fast.

This helper turns raw activity data into an **interactive, explorable audit tool** that’s fast, readable, and human‑friendly.
