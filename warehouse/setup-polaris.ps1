# setup-polaris.ps1

$clientId = "3ee8b49243069ee0"
$clientSecret = "9b21f21aa5029e00ce0eb8d9dd189dfc"

Write-Host "Setting up Polaris catalog..."

Write-Host ""
Write-Host "[1/3] Getting OAuth token..."

try {
    $response = Invoke-RestMethod -Uri "http://localhost:8181/api/catalog/v1/oauth/tokens" `
        -Method Post `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            grant_type = "client_credentials"
            client_id = $clientId
            client_secret = $clientSecret
            scope = "PRINCIPAL_ROLE:ALL"
        }
    
    $TOKEN = $response.access_token
    Write-Host "[OK] Token obtained successfully!"
} catch {
    Write-Host "[ERROR] Failed to get token:"
    Write-Host $_.Exception.Message
    exit 1
}

Write-Host ""
Write-Host "[2/3] Creating catalog 'my_catalog'..."

$catalogBody = @{
    catalog = @{
        name = "my_catalog"
        type = "INTERNAL"
        properties = @{
            "default-base-location" = "s3://warehouse/"
        }
        storageConfigInfo = @{
            storageType = "S3"
            allowedLocations = @("s3://warehouse/*")
            region = "us-east-1"
            endpoint = "http://minio:9000"
            pathStyleAccess = $true
            stsUnavailable = $true
        }
    }
} | ConvertTo-Json -Depth 10

try {
    $result = Invoke-RestMethod -Uri "http://localhost:8181/api/management/v1/catalogs" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $TOKEN"
            "Content-Type" = "application/json"
        } `
        -Body $catalogBody
    
    Write-Host "[OK] Catalog created successfully!"
} catch {
    Write-Host "[ERROR] Error creating catalog:"
    Write-Host $_.Exception.Message
    if ($_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message
    }
    exit 1
}

Write-Host ""
Write-Host "[3/3] Verifying setup..."

try {
    $catalogs = Invoke-RestMethod -Uri "http://localhost:8181/api/management/v1/catalogs" `
        -Method Get `
        -Headers @{
            "Authorization" = "Bearer $TOKEN"
        }
    
    Write-Host "[OK] Verification successful!"
    Write-Host ""
    Write-Host "Available catalogs:"
    $catalogs.catalogs | ForEach-Object { Write-Host "  - $($_.name)" }
} catch {
    Write-Host "[ERROR] Verification failed"
}

Write-Host ""
Write-Host "========================================"
Write-Host "SETUP COMPLETE!"
Write-Host "========================================"
Write-Host ""
Write-Host "Spark Configuration Credentials:"
Write-Host "  client_id:     $clientId"
Write-Host "  client_secret: $clientSecret"
Write-Host "  catalog_name:  my_catalog"
Write-Host "========================================"

# Save to .env file
@"
POLARIS_CLIENT_ID=$clientId
POLARIS_CLIENT_SECRET=$clientSecret
POLARIS_CATALOG=my_catalog
"@ | Out-File -FilePath ".env" -Encoding UTF8

Write-Host ""
Write-Host "[OK] Credentials saved to .env file"