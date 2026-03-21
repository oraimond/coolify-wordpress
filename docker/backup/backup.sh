#!/bin/bash
set -e

# Function to get database credentials
get_db_credentials() {
    DB_HOST=${WORDPRESS_DB_HOST:-db}
    DB_NAME=${WORDPRESS_DB_NAME}
    DB_USER=${WORDPRESS_DB_USER}
    DB_PASSWORD=${WORDPRESS_DB_PASSWORD}
}

# Format bytes to human readable
human_size() {
    local file="$1"
    if [ ! -e "$file" ]; then
        echo "N/A"
        return 1
    fi

    # Try du (human-readable)
    local size
    size=$(du -h "$file" 2>/dev/null | awk 'NR==1{print $1}')
    if [ -n "$size" ]; then
        echo "$size"
        return 0
    fi

    # Try ls -lh
    size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
    if [ -n "$size" ]; then
        echo "$size"
        return 0
    fi

    # Try stat raw bytes
    size=$(stat -c%s "$file" 2>/dev/null)
    if [ -n "$size" ]; then
        echo "${size}B"
        return 0
    fi

    echo "unknown"
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
    local manual=${1:-0}

    if [ "$manual" -eq 1 ]; then
        echo "Creating manual WordPress backup..."
        suffix="_manual"
    else
        echo "Creating WordPress backup..."
        suffix=""
    fi

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
    BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}${suffix}.tar.gz"
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

cleanup_backups() {
    local dir=/backups
    local now=$(date +%s)

    # Keep manual backups forever
    local keep_recent=2
    local recent_count=0

    # Step 1: cleanup old and non-sunday regional backups
    find "$dir" -maxdepth 1 -name 'backup_*.tar.gz' -not -name '*_manual.tar.gz' | while read -r f; do
        local bname=$(basename "$f")
        local ts=$(echo "$bname" | sed -E 's/^backup_([0-9]{8}_[0-9]{6}).*\.tar\.gz$/\1/')
        [ -z "$ts" ] && continue
        local created=$(date -d "${ts:0:8} ${ts:9:6}" +%s 2>/dev/null || true)
        [ -z "$created" ] && continue

        local age=$(( (now-created) / 86400 ))
        local dow=$(date -d "${ts:0:8} ${ts:9:6}" +%u 2>/dev/null || echo 0)

        if [ "$age" -gt 14 ]; then
            rm -f "$f"
            continue
        fi

        if [ "$age" -gt 3 ] && [ "$dow" != "7" ]; then
            rm -f "$f"
            continue
        fi
    done

    # Step 2: ensure at least 2 recent backups in last 72h
    mapfile -t recent < <(find "$dir" -maxdepth 1 -name 'backup_*.tar.gz' -not -name '*_manual.tar.gz' -mtime -3 -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{print $2}')
    for f in "${recent[@]}"; do
        if [ "$recent_count" -lt "$keep_recent" ]; then
            ((recent_count++))
            continue
        fi
        rm -f "$f"
    done

    # Step 3: ensure at least one 1-2 weeks old backup exists (or sunday backup)
    local week_old=$(date -d '7 days ago' +%s)
    local two_weeks_old=$(date -d '14 days ago' +%s)
    local selected=""

    # Find non-manual backup between 7 and 14 days
    mapfile -t candidates < <(find "$dir" -maxdepth 1 -name 'backup_*.tar.gz' -not -name '*_manual.tar.gz' -mtime +6 -mtime -14 -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{print $2}')
    if [ ${#candidates[@]} -gt 0 ]; then
        selected=${candidates[0]}
    fi

    # Keep selected candidate if it exists and not already removed
    if [ -n "$selected" ] && [ -f "$selected" ]; then
        echo "Retaining 1-2 weeks backup: $selected"
    fi
}

case "$1" in
    backup)
        local manual=1
        if [ "$2" == "--auto" ] || [ "$2" == "-a" ]; then
            manual=0
        fi
        create_backup "$manual"

        # Only run cleanup for automatic backups to avoid touching manual archives
        if [ "$manual" -eq 0 ]; then
            cleanup_backups
        fi
        ;;
    restore)
        restore_backup "$2"
        ;;
    cleanup)
        cleanup_backups
        ;;
    *)
        echo "WordPress Backup/Restore Tool"
        echo ""
        echo "Usage:"
        echo "  wp-backup backup [--auto]            Create a new backup (default = manual)"
        echo "  wp-backup restore [backup_file]      Restore from a backup file (interactive when omitted)"
        echo "  wp-backup cleanup                    Apply retention policy"
        echo ""
        echo "Examples:"
        echo "  wp-backup backup"
        echo "  wp-backup backup --manual"
        echo "  wp-backup restore"
        echo "  wp-backup restore /backups/backup_20240321_120000.tar.gz"
        echo "  wp-backup cleanup"
        echo ""
        echo "Note: Backups are stored in /backups directory inside the container."
        echo "Manual backups are named *_manual.tar.gz and are retained indefinitely."
        exit 1
        ;;
esac