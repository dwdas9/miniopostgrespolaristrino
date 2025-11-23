# On-Premise Iceberg Data Warehouse

A fully on-premises data warehouse using **Spark**, **Polaris**, and **MinIO** — all running in Docker. No cloud connectivity, no external dependencies.

---

## Architecture

```
Spark (Query Engine) ← Iceberg Tables ← MinIO (S3 Storage)
                  ↓
            Polaris REST Catalog
                  ↓
            PostgreSQL (Metadata)
```

| Component | Role | Port |
|-----------|------|------|
| **PostgreSQL** | Metadata backend for Polaris | 5432 |
| **MinIO** | S3-compatible object storage | 9000, 9001 |
| **Polaris** | REST Catalog for Iceberg metadata | 8181 |
| **Spark + Jupyter** | Query engine & interactive notebooks | 8888, 4040 |

---

## Quick Start

### 1. First Time Setup
```bash
cd warehouse

# Create Docker network and volumes
docker network create dasnet
docker volume create warehouse_storage
```

### 2. Start All Services
```bash
# Start infrastructure (postgres, minio, polaris)
docker-compose up -d

# Start Spark + Jupyter
docker-compose -f spark-notebook-compose.yml up -d

# Verify all containers running
docker ps
```

### 3. Access Your Warehouse
- **Jupyter Notebook**: http://localhost:8888
- **MinIO Console**: http://localhost:9001 (minioadmin/minioadmin)
- **Spark UI**: http://localhost:4040 (while queries run)

---

## Using Spark to Query Tables

### Basic Pattern
Since **`polaris` is your default catalog**, you query tables as:

```python
spark.sql("SELECT * FROM schema.tablename")
```

No catalog prefix needed!

### Create Tables
```python
# Create namespace (schema)
spark.sql("CREATE NAMESPACE IF NOT EXISTS mydb")

# Create Iceberg table with partitioning
spark.sql("""
    CREATE TABLE mydb.users (
        id INT,
        name STRING,
        created_at TIMESTAMP
    )
    USING ICEBERG
    PARTITIONED BY (CAST(created_at AS DATE))
""")
```

### Insert & Query Data
```python
# Insert data
spark.sql("""
    INSERT INTO mydb.users VALUES
    (1, 'Alice', CURRENT_TIMESTAMP()),
    (2, 'Bob', CURRENT_TIMESTAMP())
""")

# Query with simple schema.table
result = spark.sql("SELECT * FROM mydb.users")
result.show()

# DataFrame API
df = spark.table("mydb.users")
df.filter(df.id > 1).show()

# Join tables
spark.sql("""
    SELECT u.name, o.amount
    FROM mydb.users u
    JOIN mydb.orders o ON u.id = o.user_id
""").show()
```

### Advanced Iceberg Features
```python
# Time travel - view table history
spark.sql("SELECT * FROM mydb.users.history").show()

# Query specific version
spark.sql("SELECT * FROM mydb.users VERSION AS OF 1").show()

# Add column (schema evolution)
spark.sql("ALTER TABLE mydb.users ADD COLUMN email STRING")
```

---

## Configuration Reference

### Spark Configuration (Auto-configured)
All Spark containers have:
- ✅ `spark.sql.defaultCatalog=polaris` - Default catalog set
- ✅ `spark.sql.catalog.polaris=org.apache.iceberg.spark.SparkCatalog` - Polaris as catalog
- ✅ `spark.sql.catalog.polaris.uri=http://polaris:8181` - Polaris endpoint
- ✅ `spark.hadoop.fs.s3a.endpoint=http://minio:9000` - MinIO endpoint
- ✅ Iceberg Spark extensions enabled
- ✅ S3a configured for path-style access (MinIO compatible)

### Credentials (On-Prem)
- MinIO: `minioadmin` / `minioadmin`
- Polaris DB: `polaris` / `polaris_password`
- Polaris Admin: `admin` / `polaris`

---

## Common Operations

| Task | Command |
|------|---------|
| List catalogs | `spark.sql("SHOW CATALOGS").show()` |
| List schemas | `spark.sql("SHOW NAMESPACES IN polaris").show()` |
| List tables | `spark.sql("SHOW TABLES IN mydb").show()` |
| Table schema | `spark.sql("DESCRIBE TABLE mydb.users").show()` |
| Add column | `spark.sql("ALTER TABLE mydb.users ADD COLUMN new_col INT")` |
| Drop table | `spark.sql("DROP TABLE mydb.users")` |
| Row count | `spark.sql("SELECT COUNT(*) FROM mydb.users").show()` |

---

## Example Notebook

A complete example is in `workspace/notebooks/iceberg_queries.ipynb` with:
- Creating namespaces and tables
- Inserting sample data
- Querying with `schema.tablename` pattern
- Joining multiple tables
- Time travel queries
- Table metadata inspection

Open it in Jupyter at http://localhost:8888

---

## Helper Functions

In `workspace/notebooks/warehouse_helpers.py`:

```python
# Setup demo warehouse with sample tables
setup_demo_warehouse()

# Common operations
create_namespace("mydb")
create_sample_table("users", "mydb")
query_table("users", "mydb")
describe_table("users", "mydb")
export_to_pandas("users", "mydb")

# Advanced
time_travel_query("users", "mydb", version_id=1)
get_table_stats("users", "mydb")
show_spark_config()
```

---

## Storage & Data

### Data Location
- **Tables**: Stored as Parquet files in MinIO `s3a://warehouse/`
- **View in MinIO**: http://localhost:9001 → Browse `warehouse` bucket
- **Metadata**: Stored in PostgreSQL (managed by Polaris)

### Table Structure
Each Iceberg table consists of:
```
warehouse/
  └── namespace/
      └── tablename/
          ├── metadata/
          │   ├── 00000-abc123.metadata.json
          │   └── snap-xxx.avro
          └── data/
              ├── part-00000.parquet
              └── part-00001.parquet
```

---

## Stopping Services

```bash
# Stop Jupyter and Spark
docker-compose -f spark-notebook-compose.yml down

# Stop infrastructure
docker-compose down

# Full cleanup (removes data)
docker-compose down -v
docker-compose -f spark-notebook-compose.yml down -v
docker network rm dasnet
docker volume rm warehouse_storage
```

---

## Troubleshooting

### Services Won't Start
```bash
# Check logs
docker logs warehouse-polaris
docker logs warehouse-minio
docker logs spark-notebook

# Verify network exists
docker network ls | grep dasnet
```

### Can't Find Tables
```python
# Verify default catalog
print(spark.conf.get('spark.sql.defaultCatalog'))

# Check namespaces exist
spark.sql("SHOW NAMESPACES IN polaris").show()

# List tables
spark.sql("SHOW TABLES IN mydb").show()
```

### Connection to Polaris Fails
```bash
# Test from Spark container
docker exec spark-notebook curl http://polaris:8181/api/v1/catalogs

# Check Polaris health
docker logs warehouse-polaris | tail -20
```

### MinIO Not Accessible
```bash
# Test MinIO endpoint
docker exec spark-notebook curl http://minio:9000

# Check MinIO logs
docker logs warehouse-minio
```

---

## Key Features

✅ **Fully On-Premise** - All components run locally in Docker

✅ **Iceberg Tables** - Partitioning, time travel, schema evolution, ACID transactions

✅ **Default Catalog** - Use `schema.tablename` directly (polaris is default)

✅ **No Trino** - Spark is your query engine, simpler and faster

✅ **Interactive Analysis** - Jupyter notebooks with full Spark SQL support

✅ **S3-Compatible Storage** - MinIO for all data files

✅ **Metadata Management** - Polaris + PostgreSQL track all table history

✅ **No Cloud Connectivity** - Works completely offline

---

## File Structure

```
warehouse/
├── docker-compose.yml                     # Infrastructure (postgres, minio, polaris)
├── spark-notebook-compose.yml             # Spark + Jupyter with Iceberg config
├── README.md                              # This file
├── workspace/
│   ├── notebooks/
│   │   ├── iceberg_queries.ipynb         # Complete example notebook
│   │   ├── warehouse_helpers.py          # Helper functions
│   │   └── [your notebooks]
│   └── data/                             # Your data files
└── [workspace mount]
```

---

## Next Steps

1. **Run services**: `docker-compose up -d && docker-compose -f spark-notebook-compose.yml up -d`
2. **Open Jupyter**: http://localhost:8888
3. **Copy example notebook** or create your own
4. **Start querying**: `spark.sql("schema.tablename").show()`
5. **Browse data**: MinIO console at http://localhost:9001

---

## Performance Tips

- **Partition your tables** - Filter by partition for faster queries
- **Batch inserts** - Insert 1000s of rows, not one at a time
- **Monitor Spark UI** - Check http://localhost:4040 during queries
- **Use DataFrame API** - Efficient for complex transformations

---

**Your on-premise warehouse is ready! Query your data with Spark. 🚀**
