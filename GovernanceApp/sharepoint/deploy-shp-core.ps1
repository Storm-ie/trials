
param(
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string] $TenantAdminSiteUrl,  
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string] $TargetSiteCollectionTitle,
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string] $TargetSiteCollectionDescription,
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string] $TargetSiteCollectionOwner,
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string] $TargetSiteCollectionServiceAccount,
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string] $TargetSiteCollectionUrl,
  [Parameter(Mandatory)]
  [String] $SPOUsername,
  [Parameter(Mandatory)]
  [String] $SPOPassword,
  # Deployment Settings
  [bool] $DeployTenantTemplates = $true,
  [bool] $DeployTenantTemplatesOnly = $false,
  [bool] $EnableSiteCollectionAppCatalog = $false,
  [bool] $EnableSiteCollectionCustomScripts = $false
)

$global:spoCredentials = (New-Object System.Management.Automation.PSCredential ($SPOUsername, (ConvertTo-SecureString $SPOPassword -AsPlainText -Force)))

$stepsCounter = -1;
$templatesSequence = "Tenant";
$deploymentFolder = ((Get-Item $PSScriptRoot).Parent.FullName) + "\sharepoint\provisioning\" + $templatesSequence + "\sequences";
$governanceAppPackagePath = "/sharepoint/provisioning/assets/packages/connect-workspaces-app.sppkg"

# Establishing connection to Admin Site Collection as app
Write-Host [(++$stepsCounter)] -NoNewline -ForegroundColor Yellow
Write-Host " Connecting to " -NoNewline;
Write-Host  $TenantAdminSiteUrl -NoNewline -ForegroundColor Yellow;
Write-Host " as user..." -NoNewline;
Connect-PnPOnline -Url $TenantAdminSiteUrl -Credentials $global:spoCredentials
Write-Host "[OK]" -ForegroundColor Green


# Deploying Tenant templates
if ($DeployTenantTemplates -eq $true) {  

  Write-Host [(++$stepsCounter)] -NoNewline -ForegroundColor Yellow;
  Write-Host " Applying " -NoNewline;
  Write-Host  "Provisioning.$templatesSequence.Teams.Sequence.xml" -NoNewline -ForegroundColor Yellow;
  Write-Host "..." -NoNewline;

  try {

    $appCatalogSite = Get-PnPTenantAppCatalogUrl | Get-PnPTenantSite;

    $tenantTemplatesProps = @{
      "Title"       = $appCatalogSite.Title
      "Description" = $appCatalogSite.Description
      "Url"         = $appCatalogSite.Url
      "Owner"       = $TargetSiteCollectionOwner
    };

    Apply-PnPTenantTemplate -Path "$deploymentFolder\Provisioning.Tenant.Teams.Sequence.xml" -Parameters $tenantTemplatesProps > $null;    
    
    Write-Host "[OK]" -ForegroundColor Green;      
  }
  catch {
    Write-Host "[E]" -ForegroundColor Red;
  }
}

# Checking if the target Site Collection URL exists.
$siteCollection = Get-PnPTenantSite -Url $TargetSiteCollectionUrl -ErrorAction 0;

# Creating Site Collection if does not exists.
if (-not $siteCollection) {
  Write-Host [(++$stepsCounter)] -NoNewline -foregroundcolor Yellow
  Write-Host " Creating Site Collection " -NoNewline;
  Write-Host  $TargetSiteCollectionUrl -NoNewline -foregroundcolor Yellow;
  Write-Host "..." -NoNewline;

  try {
    
    New-PnPSite -Type CommunicationSite -Title $TargetSiteCollectionTitle -Url $TargetSiteCollectionUrl -Owner $TargetSiteCollectionOwner -Description $TargetSiteCollectionDescription -Wait -ErrorVariable ProcessError -ErrorAction 0 >$null;

    if ($ProcessError.Count -eq 0) {

      $siteCollection = Get-PnPTenantSite -Url $TargetSiteCollectionUrl -ErrorAction 0;

      while (-not $siteCollection) {
        $siteCollection = Get-PnPTenantSite -Url $TargetSiteCollectionUrl -ErrorAction 0 -ErrorVariable ProcessError;
        if ($ProcessError.Count -ne 0) { 
          $siteCollection = $null;
          Start-Sleep 3;
          Write-Host "." -NoNewline;
        }
      }

      Write-Host "[OK]" -ForegroundColor Green;

      if ($siteCollection) {
        # Enabling Custom Scripts
        if ($EnableSiteCollectionCustomScripts) {
          $retries = 3;
          $success = $false;
          Write-Host [(++$stepsCounter)] -NoNewline -foregroundcolor Yellow;
          Write-Host " Enabling Custom Scripts (DenyAndAddCustomizePages)..." -NoNewline;
          while (($retries -gt 0) -and (-not $success)) {
            --$retries;
            Set-PnPSite -Identity $TargetSiteCollectionUrl -DenyAndAddCustomizePages $false -ErrorAction 0 -ErrorVariable ProcessError;
            if ($ProcessError.Count -ne 0) { Start-Sleep 1; }
            else { $success = $true };
          }
          if ($success) { Write-Host "[OK]" -ForegroundColor Green; }
          else { Write-Host "[E]" -ForegroundColor Red; }
        }
      
        # Enabling App Catalog
        if ($EnableSiteCollectionAppCatalog) {
          $retries = 3;
          $success = $false;
          Write-Host [(++$stepsCounter)] -NoNewline -foregroundcolor Yellow
          Write-Host " Enabling Site Collection App Catalog..." -NoNewline;
          while (($retries -gt 0) -and (-not $success)) {
            --$retries;
            Add-PnPSiteCollectionAppCatalog -Site $TargetSiteCollectionUrl -ErrorAction 0 -ErrorVariable ProcessError;
            if ($ProcessError.Count -ne 0) { Start-Sleep 1; }
            else { $success = $true };
          }
          if ($success) { Write-Host "[OK]" -ForegroundColor Green; }
          else { Write-Host "[E]" -ForegroundColor Red; }
        }        
      }
    }
    else {
      Write-Host  "[E]" -ForegroundColor Red;
      Write-Host "[ ! ] " -ForegroundColor Red -NoNewline;
      Write-Host $ProcessError[0].ErrorDetails.Message;
      throw $("Could not complete the provisioning..." -f $ProcessError[0].ErrorDetails.Message; )
    }
  }
  catch {    
    Write-Host "[E]" -ForegroundColor Red;
    throw $_.Exception.Message
  }  
}

# Applying templates if Site Collection exists/is created.
if ($siteCollection -and $DeployTenantTemplatesOnly -eq $false) {

  $templatesSequence = "Main";
  $deploymentFolder = ((Get-Item $PSScriptRoot).Parent.FullName) + "\sharepoint\provisioning\" + $templatesSequence + "\sequences";

  Write-Host [(++$stepsCounter)] -NoNewline -foregroundcolor Yellow
  Write-Host " Applying " -NoNewline;
  Write-Host  "Provisioning.$templatesSequence.Teams.Sequence.xml" -NoNewline -foregroundcolor Yellow;
  Write-Host "..." -NoNewline;
  try {

    $serviceAccountLoginName = "i:0#.f|membership|$TargetSiteCollectionServiceAccount";
    $AuthenticationRealm = Get-PnPAuthenticationRealm

    $mainTemplatesSequenceProps = @{
      "Title"                   = $TargetSiteCollectionTitle
      "Description"             = $TargetSiteCollectionDescription
      "Url"                     = $TargetSiteCollectionUrl
      "Owner"                   = $TargetSiteCollectionOwner
      "ServiceAccountLoginName" = $serviceAccountLoginName
      "AuthenticationRealm"     = $AuthenticationRealm
    };

    Apply-PnPTenantTemplate -Path "$deploymentFolder\Provisioning.$templatesSequence.Teams.Sequence.xml" > $null -Parameters $mainTemplatesSequenceProps;
    
    Write-Host "[OK]" -ForegroundColor Green;
    
  }
  catch {
    Write-Host "[E]: There has been an error $($_.Exception.message)" -ForegroundColor Red
    throw "There has been an error $($_.Exception.message)"
  }
}

# Disconnecting
Write-Host [(++$stepsCounter)] -NoNewline -foregroundcolor Yellow
Write-Host " Disconnecting... " -NoNewline;
Disconnect-PnPOnline
Write-Host "[OK]" -ForegroundColor Green;