# DATTO BCDR MAGIC DASH

Connects Datto BCDR backup data to Hudu. For each **matched** Hudu company, the tool updates a Magic Dash titled **Datto BCDR** and can create one Hudu asset per protected machine on the layout you bind during setup.

The tool runs in PowerShell. A separate graphical window opens only when you link Datto clients to Hudu companies.

---

## Before you start

1. Extract **`Datto-BCDR-MD.zip`**. It contains one folder named **`Datto-BCDR-MD`** (with **`setup.ps1`** and **`run.ps1`** at the top of that folder).
2. Move the complete **`Datto-BCDR-MD`** folder somewhere permanent, such as `C:\Apps\Datto-BCDR-MD`. Do not move individual files out of it. Everything in that folder is required to run and update the integration.
3. Install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) (**7.2 or newer**) if it is not already installed. The MSI install is recommended so `C:\Program Files\PowerShell\7\pwsh.exe` exists.
4. Have ready:
   - your **Hudu site URL** (same spelling you use in the browser)
   - a **Hudu administrator API key**
   - **Datto REST API public and private keys** (see **Create your Datto API key** below)

**Supported Windows:** Windows 10/11, or Windows Server with **Desktop Experience**. Server Core is not supported.

**Python:** Bundled inside the **`Runtime`** folder (embedded Python 3.12 for Hudu API calls). Do not install or substitute another Python. The distribution is checked before use; do not delete or alter files inside the extracted folder.

**Elevation:** Setup and the run menu use a one-time administrator prompt so keys can be protected and the scheduled task can be registered. That is expected.

**Launcher behavior:** If you start **`setup.ps1`** or **`run.ps1`** from File Explorer or Windows PowerShell 5.1, the script finds a Microsoft-signed PowerShell 7.2+ on the machine and restarts itself under that version. If none is installed, it tells you where to get it instead of failing halfway through.

---

## Which script should I use?

| Situation | Script |
| --- | --- |
| First time on this PC | **`setup.ps1`** |
| Everything after that | **`run.ps1`** |

**`setup.ps1`** runs once: stores keys, binds the device asset layout, sets dashboard options, opens company matching, and runs the first sync.

**`run.ps1`** is the day-to-day menu: sync, keys, settings, matching, schedule, connection tests, and device layout actions.

If **`config.json`** already exists, **`setup.ps1`** does not open a second management workflow—it tells you to use **`run.ps1`**.

**Command-line shortcuts** (from the inner **`Datto-BCDR-MD`** folder where **`run.ps1`** lives):

| Goal | Command |
| --- | --- |
| Open the main menu | `.\run.ps1` |
| Sync immediately (no menu) | `.\run.ps1 -Sync` |
| Change only the automatic schedule | `.\run.ps1 -Schedule` |

If you run **`run.ps1`** before any configuration exists, it starts first-time setup for you.

---

## Create your Datto API key

1. Log in to the [Datto Partner Portal](https://auth.datto.com/login).
2. Go to **Admin → Integrations → API Keys**.
3. Create a new key. Leave the **vendor/organisation dropdown blank**. A key scoped to one organisation cannot read the partner-wide data this tool needs; failures often look like a permissions problem instead of a bad key.
4. Copy the **public** key and the **private** key. You will paste both during setup.

During setup the tool combines them into one **`publicKey:privateKey`** credential, stores it encrypted for this PC (DPAPI), and tests the connection. You do not manage the two halves separately after that.

---

## First-time setup (step by step)

1. Open the **`Datto-BCDR-MD`** folder (the one that contains **`setup.ps1`**) in File Explorer.
2. Right-click **`setup.ps1`** → **Run with PowerShell**, **or** open PowerShell 7 in that folder and run:

   ```powershell
   .\setup.ps1
   ```

3. Approve the **Windows administrator** prompt when asked.
4. Work through the prompts **in order**:

   **Hudu**

   1. **Hudu URL** — paste the full URL from your browser address bar. The tool normalizes it and checks that the site responds.
   2. **Hudu API key** — pasted masked; tested immediately against Hudu.

   **Datto**

   3. **Datto public key** and **Datto private key** — pasted masked; combined and tested immediately. You can paste corrected keys on the same screen if the first attempt fails.

   **Optional legacy cleanup**

   4. If the tool finds **unowned** legacy Magic Dashes it can identify, it lists them and asks whether to delete them. Default is **No**. It will not delete dashes it owns or unrelated same-title dashes.

   **Device asset layout** (required for per-device Hudu assets)

   5. Choose one:
      - **1 — Create a new Hudu asset layout** — you supply a name; the tool creates the layout, adds a RichText field named **Asset Details**, and **activates** the layout (new Hudu layouts start inactive).
      - **2 — Use an existing Hudu asset layout** — you connect by layout ID. The tool adds **Asset Details** if missing and leaves your other fields unchanged, then activates the layout if needed.
      - **Q** — cancel layout binding for now (bind later with **`run.ps1`** option **9**). Magic Dashes can still sync; device assets will not be created until a layout is bound.

   **Magic Dash settings**

   6. **Orphan warnings** — when **Yes**, each sync also **warns** if an **unmatched** Hudu company still has a Magic Dash **this tool created**. It never deletes those dashes automatically.
   7. **Stale backup threshold** — hours before a backup counts as “old” on the dashboard (default **24**). Enter a whole number from **1** through **720**, or press Enter to keep the current value.
   8. **Dashboard time zone** — dates on the dash use this zone. Type **K** to keep the current zone, **L** to list all zones, then enter a zone **ID**, a list **number**, or paste a full list row. Pressing Enter alone does **not** skip this step.

   **Matching and schedule**

   9. **Exact-name automatch** — when **Yes**, on future runs the matching window pre-links Hudu companies and Datto clients whose names match exactly (pairs you explicitly unmatched stay excluded).
   10. **Automatic sync** — **off**, or every **1–48** hours. If enabled, a Windows task **`DATTO-BCDR-MAGIC-DASH Sync`** is created after setup completes successfully.

   **Company matching**

   11. The **matching window** opens (see below). Review matches, click **OK — apply changes** to save and run the **first sync**.

5. When setup finishes successfully, press **Enter** to close the window. If setup fails, the window stays open until you press **Enter** so you can read the error.

**Where settings live:** **`config.json`** in the same folder as **`setup.ps1`**. API keys are encrypted for **this Windows user on this PC** (DPAPI). Do not copy **`config.json`** to another machine—run **`setup.ps1`** there and enter keys again.

**Incomplete setup:** If you cancel matching or the first sync reports errors, setup is marked incomplete. Open **`run.ps1`** and use option **5** to finish matching and a clean sync before option **7** (sync now) or automatic scheduling fully applies.

**Migrating from an old deployment:** If the tool finds a legacy **`Hudu-Datto-Dashboard`** configuration nearby, it may offer to import settings. Import is copy-only; retire the old deployment and remove its plaintext keys manually when ready.

---

## Company matching (graphical window)

Open from first-time setup or from **`run.ps1`** → option **5**.

**Columns:** Hudu company, Datto client, match state, and current connection.

**Automatch (green “Matched” rows):** When exact-name automatch is on, those pairs are prepared for you. Review them; you do not need to select them or click **Manually match selected**. Click **OK — apply changes** to save and sync.

**Match manually**

1. Click one **unmatched** Hudu row (it highlights; the **Selected** column shows your pick).
2. Click one **unmatched** Datto row.
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
- If Hudu already has a Magic Dash titled **Datto BCDR** that **this tool did not create**, the tool will **not** overwrite it. Rename or remove that dash in Hudu, then try again.
- Duplicate Hudu company names block **Move** operations—resolve duplicates in Hudu first.

---

## Using the run menu (`run.ps1`)

Start the menu from the folder that contains **`run.ps1`**:

```powershell
cd C:\Apps\Datto-BCDR-MD\Datto-BCDR-MD   # your path
.\run.ps1
```

Each time the menu opens, it prints **Current DATTO-BCDR-MAGIC-DASH configuration** (URL, stale hours, time zone, match count, layout, schedule, and whether initial setup is complete). Then choose an option:

| Option | What it does |
| --- | --- |
| **1** | Change **Hudu URL and API key**. Keys are tested before save. Changing to a **different Hudu site** clears matches, automatch exclusions, pending operations, and the device layout binding. |
| **2** | Change **Datto API keys** (public + private, stored as one credential). If you have saved matches, the tool warns that keys for a **different partner** could make saved client IDs wrong; you can keep or clear matches. Key change is blocked while **pending** unmatch move/delete operations are still journaled—finish matching first. |
| **3** | Change **Magic Dash settings**: orphan warnings, stale backup hours, dashboard time zone (same **K** / **L** rules as setup). If the saved time zone is unavailable on this PC, fix it here before sync writes continue. |
| **4** | Change **automatic sync** interval (off or every 1–48 hours) and reconcile the Windows scheduled task. If initial setup is incomplete, the interval is saved but the task stays disabled until option **5** completes successfully. |
| **5** | Open **company matching**, then apply decisions and **sync**. Use this to finish interrupted first-time setup or to add/remove matches later. |
| **6** | **Test** stored Hudu and Datto connections without syncing. |
| **7** | **Full sync now** (all matched companies). Requires **setup complete**. One company failing does not stop the rest; read the summary at the end. |
| **8** | Turn **exact-name automatch** on or off for future matching sessions. |
| **9** | **Device asset layout**: create new, connect existing, **repair** inactive layout or missing **Asset Details**, or recover if the layout was deleted in Hudu. |
| **S** | Save and exit. |
| **Q** | Exit (changes you already accepted in the menu are saved). |

**While the menu is open:** Each accepted change is written to **`config.json`** as you go.

**One operation at a time:** Only one setup session, menu action, manual sync, or scheduled sync runs at a time on the PC.

**After a sync:** Read the colored summary in the console. Detailed transcripts are under **`logs\sync-*.log`** (API keys redacted). Logs older than 30 days are removed automatically.

---

## Automatic sync (scheduled task)

- Task name: **`DATTO-BCDR-MAGIC-DASH Sync`**
- Registered when setup completes cleanly and you chose an interval.
- Can run while you are logged off; it does not store your Windows password.
- If you **move** the project folder, run **`run.ps1`** once so the task path can be repaired.
- To trigger a run manually (same user that configured the tool), exit the run menu first, then:

  ```powershell
  Start-ScheduledTask -TaskName 'DATTO-BCDR-MAGIC-DASH Sync' -TaskPath '\'
  ```

  Wait for the task to finish, then check the newest file in **`logs\`**.

If a scheduled run starts while you are in the menu or another sync is running, it waits rather than overlapping Hudu writes.

---

## What the Magic Dash shows

### Datto names vs the dashboard

| Datto API term | Meaning | On the dash |
| --- | --- | --- |
| **client** | Customer organisation | **Client** |
| **asset** | Protected machine | **Device** |
| **device** | BCDR appliance | **Appliance** |

### Tile and device health

Datto does not expose one simple healthy/unhealthy flag per machine. The tool derives status:

| Status | Meaning |
| --- | --- |
| **ARCHIVED** | Machine is archived in Datto |
| **PAUSED** | Backups are paused |
| **NO BACKUP** | No backup has ever run |
| **NORMAL** | Looks healthy |

A device also shows **warning** when its last backup is older than your **stale** threshold (default 24 hours).

**Appliances** may show **ALERTS** (Datto’s alert count above zero), **TICKETS OPEN**, or **OFFLINE** (no check-in within 24 hours).

The Magic Dash **tile** is green only when every device is healthy and every appliance behind that client is normal. Otherwise it shows **Attention needed**. Client-level health is calculated from devices and appliances, not read as a single Datto field.

**Alert rules panel:** Each appliance can list **configured** alert rules (thresholds and last trigger time). That is configuration history, not a live problem list. Appliance badges use Datto’s **alert count**, not the rule list, so old rule triggers do not mark healthy appliances as failing.

### Screenshot verification

Device rows show Datto **screenshot backup verification** (whether the recovery point booted):

| State | Meaning |
| --- | --- |
| **Verified** | Recovery point booted |
| **Failed** | Recovery point did not boot |
| **Not attempted** | Datto has not tried yet (not the same as pass) |

When Datto captured an image, the badge can link to it. The summary shows counts such as **17 / 20**. File **shares** are excluded from that ratio (no bootable recovery point). There is no per-device **Offline** count—Datto does not report that in a useful way here.

### Agents, shares, and volumes

**Agents** and **shares** are loaded from dedicated Datto endpoints when possible so each row is labeled correctly. If those calls fail, the tool falls back to the combined asset list so agents are not hidden.

**Volumes** come from each asset. The **Volumes** column is green when all volumes are protected and amber when not, listing **unprotected volume names** (not just a count).

### VM restores

Active VM restores are matched to devices when possible (volume hash, then name). In-progress restores show a badge on the device row; unmatched restores still appear in the restore section. “Nothing running” and “could not read data” are shown differently.

### Storage and portal links

**Storage** totals add usage across the client’s appliances (**local appliance** and **Datto cloud**). Missing figures show as **Unknown**, not zero. Storage is per appliance, not per machine.

Rows link to the Datto portal using URLs Datto returns on appliance records; if none is returned, the link falls back to the Datto login page.

### Hudu device assets

When a layout is bound, each device can appear as a **owned** Hudu asset with the same health, volumes, screenshot, and restore details as on the dash. The tool updates **only assets it created**; name collisions with unowned assets are reported and left untouched.

---

## Limitations

**Direct-to-Cloud (DTC):** DTC-protected machines are **not** listed on the BCDR dashboard yet. Sync **warns** if your account has DTC assets so they are not silently ignored.

**VM restore payloads:** Restore field names are matched flexibly. If Datto returns an unusual shape, restores still appear in the panel when possible rather than disappearing.

**Distribution integrity:** The Datto API module ships inside the folder (not from the PowerShell Gallery). If **`Modules`** or **`Runtime`** is missing or altered, setup stops with a clear error—restore the complete zip.

---

## Optional Hudu CSS
The Magic Dash includes its own styling. You do not need to make any modifications.


---

## Troubleshooting

| Problem | What to do |
| --- | --- |
| **PowerShell 7 missing** | Install 7.2+ from [aka.ms/powershell-release](https://aka.ms/powershell-release?tag=stable). MSI recommended. |
| **SmartScreen / “from another computer”** | Unblock the extracted folder, then run setup again. From the project folder run `Get-ChildItem -LiteralPath . -Recurse -File -Force` piped to `Unblock-File`. |
| **Antivirus blocks `python.exe`** | Allow the whole **`Datto-BCDR-MD`** folder. Do not replace bundled files. |
| **Datto key rejected** | Confirm the organisation dropdown was **blank** when the key was created; re-paste public and private keys (menu option **2**). |
| **Hudu key or URL rejected** | Fix at the prompt, or use menu option **1**. |
| **“Initial setup incomplete”** | Option **5** to complete matching and a sync without errors. Option **7** stays blocked until then. |
| **Layout inactive or missing Asset Details** | Option **9** → repair. |
| **Layout deleted in Hudu** | Option **9** → create new, connect another layout, or stay disconnected. |
| **Wrong company linked** | Option **5** → unmatch or move. |
| **Dash missing or stale** | `.\run.ps1 -Sync` or option **7**; read the summary for that company. |
| **Schedule will not run** | Option **4**; ensure setup is complete. |
| **Moved the folder** | Keep all files together; run **`run.ps1`** to repair the scheduled task path. |
| **Window closes or ignores input** | Use an **interactive** PowerShell window. Piped input is rejected. |
| **Stale elevation snapshot** | Close the failed window; delete `%TEMP%\DATTO-BCDR-MAGIC-DASH-*.snapshot` for your Windows user if warned. |

License notices for bundled components are in **`THIRD_PARTY_NOTICES.md`**.
