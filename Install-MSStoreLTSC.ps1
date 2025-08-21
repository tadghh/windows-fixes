function Start-Setup() {
  $policy = Get-ExecutionPolicy

  if ($policy -eq 'Restricted') {
    Write-Host 'Scripts are not allowed. This script requires scripts to run.'

    $answer = Read-Host 'Do you want to enable scripts for this session? (Y/N)'

    if ($answer -match '^[Yy]$') {
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
      Write-Host 'Scripts are now enabled for this session.'
    }
    else {
      Write-Host 'Cannot continue. Exiting script.'
      exit
    }
  }
  else {
    Write-Host 'Scripts are allowed.'
  }

  # If you are having issues make sure below are installed with admin
  Write-Output 'Installing modules'
  if ($PSVersionTable.PSVersion.Major -lt 7) {
    try {
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    }
    catch {
      Write-Warning "Failed to install NuGet provider: $_"
    }

  }

  try {
    if (-not (Get-Module -ListAvailable -Name PSParseHTML)) {
      Install-Module -Name PSParseHTML -Force -Scope CurrentUser -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    }
  }
  catch {
    Write-Warning "Failed to install PSParseHTML: $_"
  }

  try {
    if (-not (Get-Module -Name PSParseHTML)) {
      Import-Module PSParseHTML -ErrorAction Stop | Out-Null
    }
  }
  catch {
    Write-Warning "Failed to import PSParseHTML: $_"
  }
}


# Returns the api response from adguard
# NOTE dont use this to install a bunch of applications across a network. You should be using Intune or the like
# This will make post requests to adguard for every product id, since they return html this will get very expensive with 100+ computers
function Get-CurrentDownloads {
  param (
    [Parameter(Mandatory = $true)]
    [string]$productID
  )
  $url = 'https://store.rg-adguard.net/api/GetFiles'
  $headers = @{
    'User-Agent'   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0'
    'Content-Type' = 'application/x-www-form-urlencoded'
  }

  #Change the product id at the end of the url to make this work with other products
  $body = @{
    type = 'ProductId'
    url  = "$productID"
    ring = 'RP'
    lang = 'en-US'
  }
  Write-Host 'Getting download information'
  $currentDownloadsHTML = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
  return $currentDownloadsHTML
}

# Function to create a link item
function Save-LinkItem {
  param (
    [string]$downloadLink,
    [string]$fileName
  )

  return [PSCustomObject]@{
    downloadLink = $downloadLink
    fileName     = $fileName
  }
}

# Shortens the string to its
function Get-PrettyFileName {
  param (
    [Parameter(Mandatory = $true)]
    [string]$dirtyFileName
  )

  switch -Regex ($dirtyFileName) {
    '_' { return $dirtyFileName.Substring(0, $dirtyFileName.IndexOf('_')) }
    '\.' { return $dirtyFileName.Substring(0, $dirtyFileName.LastIndexOf('.')) }
    default { return $dirtyFileName }
  }
}

# Processes the api call to adguard store
# No idea why they return HTML, suppose its to deter 'projects like this'
function Get-LinksFromHTML {
  param (
    [Parameter(Mandatory = $true)]
    [string]$html
  )

  Write-Host 'Processing download links'
  $linkObjects = @()
  $Objects = ConvertFrom-HTMLAttributes -Content $html -Tag 'a' -ReturnObject

  foreach ($O in $Objects) {
    $linkObjects += Save-LinkItem -downloadLink $O.href -fileName $O.InnerHtml
  }

  return $linkObjects
}

# Function to process link objects
# Reduces the amount of data to sleuth through
function Format-Links {
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject[]]$linkObjects,

    [Parameter(Mandatory = $true)]
    [string]$searchEnding
  )

  $relaventLinks = $linkObjects | Where-Object {
    $_.fileName -and $_.fileName.EndsWith($searchEnding)
  }

  return $relaventLinks
}

# Gets the current devices cpu arch
function Get-CPUArch {
  # First switch on PROCESSOR_ARCHITEW6432 to check if it's a 64-bit system running a 32-bit process
  switch ($env:PROCESSOR_ARCHITEW6432) {
    'AMD64' { return 'x64' }
    # valid https://github.com/pyinstaller/pyinstaller/issues/8219#issuecomment-1889817050
    'ARM64' { return 'arm64' }
    default {
      # If PROCESSOR_ARCHITEW6432 is not set, check PROCESSOR_ARCHITECTURE for the current process architecture
      switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'x86' { return 'x86' }
        # Not sure this is valid
        'ARM' { return 'arm' }  # 32-bit ARM system
        default { throw "Unknown architecture: $($env:PROCESSOR_ARCHITECTURE)" }
      }
    }
  }
}

# Gets the latest version in comparison to others
function Get-LatestVersion {
  param (
    [Parameter(Mandatory = $true)]
    [string]$targetString,

    [Parameter(Mandatory = $true)]
    [string]$packageArch,

    [Parameter(Mandatory = $true)]
    [PSCustomObject[]]$linkObjects,

    [Parameter(Mandatory = $true)]
    [string]$filetype
  )


  try {
    $packageArch = "*$(Get-CPUArch)*"

    if ( $targetString -eq 'Microsoft.WindowsStore' -or $targetString -eq 'Microsoft.DesktopAppInstaller') {
      $packageArch = '*neutral*'
    }

    $filteredObjects = $linkObjects | Where-Object {
      $_.fileName -like "$targetString*" -and $_.fileName -like $packageArch -and $_.fileName -like "*$filetype*"
    }

    if ($filteredObjects.Count -eq 0) {
      Write-Host 'No matching link objects found.'
      return $null
    }

    $latestObject = $null
    $latestVersion = $null
    foreach ($obj in $filteredObjects) {
      $version = Get-Version -content $obj.fileName
      if ($version) {
        if ($null -eq $latestVersion -or [version]$version -gt [version]$latestVersion) {
          $latestVersion = $version
          $latestObject = $obj
        }
      }
    }
    Write-Host "`nSelecting Latest version of $(Get-PrettyFileName -dirtyFileName $latestObject.fileName)"
    Write-Host "Name: $(Get-PrettyFileName -dirtyFileName $latestObject.fileName)"
    Write-Host "Version: $latestVersion"

    return $latestObject
  }
  catch {
    Write-Host "Failed in Get-LatestVersion: Error: ${$_.Exception.Message}"
    return $null
  }
}

# Gets the version number based on the input like below
# Microsoft.NET.Native.Framework.2.2_2.2.29512.0_x64__8wekyb3d8bbwe.appx
function Get-Version {
  param (
    [Parameter(Mandatory = $true)]
    [string]$content
  )
  $regex = [regex]'\d+\.\d+\.\d+\.\d+'
  if ($regex.IsMatch($content)) {
    return $regex.Match($content).Value
  }
  return $null
}

# Function to terminate running apps before installation
function Stop-AppxProcess {
  param (
    [Parameter(Mandatory = $true)]
    [string]$packageName
  )

  try {
    $processes = Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $_.CommandLine -like "*$packageName*" -or $_.Name -like "*$packageName*"
    }

    foreach ($proc in $processes) {
      try {
        $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object {
          $_.Name -like "*$($proc.Name)*"
        }
        if ($svc) {
          Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        }
      }
      catch {
        Write-Warning "Could not stop service for $($proc.Name): $($_.Exception.Message)"
      }

      try {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
      }
      catch {
        Write-Warning "Could not kill process $($proc.Name): $($_.Exception.Message)"
      }
    }
  }
  catch {
    Write-Warning "Error in Stop-AppxProcess for $packageName`: $($_.Exception.Message)"
  }
}

function Install-StoreItems {
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject[]]$linkObjects,

    [Parameter(Mandatory = $true)]
    [PSCustomObject[]]$StoreInstallReqs
  )

  # Microsoft broke the appx package in PS 7. cant say im surprised
  if ($PSVersionTable.PSVersion.Major -lt 7) {
    Import-Module appx
  }
  else {
    Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue
  }

  $installFileTypes = $StoreInstallReqs | Select-Object -ExpandProperty filetype -Unique

  # Set our search based on the previous info
  # Narrows down the amount of data processed
  $goodItems = @()
  foreach ($item in $installFileTypes) {
    $goodItems += Format-Links -linkObjects $linkObjects -searchEnding $item
  }

  $jobs = @()

  # Override this if its null, needs to match the aval arch in the filenames of the downloaded packages. You can check this on the adguard store page using the product ID provided below
  $hostArch = "*$(Get-CPUArch)*"
  if ($null -ne $hostArch) {

    foreach ($installItem in $StoreInstallReqs) {
      $latestVersion = Get-LatestVersion -targetString $installItem.name -packageArch $hostArch -linkObjects $goodItems -filetype $installItem.filetype

      if ($latestVersion) {
        $itemFileType = $installItem.filetype
        $filename = "$($installItem.name).$itemFileType"
        $prettyName = Get-PrettyFileName -dirtyFileName $filename

        $destinationPath = Join-Path -Path $PWD -ChildPath $filename

        $jobs += Start-Job -ScriptBlock {
          param ($sourceUrl, $destinationPath, $filename, $prettyName)

          Write-Host "`nStarting download: $prettyName"

          Start-BitsTransfer -Source $sourceUrl -Destination $destinationPath

          Write-Host "Finished download: $prettyName"
        } -ArgumentList $latestVersion.downloadLink, $destinationPath, $filename, $prettyName
      }
      else {
        Write-Host "Latest version not found for $(Get-PrettyFileName -dirtyFileName $installItem.name)"
      }
    }
  }
  else {
    Write-Host 'Unknown host architecture, feel free to override this in the Install-StoreItems function'
  }

  # Wait for all jobs to complete
  $jobs | Wait-Job | Out-Null

  # Retrieve job results and remove completed jobs
  $jobs | ForEach-Object {
    Receive-Job -Job $_
    Remove-Job -Job $_ | Out-Null
  }

  foreach ($installItem in $StoreInstallReqs) {
    $itemFileType = $installItem.filetype

    Stop-AppxProcess -packageName $installItem.name
    Start-Sleep 1

    try {
      $filename = "$($installItem.name).$itemFileType"
      $destinationPath = Join-Path -Path $PWD -ChildPath $filename

      Add-AppxPackage -Path $destinationPath
      Write-Host "Successfully installed package: $($installItem.name)"
    }
    catch {
      Write-Host "Failed to install package: $($installItem.name). Error: ${$_.Exception.Message}"
    }
  }
}

### PRODUCT IDS ###
$MSStoreID = '9wzdncrfjbmp'
$StoreInstallReqs = @(
  [PSCustomObject]@{ name = 'Microsoft.UI.Xaml'; filetype = 'appx' },
  [PSCustomObject]@{ name = 'Microsoft.NET.Native.Framework'; filetype = 'appx' },
  [PSCustomObject]@{ name = 'Microsoft.NET.Native.Runtime'; filetype = 'appx' },
  [PSCustomObject]@{ name = 'Microsoft.VCLibs.140.00.UWPDesktop'; filetype = 'appx' },
  [PSCustomObject]@{ name = 'Microsoft.VCLibs.140.00_'; filetype = 'appx' },
  [PSCustomObject]@{ name = 'Microsoft.WindowsStore'; filetype = 'msixbundle' }
)

$DesktopAppInstallerID = '9NBLGGH4NNS1'
$OtherReqs = @(
  [PSCustomObject]@{ name = 'Microsoft.DesktopAppInstaller'; filetype = 'msixbundle' }
)

Start-Setup
$linkObjects = Get-LinksFromHTML -html (Get-CurrentDownloads -productID $MSStoreID )

Install-StoreItems -linkObjects $linkObjects -StoreInstallReqs $StoreInstallReqs

$otherReqItems = Get-LinksFromHTML -html (Get-CurrentDownloads -productID $DesktopAppInstallerID)
Install-StoreItems -linkObjects $otherReqItems -StoreInstallReqs $OtherReqs

if (Get-Module -ListAvailable -Name PSParseHTML) {
  Write-Host 'Removing PSParseHTML'

  [System.GC]::Collect()
  [System.GC]::WaitForPendingFinalizers()

  Get-Module PSParseHTML | Remove-Module -Force -ErrorAction SilentlyContinue
}

# narrow down table to options ending in .appx
# Look for string related to entry != version number
# narrow down the above collection to the latest version number, grab link
# Do this for all items and just hope MS will do their job and keep them all compatible
# Microsoft.NET.Native.Framework.2.2_2.2.29512.0_x64__8wekyb3d8bbwe.appx
# Microsoft.NET.Native.Runtime.2.2_2.2.28604.0_x64__8wekyb3d8bbwe.appx
# Microsoft.VCLibs.140.00_14.0.30704.0_x64__8wekyb3d8bbwe.appx
# Microsoft.WindowsStore_12107.1001.15.0_neutral_~_8wekyb3d8bbwe.appxbundle
