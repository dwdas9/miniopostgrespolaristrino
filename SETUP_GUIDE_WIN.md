# Complete Setup Guide: Polaris + Iceberg + MinIO + Spark

## 📋 Table of Contents
- [Architecture Overview](#architecture-overview)
- [Component Versions](#component-versions)
- [Prerequisites](#prerequisites)
- [Step-by-Step Setup](#step-by-step-setup)
- [Configuration Details](#configuration-details)
- [Common Issues & Solutions](#common-issues--solutions)
- [Verification Steps](#verification-steps)

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     User (Jupyter Notebook)                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Apache Spark 3.4.1                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Spark SQL  │  │  DataFrame   │  │  Streaming   │          │
│  │    Engine    │  │     API      │  │    Engine    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└──────────┬───────────────────┬──────────────────┬───────────────┘
           │                   │                  │
           │ REST API          │ S3 API          │ S3A API
           ▼                   ▼                  ▼
┌──────────────────┐  ┌──────────────────────────────────────┐
│  Apache Polaris  │  │           MinIO (S3-Compatible)       │
│   REST Catalog   │  │  ┌────────────────────────────────┐  │
│  ┌────────────┐  │  │  │  Iceberg Table Data (Parquet)  │  │
│  │  Metadata  │  │  │  │  - /warehouse/test_db/         │  │
│  │  Registry  │  │  │  │    test_table/data/*.parquet   │  │
│  │  OAuth2    │  │  │  │  - Metadata files              │  │
│  └────────────┘  │  │  │  - Manifest files              │  │
│        │         │  │  └────────────────────────────────┘  │
│        ▼         │  └──────────────────────────────────────┘
│  ┌────────────┐  │
│  │ PostgreSQL │  │  Database: polaris_db
│  │  Backend   │  │  Stores: Catalogs, Namespaces,
│  └────────────┘  │          Tables, Snapshots, Principals
└──────────────────┘
```

### Data Flow

1. **Query Submission**: User writes Spark SQL in Jupyter notebook
2. **Catalog Lookup**: Spark contacts Polaris REST API to get table metadata
3. **Authentication**: Polaris validates OAuth2 credentials
4. **Metadata Retrieval**: Polaris queries PostgreSQL for table location, schema, snapshots
5. **File Discovery**: Spark reads Iceberg metadata files from MinIO to find data files
6. **Data Reading**: Spark reads Parquet files directly from MinIO using S3A protocol
7. **Query Execution**: Spark processes data in-memory and returns results

### Storage Layout in MinIO

```
s3://warehouse/
├── test_db/                          (namespace/database)
│   └── test_table/                   (table)
│       ├── data/                     (actual data files)
│       │   ├── 00001-1-xxx.parquet
│       │   └── 00002-1-xxx.parquet
│       └── metadata/                 (Iceberg metadata)
│           ├── v1.metadata.json      (table metadata snapshot 1)
│           ├── v2.metadata.json      (table metadata snapshot 2)
│           ├── snap-xxx-1-xxx.avro   (manifest list)
│           └── xxx-m0.avro           (manifest file)
```

---

## 📦 Component Versions

| Component | Version | Purpose | Why This Version |
|-----------|---------|---------|------------------|
| **Apache Polaris** | 1.2.0-incubating | REST Catalog | Latest stable release with `stsUnavailable` support |
| **PostgreSQL** | 15-alpine | Metadata storage | Lightweight, stable, Polaris compatible |
| **MinIO** | latest (RELEASE.2024-11) | S3-compatible storage | Latest stable with all S3 API features |
| **Apache Spark** | 3.4.1 | Query engine | Matches Iceberg 1.4.3 compatibility matrix |
| **Apache Iceberg** | 1.4.3 | Table format | Latest with Spark 3.4 support |
| **Scala** | 2.12 | JVM language | Required by Spark 3.4.1 |
| **Hadoop AWS** | 3.3.4 | S3A filesystem | Provides S3 client for Spark |
| **AWS SDK Bundle** | 1.12.262 | AWS SDK v1 | S3 operations compatibility |
| **Iceberg AWS Bundle** | 1.4.3 | AWS SDK v2 | Iceberg S3 operations |

### Version Compatibility Matrix

```
Spark 3.4.1 (Scala 2.12)
    ├── iceberg-spark-runtime-3.4_2.12:1.4.3 ✓
    ├── hadoop-aws:3.3.4 ✓
    ├── aws-java-sdk-bundle:1.12.262 ✓
    └── iceberg-aws-bundle:1.4.3 ✓

Polaris 1.2.0
    ├── PostgreSQL 15 ✓
    ├── REST Catalog API v1 ✓
    └── OAuth2 authentication ✓
```

---

## ✅ Prerequisites

### Required Software
- **Docker Desktop**: 4.x or later
- **Docker Compose**: 2.x or later (included with Docker Desktop)
- **PowerShell**: 5.1 or later (Windows) or Bash (Mac/Linux)
- **Web Browser**: For Jupyter (localhost:8888) and MinIO Console (localhost:9001)

### System Requirements
- **RAM**: Minimum 8GB, Recommended 16GB
- **Disk Space**: 10GB free space
- **CPU**: 4 cores recommended
- **Network**: Internet connection for initial image downloads (~2GB)

### Port Requirements
Ensure these ports are available:
- `5432` - PostgreSQL
- `8181` - Polaris REST API
- `8888` - Jupyter Notebook
- `9000` - MinIO S3 API
- `9001` - MinIO Console
- `4040` - Spark UI (when jobs are running)

---

## 🚀 Step-by-Step Setup

### Step 1: Create Docker Network

```powershell
docker network create dasnet
```

**Why**: All containers must communicate. The `dasnet` bridge network allows containers to reach each other by name (e.g., `http://minio:9000`).

### Step 2: Start Core Infrastructure

```powershell
docker-compose up -d
```

This starts:
- ✅ PostgreSQL (database for Polaris metadata)
- ✅ MinIO (S3-compatible object storage)
- ✅ Polaris (REST catalog service)

**Wait time**: ~30 seconds for all health checks to pass.

### Step 3: Get Bootstrap Credentials

```powershell
docker logs warehouse-polaris 2>&1 | Select-String -Pattern "credentials:" -Context 0,2
```

**Output example**:
```
realm: POLARIS root principal credentials: 3ee8b49243069ee0:9b21f21aa5029e00ce0eb8d9dd189dfc
```

**Important**: These credentials change every time Polaris restarts!

### Step 4: Initialize Polaris Catalog

Edit `setup-polaris.ps1` and update credentials:

```powershell
$clientId = "3ee8b49243069ee0"
$clientSecret = "9b21f21aa5029e00ce0eb8d9dd189dfc"
```

Run the setup script:

```powershell
powershell -ExecutionPolicy Bypass -File setup-polaris.ps1
```

**What it does**:
1. Authenticates with Polaris using OAuth2
2. Creates catalog named `my_catalog` with these settings:
   - Type: `INTERNAL`
   - Storage: S3 with MinIO endpoint
   - **`stsUnavailable: true`** (disables AWS STS credential vending)
3. Saves credentials to `.env` file

### Step 5: Start Spark Notebook

```powershell
docker-compose -f spark-notebook-compose.yml up -d
```

**Access**: http://localhost:8888 (no password required)

### Step 6: Configure Spark Session

Open `getting_started.ipynb` and run the first cell:

```python
from pyspark.sql import SparkSession
import os

# Set AWS credentials and region for SDK v2
os.environ['AWS_REGION'] = 'us-east-1'
os.environ['AWS_ACCESS_KEY_ID'] = 'minioadmin'
os.environ['AWS_SECRET_ACCESS_KEY'] = 'minioadmin'

# Polaris + Iceberg with MinIO
spark = SparkSession.builder \
    .appName("Polaris-Iceberg-MinIO") \
    .config("spark.jars.packages", 
            "org.apache.iceberg:iceberg-spark-runtime-3.4_2.12:1.4.3,"
            "org.apache.hadoop:hadoop-aws:3.3.4,"
            "com.amazonaws:aws-java-sdk-bundle:1.12.262,"
            "org.apache.iceberg:iceberg-aws-bundle:1.4.3") \
    .config("spark.sql.catalog.polaris", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.polaris.catalog-impl", "org.apache.iceberg.rest.RESTCatalog") \
    .config("spark.sql.catalog.polaris.uri", "http://host.docker.internal:8181/api/catalog") \
    .config("spark.sql.catalog.polaris.credential", "3ee8b49243069ee0:9b21f21aa5029e00ce0eb8d9dd189dfc") \
    .config("spark.sql.catalog.polaris.warehouse", "my_catalog") \
    .config("spark.sql.catalog.polaris.scope", "PRINCIPAL_ROLE:ALL") \
    .config("spark.hadoop.fs.s3.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minioadmin") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .config("spark.hadoop.fs.s3a.aws.credentials.provider", "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider") \
    .getOrCreate()
```

**First run**: Takes 2-3 minutes to download JARs from Maven Central.

### Step 7: Verify Setup

```python
# Show namespaces
spark.sql("SHOW NAMESPACES IN polaris").show()

# Create test namespace
spark.sql("CREATE NAMESPACE IF NOT EXISTS polaris.test_db")

# Create test table
spark.sql("""
    CREATE TABLE IF NOT EXISTS polaris.test_db.test_table (
        id INT,
        name STRING
    ) USING iceberg
""")

# Insert data
spark.sql("INSERT INTO polaris.test_db.test_table VALUES (1, 'Hello'), (2, 'World')")

# Query data
spark.sql("SELECT * FROM polaris.test_db.test_table").show()
```

**Expected output**:
```
+---+-----+
| id| name|
+---+-----+
|  1|Hello|
|  2|World|
+---+-----+
```

✅ **Setup complete!**

---

## ⚙️ Configuration Details

### Docker Compose Configuration

#### PostgreSQL (for Polaris metadata)
```yaml
postgres:
  image: postgres:15-alpine
  environment:
    POSTGRES_DB: polaris_db
    POSTGRES_USER: polaris
    POSTGRES_PASSWORD: polaris_password
  ports:
    - "5432:5432"
```

#### MinIO (S3-compatible storage)
```yaml
minio:
  image: minio/minio:latest
  environment:
    MINIO_ROOT_USER: minioadmin
    MINIO_ROOT_PASSWORD: minioadmin
  ports:
    - "9000:9000"  # S3 API
    - "9001:9001"  # Web Console
  command: server /data --console-address ":9001"
```

#### Polaris (REST Catalog)
```yaml
polaris:
  image: apache/polaris:latest
  environment:
    # PostgreSQL connection
    QUARKUS_DATASOURCE_JDBC_URL: "jdbc:postgresql://postgres:5432/polaris_db"
    QUARKUS_DATASOURCE_USERNAME: "polaris"
    QUARKUS_DATASOURCE_PASSWORD: "polaris_password"
    QUARKUS_HIBERNATE_ORM_DATABASE_GENERATION: "update"
    
    # AWS/MinIO configuration
    AWS_ACCESS_KEY_ID: minioadmin
    AWS_SECRET_ACCESS_KEY: minioadmin
    AWS_REGION: us-east-1
    AWS_ENDPOINT_URL_S3: http://minio:9000
  ports:
    - "8181:8181"
```

### Polaris Catalog Configuration

The catalog is created via REST API with this structure:

```json
{
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
      "stsUnavailable": true  // ← CRITICAL: Disables AWS STS
    }
  }
}
```

**Key setting**: `"stsUnavailable": true`
- Without this, Polaris tries to use AWS STS for temporary credentials
- MinIO doesn't support AWS STS, causing 403 errors
- This flag tells Polaris to use static credentials instead

### Spark Configuration Breakdown

```python
# JAR dependencies (downloaded from Maven Central)
"spark.jars.packages": 
    "org.apache.iceberg:iceberg-spark-runtime-3.4_2.12:1.4.3,"  # Iceberg engine
    "org.apache.hadoop:hadoop-aws:3.3.4,"                        # S3A filesystem
    "com.amazonaws:aws-java-sdk-bundle:1.12.262,"               # AWS SDK v1
    "org.apache.iceberg:iceberg-aws-bundle:1.4.3"               # AWS SDK v2 for Iceberg

# Catalog configuration
"spark.sql.catalog.polaris": "org.apache.iceberg.spark.SparkCatalog"
"spark.sql.catalog.polaris.catalog-impl": "org.apache.iceberg.rest.RESTCatalog"
"spark.sql.catalog.polaris.uri": "http://host.docker.internal:8181/api/catalog"
"spark.sql.catalog.polaris.credential": "<clientId>:<clientSecret>"
"spark.sql.catalog.polaris.warehouse": "my_catalog"
"spark.sql.catalog.polaris.scope": "PRINCIPAL_ROLE:ALL"

# S3A filesystem (for s3:// URIs)
"spark.hadoop.fs.s3.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
"spark.hadoop.fs.s3a.endpoint": "http://minio:9000"
"spark.hadoop.fs.s3a.access.key": "minioadmin"
"spark.hadoop.fs.s3a.secret.key": "minioadmin"
"spark.hadoop.fs.s3a.path.style.access": "true"  # Required for MinIO
"spark.hadoop.fs.s3a.connection.ssl.enabled": "false"
"spark.hadoop.fs.s3a.aws.credentials.provider": 
    "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider"
```

**Why `host.docker.internal`**: 
- Spark container needs to reach Polaris container
- `localhost` won't work (different network namespaces)
- `host.docker.internal` resolves to the host machine, then Docker routing handles it

---

## 🐛 Common Issues & Solutions

### Issue 1: "Failed to get subscoped credentials" (AWS STS Error)

**Error**:
```
The security token included in the request is invalid. (Service: Sts, Status Code: 403)
```

**Root Cause**: Polaris trying to use AWS STS credential vending with MinIO (which doesn't support STS).

**Solution**: Ensure `"stsUnavailable": true` in catalog `storageConfigInfo`. Run `setup-polaris.ps1` to recreate catalog.

---

### Issue 2: "No FileSystem for scheme 's3'"

**Error**:
```
org.apache.hadoop.fs.UnsupportedFileSystemException: No FileSystem for scheme "s3"
```

**Root Cause**: Spark doesn't have S3 filesystem configured.

**Solution**: Add to Spark config:
```python
.config("spark.hadoop.fs.s3.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
```

---

### Issue 3: "Unable to load region" (AWS SDK v2)

**Error**:
```
Unable to load region from any of the providers in the chain
```

**Root Cause**: AWS SDK v2 requires `AWS_REGION` environment variable.

**Solution**: Add at top of notebook:
```python
import os
os.environ['AWS_REGION'] = 'us-east-1'
os.environ['AWS_ACCESS_KEY_ID'] = 'minioadmin'
os.environ['AWS_SECRET_ACCESS_KEY'] = 'minioadmin'
```

---

### Issue 4: "NoClassDefFoundError: software/amazon/awssdk/services/s3/model/S3Exception"

**Error**:
```
java.lang.NoClassDefFoundError: software/amazon/awssdk/services/s3/model/S3Exception
```

**Root Cause**: Missing AWS SDK v2 classes.

**Solution**: Add to packages:
```python
"org.apache.iceberg:iceberg-aws-bundle:1.4.3"
```

---

### Issue 5: Polaris Bootstrap Credentials Not Working

**Symptom**: 401 Unauthorized when running `setup-polaris.ps1`

**Root Cause**: Bootstrap credentials change on every Polaris restart.

**Solution**:
1. Get new credentials: `docker logs warehouse-polaris | Select-String "credentials:"`
2. Update `setup-polaris.ps1` with new clientId/clientSecret
3. Re-run script

---

### Issue 6: "Connection refused" to Polaris

**Symptom**: Cannot connect to `http://host.docker.internal:8181`

**Root Cause**: Polaris container not running or not healthy.

**Solution**:
```powershell
# Check container status
docker ps -a

# Check Polaris logs
docker logs warehouse-polaris

# Restart if needed
docker restart warehouse-polaris
```

---

### Issue 7: Duplicate Data After INSERT

**Symptom**: Running INSERT multiple times creates duplicate rows.

**Root Cause**: Iceberg doesn't check for duplicates (by design).

**Solution**: Use `MERGE` or `DELETE` + `INSERT`, or drop table:
```sql
DROP TABLE IF EXISTS polaris.test_db.test_table;
```

---

## ✔️ Verification Steps

### 1. Check All Containers Running

```powershell
docker ps
```

Expected output (4 containers):
```
CONTAINER ID   IMAGE                        STATUS         PORTS
xxx            warehouse-postgres           Up 2 minutes   5432->5432
xxx            warehouse-minio              Up 2 minutes   9000-9001->9000-9001
xxx            warehouse-polaris            Up 2 minutes   8181->8181
xxx            jupyter/pyspark-notebook     Up 1 minute    8888->8888
```

### 2. Test MinIO Access

Open http://localhost:9001
- Login: `minioadmin` / `minioadmin`
- Navigate to **Buckets** → `warehouse`
- Should see folder structure: `test_db/test_table/data/`

### 3. Test PostgreSQL

```powershell
docker exec -it warehouse-polaris psql -U polaris -d polaris_db -c "\dt POLARIS.*"
```

Should show Polaris schema tables.

### 4. Test Polaris REST API

```powershell
$token = (Invoke-RestMethod -Uri "http://localhost:8181/api/catalog/v1/oauth/tokens" -Method Post -ContentType "application/x-www-form-urlencoded" -Body @{grant_type="client_credentials"; client_id="<YOUR_CLIENT_ID>"; client_secret="<YOUR_CLIENT_SECRET>"; scope="PRINCIPAL_ROLE:ALL"}).access_token

Invoke-RestMethod -Uri "http://localhost:8181/api/management/v1/catalogs" -Headers @{Authorization="Bearer $token"}
```

Should return catalog list including `my_catalog`.

### 5. Test Spark + Iceberg

In Jupyter notebook:

```python
# Show all namespaces
spark.sql("SHOW NAMESPACES IN polaris").show()

# Show tables
spark.sql("SHOW TABLES IN polaris.test_db").show()

# Count rows
spark.sql("SELECT COUNT(*) FROM polaris.test_db.test_table").show()

# Time travel (show snapshots)
spark.sql("SELECT * FROM polaris.test_db.test_table.snapshots").show()
```

### 6. Test Data Persistence

```powershell
# Stop everything
docker-compose down
docker-compose -f spark-notebook-compose.yml down

# Start again
docker-compose up -d
docker-compose -f spark-notebook-compose.yml up -d

# Get new Polaris credentials and run setup-polaris.ps1
# Update notebook with new credentials
# Query table - data should still be there!
```

---

## 🎯 Success Criteria

✅ All containers running and healthy  
✅ Polaris REST API responding  
✅ MinIO accessible with data visible  
✅ Spark can create namespaces  
✅ Spark can create Iceberg tables  
✅ INSERT operations succeed  
✅ SELECT queries return data  
✅ Data persists after container restart  
✅ Time travel queries work  
✅ Schema evolution works (ADD COLUMN)  

---

## 📚 Next Steps

1. **Explore Iceberg features**: Time travel, schema evolution, partition evolution
2. **Load real data**: CSV, JSON, Parquet files
3. **Try streaming**: Structured Streaming with Iceberg
4. **Performance tuning**: Partition strategies, compaction
5. **Scale up**: Add more Spark workers, MinIO nodes

---

## 🆘 Getting Help

- **GitHub Issues**: https://github.com/dwdas9/miniopostgrespolaristrino/issues
- **Apache Iceberg Docs**: https://iceberg.apache.org/docs/latest/
- **Apache Polaris Docs**: https://polaris.apache.org/
- **Spark SQL Guide**: https://spark.apache.org/docs/latest/sql-programming-guide.html
