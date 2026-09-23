# Moving Articles

**A friendly, safety-first way to move Hudu knowledge base articles between central and company KBs.**

Moving knowledge base content can feel a little nerve-wracking. This tool is designed to make the process calmer: it starts in dry-run mode, shows you what it plans to do, preserves folder structure by default, and writes a CSV report every time it runs.

Use it when you want to move articles:

- from a company KB into the central KB,
- from the central KB into a company KB,
- from one company KB to another company KB,
- by whole source, by folder, or by specific article IDs.

## What it does

`moving-articles.ps1` plans and moves Hudu articles while keeping the destination organized. By default, it:

- runs as a dry-run until you add `-Apply`,
- asks for confirmation before live moves,
- keeps the source folder path when possible,
- can create matching destination folders,
- can place moved articles under a new destination root folder,
- can prefix company-to-company moves with the source company name,
- writes a CSV report to the local `logs/` folder.

The guided wizard is the easiest starting point if you are not sure which options you need.

```powershell
./moving-articles.ps1 -Wizard
```

## Prerequisites

- **PowerShell 7.5.1 or newer**.
- A **Hudu instance on version 2.46.0 or newer**.
- A Hudu API key with access to the articles and folders you plan to move.
- The **HuduAPI PowerShell module**. The script will try to load the expected HuduAPI fork automatically.

When the script starts, it will prompt for your Hudu base URL and API key if they are not already available in the session.

## Try it safely first

The script defaults to dry-run mode. That means you can run a command, review what would happen, and check the CSV report before anything in Hudu changes.

Move articles from a company KB to the central KB:

```powershell
./moving-articles.ps1 -Direction ToCentral -SourceCompanyId 123
```

Move articles from the central KB to a company KB:

```powershell
./moving-articles.ps1 -Direction ToCompany -DestinationCompanyId 456
```

Move articles from one or more company KBs into another company KB:

```powershell
./moving-articles.ps1 -Direction CompanyToCompany -SourceCompanyIds 101,102 -DestinationCompanyId 666 -PrefixWithSourceCompany
```

Move only specific articles:

```powershell
./moving-articles.ps1 -ArticleIds 1001,1002 -Direction ToCompany -DestinationCompanyId 456
```

## Make a real move

Once the dry-run report looks right, add `-Apply` to make live changes.

```powershell
./moving-articles.ps1 -Direction ToCompany -DestinationCompanyId 456 -Apply
```

You will still get a final confirmation prompt before the live move begins. If you are running unattended and have already checked the command carefully, add `-Force` to skip that prompt.

```powershell
./moving-articles.ps1 -Direction ToCompany -DestinationCompanyId 456 -Apply -Force
```

## Helpful options

- `-Wizard` starts the guided experience.
- `-Apply` performs the move. Without it, the script only previews the move.
- `-Force` skips the final live-move confirmation prompt.
- `-SourceCompanyId` selects one source company KB.
- `-SourceCompanyIds` selects multiple source company KBs.
- `-DestinationCompanyId` selects the destination company KB.
- `-ArticleIds` limits the run to specific article IDs.
- `-SourceFolderIds` limits the run to one or more source folders.
- `-DestinationRootFolderName` places moved articles under a named destination folder.
- `-PreserveFolderPath` keeps source folder paths in the destination. Defaults to `$true`.
- `-IncludeFolderDescendants` includes child folders when filtering by folder. Defaults to `$true`.
- `-PrefixWithSourceCompany` adds the source company name to destination paths during company-to-company moves.
- `-MaxArticles` limits how many articles are processed in a run.
- `-ReportPath` writes the CSV report to a custom path.
- `-PassThru` returns a summary object after the run.

## Reports and logs

Every run writes a CSV report, including dry-runs. By default, reports go into the `logs/` folder beside the script.

The report is your friend. Before using `-Apply`, skim it to confirm:

- the selected articles are the ones you expected,
- the destination KB is correct,
- the destination folder paths look right,
- any skipped or failed items make sense.

## A gentle workflow

1. Start with the wizard or a dry-run command.
2. Open the CSV report in `logs/`.
3. Adjust filters, folder options, or destination settings if needed.
4. Run the same command with `-Apply`.
5. Keep the report with your change notes so there is a clear record of what moved.

That is it. Take the first run slowly, let the dry-run do its job, and this becomes a very manageable little moving day.
