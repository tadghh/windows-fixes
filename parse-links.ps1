# If you are having issues make sure below are installed with admin
# Set-ExecutionPolicy Unrestricted -Force
Write-Output 'Installing modules'
if ($PSVersionTable.PSVersion.Major -lt 7) {
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

	if (-not (Get-Module -ListAvailable -Name PSParseHTML)) {
		Install-Module -Name PSParseHTML -Force
	}
}
else {
	if (-not (Get-Module -ListAvailable -Name PSParseHTML)) {
		Install-Module -Name PSParseHTML -Force
	}
}

if (-not (Get-Module -Name PSParseHTML -ListAvailable)) {
	Import-Module PSParseHTML
}

# Returns the api response from adguard
# TODO if product id is nothing bug occurs
# NOTE dont use this to install a bunch of application across a network. You should be using Intune or the like
# This will make post requests to adguard for every product id, since they return html this will get very expensive with 100+ computers
function Get-CurrentDownloads {
	param (
		[string]$productID

	)
	$url = 'https://store.rg-adguard.net/api/GetFiles'
	$headers = @{
		'User-Agent'   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0'
		'Content-Type' = 'application/x-www-form-urlencoded'
	}

	#Change the product id at the end of the url to make this work with other products
	$body = @{
		type = 'url'
		url  = "https://www.microsoft.com/en-us/p/microsoft-store/$productID"
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
		[string]$dirtyFileName
	)
	if ($dirtyFileName.contains('_')) {
		return $dirtyFileName.Substring(0, $dirtyFileName.indexOf('_'))

	}
	return $dirtyFileName.Substring(0, $dirtyFileName.LastIndexOf(('.')))

}

# Processes the api call to adguard store
# No idea why they return HTML, suppose its to deter this itself
function Get-LinksFromHTML {
	param (
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
	$relaventLinks = @()
	Write-Host 'Finding relavent links'
	foreach ($linkObj in $linkObjects) {
		if ($null -ne $linkObj.fileName) {
			$lastPeriodIndex = $linkObj.fileName.LastIndexOf('.')

			$searchLength = $lastPeriodIndex + $searchEnding.Length
			if ($searchLength -lt $linkObj.fileName.Length) {
				$substringAfterLastPeriod = $linkObj.fileName.Substring($lastPeriodIndex + 1, $searchEnding.Length)
				if ($substringAfterLastPeriod -eq $searchEnding) {
					$relaventLinks += $linkObj
				}
			}
		}
	}
	return $relaventLinks
}


# Gets the current devices cpu arch
# TODO bug: it does in fact not get the current computers arch but the current process
function Get-CPUArch {
	switch ($env:PROCESSOR_ARCHITECTURE) {
		'AMD64' { 'x64' }
		'ARM64' { 'arm64' }
		'ARM' { 'arm' }
		'x86' { 'x86' }
	}
}

# Gets the latest version in comparison to others
function Get-LatestVersion {
	param (
		[Parameter(Mandatory = $true)]

		[string]$targetString,
		[Parameter(Mandatory = $true)]

		[PSCustomObject[]]$linkObjects,
		[string]$filetype
	)
	Write-Host "Selecting Latest version of $(Get-PrettyFileName -dirtyFileName $targetString )"
	# figure out what arch we are running on
	# TODO there is a bug here. running this in x86 or an emulated 64 bit powershell instance will return the incorrect version
	$packageArch = "*$(Get-CPUArch)*"

	if ( $targetString -eq 'Microsoft.WindowsStore' -or $targetString -eq 'Microsoft.DesktopAppInstaller') {
		$packageArch = '*neutral*'
	}
	$filteredObjects = $linkObjects | Where-Object {
		$_.fileName -like "$targetString*" -and $_.fileName -like $packageArch -and $_.fileName -like "*$filetype*"
	}
	if ($filteredObjects.Count -eq 0) {
		Write-Host 'No matching link objects found.'
		return
	}
	# Find the latest version
	$latestObject = $null
	$latestVersion = $null
	foreach ($obj in $filteredObjects) {
		$version = Get-Version -content $obj.fileName
		if ($version) {
			# short circuit evaluation, skips the need to check if $version -gt null
			if ($null -eq $latestVersion -or [version]$version -gt [version]$latestVersion) {
				$latestVersion = $version
				$latestObject = $obj
			}
		}
	}
	Write-Host $(Get-PrettyFileName -dirtyFileName $latestObject.fileName)
	Write-Host $latestVersion
	return $latestObject
}

# Gets the version number based on the input like below
# Microsoft.NET.Native.Framework.2.2_2.2.29512.0_x64__8wekyb3d8bbwe.appx
function Get-Version {
	param (
		[string]$content
	)
	$regex = [regex]'\d+\.\d+\.\d+\.\d+'
	if ($regex.IsMatch($content)) {
		return $regex.Match($content).Value
	}
	return $null
}
function Install-StoreItems {
	param (
		[PSCustomObject[]]$linkObjects,
		[PSCustomObject[]]$StoreInstallReqs
	)

	# Microsoft broke the appx package in PS 7. cant say im surprised
	if ($PSVersionTable.PSVersion.Major -lt 7) {
		Import-Module appx
	}
	else {
		Import-Module appx -UseWindowsPowerShell
	}

	#Get the filetypes
	$installFileTypes = $StoreInstallReqs | Select-Object -ExpandProperty filetype -Unique

	# Set our search based on the previous info
	# Narrows down the amount of data processed
	$goodItems = @()
	foreach ($item in $installFileTypes) {
		$goodItems += Format-Links -linkObjects $linkObjects -searchEnding $item
	}

	# Download multiple files at once
	$jobs = @()
	foreach ($installItem in $StoreInstallReqs) {
		$latestVersion = Get-LatestVersion -targetString $installItem.name -linkObjects $goodItems -filetype $installItem.filetype
		if ($latestVersion) {
			$itemFileType = $installItem.filetype
			$filename = "$($installItem.name).$itemFileType"
			$destinationPath = Join-Path -Path $PWD -ChildPath $filename
			$prettyName = Get-PrettyFileName -dirtyFileName $filename

			$jobs += Start-Job -ScriptBlock {
				param ($sourceUrl, $destinationPath, $filename, $prettyName)

				Write-Host "Starting download: $prettyName from $sourceUrl"

				Start-BitsTransfer -Source $sourceUrl -Destination $destinationPath
				Write-Host "Finished download: $filename"

			} -ArgumentList $latestVersion.downloadLink, $destinationPath, $filename, $prettyName
		}
		else {
			Write-Host "Latest version not found for $(Get-PrettyFileName -dirtyFileName $installItem.name)"
		}
 }

	# Wait for all jobs to complete
	$jobs | Wait-Job | Out-Null

	# Retrieve job results and remove completed jobs
	$jobs | ForEach-Object {
		Receive-Job -Job $_
		Remove-Job -Job $_ | Out-Null
	}
	foreach ($installItem in $StoreInstallReqs) {
		# $latestVersion = Get-LatestVersion -targetString $installItem.name -linkObjects $goodItems
		$filename = "$($installItem.name).$itemFileType"
		$destinationPath = Join-Path -Path $PWD -ChildPath $filename
		Start-Sleep 1
		Add-AppxPackage -Path $destinationPath
 }

}

#9wzdncrfjbmp
$StoreInstallReqs = @(
	[PSCustomObject]@{ name = 'Microsoft.UI.Xaml'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.NET.Native.Framework'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.NET.Native.Runtime'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.VCLibs.140.00.UWPDesktop'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.VCLibs.140.00_'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.WindowsStore'; filetype = 'msixbundle' }
)
#9NBLGGH4NNS1
$OtherReqs = @(
	[PSCustomObject]@{ name = 'Microsoft.DesktopAppInstaller'; filetype = 'msixbundle' }
)

# $linkObjects = Get-LinksFromHTML -html (Get-CurrentDownloads)

# Get the link objects
$linkObjects = Get-LinksFromHTML -html (Get-CurrentDownloads -productID '9wzdncrfjbmp')
# $linkObjects = Get-LinksFromHTML -html (Get-Content -Path './test.html')

Install-StoreItems -linkObjects $linkObjects -StoreInstallReqs $StoreInstallReqs

# Get DesktopAppInstaller
$otherReqItems = Get-LinksFromHTML -html (Get-CurrentDownloads -productID '9NBLGGH4NNS1')
Install-StoreItems -linkObjects $otherReqItems -StoreInstallReqs $OtherReqs


# narrow down table to options ending in .appx
# Look for string related to entry != version number
# narrow down the above collection to the latest version number, grab link
# Do this for all items and just hope MS will do their job and keep them all compatible
# Microsoft.NET.Native.Framework.2.2_2.2.29512.0_x64__8wekyb3d8bbwe.appx
# Microsoft.NET.Native.Runtime.2.2_2.2.28604.0_x64__8wekyb3d8bbwe.appx
# Microsoft.VCLibs.140.00_14.0.30704.0_x64__8wekyb3d8bbwe.appx
# Microsoft.WindowsStore_12107.1001.15.0_neutral_~_8wekyb3d8bbwe.appxbundle