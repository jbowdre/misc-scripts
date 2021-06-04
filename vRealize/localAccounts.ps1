<# Action Secrets:
    templatePassWinWorkgroup            # built-in admin password on source template
    templatePassLin                     # built-in admin password on source template
    vCenterPassword                     # password for vCenter account passed from the template
    thycoticPassword                    # password for Thycotic account passed as an action input
    liquidApiKey                        # LiquidFiles API key for account used to send notifications
#>
<# Action Inputs:
    liquidUrl                           # [https://liquid.lab.bowdre.net]
    thycUrl                             # [https://thycc.lab.bowdre.net/SecretServer]
    thycUser                            # Thycotic user account [lab\vra]
    adminUser                           # name of admin account to be created [labAdmin]
    thycFolderId                        # ID of folder in Thycotic where password should be created [8]
    thycTemplateId                      # ID of the Secret Template to be used, recommend the standard "Password" one [2]
#>
<# Inputs from deployment
    customProperties.vCenterUser        # user to connect to vCenter [lab\vra]
    customProperties.vCenter            # vCenter instance to connect to [vcsa.lab.bowdre.net]
    customProperties.templateUser       # default admin account on the template [Administrator] / [root]
    resourceNames[0]                    # VM name [BOW-DVRT-XXX003]
    customProperties.username           # desired name of "user" account to be created [john]
    customProperties.poc                # Point of Contact from the request [John Bowdre (john@bowdre.net)]
#>

function handler($context, $inputs) {
    # Input variables
    $vcUser = $inputs.customProperties.vCenterUser
    $vcPass = $context.getSecret($inputs."vCenterPassword")
    $vCenter = $inputs.customProperties.vCenter
    $vmName = $inputs.resourceNames[0]

    $liquidUrl = $inputs.liquidUrl
    $liquidApiKey = $context.getSecret($inputs."liquidApiKey")
    
    $thycUrl = $inputs.thycUrl
    $thycUser = $inputs.thycUser
    $thycPass = $context.getSecret($inputs."thycoticPassword")
    $thycFolderId = $inputs.thycFolderId
    $thycTemplateId = $inputs.thycTemplateId
    
    $adminUser = $inputs.adminUser
    $username = $inputs.customProperties.username
    $templateUser = $inputs.customProperties.templateUser

    ##
    # Create vmtools connection to the VM
    Connect-ViServer $vCenter -User $vcUser -Password $vcPass -Force
    $vm = Get-VM -Name $vmName
    Write-Host "Waiting for VM Tools to start..."
    if (-not (Wait-Tools -VM $vm -TimeoutSeconds 180)) {
        Write-Error "Unable to establish connection with VM tools" -ErrorAction Stop
    }
    # Detect OS family (win/lin)
    $osType = ($vm | Get-View).Guest.GuestFamily.ToString()
    $toolsStatus = ($vm | Get-View).Guest.ToolsStatus.ToString()
    Write-Host "$vmName is a $osType and its tools status is $toolsStatus."
    # Update tools on Windows if out of date
    if ($osType.Equals("windowsGuest") -And $toolsStatus.Equals("toolsOld")) {
        Write-Host "Updating VM Tools..."
        Update-Tools $vm
        Write-Host "Waiting for VM Tools to start..."
        if (-not (Wait-Tools -VM $vm -TimeoutSeconds 180)) {
            Write-Error "Unable to establish connection with VM tools" -ErrorAction Stop
        }
    }

    ##
    # Generate random passwords
    $length = 20
    [string]$adminPass = $null
    [string]$userPass = $null
    # ASCII character codes for:
    #        [0 - 9]     [A - Z]    [a - z]    [!]  [#$%&]      [()*+]   [-]
    $chars = (48..57) + (65..90) + (97..122) + 33 + (35..38) + (40..43) + 45
    $chars | Get-Random -Count $length | ForEach-Object { $adminPass += [char]$_ }
    $chars | Get-Random -Count $length | ForEach-Object { $userPass += [char]$_ }
    
    ##
    # Create accounts in guest
    if ($osType.Equals("windowsGuest")){
        $templatePass = $context.getSecret($inputs.templatePassWinWorkgroup)
        $adminAccountScript = "`$password = ConvertTo-SecureString `"$adminPass`" -AsPlainText -Force
            New-LocalUser -Name $adminUser -Password `$password -Description 'Administrator account created by vRA'
            Add-LocalGroupMember -Group Administrators -Member $adminUser"
        Write-Host "Creating local admin account $adminUser..."
        $runScript = Invoke-VMScript -VM $vm -ScriptText $adminAccountScript -GuestUser "$templateUser" -GuestPassword "$templatePass"
        Write-Host "Result:`n" $runScript.ScriptOutput "`n"            
        $userAccountScript = "`$password = ConvertTo-SecureString `"$userPass`" -AsPlainText -Force
            New-LocalUser -Name $username -Password `$password -Description 'User account created by vRA'
            Add-LocalGroupMember -Group Administrators -Member $username"
        Write-Host "Creating local user account $username..."
        $runScript = Invoke-VMScript -VM $vm -ScriptText $userAccountScript -GuestUser "$templateUser" -GuestPassword "$templatePass"
        Write-Host "Result:`n" $runScript.ScriptOutput "`n"
    } elseif ($osType.Equals("linuxGuest")) {
        $templatePass = $context.getSecret($inputs.templatePassLin)
        $adminAccountScript = "if [ `$(getent group wheel) ]; then adminGroup='-G wheel'; elif [ `$(getent group sudo) ]; then adminGroup='-G sudo'; fi; useradd -s /bin/bash `$adminGroup -m $adminUser; echo `"$adminUser`:$adminPass`" | chpasswd; chage -M -1 $adminUser"
        Write-Host "Creating local admin account $adminUser..."
        $runScript = Invoke-VMScript -VM $vm -ScriptText $adminAccountScript -GuestUser "$templateUser" -GuestPassword "$templatePass"
        Write-Host "Result:`n" $runScript.ScriptOutput "`n"            
        $userAccountScript = "if [ `$(getent group wheel) ]; then adminGroup='-G wheel'; elif [ `$(getent group sudo) ]; then adminGroup='-G sudo'; fi; useradd -s /bin/bash `$adminGroup -m $username; echo `"$username`:$userPass`" | chpasswd; passwd -e $username"
        Write-Host "Creating local user account $username..."
        $runScript = Invoke-VMScript -VM $vm -ScriptText $userAccountScript -GuestUser "$templateUser" -GuestPassword "$templatePass"
        Write-Host "Result:`n" $runScript.ScriptOutput "`n"            
    }

    ##
    # Deliver user account creds via LiquidFiles
    $vmIpAddress = ($vm | Get-View).Guest.IpAddress
    $messageToFirstName = $inputs.customProperties.poc.Split(' ')[0] 
    $messageToEmail = $inputs.customProperties.poc.Split('(')[1].Split(')')[0] 
    $messageSubject = "Requested server credentials"
    $messageText = "Hi $messageToFirstName,

Here are the initial credentials for your account on $vmName at $vmIpAddress.
You should change the password once you've logged in.

`tUsername: $username
`tPassword: $userPass

Reach out to the server team if you run into issues."

    $authToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $liquidApiKey,'')))

    $messagePayload = @{
        message = @{
            recipients = @($messageToEmail)
            send_email = $true
            private_message = $true
            subject = $messageSubject
            message = $messageText
            bcc_myself = $false
            expires_after = 3
        }
    }
    
    $Parameters = @{
        Method = "Post"
        Uri = "$liquidUrl/message"
        Body = ($messagePayload | ConvertTo-Json)
        ContentType = "application/json"
        Headers = @{
            Authorization = "Basic $authToken"
        }
        # Remove for production
        SkipCertificateCheck = $true
    }

    Write-Host "Sending initial creds to $messageToEmail via Liquid Files..."
    $sendMessage = Invoke-RestMethod @Parameters -ErrorAction Continue
    if ($sendMessage.message.id.length -gt 0) {
        Write-Host "Secure message sent, ID: $($sendMessage.message.id)"
    } else {
        Write-Host "Message not sent successfully. Output:`n($sendMessage | ConvertTo-Json)"
    }


    ##
    # Store admin account creds in Thycotic
    $thycApi = "$thycUrl/api/v1"

    # Authenticate to Thycotic
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
        "Authorization" = "Bearer $token"
    }
    
    $Parameters = @{
        Uri = "$thycApi/secrets/stub?filter.SecretTemplateId=$thycTemplateId"
        Method = "Get"
        Headers = $headers
        # Remove for production
        SkipCertificateCheck = $true
    }
    
    $secret = Invoke-RestMethod @Parameters -ErrorAction Continue

    $secret.name = "$vmName admin"
    $secret.secretTemplateId = $thycTemplateId
    $secret.autoChangeEnabled = $false
    $secret.siteId = 1
    $secret.folderId = $thycFolderId

    switch ($secret.items) {
        ({$_.fieldName -eq "Resource"}) {
            $_.itemValue = "$vmName / $vmIpAddress"
        }
        ({$_.fieldName -eq "Username"}) {
            $_.itemValue = "$adminUser"
        }
        ({$_.fieldName -eq "Password"}) {
            $_.itemValue = "$adminPass"
        }
        ({$_.fieldName -eq "Notes"}) {
            $_.itemValue = "Auto-generated password set by vRA"
        }
    }

    $secretArgs = $secret | ConvertTo-Json

    $Parameters = @{
        Uri = "$thycApi/secrets/"
        Method = "Post"
        Body = $secretArgs
        ContentType = "application/json"
        Headers = $headers
        # Remove for production
        SkipCertificateCheck = $true
    } 

    Write-Host "Storing credential for $adminUser in Thycotic..."
    $createSecret = Invoke-RestMethod @Parameters -ErrorAction Continue
    
    if ($createSecret.id -gt 0) {
        Write-Host "Secret created, ID: $($createSecret.id)"
    } else {
        Write-Host "Secret not created successfully. Output:`n$($createSecret | ConvertTo-Json)"
    }


    Disconnect-ViServer -Server * -Force -Confirm:$false

}


