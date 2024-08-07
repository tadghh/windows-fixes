# LTSC Microsoft Store Installer

There are other options online but they rely on using someone elses old crusty packages. This script will always download the latest version of Microsoft Store along with all its dependencies.

# Installing

The script can be run with PowerShell 5 - 7, just make sure to run with Admin. If you run into issues please post in the issues tab.

```powershell
# https://raw.githubusercontent.com/tadghh/windows-fixes/main/Install-MSStoreLTSC.ps1
Start-BitsTransfer -Source 'https://raw.githubusercontent.com/tadghh/windows-fixes/main/Install-MSStoreLTSC.ps1' -Destination ./store-install.ps1;
Set-ExecutionPolicy Unrestricted -Force;
./store-install.ps1;

```
