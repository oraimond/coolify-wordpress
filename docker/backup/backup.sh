#!/bin/bash
set -e

# Function to get database credentials
get_db_credentials() {
    DB_HOST=${WORDPRESS_DB_HOST:-db}
    DB_NAME=${WORDPRESS_DB_NAME}
    DB_USER=${WORDPRESS_DB_USER}
    DB_PASSWORD=${WORDPRESS_DB_PASSWORD}
}

# Format bytes to human readable (default from du -h if available)
human_size() {
    du -h --apparent-size --block-size=1 "$1" 2>/dev/null | awk '{print $1}' || du -h "$1" 2>/dev/null | awk '{print $1}'
}

format_backup_timestamp() {
    local filename=$1
    if [[ $filename =~ backup_([0-9]{8}_[0-9]{6})\.tar\.gz$ ]]; then
        local ts=${BASH_REMATCH[1]}
        local d=${ts:0:8}
        local t=${ts:9:6}
        local formatted=$(date -d "${d:0:4}-${d:4:2}-${d:6:2} ${t:0:2}:${t:2:2}:${t:4:2}" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
        echo "$formatted"
    else
        echo "unknown"
    fi
}

list_backups() {
    local dir=/backups

    echo
    echo "Available backups (current: $(date +"%Y-%m-%d %H:%M:%S"))"
    echo "----------------------------------------------------"

    mapfile -t backups < <(find "$dir" -maxdepth 1 -name 'backup_*.tar.gz' -print | sort)

    if [ ${#backups[@]} -eq 0 ]; then
        echo "No backups found in $dir"
        return 1
    fi

    printf "%3s  %-25s  %-12s  %s\n" "#" "Date" "Size" "File"
    local idx=1
    for f in "${backups[@]}"; do
        local bname=$(basename "$f")
        local ts=$(format_backup_timestamp "$bname")
        local size=$(human_size "$f")
        printf "%3d  %-25s  %-12s  %s\n" "$idx" "$ts" "$size" "$bname"
        ((idx++))
    done

    echo "----------------------------------------------------"
    echo
    return 0
}

# Function to create backup
create_backup() {
    echo "Creating WordPress backup..."

    get_db_credentials

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR=/backups
    mkdir -p "$BACKUP_DIR"

    # Create database backup
    echo "Backing up database..."
    mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > "$BACKUP_DIR/db_$TIMESTAMP.sql"

    # Create files backup (wp-content directory)
    echo "Backing up WordPress files..."
    tar -czf "$BACKUP_DIR/files_$TIMESTAMP.tar.gz" -C /var/www/html wp-content

    # Create combined backup archive
    BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
    echo "Creating combined backup archive..."
    tar -czf "$BACKUP_FILE" -C "$BACKUP_DIR" "db_$TIMESTAMP.sql" "files_$TIMESTAMP.tar.gz"

    # Clean up temporary files
    rm "$BACKUP_DIR/db_$TIMESTAMP.sql" "$BACKUP_DIR/files_$TIMESTAMP.tar.gz"

    local backup_size=$(human_size "$BACKUP_FILE")

    echo "Backup completed successfully!"
    echo "Backup file: $BACKUP_FILE"
    echo "Backup size: $backup_size"
    echo "You can copy this file to a safe location for storage."
}

# Function to restore from backup
restore_backup() {
    BACKUP_DIR=/backups

    if [ -z "$1" ]; then
        if ! list_backups; then
            exit 1
        fi

        read -rp "Select backup number to restore: " choice

        if ! [[ $choice =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $(find "$BACKUP_DIR" -maxdepth 1 -name 'backup_*.tar.gz' | wc -l | tr -d ' ') ]; then
            echo "Invalid selection. Aborting."
            exit 1
        fi

        BACKUP_FILE=$(find "$BACKUP_DIR" -maxdepth 1 -name 'backup_*.tar.gz' | sort | sed -n "${choice}p")
    else
        if [[ $1 == /* ]]; then
            BACKUP_FILE="$1"
        else
            BACKUP_FILE="$BACKUP_DIR/$1"
            if [ ! -f "$BACKUP_FILE" ] && [ -f "$1" ]; then
                BACKUP_FILE="$1"
            fi
        fi
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: Backup file '$BACKUP_FILE' not found"
        exit 1
    fi

    echo "Restoring WordPress from backup: $BACKUP_FILE"

    get_db_credentials

    # Create temporary directory for extraction
    TMP_DIR=$(mktemp -d)
    trap "rm -rf $TMP_DIR" EXIT

    # Extract backup archive
    echo "Extracting backup files..."
    tar -xzf "$BACKUP_FILE" -C "$TMP_DIR"

    # Find the extracted files
    DB_DUMP=$(find "$TMP_DIR" -name "db_*.sql" | head -1)
    FILES_ARCHIVE=$(find "$TMP_DIR" -name "files_*.tar.gz" | head -1)

    if [ -z "$DB_DUMP" ] || [ -z "$FILES_ARCHIVE" ]; then
        echo "Error: Invalid backup file format"
        exit 1
    fi

    # Restore database
    echo "Restoring database..."
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$DB_DUMP"

    # Restore files
    echo "Restoring WordPress files..."
    tar -xzf "$FILES_ARCHIVE" -C /var/www/html

    # Set proper permissions if www-data user exists
    if id www-data > /dev/null 2>&1; then
        chown -R www-data:www-data /var/www/html/wp-content
    fi

    echo "Restore completed successfully!"
    echo "WordPress has been restored from the backup."
}

# Main script logic
case "$1" in
    backup)
        create_backup
        ;;
    restore)
        restore_backup "$2"
        ;;
    *)
        echo "WordPress Backup/Restore Tool"
        echo ""
        echo "Usage:"
        echo "  wp-backup backup                    Create a new backup"
        echo "  wp-backup restore [backup_file]     Restore from a backup file (interactive when omitted)"
        echo ""
        echo "Examples:"
        echo "  wp-backup backup"
        echo "  wp-backup restore /backups/backup_20240321_120000.tar.gz"
        echo "  wp-backup restore"
        echo ""
        echo "Note: Backups are stored in /backups directory inside the container."
        echo "Make sure to mount this volume or copy files as needed."
        exit 1
        ;;
esac