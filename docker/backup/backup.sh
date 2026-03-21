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

allow_date() {
    date -d "1970-01-01" +%s >/dev/null 2>&1
}

format_backup_timestamp() {
    local filename=$1
    if [[ $filename =~ ^backup_([0-9]{8}_[0-9]{6})(?:_manual)?\.tar\.gz$ ]]; then
        local ts=${BASH_REMATCH[1]}
        local y=${ts:0:4}
        local m=${ts:4:2}
        local d=${ts:6:2}
        local hh=${ts:9:2}
        local mm=${ts:11:2}
        local ss=${ts:13:2}
        echo "$y-$m-$d $hh:$mm:$ss"
    else
        echo "unknown"
    fi
}

# day-of-week: Sunday=7, Monday=1, ..., Saturday=6
weekday_from_date() {
    local y=$1
    local m=$2
    local d=$3
    if [ "$m" -le 2 ]; then
        m=$((m+12))
        y=$((y-1))
    fi
    local K=$((y % 100))
    local J=$((y / 100))
    local h=$(( (d + (13*(m+1))/5 + K + K/4 + J/4 + 5*J) % 7 ))
    local dow=$(( ((h+5) % 7) + 1 ))
    # 1=Monday..7=Sunday
    echo "$dow"
}

list_backups() {
    local dir=/backups

    echo
    echo "Available backups (current: $(date +"%Y-%m-%d %H:%M:%S"))"
    echo "-----------------------------------------------------------------------------------"

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

    echo "-----------------------------------------------------------------------------------"
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

file_mtime() {
    local file=$1

    if stat -c %Y "$file" >/dev/null 2>&1; then
        stat -c %Y "$file"
    else
        stat -f %m "$file" 2>/dev/null
    fi
}

cleanup_backups() {
    dir=/backups
    now=$(date +%s 2>/dev/null || echo "$(/bin/date +%s)")
    keep_recent=2

    # Step 1: cleanup old and non-sunday backups (manual backups preserved automatically)
    find "$dir" -maxdepth 1 -name 'backup_*.tar.gz' -not -name '*_manual.tar.gz' | while read -r f; do
        bname=$(basename "$f")
        ts=$(echo "$bname" | sed -E 's/^backup_([0-9]{8}_[0-9]{6}).*\.tar\.gz$/\1/')
        [ -z "$ts" ] && continue

        created_ts=$(file_mtime "$f")
        [ -z "$created_ts" ] && continue

        age=$(( (now - created_ts) / 86400 ))

        yyyy=${ts:0:4}
        mm=${ts:4:2}
        dd=${ts:6:2}
        dow=$(weekday_from_date "$yyyy" "$mm" "$dd")

        if [ "$age" -gt 14 ]; then
            rm -f "$f"
            continue
        fi

        if [ "$age" -gt 3 ] && [ "$dow" -ne 7 ]; then
            rm -f "$f"
            continue
        fi
    done

    # Step 2: ensure at least 2 recent backups in last 72h
    recent_items=()
    while IFS= read -r -d '' f; do
        created_ts=$(file_mtime "$f")
        [ -z "$created_ts" ] && continue
        age=$(( (now - created_ts) / 86400 ))
        if [ "$age" -le 3 ]; then
            recent_items+=("$created_ts:$f")
        fi
    done < <(find "$dir" -maxdepth 1 -name 'backup_*.tar.gz' -not -name '*_manual.tar.gz' -print0)

    if [ ${#recent_items[@]} -gt 0 ]; then
        IFS=$'\n' sorted=($(printf '%s\n' "${recent_items[@]}" | sort -rn))
        unset IFS
        recent_count=0
        for item in "${sorted[@]}"; do
            f=${item#*:}
            if [ "$recent_count" -lt "$keep_recent" ]; then
                recent_count=$((recent_count+1))
                continue
            fi
            rm -f "$f"
        done
    fi

    # Step 3: ensure at least one 1-2 weeks Sunday backup stays (in practice step 1 already retains recent Sunday backups up to 14d)
    # no additional action required here unless you want explicit enforcement
}


case "$1" in
    backup)
        manual=1
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
    list)
        list_backups
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
        echo "  wp-backup list                      List available backups"
        echo "  wp-backup cleanup                   Apply retention policy"
        echo ""
        echo "Examples:"
        echo "  wp-backup backup"
        echo "  wp-backup backup --auto"
        echo "  wp-backup restore"
        echo "  wp-backup restore /backups/backup_20240321_120000.tar.gz"
        echo "  wp-backup list"
        echo "  wp-backup cleanup"
        echo ""
        echo "Note: Backups are stored in /backups directory inside the container."
        echo "Manual backups are named *_manual.tar.gz and are retained indefinitely."
        exit 1
        ;;
esac