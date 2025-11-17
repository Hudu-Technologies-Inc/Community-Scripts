# Hudu Health Report and Statistics

Easily Keep Tabs on Important Key Hudu Health Metrics

[See Also: original community post, Oct 2025](https://community.hudu.com/script-library-awpwerdu/post/hudu-health-report-and-statistics-01coqpXffyYpINh)

Tracking health information of your Hudu instance can be helpful for even those who aren't self-hosted.

## What gets Tracked

- **Overall System Information**
  - Basic / Overall Info
  - Current Version / Latest Version *(Is an update available?)*
  - Self-Hosted Information
    - If self-hosted, links for self-hosted upgrade documentation are provided
    - Links to Docker image upgrades
    - Links to Release Notes
  - Hudu Reported Date
    - The date reported by Hudu (especially useful for self-hosted instances)
  - Web Redirects for HTTP
    - Ensures all traffic is secure and no data is sent/received over non-TLS channels

<img width="2112" height="830" alt="image" src="https://github.com/user-attachments/assets/a94fd280-c612-4601-9635-29ac57de5d9d" />

- **Uploads / Photos Statistics**
  - Uploads by MIME Type / File Type
    - Breakdown of how many files of each type exist
  - Space Used per MIME Type / File Type
    - How much disk space each type of file occupies
  - Newest Files per MIME Type
    - Recent uploads contributing to space usage
  - Uploads Per Month
    - How many uploads are added over time (month-over-month)
  - Uploads per Relationship Type
    - What each upload is associated with (company, asset, article, etc.)
  - Top-Ten Largest Uploads by Size
  - Photos by Relationship Type
    - What photos are associated with
  - Duplicated Upload Names
    - Top 10 most frequent upload filenames  
    - Useful for identifying duplicate uploads that may be deletable

<img width="2042" height="1774" alt="image" src="https://github.com/user-attachments/assets/9824cb00-1893-4027-86c5-4a5f0e9bb4d7" />
<img width="2080" height="1190" alt="image" src="https://github.com/user-attachments/assets/c02fce85-1c60-4d7e-94e1-f5ec0b0de24d" />

- **Article Statistics**
  - Word Count (Largest)
    - Which article contains the most words?
  - Word Count (Smallest)
    - Identifies articles that are empty or nearly empty
  - Text Length (Longest)
    - Helps identify articles with embedded base64 images or bloated content
  - Text Length (Shortest)
    - Helps find empty or unpopulated articles
  - MIME Type Awareness
    - Notes that MIME-type indicates document/file format for embedded content


## Setting Up

Setting Up is easy, All you need to do is:

Enter your Hudu Base URL in this variable, below

```
$HuduBaseUrl = "https://yourhuduURL.huducloud.com"
```

If you want a custom name for your global kb article, you can set this to anything you'd like, as long as it makes sens

```
$PreferredArticleTitle = "Hudu Health Report"
```

If you are self-hosted, some alternative information is given to you, so you'll want to set $selfhosted to $true here:


```
$HuduSetup = @{
    SelfHosted=$false
    HuduImage="hududocker/hudu" #for beta, use hududocker/hudubeta
}
```
If you are on beta, you can switch the channel that you are checking as well. The only downside is that there are less tags available for beta and thus somewhat limited tag differentiation.

If running **continuously**, you'll want to fill out your AZ keystore information for safe and continuous secrets management. We only need one secret for this one, $huduAPIKey. Set up the script to run on a schedule in Task Scheduler to **runAs a user that can authenticate to AZ keystore**.

```
$UseAZVault = $true
$AzVault_HuduSecretName = "HuduAPIKeySecretName" # Name of your secret
$AzVault_Name           = "MyVaultName"          # Name of your vault
```

That's It!
The script should only take a few seconds to run and will generate a KB article with all of the selected information.
