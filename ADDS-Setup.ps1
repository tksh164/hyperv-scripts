#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $VMName,

    [Parameter(Mandatory = $true)]
    [PSCredential] $CredentialForConnectToVM,

    [Parameter(Mandatory = $true)]
    [string] $DomainName,

    [Parameter(Mandatory = $false)]
    [string] $ForestMode = 'WinThreshold',
    
    [Parameter(Mandatory = $false)]
    [string] $DomainMode = 'WinThreshold',

    [Parameter(Mandatory = $false)]
    [securestring] $SafeModeAdministratorPassword,

    [Parameter(Mandatory = $false)]
    [switch] $InstallDns = $true
)

# Using $CredentialForConnectToVM password as $SafeModeAdministratorPassword if it does not provided.
if (-not $PSBoundParameters.Keys.Contains('SafeModeAdministratorPassword'))
{
    $SafeModeAdministratorPassword = $CredentialForConnectToVM.Password
}

$argumentList = @(
    $DomainName,
    $ForestMode,
    $DomainMode,
    $SafeModeAdministratorPassword,
    $InstallDns
)

Invoke-Command -VMName $VMName -Credential $CredentialForConnectToVM -ArgumentList $argumentList -ScriptBlock {

    param (
        [Parameter(Mandatory = $true)]
        [string] $DomainName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Win2008', 'Win2008R2', 'Win2012', 'Win2012R2', 'WinThreshold')]
        [string] $ForestMode,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Win2008', 'Win2008R2', 'Win2012', 'Win2012R2', 'WinThreshold')]
        [string] $DomainMode,

        [Parameter(Mandatory = $true)]
        [securestring] $SafeModeAdministratorPassword,

        [Parameter(Mandatory = $true)]
        [bool] $InstallDns
    )

    $VerbosePreference = 'Continue'

    # Install ADDS role.
    Write-Verbose -Message 'Install ADDS role.'
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

    # Create a new ADDS forest.
    $params = @{
        DomainName = $DomainName
        ForestMode = $ForestMode
        DomainMode = $DomainMode
        SafeModeAdministratorPassword = $SafeModeAdministratorPassword
        InstallDns = $InstallDns
        Force = $true
    }
    Install-ADDSForest @params
}
