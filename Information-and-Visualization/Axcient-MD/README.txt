AXCIENT MAGIC DASH

This tool connects your Axcient x360Recover backup data to Hudu. It pulls
backup status from the Axcient API, matches each Axcient client to a company
in Hudu, and writes a Magic Dash for every matched company so your team can
see backup health at a glance. Every protected machine also gets its own Hudu
asset record.

(WHEN MATCHING companies you must hold Control and left click one unmatched
Hudu company and one unmatched Axcient client, then click Manually match
selected. Exact-name matches are already prepared when automatch is on. They
show in green. Review them, then click OK — apply changes. Nothing is written
to Hudu until you click OK. Closing with X cancels the staged changes.)

---------------------------------------------------------------------------

SETUP

Step 1 - Create your API keys

Hudu

1. Log in to your Hudu site as an administrator.
2. Open Admin > API Keys and create a key.
3. Copy the site URL and the key. Setup checks the key as soon as you paste it.

Axcient

1. Log in to the Axcient partner portal.
2. Open https://partner.axcient.com/settings/api-keys
3. Create an x360Recover partner API key and copy it. Setup checks this key
   as soon as you paste it.

Step 2 - Run setup

Extract Axcient-MD.zip. It contains one folder named Axcient-MD. Move that
whole folder somewhere permanent, such as C:\Apps\Axcient-MD. Do not move
individual files out of it.

Run setup.ps1 once on a new computer. Approve the Windows administrator prompt
when asked. Setup collects the Hudu URL, both API keys, dashboard settings,
and company matches, then runs the first sync.

Your keys are stored encrypted for this computer only in config.json inside
the same folder. Do not copy that file to another PC. Run setup again there
and re-enter the keys.

Setup also creates the Hudu asset layout used for device records. Hudu creates
new layouts inactive, so the tool activates it and adds the RichText "Asset
Details" field it writes into. You choose the layout name during setup.

While setup is running it also asks:

  - whether to delete listed unowned legacy "Axcient X360Recover" Magic Dashes
    (No by default; later syncs never delete these)
  - whether to warn about leftover Magic Dashes this tool created on unmatched
    companies (on by default; this is a warning only)
  - how many hours before a backup counts as stale (24 by default)
  - the time zone used to display dates (this computer's time zone by default)
  - whether to auto-match companies that already share the exact same name
  - how often to sync automatically (off, or every 1-48 hours)

When setup finishes, press Enter so the window can close. If setup fails, the
window stays open until you press Enter so the error can be read.

Running setup.ps1 after a configuration already exists does not open a second
setup. It tells you to use run.ps1 instead.

Step 3 - Day to day

Use run.ps1 for everything after setup: changing settings, matching companies,
scheduling, testing connections, and running a sync. If you run run.ps1 before
setup exists, it starts setup for you.

To unmatch a company, select one matched row and choose one of:

  Delete old Magic Dash     remove this tool's dash from the old company
  Move to selected company  recreate it on another Hudu company, then remove
                            the old one
  Cancel                    leave things as they are

One company failing does not stop the rest. The summary at the end lists
matches, updates, unmatched items, warnings, and errors.

Automatic sync uses a Windows task named AXCIENT-MAGIC-DASH Sync. It can run
while you are logged off. Scheduled logs go under logs\ in this folder and are
cleaned up after 30 days. If you move the folder, keep everything together and
run run.ps1. It repairs the scheduled task path.

---------------------------------------------------------------------------

REQUIREMENTS

Windows 10/11, or Windows Server with Desktop Experience. Server Core is not
supported.

PowerShell 7.2 or newer. You do not have to launch it yourself: if you start
setup.ps1 or run.ps1 from Windows PowerShell 5.1, the script finds a
Microsoft-signed PowerShell 7.2+ on the machine and relaunches itself under it,
passing your arguments through. If no suitable PowerShell 7 is installed it
tells you where to get it instead of failing part way through.

Python is bundled. The Runtime folder contains an embedded Python 3.12 that the
Hudu client runs on, so nothing needs installing separately. The bundled runtime
is hash-verified before use.

---------------------------------------------------------------------------

FOLDER STRUCTURE

Axcient-MD/
  run.ps1                          Start here after setup
  setup.ps1                        First-time configuration
  AxcientMagicDash/                Main application
    Private/                       Core helpers, HTML, Hudu bridge
    Public/                        Config, connection, matching, sync, schedule
    Bridge/hudu_bridge.py          Hudu API client
  Modules/AxcientAPI/0.4.0/        Axcient REST client
  Runtime/                         Embedded Python 3.12 (no separate install needed)

---------------------------------------------------------------------------

HOW IT WORKS

Axcient uses different names for some things than you might expect. Here is
how the tool maps them:

  Axcient calls it "client"   = Customer organisation  = shown as Client
  Axcient calls it "device"   = Protected machine      = shown as Device
  Axcient calls it "appliance" = The local backup appliance = shown as Appliance

Devices are grouped into Servers, Workstations, and Other devices. Each row
shows the protection type, operating system, IP address, agent version,
health, local recovery age, cloud recovery age, and vault usage.

BACKUP HEALTH

The Magic Dash tile is green only when Axcient reports the client as NORMAL
and every device on that client is healthy. Otherwise the tile says
"Attention needed". Open the dash for the device counts and the reason.

A device is flagged as a warning when the recovery point for its protection
type is missing, or older than your stale threshold (24 hours by default).
The time zone you chose changes how dates are displayed. It does not change
how stale is calculated.

Axcient does not provide agent online/offline status in the data this tool
uses. Agent status and the Offline count therefore say the value is not
provided, instead of guessing. A permanently empty Offline box would look
like missing data, so the tile shows that the value is unknown.

STORAGE USAGE

Usage totals come from Axcient's per-client usage endpoint. The tool does not
add up every device itself.

The dash shows three figures:

  Local appliance usage  = storage used on the appliances
  Private vault usage    = private vault storage
  Axcient cloud usage    = Axcient cloud storage

Total vault usage is private vault plus Axcient cloud. A figure Axcient does
not return shows as unavailable rather than 0, because those are two different
things. Small amounts are shown in MB or KB rather than 0.0 GB.

PROTECTION METHODS

The protection table counts servers and workstations for the methods this
client actually uses:

  Appliance-based
  D2C
  Cloud Archive

PORTAL LINKS

The client panel links to that client in the Axcient portal. Each device card
links to that device in Axcient.

HUDU ASSET RECORDS

Every matched Magic Dash is written on each sync. There is no create/update
toggle. When a Hudu asset layout is bound, each Axcient device is also
published as one asset on that layout.

Device rows and per-device assets are named "Device Name (Axcient device ID)".
The tool remembers that numeric device ID, so a rename updates the same owned
asset instead of creating a duplicate.

Records the tool created are tagged with an ownership marker. A later sync
updates its own records in place. It will not overwrite a Magic Dash or an
asset it did not create. If it finds an unowned dash titled
"Axcient X360Recover", or an unowned asset with the name it wants, it reports
the collision and leaves that record alone. Rename or remove it in Hudu, then
sync again.

The integration reads Axcient clients, devices, appliances, and usage only.
All create, update, and archive operations target Hudu.

Before the first device-layout bind, setup can offer one optional cleanup for
clearly related, unowned legacy "Axcient X360Recover" dashes. The prompt lists
the candidates and defaults to No. Owned dashes and unrelated dashes with the
same title are excluded. Manual and scheduled sync never run this cleanup.

A spacing-or-punctuation near-match is only a warning. Use run.ps1 company
matching if those two records are the same customer.

The server list uses the space below Basic info. Server and workstation lists
scroll, so a large customer does not make the whole page unmanageable. Long
values wrap inside their cells.

Changing the Hudu URL to a different Hudu instance clears saved matches. Use
the same site URL spelling you used before if you only meant to fix formatting.

---------------------------------------------------------------------------

WHAT IS NOT COVERED

The AxcientAPI module is not on the PowerShell Gallery. It ships in Modules/
and loads from there, and its files are checked against a recorded SHA-256 hash
before use. If that folder is missing or altered, setup stops with a clear
error rather than downloading anything.