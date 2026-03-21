#!/bin/bash
set -e

# Function to get database credentials
get_db_credentials() {
    DB_HOST=${WORDPRESS_DB_HOST:-db}
    DB_NAME=${WORDPRESS_DB_NAME}
    DB_USER=${WORDPRESS_DB_USER}
    DB_PASSWORD=${WORDPRESS_DB_PASSWORD}
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
    echo "Creating combined backup archive..."
    tar -czf "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz" -C "$BACKUP_DIR" "db_$TIMESTAMP.sql" "files_$TIMESTAMP.tar.gz"

    # Clean up temporary files
    rm "$BACKUP_DIR/db_$TIMESTAMP.sql" "$BACKUP_DIR/files_$TIMESTAMP.tar.gz"

    echo "Backup completed successfully!"
    echo "Backup file: $BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
    echo "You can copy this file to a safe location for storage."
}

# Function to restore from backup
restore_backup() {
    if [ -z "$1" ]; then
        echo "Error: Please provide the backup file path"
        echo "Usage: $0 restore /path/to/backup_file.tar.gz"
        exit 1
    fi

    BACKUP_FILE=$1

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

    # Set proper permissions
    chown -R www-data:www-data /var/www/html/wp-content

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
        echo "  $0 backup                    Create a new backup"
        echo "  $0 restore <backup_file>     Restore from a backup file"
        echo ""
        echo "Examples:"
        echo "  $0 backup"
        echo "  $0 restore /backups/backup_20240321_120000.tar.gz"
        echo ""
        echo "Note: Backups are stored in /backups directory inside the container."
        echo "Make sure to mount this volume or copy files as needed."
        exit 1
        ;;
esac