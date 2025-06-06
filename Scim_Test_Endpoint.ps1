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
# Set up the HTTP Listener
# =====================================================
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("${protocol}://+:${port}/scim/")
$listener.Start()
Write-Host "SCIM test server running: ${protocol}://${Hostname}:${port}/scim/"

# =====================================================
# In-Memory User Store (Now includes additional attributes)
# =====================================================
$users = @(
    @{
        id           = "1"
        userName     = "jdoe"
        name         = @{ givenName = "John"; familyName = "Doe" }
        active       = $true
        emails       = @(@{ value = "jdoe@example.com"; type = "work" })
        phoneNumbers = @(@{ value = "+1234567890"; type = "mobile" })
        jobTitle     = "Software Engineer"
        department   = "IT"
    }
)

# =====================================================
# Helper Functions
# =====================================================

function ConvertTo-ScimJson {
    param (
        [hashtable]$user,
        [string[]]$attributes
    )
    $scimRepresentation = @{ schemas = @("urn:ietf:params:scim:schemas:core:2.0:User") }
    
    if ($attributes -and $attributes.Count -gt 0) {
        foreach ($attr in $attributes) {
            if ($user.ContainsKey($attr)) {
                $scimRepresentation[$attr] = $user[$attr]
            }
        }
    } else {
        foreach ($key in $user.Keys) {
            $scimRepresentation[$key] = $user[$key]
        }
    }

    return $scimRepresentation | ConvertTo-Json -Depth 10
}

function Read-RequestBody {
    param ($request)
    $reader = New-Object System.IO.StreamReader($request.InputStream)
    $body = $reader.ReadToEnd()
    $reader.Close()
    return $body
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
    
    # Validate API Key
    $authHeader = $request.Headers["Authorization"]
    $providedKey = $null
    if ($authHeader -and $authHeader.StartsWith("Bearer ")) {
        $providedKey = $authHeader.Substring(7)
    }

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

    # GET /scim/users (Retrieve Users)
    if (($path -eq "/scim/users" -or $path -eq "/scim/users/") -and $request.HttpMethod -eq "GET") {
        $responseBody = ConvertTo-Json @{ Resources = $users; totalResults = $users.Count } -Depth 10
    }
    
    # POST /scim/users (Create User)
    elseif (($path -eq "/scim/users" -or $path -eq "/scim/users/") -and $request.HttpMethod -eq "POST") {
        $body = Read-RequestBody $request | ConvertFrom-Json
        $newId = ([int]$users[-1].id + 1).ToString()
        $newUser = @{
            id       = $newId
            userName = $body.userName
            name     = $body.name
            active   = $body.active
            jobTitle = $body.jobTitle
            department = $body.department
        }
        $users += $newUser
        $response.StatusCode = 201
        $responseBody = ConvertTo-ScimJson -user $newUser
    }
    
    # PATCH /scim/users/{id} (Update User)
    elseif ($path -match "^/scim/users/(\d+)$" -and $request.HttpMethod -eq "PATCH") {
        $userId = $matches[1]
        $body = Read-RequestBody $request | ConvertFrom-Json
        $user = $users | Where-Object { $_.id -eq $userId }
        if ($user) {
            if ($body.userName)  { $user.userName = $body.userName }
            if ($body.name)      { $user.name = $body.name }
            if ($body.active)    { $user.active = $body.active }
            if ($body.jobTitle)  { $user.jobTitle = $body.jobTitle }
            if ($body.department){ $user.department = $body.department }
            $responseBody = ConvertTo-ScimJson -user $user
        } else {
            $response.StatusCode = 404
            $responseBody = '{"error":"User not found"}'
        }
    }
    
    # DELETE /scim/users/{id} (Delete User)
    elseif ($path -match "^/scim/users/(\d+)$" -and $request.HttpMethod -eq "DELETE") {
        $userId = $matches[1]
        $users = $users | Where-Object { $_.id -ne $userId }
        $response.StatusCode = 204
        $responseBody = ""
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
