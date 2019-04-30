#Requires -RunAsAdministrator

[CmdletBinding()]
param (
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
)

$argumentList = @(
    $NewComputerName,
    $IPv4Address,
    $PrefixLength,
    $DnsSeverAddress
)

Invoke-Command -VMName $VMName -Credential $CredentialForConnectToVM -ArgumentList $argumentList -ScriptBlock {

    param (
        [Parameter(Mandatory = $true)]
        [string] $NewComputerName,

        [Parameter(Mandatory = $true)]
        [string] $IPv4Address,

        [Parameter(Mandatory = $true)]
        [byte] $PrefixLength,

        [Parameter(Mandatory = $true)]
        [string] $DnsSeverAddress
    )

    $VerbosePreference = 'Continue'

    # Change the first connected network adapter settings.
    $netAdapter = Get-NetAdapter |
        Where-Object -Property 'MediaConnectionState' -EQ -Value Connected |
        Sort-Object -Property 'InterfaceIndex' |
        Select-Object -First 1

    if ($netAdapter -eq $null)
    {
        Write-Error -Message 'Connected network adapter not found.'
        return
    }

    Write-Verbose -Message ('Change the network adapter "{0}" settings.' -f $netAdapter.Name)

    # Disable DHCP.
    Set-NetIPInterface -InterfaceIndex $netAdapter.InterfaceIndex -PolicyStore PersistentStore -AddressFamily IPv4 -Dhcp Disabled
    Write-Verbose -Message ('DHCP of the network adapter "{0}" has been disabled.' -f $netAdapter.Name)

    # Set IP address.
    New-NetIPAddress -InterfaceIndex $netAdapter.InterfaceIndex -AddressFamily IPv4 -IPAddress $IPv4Address -PrefixLength $PrefixLength
    Write-Verbose -Message ('Added IP address {0}/{1} to the network adapter "{2}" settings.' -f $IPv4Address,$PrefixLength,$netAdapter.Name)

    # Set DNS server address.
    Set-DnsClientServerAddress -InterfaceIndex $netAdapter.InterFaceIndex -ServerAddresses $DnsSeverAddress
    Write-Verbose -Message ('Added DNS server {0} to the network adapter "{1}" settings.' -f $DnsSeverAddress,$netAdapter.Name)

    # Change the computer name.
    Rename-Computer -NewName $NewComputerName
    Write-Verbose -Message ('Renamed the computer name to "{0}".' -f $NewComputerName)

    # Reboot the computer.
    Restart-Computer
}
