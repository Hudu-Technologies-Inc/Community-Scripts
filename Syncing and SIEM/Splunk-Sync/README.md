# Splunk Sync - Hudu Activity Logs

We've created a PowerShell script that allows you to import your Hudu logs into your Splunk Cloud instance.

Script is located at the bottom of this post and is also attached.

---

Getting Started
Requirements:

Splunk Cloud account

Active, In-Scope Splunk Token (HEC read/write)

Hudu Cloud or Self-Hosted account

Active, In-Scope Hudu API Key

Powershell 7+

Setup:
If you are using this on a repeated basis, it's recommended to utilize a secrets management solution like Azure Key Vault.

Variables:
First, edit these variables to contain your specific Hudu, Vault, and Splunk info:

AzVault_Name # this is the name of your Azure Key Vault

HuduBaseURL # this is the url for your Hudu instance, example: https://yoururl.huducloud.com

AzVault_HuduSecretName # this is the name of your key vault secret containing your Hudu API key

Splunk_Subdomain # this is the subdomain that your Splunk instance is accessed from

Splunk_sourcename # this is the name of your data source as named in splunk HEC

Splunk_sourcetype # this is the the source type you designated when setting up HEC. It can be main, archive, history. If you aren't sure, just leave on 'history'.

DaysAgo # this is how many days of Hudu Logs to sync

Secrets:
To set up your key vault secrets, create secrets entries with these names in your key vault, which hold your respective secrets:

AZVault_SplunkTokenName= default name is splunk-token for this key vault secret which contains splunk token

AzVault_HuduSecretName= default name is yourhuduapikey for this key vault secret which contains your Hudu API key

Auxiliary:
Filtering:

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

. .\Commit_Hudu_Logs.ps1

You may be met with a authentication prompt the first time. Simply log in with a user principal that has access to your Azure Key Vault.

It will collect many log entries that are set in your observable_objects variable which also are in observable_actions

Setup: Splunk
After Logging in, select 'source types' from the top menu bar

---

Add an HTTP Event Collector / HEC ingestion method

---

Create a New Token

---

Take note of your HEC name, which correlates to Splunk_sourcename variable, click 'Next'

---

Select Source Type. If you are unsure, select history. Take note of this, as it relates to variable. Splunk_sourcetype. Proceed. Important: Leave the indexer agreement unchecked / false.

---

Take note of this now-generated token. It is reccomended to place within Azure Key Store for safekeeping! The default name for this secret is splunk-token from the variable: AZVault_SplunkTokenName. If you change this secret name in the script, be sure the secret name matches what is in your key vault.

---
