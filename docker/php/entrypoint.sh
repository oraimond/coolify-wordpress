#!/bin/bash
set -e

# Ensure PHP temp folder exists and is writable
mkdir -p /var/www/html/tmp
chown -R www-data:www-data /var/www/html/tmp

# Wait for WordPress to be installed
# until wp core is-installed --path=/var/www/html --quiet --allow-root; do
#     echo "Waiting for WordPress to be installed..."
#     sleep 5
# done

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

# Install All-in-One WP Migration plugin if not already installed
if [ ! -d "/var/www/html/wp-content/plugins/all-in-one-wp-migration" ]; then
    echo "Installing All-in-One WP Migration plugin..."
    curl -o /tmp/ai1wm.zip -SL https://downloads.wordpress.org/plugin/all-in-one-wp-migration.latest-stable.zip
    unzip /tmp/ai1wm.zip -d /var/www/html/wp-content/plugins/
    rm /tmp/ai1wm.zip
    chown -R www-data:www-data /var/www/html/wp-content/plugins/all-in-one-wp-migration
fi

# Activate plugin if not activated
# if ! wp plugin is-active redis-cache --path=/var/www/html --allow-root >/dev/null 2>&1; then
#     echo "Activating Redis Object Cache plugin..."
#     wp plugin activate redis-cache --path=/var/www/html --allow-root
# fi

# Call the original WordPress entrypoint
exec docker-entrypoint.sh "$@"
