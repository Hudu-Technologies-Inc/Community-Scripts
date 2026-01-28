# Flagging items can help identify critical items, high-sensitivity areas, items that need attention, or other conditions that require a second thought.

### Here are some ways you can easily add such flags and apply them to suit your organizations needs!

`Flags` and `FlagTypes` can help tighten focus around items in Hudu that need special care, more attention, review or revision. Being a powerful feature set for organization and notation, it's a good capability to have a handle on as a Hudu user, administrator or power-user.

### Notes on FlagTypes

`FlagTypes` can be applied to a **variety of objects** in Hudu

- Articles
- Networks
- Ip Addresses
- VLAN Zones
- Assets
- Companies
- Procedures
- Rack Storages
- Passwords

While these are general categories that something might fit in, how you use them is up to you. 
#### The best part? You can pick from a variety of colors to represent any of your `FlagTypes`

You might have a `FlagType` named 'Needs Attention' or 'Under Review' for **quality assurance purposes** with the color Orange
You might have a `FlagType` named 'Handle With Care' or 'Special Case' for **special cases or edge cases** with the color Pink
You might have a `FlagType` named 'Mason' or 'Cameron' **to define ownership of article or object** with the color Green
You might have a `FlagType` named 'Wild Child' or 'Cash on Delivery' **to define characteristics of a company** with the color Purple
You might have a `FlagType` named 'Deprecated' or 'EOL' **to flag objects that aren't going to be in use much longer** with the color Blue
You might have a `FlagType` named 'In-Service', 'Checked-Out' or 'Not-In-Service' **to flag objects that are in a special state** with the color Grey

### Notes on Flags

`Flags` represent the individual attribution of a `flagtype` to an object
For example, if you have a `FlagType` named 'Needs Attention' or 'Under Review' for **quality assurance purposes** with the color Orange, you might apply that to 6 `passwords`, 2 `companies`, and an `asset`. This would result in 9 new Flag objects. Flag objects can be revoked or changed at any time and any single object can have one, none, or several distinct/unique `flagtypes` attributed to them.

---

## Firstly, you'll need to load the prerequisite helper functions with this nifty oneliner (using pwsh7+), then you're ready to roll-

```powershell
pwsh  -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/refs/heads/main/Administration/Flags-And-Flagtypes/Prerequisites.ps1' | iex"
```

If all the prerequisites are met (updated HuduAPI module and Hudu 2.40.0 or newer), you'll get a nice green message indicating that you're ready to go-

<img width="3438" height="232" alt="image" src="https://github.com/user-attachments/assets/0aa669f3-b5df-4739-9ff3-990dde3c1f01" />

*Let's go through some scenarios.* **Of course, you can and are encouraged to modify these scenarios to better suit your needs-**

---

## Scenario 1: we want to flag all assets that havent been updated since `$flagDate`  

first, you'll need to set your `$flagDate` variable. This can be any date that you think any given `asset` **should have been updated since**. Most date formats are valid to set here, but to keep the day and month sections from being conflated with one another, the below formats are good. We give preference to international formats here.

```powershell
$flagDate = '26 Jan 2026 15:56'
# $flagdate = '26-01-2026 15:56'
# $flagdate = '26/01/2026 15:56'
```

with your `flagdate` variable set, we can compare the dates, assign some  flags, and take a closer look at these stale assets as a team-

```powershell
$allAssets = Get-HuduAssets | Where-Object {Compare-DateStrings -a $_.updated_at -b $flagDate}
$staleAssetesFlag = Select-OrCreateFlagType -description "Flag all assets not updated since $flagDate"
$allassets | ForEach-Object {New-HuduFlag -flagTypeId $staleAssetesFlag.id -flagableType "asset" -flaggableId $_.id}
```

---

## Scenario 2: we want to flag all articles that have less than 100 characters in Length 

For this snippet, we'll want to set what we think is an **acceptable minimum length (in characters)** for `articles`. Any articles shorter than this, we will flag for review-

```powershell
$minimumAcceptableLength = 100
```

```powershell
$shortArticles = Get-HuduArticles | Where-Object {"$($_.content)".length -lt $minimumAcceptableLength}
$shortArticlesFlag = Select-OrCreateFlagType -description "Flag all articles with less than 100 characters"
$shortArticles | ForEach-Object {New-HuduFlag -flagTypeId $shortArticlesFlag.id -flagableType "article" -flaggableId $_.id}
```

---

## Scenario 3: lets get a handle on these weak passwords!  

Weak passwords should be under a magnifying glass, since they can create a major security gap.
In this example, we'll set a variable for **minimum password length** and for **minimum unique characters used**.

```powershell
$minimumpasswordLength=8
$minimumCharsUsed=6
```

Once you've defined what you think are **acceptable minimum values** for `passwords`, you can **'flag away'**

```powershell
$weakPasswords = get-hudupasswords | Where-Object {"$($_.asset_password.password ?? $_.password)".length -lt $minimumpasswordLength -or ("$($_.asset_password.password ?? $_.password)".ToCharArray() | Select-Object -Unique).Count -lt $minimumCharsUsed}
$weakPasswordsFlag = Select-OrCreateFlagType -description "Flag all weak passwords with either less than $minimumpasswordLength chars, or fewer than $minimumCharsUsed different chars"
$weakPasswords | ForEach-Object {New-HuduFlag -flagTypeId $weakPasswordsFlag.id -flagableType "password" -flaggableId $_.id}
```

---

## Scenario 4: we want to flag all procedures that have too-few tasks/steps

If your organization has some procedures that might need to be evaluated, this can be a great starting point
Firstly, we'll define what we think is an **acceptable minimum number of steps or tasks** a `procedure` should have

```powershell
$minimumAllowedSteps=2
```

And we can then apply that to all the `procedures` in Hudu with the snippet below

```powershell
$weakProcedures = Get-HuduProcedures | Where-Object {$_.total -le $minimumAllowedSteps}
$proceduresFlag = Select-OrCreateFlagType -description "Flag all procedures that have $minimumAllowedSteps or fewer tasks/steps"
$weakProcedures | ForEach-Object {New-HuduFlag -flagTypeId $proceduresFlag.id -flagableType "procedure" -flaggableId $_.id}
```

---

## Scenario 5: we want to flag all rack storages that are underutilized (less than X% capacity)

First, we'll need to define **what we consider to be underutilized (as percent utilization)**. In this example, we'll suppose ***10%*** or lower constitutes an underutilized `rack storage`, but you can change this as best suits your needs

```powershell
$minimumUtilization=10
```

Then, we're ready to flag some `rack storages`

```powershell
$underutilizedRacks = Get-HuduRackStorages | Where-Object {[int]($_.utilization) -le $minimumUtilization}
$racksFlag = Select-OrCreateFlagType -description "Flag all rack storages that are underutilized (less than $minimumUtilization% capacity)"
$underutilizedRacks | ForEach-Object {New-HuduFlag -flagTypeId $racksFlag.id -flagableType "rack" -flaggableId $_.id}
```

---

## Scenario 6: we want to flag external networks so that they will be recognized and **handled with care**

This one is pretty straightforward and doesn't require any user-defined variables. We're just selecting for **external** `networks`. It can help to make these external `networks` easily identifiable so they may be *handled with extra care*

```powershell
$externalNetworks = Get-HuduNetworks | Where-Object {[int]($_.network_type) -eq 1}
$externalNetworksFlag = Select-OrCreateFlagType -description "Flag all external networks"
$externalNetworks | ForEach-Object {New-HuduFlag -flagTypeId $externalNetworksFlag.id -flagableType "network" -flaggableId $_.id}
```

---

## Scenario 7: lets flag all publicly shared articles **so that we don't update them with sensitive info by mistake**

This is a *pretty big one*, especially if you have many **internal** and **external** `articles` to differentiate.

```powershell
$publicArticles = Get-HuduArticles | Where-Object {$_.enable_sharing -or $_.share_url}
$publicArticlesFlag = Select-OrCreateFlagType -description "Flag all publicly shared articles"
$publicArticles | ForEach-Object {New-HuduFlag -flagTypeId $publicArticlesFlag.id -flagableType "article" -flaggableId $_.id}
```
