$domainRoot = "D:\Domains\"
$uur = 24
$emailFrom = "monitor@mordamus.nl" 
$emailTo = "admin@mordamus.nl" 
$smtpserver="localhost" 

$styleLow = @"
<style>
TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
TH{border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:OliveDrab  }
TD{border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:LemonChiffon  }
</style>
"@

$styleMedium = @"
<style>
TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
TH{border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:Orange }
TD{border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:LemonChiffon  }
</style>
"@

$styleHigh = @"
<style>
TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
TH{border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:OrangeRed}
TD{border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:LemonChiffon  }
</style>
"@

$analyzedFiles=@()


function whitelistWordpress
{
	Param ([string]$website)
	
	$wordpressFiles = $analyzedFiles | where {$_.type -eq 'file' -and $_.website -eq $website -and  $_.FullName -match "\\wp-content\\" -or $_.FullName -match "\\wp-includes\\" -or $_.FullName -match "\\wp-admin\\"}
	if ($wordpressFiles.count -gt 10)
	{
		Write-Host "Whistelist Wordpress Match:" $website
		Return -500
	}
	else
	{
		Return 0
	}
}

function whitelistFullName
{
	Param ([string]$fullName)
	
	if ($fullName | select-string -pattern addthis-for-wordpress.php, ajax-load-more\\core\\repeater\\default.php,  \\logs\\, \\tmp\\, form-data-log.php, email-traffics-log.php)
	{
		Write-Host "Whistelist FullName Match:" $fullName
		Return -6
	}
	else
	{
		Return 0
	}
}

function blacklistFullName
{
	Param ([string]$fullName)
	
	if ($fullName | select-string -pattern system.php)
	{
		Write-Host "Blacklist FullName Match:" $fullName
		Return 10
	}
	else
	{
		Return 0
	}
}

function blacklistContent
{
	Param ([string]$fullName)
	
	if ( select-string -path $fullName -pattern base64_decode)
	{
		Write-Host "Blacklist Content Match:" $fullName
		Return 30
	}
	else
	{
		Return 0
	}
}

function blacklistModifiedTime
{
	Param ([string]$fullName)

	if ((get-item $fullName).LastWriteTime.hour -lt 7  )
	{
		Write-Host "Blacklist ModifiedTime Match:" $fullName
		Return 5
	}
	else
	{
		Return 0
	}
}

$modifiedFiles = get-childitem $domainRoot -Include *.php -recurse  | where-object {$_.mode -notmatch "d" -and $_.FullName -notmatch "\\cache\\" -and $_.FullName -notmatch "\\templates_c\\"} | where-object {$_.lastwritetime -gt [datetime]::Now.AddHours(-$uur) -or $_.CreationTime -gt [datetime]::Now.AddHours(-$uur)}
foreach ($modifiedFile in $modifiedFiles)
{
	$websiteName = ([uri]$modifiedFile.FullName).segments[4].trim('/') 
	
	$level = 0
	$level += (whitelistWordpress($websiteName))
	$level += (whitelistFullName($modifiedFile.FullName))
	$level += (blacklistFullName($modifiedFile.FullName))
	$level += (blacklistContent($modifiedFile.FullName))
	$level += (blacklistModifiedTime($modifiedFile.FullName))
	
	$websiteSearch=$analyzedFiles | where {$_.website -eq $websiteName -and $_.type -eq 'website'}
	if ($websiteSearch.count -eq 0)
	{
		$website=@{"fullName"=$websiteName;"website"=$websiteName;"level"=$level;"type"="website"}
		$analyzedFiles += new-object pscustomobject -property $website
	}
	else 
	{
		$websiteSearch.level += $level
	}	
	
	$file=@{"fullName"=$modifiedFile.FullName;"website"=$websiteName;"level"=$level;"type"="file"}
	$analyzedFiles += new-object pscustomobject -property $file					
}

$analyzedFiles

$analyzedWebsites = $analyzedFiles | where {$_.type -eq 'website' -and $_.level -ge 0} | Sort-Object level -descending
ForEach ($analyzedWebsite in $analyzedWebsites)
{
	if ($analyzedWebsite.level -lt 0)
	{
		$style = $styleLow
	}
	elseif ($analyzedWebsite.level -lt 4)
	{	
		$style = $styleMedium
	}
	else 
	{
		$style = $styleHigh
	}
	
	if ($analyzedWebsite.level -gt $lowestWebsiteLevel)
	{
		$lowestWebsiteLevel = $analyzedWebsite.level
	}

	$emailMessage += $analyzedFiles | where {$_.website -eq $analyzedWebsite.website} | where-object {$_.level -ge 0} | Sort-Object type, level -descending | ConvertTo-HTML -property fullname, level -head $style
	$emailMessage += "<br />"
}

if ($lowestWebsiteLevel -ge 0)
{
	Write-Host "Sending Report Email"
	$emailSubject="Daily Report: Website changes"
	$smtp=new-object Net.Mail.SmtpClient($smtpServer) 
	$message = New-Object System.Net.Mail.MailMessage $emailFrom, $emailTo
	$message.Subject = $emailSubject
	$message.IsBodyHTML = $true
	$message.Body = $emailMessage
	$smtp.Send($message) 
}