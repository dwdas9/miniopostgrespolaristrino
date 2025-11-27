# delete-catalog.ps1

$clientId = "aef701c93c2e3f14"
$clientSecret = "24c4018dfcdc9378c8a7def2c4adb452"

Write-Host "Deleting catalog 'my_catalog'..."

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

# Delete catalog
try {
    Invoke-RestMethod -Uri "http://localhost:8181/api/management/v1/catalogs/my_catalog" `
        -Method Delete `
        -Headers @{
            "Authorization" = "Bearer $TOKEN"
        }
    Write-Host "[OK] Catalog deleted successfully!"
} catch {
    Write-Host "[ERROR] Failed to delete catalog:"
    Write-Host $_.Exception.Message
}
