<# vRA 8.x ABX Action to soft-delete Thycotic secrets when a deployment is deleted.

    ## Action Secrets:
        thycoticPassword                    # password for Thycotic account passed as an action input
    
    ## Action Inputs:
        thycUrl                             # [https://thycc.lab.bowdre.net/SecretServer]
        thycUser                            # Thycotic user account [lab\vra]
    
    ## Inputs from deployment
        customProperties.thycSecretId       # ID of secret to be archived
#>

function handler($context, $inputs) {
    ## Input variables
    $thycUrl = $inputs.thycUrl
    $thycUser = $inputs.thycUser
    $thycPass = $context.getSecret($inputs."thycoticPassword")
    $thycSecretId = $inputs.customProperties.thycSecretId
    $thycApi = "$thycUrl/api/v1"

    ## Authenticate to Thycotic
    $creds = @{
        username = $thycUser
        password = $thycPass
        grant_type = "password"
    }

    $Parameters = @{
        Uri = "$thycUrl/oauth2/token"
        Method = "Post"
        Body = $creds
        # Remove for production
        SkipCertificateCheck = $true
    }

    $response = Invoke-RestMethod @Parameters -ErrorAction Continue
    $token = $response.access_token
    $headers = @{
        Authorization = "Bearer $token"
    }
   
    ## Delete specified secret from Thycotic
    $Parameters = @{
        Uri = "$thycApi/secrets/$thycSecretId/"
        Method = "Delete"
        Headers = $headers
        ContentType = "application/json"
        # Remove for production
        SkipCertificateCheck = $true
    }
    
    $deleteSecret = Invoke-RestMethod @Parameters -ErrorAction Continue
    
    if ($deleteSecret.id -gt 0) {
        Write-Host "Secret successfully deleted, ID: $($deleteSecret.id)"
    } else {
        Write-Host "Secret may not have been deleted. Output:`n$($deleteSecret | ConvertTo-Json)"
    }
}
