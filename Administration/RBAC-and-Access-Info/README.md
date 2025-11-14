# Auditing RBAC, Password Folder Access, and Public Articles

It's always important to audit access levels and public data, especially when dealing with large swaths of client data or new access control features.

There are *several angles to consider* - user permissions, group permissions, public articles, password folders, but this handy script can be a useful way to visualize some of these potential areas of improvement.

If you are a ***'Totally Tabular'*** kind of user, this is just the tool for you- the results export to a few handy csv's for any drilldown or analysis needed (no actual passwords included in these tables).

## RBAC Passwords / Folders Section

tables included:
- Per-user password/folder access and membership details
- Group-accessibility counts
- RBAC passwords per-company/per-folder
- Per-user accessible passwords count
- group associations for all RBAC-enabled passwords

<img width="3200" height="818" alt="image" src="https://github.com/user-attachments/assets/dbd0371d-8d2f-4119-aeca-ccf07358097c" />
<img width="1660" height="946" alt="image" src="https://github.com/user-attachments/assets/09172aca-9ab4-4fa1-a08b-a9b25cadf1c0" />

## All Passwords / Scope Section

Tables included:
- All Password Details scope, RBAC, name and company
- password / scope / company comparison
- Which companies have more passwords with/without RBAC

<img width="1256" height="270" alt="image" src="https://github.com/user-attachments/assets/f4adb326-c9bd-4435-b9e0-b1458cd2d02b" />
<img width="1256" height="270" alt="image" src="https://github.com/user-attachments/assets/f7b1841a-14b2-41fa-aed9-85e6c48a937f" />

## Articles Section

Public Articles overview - just a simple table of article name, public url, and company. (if no company is present, it is a Central/Global Knowledge Base article).

Generally, it's good to ensure that these article names should reflect its contents. Too-general of article names could lead to confusion during management.

<img width="1536" height="200" alt="image" src="https://github.com/user-attachments/assets/2eb24d5c-07e5-4fc6-be72-83d8d1dad05b" />

Viewing CSV Results
If you wish to use these files, you can open them in a folder named 'hudu-audit' with a timestamp.

<img width="1108" height="254" alt="image" src="https://github.com/user-attachments/assets/5946ff15-b008-41a0-98a4-40b013ace483" />


