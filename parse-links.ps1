# Import the PSParseHTML module
Import-Module 'C:\Users\tadghh\Documents\PowerShell\Modules\PSParseHTML'

# Function to process the HTML input
function Get-LinksFromHTML {
	param (
		[string]$html
	)
	$Objects = ConvertFrom-HTMLAttributes -Url 'file:///D:/Personal/Projects/windows-fixes-scripts/windows-fixes/test.html' -Tag 'a' -ReturnObject
	Write-Output $Objects
	foreach ($O in $Objects) {
		Write-Output 'ass'
		[PSCUstomObject] @{
			name = $O.href
			# content = $O.content
			# comment = $O.comment
		}
	}
	$Output = ConvertFrom-HtmlTable -Content $html
	Write-Output $Output
	Write-Output 'yo'
	# foreach ($O in $Output) {
	# 	$Header = ConvertFrom-HTMLAttributes -Content $O.InnerHtml -Tag 'td'
	# 	# $List = ConvertFrom-HTMLAttributes -Content $Header.InnerHtml -Tag 'a'
	# 	Write-Output $Header
	# 	# $List
	# }
	# Parse the HTML
	# $parsedHtml = ConvertFrom-HtmlTable -Content $html -Verbose

	# Write-Output $parsedHtml

}

# Read HTML input from pipeline
$htmlContent = ''
while ($line = [Console]::In.ReadLine()) {
	$htmlContent += $line + "`n"
}

# Get the link objects
$linkObjects = Get-LinksFromHTML -html $htmlContent

# Output the link objects
$linkObjects | Format-Table -AutoSize

# # Return the final array of link objects
# return $linkObjects
