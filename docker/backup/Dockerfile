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

# Default command to keep container running
CMD ["sleep", "infinity"]