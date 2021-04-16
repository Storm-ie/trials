# Parameters
Param(

    [Parameter(Mandatory)]
    [String] $SubscriptionId,

    [Parameter(Mandatory)]
    [String] $TenantId,

    [Parameter(Mandatory)]
    [String] $SiteUrl,
    
    [Parameter(Mandatory)]
    [String] $ListRelativeUrl,

    [Parameter(Mandatory)]
    [String] $SPOUsername,

    [Parameter(Mandatory)]
    [String] $SPOPassword,
    
    [Parameter(Mandatory)]
    [ValidateSet("dev", "qa", "uat", "prod")]
    [string] $Environment,
    
    [Parameter(Mandatory)]
    [string] $InstanceNumber,

    [Parameter(Mandatory)]
    [string] $ApproverEmail,

    [Parameter()]
    [string] $ResourceGroupName = "rg-governanceapp-prod-001",

    [Parameter()]
    [string] $AppName = "Governance App",

    [Parameter()]
    [bool] $SkipAzLogicAppsConnectionsDeployment,

    [Parameter()]
    [bool] $SkipAzLogicAppsConnectionsAuthorisation

)

# import Utils
$psRoot = $PSScriptRoot 
. "${psRoot}/../Utils/AuthoriseLogicAppsConnections.ps1"

# Azure variables
$psRoot = $PSScriptRoot 
$AzureTemplatesPath = $psRoot
$spoConnectionName = "con-$AppName-sp-$Environment-$InstanceNumber"
$outlookConnectionName = "con-$AppName-outlook-$Environment-$InstanceNumber"
$storageAccountName = "st$($AppName.ToLower())$Environment$InstanceNumber"
$queuesConnectionName = "con-$AppName-queues-$Environment-$InstanceNumber"
$logicAppEmailApprovalName = "lapp-$AppName-approval-$Environment-$InstanceNumber"
$logicAppEmailNotificationsName = "lapp-$AppName-notifications-$Environment-$InstanceNumber"
$logicAppQueueRequestsName = "lapp-$AppName-queue-requests-$Environment-$InstanceNumber"

######################
## Start deployment ##
######################

Write-Host "Deploying Logic Apps..." -ForegroundColor Yellow

if (!$SkipAzLogicAppsConnectionsDeployment) {
    
    Write-Host "Deploying Logic Apps api connections..." -ForegroundColor Yellow
    
    # Deploy Logic Apps connections
    $storageAccountKey = az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query [0].value -o tsv
    
    # Connections
    az deployment group create `
        --resource-group $ResourceGroupName `
        --subscription $SubscriptionId `
        --template-file "$AzureTemplatesPath\LogicApps\connections.json" `
        --parameters "SPOConnectionName=$spoConnectionName" "OutlookConnectionName=$outlookConnectionName" "QueuesConnectionName=$queuesConnectionName" "StorageAccountName=$storageAccountName" "StorageAccountKey=$storageAccountKey"
    
    Write-Host "Finished deploying Logic Apps api connections" -ForegroundColor Green
    
    if (!$SkipAzLogicAppsConnectionsAuthorisation) {
        # authorise connections
        Write-Host "### LOGIC APP CONNECTIONS AUTHORISATION ###`nStarting authorisation for Logic App Connections`nPlease authenticate with the Service Account" -ForegroundColor Yellow
        
        # Initialise connections - Azure Az
        Write-Host "Azure sign-in..." -ForegroundColor Yellow
        # Logout of the current account
        Disconnect-AzAccount
        $azConnect = Connect-AzAccount -Subscription $SubscriptionId -Tenant $TenantId

        $spoconnection = Get-AzResource -ResourceType "Microsoft.Web/connections" -ResourceGroupName $ResourceGroupName -Name $spoConnectionName
        $outlookConnection = Get-AzResource -ResourceType "Microsoft.Web/connections" -ResourceGroupName $ResourceGroupName -Name $outlookConnectionName
        
        Write-Host "SharePoint Connection"
        AuthoriseLogicAppConnection($spoConnection.ResourceId)
        Write-Host "Office 365 Outlook Connection"
        AuthoriseLogicAppConnection($outlookConnection.ResourceId)
        
        Write-Host "### LOGIC APP CONNECTIONS AUTHORISATION COMPLETE ###" -ForegroundColor Green
    }
   
}


# Create credentials
$credentials = (New-Object System.Management.Automation.PSCredential ($SPOUsername, (ConvertTo-SecureString $SPOPassword -AsPlainText -Force)))

#Getting SharePoint List IDs
$SiteUrl
Connect-PnPOnline -Url $SiteUrl -Credentials $credentials
$ListRelativeUrl
$list = Get-PnPList $ListRelativeUrl
$listId = $list.Id
$listView = Get-PnPView -List $list -Identity "All Items"
$listViewId = $listView.Id
Write-Host "SharePoint list ID: $listId" -ForegroundColor Yellow
Write-Host "SharePoint list view ID: $listViewId" -ForegroundColor Yellow
Disconnect-PnPOnline


# Deploy Logic Apps templates

az deployment group create `
    --resource-group $ResourceGroupName `
    --subscription $SubscriptionId `
    --template-file "$AzureTemplatesPath\LogicApps\email-approval.json" `
    --parameters "Name=$logicAppEmailApprovalName" "SiteUrl=$SiteUrl" "ListId=$listId" "ListViewId=$listViewId" "ApproverEmail=$ApproverEmail" "SPOConnectionName=$spoConnectionName" "OutlookConnectionName=$outlookConnectionName"
    
az deployment group create `
    --resource-group $ResourceGroupName `
    --subscription $SubscriptionId `
    --template-file "$AzureTemplatesPath\LogicApps\email-notifications.json" `
    --parameters "Name=$logicAppEmailNotificationsName" "SiteUrl=$SiteUrl" "ListId=$listId" "ListViewId=$listViewId" "SPOConnectionName=$spoConnectionName" "OutlookConnectionName=$outlookConnectionName"
    
az deployment group create `
    --resource-group $ResourceGroupName `
    --subscription $SubscriptionId `
    --template-file "$AzureTemplatesPath\LogicApps\queue-requests.json" `
    --parameters "Name=$logicAppQueueRequestsName" "SiteUrl=$SiteUrl" "ListId=$listId" "ListViewId=$listViewId" "SPOConnectionName=$spoConnectionName" "QueuesConnectionName=$queuesConnectionName"
    
Write-Host "Finished deploying Logic Apps" -ForegroundColor Green
