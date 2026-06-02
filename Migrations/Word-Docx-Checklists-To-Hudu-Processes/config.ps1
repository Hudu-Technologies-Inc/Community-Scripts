# Checklists-To-Processes configuration / defaults
#
# These are sane defaults. Anything here can be overridden with a script
# parameter on Checklists-To-Processes.ps1, or by editing this file.

# Only these document types are parsed for checklists. Native Open-XML parsing
# is used for .docx/.docm. .doc (legacy binary) is NOT supported without
# LibreOffice and is skipped with a warning.
$script:SupportedExtensions = @(".docx", ".docm")

# When discovering files by name (Filter blank), only treat documents whose
# file name matches this pattern as "numbered checklists". Default: the file
# name starts with one or more digits (e.g. "01 - Onboarding.docx",
# "100_Server_Build.docx", "12.Patch Review.docx").
# Set to '.*' to accept any name.
$script:NumberedNamePattern = '^\s*\d+'

# How sub-items (indented list items / multi-level numbering like 1.1) are
# handled. Overridable with -SubItemHandling.
#   Subtask      -> nested as Hudu subtasks under their parent task (default)
#   Description  -> folded into the parent task's description as a bulleted list
#   TopLevel     -> flattened so every item becomes its own top-level task
$script:DefaultSubItemHandling = "Subtask"

# What to do when a process of the same name already exists in the target scope.
# Overridable with -OnExisting.
#   Skip      -> leave the existing process untouched (default, agreed)
#   Update    -> add only tasks that don't already exist (matched by name+position)
#   Replace   -> delete all existing tasks on the process, then recreate from the doc
#   Recreate  -> always create a brand new process (may create duplicates)
$script:DefaultOnExisting = "Skip"

# What to do when ByFolderName / ByFileName company resolution finds no match.
# Overridable with -OnNoCompanyMatch.
#   Prompt -> ask the operator to pick a company (or global) for that doc (default)
#   Skip   -> skip the document entirely
#   Global -> fall back to a global template
$script:DefaultOnNoCompanyMatch = "Prompt"

# Minimum similarity (0..1) for fuzzy company-name matching in ByFolderName /
# ByFileName modes. 1.0 = exact (after normalization).
$script:CompanyMatchThreshold = 0.90

# Word paragraph style names (case-insensitive, normalized) treated as the
# document title when deriving a process name.
$script:TitleStyleHints = @("title", "heading 1", "heading1", "head1")
