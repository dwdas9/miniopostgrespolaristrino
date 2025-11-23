"""
Helper functions for Spark + Polaris + MinIO warehouse operations.
Use in Jupyter notebook cells.
"""

from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, TimestampType, DoubleType
from datetime import datetime
import pandas as pd

# Assume 'spark' session already initialized via PySpark notebook
# spark is available globally

def get_catalogs():
    """List all available catalogs"""
    return spark.sql("SHOW CATALOGS").collect()

def get_namespaces(catalog="polaris"):
    """List all namespaces in a catalog"""
    return spark.sql(f"SHOW NAMESPACES IN {catalog}").collect()

def get_tables(namespace, catalog="polaris"):
    """List all tables in a namespace"""
    full_name = f"{catalog}.{namespace}"
    return spark.sql(f"SHOW TABLES IN {full_name}").collect()

def create_namespace(namespace_name, catalog="polaris"):
    """Create a new namespace (schema)"""
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {catalog}.{namespace_name}")
    print(f"✓ Created namespace: {catalog}.{namespace_name}")

def drop_namespace(namespace_name, catalog="polaris"):
    """Drop a namespace (schema)"""
    spark.sql(f"DROP NAMESPACE IF EXISTS {catalog}.{namespace_name} CASCADE")
    print(f"✓ Dropped namespace: {catalog}.{namespace_name}")

def create_sample_table(table_name, namespace, catalog="polaris"):
    """Create a sample users table for testing"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS {full_name} (
            id INT,
            name STRING,
            email STRING,
            created_at TIMESTAMP
        )
        USING ICEBERG
        PARTITIONED BY (CAST(created_at AS DATE))
    """)
    print(f"✓ Created table: {full_name}")

def insert_sample_data(table_name, namespace, catalog="polaris"):
    """Insert sample data into a table"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    spark.sql(f"""
        INSERT INTO {full_name} VALUES
        (1, 'Alice', 'alice@example.com', CAST('2025-01-01 10:00:00' AS TIMESTAMP)),
        (2, 'Bob', 'bob@example.com', CAST('2025-01-02 11:00:00' AS TIMESTAMP)),
        (3, 'Charlie', 'charlie@example.com', CAST('2025-01-03 12:00:00' AS TIMESTAMP)),
        (4, 'Diana', 'diana@example.com', CAST('2025-01-04 13:00:00' AS TIMESTAMP))
    """)
    print(f"✓ Inserted 4 rows into {full_name}")

def describe_table(table_name, namespace, catalog="polaris"):
    """Show table schema"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    print(f"\n=== Schema for {full_name} ===")
    spark.sql(f"DESCRIBE TABLE {full_name}").show(truncate=False)

def query_table(table_name, namespace, filter_sql="", catalog="polaris"):
    """Query a table with optional filter"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    if filter_sql:
        sql = f"SELECT * FROM {full_name} WHERE {filter_sql}"
    else:
        sql = f"SELECT * FROM {full_name}"
    return spark.sql(sql)

def get_table_stats(table_name, namespace, catalog="polaris"):
    """Show table statistics"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    print(f"\n=== Statistics for {full_name} ===")
    
    # Row count
    count = spark.sql(f"SELECT COUNT(*) as row_count FROM {full_name}").collect()[0][0]
    print(f"Row count: {count}")
    
    # Table history
    print(f"\nTable history:")
    spark.sql(f"SELECT * FROM {full_name}.history").show(truncate=False)

def view_table_metadata(table_name, namespace, catalog="polaris"):
    """View table properties and metadata"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    print(f"\n=== Metadata for {full_name} ===")
    spark.sql(f"SHOW TBLPROPERTIES {full_name}").show(truncate=False)

def drop_table(table_name, namespace, catalog="polaris"):
    """Drop a table"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    spark.sql(f"DROP TABLE IF EXISTS {full_name}")
    print(f"✓ Dropped table: {full_name}")

def create_parquet_from_dataframe(df, table_name, namespace, catalog="polaris"):
    """Create Iceberg table from a Spark DataFrame"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    df.write \
        .format("iceberg") \
        .mode("overwrite") \
        .option("path", f"s3a://warehouse/{namespace}/{table_name}") \
        .saveAsTable(full_name)
    print(f"✓ Created {full_name} from DataFrame")

def export_to_pandas(table_name, namespace, catalog="polaris"):
    """Export table to Pandas DataFrame"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    df = spark.sql(f"SELECT * FROM {full_name}")
    return df.toPandas()

def show_spark_config():
    """Display Spark configuration"""
    print("\n=== Spark Configuration ===")
    print(f"Default Catalog: {spark.conf.get('spark.sql.defaultCatalog')}")
    print(f"Polaris URI: {spark.conf.get('spark.sql.catalog.polaris.uri')}")
    print(f"Warehouse Path: {spark.conf.get('spark.sql.catalog.polaris.warehouse')}")
    print(f"S3 Endpoint: {spark.conf.get('spark.hadoop.fs.s3a.endpoint')}")
    print(f"S3 Path Style: {spark.conf.get('spark.hadoop.fs.s3a.path.style.access')}")

def time_travel_query(table_name, namespace, version_id=None, timestamp=None, catalog="polaris"):
    """Query a specific version of table (time travel)"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    
    if version_id:
        sql = f"SELECT * FROM {full_name} VERSION AS OF {version_id}"
    elif timestamp:
        sql = f"SELECT * FROM {full_name} TIMESTAMP AS OF '{timestamp}'"
    else:
        raise ValueError("Provide either version_id or timestamp")
    
    return spark.sql(sql)

def compact_table(table_name, namespace, catalog="polaris"):
    """Compact small Iceberg files for better performance"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    spark.sql(f"ALTER TABLE {full_name} COMPACT")
    print(f"✓ Compacted table: {full_name}")

def get_table_history(table_name, namespace, catalog="polaris"):
    """Get full history of table changes"""
    full_name = f"{catalog}.{namespace}.{table_name}"
    print(f"\n=== History for {full_name} ===")
    return spark.sql(f"SELECT * FROM {full_name}.history")

# ============================================================================
# Quick setup function - creates demo warehouse
# ============================================================================

def setup_demo_warehouse():
    """
    One-line setup for demo environment.
    Creates namespace and sample tables.
    """
    namespace = "demo"
    
    print("Setting up demo warehouse...\n")
    
    # Create namespace
    create_namespace(namespace)
    
    # Create tables
    create_sample_table("users", namespace)
    create_sample_table("orders", namespace)
    
    # Insert sample data
    insert_sample_data("users", namespace)
    
    # Insert order data
    spark.sql(f"""
        INSERT INTO polaris.{namespace}.orders VALUES
        (101, 1, 150.50, CAST('2025-01-10 08:00:00' AS TIMESTAMP)),
        (102, 2, 200.00, CAST('2025-01-11 09:00:00' AS TIMESTAMP)),
        (103, 1, 75.25, CAST('2025-01-12 10:00:00' AS TIMESTAMP)),
        (104, 3, 300.00, CAST('2025-01-13 11:00:00' AS TIMESTAMP))
    """)
    print(f"✓ Inserted sample order data")
    
    print("\n✓ Demo warehouse ready!")
    print(f"\nStart querying:")
    print(f"  spark.sql('SELECT * FROM {namespace}.users').show()")
    print(f"  spark.sql('SELECT * FROM {namespace}.orders').show()")

# ============================================================================
# Usage examples (paste into Jupyter cells)
# ============================================================================

"""
# Example 1: Setup demo
setup_demo_warehouse()

# Example 2: Query tables
spark.sql("SELECT * FROM demo.users WHERE id > 2").show()

# Example 3: Join tables
spark.sql('''
    SELECT u.name, o.order_id, o.amount
    FROM demo.users u
    JOIN demo.orders o ON u.id = o.user_id
''').show()

# Example 4: Time travel
time_travel_query("users", "demo", version_id=1)

# Example 5: Get stats
get_table_stats("users", "demo")

# Example 6: Export to Pandas
df_pandas = export_to_pandas("users", "demo")
print(df_pandas)

# Example 7: Show configuration
show_spark_config()

# Example 8: List all tables
catalogs = get_catalogs()
print("Catalogs:", catalogs)

for cat in catalogs:
    namespaces = get_namespaces(cat.namespace)
    print(f"Namespaces in {cat.namespace}:", namespaces)
"""
