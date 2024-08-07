# If you are having issues make sure below are installed with admin
# Set-ExecutionPolicy Unrestricted -Force
# # Import the PSParseHTML module
# Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
# Install-Module -Name PSParseHTML -Force

Import-Module PSParseHTML
# Import-Module appx

# Returns the api response from adguard
function Get-CurrentDownloads {
	$url = 'https://store.rg-adguard.net/api/GetFiles'
	$headers = @{
		'User-Agent'   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0'
		'Content-Type' = 'application/x-www-form-urlencoded'
	}
	$body = @{
		type = 'url'
		url  = 'https://www.microsoft.com/en-us/p/microsoft-store/9wzdncrfjbmp'
		ring = 'RP'
		lang = 'en-US'
	}

	$currentDownloadsHTML = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
	return $currentDownloadsHTML
}

# Function to create a link item
function Save-LinkItem {
	param (
		[string]$href,
		[string]$innerHtml
	)

	return [PSCustomObject]@{
		name    = $href
		content = $innerHtml
	}
}

function Get-PrettyFileName {
	param (
		[string]$dirtyFileName
	)
	return  $dirtyFileName.Substring(0, $dirtyFileName.indexOf('_'))

}

# Processes the api call to adguard store
# No idea why they return HTML, suppose its to deter this itself
function Get-LinksFromHTML {
	param (
		[string]$html
	)
	$linkObjects = @()
	$Objects = ConvertFrom-HTMLAttributes -Content $html -Tag 'a' -ReturnObject

	foreach ($O in $Objects) {
		$linkObjects += Save-LinkItem -href $O.href -innerHtml $O.InnerHtml
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

	foreach ($linkObj in $linkObjects) {
		$lastPeriodIndex = $linkObj.content.LastIndexOf('.')

		$searchLength = $lastPeriodIndex + $searchEnding.Length
		if ($searchLength -lt $linkObj.content.Length) {
			$substringAfterLastPeriod = $linkObj.content.Substring($lastPeriodIndex + 1, $searchEnding.Length)
			if ($substringAfterLastPeriod -eq $searchEnding) {
				$relaventLinks += $linkObj
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

	# figure out what arch we are running on
	# TODO there is a bug here. running this in x86 or an emulated 64 bit powershell instance will return the incorrect version
	$packageArch = "*$(Get-CPUArch)*"

	if ( $targetString -eq 'Microsoft.WindowsStore') {
		$packageArch = '*neutral*'
	}

	$filteredObjects = $linkObjects | Where-Object {
		$_.content -like "$targetString*" -and $_.content -like $packageArch -and $_.content -like "*$filetype*"
	}
	if ($filteredObjects.Count -eq 0) {
		Write-Host 'No matching link objects found.'
		return
	}
	# Find the latest version
	$latestObject = $null
	$latestVersion = $null
	foreach ($obj in $filteredObjects) {
		$version = Get-Version -content $obj.content
		if ($version) {
			# short circuit evaluation, skips the need to check if $version -gt null
			if ($null -eq $latestVersion -or [version]$version -gt [version]$latestVersion) {
				$latestVersion = $version
				$latestObject = $obj
			}
		}
	}
	Write-Host Get-PrettyFileName -dirtyFileName $latestObject.content
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
	Import-Module appx -UseWindowsPowerShell

	$counter = 0

	#Get the filetypes
	$installFileTypes = $StoreInstallReqs | Select-Object -ExpandProperty filetype -Unique

	# Set our search based on the previous info
	$goodItems = @()
	foreach ($item in $installFileTypes) {
		$goodItems += Format-Links -linkObjects $linkObjects -searchEnding $item
	}


	$jobs = @()
	foreach ($installItem in $StoreInstallReqs) {
		$counter++
		$latestVersion = Get-LatestVersion -targetString $installItem.name -linkObjects $goodItems -filetype $installItem.filetype
		$itemFileType = $installItem.filetype
		$filename = "item$counter.$itemFileType"
		$destinationPath = Join-Path -Path $PWD -ChildPath $filename

		# Start a new job for each download
		$jobs += Start-Job -ScriptBlock {
			param ($sourceUrl, $destinationPath, $filename)

			Write-Host "Starting download: $filename from $sourceUrl"

			Start-BitsTransfer -Source $sourceUrl -Destination $destinationPath
			Write-Host "Finished download: $filename"

		} -ArgumentList $latestVersion.name, $destinationPath, $filename
	}

	# Wait for all jobs to complete
	$jobs | Wait-Job

	# Retrieve job results and remove completed jobs
	$jobs | ForEach-Object {
		Receive-Job -Job $_
		Remove-Job -Job $_
	}
	$counter = 0
	foreach ($installItem in $StoreInstallReqs) {
		$counter++
		$latestVersion = Get-LatestVersion -targetString $installItem.name -linkObjects $goodItems
		$itemArch = $installItem.filetype
		$filename = "item$counter.$itemArch"
		$destinationPath = Join-Path -Path $PWD -ChildPath $filename
		Add-AppxPackage -Path $destinationPath
	}

}


$StoreInstallReqs = @(
	[PSCustomObject]@{ name = 'Microsoft.UI.Xaml'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.NET.Native.Framework'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.NET.Native.Runtime'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.VCLibs.140'; filetype = 'appx' },
	[PSCustomObject]@{ name = 'Microsoft.WindowsStore'; filetype = 'msixbundle' }

)


# Get the link objects
$linkObjects = Get-LinksFromHTML -html (Get-CurrentDownloads)
# $linkObjects = Get-LinksFromHTML -html (Get-Content -Path './test.html')
Install-StoreItems -linkObjects $linkObjects -StoreInstallReqs $StoreInstallReqs
#Install-StoreItems -linkObjects $linkObjects -StoreInstallReqs $StoreInstallReqs2


# narrow down table to options ending in .appx
# Look for string related to entry != version number
# narrow down the above collection to the latest version number, grab link
# Do this for all items and just hope MS will do their job and keep them all compatible
# Microsoft.NET.Native.Framework.2.2_2.2.29512.0_x64__8wekyb3d8bbwe.appx
# Microsoft.NET.Native.Runtime.2.2_2.2.28604.0_x64__8wekyb3d8bbwe.appx
# Microsoft.VCLibs.140.00_14.0.30704.0_x64__8wekyb3d8bbwe.appx
# Microsoft.WindowsStore_12107.1001.15.0_neutral_~_8wekyb3d8bbwe.appxbundle