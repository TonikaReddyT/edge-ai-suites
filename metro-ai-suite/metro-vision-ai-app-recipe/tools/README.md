# Smart Intersection Backup and Restore Tools

This directory contains shell scripts to backup and restore the Smart Intersection deployment from the metro-vision-ai-app-recipe.

## Quick Start

```bash
# Create a backup
./tools/save_restore.sh backup [output_file]

# Restore from backup
./tools/save_restore.sh restore <backup_archive> [target_directory]
```

## Tools Overview

- **`tools/save_restore.sh`** - **UNIFIED TOOL** - Creates backups and restores deployments

The backup includes:

- All Docker images (9 total)
- All Docker volumes (16 total)
- Configuration files (docker-compose.yml, .env, smart-intersection/)
- **Embedded restore script** (self-contained restoration)

## Requirements

- Docker Engine
- Docker Compose (`docker-compose` or `docker compose`)
- Sufficient disk space for backup files

## Main Script

### save_restore.sh

Unified tool that provides both backup and restore functionality with simplified commands.

**Usage:**

```bash
# Create a backup
./save_restore.sh backup [output_file]

# Restore from backup
./save_restore.sh restore <backup_archive> [target_directory]

# Show help
./save_restore.sh --help
```

**Backup Features:**

- Backs up all Docker images used by the deployment
- Exports all Docker volumes with data
- Copies all configuration files (.env, docker-compose.yml, smart-intersection directory)
- Creates an automated restore script
- Packages everything into a single tar.gz archive

**Restore Features:**

- Extracts and validates backup archive
- Loads Docker images
- Restores Docker volumes
- Copies configuration files
- Starts the deployment automatically

**Examples:**

```bash
# Create backup with default filename
./save_restore.sh backup

# Create backup with custom filename
./save_restore.sh backup my_backup.tar.gz

# Restore using this tool
./save_restore.sh restore smart_intersection_backup_20250930_143022.tar.gz

# Restore to specific directory
./save_restore.sh restore backup.tar.gz /opt/smart-intersection

# OR use the embedded restore script (after extracting)
tar -xzf smart_intersection_backup_20250930_143022.tar.gz
cd smart_intersection_backup
./restore.sh [target_directory]
```

## What Gets Backed Up

The backup includes:

1. **Docker Images:**
   - `docker.io/dockurr/chrony:4.6.1`
   - `docker.io/library/eclipse-mosquitto:2.0.21`
   - `docker.io/nodered/node-red:4.0`
   - `docker.io/library/influxdb:2.7.11`
   - `docker.io/grafana/grafana:11.6.0`
   - `intel/dlstreamer-pipeline-server:3.1.0-ubuntu24`
   - `docker.io/intel/scenescape-manager:v1.4.0`
   - `docker.io/intel/scenescape-controller:v1.4.0`

2. **Docker Volumes:**
   - `influxdb2-data`
   - `influxdb2-config`
   - `grafana-storage`
   - `pgserver-db`
   - `pgserver-migrations`
   - `pgserver-media`
   - `dlstreamer-pipeline-server-pipeline-root`
   - `dlstreamer-pipeline-server-tmp`

3. **Configuration Files:**
   - `docker-compose.yml`
   - `.env` (with automatic HOST_IP update during restore)
   - Complete `smart-intersection/` directory with all configs and secrets

## Requirements

### For Backup:

- Docker running on the source system
- Sufficient disk space for the backup file
- Read access to the deployment directory

### For Restore:

- Docker Engine
- Docker Compose (`docker-compose` or `docker compose`)
- Sufficient disk space for images and volumes
- Network access (if images need to be pulled)

## Backup Process

The backup script performs these steps:

1. **Prerequisites Check:** Verifies Docker is running and required files exist
2. **Image Discovery:** Parses docker-compose.yml to find all Docker images
3. **Volume Discovery:** Extracts named volume definitions
4. **Image Backup:** Pulls and saves each Docker image to tar files
5. **Volume Backup:** Uses temporary containers to backup volume data
6. **File Copy:** Copies all configuration files and directories
7. **Script Creation:** Generates an embedded restore script with the backup
8. **Archive Creation:** Packages everything into a compressed archive

## Restore Process

You can restore a backup using two methods:

### Method 1: Using the save_restore.sh tool

```bash
./save_restore.sh restore backup_file.tar.gz [target_directory]
```

### Method 2: Using the embedded restore script

```bash
tar -xzf backup_file.tar.gz
cd smart_intersection_backup
./restore.sh [target_directory]
```

Both methods perform these steps:

1. **Prerequisites Check:** Verifies Docker and Docker Compose availability
2. **Configuration Restore:** Copies config files to target directory
3. **HOST_IP Update:** Automatically updates the HOST_IP in .env to match target system
4. **Image Loading:** Loads Docker images from backup files
5. **Volume Restoration:** Recreates and restores volume data
6. **Deployment Start:** Stops existing deployment and starts restored one

## File Structure

After extraction, the backup contains:

```
smart_intersection_backup/
├── backup_info.json          # Backup metadata
├── README.md                 # Documentation
├── restore.sh               # Embedded restore script
├── image_list.txt           # List of Docker images
├── volume_list.txt          # List of Docker volumes
├── config/                  # Configuration files
│   ├── docker-compose.yml
│   ├── .env
│   └── smart-intersection/
├── images/                  # Docker image tar files
│   ├── docker.io_library_eclipse-mosquitto_2.0.21.tar
│   ├── docker.io_grafana_grafana_11.6.0.tar
│   └── ...
└── volumes/                 # Volume backup files
    ├── influxdb2-data.tar.gz
    ├── grafana-storage.tar.gz
    └── ...
```

## Tips

1. **Backup Size:** The backup file can be large (several GB) due to Docker images and volume data.

2. **Network Requirements:** If the target system cannot access Docker Hub, ensure all images are included in the backup.

3. **Storage Cleanup:** The backup process may require significant temporary disk space during creation.

4. **Testing:** Always test restore on a non-production system first.

5. **Regular Backups:** Consider automating backups with cron for production deployments.

6. **HOST_IP Updates:** The restore process automatically updates the HOST_IP in .env to match the target system's IP address. If this fails, you can manually edit .env after restoration.

## Troubleshooting

### Common Issues:

1. **Docker not running:** Ensure Docker service is started
2. **Permission denied:** Run scripts with appropriate permissions
3. **Insufficient space:** Check available disk space before backup/restore
4. **Network issues:** Ensure Docker Hub access for image pulls
5. **Port conflicts:** Stop conflicting services before restore
6. **Missing .env file:** The restore process automatically places .env in the same directory as docker-compose.yml

### Logs:

Check Docker Compose logs if deployment fails:

```bash
docker-compose logs
# or
docker compose logs
```

### Manual Cleanup:

If restore fails, you can manually clean up:

```bash
docker-compose down --remove-orphans
docker system prune -f
```
