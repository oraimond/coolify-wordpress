FROM alpine:3.19

# Install necessary packages
RUN apk add --no-cache \
    mariadb-client \
    bash \
    tar \
    gzip \
    && rm -rf /var/cache/apk/*

# Create backup directory
RUN mkdir -p /backups

# Copy backup script
COPY backup.sh /usr/local/bin/wp-backup
RUN chmod +x /usr/local/bin/wp-backup

# Set working directory
WORKDIR /backups

# Copy internal scheduler
COPY run-backup-scheduler.sh /usr/local/bin/run-backup-scheduler.sh
RUN chmod +x /usr/local/bin/run-backup-scheduler.sh

# Default command: run scheduler that triggers only 02:00-02:59
CMD ["/usr/local/bin/run-backup-scheduler.sh"]