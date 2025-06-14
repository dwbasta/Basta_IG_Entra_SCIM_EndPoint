# =====================================================
# Configuration: Update these values for your environment
# =====================================================
$Hostname    = "TestServer.Example.com"
$BearerToken = "ThisIsYourAPIKeySoChangeMe"
$useHttps    = $false    # Set $true for HTTPS, or $false for HTTP

# Determine protocol and port based on $useHttps value.
if ($useHttps) {
    $protocol = "https"
    $port     = 443
} else {
    $protocol = "http"
    $port     = 80
}

# =====================================================
# Set up the HTTP Listener using wildcard prefixes.
#
# For HTTPS, the prefix will be e.g. "https://+:443/scim/"
# For HTTP, the prefix will be e.g. "http://+:80/scim/"
#
# Note: When using HTTPS ($useHttps = $true), ensure you have a valid SSL certificate bound to the port.
# =====================================================
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("${protocol}://+:${port}/scim/")
$listener.Prefixes.Add("${protocol}://+:${port}/scim/serviceproviderconfig/")
$listener.Prefixes.Add("${protocol}://+:${port}/scim/users/")
$listener.Start()
Write-Host "SCIM test server running. Expected hostname: ${protocol}://${Hostname}:${port}/scim/"

# =====================================================
# In-Memory User Store (sample user)
# =====================================================
$users = @(
    @{
        id           = "1"
        userName     = "jdoe"
        name         = @{ givenName = "John"; familyName = "Doe" }
        active       = $true
        emails       = @(
            @{ value = "jdoe@example.com"; type = "work" }
        )
        phoneNumbers = @(
            @{ value = "+1234567890"; type = "mobile" }
        )
    }
)

# =====================================================
# Helper Functions
# =====================================================

# Constructs the SCIM JSON for a given user.
# If a list of attribute names is provided in $attributes, only those keys are returned.
function ConvertTo-ScimJson {
    param (
        [hashtable]$user,
        [string[]]$attributes
    )
    # Start with the required SCIM schema.
    $scimRepresentation = @{
        schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
    }
    if ($attributes -and $attributes.Count -gt 0) {
        foreach ($attr in $attributes) {
            if ($user.ContainsKey($attr)) {
                $scimRepresentation[$attr] = $user[$attr]
            }
        }
    }
    else {
        foreach ($key in $user.Keys) {
            $scimRepresentation[$key] = $user[$key]
        }
    }
    return $scimRepresentation | ConvertTo-Json -Depth 10
}

# Reads the entire request body.
function Read-RequestBody {
    param ($request)
    $reader = New-Object System.IO.StreamReader($request.InputStream)
    $body = $reader.ReadToEnd()
    $reader.Close()
    return $body
}

# Extracts a comma-separated list of requested attributes from the query string.
function Get-RequestedAttributes {
    param ($urlQuery)
    $attributes = @()
    if ($urlQuery -match "attributes=") {
        $queryParams = [System.Web.HttpUtility]::ParseQueryString($urlQuery)
        $attrParam = $queryParams["attributes"]
        if ($attrParam -and $attrParam.Trim() -ne "") {
            $attributes = $attrParam.Split(",") | ForEach-Object { $_.Trim() }
        }
    }
    return $attributes
}

# =====================================================
# Main Listener Loop
# =====================================================
while ($listener.IsListening) {
    $context   = $listener.GetContext()
    $request   = $context.Request
    $response  = $context.Response
    $path      = $request.Url.AbsolutePath.ToLower()

    Write-Host "`n[$($request.HttpMethod)] $path"
    Write-Host "Full URL: $($request.Url.AbsoluteUri)"

    # Validate the Host header against the configured $Hostname.
    if ($request.Url.Host -ne $Hostname) {
        Write-Host "Invalid Host header: $($request.Url.Host). Expected: $Hostname"
        $response.StatusCode = 400
        $errMsg = '{"error": "Invalid Host header"}'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
        $response.ContentType = "application/json"
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Flush()
        $response.Close()
        continue
    }

    # Log all request headers for debugging.
    $request.Headers.AllKeys | ForEach-Object {
        Write-Host "$_ : $($request.Headers[$_])"
    }

    # API Key validation using the configured $BearerToken.
    $authHeader = $request.Headers["Authorization"]
    $providedKey = $null
    if ($authHeader -and $authHeader.StartsWith("Bearer ")) {
        $providedKey = $authHeader.Substring(7)
    }
    Write-Host "Received Bearer Token: $providedKey"

    if ($providedKey -ne $BearerToken) {
        $response.StatusCode = 401
        $response.ContentType = "application/json"
        $responseBody = '{"error":"Unauthorized - Invalid API Key"}'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Flush()
        $response.Close()
        continue
    }

    $response.ContentType = "application/scim+json"
    $response.StatusCode = 200

    # GET /scim/users (with optional attribute filtering and userName filter)
    if ((($path -eq "/scim/users") -or ($path -eq "/scim/users/")) -and $request.HttpMethod -eq "GET") {
        $requestedAttrs = Get-RequestedAttributes $request.Url.Query
        $decodedQuery = [System.Net.WebUtility]::UrlDecode($request.Url.Query)
        if ($decodedQuery -match 'userName\s+eq\s+"(.+?)"') {
            $filterUserName = $matches[1]
            Write-Host "Decoded filter userName: $filterUserName"
            $matchedUsers = $users | Where-Object { $_.userName -eq $filterUserName }
            $listResponse = @{
                schemas      = @("urn:ietf:params:scim:api:messages:2.0:ListResponse")
                totalResults = $matchedUsers.Count
                Resources    = $matchedUsers | ForEach-Object {
                    ConvertTo-ScimJson -user $_ -attributes $requestedAttrs | ConvertFrom-Json
                }
            }
            $responseBody = $listResponse | ConvertTo-Json -Depth 10
        }
        else {
            $listResponse = @{
                schemas      = @("urn:ietf:params:scim:api:messages:2.0:ListResponse")
                totalResults = $users.Count
                Resources    = $users | ForEach-Object {
                    ConvertTo-ScimJson -user $_ -attributes $requestedAttrs | ConvertFrom-Json
                }
            }
            $responseBody = $listResponse | ConvertTo-Json -Depth 10
        }
    }
    # GET /scim/users/{id}
    elseif ($path -match "^/scim/users/(\d+)$" -and $request.HttpMethod -eq "GET") {
        $requestedAttrs = Get-RequestedAttributes $request.Url.Query
        $userId = $matches[1]
        $user = $users | Where-Object { $_.id -eq $userId }
        if ($user) {
            $responseBody = ConvertTo-ScimJson -user $user -attributes $requestedAttrs
        }
        else {
            $response.StatusCode = 404
            $errorResponse = @{
                schemas = @("urn:ietf:params:scim:api:messages:2.0:Error")
                detail  = "User with id '$userId' not found."
                status  = "404"
            }
            $responseBody = $errorResponse | ConvertTo-Json -Depth 10
        }
    }
    # POST /scim/users (create a new user with dynamic attribute merging)
    elseif ((($path -eq "/scim/users") -or ($path -eq "/scim/users/")) -and $request.HttpMethod -eq "POST") {
        $body = Read-RequestBody $request | ConvertFrom-Json
        $newId = ([int]$users[-1].id + 1).ToString()
        # Create new user with auto-assigned id.
        $userObj = [ordered]@{ id = $newId }
        # Merge all properties from the incoming JSON, except any id property.
        foreach ($property in $body.PSObject.Properties) {
            if ($property.Name -ne "id") {
                $userObj[$property.Name] = $property.Value
            }
        }
        $users += $userObj
        $response.StatusCode = 201
        $responseBody = ConvertTo-ScimJson -user $userObj -attributes @()
    }
    # PATCH /scim/users/{id} (update an existing user with dynamic attribute merging)
    elseif ($path -match "^/scim/users/(\d+)$" -and $request.HttpMethod -eq "PATCH") {
        $userId = $matches[1]
        $body = Read-RequestBody $request | ConvertFrom-Json
        $user = $users | Where-Object { $_.id -eq $userId }
        if ($user) {
            # Update any property provided in the request, except the id.
            foreach ($property in $body.PSObject.Properties) {
                if ($property.Name -ne "id") {
                    $user[$property.Name] = $property.Value
                }
            }
            $responseBody = ConvertTo-ScimJson -user $user -attributes @()
        }
        else {
            $response.StatusCode = 404
            $errorResponse = @{
                schemas = @("urn:ietf:params:scim:api:messages:2.0:Error")
                detail  = "User with id '$userId' not found."
                status  = "404"
            }
            $responseBody = $errorResponse | ConvertTo-Json -Depth 10
        }
    }
    # DELETE /scim/users/{id} (delete a user)
    elseif ($path -match "^/scim/users/(\d+)$" -and $request.HttpMethod -eq "DELETE") {
        $userId = $matches[1]
        $index = $users.FindIndex({ $_.id -eq $userId })
        if ($index -ge 0) {
            $users.RemoveAt($index)
            $response.StatusCode = 204
            $responseBody = ""
        }
        else {
            $response.StatusCode = 404
            $errorResponse = @{
                schemas = @("urn:ietf:params:scim:api:messages:2.0:Error")
                detail  = "User with id '$userId' not found."
                status  = "404"
            }
            $responseBody = $errorResponse | ConvertTo-Json -Depth 10
        }
    }
    # GET /scim/serviceproviderconfig (retrieve service provider configuration)
    elseif ($path -eq "/scim/serviceproviderconfig" -or $path -eq "/scim/serviceproviderconfig/") {
        $response.StatusCode = 200
        $responseBody = @'
{
    "schemas": ["urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"],
    "patch": { "supported": true },
    "bulk": { "supported": false },
    "filter": { "supported": true },
    "changePassword": { "supported": false },
    "sort": { "supported": false },
    "etag": { "supported": false },
    "authenticationSchemes": []
}
'@
    }
    else {
        $response.StatusCode = 404
        $responseBody = '{"error":"Endpoint not implemented"}'
    }

    Write-Host "Response Body:"
    Write-Host $responseBody

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Flush()
    $response.Close()
}
