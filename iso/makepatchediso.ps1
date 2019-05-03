#requires -Version 5
#requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $IsoFilePath,

    [Parameter(Mandatory = $true)]
    [string] $WorkFolderPath,

    [Parameter(Mandatory = $true)]
    [string] $PackageListFile
)

#$IsoFilePath = 'C:\Work\en_windows_server_2019_updated_march_2019_x64_dvd_2ae967ab.iso'
#$WorkFolderPath = 'C:\Work\dismwork'
#$PackageListFile = 'C:\Work\packagelist.txt'

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

$ADK_DISM_EXE = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe'
$ADK_DISM_PSMODULE = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.psd1'
$ADK_OSCDIMG_EXE = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'

function GetPackagePathList
{
    [Cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $PackageListFile
    )

    $packagePaths = @()
    $lines = Get-Content -LiteralPath $PackageListFile -Encoding UTF8
    foreach ($line in $lines)
    {
        # Ignore the commented lines.
        if ((-not [string]::IsNullOrWhiteSpace($line)) -and (-not $line.StartsWith('#')))
        {
            $packagePaths += $line.Trim('"')
        }
    }
    
    ,$packagePaths
}

<#
function Invoke-WindowsImageDeletion
{
    [Cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $WimFilePath,

        [Parameter(Mandatory = $true)]
        [string] $ImageName
    )

    $cmdline = ('&"{0}" /Delete-Image /ImageFile:"{1}" /Name:"{2}" /CheckIntegrity' -f $ADK_DISM_EXE, $WimFilePath, $ImageName)
    Write-Verbose -Message ($cmdline)
    $result = Invoke-Expression -Command $cmdline
    $result
}
#>

function Invoke-WindowsImageCleanup
{
    [Cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ImageFolderPath
    )

    $cmdline = ('&"{0}" /Image:"{1}" /Cleanup-Image /StartComponentCleanup /ResetBase' -f $ADK_DISM_EXE, $ImageFolderPath)
    Write-Verbose -Message ($cmdline)
    $result = Invoke-Expression -Command $cmdline
    $result
}

function Invoke-Oscdimg
{
    [Cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SourceLocation,

        [Parameter(Mandatory = $true)]
        [string] $DestinationFile,

        [Parameter(Mandatory = $false)]
        [string] $BiosBootSectorFile,

        [Parameter(Mandatory = $false)]
        [string] $UefiBootSectorFile,

        [Parameter(Mandatory = $false)]
        [string] $VolumeLabel
    )

    #
    # Oscdimg Command-Line Options
    # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oscdimg-command-line-options
    #

    if ((-not $PSBoundParameters.ContainsKey('BiosBootSectorFile')) -and (-not $PSBoundParameters.ContainsKey('UefiBootSectorFile')))
    {
        throw 'Either BIOS or UEFI or both need as the boot sector file.'
    }

    $cmdlineOptions = @()

    $cmdlineOptions += '-m'  # Ignores the maximum size limit of an image.
    $cmdlineOptions += '-o'  # Uses a MD5 hashing algorithm to compare files.
    $cmdlineOptions += '-u1'  # Produces an image that has both the UDF file system and the ISO 9660 file system.
    $cmdlineOptions += '-udfver102'  # Specifies UDF file system version 1.02.

    if ($PSBoundParameters.ContainsKey('VolumeLabel'))
    {
        $actualVolumeLabel = $VolumeLabel.Replace(' ', '_')
        $cmdlineOptions += ('-l{0}' -f $actualVolumeLabel)  # The volume label.
    }

    $bootEntries = @()

    if ($PSBoundParameters.ContainsKey('BiosBootSectorFile'))
    {
        $biosBootEntry = @()

        # The value to use for the platform ID in the El Torito catalog. 0x00 represents a BIOS system.
        $biosBootEntry += 'p0'

        # Disables floppy disk emulation in the El Torito catalog.
        $biosBootEntry += 'e'

        # The El Torito boot sector file that will be written in the boot sector or sectors of the disk.
        $biosBootEntry += ('b{0}' -f $BiosBootSectorFile)

        $bootEntries += $biosBootEntry -join ','
    }

    if ($PSBoundParameters.ContainsKey('UefiBootSectorFile'))
    {
        $uefiBootEntry = @()

        # The value to use for the platform ID in the El Torito catalog. 0xEF represents a UEFI system.
        $uefiBootEntry += 'pEF'

        # Disables floppy disk emulation in the El Torito catalog.
        $uefiBootEntry += 'e'

        # The El Torito boot sector file that will be written in the boot sector or sectors of the disk.
        $uefiBootEntry += ('b{0}' -f $UefiBootSectorFile)

        $bootEntries += $uefiBootEntry -join ','
    }

    # The boot entries for a multi-boot image.
    $cmdlineOptions += ('-bootdata:{0}#{1}' -f $bootEntries.Length, ($bootEntries -join '#'))

    $cmdlineOptions += ('"{0}"' -f $SourceLocation)
    $cmdlineOptions += ('"{0}"' -f $DestinationFile)

    $cmdline = ('&"{0}" {1}' -f $ADK_OSCDIMG_EXE, ($cmdlineOptions -join ' '))
    Write-Verbose -Message ($cmdline)
    $result = Invoke-Expression -Command $cmdline
    $result
}

# Verify the ADK existence.
Resolve-Path -LiteralPath $ADK_DISM_PSMODULE
Resolve-Path -LiteralPath $ADK_DISM_EXE
Resolve-Path -LiteralPath $ADK_OSCDIMG_EXE

# Import the DISM module from Windows ADK.
Import-Module -Name $ADK_DISM_PSMODULE -Force

# Capture the start time.
$startTime = Get-Date

#
# Mount an ISO file and copy a WIM file to the working directory.
#

try
{
    # Mount an ISO file.
    Write-Verbose -Message ('Mount the ISO file: "{0}"' -f $IsoFilePath)
    $isoVolume = Mount-DiskImage -StorageType ISO -Access ReadOnly -ImagePath $IsoFilePath -PassThru | Get-Volume
    Write-Verbose -Message ('The ISO volume is now showing as "{0}:" on this computer.' -f $isoVolume.DriveLetter)

    # Create a new folder for store the files that copied from the ISO file.
    $isoFolder = New-Item -ItemType Directory -Path (Join-Path -Path $WorkFolderPath -ChildPath 'iso') -Force

    Write-Verbose -Message 'Copy the files contained within the ISO file to the working folder.'
    Copy-Item -Path ('{0}:\*' -f $isoVolume.DriveLetter) -Destination $isoFolder.FullName -Recurse -Force

    $wimFilePath = Join-Path -Path $isoFolder.FullName -ChildPath 'sources\install.wim'
    $workWimFile = Get-Item -LiteralPath $wimFilePath

    # Remove the read-only attribute.
    Set-ItemProperty -LiteralPath $workWimFile.FullName -Name IsReadOnly -Value $false
}
finally
{
    # Dismount the ISO file.
    Write-Verbose -Message 'Dismount the ISO file.'
    Dismount-DiskImage -ImagePath $IsoFilePath | Select-Object -Property 'ImagePath'
}

#
# Select the image to use.
#

Write-Verbose -Message ('Get Windows image information from "{0}".' -f $workWimFile.FullName)
Get-WindowsImage -ImagePath $workWimFile.FullName | Format-List

# Select a Windows image index for apply to the VHD.
$imageIndex = Read-Host -Prompt 'Select an image index for using'

<#
# Remove the unnecessary images.
$deleteLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'dism-delete.log'

Get-WindowsImage -ImagePath $workWimFile.FullName |
    Where-Object -Property 'ImageIndex' -NE -Value $imageIndex |
    ForEach-Object -Process {
        # We use the image name because the image index is changed after deleting the image.
        #Invoke-WindowsImageDeletion -WimFilePath $workWimFile.FullName -ImageName $_.ImageName |
        #    Out-File -Encoding utf8 -LiteralPath $deleteLogFilePath -Append -Force

        Remove-WindowsImage -ImagePath $workWimFile.FullName -Name $_.ImageName
    }
#>

try
{
    #
    # Mount the working Windows image.
    #

    $mountFolder = New-Item -ItemType Directory -Path (Join-Path -Path $WorkFolderPath -ChildPath 'mount') -Force

    Write-Verbose -Message ('Mount the working Windows image "{0}" (Index:{1}) to "{2}".' -f $workWimFile.FullName, $imageIndex, $mountFolder.FullName)
    $mountLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'dism-mount.log'
    Mount-WindowsImage -ImagePath $workWimFile.FullName -Index $imageIndex -Path $mountFolder.FullName -LogLevel WarningsInfo -LogPath $mountLogFilePath

    #
    # Apply updates to the working Windows image.
    # NOTE: Applying updates to selected image only. Other images are not patched.
    #

    # Get the list of package files.
    $packagePaths = GetPackagePathList -PackageListFile $PackageListFile
    Write-Verbose -Message ('Applying {0} package(s) to the working Windows image.' -f $packagePaths.Length)

    # Apply updates to an image.
    $packageLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'dism-package.log'
    foreach ($packagePath in $packagePaths)
    {
        Write-Verbose -Message ('Applying: "{0}"' -f $packagePath)
        Add-WindowsPackage -Path $mountFolder.FullName -PackagePath $packagePath -LogLevel WarningsInfo -LogPath $packageLogFilePath
    }

    #
    # Finalize the working Windows image.
    #

    # Optimize an image.
    Write-Verbose -Message 'Optimize the working Windows image.'
    $optimizeLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'dism-optimize.log'
    Invoke-WindowsImageCleanup -ImageFolderPath $mountFolder.FullName |
        Out-File -Encoding utf8 -LiteralPath $optimizeLogFilePath -Append -Force

    # Commit the changes to an image.
    Write-Verbose -Message 'Commit the changes to the working Windows image.'
    $saveLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'dism-save.log'
    Save-WindowsImage -Path $mountFolder.FullName -CheckIntegrity -LogLevel WarningsInfo -LogPath $saveLogFilePath

    # Unmount the working Windows image.
    Write-Verbose -Message 'Unmount the working Windows image.'
    $unmountLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'dism-unmount.log'
    Dismount-WindowsImage -Path $mountFolder.FullName -Save -CheckIntegrity -LogLevel WarningsInfo -LogPath $unmountLogFilePath
}
catch
{
    Write-Verbose -Message 'Unmount the working Windows image due to the exceptions.'
    $discardUnmountLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'dism-unmount-discard.log'
    Dismount-WindowsImage -Path $mountFolder.FullName -Discard -LogLevel WarningsInfo -LogPath $discardUnmountLogFilePath
}

#
# Create a ISO file.
#

$oscdimgLogFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'oscdimg.log'

$params = @{
    SourceLocation     = $isoFolder.FullName
    DestinationFile    = Join-Path -Path $WorkFolderPath -ChildPath 'test.iso'
    VolumeLabel        = 'CUSTOM_ISO'
    BiosBootSectorFile = Join-Path -Path $isoFolder.FullName -ChildPath 'boot\etfsboot.com'
    UefiBootSectorFile = Join-Path -Path $isoFolder.FullName -ChildPath 'efi\microsoft\boot\efisys.bin'
}
Invoke-Oscdimg @params |
    Out-File -Encoding utf8 -LiteralPath $oscdimgLogFilePath -Append -Force

# Capture the end time.
$endTime = Get-Date

# Show elapsed time.
$endTime - $startTime |
    Select-Object -Property Hours,Minutes,Seconds,Milliseconds |
    Format-Table
