# Native Open-XML parser for numbered/bulleted "checklist" Word documents.
# No LibreOffice required: a .docx/.docm is a zip; we read word/document.xml
# directly and turn list paragraphs into an ordered task model.
#
# Output model (per document):
#   @{
#     SourceFile  = <full path>
#     Title       = <raw title from doc, or $null -> caller falls back to file name>
#     Description = <intro text before the first list item>
#     Tasks       = @( @{ Name; Description; SubTasks = @( @{ Name; Description } ) } )
#   }

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

$script:WordMainNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

function Read-DocxDocumentXml {
    param([Parameter(Mandatory)][string]$Path)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('word/document.xml')
        if (-not $entry) { throw "No word/document.xml in '$Path' - not a valid Word document." }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
}

function Get-WordParagraphText {
    param([System.Xml.XmlElement]$Paragraph, [System.Xml.XmlNamespaceManager]$Ns)
    $sb = New-Object System.Text.StringBuilder
    foreach ($t in $Paragraph.SelectNodes('.//w:t', $Ns)) { [void]$sb.Append($t.InnerText) }
    # represent tabs/line breaks as spaces so names read cleanly
    $text = $sb.ToString() -replace "[`t`r`n]+", ' '
    return ($text -replace '\s{2,}', ' ').Trim()
}

# Normalize a style name for comparison: lowercase, strip non-alphanumerics.
# "Heading 1" / "Heading1" / "heading1" all collapse to "heading1".
function Get-NormalizedStyleKey {
    param([string]$Style)
    if ([string]::IsNullOrWhiteSpace($Style)) { return $null }
    return ([regex]::Replace($Style.ToLowerInvariant(), '[^a-z0-9]', ''))
}

# Returns @{ Text; Style; IsTitle; IsListItem; Level } for a paragraph.
# Level is 0 for top-level items, 1+ for nested items. Title/heading-styled
# paragraphs are flagged IsTitle and are never treated as list items, so a
# document number in the heading (e.g. "01 - Onboarding") is not mistaken for
# a checklist item.
function Get-WordParagraphInfo {
    param(
        [System.Xml.XmlElement]$Paragraph,
        [System.Xml.XmlNamespaceManager]$Ns,
        [string[]]$TitleStyleKeys = @("title","heading1")
    )

    $text  = Get-WordParagraphText -Paragraph $Paragraph -Ns $Ns
    $style = $Paragraph.SelectSingleNode('w:pPr/w:pStyle/@w:val', $Ns)?.Value

    $isTitle = $false
    if ($style) {
        $key = Get-NormalizedStyleKey -Style $style
        if ($TitleStyleKeys -contains $key) { $isTitle = $true }
    }
    if ($isTitle) {
        return @{ Text = $text; Style = $style; IsTitle = $true; IsListItem = $false; Level = 0 }
    }

    $isList = $false
    $level  = 0

    # 1) True Word list formatting (auto-numbered / bulleted)
    $numPr = $Paragraph.SelectSingleNode('w:pPr/w:numPr', $Ns)
    if ($numPr) {
        $isList = $true
        $ilvl = $numPr.SelectSingleNode('w:ilvl/@w:val', $Ns)?.Value
        if ($ilvl -ne $null -and ($ilvl -as [int]) -ne $null) { $level = [int]$ilvl }
    }
    else {
        # 2) Manual numbering / bullets typed into the text
        #    Captures: "1." "1)" "1.2.3" "a." "-" "*" "•" and checkbox glyphs.
        $m = [regex]::Match($text, '^\s*(?:[☐☑☒□✅]\s*)?(?<marker>\d+(?:\.\d+)*[\.\)]?|[A-Za-z][\.\)]|[\-\*•▪◦‣])\s+(?<rest>\S.*)$')
        if ($m.Success) {
            $isList = $true
            $marker = $m.Groups['marker'].Value
            $text   = $m.Groups['rest'].Value.Trim()
            # dotted numbering like 1.2.3 implies nesting depth
            if ($marker -match '^\d+(\.\d+)+') {
                $level = ($marker.TrimEnd('.',')') -split '\.').Count - 1
            }
        }
    }

    return @{ Text = $text; Style = $style; IsTitle = $false; IsListItem = $isList; Level = $level }
}

function ConvertTo-ChecklistModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet("Subtask","Description","TopLevel")]
        [string]$SubItemHandling = "Subtask",
        [string[]]$TitleStyleHints = @("title","heading 1","heading1")
    )

    $xmlText = Read-DocxDocumentXml -Path $Path
    $doc = New-Object System.Xml.XmlDocument
    $doc.LoadXml($xmlText)
    $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('w', $script:WordMainNs)

    $body = $doc.SelectSingleNode('//w:body', $ns)
    if (-not $body) { throw "No document body found in '$Path'." }

    $titleStyleKeys = @($TitleStyleHints | ForEach-Object { Get-NormalizedStyleKey -Style $_ } | Where-Object { $_ })

    $title       = $null
    $introLines  = New-Object System.Collections.Generic.List[string]
    $tasks       = New-Object System.Collections.Generic.List[object]
    $sawFirstItem = $false

    foreach ($node in $body.ChildNodes) {
        if ($node.LocalName -ne 'p') { continue }   # skip tables, sectPr, etc.
        $info = Get-WordParagraphInfo -Paragraph $node -Ns $ns -TitleStyleKeys $titleStyleKeys
        if ([string]::IsNullOrWhiteSpace($info.Text)) { continue }

        if ($info.IsListItem) {
            $sawFirstItem = $true
            if ($info.Level -le 0) {
                $tasks.Add([pscustomobject]@{
                    Name        = $info.Text
                    Description = $null
                    SubTasks    = (New-Object System.Collections.Generic.List[object])
                }) | Out-Null
            }
            else {
                # nested item
                switch ($SubItemHandling) {
                    "TopLevel" {
                        $tasks.Add([pscustomobject]@{
                            Name = $info.Text; Description = $null
                            SubTasks = (New-Object System.Collections.Generic.List[object])
                        }) | Out-Null
                    }
                    default {
                        if ($tasks.Count -eq 0) {
                            # a nested item with no parent yet -> promote to top level
                            $tasks.Add([pscustomobject]@{
                                Name = $info.Text; Description = $null
                                SubTasks = (New-Object System.Collections.Generic.List[object])
                            }) | Out-Null
                        }
                        else {
                            $parent = $tasks[$tasks.Count - 1]
                            if ($SubItemHandling -eq "Description") {
                                $parent.Description = if ($parent.Description) {
                                    "$($parent.Description)`n- $($info.Text)"
                                } else { "- $($info.Text)" }
                            }
                            else {
                                # Subtask (Hudu allows one level of subtasks)
                                $parent.SubTasks.Add([pscustomobject]@{
                                    Name = $info.Text; Description = $null
                                }) | Out-Null
                            }
                        }
                    }
                }
            }
            continue
        }

        # Non-list paragraph (title/heading or intro prose)
        if (-not $sawFirstItem) {
            if (-not $title -and $info.IsTitle) { $title = $info.Text }
            elseif (-not $title -and $introLines.Count -eq 0) { $title = $info.Text }  # first line as fallback title
            else { $introLines.Add($info.Text) | Out-Null }
        }
        # paragraphs after the list begins are ignored (notes/footers)
    }

    $description = if ($introLines.Count -gt 0) { ($introLines -join "`n") } else { $null }

    # Normalize the generic Lists into plain arrays. Assigning a List[object]
    # whose elements carry nested Lists directly onto a [pscustomobject] hits a
    # PowerShell binding quirk ("Argument types do not match"); arrays are safe.
    $taskArray = foreach ($t in $tasks) {
        [pscustomobject]@{
            Name        = $t.Name
            Description = $t.Description
            SubTasks    = $t.SubTasks.ToArray()
        }
    }

    return [pscustomobject]@{
        SourceFile  = (Resolve-Path -LiteralPath $Path).Path
        Title       = $title
        Description = $description
        Tasks       = @($taskArray)
    }
}

# Count helper for summaries
function Get-ChecklistTaskCount {
    param([Parameter(Mandatory)]$Model)
    $top = @($Model.Tasks).Count
    $sub = 0
    foreach ($t in $Model.Tasks) { $sub += @($t.SubTasks).Count }
    return [pscustomobject]@{ TopLevel = $top; SubTasks = $sub; Total = ($top + $sub) }
}
