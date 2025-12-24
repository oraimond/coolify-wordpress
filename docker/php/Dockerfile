# Dockerfile
FROM wordpress:php8.5-fpm-alpine

# Install necessary tools
RUN apk add --no-cache bash curl libzip unzip less

# Enable PHP zip extension
RUN docker-php-ext-configure zip \
    && docker-php-ext-install zip

# Install WP-CLI
RUN curl -o /usr/local/bin/wp -SL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Copy custom entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
