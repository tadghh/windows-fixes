
function Copy-SSHId {
    <#
    .SYNOPSIS
    Copies SSH public key to remote server (PowerShell equivalent of ssh-copy-id)
    
    .DESCRIPTION
    This function copies your SSH public key to a remote server's ~/.ssh/authorized_keys file,
    enabling passwordless SSH authentication. Uses the same syntax as ssh-copy-id.
    
    .PARAMETER Target
    The target in format [user@]hostname - if user is omitted, uses current username
    
    .PARAMETER i
    Path to the identity file (SSH public key) to copy
    
    .PARAMETER p
    SSH port number (default: 22)
    
    .PARAMETER f
    Force mode - overwrite authorized_keys instead of appending
    
    .EXAMPLE
    Copy-SSHId user@192.168.1.100
    
    .EXAMPLE
    Copy-SSHId -i ~/.ssh/id_ed25519.pub user@myserver.com
    
    .EXAMPLE
    Copy-SSHId -p 2222 admin@server.local
    
    .EXAMPLE
    Copy-SSHId -f user@host.com
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target,
        
        [Parameter(Mandatory = $false)]
        [Alias("i")]
        [string]$IdentityFile = "",
        
        [Parameter(Mandatory = $false)]
        [Alias("p")]
        [int]$Port = 22,
        
        [Parameter(Mandatory = $false)]
        [Alias("f")]
        [switch]$Force
    )
    
    if ($Target -match '^(.+)@(.+)$') {
        $Username = $Matches[1]
        $RemoteHost = $Matches[2]
    } elseif ($Target -match '^([^@]+)$') {
        $Username = $env:USERNAME
        $RemoteHost = $Matches[1]
    } else {
        throw "Invalid target format. Use 'user@host' or 'host'"
    }
    
    function Find-SSHPublicKey {
        $sshDir = Join-Path $env:USERPROFILE ".ssh"
        $keyTypes = @("id_rsa.pub", "id_ed25519.pub", "id_ecdsa.pub", "id_dsa.pub")
        
        foreach ($keyType in $keyTypes) {
            $keyFile = Join-Path $sshDir $keyType
            if (Test-Path $keyFile) {
                return $keyFile
            }
        }
        return $null
    }
    
    try {
        if ([string]::IsNullOrEmpty($IdentityFile)) {
            $KeyPath = Find-SSHPublicKey
            if (-not $KeyPath) {
                throw "No SSH public key found. Generate one with: ssh-keygen -t ed25519"
            }
            Write-Host "Using SSH public key: $KeyPath" -ForegroundColor Green
        } else {
            if ($IdentityFile.StartsWith("~/")) {
                $KeyPath = Join-Path $env:USERPROFILE $IdentityFile.Substring(2)
            } else {
                $KeyPath = $IdentityFile
            }
        }
        
        if (-not (Test-Path $KeyPath)) {
            throw "SSH public key file not found: $KeyPath"
        }
        
        $publicKey = Get-Content $KeyPath -Raw
        $publicKey = $publicKey.Trim()
        
        if ([string]::IsNullOrEmpty($publicKey)) {
            throw "SSH public key file is empty: $KeyPath"
        }
        
        Write-Host "Copying SSH public key to ${Username}@${RemoteHost}..." -ForegroundColor Yellow
        $remoteCommands = @(
            "mkdir -p ~/.ssh",
            "chmod 700 ~/.ssh"
        )
        
        if ($Force) {
            $remoteCommands += "echo '$publicKey' > ~/.ssh/authorized_keys"
        } else {
            $remoteCommands += "echo '$publicKey' >> ~/.ssh/authorized_keys"
        }
        $remoteCommands += @(
            "chmod 600 ~/.ssh/authorized_keys",
            "echo 'SSH key successfully added to authorized_keys'"
        )
        $commandString = $remoteCommands -join "; "   
        $sshArgs = @(
            "-p", $Port
            "${Username}@${RemoteHost}"
            $commandString
        )

        $result = & ssh $sshArgs
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SSH key successfully copied to ${Username}@${RemoteHost}" -ForegroundColor Green
            Write-Host "You should now be able to connect without a password:" -ForegroundColor Cyan
            Write-Host "  ssh ${Username}@${RemoteHost}" -ForegroundColor White
            if ($Port -ne 22) {
                Write-Host "  ssh -p $Port ${Username}@${RemoteHost}" -ForegroundColor White
            }
        } else {
            throw "SSH command failed with exit code: $LASTEXITCODE"
        }
        
    } catch {
        Write-Error "Failed to copy SSH key: $($_.Exception.Message)"
        Write-Host "Make sure:" -ForegroundColor Yellow
        Write-Host "  1. SSH client is installed and in PATH" -ForegroundColor Yellow
        Write-Host "  2. You can connect to the remote server manually" -ForegroundColor Yellow
        Write-Host "  3. The remote server allows SSH connections" -ForegroundColor Yellow
        Write-Host "  4. You have the correct username and hostname" -ForegroundColor Yellow
    }
}
