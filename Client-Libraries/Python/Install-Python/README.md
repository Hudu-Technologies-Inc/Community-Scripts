# Install Python

Quick install scripts for setting up **Python 3.14** for the Python client libraries.


#### These Scripts Will:

- Install Python3.14
- Create a Virtual Environment ***(in your current directory)***
- Upgrade Pip

## Windows

Run either of these in PowerShell ***(elevated permissions may be required)***:

```powershell
irm https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/main/Client-Libraries/Python/Install-Python/install-python.ps1 | iex
```

```powershell
iex ((Invoke-WebRequest https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/main/Client-Libraries/Python/Install-Python/install-python.ps1).Content)
```

## macOS / Linux

Run either of these in your shell ***(avoid running as root)***:

```bash
curl -fsSL https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/main/Client-Libraries/Python/Install-Python/install-python.sh | bash
```

```bash
wget -qO- https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/main/Client-Libraries/Python/Install-Python/install-python.sh | bash
```
