
#region Parameters
Param(
    [Parameter(Mandatory)]
    [String] $TenantName,

    [Parameter(Mandatory)]
    [String] $TenantId,
    
    [Parameter(Mandatory)]
    [String] $SubscriptionId,
    
    [Parameter(Mandatory)]
    [String] $SPOTenantId,

    [Parameter(Mandatory)]
    [String] $SPOUsername,

    [Parameter(Mandatory)]
    [String] $SPOPassword,
    
    [Parameter(Mandatory)]
    [String] $CertificatePassword,

    [Parameter(Mandatory)]
    [ValidateSet("dev", "qa", "uat", "prod")]
    [string] $Environment,
    
    [Parameter(Mandatory)]
    [string] $InstanceNumber,

    [Parameter(Mandatory)]
    [string] $ApproverEmail,
    
    [Parameter()]
    [String] $SiteAlias = "GovernanceApp",

    [Parameter()]
    [String] $ManagedPath = "sites",

    [Parameter()]
    [String] $ResourceGroupName = "rg-governanceapp-prod-001",

    [Parameter()]
    [String] $Location = "northeurope",

    [Parameter()]
    [String] $AppName = "Governance App",

    [Parameter()]
    [String] $SiteTemplatesListUrl = "ProvisioningTemplates",

    [Parameter()]
    [String] $ProvisioningRequestsListUrl = "Lists/ProvisioningRequests",

    [Parameter()]
    [switch] $SkipDependenciesInstall,

    [Parameter()]
    [switch] $SkipAzADAppCreation,
    
    [Parameter()]
    [switch] $SkipAllAzResourcesDeployment,

    [Parameter()]
    [switch] $SkipAzResourceGroupCreation,

    [Parameter()]
    [switch] $SkipAzFunctionDeployment,

    [Parameter()]
    [switch] $SkipAzLogicAppsDeployment,

    [Parameter()]
    [switch] $SkipAzLogicAppsConnectionsDeployment,
    
    [Parameter()]
    [switch] $SkipAzLogicAppsConnectionsAuthorisation
    
)
#endregion Parameters


#region Imports

# import utils
$psRoot = $PSScriptRoot 
. "${psRoot}/../Utils/Azure.ps1"
. "${psRoot}/../Utils/DependenciesChecker.ps1"

#endregion Imports


#region Dependencies

if (!$SkipDependenciesInstall) {   
    GetModules -ModuleToCheck PnP.PowerShell
    # GetModules -ModuleToCheck Az
}

#endregion Dependencies


#region Variables

# Handle spaces in variables
$AppName = $AppName.Replace(" ", "").ToLower()
$Location = $Location.Replace(" ", "").ToLower()
$ResourceGroupName = $ResourceGroupName.Replace(" ", "")

$global:spoCredentials = (New-Object System.Management.Automation.PSCredential ($SPOUsername, (ConvertTo-SecureString $SPOPassword -AsPlainText -Force)))
$appId = $null

# SharePoint variables
$tenant = "$TenantName.onmicrosoft.com"
$tenantAdminUrl = "https://$TenantName-admin.sharepoint.com"
$siteRelativeUrl = "/$ManagedPath/$SiteAlias"
$siteUrl = "https://$TenantName.sharepoint.com$siteRelativeUrl"

# Certificate variables
$certificatesPath = "${psRoot}/../certificates"

#endregion Variables

#region Functions

function CreateAzureADApp {
    try {
        Write-Host "### AZURE AD APP CREATION ###`nCreating Azure AD App - '$appName'..." -ForegroundColor Yellow
        
        $securedCertificatePassword = $CertificatePassword | ConvertTo-SecureString -Force -AsPlainText

        Write-Host "Connect to SharePoint admin portal using admin account for context" -ForegroundColor Yellow
        Connect-PnPOnline -Url $tenantAdminUrl -Credentials $spoCredentials
        Register-PnPAzureADApp -ApplicationName $AppName -Tenant $tenant -CertificatePassword $securedCertificatePassword -OutPath $certificatesPath -DeviceLogin
        
        Write-Host "### AZURE AD APP CREATION FINISHED ###" -ForegroundColor Green
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "Error occured while creating an Azure AD App: $errorMessage" -ForegroundColor Red
    }
}

#endregion Functions


######################
## Start deployment ##
######################

Write-Host "Governance App" -ForegroundColor Magenta
Write-Host "### DEPLOYMENT SCRIPT STARTED ###" -ForegroundColor Magenta


#region AAD App

# Create/update app registration if required
if (!$SkipAzADAppCreation -and !$appRegistration) {
    CreateAzureADApp
}

# logout of any previous sessions
az logout
Write-Host "Azure CLI sign-in for the SharePoint tenant..." -ForegroundColor Yellow
$spocliLogin = az login --allow-no-subscriptions

# check if app with same name already exists
$appRegistrationCollection = az ad app list --display-name $appName
$appRegistration = $appRegistrationCollection | ConvertFrom-Json
Write-Host "Found $($appRegistration.Count) Azure AD app registrations with the name specified" -ForegroundColor Green

# App already exists -> set AppId variable
if ($appRegistration.Count -gt 0) {
    $appId = $appRegistration.appId
    Write-Host "AppId: $appId"
}
else {
    exit
}

#endregion AAD App

#region Azure

if (!$SkipAllAzResourcesDeployment) {   

    #region azure Connections

    # Initialise connection - Azure CLI    
    # logout of any previous sessions
    az logout
    Write-Host "Azure CLI sign-in..." -ForegroundColor Yellow
    $cliLogin = az login --allow-no-subscriptions
    az account set --subscription $SubscriptionId # set subscription
    
    $email = az ad signed-in-user show | ConvertFrom-Json | Select-Object -Property UserPrincipalName
    # $UserPrincipalName = $email.UserPrincipalName
    # Write-Host "UPN: $UserPrincipalName"
    
    # validate azure location
    ValidateAzureLocation -Location $Location
    Write-Host "Connected to Azure" -ForegroundColor Green

    #endregion azure Connections

    # Create resource group if required
    if (!$SkipAzResourceGroupCreation) {
        
        Write-Host "Creating resource group $ResourceGroupName..." -ForegroundColor Yellow
        az group create -l $Location -n $ResourceGroupName
        Write-Host "Created resource group" -ForegroundColor Green
    }
    
    # Deploy Function
    if (!$SkipAzFunctionDeployment) {

        # array of additional template parameters
        $functionTemplateParameters = @(
            "authId=$appId"
            "authSecret=$CertificatePassword"
            "appId=$AppId"
            "appName=$AppName"
            "environment=$Environment"
            "instanceNumber=$InstanceNumber"
        )
        # array of additional app settings
        $functionAppSettings = @(
            "AuthType=AzureADAppOnly"
            "SPOTenantId=$SPOTenantId"
            "SPOTenantName=$TenantName"
            "SPOManagedPath=$ManagedPath"
            "SPOSiteCollectionRelativeUrl=$siteRelativeUrl"
            "SPOSiteTemplatesListUrl=$siteTemplatesListUrl"
            "SPOProvisioningRequestsListUrl=$provisioningRequestsListUrl"
        )
        
        . "${psRoot}\deploy-az-function.ps1" `
            -TenantName $TenantName `
            -TenantId $TenantId `
            -SubscriptionId $SubscriptionId `
            -Environment $Environment `
            -InstanceNumber $InstanceNumber `
            -CertificatePassword $CertificatePassword `
            -TemplateParameters $functionTemplateParameters `
            -AppSettings $functionAppSettings `
            -SiteAlias $SiteAlias `
            -ManagedPath $ManagedPath `
            -ResourceGroupName $ResourceGroupName `
            -Location $Location `
            -AppName $AppName 
    }

    # Deploy Logic Apps
    if (!$SkipAzLogicAppsDeployment) {

        # Deploy Logic Apps
        . "${psRoot}\deploy-logic-apps.ps1" `
            -SubscriptionId $SubscriptionId `
            -TenantId $TenantId `
            -SiteUrl $siteUrl `
            -ListRelativeUrl $provisioningRequestsListUrl `
            -SPOUsername $SPOUsername `
            -SPOPassword $SPOPassword `
            -Environment $Environment `
            -InstanceNumber $InstanceNumber `
            -ApproverEmail $ApproverEmail `
            -ResourceGroupName $ResourceGroupName `
            -AppName $AppName `
            -SkipAzLogicAppsConnectionsDeployment $SkipAzLogicAppsConnectionsDeployment `
            -SkipAzLogicAppsConnectionsAuthorisation $SkipAzLogicAppsConnectionsAuthorisation
        
    }

    Write-Host "Azure resources deployed`n### AZURE RESOURCES DEPLOYMENT COMPLETE ###" -ForegroundColor Green
}
#endregion Azure

Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY" -ForegroundColor Green