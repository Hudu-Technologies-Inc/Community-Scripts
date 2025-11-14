# Splunk Sync - Hudu Activity Logs

We've created a PowerShell script that allows you to import your Hudu logs into your Splunk Cloud instance.

<img width="2994" height="1556" alt="image" src="https://github.com/user-attachments/assets/3d32acee-3709-4ab5-bbe9-a7858d24cca2" />

## Getting Started

### Requirements:

- Splunk Cloud account
- Active, In-Scope Splunk Token (HEC read/write)
- Hudu Cloud or Self-Hosted account
- Active, In-Scope Hudu API Key
- Powershell 7+

## Setup:

If you are using this on a repeated basis, it's recommended to utilize a secrets management solution like Azure Key Vault.

### Variables:

First, edit these variables to contain your specific Hudu, Vault, and Splunk info:

`AzVault_Name` # this is the name of your Azure Key Vault

`HuduBaseURL` # this is the url for your Hudu instance, example: `https://yoururl.huducloud.com`

`AzVault_HuduSecretName` # this is the name of your key vault secret containing your Hudu API key

`Splunk_Subdomain` # this is the subdomain that your Splunk instance is accessed from

`Splunk_sourcename` # this is the name of your data source as named in splunk HEC

`Splunk_sourcetype` # this is the the source type you designated when setting up HEC. It can be main, archive, history. If you aren't sure, just leave on 'history'.

`DaysAgo` # this is how many days of Hudu Logs to sync

### Secrets:

To set up your key vault secrets, create secrets entries with these names in your key vault, which hold your respective secrets:

`AZVault_SplunkTokenName` default name is splunk-token for this key vault secret which contains splunk token

`AzVault_HuduSecretName` default name is yourhuduapikey for this key vault secret which contains your Hudu API key

#### Auxiliary - Filtering

Filtering log entries is off by default, but can be turned on by setting AllowFiltering to $true in this script.

Filter items out:

You can filter out events in hudu by observable objects. To exclude these in your event sync, leave them in the excluded_objects list.

You can also filter out by action with the list named excluded_actions. These are verbs that we are excluding.

Override key fiiltered items:

For key items that are mission-critical, you can elect to always filtered in certain nouns / verbs, even if they would otherwise be filtered out.

Override these to be filtered in via observable_objects and observable_actions and observable_actions. These are always logged, so if you leave these entries and try to filter items out, they will be overridden!

Running:
Test Run
When you run this for the first time, you can simply run with

```
. .\Commit_Hudu_Logs.ps1
```

You may be met with a authentication prompt the first time. Simply log in with a user principal that has access to your Azure Key Vault.

It will collect many log entries that are set in your observable_objects variable which also are in observable_actions

### Setup: Splunk

After Logging in, select 'source types' from the top menu bar

<img width="1362" height="482" alt="image" src="https://github.com/user-attachments/assets/c14a7d79-ff27-45ea-8e9a-f7ab032b4f87" />

Add an HTTP Event Collector / HEC ingestion method

<img width="1810" height="536" alt="image" src="https://github.com/user-attachments/assets/063005ab-2a9f-4894-98a8-91e15f038f60" />

Create a New Token

<img width="2100" height="260" alt="image" src="https://github.com/user-attachments/assets/685aa2f6-be7b-4162-b6ae-0b071e906e41" />

Take note of your HEC name, which correlates to Splunk_sourcename variable, click 'Next'

<img width="2088" height="602" alt="image" src="https://github.com/user-attachments/assets/fd3d2e56-4bda-48f2-a8e8-052f7a889346" />

Select Source Type. If you are unsure, select history. Take note of this, as it relates to variable. Splunk_sourcetype. Proceed. Important: Leave the indexer agreement unchecked / false.

<img width="1590" height="1170" alt="image" src="https://github.com/user-attachments/assets/342c5406-1a3b-461e-9e66-3f3dcb333cb1" />

Take note of this now-generated token. It is reccomended to place within Azure Key Store for safekeeping! The default name for this secret is splunk-token from the variable: `AZVault_SplunkTokenName`. If you change this secret name in the script, be sure the secret name matches what is in your key vault.

<img width="510" height="548" alt="image" src="https://github.com/user-attachments/assets/cb93385e-b969-4a18-a6af-78f84a79bab0" />

