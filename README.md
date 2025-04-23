# LTSC Microsoft Store Installer

There are other options online but they rely on using someone elses old crusty packages. This script will always download the latest version of Microsoft Store for your architecture along with all of its dependencies.

## Installing

The script is compatible with PowerShell 5 and later, just make sure to run with admin. If you run into issues please post in the issues tab.

> [!IMPORTANT]  
> Run the following command with Admin.


```powershell
Start-BitsTransfer -Source 'https://raw.githubusercontent.com/tadghh/windows-fixes/main/Install-MSStoreLTSC.ps1' -Destination ./store-install.ps1;
Set-ExecutionPolicy Unrestricted -Force;
./store-install.ps1;
Set-ExecutionPolicy RemoteSigned -Force 
```
# SSH Copy ID
A simple script to copy your ssh keys to the host [see](https://github.com/tadghh/windows-fixes/blob/main/ssh-copy-id.ps1). This would typically be added to your powershell `$PROFILE`

# Power plan 'unlocker' 
A [script](https://github.com/tadghh/windows-fixes/blob/main/Toggle-PowerSettingsVisibility.ps1) that allows you to enable access and configuration to any/all power plan options. This would typically be added to your powershell `$PROFILE`
