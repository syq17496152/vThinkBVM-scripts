
<#
.SYNOPSIS PowerCLI script:For spectre vulnerability : "How to confirm whether vCenter server, ESXi hypervisor & CPU microcode patches are applied or not?" 
.NOTES  Author:  Vikas Shitole
.NOTES  Site:    www.vThinkBeyondVM.com
.NOTES Reference: http://vthinkbeyondvm.com/powercli-script-confirm-esxi-host-patched-vmware-hypervisor-patched-microcode-spectre-vulnerability/
.NOTES Please add the vCenter server IP/credetails as per your environment
.NOTES Relese notes: 
  VC 6.5 U1g: https://docs.vmware.com/en/VMware-vSphere/6.5/rn/vsphere-vcenter-server-65u1g-release-notes.html
  VC 6.0 U3e: https://docs.vmware.com/en/VMware-vSphere/6.0/rn/vsphere-vcenter-server-60u3e-release-notes.html
  VC 5.5 U3h: https://docs.vmware.com/en/VMware-vSphere/5.5/rn/vsphere-vcenter-server-55u3h-release-notes.html
#>

#vCenter Connection, please modify as per your env.

Connect-VIServer -Server 10.160.20.30 -Protocol https -User administrator@vsphere.local -Password VMware!32


function Get-VMLog{
<# .SYNOPSIS Retrieve the virtual machine logs .DESCRIPTION The function retrieves the logs from one or more virtual machines and stores them in a local folder .NOTES Author: Luc Dekens .PARAMETER VM The virtual machine(s) for which you want to retrieve the logs. .PARAMETER Path The folderpath where the virtual machines logs will be stored. The function creates a folder with the name of the virtual machine in the specified path. .EXAMPLE PS> Get-VMLog -VM $vm -Path "C:\VMLogs"
.EXAMPLE
	PS> Get-VM | Get-VMLog -Path "C:\VMLogs"
#>
 
	param(
	[parameter(Mandatory=$true,ValueFromPipeline=$true)]
	[PSObject[]]$VM,
	[parameter(Mandatory=$true)]
	[string]$Path
	)
 
	process{
		foreach($obj in $VM){
			if($obj.GetType().Name -eq "string"){
				$obj = Get-VM -Name $obj
			}
		}
		$logPath = $obj.Extensiondata.Config.Files.LogDirectory
		$dsName = $logPath.Split(']')[0].Trim('[')
		$vmPath = $logPath.Split(']')[1].Trim(' ')
		$ds = Get-Datastore -Name $dsName
		$drvName = "MyDS" + (Get-Random)
		New-PSDrive -Location $ds -Name $drvName -PSProvider VimDatastore -Root '\' | Out-Null
		Copy-DatastoreItem -Item ($drvName + ":" + $vmPath + "vmware.log") -Destination ($Path + "\" + $obj.Name + "\") -Force:$true
		Remove-PSDrive -Name $drvName -Confirm:$false
	}
}
$report = @()

#Location where vmware.log file gets downloaded
$drive="C:\"
$vmname="MyVM"

# Any of below lines must be found in vmware.log file to confirm microcode & VMware hypervisor patch
$pat1='Capability Found: cpuid.IBRS'
$pat2='Capability Found: cpuid.IBPB'
$pat3='Capabliity Found: cpuid.STIBP'

$clusterName="EVCCluster" #Your cluster name, script assumes that cluster is available
$cluster= Get-Cluster -Name $clusterName

#Get connected hosts from above cluster
$esxhosts = Get-Cluster $cluster | Get-VMHost -State Connected

#Counter used to give unique name to dummyvm, you can use any number of your choice.
$i=45

#Iterating through each host for VM creation and scanning vmware.log file
Foreach ($ESXHost in ($esxhosts)){
	$vm=$vmname+$i
#Creating dummy vm with below configuration
	New-VM -Name $vm -VMHost $ESXHost -ResourcePool $cluster -DiskGB 1 -MemoryGB 1 -DrsAutomationLevel Disabled -DiskStorageFormat Thin
	Start-VM -VM $vm -RunAsync -Confirm:$false  #DRS may powerON this VM on some other host inside the cluster
	$dest=$drive+$vm
	Get-VMLog -VM $vm -Path "C:\"
	if (Get-ChildItem -Path $dest -Filter "*.log" | Where {Get-Content -Path $_.FullName | Select-String -Pattern $pat1}){
 		$row = '' | select HostName, Status
 		$row.HostName = $($ESXHost.name)
 		$row.Status="Patched"
 		$report += $row
 		Write-Host "Matched pattern:"+$pat1+":"+$vm+":"+$($ESXHost.name) 
 }
 ElseIf (Get-ChildItem -Path $dest -Filter "*.log" | Where {Get-Content -Path $_.FullName | Select-String -Pattern $pat2}){
  	$row = '' | select HostName, Status
 	$row.HostName = $($ESXHost.name)
	$row.Status ="Patched"
    $report += $row
    Write-Host "Matched pattern:"+$pat2+":"+$vm+":"+$($ESXHost.name) 
 }
  ElseIf (Get-ChildItem -Path $dest -Filter "*.log" | Where {Get-Content -Path $_.FullName | Select-String -Pattern $pat3}){
   	$row = '' | select HostName, Status
  	$row.HostName = $($ESXHost.name)
 	$row.Status ="Patched"
 	$report += $row
   	Write-Host "Matched pattern:"+$pat3+":"+$vm+":"+$($ESXHost.name) 
 }
 Else{
  	$row = '' | select HostName, Status
 	$row.HostName = $($ESXHost.name)
	$row.Status ="Un-Patched"
  	$report += $row
 	Write-Host "Nothing matched on for VM on host:"$($ESXHost.name) 
 }
 Stop-VM -VM $vm -RunAsync -Confirm:$false
 #you can delete this VM as well to avoid any disk space consumption or minimize the disk size
 $i++
}
#Log the report into this CSV file, you can provide your name
$report | Sort HostName | Export-Csv -Path "D:PatchStatus.csv"

#Disconnect the vCenter server
 Disconnect-VIServer -Confirm:$false
