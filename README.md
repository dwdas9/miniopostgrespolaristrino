# Building Your Own Data Warehouse on Your Laptop

**Note:** This setup works on both Windows and macOS. However, every time the Polaris container restarts, a new clientID and clientSecret are generated. You'll need to:
1. Get the new credentials from Polaris logs (`docker logs warehouse-polaris 2>&1 | grep "credentials:"`)
2. Update the setup-polaris script and run it
3. Update the credentials in your Jupyter notebook


## Why Even Bother?

Most people will tell you to just use Snowflake or Databricks and call it a day. And honestly, for production workloads at scale, they're probably right. But here's the thing - if you want to actually understand how modern data warehouses work, or if you need something running completely on-prem with zero cloud dependencies, building your own setup teaches you a lot.

Plus, it's kind of fun to have your own mini data warehouse running on your laptop that does basically the same stuff as those multi-billion dollar platforms.

## What We're Building

We're putting together a proper lakehouse stack - Spark for processing and queries, Iceberg for the table format, Polaris for the catalog, and MinIO for storage. Everything runs in Docker, so you're not messing up your system, and you can blow it away anytime.

The cool part? This isn't some toy setup. The architecture is the same as what companies run in production. Just smaller.

## Haddop Hive were all good. Why this new stack?

### Why Not Hadoop?

Look, Hadoop was revolutionary back in 2006, but it's basically legacy now. HDFS is a pain to operate - you need NameNodes, DataNodes, complicated configurations, and it doesn't play well with modern cloud-native tools. More importantly, Hadoop ecosystem tools like MapReduce are way slower than Spark. MapReduce writes intermediate results to disk between every stage, which kills performance. Spark keeps everything in memory when possible.

The other issue is Hadoop assumes you're running on bare metal with local disks. That made sense 15 years ago, but modern architectures separate storage and compute. You want to scale them independently. HDFS couples them together, which is just not how people build systems anymore.

### Why Spark Over Hive?

Here's where it gets confusing because "Hive" means two different things, and people mix them up all the time.

**Hive the Query Engine** vs **Hive Metastore the Catalog** - these are separate things. When people say "use Hive," they usually mean the query engine that translates SQL to MapReduce or Tez jobs. That's what we're replacing with Spark.

Hive query engine sits on top of Hadoop and is slow. Really slow. You're waiting minutes for queries that Spark finishes in seconds. Hive also doesn't do streaming well - it's batch-first by design.

Spark gives you:
- **Speed**: In-memory processing, much faster than disk-based MapReduce
- **Unified engine**: Same tool for batch, streaming, SQL, ML - you're not learning five different systems
- **Better API**: DataFrame API is way more intuitive than writing MapReduce jobs
- **Active development**: Spark is actively maintained and improving. Hive development has basically stalled.

The performance difference isn't subtle. We're talking 10-100x faster for most workloads. That's not an exaggeration.

### Why MinIO Over HDFS?

MinIO speaks S3 API, which means every modern data tool works with it out of the box. It's simpler to operate - no NameNode HA configurations, no complicated rebalancing, no block management headaches. You just add more disks or nodes when you need capacity.

More importantly, MinIO gives you proper object storage semantics. You can use it with Iceberg, Delta Lake, Hudi - all the modern table formats. HDFS is really only for Hadoop ecosystem tools. MinIO is storage, Spark is compute - clean separation.

Also, MinIO's erasure coding is more efficient than HDFS replication. HDFS typically does 3x replication for reliability. MinIO can give you similar or better durability with less overhead.

### What Even Is a Table Format? (And Why Iceberg?)

Okay, this is important because "table format" isn't something people talked about much until recently.

**The Traditional Approach (Hive Tables)**:

In the old Hadoop world, a "table" was just:
- A directory in HDFS (like `/user/hive/warehouse/users/`)
- Bunch of Parquet or ORC files dumped in that directory
- Some metadata in Hive Metastore saying "this directory is a table with these columns"
- Maybe partitioned subdirectories like `/users/year=2024/month=11/`

That's it. Super simple, but also super problematic:

**Problems with Traditional Approach**:
- **No atomicity**: If a write fails halfway, you've got partial data and corruption
- **No isolation**: Readers see half-written data
- **Manual partition management**: You have to know partition columns and include them in WHERE clauses or you scan everything
- **Schema evolution nightmares**: Adding a column means rewriting all files or dealing with missing columns
- **Small file problem**: Lots of small files kill performance, no automatic compaction
- **No time travel**: Once data is changed, it's gone
- **Statistics are stale**: No automatic stats maintenance, query planning suffers

**What a Table Format Actually Is**:

A table format is basically a spec that defines:
1. How metadata is organized and tracked
2. How files are discovered and read
3. How transactions work
4. How schema changes are handled
5. How partitioning is managed

Think of it as the "database layer" on top of object storage. Raw Parquet files are like having database pages on disk with no transaction log, no catalog, no indexes - just bytes. A table format adds all that missing structure.

**Why Iceberg Specifically**:

Iceberg was built by Netflix to solve all those problems they hit at massive scale. Here's what makes it different:

**1. ACID Transactions**:
Every write is atomic. Iceberg uses a metadata tree structure where commits are atomic pointer swaps. If a write fails, nothing changes - no partial data, no corruption. Multiple writers can work concurrently using optimistic concurrency control.

**2. Hidden Partitioning**:
Users don't need to know about partitions. You partition by date, but queries just say `WHERE created_at = '2024-11-25'` and Iceberg automatically prunes partitions. No more `WHERE year=2024 AND month=11 AND day=25` nonsense that breaks if you change partitioning.

**3. Partition Evolution**:
You can change how a table is partitioned without rewriting data. Start with daily partitions, realize you need hourly? Just change it. Old data stays in daily partitions, new data goes into hourly. Queries work seamlessly across both.

**4. Schema Evolution Without Rewrites**:
Add, drop, rename columns - all without touching data files. Iceberg tracks schema at the metadata level. Add a column? New files include it, old files don't, Iceberg fills in NULLs automatically when reading old files.

**5. Time Travel**:
Every commit creates a snapshot. You can query any historical version: `SELECT * FROM table VERSION AS OF snapshot_id` or `SELECT * FROM table TIMESTAMP AS OF '2024-11-20'`. Amazing for debugging, auditing, or rolling back bad data.

**6. Efficient Metadata Operations**:
Iceberg's metadata tree structure means operations like listing files, computing statistics, or filtering by partitions are fast even with billions of files. Traditional Hive tables slow down massively as file counts grow.

**7. Built-in Compaction**:
Iceberg tracks file sizes and can automatically trigger compaction to merge small files. Traditional approaches need manual compaction jobs.

**The Alternatives**:

- **Delta Lake**: Built by Databricks, similar goals to Iceberg but more tied to Spark. Less engine-neutral.
- **Apache Hudi**: Built by Uber, focuses more on streaming updates and incremental processing. More complex.
- **Raw Parquet/ORC directories**: What we used to do. Works but lacks all the warehouse features.

Iceberg is the most engine-neutral (works with Spark, Flink, Trino, Presto, even Hive) and has the cleanest design. That's why it's becoming the standard.

**Real Example**:

Traditional Hive table:
```
/warehouse/users/
  ├── part1.parquet  (oops, 1KB file)
  ├── part2.parquet  (500MB file)
  ├── part3.parquet  (corrupted from failed write)
  └── year=2024/month=11/
      └── data.parquet
```

Query: You manually specify `year=2024 AND month=11` or scan everything. Files aren't tracked properly. No idea which files are valid.

Iceberg table:
```
/warehouse/users/
  ├── metadata/
  │   ├── v1.metadata.json (snapshot 1)
  │   ├── v2.metadata.json (snapshot 2)
  │   └── snap-123-manifest-list.avro
  └── data/
      ├── file1.parquet
      └── file2.parquet
```

Query: Just `WHERE created_at = '2024-11-25'`. Iceberg reads metadata, figures out exactly which files to read, which partitions to scan. Every file is tracked, every commit is atomic. Time travel works. Schema changes are tracked.

That metadata layer is the whole point. It's what makes object storage work like a real database.

### Why Polaris Over Hive Metastore?

Now back to catalogs. Remember, **Hive Metastore** is just the catalog service - the thing that stores information about what tables exist and where they are. It's separate from the Hive query engine.

Hive Metastore is the old standard, and it technically works with Iceberg, but:

- **Hadoop baggage**: Built for HDFS, lots of legacy assumptions
- **Heavyweight**: Requires extensive configuration, Thrift protocol, complicated setup
- **Limited features**: Basic catalog functionality, no multi-catalog support
- **Access control is external**: You need separate tools like Apache Ranger

Polaris is the modern replacement:
- **REST API**: Clean, simple, no Thrift
- **Lightweight**: No Hadoop dependencies
- **Multi-catalog support**: Organize tables into logical catalogs
- **Fine-grained access control**: Built in, not bolted on
- **Purpose-built for Iceberg**: Understands modern table formats natively
- **Production-grade**: Snowflake built it for their own use, then open-sourced it

Both do the same job (store catalog metadata), but Polaris does it better with modern architecture. You could use Hive Metastore if you wanted - it works - but you'd be making your life harder.

### Compatibility Concerns?

This is important - everything here uses open formats and standards. Your Parquet files can be read by any tool. Iceberg tables work with Spark, Trino, Flink, Presto, even Hive if you really need it. MinIO speaks S3 API, so anything that works with S3 works with MinIO.

You're not locked into anything. Don't like Spark later? Switch to Trino. Want to move to cloud? Point your tools at AWS S3 instead of MinIO. The table format stays the same, the data stays the same. This is the whole point of open standards.

Compare that to Hadoop ecosystem where everything is tightly coupled and proprietary configuration is everywhere.

## Why This is Bare Minimum and Sufficient

Let's break down what you actually need for a functional data warehouse and what each component does:

### The Four Essential Pieces

**1. Storage Layer (MinIO)**

You need somewhere to put the actual data files. That's it. MinIO is literally just distributed object storage. It stores your Parquet files, your Iceberg metadata files, everything. Without storage, you have nothing. This is non-negotiable.

Could you use local filesystem? Sure, for a toy. But you lose durability, can't scale across machines, and don't get enterprise features like replication. MinIO is the minimum viable storage that doesn't compromise on features.

**2. Catalog (Polaris + PostgreSQL)**

A catalog is mandatory. Something needs to answer "what tables exist?" and "where is table X's data?". Without a catalog, your query engine has no idea what tables are available or where to find them.

PostgreSQL stores the actual catalog data. Polaris is the service that manages it. Together, they're the minimum you need. You could potentially skip Polaris and use a simpler catalog like JDBC or REST, but then you lose access control and multi-catalog support. For a serious setup, Polaris is already pretty minimal.

**3. Table Format (Iceberg)**

This is what makes object storage behave like a database. Without Iceberg (or Delta/Hudi), you're just dumping Parquet files in directories and hoping for the best. No transactions, no consistency, no proper metadata management.

Iceberg is the minimum layer that gives you:
- Atomic operations (no partial writes)
- Schema tracking and evolution
- Partition management without user intervention
- Snapshot isolation and time travel
- Efficient metadata operations

Could you skip this and just use raw Parquet? Technically yes, but then you don't have a warehouse - you have a data lake with all its problems. No ACID, no schema evolution, no time travel. You'd be back to the problems we had 10 years ago. Iceberg is the minimum to call this a "warehouse."

**4. Compute Engine (Spark)**

You need something to read and write data, run queries, do transformations. Spark is actually overkill in some ways - it does ETL, streaming, ML, everything. But here's why it's still minimal:

- **One tool for everything**: You could have separate tools for ETL (NiFi), SQL (Trino), streaming (Flink), but that's more components, not fewer. Spark consolidates all of this.
- **Native Iceberg integration**: Full read/write support with ACID guarantees
- **Mature and stable**: You're not betting on experimental tech

Could you use a lighter query engine? Maybe Trino for just queries, but then you need something else for ETL and streaming. Spark handles everything in one package, which is actually more minimal from an operational perspective.

### What We're NOT Including (and Why That's Fine)

**Data Ingestion Tools (Kafka, NiFi, Airbyte)**: Not needed for the core warehouse. You can manually load data or use simple Python scripts. Ingestion tools are workflow-specific, not core architecture.

**Orchestration (Airflow)**: Scheduling and workflows are important for production, but not for the warehouse itself to function. You can run Spark jobs manually or with cron.

We are also excluding, BI Tools, Monitoring, and Security Layers.

### Why This is Actually Sufficient

This stack gives you:

✅ **Persistent storage** with durability (MinIO)
✅ **Metadata management** and catalog (Polaris/PostgreSQL)  
✅ **ACID transactions** (Iceberg)  
✅ **Schema evolution** without rewrites (Iceberg)  
✅ **Time travel** and auditing (Iceberg)  
✅ **SQL queries** (Spark SQL)  
✅ **Batch processing** (Spark)  
✅ **Streaming** (Spark Structured Streaming)  
✅ **ETL capabilities** (Spark transformations)  
✅ **Partition management** (Iceberg)  
✅ **Concurrent read/write** (Iceberg + Spark)  

That's everything you need for a functional warehouse. Could you add more tools? Sure. Would they make it more capable? Marginally. But you'd be adding operational complexity without adding core functionality.

### The Beauty of This Setup

Each component does exactly one thing:
- MinIO: stores bytes
- PostgreSQL: persists metadata
- Polaris: serves catalog API
- Iceberg: manages table metadata and ACID
- Spark: processes and queries data

There's no overlap, no redundancy. Remove any one piece and something critical breaks. That's how you know it's minimal.

And because it's all open source with standard interfaces, you can swap components later if needed. Not happy with Polaris? Try Nessie or even Hive Metastore. Want faster queries? Add Trino alongside Spark. The architecture supports evolution without forcing you to rebuild everything.

## Getting It Running

First, you need Docker installed. That's it. No other dependencies, no complicated setup.

```bash
# Create the network and storage volume (one-time thing)
docker network create dasnet
docker volume create warehouse_storage

# Start everything
docker-compose up -d
docker-compose -f spark-notebook-compose.yml up -d
```

Give it a minute to start up, then you've got:
- Jupyter notebooks at http://localhost:8888
- MinIO console at http://localhost:9001 (login: minioadmin/minioadmin)
- Spark UI at http://localhost:4040 when you're running queries

## Actually Using It

Open up Jupyter in your browser. The Spark session is already configured and ready - you just use `spark` directly. No boilerplate, no configuration hassle.

Here's how you create your first table:

```python
# Make a database (namespace in Iceberg terms)
spark.sql("CREATE NAMESPACE IF NOT EXISTS mydb")

# Create a table with partitioning
spark.sql("""
    CREATE TABLE mydb.users (
        id INT,
        name STRING,
        created_at TIMESTAMP
    )
    USING ICEBERG
    PARTITIONED BY (CAST(created_at AS DATE))
""")

# Put some data in
spark.sql("""
    INSERT INTO mydb.users VALUES
    (1, 'Alice', CURRENT_TIMESTAMP()),
    (2, 'Bob', CURRENT_TIMESTAMP())
""")

# Query it back
spark.sql("SELECT * FROM mydb.users").show()
```

That's it. You've got a working Iceberg table with partitioning, ACID transactions, the whole deal.

## What You Can Do

The pattern is simple - use `schema.tablename` for everything. List your tables with `SHOW TABLES IN mydb`. Describe a table with `DESCRIBE TABLE mydb.users`. All standard SQL stuff.

Want to do updates and deletes? Just do them:

```python
spark.sql("UPDATE mydb.users SET name='Alice2' WHERE id=1")
spark.sql("DELETE FROM mydb.users WHERE id=2")
```

This is where Iceberg shines - these operations are fast and atomic. No crazy workarounds like in traditional data lakes.

Time travel is built in. Every change creates a snapshot, so you can query old versions:

```python
spark.sql("SELECT * FROM mydb.users VERSION AS OF 0").show()
```

Schema evolution is straightforward too. Add columns, rename stuff, change types - all without rewriting data:

```python
spark.sql("ALTER TABLE mydb.users ADD COLUMN email STRING")
```

You can use the DataFrame API if you prefer that style over SQL:

```python
df = spark.table("mydb.users")
df.filter(df.id > 1).show()
df.groupBy("name").count().show()
```

## Where Everything Lives

Your actual data - the Parquet files - sits in MinIO. Open the console at localhost:9001, navigate to the warehouse bucket, and you can see the folder structure. Each table gets its own path with data and metadata directories.

The catalog metadata (what tables exist, their schemas, snapshots) is in PostgreSQL, managed by Polaris. You don't usually need to touch this directly, but it's there if you need it.

Everything persists across container restarts because of the Docker volume. Your tables and data stick around until you explicitly delete them.

## Shutting Down

When you're done:

```bash
docker-compose down
docker-compose -f spark-notebook-compose.yml down
```

This stops everything but keeps your data. If you want to completely wipe it and start fresh:

```bash
docker-compose down -v
docker-compose -f spark-notebook-compose.yml down -v
docker network rm dasnet
docker volume rm warehouse_storage
```

## What This Gets You

You've got a real lakehouse running on your machine. ACID transactions, schema evolution, time travel, partitioning - all the features you'd get from expensive cloud platforms. It runs locally, no internet needed after the initial image downloads, complete data sovereignty.

Is it going to handle petabytes? No, obviously not, it's running on your laptop. But for learning, development, small-scale analytics, or building proof-of-concepts, it's genuinely useful. And you understand exactly how everything works because you set it up yourself.

The architecture is legit. Companies run this exact stack in production, just scaled up with more nodes and better hardware. You're not learning toy versions of things - you're using the real tools.

The best part? Every component here can scale to production. MinIO runs at companies storing exabytes. Spark powers data platforms at Netflix, Uber, Airbnb. Iceberg handles billions of files at Apple and LinkedIn. When you're ready to go bigger, you're not rewriting everything - you're just adding more nodes.

Check out the `getting_started.ipynb` notebook in the workspace folder for more examples and patterns. Start there, break things, figure out how to fix them. That's how you actually learn this stuff.