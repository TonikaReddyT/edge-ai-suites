#!/bin/bash
#
# Smart Intersection Backup and Restore Tool
#
# This unified script can create backups and restore Smart Intersection deployments
# Usage: 
#   ./save_restore.sh backup [output_file]
#   ./save_restore.sh restore <backup_archive> [target_directory]
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Smart Intersection Backup and Restore Tool"
    echo
    echo "Usage:"
    echo "  $0 backup [output_file]                    # Create a backup"
    echo "  $0 restore <backup_archive> [target_dir]  # Restore from backup"
    echo "  $0 --help                                  # Show this help"
    echo
    echo "Backup Mode:"
    echo "  Creates a complete backup of the Smart Intersection deployment"
    echo "  Arguments:"
    echo "    output_file    Optional output filename (default: smart_intersection_backup_TIMESTAMP.tar.gz)"
    echo
    echo "  Examples:"
    echo "    $0 backup"
    echo "    $0 backup my_custom_backup.tar.gz"
    echo
    echo "Restore Mode:"
    echo "  Restores a Smart Intersection deployment from a backup archive"
    echo "  Arguments:"
    echo "    backup_archive   Path to the backup tar.gz file"
    echo "    target_dir       Optional target directory (default: current directory)"
    echo
    echo "  Examples:"
    echo "    $0 restore smart_intersection_backup_20250930_143022.tar.gz"
    echo "    $0 restore backup.tar.gz /opt/smart-intersection"
    echo
}

# Function to cleanup on exit
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        print_info "Cleaning up temporary directory..."
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# ========================= BACKUP FUNCTIONS =========================

# Function to check backup prerequisites
check_backup_prerequisites() {
    print_info "Checking backup prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running or not accessible"
        exit 1
    fi
    
    # Check if docker-compose.yml exists
    if [ ! -f "${PROJECT_DIR}/docker-compose.yml" ]; then
        print_error "docker-compose.yml not found in ${PROJECT_DIR}"
        exit 1
    fi
    
    # Check if smart-intersection directory exists
    if [ ! -d "${PROJECT_DIR}/smart-intersection" ]; then
        print_error "smart-intersection directory not found in ${PROJECT_DIR}"
        exit 1
    fi
    
    # Check if .env file exists and warn if missing
    if [ ! -f "${PROJECT_DIR}/.env" ]; then
        print_warning ".env file not found - backup will proceed but deployment may not work without it"
    fi
    
    print_success "Backup prerequisites check passed"
}

# Function to extract Docker images from docker-compose.yml
extract_docker_images() {
    print_info "Extracting Docker images from docker-compose.yml..."
    
    # Use grep and awk to extract image names from docker-compose.yml
    grep -E "^\s*image:\s" "${PROJECT_DIR}/docker-compose.yml" | \
        awk '{print $2}' | \
        sort | uniq > "${BACKUP_DIR}/image_list.txt"
    
    local image_count=$(wc -l < "${BACKUP_DIR}/image_list.txt")
    print_info "Found ${image_count} Docker images"
    
    while IFS= read -r image; do
        echo "  - $image"
    done < "${BACKUP_DIR}/image_list.txt"
}

# Function to extract Docker volumes from docker-compose.yml
extract_docker_volumes() {
    print_info "Extracting Docker volumes from docker-compose.yml..."
    
    # Extract named volumes from the volumes section
    awk '
        /^volumes:/ { in_volumes=1; next }
        in_volumes && /^[[:space:]]*$/ { next }
        in_volumes && /^[a-zA-Z]/ && !/^[[:space:]]/ { in_volumes=0 }
        in_volumes && /^[[:space:]]*[a-zA-Z0-9_-]+:/ {
            gsub(/:.*/, "", $1)
            gsub(/^[[:space:]]*/, "", $1)
            print $1
        }
    ' "${PROJECT_DIR}/docker-compose.yml" | sort | uniq > "${BACKUP_DIR}/volume_list.txt"
    
    local volume_count=$(wc -l < "${BACKUP_DIR}/volume_list.txt")
    print_info "Found ${volume_count} Docker volumes"
    
    while IFS= read -r volume; do
        echo "  - $volume"
    done < "${BACKUP_DIR}/volume_list.txt"
}

# Function to save Docker images
save_docker_images() {
    print_info "Saving Docker images..."
    
    mkdir -p "${BACKUP_DIR}/images"
    
    while IFS= read -r image; do
        if [ -n "$image" ]; then
            print_info "  Saving $image..."
            
            # Create safe filename
            safe_name=$(echo "$image" | sed 's/[\/:]/_/g').tar
            
            # Pull and save the image
            if docker pull "$image" >/dev/null 2>&1; then
                if docker save -o "${BACKUP_DIR}/images/${safe_name}" "$image" 2>/dev/null; then
                    print_success "    Saved to ${safe_name}"
                else
                    print_warning "    Failed to save $image"
                fi
            else
                print_warning "    Failed to pull $image"
            fi
        fi
    done < "${BACKUP_DIR}/image_list.txt"
}

# Function to backup Docker volumes
backup_docker_volumes() {
    print_info "Backing up Docker volumes..."
    
    mkdir -p "${BACKUP_DIR}/volumes"
    
    while IFS= read -r volume; do
        if [ -n "$volume" ]; then
            print_info "  Backing up volume $volume..."
            
            # Check if volume exists
            if docker volume inspect "$volume" >/dev/null 2>&1; then
                # Backup the volume using a temporary container
                if docker run --rm \
                    -v "${volume}:/backup-source" \
                    -v "${BACKUP_DIR}/volumes:/backup-dest" \
                    docker.io/library/alpine:latest \
                    tar czf "/backup-dest/${volume}.tar.gz" -C "/backup-source" . 2>/dev/null; then
                    print_success "    Backed up to ${volume}.tar.gz"
                else
                    print_warning "    Failed to backup volume $volume"
                fi
            else
                print_warning "    Volume $volume does not exist"
            fi
        fi
    done < "${BACKUP_DIR}/volume_list.txt"
}

# Function to copy configuration files
copy_configuration_files() {
    print_info "Copying configuration files..."
    
    mkdir -p "${BACKUP_DIR}/config"
    
    # Copy docker-compose.yml
    cp "${PROJECT_DIR}/docker-compose.yml" "${BACKUP_DIR}/config/"
    print_success "  Copied docker-compose.yml"
    
    # Copy .env file (required for deployment)
    if [ -f "${PROJECT_DIR}/.env" ]; then
        cp "${PROJECT_DIR}/.env" "${BACKUP_DIR}/config/"
        print_success "  Copied .env"
    else
        print_warning "  .env file not found - deployment may not work properly without it"
    fi
    
    # Copy smart-intersection directory
    cp -r "${PROJECT_DIR}/smart-intersection" "${BACKUP_DIR}/config/"
    print_success "  Copied smart-intersection directory"
}

# Function to create backup info
create_backup_info() {
    print_info "Creating backup information file..."
    
    cat > "${BACKUP_DIR}/backup_info.json" << EOF
{
  "backup_date": "$(date -Iseconds)",
  "backup_version": "1.0",
  "deployment": "smart-intersection",
  "script_version": "1.0",
  "created_by": "$(whoami)@$(hostname)",
  "source_directory": "${PROJECT_DIR}",
  "files": [
    "docker-compose.yml",
    ".env",
    "smart-intersection/"
  ]
}
EOF
    
    print_success "  Created backup_info.json"
}

# Function to create embedded restore script
create_restore_script() {
    print_info "Creating embedded restore script..."
    
    cat > "${BACKUP_DIR}/restore.sh" << 'EOF'
#!/bin/bash
#
# Embedded Smart Intersection Restore Script
# This script is automatically generated and packaged with the backup
#

set -e

# Get the directory where this script is located (the extracted backup directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$(pwd)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Embedded Smart Intersection Restore Script"
    echo
    echo "Usage: $0 [target_directory]"
    echo
    echo "Arguments:"
    echo "  target_directory   Optional target directory (default: current directory)"
    echo
    echo "Examples:"
    echo "  $0                           # Restore to current directory"
    echo "  $0 /opt/smart-intersection   # Restore to specific directory"
    echo
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running or not accessible"
        exit 1
    fi
    
    # Check if docker-compose is available
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        print_error "docker-compose or 'docker compose' is not available"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
    print_info "Using compose command: $COMPOSE_CMD"
}

# Function to restore configuration files
restore_configuration() {
    print_info "Restoring configuration files..."
    
    # Create target directory if it doesn't exist
    mkdir -p "$TARGET_DIR"
    
    if [ -d "$SCRIPT_DIR/config" ]; then
        cp -r "$SCRIPT_DIR/config/." "$TARGET_DIR/"
        print_success "Configuration files restored to: $TARGET_DIR"
        
        # Update HOST_IP in .env file if it exists
        update_host_ip_in_env
    else
        print_error "Configuration files not found in backup"
        exit 1
    fi
}

# Function to update HOST_IP in .env file
update_host_ip_in_env() {
    local env_file="$TARGET_DIR/.env"
    
    if [ -f "$env_file" ]; then
        # Get the current system's IP address
        local current_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
        
        if [ "$current_ip" != "localhost" ] && [ -n "$current_ip" ]; then
            print_info "Updating HOST_IP in .env file to: $current_ip"
            
            # Update HOST_IP in .env file using sed
            if sed -i.bak "s/^HOST_IP=.*/HOST_IP=$current_ip/" "$env_file" 2>/dev/null; then
                print_success "  Updated HOST_IP to $current_ip"
                rm -f "$env_file.bak" 2>/dev/null
            else
                print_warning "  Failed to update HOST_IP in .env file"
            fi
        else
            print_warning "  Could not determine system IP address, HOST_IP not updated"
        fi
    else
        print_warning "  .env file not found, skipping HOST_IP update"
    fi
}

# Function to load Docker images
load_docker_images() {
    print_info "Loading Docker images..."
    
    if [ -f "$SCRIPT_DIR/image_list.txt" ]; then
        while IFS= read -r image; do
            if [ -n "$image" ]; then
                local safe_name=$(echo "$image" | sed 's/[\/:]/_/g').tar
                if [ -f "$SCRIPT_DIR/images/$safe_name" ]; then
                    print_info "  Loading $image..."
                    if docker load -i "$SCRIPT_DIR/images/$safe_name" >/dev/null 2>&1; then
                        print_success "    Loaded $image"
                    else
                        print_warning "    Failed to load $image"
                    fi
                else
                    print_warning "  Image file $safe_name not found, attempting to pull..."
                    docker pull "$image" 2>/dev/null || print_warning "    Failed to pull $image"
                fi
            fi
        done < "$SCRIPT_DIR/image_list.txt"
    else
        print_warning "Image list not found in backup"
    fi
}

# Function to restore Docker volumes
restore_docker_volumes() {
    print_info "Restoring Docker volumes..."
    
    if [ -f "$SCRIPT_DIR/volume_list.txt" ]; then
        while IFS= read -r volume; do
            if [ -n "$volume" ] && [ -f "$SCRIPT_DIR/volumes/$volume.tar.gz" ]; then
                print_info "  Restoring volume $volume..."
                
                # Create the volume if it doesn't exist
                docker volume create "$volume" >/dev/null 2>&1 || true
                
                # Restore the volume content
                if docker run --rm \
                    -v "$volume:/restore-dest" \
                    -v "$SCRIPT_DIR/volumes:/backup-source" \
                    docker.io/library/alpine:latest \
                    sh -c "cd /restore-dest && tar xzf /backup-source/$volume.tar.gz" 2>/dev/null; then
                    print_success "    Restored volume $volume"
                else
                    print_warning "    Failed to restore volume $volume"
                fi
            fi
        done < "$SCRIPT_DIR/volume_list.txt"
    else
        print_warning "Volume list not found in backup"
    fi
}

# Function to start deployment
start_deployment() {
    print_info "Starting the deployment..."
    
    cd "$TARGET_DIR"
    
    # Stop any existing deployment
    print_info "Stopping any existing deployment..."
    $COMPOSE_CMD down --remove-orphans 2>/dev/null || true
    
    # Start the deployment
    print_info "Starting services..."
    if $COMPOSE_CMD up -d; then
        print_success "Deployment started successfully!"
        
        # Show status
        echo
        print_info "Deployment status:"
        $COMPOSE_CMD ps
        
        return 0
    else
        print_error "Failed to start the deployment"
        return 1
    fi
}

# Function to display backup info
show_backup_info() {
    if [ -f "$SCRIPT_DIR/backup_info.json" ]; then
        print_info "Backup Information:"
        if command -v jq >/dev/null 2>&1; then
            jq -r '
                "  Backup Date: " + .backup_date,
                "  Deployment: " + .deployment,
                "  Created by: " + (.created_by // "unknown")
            ' "$SCRIPT_DIR/backup_info.json"
        else
            grep -E '"backup_date"|"deployment"|"created_by"' "$SCRIPT_DIR/backup_info.json" | \
                sed 's/^[[:space:]]*/  /' | sed 's/,$//'
        fi
        echo
    fi
}

# Main function
main() {
    echo "=============================================="
    echo "Smart Intersection Restore"
    echo "=============================================="
    echo "Target directory: $TARGET_DIR"
    echo
    
    # Run restore steps
    check_prerequisites
    show_backup_info
    restore_configuration
    load_docker_images
    restore_docker_volumes
    
    if start_deployment; then
        echo
        echo "=============================================="
        echo "Restoration completed successfully!"
        echo "=============================================="
        echo
        echo "The Smart Intersection deployment is now running."
        echo "You can check the status with: $COMPOSE_CMD ps"
        
        # Try to get the host IP
        local host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
        echo "Access the web interface at: https://${host_ip}:443"
        echo
    else
        echo
        echo "=============================================="
        echo "Restoration failed!"
        echo "=============================================="
        echo
        echo "Please check the error messages above and try again."
        echo "You can also check the logs with: $COMPOSE_CMD logs"
        echo
        exit 1
    fi
}

# Show usage if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Run main function
main
EOF

    # Make the restore script executable
    chmod +x "${BACKUP_DIR}/restore.sh"
    
    print_success "  Created embedded restore.sh script"
}

# Function to create the final backup archive
create_backup_archive() {
    print_info "Creating final backup archive..."
    
    # Create the tar.gz archive
    cd "$TEMP_DIR"
    tar -czf "${PROJECT_DIR}/${OUTPUT_FILE}" smart_intersection_backup/
    
    # Get file size
    local size_bytes=$(stat -f%z "${PROJECT_DIR}/${OUTPUT_FILE}" 2>/dev/null || stat -c%s "${PROJECT_DIR}/${OUTPUT_FILE}")
    local size_mb=$((size_bytes / 1024 / 1024))
    
    print_success "Backup created: ${OUTPUT_FILE} (${size_mb} MB)"
}

# Main backup function
do_backup() {
    local output_file="${1:-smart_intersection_backup_${TIMESTAMP}.tar.gz}"
    OUTPUT_FILE="$output_file"
    
    echo "=============================================="
    echo "Smart Intersection Backup"
    echo "=============================================="
    echo "Output file: $OUTPUT_FILE"
    echo "Project directory: $PROJECT_DIR"
    echo
    
    # Create temporary directory for backup files
    TEMP_DIR=$(mktemp -d)
    BACKUP_DIR="${TEMP_DIR}/smart_intersection_backup"
    mkdir -p "$BACKUP_DIR"
    
    # Run backup steps
    check_backup_prerequisites
    extract_docker_images
    extract_docker_volumes
    save_docker_images
    backup_docker_volumes
    copy_configuration_files
    create_backup_info
    create_restore_script
    create_backup_archive
    
    echo
    echo "=============================================="
    echo "Backup completed successfully!"
    echo "=============================================="
    echo
    echo "To restore on a target system, you have two options:"
    echo
    echo "Option 1 - Use the embedded restore script:"
    echo "  1. Extract: tar -xzf $OUTPUT_FILE"
    echo "  2. Restore: cd smart_intersection_backup && ./restore.sh [target_dir]"
    echo
    echo "Option 2 - Use this tool directly:"
    echo "  $0 restore $OUTPUT_FILE [target_dir]"
    echo
}

# ========================= RESTORE FUNCTIONS =========================

# Function to check restore prerequisites
check_restore_prerequisites() {
    local backup_archive="$1"
    
    print_info "Checking restore prerequisites..."
    
    # Check if backup archive is provided
    if [ -z "$backup_archive" ]; then
        print_error "No backup archive specified"
        show_usage
        exit 1
    fi
    
    # Check if backup archive exists
    if [ ! -f "$backup_archive" ]; then
        print_error "Backup archive not found: $backup_archive"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running or not accessible"
        exit 1
    fi
    
    # Check if docker-compose is available
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        print_error "docker-compose or 'docker compose' is not available"
        exit 1
    fi
    
    print_success "Restore prerequisites check passed"
    print_info "Using compose command: $COMPOSE_CMD"
}

# Function to extract backup archive
extract_backup() {
    local backup_archive="$1"
    print_info "Extracting backup archive..."
    
    TEMP_DIR=$(mktemp -d)
    
    # Extract the archive to temp directory
    if tar -xzf "$backup_archive" -C "$TEMP_DIR" 2>/dev/null; then
        # Find the backup directory (should be smart_intersection_backup)
        local backup_dir=$(find "$TEMP_DIR" -type d -name "*backup*" | head -1)
        
        if [ -z "$backup_dir" ]; then
            print_error "Could not find backup directory in archive"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        EXTRACTED_BACKUP_DIR="$backup_dir"
        print_success "Backup extracted to: $EXTRACTED_BACKUP_DIR"
    else
        print_error "Failed to extract backup archive"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
}

# Function to display backup info
show_backup_info() {
    if [ -f "$EXTRACTED_BACKUP_DIR/backup_info.json" ]; then
        print_info "Backup Information:"
        if command -v jq >/dev/null 2>&1; then
            jq -r '
                "  Backup Date: " + .backup_date,
                "  Deployment: " + .deployment,
                "  Created by: " + (.created_by // "unknown")
            ' "$EXTRACTED_BACKUP_DIR/backup_info.json"
        else
            grep -E '"backup_date"|"deployment"|"created_by"' "$EXTRACTED_BACKUP_DIR/backup_info.json" | \
                sed 's/^[[:space:]]*/  /' | sed 's/,$//'
        fi
        echo
    fi
}

# Function to restore configuration files
restore_configuration() {
    local target_dir="$1"
    print_info "Restoring configuration files..."
    
    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"
    
    if [ -d "$EXTRACTED_BACKUP_DIR/config" ]; then
        cp -r "$EXTRACTED_BACKUP_DIR/config/." "$target_dir/"
        print_success "Configuration files restored to: $target_dir"
        
        # Update HOST_IP in .env file if it exists
        update_host_ip_in_main_restore "$target_dir"
    else
        print_error "Configuration files not found in backup"
        exit 1
    fi
}

# Function to update HOST_IP in .env file (for main restore function)
update_host_ip_in_main_restore() {
    local target_dir="$1"
    local env_file="$target_dir/.env"
    
    if [ -f "$env_file" ]; then
        # Get the current system's IP address
        local current_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
        
        if [ "$current_ip" != "localhost" ] && [ -n "$current_ip" ]; then
            print_info "Updating HOST_IP in .env file to: $current_ip"
            
            # Update HOST_IP in .env file using sed
            if sed -i.bak "s/^HOST_IP=.*/HOST_IP=$current_ip/" "$env_file" 2>/dev/null; then
                print_success "  Updated HOST_IP to $current_ip"
                rm -f "$env_file.bak" 2>/dev/null
            else
                print_warning "  Failed to update HOST_IP in .env file"
            fi
        else
            print_warning "  Could not determine system IP address, HOST_IP not updated"
        fi
    else
        print_warning "  .env file not found, skipping HOST_IP update"
    fi
}

# Function to load Docker images
load_docker_images() {
    print_info "Loading Docker images..."
    
    if [ -f "$EXTRACTED_BACKUP_DIR/image_list.txt" ]; then
        while IFS= read -r image; do
            if [ -n "$image" ]; then
                local safe_name=$(echo "$image" | sed 's/[\/:]/_/g').tar
                if [ -f "$EXTRACTED_BACKUP_DIR/images/$safe_name" ]; then
                    print_info "  Loading $image..."
                    if docker load -i "$EXTRACTED_BACKUP_DIR/images/$safe_name" >/dev/null 2>&1; then
                        print_success "    Loaded $image"
                    else
                        print_warning "    Failed to load $image"
                    fi
                else
                    print_warning "  Image file $safe_name not found, attempting to pull..."
                    docker pull "$image" 2>/dev/null || print_warning "    Failed to pull $image"
                fi
            fi
        done < "$EXTRACTED_BACKUP_DIR/image_list.txt"
    else
        print_warning "Image list not found in backup"
    fi
}

# Function to restore Docker volumes
restore_docker_volumes() {
    print_info "Restoring Docker volumes..."
    
    if [ -f "$EXTRACTED_BACKUP_DIR/volume_list.txt" ]; then
        while IFS= read -r volume; do
            if [ -n "$volume" ] && [ -f "$EXTRACTED_BACKUP_DIR/volumes/$volume.tar.gz" ]; then
                print_info "  Restoring volume $volume..."
                
                # Create the volume if it doesn't exist
                docker volume create "$volume" >/dev/null 2>&1 || true
                
                # Restore the volume content
                if docker run --rm \
                    -v "$volume:/restore-dest" \
                    -v "$EXTRACTED_BACKUP_DIR/volumes:/backup-source" \
                    docker.io/library/alpine:latest \
                    sh -c "cd /restore-dest && tar xzf /backup-source/$volume.tar.gz" 2>/dev/null; then
                    print_success "    Restored volume $volume"
                else
                    print_warning "    Failed to restore volume $volume"
                fi
            fi
        done < "$EXTRACTED_BACKUP_DIR/volume_list.txt"
    else
        print_warning "Volume list not found in backup"
    fi
}

# Function to start deployment
start_deployment() {
    local target_dir="$1"
    print_info "Starting the deployment..."
    
    cd "$target_dir"
    
    # Stop any existing deployment
    print_info "Stopping any existing deployment..."
    $COMPOSE_CMD down --remove-orphans 2>/dev/null || true
    
    # Start the deployment
    print_info "Starting services..."
    if $COMPOSE_CMD up -d; then
        print_success "Deployment started successfully!"
        
        # Show status
        echo
        print_info "Deployment status:"
        $COMPOSE_CMD ps
        
        return 0
    else
        print_error "Failed to start the deployment"
        return 1
    fi
}

# Main restore function
do_restore() {
    local backup_archive="$1"
    local target_dir="${2:-$(pwd)}"
    
    echo "=============================================="
    echo "Smart Intersection Restore"
    echo "=============================================="
    echo "Backup archive: $backup_archive"
    echo "Target directory: $target_dir"
    echo
    
    # Run restore steps
    check_restore_prerequisites "$backup_archive"
    extract_backup "$backup_archive"
    show_backup_info
    restore_configuration "$target_dir"
    load_docker_images
    restore_docker_volumes
    
    if start_deployment "$target_dir"; then
        echo
        echo "=============================================="
        echo "Restoration completed successfully!"
        echo "=============================================="
        echo
        echo "The Smart Intersection deployment is now running."
        echo "You can check the status with: $COMPOSE_CMD ps"
        
        # Try to get the host IP
        local host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
        echo "Access the web interface at: https://${host_ip}:443"
        echo
    else
        echo
        echo "=============================================="
        echo "Restoration failed!"
        echo "=============================================="
        echo
        echo "Please check the error messages above and try again."
        echo "You can also check the logs with: $COMPOSE_CMD logs"
        echo
        exit 1
    fi
}

# ========================= MAIN LOGIC =========================

# Parse command line arguments
case "${1:-}" in
    "backup")
        do_backup "$2"
        ;;
    "restore")
        if [ -z "$2" ]; then
            print_error "Backup archive required for restore mode"
            show_usage
            exit 1
        fi
        do_restore "$2" "$3"
        ;;
    "-h"|"--help"|"help")
        show_usage
        exit 0
        ;;
    *)
        if [ $# -eq 0 ]; then
            show_usage
            exit 0
        else
            print_error "Unknown command: $1"
            echo
            show_usage
            exit 1
        fi
        ;;
esac
