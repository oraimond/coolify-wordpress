# Dockerfile
FROM wordpress:php8.5-fpm-alpine

# Install runtime deps + build deps for PHP extensions
RUN apk add --no-cache \
    bash \
    curl \
    unzip \
    less \
    libzip-dev \
    zip \
    $PHPIZE_DEPS

# Build and enable PHP zip extension
RUN docker-php-ext-configure zip \
    && docker-php-ext-install zip

# Remove build deps to keep image small
RUN apk del $PHPIZE_DEPS

# Install WP-CLI
RUN curl -o /usr/local/bin/wp -SL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Copy custom entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
