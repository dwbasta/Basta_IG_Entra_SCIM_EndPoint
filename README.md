# Test SCIM EndPoint for Entra testing

Scim Endpoint is meant to be used with the Entra On-premises SCIM app in the Microsoft Gallery.
> [!Warning]
> I am not developer! This is not meant to be an example of how to implement SCIM. It is mainly use for testing feature of Entra

## Starting the Scim Endpoint
1.) Edit the Scim_Test_Endpoints.ps1
  - the Hostname which will be your TenantID in entra with the Http://Hostname.domain.com/scim setup
  - Edit the BearerToken which will be your SecretToken in entra
  - Set the useHttps to false
  
2.) Run the powershell script with administrative rights

>[!NOTE]
> If successful will return "SCIM test server running. Expected Hostname: (Yourhostname)/SCIM

3.) Install the cloud provisioning agent based on the following documentation on a separete server that can communicate to the SCIM endpoint and configure the [Entra On-premises SCIM app](https://learn.microsoft.com/en-us/entra/identity/app-provisioning/on-premises-scim-provisioning)

4.) Test the configuration. The SCIM endpoint will output the file the request that are going to be sent over from the Entra Provisioning agent.

## Testing the SCIM Endpoint out side of Entra

### Test Get /Users
```
Invoke-RestMethod -Uri "http://hostname/SCIM/Users" `
  -Headers @{ "Authorization" = "Bearer yourAPIKey" } `
  -Method Get
```
### Test GET /Users with Filter
```
Invoke-RestMethod -Uri "http://hostname/SCIM/Users?filter=userName+eq+`"jdoe`"" `
  -Headers @{ "Authorization" = "Bearer yourAPIKey" } `
  -Method Get
```

### Test Get /User with Employee ID
```
Invoke-RestMethod -Uri "https://hostname/SCIM/Users/2"`
 -Headers @{ "Authorization" = "Bearer yourAPIKey" } `
 -Method Get
```



## HTTPS install
1.) Install the public key on the server you are going to run the scim connector
```
$password = ConvertTo-SecureString -String "YourPfxPasswordHere" -AsPlainText -Force

Import-PfxCertificate -FilePath "C:\PathToCertificate.pfx" `
                      -CertStoreLocation "Cert:\LocalMachine\My" `
                      -Password $password `
                      -Exportable
```

2.) Get the thumbprint of the certificate
```
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*applicationtarg*" }
```

3.) Bind the Certificate to that port
```
netsh http add sslcert ipport=0.0.0.0:443 certhash=<thumbprint> appid="{<your-guid>}"
```
4.) Change the script to useHttps to true
5.) Run the Sript with administrative rights


## Additional Attributes
For the most part the SCIM endpoints loops through and does not need to add the code to handle new attributes sent over from the scim system.
1.) Provision users on demand in the entra enterprise application
![UserProvisioned](https://github.com/dwbasta/Basta_IG_Entra_SCIM_EndPoint/blob/powershell-addtions/Images/PVDefaultAttributes.png)
2.) Check that default users are provisioned on the console of your SCIM endpoint (the Powershell terminal) 
![ConsoleUserCreate](https://github.com/dwbasta/Basta_IG_Entra_SCIM_EndPoint/blob/powershell-addtions/Images/TerminalOutput.png)
3.) Modify an attribute that you didnt already have on the entra user object and run ondemand provisioning again.
![AttributeAdd](https://github.com/dwbasta/Basta_IG_Entra_SCIM_EndPoint/blob/powershell-addtions/Images/ProvisionAttributeUpdate.png)
4.) Check the console to make sure one that we can update attributes and secondly dynamically add additional attributes even if not configure in the application.
![ReviewConsole](https://github.com/dwbasta/Basta_IG_Entra_SCIM_EndPoint/blob/powershell-addtions/Images/ConsoleConfirmation.png)



<meta name="google-site-verification" content="bwfq2dStYqtf7epTEanIUsvxPpJ30ZEv2Dom3VQlL5M" />
