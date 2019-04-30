#requires -Version 5
#requires -RunAsAdministrator
#requires -Modules @{ ModuleName = 'Storage'; ModuleVersion = '2.0.0.0' }
#requires -Modules @{ ModuleName = 'Hyper-V'; ModuleVersion = '2.0.0.0' }
#requires -Modules @{ ModuleName = 'Dism'; ModuleVersion = '3.0' }
#requires -Modules @{ ModuleName = 'Microsoft.PowerShell.Utility'; ModuleVersion = '3.1.0.0' }
#requires -Modules @{ ModuleName = 'Microsoft.PowerShell.Management'; ModuleVersion = '3.1.0.0' }

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = 'Enter the Windows ISO file path (*.iso).')]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [ValidatePattern('.+\.iso$')]
    [string] $IsoFilePath,

    [Parameter(Mandatory = $true, HelpMessage = 'Enter the VHD file path to create (*.vhdx).')]
    [ValidatePattern('.+\.vhdx$')]
    [string] $VhdFilePath,

    [Parameter(Mandatory = $false, HelpMessage = 'Enter the Servicing Stack Update file path (*.msu).')]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [ValidatePattern('.+\.msu$')]
    [string] $SsuFilePath,

    [Parameter(Mandatory = $false, HelpMessage = 'Enter the Cumulative Update file path (*.msu).')]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [ValidatePattern('.+\.msu$')]
    [string] $CUFilePath
)

$VerbosePreference = 'Continue'

function Invoke-BcdBoot
{
    [Cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $CmdlineArgs
    )

    $cmdline = ('C:\Windows\System32\bcdboot.exe {0}' -f ($CmdlineArgs -join ' '))
    Write-Verbose -Message ($cmdline)
    $result = Invoke-Expression -Command $cmdline
    $result
}

# Capture the start time.
$startTime = Get-Date

#
# Mount the Windows image and select the image to apply.
#

Write-Verbose -Message ('Mount the ISO file: "{0}"' -f $IsoFilePath)
$isoVolume = Mount-DiskImage -StorageType ISO -Access ReadOnly -ImagePath $IsoFilePath -PassThru | Get-Volume
Write-Verbose -Message ('The ISO volume is now showing as "{0}:" on this computer.' -f $isoVolume.DriveLetter)

$wimFilePath = ('{0}:\sources\install.wim' -f $isoVolume.DriveLetter)
Write-Verbose -Message ('Get Windows image information from "{0}".' -f $wimFilePath)
Get-WindowsImage -ImagePath $wimFilePath | Format-List

# Select a Windows image index for apply to the VHD.
$imageIndex = Read-Host -Prompt 'Select a image index for applying'

#
# Prepare the VHD. 
#
# UEFI/GPT-based hard drive partitions
# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions
#

Write-Verbose -Message ('Create a new VHD file: "{0}"' -f $VhdFilePath)
$vhdFile = New-VHD -Path $VhdFilePath -Dynamic -SizeBytes 127GB

Write-Verbose -Message 'Mount the VHD and initialize it.'
$vhdDisk = Mount-DiskImage -StorageType VHDX -Access ReadWrite -ImagePath $vhdFile.Path -PassThru |
    Get-Disk |
    Initialize-Disk -PartitionStyle GPT -PassThru

Write-Verbose -Message 'Create a recovery partition on the VHD.'
$vhdDisk |
    New-Partition -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -Size 530MB |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Recovery' -Force |
    Out-Null

Write-Verbose -Message 'Create an EFI system partition on the VHD.'
$systemVolume = $vhdDisk |
    New-Partition -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -Size 100MB -AssignDriveLetter |
    Format-Volume -FileSystem FAT32 -Force
Write-Verbose -Message ('The EFI system partition is now showing as "{0}:" on this computer.' -f $systemVolume.DriveLetter)

<#
Write-Verbose -Message 'Create a Microsoft reserved (MSR) partition on the VHD.'
$vhdDisk |
    New-Partition -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' -Size 16MB |
    Out-Null
#>

Write-Verbose -Message 'Create a boot partition (a basic data partition) on the VHD.'
$bootVolume = $vhdDisk |
    New-Partition -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -UseMaximumSize -AssignDriveLetter |
    Format-Volume -FileSystem NTFS -Force
Write-Verbose -Message ('The boot partition is now showing as "{0}:" on this computer.' -f $bootVolume.DriveLetter)

#
# Apply Windows image and updates to the VHD.
#

Write-Verbose -Message 'Apply the Windows image to the volume on VHD file.'
$bootVolumeRootPath = ('{0}:\' -f $bootVolume.DriveLetter)
$dismLogFilePath = $vhdFile.Path + '.dism.log'
Expand-WindowsImage -ImagePath $wimFilePath -Index $imageIndex -ApplyPath $bootVolumeRootPath -LogLevel WarningsInfo -LogPath $dismLogFilePath

if ($PSBoundParameters.ContainsKey('SsuFilePath'))
{
    Write-Verbose -Message 'Apply the Servicing Stack Update to the Windows image on VHD file.'
    $ssuLogFilePath = $vhdFile.Path + '.ssu.log'
    Add-WindowsPackage -Path $bootVolumeRootPath -PackagePath $SsuFilePath -LogLevel WarningsInfo -LogPath $ssuLogFilePath
}

if ($PSBoundParameters.ContainsKey('CUFilePath'))
{
    Write-Verbose -Message 'Apply the Cumulative Update to the Windows image on VHD file.'
    $cuLogFilePath = $vhdFile.Path + '.cu.log'
    Add-WindowsPackage -Path $bootVolumeRootPath -PackagePath $CUFilePath -LogLevel WarningsInfo -LogPath $cuLogFilePath
}

#
# Create the BCD boot file.
#

Write-Verbose -Message 'Set bootable to the partition.'
$windowsSystemRootPath = ('{0}:\Windows' -f $bootVolume.DriveLetter)
$targetSystemVolumeLetter = ('{0}:' -f $systemVolume.DriveLetter)
$bcdBootLogFilePath = $vhdFile.Path + '.bcdboot.log'
Invoke-BcdBoot -CmdlineArgs $windowsSystemRootPath, '/s', $targetSystemVolumeLetter, '/v', '/f UEFI' |
    Out-File -Encoding utf8 -LiteralPath $bcdBootLogFilePath -Force

#
# Finalizations.
#

Write-Verbose -Message 'Dismount the ISO file.'
Dismount-DiskImage -ImagePath $IsoFilePath | Select-Object -Property 'ImagePath'

Write-Verbose -Message 'Dismount the VHD file.'
Dismount-DiskImage -ImagePath $vhdFile.Path | Select-Object -Property 'ImagePath'

Write-Verbose -Message 'Optimize the VHD file.'
Optimize-VHD -Mode Full -Path $vhdFile.Path

# Show the created VHD file.
Get-ChildItem -LiteralPath $vhdFile.Path | Format-Table

# Capture the end time.
$endTime = Get-Date

# Show elapsed time.
$endTime - $startTime |
    Select-Object -Property Hours,Minutes,Seconds,Milliseconds |
    Format-Table
