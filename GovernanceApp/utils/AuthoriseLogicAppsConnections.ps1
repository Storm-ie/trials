# Shows OAuth sign-in window
function ShowOAuthWindow {
    param (
        $URL
    )
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object -TypeName System.Windows.Forms.Form -Property @{Width = 600; Height = 800 }
    $web = New-Object -TypeName System.Windows.Forms.WebBrowser -Property @{Width = 580; Height = 780; Url = ($URL -f ($Scope -join "%20")) }
    $docComp = {
        $global:uri = $web.Url.AbsoluteUri
        if ($global:uri -match "error=[^&]*|code=[^&]*") { $form.Close() }
    }
    $web.Add_DocumentCompleted($docComp)
    $form.Controls.Add($web)
    $form.Add_Shown( { $form.Activate() })
    $form.ShowDialog() | Out-Null
}

function AuthoriseLogicAppConnection($resourceId) {
    $parameters = @{
        "parameters" = , @{
            "parameterName" = "token";
            "redirectUrl"   = "https://ema1.exp.azure.com/ema/default/authredirect"
        }
    }

    # Get the links needed for consent
    $consentResponse = Invoke-AzResourceAction -Action "listConsentLinks" -ResourceId $resourceId -Parameters $parameters -Force

    $url = $consentResponse.Value.Link 

    # Show sign-in prompt window and grab the code after auth
    ShowOAuthWindow -URL $url

    $regex = '(code=)(.*)$'
    $code = ($uri | Select-string -pattern $regex).Matches[0].Groups[2].Value
    # Write-output "Received an accessCode: $code"

    if (-Not [string]::IsNullOrEmpty($code)) {
        $parameters = @{ }
        $parameters.Add("code", $code)
        # NOTE: errors ignored as this appears to error due to a null response
    
        #confirm the consent code
        Invoke-AzResourceAction -Action "confirmConsentCode" -ResourceId $resourceId -Parameters $parameters -Force -ErrorAction Ignore
    }   

    # Retrieve the connection
    $connection = Get-AzResource -ResourceId $resourceId
    Write-Host "Connection " $connection.Name " now " $connection.Properties.Statuses[0]
}