function Set-CIPPAuthenticationPolicy {
    [CmdletBinding()]
    param(
        $TenantFilter,
        [Parameter(Mandatory = $true)]$AuthenticationMethodId,
        [Parameter(Mandatory = $true)][bool]$State, # true = enabled or false = disabled
        [bool]$MicrosoftAuthenticatorSoftwareOathEnabled, 
        $TAPMinimumLifetime = '60', #Minutes
        $TAPMaximumLifetime = '480', #minutes
        $TAPDefaultLifeTime = '60', #minutes
        $TAPDefaultLength = '8', #TAP password generated length in chars
        $APIName = 'Set Authentication Policy',
        $ExecutingUser = 'None'
    )

    # Convert bool input to usable string
    $State = if ($State) { 'enabled' } else { 'disabled' }

    switch ($AuthenticationMethodId) {

        # FIDO2
        'FIDO2' {
            # Set FIDO2 state
            try {

                $Fido2Body = [PSCustomObject]@{
                    '@odata.type'                    = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
                    id                               = 'Fido2'
                    includeTargets                   = @(@{
                            id                     = 'all_users'
                            isRegistrationRequired = $false
                            targetType             = 'group'
                            displayName            = 'All users'
                        })
                    
                    excludeTargets                   = @()
                    isAttestationEnforced            = $true
                    isSelfServiceRegistrationAllowed = $true
                    keyRestrictions                  = @{
                        aaGuids         = @()
                        enforcementType = 'block'
                        isEnforced      = $false
                    }
                    state                            = $State
                }
                $body = ConvertTo-Json -Compress -Depth 10 -InputObject $Fido2Body
                New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Set $AuthenticationMethodId state to $State" -sev Info
            }
            catch {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            }
        }

        # Microsoft Authenticator
        'MicrosoftAuthenticator' {  

            if ($State -eq 'enabled') {
                try {
                    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $TenantFilter
                    $CurrentInfo.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
                    $CurrentInfo.featureSettings.displayAppInformationRequiredState.state = $State
                    $CurrentInfo.featureSettings.displayLocationInformationRequiredState.state = $State
                    # Enable MS authenticator OTP if called for
                    if ($null -ne $MicrosoftAuthenticatorSoftwareOathEnabled ) { $CurrentInfo.isSoftwareOathEnabled = $MicrosoftAuthenticatorSoftwareOathEnabled }
                    $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
                    (New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type patch -Body $body -ContentType 'application/json')
                
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Enabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            elseif ($State -eq 'disabled') {
                try {
                    # Get current state and disable
                    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $TenantFilter
                    $CurrentInfo.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
                    $CurrentInfo.state = $State
                    $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
                    (New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type patch -Body $body -ContentType 'application/json')
                
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Disabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            else {
                # Catch invalid input
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            }

        }
        # SMS
        'SMS' {  

            if ($State -eq 'enabled') {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
            }
            else {
                try {
                    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/SMS' -tenantid $TenantFilter
                    $CurrentInfo.state = $State
                    $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
                    (New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/SMS' -Type patch -Body $body -ContentType 'application/json')
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Diabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
        }
        # Temporary Access Pass
        'TemporaryAccessPass' {  

            if ($State -eq 'enabled') {
                # Get the TAP config from the standards table. If it's not there, use the default value of true
                $ConfigTable = Get-CippTable -tablename 'standards'
                $TAPConfig = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$TenantFilter'").JSON | ConvertFrom-Json).Standards.TAP.config
                if (!$TAPConfig) {
                    $TAPConfig = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).Standards.TAP.config
                }
                if (!$TAPConfig) { $TAPConfig = 'true' }

                try {                
                    # Build the body of the request
                    $CurrentInfo = [PSCustomObject]@{
                        '@odata.type'            = '#microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration'
                        id                       = 'TemporaryAccessPass'
                        includeTargets           = @(
                            @{
                                id                     = 'all_users'
                                isRegistrationRequired = $false
                                targetType             = 'group'
                                displayName            = 'All users'
                            }
                        )
                        defaultLength            = $TAPDefaultLength
                        defaultLifetimeInMinutes = $TAPDefaultLifeTime
                        isUsableOnce             = $TAPConfig
                        maximumLifetimeInMinutes = $TAPMaximumLifetime
                        minimumLifetimeInMinutes = $TAPMinimumLifetime
                        state                    = $State
                    }
                

                    # Convert to JSON and send the request
                    $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
                    (New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/TemporaryAccessPass' -Type patch -asApp $true -Body $body -ContentType 'application/json')
                
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Enabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            elseif ($State -eq 'disabled') {
                try {
                    # Get current state and disable
                    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/TemporaryAccessPass' -tenantid $TenantFilter
                    $CurrentInfo.state = $State
                    $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
                    (New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/TemporaryAccessPass' -Type patch -Body $body -ContentType 'application/json')

                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Diabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            else {
                # Catch invalid input
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            } 
        } 
    
        # Hardware OATH tokens (Preview)
        'HardwareOATH' {  

            if ($State -eq 'enabled') {
                try {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Enabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            elseif ($State -eq 'disabled') {
                try {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Diabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            else {
                # Catch invalid input
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            }
        }
        # Third-party software OATH tokens
        'softwareOath' {  
            # Get current state and set state
            try {
                $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -tenantid $TenantFilter
                $CurrentInfo.state = $State
                $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
                (New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -Type patch -Body $body -ContentType 'application/json')
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Set $AuthenticationMethodId state to $State" -sev Info
            }
            catch {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            }
        }
        # Voice call
        'Voice' {  
            # Disallow enabling voice
            if ($State -eq 'enabled') {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
            }
            else {
                # Get current state and disable
                try {
                    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/Voice' -tenantid $TenantFilter
                    $CurrentInfo.state = $State
                    $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
                    (New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/Voice' -Type patch -Body $body -ContentType 'application/json')
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Diabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
        }
        # Email OTP
        'Email' {  

            if ($State -eq 'enabled') {
                try {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Enabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            elseif ($State -eq 'disabled') {
                try {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Diabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
        }
        # Certificate-based authentication
        'x509Certificate' {  
            
            if ($State -eq 'enabled') {
                try {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Enabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            elseif ($State -eq 'disabled') {
                try {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Diabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            else {
                # Catch invalid input
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            }

        }
        Default {
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message 'Somehow you hit the default case. You did something wrong' -sev Error
            return 'Somehow you hit the default case. You did something wrong'
        }
    }











}