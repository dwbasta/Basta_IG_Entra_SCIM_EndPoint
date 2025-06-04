# Basta_IG_Entra
Any solution around the deployment/testing out Microsoft Entra identity governance solution.
Scim Endpoint is meant to be used with the [Entra On-premises SCIM app](https://learn.microsoft.com/en-us/entra/identity/app-provisioning/on-premises-scim-provisioning)

## Starting the Scim Endpoint
1.) Edit the Scim_Test_Endpoints.ps1
  - the Hostname which will be your TenantID in entra with the Http://Hostname.domain.com/scim setup
  - Edit the BearerToken which will be your SecretToken in entra
  - Set the useHttps to false
2.) Run the powershell script with administrative rights

>[!NOTE]
> If successful will return "SCIM test server running. Expected Hostname: (Yourhostname)/SCIM
