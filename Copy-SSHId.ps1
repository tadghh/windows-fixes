function Copy-SSHId {
  <#
  .SYNOPSIS
  Copies SSH public key to remote server (PowerShell equivalent of ssh-copy-id)

  .DESCRIPTION
  This function copies your SSH public key to a remote server's ~/.ssh/authorized_keys file,
  enabling passwordless SSH authentication. Works with both Windows and Unix remote servers.

  .PARAMETER Target
  The target in format [user@]hostname - if user is omitted, uses current username

  .PARAMETER i
  Path to the identity file (SSH public key) to copy

  .PARAMETER p
  SSH port number (default: 22)

  .PARAMETER w
  Force Windows commands for remote server (auto-detected by default)

  .PARAMETER u
  Force Unix commands for remote server (auto-detected by default)

  .PARAMETER a
  Copies the public key to 'administrators_authorized_keys', this is only useful for Windows remotes

  .EXAMPLE
  Copy-SSHId Administrator@ADVM

  .EXAMPLE
  Copy-SSHId -i ~/.ssh/id_ed25519.pub user@myserver.com

  .EXAMPLE
  Copy-SSHId -w -a Administrator@windowsserver
  #>

  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Target,

    [Parameter(Mandatory = $false)]
    [Alias('i')]
    [string]$IdentityFile = '',

    [Parameter(Mandatory = $false)]
    [Alias('p')]
    [int]$Port = 22,

    [Parameter(Mandatory = $false)]
    [Alias('a')]
    [switch]$AdminAccount,

    [Parameter(Mandatory = $false)]
    [Alias('w')]
    [switch]$Windows,

    [Parameter(Mandatory = $false)]
    [Alias('u')]
    [switch]$Unix
  )

  if ($Target -match '^(.+)@(.+)$') {
    $Username = $Matches[1]
    $RemoteHost = $Matches[2]
  }
  elseif ($Target -match '^([^@]+)$') {
    $Username = $env:USERNAME
    $RemoteHost = $Matches[1]
  }
  else {
    throw "Invalid target format. Use 'user@host' or 'host'"
  }

  function Find-SSHPublicKey {
    $sshDir = Join-Path $env:USERPROFILE '.ssh'
    $keyTypes = @('id_rsa.pub', 'id_ed25519.pub', 'id_ecdsa.pub', 'id_dsa.pub')

    foreach ($keyType in $keyTypes) {
      $keyFile = Join-Path $sshDir $keyType
      if (Test-Path $keyFile) {
        return $keyFile
      }
    }
    return $null
  }

  function Test-RemoteOS {
    param([string]$Username, [string]$RemoteHost, [int]$Port)
    Write-Host 'Detecting remote OS... (enter SSH user password)' -ForegroundColor Yellow

    $windowsTest = & ssh -p $Port "${Username}@${RemoteHost}" 'cmd /c echo %OS%' 2>$null
    if ($LASTEXITCODE -eq 0 -and $windowsTest -like '*Windows*') {
      return 'Windows'
    }

    return 'Unix'
  }

  try {
    if ([string]::IsNullOrEmpty($IdentityFile)) {
      $KeyPath = Find-SSHPublicKey
      if (-not $KeyPath) {
        throw 'No SSH public key found. Generate one with: ssh-keygen -t ed25519'
      }
    }
    else {
      if ($IdentityFile.StartsWith('~/')) {
        $KeyPath = Join-Path $env:USERPROFILE $IdentityFile.Substring(2)
      }
      else {
        $KeyPath = $IdentityFile
      }
    }

    if (-not (Test-Path $KeyPath)) {
      throw "SSH public key file not found: $KeyPath"
    }

    Write-Host "Using SSH public key: $KeyPath" -ForegroundColor Green
    $publicKey = Get-Content $KeyPath -Raw
    $publicKey = $publicKey.Trim()

    if ([string]::IsNullOrEmpty($publicKey)) {
      throw "SSH public key file is empty: $KeyPath"
    }

    $remoteOS = 'Unix'
    if ($Windows) {
      $remoteOS = 'Windows'
    }
    elseif ($Unix) {
      $remoteOS = 'Unix'
    }
    else {
      Write-Host 'Creating connection to determine OS (hint: use -Windows or -Unix)' -ForegroundColor Yellow
      $remoteOS = Test-RemoteOS -Username $Username -RemoteHost $RemoteHost -Port $Port
    }

    $cleanKey = $publicKey -replace '\r?\n', '' -replace '\s+', ' '
    $cleanKey = $cleanKey.Trim()

    Write-Host "Copying SSH public key to ${Username}@${RemoteHost} (${remoteOS})..." -ForegroundColor Yellow

    if ($remoteOS -eq 'Windows') {
      if ($AdminAccount) {
        Write-Host "AdminAccount: Writing SSH public key to 'C:\ProgramData\ssh\administrators_authorized_keys'" -ForegroundColor Cyan
        $sshPath = 'C:\ProgramData\ssh\administrators_authorized_keys'
      }
      else {
        $sshPath = '%USERPROFILE%\.ssh\authorized_keys'
      }

      $commandString = "cmd /c `"" + (@(
          "if not exist `"$sshPath`" type nul > `"$sshPath`"",
          "echo $cleanKey >> `"$sshPath`""
        ) -join ' && ') + "`""
    }
    else {
      $escapedKey = $cleanKey -replace "'", "'\\''"
      $remoteCommands = @(
        'mkdir -p ~/.ssh',
        'chmod 700 ~/.ssh',
        "echo '$escapedKey' >> ~/.ssh/authorized_keys",
        'chmod 600 ~/.ssh/authorized_keys'
      )

      $commandString = $remoteCommands -join '; '
    }

    $sshArgs = @(
      '-p', $Port
      "${Username}@${RemoteHost}"
      $commandString
    )

    & ssh $sshArgs

    if ($LASTEXITCODE -eq 0) {
      Write-Host "SSH key successfully copied to ${Username}@${RemoteHost}" -ForegroundColor Green
      Write-Host 'You should now be able to connect without a password:' -ForegroundColor Cyan
      Write-Host "`nssh ${Username}@${RemoteHost}" -ForegroundColor White
      if ($Port -ne 22) {
        Write-Host "`nssh -p $Port ${Username}@${RemoteHost}" -ForegroundColor White
      }
    }
    else {
      throw "SSH command failed with exit code: $LASTEXITCODE"
    }
  }
  catch {
    Write-Error "Failed to copy SSH key: $($_.Exception.Message)"
  }
}
