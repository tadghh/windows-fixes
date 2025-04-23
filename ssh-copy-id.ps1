# Warning partial AI slop, although verified and works. Connects, adds the key, then disconnects
function ssh-copy-id {
    Param (
        [string]$sshHost,
        [int]$Port = 22  # Default to 22 if no port is specified
    )

    # Read and prepare the local public key with Unix-style line endings
    $localKey = (Get-Content -Path "$HOME\.ssh\id_rsa.pub") -join "`n" -replace "`r`n", "`n"
    $escapedKey = $localKey -replace "'", "'\\''"  # Escape single quotes for Bash

    # Combine the commands into one single SSH execution
    $addKeyCmd = @"
mkdir -p ~/.ssh && chmod 700 ~/.ssh &&
echo '$escapedKey' >> ~/.ssh/authorized_keys &&
chmod 600 ~/.ssh/authorized_keys &&
sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
"@ -replace "`r`n", "`n"  # Ensure Unix-style line endings

    # Attempt to add the key
    ssh -p $Port $sshHost "$addKeyCmd" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Key added to remote host."
    } else {
        Write-Output "Failed to add key or check key existence."
    }
}
