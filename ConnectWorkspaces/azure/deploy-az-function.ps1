
# Parameters
Param(
    [Parameter(Mandatory)]
    [String] $TenantName,

    [Parameter(Mandatory)]
    [String] $TenantId,

    [Parameter(Mandatory)]
    [String] $SubscriptionId,
    
    [Parameter(Mandatory)]
    [ValidateSet("dev", "qa", "uat", "prod")]
    [string] $Environment,
    
    [Parameter(Mandatory)]
    [string] $InstanceNumber,

    [Parameter()]
    [String] $CertificatePassword = "",
    
    [Parameter()]
    [String[]]$TemplateParameters = @(),

    [Parameter()]
    [String[]]$AppSettings = @(),
    
    [Parameter()]
    [String] $SiteAlias = "GovernanceApp",

    [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
    [String] $ManagedPath = "sites",

    [Parameter()]
    [String] $ResourceGroupName = "rg-governanceapp-prod-001",

    [Parameter()]
    [String] $Location = "northeurope",

    [Parameter()]
    [String] $AppName = "Governance App",
    
    [Parameter()]
    [String] $AppId,

    [Parameter()]
    [switch] $SkipARMTemplateDeployment,

    [Parameter()]
    [switch] $SkipCertificateDeployment,
    
    [Parameter()]
    [switch] $SkipAppSettingsDeployment,

    [Parameter()]
    [switch] $SkipZipDeployment

)

# Global variables
# Handle spaces in variables
$AppName = $AppName.Replace(" ", "").ToLower()
$Location = $Location.Replace(" ", "").ToLower()
$ResourceGroupName = $ResourceGroupName.Replace(" ", "").ToLower()

$certificate = $null
$certificateAppSetting = $null

# Azure variables
$psRoot = $PSScriptRoot 
$AzureTemplatesPath = $psRoot
$certificatesPath = "${psRoot}/../certificates"
$functionSolutionPath = "${psRoot}/../Solution"
$functionName = "func-$AppName-$Environment-$InstanceNumber"
$keyVaultName = "kv-$AppName-$Environment-$InstanceNumber"


######################
## Start deployment ##
######################

Write-Host "Deploying Azure Function..." -ForegroundColor Yellow

if (!$SkipARMTemplateDeployment) {
    
    # get objectId of current user account
    $userObjectId = az ad signed-in-user show --query "objectId"
    Write-Host "User ObjectId: $userObjectId" -ForegroundColor Green
    # add user objectId as parameter to the template
    $TemplateParameters = @("userObjectId=$userObjectId") + $TemplateParameters
    
    # deploy resources
    az deployment group create `
        --resource-group $ResourceGroupName `
        --subscription $SubscriptionId `
        --template-file "$AzureTemplatesPath\Function\functionTemplate.json" `
        --parameters "$AzureTemplatesPath\Function\function-parameters-$Environment.json" `
        --parameters $TemplateParameters #"userObjectId=$userObjectId" "authId=$Username" "authSecret=$Password" "appId=$AppId" "appName=$AppName" "environment=$Environment" "instanceNumber=$InstanceNumber"
}
    

if (!$SkipCertificateDeployment) {
    
    Write-Host "Uploading certificate to KeyVault..." -ForegroundColor Yellow
    "$certificatesPath/$AppName.pfx"
    # upload certificate to Key Vault
    az keyvault certificate import `
        --vault-name $keyVaultName `
        --file "$certificatesPath/$AppName.pfx" `
        --name $AppName `
        --password $CertificatePassword
        
    # get certificate reference from KeyVault and generate app setting
    $certificate = az keyvault certificate show --vault-name $keyVaultName --name $AppName | ConvertFrom-Json
    $certificateAppSetting = "@Microsoft.KeyVault^^(SecretUri=" + $certificate.sid + "^^)"
    # add certificate info to app settings
    $AppSettings += @("Certificate=$certificateAppSetting")
}
    
if (!$SkipAppSettingsDeployment) {
    
    Write-Host "Updating Function app settings..." -ForegroundColor Yellow
    # add extra function app settings not included on ARM template as they are SharePoint specific
    az functionapp config appsettings set `
        --resource-group $ResourceGroupName `
        --name $functionName `
        --settings $AppSettings # "SPOTenantId=$TenantId" "SPOTenantName=$TenantName" "SPOManagedPath=$ManagedPath" "SPOSiteCollectionRelativeUrl=$siteRelativeUrl" "SPOSiteTemplatesListUrl=$siteTemplatesListUrl" "SPOProvisioningRequestsListUrl=$provisioningRequestsListUrl" "Certificate=$certificateAppSetting"
}

if (!$SkipZipDeployment) {
    
    # deploy Zip Package to function
    $FunctionZipPath = "$AzureTemplatesPath/Function/assets/Function.zip"
    az webapp deployment source config-zip --resource-group $ResourceGroupName --name $functionName --src $FunctionZipPath
}

Write-Host "Finished deploying Azure Function" -ForegroundColor Green
