# Dockerfile
FROM wordpress:php8.5-fpm

# Install runtime deps + build deps for PHP extensions
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    unzip \
    less \
    libzip-dev \
    zip \
    mariadb-client \
    $PHPIZE_DEPS \
    && rm -rf /var/lib/apt/lists/*

# Build and enable PHP zip extension
RUN docker-php-ext-configure zip \
    && docker-php-ext-install zip

# Install WP-CLI
RUN curl -o /usr/local/bin/wp -SL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Copy custom entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy backup script
COPY backup.sh /usr/local/bin/wp-backup
RUN chmod +x /usr/local/bin/wp-backup

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]