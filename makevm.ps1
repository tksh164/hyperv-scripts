#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $VMName,

    [Parameter(Mandatory = $true)]
    [string] $TemplateVHDFilePath,

    [Parameter(Mandatory = $true)]
    [string] $VMStoreBasePath
)

$ErrorActionPreference = 'Stop'

# Create a new VM store folder if it does not exist.
$vmStoreFolderPath = Join-Path -Path $VMStoreBasePath -ChildPath $VMName
if (-not (Test-Path -LiteralPath $vmStoreFolderPath))
{
    [void] (New-Item -ItemType Directory -Path $vmStoreFolderPath)
}

# Create a new VHD store folder if it does not exist.
$vmVHDStoreFolderPath = Join-Path -Path $vmStoreFolderPath -ChildPath 'Virtual Hard Disks'
if (-not (Test-Path -LiteralPath $vmVHDStoreFolderPath))
{
    [void] (New-Item -ItemType Directory -Path $vmVHDStoreFolderPath)
}

# Create a new OS disk as a differencing disk from the template disk.
$vmOSDiskFilePath = Join-Path -Path $vmVHDStoreFolderPath -ChildPath 'osdisk.vhdx'
$osDisk = New-VHD -Differencing -ParentPath $TemplateVHDFilePath -Path $vmOSDiskFilePath

# Create a new virtual machine.
# The VM configuration store folder 'Virtual Machines' is automatically create.
$params = @{
    Name               = $VMName
    Path               = $VMStoreBasePath
    Version            = [System.Version] '9.0'
    Generation         = 2
    BootDevice         = [Microsoft.HyperV.PowerShell.BootDevice]::VHD
    VHDPath            = $osDisk.Path
    #MemoryStartupBytes = $memoryStartupBytes
    #SwitchName         = ''
    #Prerelease         =
}
$vm = New-VM @params

# Set the VM's processor configurations.
$params = @{
    VMName                         = $vm.Name
    Count                          = 2
    ExposeVirtualizationExtensions = $true
}
Set-VMProcessor @params

# Set the VM's memory configurations.
$params = @{
    VMName               = $vm.Name
    DynamicMemoryEnabled = $true
    StartupBytes         = 2048MB
    MinimumBytes         = 512MB
    MaximumBytes         = 4096MB
}
Set-VMMemory @params

# Set the VM's misc configurations.
$params = @{
    Name                        = $vm.Name
    SnapshotFileLocation        = $vmStoreFolderPath
    CheckpointType              = [Microsoft.HyperV.PowerShell.CheckpointType]::Standard
    AutomaticCheckpointsEnabled = $false
    SmartPagingFilePath         = $vmStoreFolderPath
    BatteryPassthroughEnabled   = $false
    LockOnDisconnect            = [Microsoft.HyperV.PowerShell.OnOffState]::Off
    Notes                       = ''
}
Set-VM @params

Write-Host ('VM Name     : {0}' -f $vm.Name)
Write-Host ('Store Folder: {0}' -f $vmStoreFolderPath)
Write-Host ('Template VHD: {0}' -f $TemplateVHDFilePath)
