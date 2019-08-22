#requires -Version 5
#requires -RunAsAdministrator
<#
.SYNOPSIS
   This script imports a CSV file with the intended VPG fail over order and then performs the specified fail over action. 
.DESCRIPTION
   Detailed explanation of script
.EXAMPLE
   Examples of script execution
.VERSION 
   Applicable versions of Zerto Products script has been tested on.  Unless specified, all scripts in repository will be 5.0u3 and later.  If you have tested the script on multiple
   versions of the Zerto product, specify them here.  If this script is for a specific version or previous version of a Zerto product, note that here and specify that version 
   in the script filename.  If possible, note the changes required for that specific version.  
.LEGAL
   Legal Disclaimer:
----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without 
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability 
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages.  The entire risk arising out of the use or 
performance of the sample scripts and documentation remains with you.
----------------------
#>
#------------------------------------------------------------------------------#
# Declare variables
#------------------------------------------------------------------------------#
#Examples of variables:

##########################################################################################################################
#Any section containing a "GOES HERE" should be replaced and populated with your site information for the script to work.#  
##########################################################################################################################
$ZVMIPAddress = "ZVM IP Address Goes here"
$ZVMPort = "9080"
$ZVMAPIPort = "9669"
$ZVMUser = "PS CMDlet User goes here"
$ZVMPassword = "PS CMDlet Password Goes Here"
$APIUser = "ZVM User goes here"
$APIPassword = "ZVM Password Goes Here"
#------------------------------------------------------------------------------#
# 2. CSV Location - enter the name of the recovery plan location
# The CSV columns are VPGName, Action (Failover,Test - if test used then the commit policy, commit time and shutdown setting do nothing) TimeBeforeNextVPGFailover (seconds), CommitPolicy (none,commit,rollback),CommitTime (seconds), ShutdownPolicy (None, shutdown, forceshutdown), PreFailoverScript (powershell in same directory), PostFailoverScript (same as pre but runs after the TimeBeforeNextVPGFailover period).
# The VPGs are recovered in the order that they are listed in the CSV
#------------------------------------------------------------------------------#
$csvdirectoryandname = "CSV Import Location Goes here"
#------------------------------------------------------------------------------#
# 3. Log file settings where to store it (on the target ZVM running the script) and the share name to allow access to the logs
#------------------------------------------------------------------------------#
$logDirectory = "Log Directory Goes Here"
#------------------------------------------------------------------------------#
# No need to edit ANYTHING BELOW THIS LINE
#------------------------------------------------------------------------------#
Write-Host -ForegroundColor Yellow "Informational line denoting start of script GOES HERE." 
Write-Host -ForegroundColor Red "   Legal Disclaimer:
----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without 
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability 
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages.  The entire risk arising out of the use or 
performance of the sample scripts and documentation remains with you.
----------------------
"
#------------------------------------------------------------------------------#
# Setting log file naming convention
#------------------------------------------------------------------------------#
$now = Get-Date
$logFile = $logDirectory + "\ZERTO-RecoveryPlanLog-" + $now.ToString("yyyy-MM-dd") + "@" + $now.ToString("HH-mm-ss") + ".log"
#------------------------------------------------------------------------------#
# Logging Session Variables
#------------------------------------------------------------------------------#
$startofscript = Get-Date
"$startofscript - Starting Zerto Recovery Plan Failover Script" | out-file $logfile
"$now - ZVMIPAddress = $ZVMIPAddress - ZVMPort = $ZVMPort - ZVMAPIPort = $ZVMAPIPort - ZVMUser = $ZVMUser - ZVMPassword = $ZVMPassword" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Adding VMware and Zerto Powershell Commands
#------------------------------------------------------------------------------#
function LoadSnapin{
  param($PSSnapinName)
  if (!(Get-PSSnapin | where {$_.Name   -eq $PSSnapinName}))
  {Add-pssnapin -name $PSSnapinName}}
LoadSnapin -PSSnapinName   "Zerto.PS.Commands"
#------------------------------------------------------------------------------#
# Building authentication and URLs for API interaction and authentication
#------------------------------------------------------------------------------#
$vpgListApiUrl = "https://" + $ZVMIPAddress + ":"+$ZVMAPIPort+"/v1/vpgs"
$xZertoSessionURI = "https://" + $ZVMIPAddress + ":"+$ZVMAPIPort+"/v1/session/add"
$authInfo = ("{0}:{1}" -f $APIUser,$APIPassword)
$authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
$authInfo = [System.Convert]::ToBase64String($authInfo)
$headers = @{Authorization=("Basic {0}" -f $authInfo)}
$xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $headers -Method POST
$xZertoSession = $xZertoSessionResponse.headers.get_item("x-zerto-session")
$zertoSessionHeader = @{"x-zerto-session"=$xZertoSession}
#------------------------------------------------------------------------------#
# Importing the Recovery Plan CSV
#------------------------------------------------------------------------------#
$csv = import-csv $csvdirectoryandname
#------------------------------------------------------------------------------#
# Logging VPG Check 
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Getting list of VPGs from ZVM: $ZVMIPAddress " | out-file $logfile -append
#------------------------------------------------------------------------------#
# Getting VPG list from ZVM for Checking if VPG exists
#------------------------------------------------------------------------------#
$vpglist = get-protectiongroups -zvmip $ZVMIPAddress -zvmport $ZVMPort -username $ZVMUser -password $ZVMPassword -site all
#------------------------------------------------------------------------------#
# Logging output from VPG list check
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - VPGs found:" | out-file $logfile -append
foreach ($_ in $vpglist)
{"$_" | out-file $logfile -append}
#------------------------------------------------------------------------------#
# Starting Recovery Plan using the CSV imported
#------------------------------------------------------------------------------#
foreach ($vpg in $csv) 
{
#------------------------------------------------------------------------------#
# Setting the current VPG Name variable from the CSV
#------------------------------------------------------------------------------#
$currentvpgselected = $vpg.VPGName
#------------------------------------------------------------------------------#
# Logging the START of Actions being performed for this VPG in the CSV
#------------------------------------------------------------------------------#
$starttime = get-date
"$starttime - Checking VPG: $currentvpgselected exists" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Checking VPG Exists first, also checking the case is correct as the failover cmd issued to Zerto is case sensitive.
#------------------------------------------------------------------------------#
if ($vpglist -ccontains $currentvpgselected)
{$VPGEXists = "TRUE"}
else
{$VPGEXists = "FALSE"}
#------------------------------------------------------------------------------#
# If the VPG exists then continue with running the script for this VPG. Else it will log the result and will move onto the next VPG.
#------------------------------------------------------------------------------#
if ($VPGEXists -eq "TRUE")
{
#------------------------------------------------------------------------------#
# Setting the most recent checkpoint for the VPG as this is required for both FAILOVER and TEST
#------------------------------------------------------------------------------#
$cp_list = get-checkpoints -virtualprotectiongroup $currentvpgselected -zvmip $ZVMIPAddress -zvmport $ZVMPort -username $ZVMUser -password $ZVMPassword -confirm:$false
$last_cp = $cp_list[$cp_list.Count-1]
$latesttimeobjectforFailover = $last_cp | select-object Identifier | select -expandproperty Identifier
$latesttimeobjectforTest = $last_cp | select-object timestamp | select -expandproperty timestamp
#------------------------------------------------------------------------------#
# Checking if Operation is for FAILOVER or a TEST then running the TEST Actions if the VPG is set to TEST in the ACTION column
#------------------------------------------------------------------------------#
if ($vpg.Action -eq "TEST")
{
#------------------------------------------------------------------------------#
# Logging TEST Action
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Starting Failover TEST Actions for VPG: $currentvpgselected" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Running the Pre failover TEST script if specified
#------------------------------------------------------------------------------#
if ($vpg.PreFailoverScript -ne "" -and $vpg.RunScriptsinTest -eq "TRUE") 
{
#------------------------------------------------------------------------------#
# Logging Scripting Action
#------------------------------------------------------------------------------#
$currentPreFailoverScript = $vpg.PreFailoverScript
$now = Get-Date
"$now - Running PRE-Failover script: $currentPreFailoverScript" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Running PRE failover script
#------------------------------------------------------------------------------#
invoke-expression $currentPreFailoverScript
}
#------------------------------------------------------------------------------#
# Logging TEST Action
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Performing Failover TEST for VPG: $currentvpgselected to Checkpoint: $latesttimeobjectforTest Using the below cmd:" | out-file $logfile -append
"$now - failovertest-start -virtualprotectiongroup $currentvpgselected -checkpointdatetime $latesttimeobjectforTest -zvmip $ZVMIPAddress -zvmport $ZVMPort -username $ZVMUser -password $ZVMPassword -confirm:$false" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Running a TEST as this is set as the Action in the CSV
#------------------------------------------------------------------------------#
start-failovertest -virtualprotectiongroup $currentvpgselected -checkpointdatetime $latesttimeobjectforTest -zvmip $ZVMIPAddress -zvmport $ZVMPort -username $ZVMUser -password $ZVMPassword -confirm:$false
#------------------------------------------------------------------------------#
# Running POST failover TEST script if specified
#------------------------------------------------------------------------------#
if ($vpg.PostFailoverScript -ne "" -and $vpg.RunScriptsinTest -eq "TRUE")
{
#------------------------------------------------------------------------------#
# Setting time to before running Post failover TEST script
#------------------------------------------------------------------------------#
$currentPostFailoverScriptDelay = $vpg.PostFailoverScriptDelay
#------------------------------------------------------------------------------#
# Logging time to sleep before starting Post failover Test script
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Waiting: $currentPostFailoverScriptDelay Seconds before running POST Failover Test Script" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Applying currentPostFailoverScriptDelay value from CSV
#------------------------------------------------------------------------------#
sleep $currentPostFailoverScriptDelay
#------------------------------------------------------------------------------#
# Logging Scripting Action
#------------------------------------------------------------------------------#
$currentPostFailoverScript = $vpg.PostFailoverScript
$now = Get-Date
"$now - Running POST-Failover script: $currentPostFailoverScript" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Running POST failover script
#------------------------------------------------------------------------------#
invoke-expression $currentPostFailoverScript
}
#------------------------------------------------------------------------------#
# Setting time to sleep before failing over next VPG
#------------------------------------------------------------------------------#
$currentNextVPGFailoverDelay = $vpg.NextVPGFailoverDelay
#------------------------------------------------------------------------------#
# Logging time to sleep before starting TEST of next VPG
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Waiting: $currentNextVPGFailoverDelay Seconds before starting action for next VPG" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Applying currentNextVPGFailoverDelay value from CSV
#------------------------------------------------------------------------------#
sleep $currentNextVPGFailoverDelay
#------------------------------------------------------------------------------#
# End of the block for TEST Actions. Will now repeat for the next VPG in the CSV until finished.
#------------------------------------------------------------------------------#
}
#------------------------------------------------------------------------------#
# Checking if Operation is for FAILOVER or a TEST then running the FAILOVER Actions if the VPG is set to FAILOVER in the ACTION column
#------------------------------------------------------------------------------#
if ($vpg.Action -eq "FAILOVER")
{
#------------------------------------------------------------------------------#
# Logging FAILOVER Action
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Starting FAILOVER Actions for VPG: $currentvpgselected" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Running a FAILOVER as this is set as the Action in the CSV
# Getting the ID of the VPG then setting the variable using the API. Only needed for a Failover, not Test
#------------------------------------------------------------------------------#
$vpglistfromAPI = Invoke-RestMethod -Uri $vpgListApiUrl -TimeoutSec 100 -Headers $zertoSessionHeader -Method GET
foreach ($vpgsAPI in $vpglistfromAPI | where {$_.VpgName -eq $currentvpgselected})
{
$vpgidselected = $vpgsAPI.VpgIdentifier
Write-Host $vpgid
}
#------------------------------------------------------------------------------#
# Building URL for failover action
#------------------------------------------------------------------------------#
$commitpolicyselected = $vpg.CommitPolicy
$committimeselected = $vpg.CommitTime
$Shutdownpolicyselected = $vpg.ShutdownPolicy
$requestbody = "{""CheckpointIdentifier"":" + $latesttimeobjectforFailover + ",""CommitPolicy"":""" + $commitpolicyselected + """,""ShutdownPolicy"":""" + $Shutdownpolicyselected + """,""TimeToWaitBeforeShutdownInSec"":" + $committimeselected
if ($vpg.CommitPolicy -eq "commit")
{
$requestbody = $requestbody + ",""IsReverseProtection"":""true"""
}
$requestbody = $requestbody + "}"
$currentfailoverURL = "https://" + $ZVMIPAddress + ":" + $ZVMAPIPort + "/v1/vpgs/" + $vpgidselected + "/failover"
#------------------------------------------------------------------------------#
# Running the Pre failover script if specified
#------------------------------------------------------------------------------#
if ($vpg.PreFailoverScript -ne "" -and $vpg.RunScriptsinTest -eq "TRUE") 
{
#------------------------------------------------------------------------------#
# Logging Scripting Action
#------------------------------------------------------------------------------#
$currentPreFailoverScript = $vpg.PreFailoverScript
$now = Get-Date
"$now - Running PRE-Failover script: $currentPreFailoverScript" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Running PRE failover script
#------------------------------------------------------------------------------#
invoke-expression $currentPreFailoverScript
}
#------------------------------------------------------------------------------#
# Logging FAILOVER Action
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Performing FAILOVER for VPG: $currentvpgselected  to Checkpoint: $latesttimeobjectforFailover Using the below cmd:" | out-file $logfile -append
"$now - invoke-webrequest -uri $currentfailoverURL -headers $zertoSessionHeader -Body $requestbody -ContentType ""application/json"" -method POST"  | out-file $logfile -append
#------------------------------------------------------------------------------#
# Initiating failover for VPG
#------------------------------------------------------------------------------#
invoke-webrequest -uri $currentfailoverURL -headers $zertoSessionHeader -Body $requestbody -ContentType "application/json" -method POST
#------------------------------------------------------------------------------#
# Running Post failover script if specified
#------------------------------------------------------------------------------#
if ($vpg.PostFailoverScript -ne "" -and $vpg.RunScriptsinTest -eq "TRUE")
{
#------------------------------------------------------------------------------#
# Setting time to before running Post failover script
#------------------------------------------------------------------------------#
$currentPostFailoverScriptDelay = $vpg.PostFailoverScriptDelay
#------------------------------------------------------------------------------#
# Logging time to sleep before starting Post failover script
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Waiting: $currentPostFailoverScriptDelay Seconds before running POST Failover Script" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Applying currentPostFailoverScriptDelay value from CSV
#------------------------------------------------------------------------------#
sleep $currentPostFailoverScriptDelay
#------------------------------------------------------------------------------#
# Logging Scripting Action
#------------------------------------------------------------------------------#
$currentPostFailoverScript = $vpg.PostFailoverScript
$now = Get-Date
"$now - Running POST-Failover script: $currentPostFailoverScript" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Running POST failover script
#------------------------------------------------------------------------------#
invoke-expression $currentPostFailoverScript
}
#------------------------------------------------------------------------------#
# Setting time to sleep before failing over next VPG
#------------------------------------------------------------------------------#
$currentNextVPGFailoverDelay = $vpg.NextVPGFailoverDelay
#------------------------------------------------------------------------------#
# Logging time to sleep before failing over next VPG
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - Waiting: $currentNextVPGFailoverDelay Seconds before starting action for next VPG" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Applying currentNextVPGFailoverDelay value from CSV
#------------------------------------------------------------------------------#
sleep $currentNextVPGFailoverDelay
#------------------------------------------------------------------------------#
# End of the block for Failover Actions.
#------------------------------------------------------------------------------#
}
#------------------------------------------------------------------------------#
# End of the block for when the VPG exists. Will now repeat for the next VPG in the CSV until finished.
#------------------------------------------------------------------------------#
}
#------------------------------------------------------------------------------#
# End of for each VPG Actions. Will now repeat for the next VPG in the CSV until finished.
#------------------------------------------------------------------------------#
if ($VPGEXists -eq "FALSE")
{
#------------------------------------------------------------------------------#
# Logging VPG Not FOUND result
#------------------------------------------------------------------------------#
$now = Get-Date
"$now - $currentvpgselected Not FOUND in VPG List. Check VPG exists, spaces and case sensitivity between CSV and Zerto." | out-file $logfile -append
}
#------------------------------------------------------------------------------#
# Logging the END of Actions being performed for this VPG in the CSV
#------------------------------------------------------------------------------#
$endtime = Get-Date
"$endtime - Finished actions for VPG: $currentvpgselected" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Calculating time it took to execute the script for this VPG
#------------------------------------------------------------------------------#
$timedifferencebeforerounding = new-timespan -start $starttime -end $endtime | select-object totalseconds -expandproperty totalseconds
$timedifference = "{0:N2}" -f $timedifferencebeforerounding
"$endtime - Taken: $timedifference Seconds to Execute Actions for VPG: $currentvpgselected" | out-file $logfile -append
"$endtime - Continuing to next VPG in CSV" | out-file $logfile -append
} 
#------------------------------------------------------------------------------#
# End of script time taken
#------------------------------------------------------------------------------#
$endofscript = Get-Date
"$endofscript - Ended Zerto Recovery Plan Failover Script" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Calculating time it took to execute the script for this VPG
#------------------------------------------------------------------------------#
$scripttimedifferencebeforerounding = new-timespan -start $startofscript -end $endofscript | select-object totalseconds -expandproperty totalseconds
$scripttimedifference = "{0:N2}" -f $scripttimedifferencebeforerounding
"$endtime - Taken: $scripttimedifference Seconds to Execute the Recovery Plan" | out-file $logfile -append
#------------------------------------------------------------------------------#
# Exiting script
#------------------------------------------------------------------------------#
exit
