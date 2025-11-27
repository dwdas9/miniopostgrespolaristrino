# update-catalog.ps1

$clientId = "aef701c93c2e3f14"
$clientSecret = "24c4018dfcdc9378c8a7def2c4adb452"

Write-Host "Updating catalog 'my_catalog' properties..."

# Get OAuth token
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
Write-Host "[OK] Token obtained"

# Update catalog properties
$updateBody = @{
    properties = @{
        "default-base-location" = "s3://warehouse/"
        "s3.endpoint" = "http://minio:9000"
        "s3.access-key-id" = "minioadmin"
        "s3.secret-access-key" = "minioadmin"
        "s3.path-style-access" = "true"
        "credential-vending-enabled" = "false"
    }
    storageConfigInfo = @{
        storageType = "S3"
        allowedLocations = @("s3://warehouse/", "s3a://warehouse/")
        roleArn = $null
    }
} | ConvertTo-Json -Depth 10

try {
    $result = Invoke-RestMethod -Uri "http://localhost:8181/api/management/v1/catalogs/my_catalog" `
        -Method PUT `
        -Headers @{
            "Authorization" = "Bearer $TOKEN"
            "Content-Type" = "application/json"
        } `
        -Body $updateBody
    
    Write-Host "[OK] Catalog updated successfully!"
    Write-Host ""
    Write-Host "Catalog 'my_catalog' now has credential vending disabled"
} catch {
    Write-Host "[ERROR] Failed to update catalog:"
    Write-Host $_.Exception.Message
    if ($_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message
    }
}
