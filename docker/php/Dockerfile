# Dockerfile
FROM wordpress:php8.5-fpm-alpine

# Install necessary tools
RUN apk add --no-cache bash curl unzip

# Copy custom entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
