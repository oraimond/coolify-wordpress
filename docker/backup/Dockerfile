FROM alpine:3.19

# Install necessary packages
RUN apk add --no-cache \
    mariadb-client \
    bash \
    tar \
    gzip \
    busybox-suid \
    busybox-cron \
    && rm -rf /var/cache/apk/*

# Create backup directory
RUN mkdir -p /backups

# Copy backup script and cron definition
COPY backup.sh /usr/local/bin/wp-backup
RUN chmod +x /usr/local/bin/wp-backup
COPY backup.cron /etc/crontabs/root
RUN chmod 644 /etc/crontabs/root

# Set working directory
WORKDIR /backups

# Default command to run cron in foreground
CMD ["crond", "-f", "-L", "/dev/stdout"]