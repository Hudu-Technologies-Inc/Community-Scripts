DATTO BCDR MAGIC DASH

This tool connects your Datto BCDR backup data to Hudu. It pulls backup status
from the Datto API, matches each Datto client to a company in Hudu, and writes
a Magic Dash for every matched company so your team can see backup health at a
glance. Every protected machine also gets its own Hudu asset record.

(WHEN MATCHING companies you must hold Control and left click one unmatched
Hudu company and one unmatched Axcient client, then click Manually match
selected. Exact-name matches are already prepared when automatch is on. They
show in green. Review them, then click OK — apply changes. Nothing is written
to Hudu until you click OK. Closing with X cancels the staged changes.)
---------------------------------------------------------------------------

SETUP

Step 1 - Create your API key

1. Log in to the Datto Partner Portal.
2. Go to Admin > Integrations > API Keys.
3. Create a new key. Leave the vendor/organisation dropdown blank. A key
   scoped to a single organisation cannot read the partner-wide data this
   tool needs, and the error you get will look like a permissions problem
   rather than a key issue.
4. Copy the public key and the private key.

Step 2 - Run setup

Run setup.ps1 and enter both keys when prompted. The tool combines them into
a single publicKey:privateKey credential and stores it securely using DPAPI.
You do not need to handle them separately after this.

Setup also creates the Hudu asset layout used for device records. Hudu creates
new layouts inactive, so the tool activates it and adds the RichText "Asset
Details" field it writes into.

Step 3 - Day to day

Use run.ps1 for everything after setup: changing settings, matching companies,
scheduling, testing connections, and running a sync.

---------------------------------------------------------------------------

REQUIREMENTS

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

Datto-BCDR-MD/
  run.ps1                          Start here to run the tool
  setup.ps1                        First-time configuration and menus
  DattoBcdrMagicDash/              Main application
    Private/                       Core helpers, HTML, Hudu bridge
    Public/                        Config, connection, matching, sync, schedule
    Bridge/hudu_bridge.py          Hudu API client
  Modules/DattoBcdrAPI/1.0.0/      Datto REST client
  Runtime/                         Embedded Python 3.12 (no separate install needed)
 ---------------------------------------------------------------------------


HOW IT WORKS

Datto uses different names for some things than you might expect. Here is
how the tool maps them:

  Datto calls it "client"  = Customer organisation  = shown as Client
  Datto calls it "asset"   = Protected machine      = shown as Device
  Datto calls it "device"  = The BCDR appliance     = shown as Appliance

BACKUP HEALTH

Datto does not have a single healthy/unhealthy field per machine, so the
tool determines health from the available data:

  Machine is archived            = ARCHIVED
  Machine is paused              = PAUSED
  No backup has ever run         = NO BACKUP
  Everything looks fine          = NORMAL

A machine is also flagged as a warning when its last backup is older than your
configured stale threshold (24 hours by default).

Appliances show as ALERTS when Datto's own alert count for that appliance is
above zero, TICKETS OPEN when Datto reports open tickets, and OFFLINE when the
appliance has not checked in within the last 24 hours.

The Magic Dash tile itself is green only when every device is healthy and every
appliance behind it is normal. Otherwise it shows "Attention needed". Datto does
not publish a client-level health field, so this is derived from the devices and
appliances rather than read from the API.

ALERT RULES

The tool shows the alert rules each appliance has configured - what it is set to
alert on, the threshold, and when that rule last fired. This is a configuration
panel, not a list of current problems.

This distinction matters. Datto's per-appliance alert endpoint returns configured
rules rather than firing alerts, and those records carry no machine name, no
volume and no message. An appliance seen two minutes ago can still list a
60-minute "Device Not Seen" rule whose last trigger was months earlier. Counting
those rules as active problems would mark healthy appliances as failing, so the
appliance health badge uses Datto's own alert count instead.

SCREENSHOT VERIFICATION

Each device row shows Datto's screenshot backup verification: Datto boots the
recovery point and reports whether it came up. This is stronger evidence than a
recent backup timestamp, because a job can complete every night and still restore
to a machine that will not boot.

Three states are shown, and they mean different things:

  Verified       = the recovery point booted
  Failed         = the recovery point did not boot
  Not attempted  = Datto has not tried, which is not the same as a pass

Where Datto captured an image, the badge links straight to it.

The summary panel shows how many machines are verified, for example "17 / 20".
The denominator is every machine that could have a screenshot, so a machine Datto
has never attempted still counts against the total - that is a real gap. File
shares are excluded, because a share has no recovery point to boot and counting
them would permanently understate the ratio.

There is no Offline count. Datto reports no per-device connectivity, so an
offline tile could only ever read Unknown, and a permanently empty box reads as
missing data rather than as "not applicable here".

The protection-methods table lists only methods that actually carry machines.
A Direct-to-Cloud row appears if DTC assets are ever ingested, rather than
sitting on the dashboard reading 0 / 0.

AGENTS, SHARES, AND VOLUMES

Agents and shares are pulled from separate Datto endpoints rather than the
combined asset list, because the combined list does not tell you which type
each record is. Each row on the dashboard shows a label indicating whether it
is an agent or a share. If the typed endpoints fail, the tool falls back to
the combined list so a share issue does not hide your agents.

Volumes come directly from each asset's record. The Volumes column shows
green when all volumes are covered by backups and amber when they are not.
It lists the unprotected volume names rather than just showing a count. This
matters because a backup can run every night, look completely healthy, and
still be missing the volume that holds your actual data.

VM RESTORES

Active VM restores are pulled per appliance and then matched to the specific
machine being restored, first by volume hash and then by asset name as a
fallback. A restore in progress gets a badge on its device row. A restore that
cannot be matched to a machine in the client list gets its own line rather than
being dropped.

An appliance with nothing restoring is reported as exactly that. "Nothing is
running" and "this could not be read" are different facts and the dashboard
keeps them separate: a panel only says the data was unavailable when a read
actually failed, and then it says why.

HUDU ASSET RECORDS

Every device also gets a Hudu asset record carrying the same health, volumes,
screenshot result and VM restore information shown on its Magic Dash row. Both
are written from the same function, so they cannot show different information
about the same machine.

Records the tool created are tagged with an ownership marker. A later sync
updates its own records in place and will not touch, overwrite or duplicate an
asset it did not create. If it finds an unowned asset with a name it wants, it
reports the collision and leaves that asset alone.

STORAGE USAGE

Datto does not have a per-client usage endpoint, so the totals are calculated by
adding up usage figures across each client appliance:

  Local appliance usage  = storage used on the appliances themselves
  Datto cloud storage    = offsite storage used

There is no private-vault figure. That was an Axcient tier with no Datto
equivalent, and carrying it forward made the storage headline read Unknown even
though the cloud number beside it was known.

Storage is reported per appliance, not per machine, so there is no per-device
storage column. A figure Datto does not report shows as Unknown rather than 0,
because those are two different things.

PORTAL LINKS

Device rows and appliances link to the appliance in the Datto portal, using the
per-appliance URL Datto returns on the appliance record. The URL is read from
the API rather than assembled from a guessed pattern. If Datto does not return
one, the link falls back to the Datto login page.

---------------------------------------------------------------------------

WHAT IS NOT COVERED

Direct-to-Cloud assets are not shown. DTC is a separate inventory from the BCDR
appliances, so a DTC-protected machine appears in no appliance asset list. The
tool checks how many DTC assets your account has and warns you during a sync if
there are any, so those machines are never silently missing. It does not yet
display them.

The DattoBcdrAPI module is not on the PowerShell Gallery. It ships in Modules/
and loads from there, and its files are checked against a recorded SHA-256 hash
before use. If that folder is missing or altered, setup stops with a clear error
rather than downloading anything.
