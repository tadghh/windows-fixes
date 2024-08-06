# Import the PSParseHTML module
Import-Module 'C:\Users\tadghh\Documents\PowerShell\Modules\PSParseHTML'

# Function to process the HTML input
function Get-LinksFromHTML {
	param (
		[string]$html
	)

	# Initialize an array to hold the objects
	$linkObjects = @()

	# Convert HTML to objects
	$Objects = ConvertFrom-HTMLAttributes -Content $html -Tag 'a' -ReturnObject

	foreach ($O in $Objects) {
		# Create a new PSCustomObject and add it to the array
		$linkObjects += [PSCustomObject]@{
			name    = $O.href
			content = $O.InnerHtml
			# comment = $O.comment
		}
	}

	# Return the final array of link objects
	return $linkObjects
}

# Read HTML input from pipeline
$htmlContent = ''
while ($line = [Console]::In.ReadLine()) {
	$htmlContent += $line + "`n"
}

# Get the link objects
$linkObjects = Get-LinksFromHTML -html $htmlContent

# Output the link objects
$linkObjects | Format-Table -Property content

# narrow down table to options ending in .appx
# Look for string related to entry != version number
# narrow down the above collection to the latest version number, grab link
# Do this for all items and just hope MS will do their job and keep them all compatible
# Microsoft.NET.Native.Framework.2.2_2.2.29512.0_x64__8wekyb3d8bbwe.appx
# Microsoft.NET.Native.Runtime.2.2_2.2.28604.0_x64__8wekyb3d8bbwe.appx
# Microsoft.VCLibs.140.00_14.0.30704.0_x64__8wekyb3d8bbwe.appx
# Microsoft.WindowsStore_12107.1001.15.0_neutral_~_8wekyb3d8bbwe.appxbundle