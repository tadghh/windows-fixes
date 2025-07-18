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

# Utilities
These are just some utility functions, to use these add them to your `$PROFILE`. You can find this file by running `notepad $PROFILE` from within powershell (note that different installs of powershell use various locations to store the profile, the preinstalled powershell uses a different location than for example a fresh install of powershell 7).

## Copy-SSHId
Its just ssh-copy-id but for Windows. Add the function inside your `$PROFILE`. Find the function [here](https://github.com/tadghh/windows-fixes/blob/main/Copy-SSHId.ps1) also consider adding the following alias to your `$PROFILE`.
```ps1
Set-Alias -Name ssh-copy-id -Value Copy-SSHId
```

## Power plan 'unlocker' 
A [script](https://github.com/tadghh/windows-fixes/blob/main/Toggle-PowerSettingsVisibility.ps1) that allows you to enable access and configuration to any/all power plan options.

## Skip pending update reboots
The following [script](https://github.com/tadghh/windows-fixes/blob/main/Skip-UpdateReboot.ps1) remove the pending updates file. Think of this like a dirty update/reboot. You might encounter errors by using this bypass but I would find that unlikely (theres a lot of 'you must reboot to complete install' that dont actually need a reboot) 


