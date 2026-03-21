#!/bin/sh
set -e

# Sleep a small random amount to avoid thundering herd on startup
sleep $((RANDOM % 300))

last_run_date=""

while true; do
    now=$(date +"%Y-%m-%d %H:%M:%S")
    hour=$(date +"%H")
    today=$(date +"%Y-%m-%d")

    if [ "$hour" = "15" ] && [ "$last_run_date" != "$today" ]; then
        echo "[backup-scheduler] Starting automatic backup at $now"
        /usr/local/bin/wp-backup backup --auto
        /usr/local/bin/wp-backup cleanup
        last_run_date="$today"

        # sleep ~23 hours to avoid repeated runs and reduce wakeups
        sleep 82800
        continue
    fi

    # Sleep 10 minutes and re-check if not run yet
    sleep 600
done
