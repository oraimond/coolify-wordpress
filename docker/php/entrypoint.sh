#!/bin/bash
set -e

# Ensure plugins directory exists and is writable
mkdir -p /var/www/html/wp-content/plugins
chown -R www-data:www-data /var/www/html/wp-content/plugins

# Install Redis Object Cache plugin if not already installed
if [ ! -d "/var/www/html/wp-content/plugins/redis-cache" ]; then
    echo "Installing Redis Object Cache plugin..."
    curl -o /tmp/redis.zip -SL https://downloads.wordpress.org/plugin/redis-cache.latest-stable.zip
    unzip /tmp/redis.zip -d /var/www/html/wp-content/plugins/
    rm /tmp/redis.zip
    chown -R www-data:www-data /var/www/html/wp-content/plugins/redis-cache
fi

# Activate plugin if not activated
if ! wp plugin is-active redis-cache --path=/var/www/html >/dev/null 2>&1; then
    echo "Activating Redis Object Cache plugin..."
    wp plugin activate redis-cache --path=/var/www/html
fi

# Call the original WordPress entrypoint
exec docker-entrypoint.sh "$@"
