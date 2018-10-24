#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $VMName,

    [Parameter(Mandatory = $true)]
    [PSCredential] $CredentialForConnectToVM
)

$argumentList = @()

Invoke-Command -VMName $VMName -Credential $CredentialForConnectToVM -ArgumentList $argumentList -ScriptBlock {

    param ()

    $VerbosePreference = 'Continue'

    # Install Failover Clustering feature.
    Write-Verbose -Message 'Install Failover Clustering feature.'
    Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools
}
