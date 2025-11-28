# Setting This Up on Mac (Apple Silicon)

So you've got an M1/M2/M3 Mac and want to run this locally. Good news - it works. There are a few quirks with ARM64 architecture, but nothing crazy.

## Before You Start

You need Docker Desktop for Mac. Not the Intel version - the Apple Silicon version. Go to docker.com, download it, make sure you pick "Apple Silicon" when it asks. If you accidentally got the Intel version, it'll still work through Rosetta emulation, but it'll be slower and hotter.

Once Docker's installed, bump up the resources a bit. Open Docker Desktop → Settings → Resources. Give it at least 8GB RAM (10-12GB is better for Spark), 4 CPUs. The default 2GB RAM will make Spark cry.

## Getting Everything Running

First time setup - create the network and volume:

```bash
docker network create dasnet
docker volume create warehouse_storage
```

Start the infrastructure (Postgres, MinIO, Polaris):

```bash
docker-compose up -d
```

Wait about 30 seconds. Polaris needs time to initialize and connect to Postgres. You can check if everything's healthy:

```bash
docker ps
```

You should see three containers running - warehouse-postgres, warehouse-minio, warehouse-polaris.

Now the important part - **get the Polaris credentials**. These change every time Polaris restarts:

```bash
docker logs warehouse-polaris 2>&1 | grep "credentials:"
```

You'll see something like:
```
realm: POLARIS root principal credentials: a78cf5b1274db27a:aac273037efbfd31ae9b285c7eb206a1
```

That first part before the colon is your client ID, the second part is your secret. Write these down.

## Create the MinIO Bucket

This is the part that trips everyone up. MinIO starts empty - no buckets. But Polaris is configured to store data in `s3://warehouse/`. You need to create that bucket manually.

Open http://localhost:9001 in your browser. Login with `minioadmin` / `minioadmin`. Click "Create Bucket", name it `warehouse`, done.

Skip this step and you'll get a 404 error when you try to create tables. Ask me how I know.

## Set Up the Polaris Catalog

Edit the setup script with your credentials:

```bash
nano setup-polaris.sh  # or vim, or whatever
```

Find these lines and update them:
```bash
CLIENT_ID="your-client-id-here"
CLIENT_SECRET="your-client-secret-here"
```

Then run it:

```bash
./setup-polaris.sh
```

If it says "Catalog created!" you're good. If it fails with a 401 error, your credentials are wrong - go get fresh ones from the Polaris logs.

## Start Jupyter

Now bring up the Spark notebook:

```bash
docker-compose -f spark-notebook-compose.yml up -d
```

This pulls the `jupyter/all-spark-notebook` image which is about 4GB. First time takes a few minutes depending on your internet.

Once it's up, open http://localhost:8888 in your browser. You should see JupyterLab.

## Update the Notebook Credentials

Navigate to `work/getting_started.ipynb`. Before running anything, find this line:

```python
.config("spark.sql.catalog.polaris.credential", "old-id:old-secret")
```

Replace it with your actual credentials from earlier:

```python
.config("spark.sql.catalog.polaris.credential", "your-id:your-secret")
```

Now run the first cell. First time takes 2-3 minutes because Spark downloads a bunch of JARs from Maven Central. Grab a coffee.

If you see tables being created and data being queried - you're done. It works.

## The Mac-Specific Gotchas

### Docker Desktop Memory

Spark is memory hungry. If you see "Container killed" or weird Java heap errors, you need more RAM allocated in Docker Desktop. 8GB minimum, 12GB recommended.

### host.docker.internal

On Mac, containers can't reach `localhost` on your host machine directly. The magic hostname `host.docker.internal` bridges that gap. That's why the Polaris URI in the Spark config uses:

```python
.config("spark.sql.catalog.polaris.uri", "http://host.docker.internal:8181/api/catalog")
```

This works on Mac and Windows. On Linux you'd need to do something different (usually `--network host`), but that's a Linux problem.

### File Permissions in Mounted Volumes

Sometimes you'll see permission errors when Jupyter tries to save notebooks. That's because the container runs as user `jovyan` (uid 1000) but your Mac files are owned by your user.

Quick fix - from the workspace directory:
```bash
chmod -R 777 workspace/
```

Not the most secure thing, but for local development it's fine.

### Container Architecture

All the images we use are multi-arch - they have ARM64 versions. Docker pulls the right one automatically. You don't need to add any platform flags or anything special.

If you're using an older image that doesn't have ARM64, Docker will emulate x86 through Rosetta. Works, but slower. Stick with the images in our compose files and you're fine.

## Quick Reference

| Service | URL | Credentials |
|---------|-----|-------------|
| Jupyter | http://localhost:8888 | none |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| Spark UI | http://localhost:4040 | none (only when queries running) |
| Polaris API | http://localhost:8181 | from setup script |

## Something Broke?

### "Bucket does not exist" error
You forgot to create the `warehouse` bucket in MinIO. Go to http://localhost:9001 and create it.

### "401 Unauthorized" from Polaris
Your credentials expired because Polaris restarted. Get new ones:
```bash
docker logs warehouse-polaris 2>&1 | grep "credentials:"
```
Update your setup script and notebook, re-run the setup script.

### Spark session hangs forever
Usually means Polaris isn't reachable. Check if containers are running:
```bash
docker ps
```
If warehouse-polaris isn't there, bring up the infrastructure again.

### "Connection refused" errors
Docker network issue. Make sure all containers are on the same network:
```bash
docker network inspect dasnet
```
You should see all four containers listed.

### Out of memory / container killed
Docker Desktop needs more RAM. Settings → Resources → bump Memory to 10-12GB.

## Starting Fresh

If you want to nuke everything and start over:

```bash
docker-compose down -v
docker-compose -f spark-notebook-compose.yml down -v
docker network rm dasnet
docker volume rm warehouse_storage
```

Then start from the beginning of this guide. Your data will be gone, but sometimes that's what you need.

## That's It

You've got a working data warehouse on your Mac. MinIO for storage, Polaris for the catalog, Spark for queries, Iceberg for the table format. Same architecture the big companies use, just smaller.

Go create some tables, load some data, run some queries. Break things and figure out how to fix them. That's how you learn.
