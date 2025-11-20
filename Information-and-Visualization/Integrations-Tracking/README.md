# Magic Dash - Integration Asset Tracking

[original community post - Sept 2025](https://community.hudu.com/script-library-awpwerdu/post/magic-dash---integration-asset-counting-No63JxIPRFzRh5R)

## Overview

This script automatically creates Magic Dash tiles in Hudu based on your integration assets. It currently supports 11 different integrations and can count devices, locations, contacts, and assets from various RMM/PSA platforms.

<img width="1900" height="890" alt="image" src="https://github.com/user-attachments/assets/a2fe0bd1-c5fd-4a9a-a72e-ba3398bb2eb4" />

## What You’ll Get:

Once set up correctly, the script will:

- Automatically count integration assets.
- Create and update Magic Dash tiles.
- Support both automation and custom messages.
- Skip companies gracefully if something’s missing.

Your Magic Dash will show live counts for all integrations with almost no manual work.

You can choose not to use the automation part, and fill out custom data to be pushed to magic dash tiles via Hudu's API. Please note integration Asset are counted as a WHOLE, not the individual cards. Meaning that if you have 3 cards from one integration or more in one Asset, this will show up in the magic dash as one Asset counted. If you are using Connected Fields, please ensure these are setup properly as duplicate Assets may cause miscounting.

## What You Need Before You Start:

- PowerShell 7 or later
- Hudu Version 2.39.3 or later
- Azure PowerShell module (Install-Module Az)
- HuduAPI PowerShell module (Install-Module HuduAPI)
- Entra ID (Azure AD) account with access to Key Vault
- Hudu instance with API access

## Step 1 – Set Up Azure Key Vault

# Azure Key Vault Setup Guide

### 1. Create a Key Vault

a. Go to Azure Portal  
b. Search for **“Key Vaults”** and click **Create**.  
c. Fill in the following:  
   1. **Subscription:** Your Azure subscription  
   2. **Resource Group:** Create new or use existing  
   3. **Key Vault name:** Example `My-Key-Vault-Name`  
   4. **Region:** Choose your region  
   5. **Pricing tier:** Standard  
d. Click **Review + Create → Create**.

---

### 2. Add Secrets

a. Inside the Key Vault, go to **Secrets → Generate/Import**, and add two secrets:

### **Secret 1: HuduAPIKey**
1. **Name:** `HuduAPIKey`  
2. **Value:** Your Hudu API key (Hudu → Admin → API Keys)  
3. **Content Type:** `text/plain`  
4. Choose an expiry date or leave it to never expire.

### **Secret 2: HuduBaseDomain**
1. **Name:** `HuduBaseDomain`  
2. **Value:** Your Hudu base URL (e.g., `https://yourcompany.hudu.io`)  
3. **No trailing slash!**  
4. **Content Type:** `text/plain`  
5. Choose an expiry date or leave it to never expire.

---

### 3. Give Yourself Permission

a. Key Vault → **Access Policies** → **Add Access Policy**  
b. Pick your user account  
c. Under **Secret permissions**, select **Get** and **List**  
d. Click **Add**, then **Save**.

## Step 2 – Configure the Script

Open test_magic_dash.ps1 in a text editor.

On line 51 you’ll see:

```
$VaultName = "My-Key-Vault-Name-Here"
```
Replace `My-Key-Vault-Name-Here` with the name of your Key Vault.

## Step 3 – Create the Asset Layout in Hudu

- In Hudu go to Admin → Asset Layouts → New Asset Layout.
- Name it Company Details (this name is required).
- Pick any icon and color.
- Click Create.

## Step 4 – Add the Required Fields

Every integration needs its own set of fields in the Company Details layout. You only have to add the fields for the integrations you actually use.

Base Fields (all integrations need these):

- Custom Fields:ENABLED (CheckBox) – switches between custom and automation mode.
- IncludeArchivedAssets:ENABLED (CheckBox) – whether to include archived assets in the count.

Field Types:

- CheckBox for any :ENABLED field.
- Text for :URL, :NOTE and all :Count fields.

Field Naming:

- Use exactly the names below (case-sensitive).
- Format: ServiceName:FieldName.

### Field Reference by Integration (ENABLED → URL → NOTE → Counts)

