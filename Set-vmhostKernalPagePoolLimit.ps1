<#
.SYNOPSIS  Configures netPagePoolLimitPerGB & netPagePoolLimitCap values for ESXi host

.DESCRIPTION 
 This will update netPagePoolLimitPerGB & netPagePoolLimitCap values in ESXi hosts
 Based on this KB -> https://kb.vmware.com/s/article/76656?lang=en_US
 Each hosts will be put into maintenance mode for the configuration and taken out
 The host will be put into maintenance mode, values changed and rebooted
 Default is 45 mins for MM and reboot
 The script will exit if it takes too long to either go into maintenace mode or to reboot
 You should investigate why and correct the issue 

.NOTES  
 [1.0][25MAR2021][Kelvin][New]: Base version

.REQUIREMENTS 
  - PowerCLI 6+
  - Connected to a vCenter via connect-viserver
  - Logged on with Admin rights
 
.PARAMETER vHost
  Host name to configure

.PARAMETER Cluster
  Cluster name to where you want to configure all the hosts

.PARAMETER HostsEx
  Full path to textt file containing a list of hosts names to exclude
  
.PARAMETER Reboot
  Default is $true, set to $false if you don't want to reboot

.OUTPUT 
  <Scriptname>-yyyMMddHHmm.log

.EXAMPLE
  <Scriptname> -vHost host1.acme.com
  <Scriptname> -Cluster cluster1
  <Scriptname> -Cluster cluster1 -Cluster cluster1 -HostEx .\mylist.txt -Reboot $false
#>

param
(
  [Parameter(Mandatory=$false)]
  [System.String]$vHost = "",
  [Parameter(Mandatory=$false)]
  [System.String]$Cluster = "",
  [Parameter(Mandatory=$false)]
  [ValidateScript({Test-path $_})]
  [System.String]$HostsEx,
  [Parameter(Mandatory=$false)]
  [Switch]$Reboot=$true
)


#Sends output to both console and log file.
Function Write-Log {
  [CmdletBinding()]
  Param(
  [Parameter(Mandatory=$False)]
  [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG","INFO2")]
  [String]$Level = "INFO",
  [Parameter(Mandatory=$True)]
  [string]$logfile,
  [Parameter(Mandatory=$True)]
  [string]$Message,
  [Parameter(Mandatory=$False)]
  [switch]$NoConsole,
  [Parameter(Mandatory=$False)]
  [switch]$NoLog
  )

  $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
  $Line = "$Stamp|$Level|$Message"
  If (!$NoLog) {
    Add-Content $logfile -Value $Line
  }
  if (!$NoConsole) {
    Switch ($Level) {
      "INFO" {Write-Host $Line -foregroundcolor green}
      "INFO2" {Write-Host $Line -foregroundcolor cyan}	  
      "WARN" {Write-Host $Line -foregroundcolor yellow}
      default {Write-Host $Line -foregroundcolor red}
    }
  }
} #end function
 

#Sets hosts to maintenance mode. Will error if beyond 30 mins 
Function Set-VMHostMaint {
  Param(
  [Parameter(Mandatory=$true)]
  [Object]$objHost
  )
    
  $HostState = "Connected"
  switch ($objHost.ConnectionState) {

    "Maintenance" {$HostState="AlreadyInMaint"; break;}

    "Connected"   {
      $objHost | set-vmhost -state Maintenance -confirm:$false -Runasync | out-null
      Start-Sleep -Seconds 5
      $count = 0
      $maxMaintMins = 45
      while ($true) {
        #Refresh the state, cannot use the existing variable as it will not update
        if ( (get-VMHost $objHost.name).ConnectionState -eq "Maintenance") {
          $HostState = "InMaint" 
          break ;
	    }
        else {
	      $count++
          Write-Progress -Activity "Setting host to maintenance mode" -Status "Waited for $($count-1) minutes" -PercentComplete (($count-1)/$maxMaintMins*100)
 	      start-sleep -Seconds 60
         }
        if ($count -gt $maxMaintMins) {
          #Waited too long for maintenance.. quiting
	      break;
	    }
      }
      break;    
    } #end "Connected"
  
  } #end switch

  return $HostState
}
 

Function Set-VMHostReboot {
  Param(
  [Parameter(Mandatory=$true)]
  [Object]$objHost
  )
    
  $HostState = "FailedReboot"
  switch ($objHost.ConnectionState) {

    "Maintenance"  {
      $objHost | restart-vmhost -confirm:$false -Runasync | out-null
      Write-Host "Restarting $($objHost.name) now..." -ForegroundColor Yellow

      $count = 0
      $maxNoRespMins = 10
      while ($true) {
        if ((get-VMHost $objHost.name).ConnectionState -ne "NotResponding") {
	      $count++
          Write-Progress -Activity "Waiting for host to start reboot" -Status "Waited for $($count-1) minutes" -PercentComplete (($count-1)/$maxNoRespMins*100)
 	      start-sleep -Seconds 60
        }
        elseif ((get-VMHost $objHost.name).ConnectionState -eq "NotResponding") {break;}
        if ($count -gt $maxNoRespMins) {break;}
      }

      $count = 0
      $maxRebootMins = 45
      while ($true) {
        #Refresh the state, cannot use the existing variable as it will not update
        if ((get-VMHost $objHost.name).ConnectionState -ne "Maintenance") {
	      $count++
          Write-Progress -Activity "Waiting for host reboot to complete" -Status "Waited for $($count-1) minutes" -PercentComplete (($count-1)/$maxRebootMins*100)
 	      start-sleep -Seconds 60
        }
        elseif ((get-VMHost $objHost.name).ConnectionState -eq "Maintenance") {
          $HostState = "Rebooted"
          break;
        }

        if ($count -gt $maxRebootMins) {break;}
      }
      break;
    } 
  
    default {$HostState="NotInMaint"; break;}

  } #end switch

  return $HostState
}

$vobject = $null

#Check which parameter is given
#precdence is vhost, then cluster
if(![string]::IsNullOrEmpty($vHost)) {            
  $vobject = (Get-VMHost $vHost)  | Sort-Object -Property Name              
}
elseif(![string]::IsNullOrEmpty($Cluster)) {            
  $vobject = (Get-Cluster $Cluster| Get-VMHost)  | Sort-Object -Property Name            
}
else {
  Write-Host No vhost or cluster specified! -foregroundcolor yellow
  return
}

#any hosts to exclude?
if([string]::IsNullOrEmpty($HostsEx)) {            
  $ExcludeList = ""
} else {            
  $ExcludeList = get-content $HostsEx            
}

$ScriptPath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($myInvocation.MyCommand.path)
$DTstamp = (Get-Date).toString("yyyyMMddHHmm")
$Logfile = "$ScriptPath\$ScriptName-$DTstamp.log"

if ($Reboot) {
  Write-Host WARNING Hosts will put into maintenance and rebooted -foregroundcolor yellow
  $Confirm = ""
  $Confirm = Read-Host Please confirm by typing "yes" or Enter to exit
  If ($Confirm.Tolower() -ne "yes") {exit;}
}

foreach ( $vmhost in $vobject) {

  if ($vmhost.name -in $ExcludeList) {
    $Message = "$($VMHost.name)|Skipped as instructed"
    Write-Log -logfile $Logfile -Message $Message
    continue;
  }

  #skip if host is not connected or down
  if ($vmhost.connectionstate -match "(Discon|NotRes)") { 
    $Message = "$($VMHost.name)|Host is $($VMHost.ConnectionState)|No data"
    Write-Log -logfile $Logfile -Message $Message -Level ERROR
    continue ;
  }

  Write-Host "************************************************************************"
  Write-Log -logfile $Logfile -Message "$($vmhost.name)|Set to maintenance... please wait" -level INFO2 -NoLog
  $HostMaintState = Set-VMHostMaint $vmhost
  if ($HostMaintState -match "maint") { 
    Write-Log -logfile $Logfile -Message "$($vmhost.name)|In Maintenance mode" -NoLog
  }
  else { 
    Write-Log -logfile $Logfile -Message "$($vmhost.name)|Failed to set in Maintenance mode" -Level ERROR -NoLog
    Write-Log -logfile $Logfile -Message "$($vmhost.name)|Either took too long or there was an error, exiting..." -Level ERROR -NoLog
    break ;
  }  

  #Start of main change
  
  $esxcli = $vmhost | get-esxcli -V2
  
  $argPPLGB = $esxcli.system.settings.kernel.list.CreateArgs()
  $argPPLGB.option = "netPagePoolLimitPerGB"

  $argPPLCap = $esxcli.system.settings.kernel.list.CreateArgs()
  $argPPLCap.option = "netPagePoolLimitCap"

  $PPLGB = $esxcli.system.settings.kernel.list.invoke($argPPLGB)
  $PPLCap = $esxcli.system.settings.kernel.list.invoke($argPPLCap)
  
  $Message = "$($vmHost.name)|netPagePoolLimitPerGB = $($PPLGB.Configured) , netPagePoolLimitCap = $($PPLCap.Configured)"
  Write-Log -logfile $Logfile -Message $Message

  $argPPLGB_new = $esxcli.system.settings.kernel.set.CreateArgs()
  $argPPLGB_new.setting = "netPagePoolLimitPerGB"
  $argPPLGB_new.value = 15360

  $argPPLCap_new = $esxcli.system.settings.kernel.set.CreateArgs()
  $argPPLCap_new.setting = "netPagePoolLimitCap"
  $argPPLCap_new.value = 1375920

  $Message = "$($vmHost.name)|Setting netPagePoolLimitPerGB value to $($argPPLGB_new.value)"
  Write-Log -logfile $Logfile -Message $Message -Level INFO2

  $IsSetSuccess = $esxcli.system.settings.kernel.set.invoke($argPPLGB_new)
  $PPLGB_new = $esxcli.system.settings.kernel.list.invoke($argPPLGB)
  if ($IsSetSuccess) { 
    $Message = "$($vmHost.name)|New netPagePoolLimitPerGB value is $($PPLGB_new.Configured)"
    Write-Log -logfile $Logfile -Message $Message 
  }
  else { 
    $Message = "$($vmHost.name)|netPagePoolLimitPerGB value failed to set"
    Write-Log -logfile $Logfile -Message $Message -Level ERROR
  }

  $Message = "$($vmHost.name)|Setting netPagePoolLimitCap value to $($argPPLCap_new.value)"
  Write-Log -logfile $Logfile -Message $Message -Level INFO2

  $IsSetSuccess = $esxcli.system.settings.kernel.set.invoke($argPPLCap_new)
  $PPLCap_new = $esxcli.system.settings.kernel.list.invoke($argPPLCap)
    if ($IsSetSuccess) { 
    $Message = "$($vmHost.name)|New netPagePoolLimitCap value is $($PPLCap_new.Configured)"
    Write-Log -logfile $Logfile -Message $Message 
  }
  else { 
    $Message = "$($vmHost.name)|netPagePoolLimitCap value failed to set"
    Write-Log -logfile $Logfile -Message $Message -Level ERROR
  }
  
  
  #End of main changes

  $HostRebootState = "FailedReboot"
  if ($Reboot) {
    Write-Log -logfile $Logfile -Message "$($vmhost.name)|Rebooting host... please wait" -level INFO2 -NoLog
  
    $vmhost = Get-vmhost $vmhost.name
    $HostRebootState = Set-VMHostReboot -objHost $vmhost
    $vmhost = Get-vmhost $vmhost.name
    
    if ($HostRebootState -eq "Rebooted") {
      if ($HostMaintState -eq "AlreadyInMaint") {
        Write-Log -logfile $Logfile -Message "$($vmhost.name)|Was previously in Maint mode, nothing to do" -level INFO2 -NoLog
      }
      else {
        Write-Log -logfile $Logfile -Message "$($vmhost.name)|Taking out of maintenance" -level INFO2 -NoLog
        $vmhost | Set-VMHost -state Connected | out-null
        if ((Get-VMHost $vmhost.name).connectionstate -eq "Connected") {
          Write-Log -logfile $Logfile -Message "$($vmhost.name)|Is online" -NoLog
        }
        else { 
          Write-Log -logfile $Logfile -Message "$($vmhost.name)|Failed to take out of Maintenance" -Level ERROR -NoLog
          Write-Log -logfile $Logfile -Message "$($vmhost.name)|Please check for error, exiting now!" -Level ERROR -NoLog
          break ;
        }
      }
    }
    else {
      Write-Host $vmhost.name : Failed to reboot host in time or host not in maintenace before/after reboot! -ForegroundColor Red
      Write-Host Please check and fix issue, exiting now! -ForegroundColor Red
      break ;
    }

  }

  
} #end foreach loop


