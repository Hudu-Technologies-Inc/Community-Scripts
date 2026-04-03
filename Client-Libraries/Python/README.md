# Installing Python

Either of the below scripts are a great way to try out python. Either script will install python3.14, create a virtual environment for you, and upgrade pip, the python package manager.

## Windows 

Windows 11 Windows 10 version 2004 or newer with (May 2020 Update, which contains winget) Windows 8.1 (non-ARM architecture) with (May 2020 Update, which contains winget) can install with the install-python.ps1 powershell script.

```powershell
irm 'https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/refs/heads/main/Client-Libraries/Python/install-python.ps1' | iex
```

## Linux and MacOS

Ubuntu, Debian, Linux mint, MX Linux, Zorin OS, Pop! OS, KDE Neon, Antix, or any other Debian-based distro that uses apt for package management can run the install-python.sh script.

```shell
curl -fsSL https://raw.githubusercontent.com/Hudu-Technologies-Inc/Community-Scripts/main/Client-Libraries/Python/install-python.sh | bash -s -- --user
```