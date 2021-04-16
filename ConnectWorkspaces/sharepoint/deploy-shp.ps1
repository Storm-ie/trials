
# Parameters
Param(
    [Parameter(Mandatory = $true,
        ValueFromPipeline = $true)]
    [String]
    $TenantName,

    [Parameter(Mandatory = $true,
        ValueFromPipeline = $true)]
    [String]
    $ServiceAccountUPN,

    [Parameter(Mandatory = $true,
        ValueFromPipeline = $true)]
    [string]
    $ApprovalTeamId,

    [Parameter(Mandatory = $false,
        ValueFromPipeline = $true)]
    [String]
    $RequestsSiteName = "Governance App",

    [Parameter(Mandatory = $false,
        ValueFromPipeline = $true)]
    [String]
    $RequestsSiteDesc = "Site for Governance App",

    [Parameter(Mandatory = $false,
        ValueFromPipeline = $true)]
    [String]
    $ManagedPath = "sites",

    [Parameter(Mandatory)]
    [String] $SPOUsername,

    [Parameter(Mandatory)]
    [String] $SPOPassword,

    [Parameter(Mandatory = $false,
        ValueFromPipeline = $true)]
    [switch]
    $SkipSharePoint = $false,
    
    [Parameter(Mandatory = $false,
        ValueFromPipeline = $true)]
    [switch]
    $SkipPowerShellModules = $false,

    [Parameter(Mandatory = $false,
        ValueFromPipeline = $true)]
    [String]
    $requestsInternalListName = "ProvisioningRequests",

    [Parameter(Mandatory = $false,
        ValueFromPipeline = $true)]
    [String]
    $customPropertiesInternalListName = "ProvisioningCustomProperties"
)
#endregion Parameters

$global:spoCredentials = (New-Object System.Management.Automation.PSCredential ($SPOUsername, (ConvertTo-SecureString $SPOPassword -AsPlainText -Force)))

#region Imports

# import utils
$psRoot = $PSScriptRoot 
. "${psRoot}/../Utils/Azure.ps1"
. "${psRoot}/../Utils/DependenciesChecker.ps1"

#endregion Imports

# region Dependencies

if (!$SkipPowerShellModules) {   
    GetModules -ModuleToCheck Microsoft.Online.Sharepoint.Powershell
    GetModules -ModuleToCheck SharePointPnPPowerShellOnline
    GetModules -ModuleToCheck WriteAscii
}

#endregion Dependencies

# SharePoint variables
$tenantUrl = "https://$TenantName.sharepoint.com"
$tenantAdminUrl = ("https://$TenantName-admin.sharepoint.com");

# Remove any spaces in the site name to create the alias
$textInfo = (Get-Culture).TextInfo
$requestsSiteAlias = $RequestsSiteName -replace (' ', '')
$requestsSiteUrl = "https://$TenantName.sharepoint.com/$ManagedPath/$requestsSiteAlias";

# Global variables
$global:requestsListId = $null

######################
## Start deployment ##
######################

Write-Ascii -InputObject "Governance App - Storm" -ForegroundColor Magenta

Write-Host "### DEPLOYMENT SCRIPT STARTED ###" -ForegroundColor Magenta



if (!$SkipSharePoint) {

    # Getting tenant app catalog
    try {
        Connect-PnPOnline -Url $requestsSiteUrl -Credentials $spoCredentials
        
        # Create the Site Collection if it doesn't exist and apply PnP Provisioning Templates
        . "${psRoot}\deploy-shp-core.ps1" -TenantAdminSiteUrl $tenantAdminUrl -TargetSiteCollectionTitle $RequestsSiteName -TargetSiteCollectionDescription $RequestsSiteDesc -TargetSiteCollectionOwner $SPOUsername -TargetSiteCollectionServiceAccount $ServiceAccountUPN -TargetSiteCollectionUrl $requestsSiteUrl -SPOUsername $SPOUsername -SPOPassword $SPOPassword       
    
        Connect-PnPOnline -Url $requestsSiteUrl -Credentials $spoCredentials
    }
    catch {
        # Create the Site Collection if it doesn't exist and apply PnP Provisioning Templates
        . "${psRoot}\deploy-shp-core.ps1" -TenantAdminSiteUrl $tenantAdminUrl -TargetSiteCollectionTitle $RequestsSiteName -TargetSiteCollectionDescription $RequestsSiteDesc -TargetSiteCollectionOwner $SPOUsername -TargetSiteCollectionServiceAccount $ServiceAccountUPN -TargetSiteCollectionUrl $requestsSiteUrl -SPOUsername $SPOUsername -SPOPassword $SPOPassword       

        Connect-PnPOnline -Url $requestsSiteUrl -Credentials $spoCredentials
    }

    $appCatalogUrl = Get-PnPTenantAppCatalogUrl
    $global:requestsListId = Get-PnPList -Identity Lists/$requestsInternalListName
    $global:customPropertiesListId = Get-PnPList -Identity Lists/$customPropertiesInternalListName
    Disconnect-PnPOnline;
    
    # Adding default settings list item;
    try {
        Connect-PnPOnline -Url $appCatalogUrl -Credentials $spoCredentials

        $oListItems = Get-PnPListItem -List "SettingsTeamsRequest";

        if ($oListItems.Count -eq 0) {
            $oListItem = Add-PnPListItem -List "SettingsTeamsRequest" -Values @{
                "Title"                  = "Governance App - Default settings"
                "listId"                 = $global:requestsListId.Id
                "listCustomPropertiesId" = $global:customPropertiesListId.Id
                "webUrl"                 = $requestsSiteUrl
                "groupId"                = $ApprovalTeamId
            };
        }
        Disconnect-PnPOnline;        
    }
    catch {
        
    }
}

Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY" -ForegroundColor Green