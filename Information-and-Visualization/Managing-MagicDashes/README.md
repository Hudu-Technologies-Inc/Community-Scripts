# Hudu Magic Dash Manager

---

## Overview

The **Hudu Magic Dash Manager** is a powerful PowerShell script designed to provide comprehensive management of Magic Dash tiles within your Hudu instance. This tool offers an intuitive, menu-driven interface for creating, updating, deleting, and managing Magic Dash tiles across all companies in your Hudu environment.

### Key Benefits

- **Interactive Interface** - User-friendly menu system with visual feedback
- **Complete Management** - Create, update, delete, and manage Magic Dash tiles
- **Multi-Company Support** - Work with tiles across all companies
- **Error Handling** - Robust error handling and validation
- **Real-time Updates** - Live tile list updates after operations
- **Professional UI** - Beautiful, color-coded interface with emojis

---

## Prerequisites

### System Requirements

- **PowerShell 7.5.1 or higher**
- **Windows 10/11** (or compatible PowerShell environment)
- **Internet connectivity** to your Hudu instance
- **Azure Key Vault access** (for credential management)

### Required Access

- **Hudu API Key** (24-character key from your Hudu instance)
- **Hudu Instance URL** (your Hudu domain without trailing slash)
- **Azure Key Vault** with stored credentials
- **Magic Dash functionality** enabled in your Hudu instance

---

## Installation & Setup

### Step 1: Download the Script

A. clone the community repo
```powershell
git clone https://github.com/Hudu-Technologies-Inc/Community-Scripts
```

B. download just this script from Github

```
$(Invoke-WebRequest -uri "https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/refs/heads/main/Information-and-Visualization/Managing-MagicDashes/Managing-MagicDashes.ps1").content | Out-File .\Managing-MagicDashes.ps1
```


### Step 2: Azure Key Vault Setup

***If you haven't set up keyvault or fetching your secret fails, you will be asked to type in your Hudu API key, which is removed from memory when script completes***

1. **Create Azure Key Vault** (if not already created):
2. Add Hudu API key as a **new secret** in this vault
3. Change the `$VaultName` variable in this script to the name of your vault
4. Change the `$ApiKeySecretName` variable in this script to the name of your secret which has your Hudu API key

### Step 3: Verify Installation

Invoke the script-

(if you cloned Community repo)
``` powershell
. .\Information-and-Visualization\Managing-MagicDashes\Managing-MagicDashes.ps1
```

(if you downloaded directly)
```powershell
. .\Managing-MagicDashes.ps1
```

---

## Configuration

### Azure Key Vault Configuration

The script expects the following secrets in your Azure Key Vault:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `HuduAPIKey` | Your 24-character Hudu API key | `abc123def456ghi789jkl012` |
| `VaultName` | Your Key Vault Name | `Rickys-Vault` |


## Usage Guide

### Starting the Script

1. **Open PowerShell** as Administrator
2. **Navigate** to the script directory
3. **Run** the script:
   ```powershell
   .\interactive_magic_dash_manager.ps1
   ```

### Main Menu Navigation

Upon startup, you'll see the main menu:

```
🎯 WELCOME TO THE MAGIC DASH MANAGER🎯.               

  ┌─ 1. Select a company with existing Magic Dash tiles
  ├─ 2. Create a new Magic Dash tile for any company
  └─ 0. Exit
```

### Option 1: Managing Existing Tiles

1. **Select a company** from the list of companies with Magic Dash tiles
2. **Choose management option**:
   - **Mass Delete** - Delete all tiles for the company
   - **Individual Delete** - Select specific tiles to delete
   - **Update Tiles** - Modify existing tile properties
   - **Create New** - Add a new tile to the company

### Option 2: Creating New Tiles

1. **Enter company name** (case-sensitive)
2. **Provide tile details**:
   - **Title** - Name of the Magic Dash tile
   - **URL** - Link destination (must include https://)
   - **Description** - Optional description text

### Navigation Tips

- **Type '0'** at any input prompt to return to the previous menu
- **Type 'No'** at any Yes/No prompt to go back to the previous page
- **Press Enter** to keep current values when updating tiles
- **Use '0'** to exit any menu and return to the main menu

---

## 🔧 Troubleshooting

### Common Issues

#### ❌ "Failed to retrieve data from Hudu"

**Cause**: API connection issues or invalid credentials

**Solution**:
1. Verify your Hudu API key is correct
2. Check your Hudu instance URL format
3. Ensure internet connectivity
4. Verify Hudu instance is accessible

#### ❌ "Invalid URL format" Error

**Cause**: URL doesn't include proper protocol

**Solution**:
- Always include `https://` at the beginning of URLs
- Example: `https://example.com` instead of `example.com`

#### ❌ "Company not found" Error

**Cause**: Company name doesn't match exactly

**Solution**:
- Company names are case-sensitive
- Check spelling and capitalization
- Use exact company name from Hudu

#### ❌ Azure Key Vault Access Issues

**Cause**: Insufficient permissions or incorrect vault name

**Solution**:
1. Verify you're logged into Azure: `Connect-AzAccount`
2. Check Key Vault permissions
3. Update `$VaultName` variable in script if needed

### Debug Information

The script includes comprehensive error handling and will display:
- **API Response Codes** - HTTP status codes from Hudu
- **Error Messages** - Detailed error descriptions
- **Operation Status** - Success/failure indicators

---

## ❓ FAQ

### Q: Can I use this script with multiple Hudu instances?

**A**: No, the script is designed to work with one Hudu instance at a time. You would need to modify the credentials for different instances.

### Q: What happens if I change a tile's title during an update?

**A**: Changing the title will create a new tile instead of updating the existing one. This is due to how Hudu's Magic Dash API works.

### Q: Can I bulk import Magic Dash tiles?

**A**: The current version doesn't support bulk import, but you can create multiple tiles quickly using the continuous creation workflow.

### Q: Is there a way to backup tiles before deletion?

**A**: The script doesn't include backup functionality, but you can export your Hudu data through the standard Hudu interface before making changes.

### Q: Can I run this script on Linux or macOS?

**A**: The script is designed for Windows PowerShell, but should work on PowerShell Core on Linux/macOS with some modifications.

### Q: What's the maximum number of tiles I can manage?

**A**: There's no hard limit in the script, but it's limited by your Hudu instance's API rate limits and your system's memory.

### Q: Can I customize the script's appearance?

**A**: Yes, you can modify the color schemes, emojis, and text formatting by editing the `Write-Host` statements in the script.

### Q: Is my data secure when using this script?

**A**: Yes, credentials are stored securely in Azure Key Vault, and the script uses HTTPS for all API communications.

### Q: Can I schedule this script to run automatically?

**A**: Yes, you can use Windows Task Scheduler or Azure Automation to run the script on a schedule.

### Q: What if I accidentally delete all tiles for a company?

**A**: The script includes confirmation prompts to prevent accidental deletions, but if this happens, you'll need to recreate the tiles manually.

---

## Support

### Getting Help

If you encounter issues not covered in this guide:

1. **Check the Troubleshooting section** above
2. **Review the error messages** displayed by the script
3. **Verify your configuration** matches the requirements
4. **Test with a single tile** to isolate issues

### Script Information

- **Version**: 1.0.1
- **Last Updated**: November 2025
- **Compatible With**: Hudu API v1
- **PowerShell Version**: 7.5.1+
---

*Happy Magic Dash Managing! 🎯✨*
