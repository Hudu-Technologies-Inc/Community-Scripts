# AXCIENT MAGIC DASH

Connects Axcient x360Recover backup data to Hudu. For each **matched** Hudu company, the tool updates a Magic Dash titled **Axcient X360Recover** and can create one Hudu asset per protected device on the layout you bind during setup.

The tool runs in PowerShell. A separate graphical window opens only when you link Axcient clients to Hudu companies.

---

## Before you start

1. Extract **`Axcient-MD.zip`**. It contains one folder named **`Axcient-MD`**.
2. Move the complete **`Axcient-MD`** folder somewhere permanent, such as `C:\Apps\Axcient-MD`. Do not move individual files out of it. Everything in that folder is required to run and update the integration.
3. Install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) (**7.2 or newer**) if it is not already installed. The MSI install is recommended so `C:\Program Files\PowerShell\7\pwsh.exe` exists.
4. Have ready:
   - your **Hudu site URL** (same spelling you use in the browser)
   - a **Hudu administrator API key**
   - an **Axcient x360Recover partner API key**

**Supported Windows:** Windows 10/11, or Windows Server with **Desktop Experience**. Server Core is not supported.

**Python:** Bundled inside the folder. Do not install or substitute another Python.

**Elevation:** Setup and the run menu use a one-time administrator prompt so keys can be protected and the scheduled task can be registered. That is expected.

---

## Which script should I use?

| Situation | Script |
| --- | --- |
| First time on this PC | **`setup.ps1`** |
| Everything after that | **`run.ps1`** |

**`setup.ps1`** runs once: stores keys, binds the device asset layout, sets dashboard options, opens company matching, and runs the first sync.

**`run.ps1`** is the day-to-day menu: sync, keys, settings, matching, schedule, connection tests, and device layout actions.

If **`config.json`** already exists, **`setup.ps1`** does not open a second management workflow—it tells you to use **`run.ps1`**.

**Command-line shortcuts** (from the `Axcient-MD` folder):

| Goal | Command |
| --- | --- |
| Open the main menu | `.\run.ps1` |
| Sync immediately (no menu) | `.\run.ps1 -Sync` |
| Change only the automatic schedule | `.\run.ps1 -Schedule` |

If you run **`run.ps1`** before any configuration exists, it starts first-time setup for you.

---

## First-time setup (step by step)

1. Open the **`Axcient-MD`** folder in File Explorer.
2. Right-click **`setup.ps1`** → **Run with PowerShell**, **or** open PowerShell 7 in that folder and run:

   ```powershell
   .\setup.ps1
   ```

3. Approve the **Windows administrator** prompt when asked.
4. Work through the prompts **in order**:

   **Hudu**

   1. **Hudu URL** — paste the full URL from your browser address bar. The tool normalizes it and checks that the site responds.
   2. **Hudu API key** — pasted masked; tested immediately against Hudu. If it fails, you can fix the URL or key without restarting setup.

   **Axcient**

   3. **Axcient API key** — partner key; tested immediately. You can paste a corrected key on the same screen if the first attempt fails.

   **Optional legacy cleanup**

   4. If the tool finds **unowned** legacy Magic Dashes titled **Axcient X360Recover**, it lists them and asks whether to delete them. Default is **No**. Only dashes this tool can identify as unowned legacy candidates are listed; it will not delete dashes it owns or unrelated same-title dashes.

   **Device asset layout** (required for per-device Hudu assets)

   5. Choose one:
      - **1 — Create a new Hudu asset layout** — you supply a name; the tool creates the layout, adds a RichText field named **Asset Details**, and **activates** the layout (new Hudu layouts start inactive).
      - **2 — Use an existing Hudu asset layout** — you connect by layout ID. The tool adds **Asset Details** if missing and leaves your other fields unchanged, then activates the layout if needed.
      - **Q** — cancel layout binding for now (you can bind later with **`run.ps1`** option **9**). Magic Dashes can still sync; device assets will not be created until a layout is bound.

   **Magic Dash settings**

   6. **Orphan warnings** — when **Yes**, each sync also **warns** if an **unmatched** Hudu company still has a Magic Dash **this tool created**. It never deletes those dashes automatically.
   7. **Stale backup threshold** — hours before a recovery point counts as “old” on the dashboard (default **24**). Enter a whole number from **1** through **720**, or press Enter to keep the current value.
   8. **Dashboard time zone** — dates on the dash use this zone. Type **K** to keep the current zone, **L** to list all zones, then enter a zone **ID**, a list **number**, or paste a full list row. Pressing Enter alone does **not** skip this step.

   **Matching and schedule**

   9. **Exact-name automatch** — when **Yes**, on future runs the matching window pre-links Hudu companies and Axcient clients whose names match exactly (pairs you explicitly unmatched stay excluded).
   10. **Automatic sync** — **off**, or every **1–48** hours. If enabled, a Windows task **`AXCIENT-MAGIC-DASH Sync`** is created after setup completes successfully.

   **Company matching**

   11. The **matching window** opens (see below). Review matches, click **OK — apply changes** to save and run the **first sync**.

5. When setup finishes successfully, press **Enter** to close the window. If setup fails, the window stays open until you press **Enter** so you can read the error.

**Where settings live:** **`config.json`** in the same folder. API keys are encrypted for **this Windows user on this PC** (DPAPI). Do not copy **`config.json`** to another machine—run **`setup.ps1`** there and enter keys again.

**Incomplete setup:** If you cancel matching or the first sync reports errors, setup is marked incomplete. Open **`run.ps1`** and use option **5** to finish matching and a clean sync before option **7** (sync now) or automatic scheduling fully applies.

---

## Company matching (graphical window)

Open from first-time setup or from **`run.ps1`** → option **5**.

**Columns:** Hudu company, Axcient client, match state, and current connection.

**Automatch (green “Matched” rows):** When exact-name automatch is on, those pairs are prepared for you. Review them; you do not need to select them or click **Manually match selected**. Click **OK — apply changes** to save and sync.

**Match manually**

1. Click one **unmatched** Hudu row (it highlights; the **Selected** column shows your pick).
2. Click one **unmatched** Axcient row.
3. Click **Manually match selected**.

Use **plain clicks only**—no Ctrl, Shift, or other modifier keys. Clicking another row on the same side changes your selection; clicking the same row again clears it.

**Unmatch**

Select a matched pair, then choose:

- **Delete old Magic Dash** — removes this tool’s Magic Dash from the old Hudu company.
- **Move to selected company** — recreates the dash on another Hudu company you select, then removes it from the old one.
- **Cancel** — leave matches unchanged.

**Important**

- Nothing is written to Hudu until you click **OK — apply changes**. Closing with **X** cancels staged changes.
- After **OK**, the tool saves matches, applies unmatch actions you confirmed, runs a sync, and prints a summary in the console.
- If Hudu already has a Magic Dash titled **Axcient X360Recover** that **this tool did not create**, the tool will **not** overwrite it. Rename or remove that dash in Hudu, then try again.
- Duplicate Hudu company names block **Move** operations—Hudu targets companies by name for Magic Dash writes. Resolve duplicates in Hudu first.

---

## Using the run menu (`run.ps1`)

Start the menu:

```powershell
cd C:\Apps\Axcient-MD   # your path
.\run.ps1
```

Each time the menu opens, it prints **Current AXCIENT-MAGIC-DASH configuration** (URL, stale hours, time zone, match count, layout, schedule, and whether initial setup is complete). Then choose an option:

| Option | What it does |
| --- | --- |
| **1** | Change **Hudu URL and API key**. Keys are tested before save. Changing to a **different Hudu site** clears matches, automatch exclusions, pending operations, and the device layout binding so IDs are not reused across instances. |
| **2** | Change **Axcient API key**. If you have saved matches, the tool warns that a key for a **different partner** could make saved client IDs wrong; you can keep or clear matches. Key change is blocked while **pending** unmatch move/delete operations are still journaled—finish matching first. |
| **3** | Change **Magic Dash settings**: orphan warnings, stale backup hours, dashboard time zone (same **K** / **L** rules as setup). If the saved time zone is unavailable on this PC, fix it here before sync writes continue. |
| **4** | Change **automatic sync** interval (off or every 1–48 hours) and reconcile the Windows scheduled task. If initial setup is incomplete, the interval is saved but the task stays disabled until option **5** completes successfully. |
| **5** | Open **company matching**, then apply decisions and **sync**. Use this to finish interrupted first-time setup or to add/remove matches later. |
| **6** | **Test** stored Hudu and Axcient connections without syncing. |
| **7** | **Full sync now** (all matched companies). Requires **setup complete**. One company failing does not stop the rest; read the summary at the end. |
| **8** | Turn **exact-name automatch** on or off for future matching sessions. Does not override existing matches or re-include pairs you explicitly unmatched. |
| **9** | **Device asset layout**: create new, connect existing, **repair** inactive layout or missing **Asset Details**, or recover if the layout was deleted in Hudu. Optional legacy Magic Dash cleanup may be offered when binding from an unbound state. |
| **S** | Save and exit. |
| **Q** | Exit (changes you already accepted in the menu are saved). |

**While the menu is open:** Each accepted change is written to **`config.json`** as you go. **Q** does not roll back saves from earlier options in the same session.

**One operation at a time:** Only one setup session, menu action, manual sync, or scheduled sync runs at a time across users on the PC. You may briefly see extra PowerShell or administrator windows during elevation; that is normal.

**After a sync:** Read the colored summary in the console. Detailed transcripts are under **`logs\sync-*.log`** (API keys redacted). Logs older than 30 days are removed automatically.

---

## Automatic sync (scheduled task)

- Task name: **`AXCIENT-MAGIC-DASH Sync`**
- Registered when setup completes cleanly and you chose an interval.
- Can run while you are logged off; it does not store your Windows password.
- If you **move** the `Axcient-MD` folder, run **`run.ps1`** once so the task path can be repaired.
- To verify manually: exit the run menu, then in PowerShell (as the same user that configured the tool):

  ```powershell
  Start-ScheduledTask -TaskName 'AXCIENT-MAGIC-DASH Sync' -TaskPath '\'
  ```

  Wait for the task to finish, then check the newest file in **`logs\`**.

If a scheduled run starts while you are in the menu or another sync is running, it waits (up to 15 minutes) rather than overlapping Hudu writes.

---

## What gets updated in Hudu

**Magic Dash (every matched company, every sync)**

- Title: **Axcient X360Recover**
- Company-level summary: healthy / warning / unknown device counts, storage usage where Axcient provides it, and device lists (protection type, OS/IP, agent version, health, local and cloud recovery ages, usage).
- Server and workstation sections scroll when lists are long so the page stays usable.

**Device assets (when a layout is bound)**

- One **owned** asset per Axcient device on your chosen layout, with the same health and detail as on the dash.
- Display name format: **`Device Name (Axcient device ID)`** so renames update the same asset instead of creating duplicates.
- The tool updates **only assets it created** (ownership marker). It will not overwrite unrelated assets; name collisions are reported in the sync summary.

**Health and warnings**

- A device shows **warning** when a recovery point for its protection type is missing or older than your **stale** threshold.
- Dates on the dash use your chosen **time zone**; that does not change how stale is calculated.
- Axcient does not provide reliable agent online/offline status in the data this tool uses, so those fields say **not provided** rather than guessing.

**Orphan warnings (optional setting)**

- When enabled, sync **warns** if an unmatched Hudu company still has an **owned** **Axcient X360Recover** dash. It does **not** delete it.

**Near-name warnings**

- If an Axcient client and a Hudu company look like the same customer except for spacing or punctuation, sync may warn. Use option **5** to match them manually if they are the same.

---

## Optional Hudu CSS
The Magic Dash includes its own styling. You do not need extra CSS.

---

## Troubleshooting

| Problem | What to do |
| --- | --- |
| **PowerShell 7 missing** | Install 7.2+ from [aka.ms/powershell-release](https://aka.ms/powershell-release?tag=stable). Starting **`setup.ps1`** or **`run.ps1`** from File Explorer or Windows PowerShell 5.x is fine when 7.2+ is installed; scripts restart under **`pwsh`**. Store-only installs may fail until the MSI is present. |
| **SmartScreen / “from another computer”** | Unblock the extracted folder, then run setup again. From the `Axcient-MD` folder run `Get-ChildItem -LiteralPath . -Recurse -File -Force` piped to `Unblock-File`. |
| **Antivirus blocks `python.exe`** | Allow the whole **`Axcient-MD`** folder. Do not replace bundled files. |
| **Key or URL rejected** | Fix at the prompt, or after setup use menu options **1** or **2**. |
| **“Initial setup incomplete”** | Use menu option **5** to complete matching and a sync without errors. Option **7** stays blocked until then. |
| **Layout inactive or missing Asset Details** | Menu option **9** → repair activates the layout and adds **Asset Details** if missing. |
| **Layout deleted in Hudu** | Option **9** → create new, connect another layout by ID, or stay disconnected. |
| **Wrong company linked** | Option **5** → unmatch or move. |
| **Dash missing or stale** | `.\run.ps1 -Sync` or option **7**; read the summary for that company. |
| **Schedule will not run** | Option **4** to reconcile; ensure setup is complete. |
| **Moved the folder** | Keep all files together; run **`run.ps1`** to repair the scheduled task path. |
| **Window closes or ignores input** | Use an **interactive** PowerShell window. Piped input is rejected so secrets do not leak into later prompts. |
| **Stale elevation snapshot** | Close the failed window; delete only `%TEMP%\AXCIENT-MAGIC-DASH-*.snapshot` for your Windows user. |

