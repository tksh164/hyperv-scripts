#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    <#
    [Parameter(Mandatory = $true)]
    [string] $VMName,

    [Parameter(Mandatory = $true)]
    [PSCredential] $CredentialForConnectToVM,

    [Parameter(Mandatory = $true)]
    [string] $NewComputerName,

    [Parameter(Mandatory = $true)]
    [string] $IPv4Address,

    [Parameter(Mandatory = $false)]
    [byte] $PrefixLength = 24,

    [Parameter(Mandatory = $true)]
    [string] $DnsSeverAddress
    #>
)

$argumentList = @(
    $NewComputerName,
    $IPv4Address,
    $PrefixLength,
    $DnsSeverAddress
)

Invoke-Command -VMName $VMName -Credential $CredentialForConnectToVM -ArgumentList $argumentList -ScriptBlock {

    param (
        <#
        [Parameter(Mandatory = $true)]
        [string] $NewComputerName,

        [Parameter(Mandatory = $true)]
        [string] $IPv4Address,

        [Parameter(Mandatory = $true)]
        [byte] $PrefixLength,

        [Parameter(Mandatory = $true)]
        [string] $DnsSeverAddress
        #>
    )

    $VerbosePreference = 'Continue'


<#
    # Install the iSCSI feature.
    Install-WindowsFeature -Name FS-iSCSITarget-Server

    # Create a new directory for iSCSI Target virtual disks.
    $vhdxDir = New-Item -ItemType Directory -Path 'C:\iscsi'

    # Create a new iSCSI target for cluster disks.
    $iscsiTarget = New-IscsiServerTarget -TargetName 'SR-ClusterDisk1' -InitiatorId 'IPAddress:192.168.1.51','IPAddress:192.168.1.52'

    # Create new iSCSI virtual disks.
    $vhdxLog = New-IscsiVirtualDisk -SizeBytes 10GB -Path (Join-Path -Path $vhdxDir.FullName -ChildPath 'clusterdisk1-log.vhdx')
    $vhdxData = New-IscsiVirtualDisk -SizeBytes 80GB -Path (Join-Path -Path $vhdxDir.FullName -ChildPath 'clusterdisk1-data.vhdx')

    # Mapping iSCSI virtual disks to iSCSI target.
    Add-IscsiVirtualDiskTargetMapping -TargetName $iscsiTarget.TargetName -Path $vhdxLog.Path
    Add-IscsiVirtualDiskTargetMapping -TargetName $iscsiTarget.TargetName -Path $vhdxData.Path
#>

}
