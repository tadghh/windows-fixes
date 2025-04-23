# Warning old notes converted to AI slop. Havent used in a bit but the fail (no pending update) works

function Skip-UpdateReboot {
    <#
    .SYNOPSIS
    Deletes the pending.xml file to skip Windows update-related reboots.
    
    .DESCRIPTION
    This function deletes the pending.xml file in the Windows WinSxS folder,
    which can help to skip or avoid Windows update-related reboots.
    Must be run with administrator privileges.
    
    .EXAMPLE
    Skip-UpdateReboot
    
    .NOTES
    Use with caution as skipping Windows update reboots may cause issues in some situations.
    #>
    
    [CmdletBinding()]
    param()
    
    begin {
        # Check if running as administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Error "This function requires administrator privileges. Please run PowerShell as Administrator."
            return
        }
        
        # Path to pending.xml file
        $pendingXmlPath = "$env:SystemRoot\winsxs\pending.xml"
    }
    
    process {
        # Check if the file exists
        if (Test-Path -Path $pendingXmlPath) {
            try {
                # Take ownership and set full permissions before deleting
                $acl = Get-Acl -Path $pendingXmlPath
                $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl
                $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
                $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
                $accessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $identity, $fileSystemRights, $inheritanceFlags, $propagationFlags, $accessControlType
                )
                
                $acl.SetAccessRule($accessRule)
                Set-Acl -Path $pendingXmlPath -AclObject $acl
                
                # Delete the file
                Remove-Item -Path $pendingXmlPath -Force
                Write-Host "Successfully deleted $pendingXmlPath" -ForegroundColor Green
                Write-Host "Windows update reboot requirement should now be bypassed." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to delete $pendingXmlPath" -ForegroundColor Red
                Write-Host "Error: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "The file $pendingXmlPath does not exist. No action needed." -ForegroundColor Yellow
        }
    }
}
