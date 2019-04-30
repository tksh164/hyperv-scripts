#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $VMName,

    [Parameter(Mandatory = $true)]
    [PSCredential] $CredentialForConnectToVM,

    [Parameter(Mandatory = $true)]
    [string] $DomainName,

    [Parameter(Mandatory = $true)]
    [PSCredential] $CredentialForDomainJoin
)

$argumentList = @(
    $DomainName,
    $CredentialForDomainJoin
)

Invoke-Command -VMName $VMName -Credential $CredentialForConnectToVM -ArgumentList $argumentList -ScriptBlock {

    param (
        [Parameter(Mandatory = $true)]
        [string] $DomainName,
    
        [Parameter(Mandatory = $true)]
        [PSCredential] $CredentialForDomainJoin
    )

    $VerbosePreference = 'Continue'

    Resolve-DnsName -Name $DomainName

    # Join to a domain.
    Add-Computer -DomainName $DomainName -Credential $CredentialForDomainJoin -Restart -Force
}
