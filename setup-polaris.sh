#!/bin/bash
# setup-polaris.sh - Mac/Linux version

# ================================================
# STEP 1: Get your credentials from Polaris logs
# Run: docker logs warehouse-polaris 2>&1 | grep "credentials:"
# Then update these values:
# ================================================
CLIENT_ID="30d861989a2b1605"
CLIENT_SECRET="c93e64ae4132ecb1a33aba14e8506a6d"

echo "Setting up Polaris catalog..."
echo ""

# Get OAuth token
echo "[1/3] Getting OAuth token..."
TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:8181/api/catalog/v1/oauth/tokens" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=PRINCIPAL_ROLE:ALL")

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "[ERROR] Failed to get token. Check credentials."
  echo "Response: $TOKEN_RESPONSE"
  echo ""
  echo "To get credentials, run:"
  echo "  docker logs warehouse-polaris 2>&1 | grep 'credentials:'"
  exit 1
fi

echo "[OK] Token obtained!"
echo ""

# Create catalog
echo "[2/3] Creating catalog 'my_catalog'..."
CATALOG_RESPONSE=$(curl -s -X POST "http://localhost:8181/api/management/v1/catalogs" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "catalog": {
      "name": "my_catalog",
      "type": "INTERNAL",
      "properties": {
        "default-base-location": "s3://warehouse/"
      },
      "storageConfigInfo": {
        "storageType": "S3",
        "allowedLocations": ["s3://warehouse/*"],
        "region": "us-east-1",
        "endpoint": "http://minio:9000",
        "pathStyleAccess": true,
        "stsUnavailable": true
      }
    }
  }')

if echo "$CATALOG_RESPONSE" | grep -q "error"; then
  echo "[ERROR] Failed to create catalog:"
  echo "$CATALOG_RESPONSE"
  exit 1
fi

echo "[OK] Catalog created!"
echo ""

# Verify
echo "[3/3] Verifying setup..."
CATALOGS=$(curl -s -X GET "http://localhost:8181/api/management/v1/catalogs" \
  -H "Authorization: Bearer ${TOKEN}")

echo "[OK] Available catalogs:"
echo "$CATALOGS" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read name; do
  echo "  - $name"
done

echo ""
echo "========================================"
echo "SETUP COMPLETE!"
echo "========================================"
echo ""
echo "Spark Configuration Credentials:"
echo "  client_id:     $CLIENT_ID"
echo "  client_secret: $CLIENT_SECRET"
echo "  catalog_name:  my_catalog"
echo "========================================"

# Save to .env
cat > .env << EOF
POLARIS_CLIENT_ID=$CLIENT_ID
POLARIS_CLIENT_SECRET=$CLIENT_SECRET
POLARIS_CATALOG=my_catalog
EOF

echo ""
echo "[OK] Credentials saved to .env file"
