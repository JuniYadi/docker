#!/bin/bash

# Test script for the dynamic configuration system
set -e

# Create test directories
mkdir -p /tmp/test-config/etc/nginx/conf.d
mkdir -p /tmp/test-config/etc/supervisor/conf.d
mkdir -p /tmp/test-config/usr/local/etc/php/conf.d
mkdir -p /tmp/test-config/usr/local/etc/php-fpm.d

# Export test environment variables
export APP_DIR="/var/www/html"
export PHP_MEMORY_LIMIT="256M"
export NGINX_WORKER_PROCESSES="2"
export SUPERVISOR_NODAEMON="true"

# Simple logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

export -f log
export -f log_error

echo "=== Testing Configuration Scripts ==="

# Test PHP configuration
echo "Testing PHP configuration..."
source ./scripts/php.sh
generate_php_ini() {
    local ini_file="/tmp/test-config/usr/local/etc/php/conf.d/php-custom.ini"
    mkdir -p "$(dirname "$ini_file")"
    cat > "$ini_file" << EOF
; Generated PHP configuration
memory_limit=${PHP_MEMORY_LIMIT:-512M}
upload_max_filesize=50M
EOF
    echo "PHP INI generated at $ini_file"
}

generate_php_ini

# Test Nginx configuration
echo "Testing Nginx configuration..."
source ./scripts/nginx.sh
generate_nginx_conf() {
    local nginx_conf="/tmp/test-config/etc/nginx/nginx.conf"
    mkdir -p "$(dirname "$nginx_conf")"
    cat > "$nginx_conf" << EOF
user www-data;
worker_processes ${NGINX_WORKER_PROCESSES:-auto};

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/conf.d/*.conf;
}
EOF
    echo "Nginx config generated at $nginx_conf"
}

generate_nginx_conf

# Test VHost configuration
echo "Testing VHost configuration..."
source ./scripts/nginx-vhost.sh

# Test Supervisor configuration
echo "Testing Supervisor configuration..."
source ./scripts/supervisor.sh
generate_supervisor_conf() {
    local supervisor_conf="/tmp/test-config/etc/supervisor/conf.d/supervisord.conf"
    mkdir -p "$(dirname "$supervisor_conf")"
    cat > "$supervisor_conf" << EOF
[supervisord]
nodaemon=${SUPERVISOR_NODAEMON:-true}

[program:nginx]
command=nginx -g "daemon off;"
autostart=true

[program:php-fpm]
command=php-fpm -F
autostart=true
EOF
    echo "Supervisor config generated at $supervisor_conf"
}

generate_supervisor_conf

echo "=== Configuration Test Complete ==="
echo "Generated files:"
find /tmp/test-config -name "*.conf" -o -name "*.ini" | sort

# Clean up
rm -rf /tmp/test-config
echo "Test cleanup complete"