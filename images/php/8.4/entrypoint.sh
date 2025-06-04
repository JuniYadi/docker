#!/bin/bash

# Redirect all output to stdout/stderr for Docker logging
exec > >(tee -a /proc/1/fd/1)
exec 2> >(tee -a /proc/1/fd/2)

# Generate php.ini based on environment variables
generate_php_ini() {
    local ini_file="/usr/local/etc/php/conf.d/php-custom.ini"
    
    echo "[$(date)] Generating PHP configuration..."
    
    # Start with base configuration
    cat > "$ini_file" << EOF
; Generated PHP configuration
memory_limit=${PHP_MEMORY_LIMIT:-512M}
upload_max_filesize=${PHP_UPLOAD_MAX_FILESIZE:-50M}
post_max_size=${PHP_POST_MAX_SIZE:-50M}
max_execution_time=${PHP_MAX_EXECUTION_TIME:-300}

; OPcache settings
opcache.enable=${PHP_OPCACHE_ENABLE:-1}
opcache.memory_consumption=${PHP_OPCACHE_MEMORY:-256}
opcache.max_accelerated_files=${PHP_OPCACHE_MAX_FILES:-20000}
opcache.validate_timestamps=${PHP_OPCACHE_VALIDATE:-0}

EOF

    # Process PHP extension environment variables
    for var in $(env | grep '^PHP_EXTENSION_' | cut -d= -f1); do
        extension_name=$(echo "$var" | sed 's/PHP_EXTENSION_//' | tr '[:upper:]' '[:lower:]')
        extension_value=$(eval echo \$$var)
        
        if [[ "$extension_value" == "1" || "$extension_value" == "true" || "$extension_value" == "on" ]]; then
            echo "extension=$extension_name" >> "$ini_file"
            echo "[$(date)] Enabled extension: $extension_name"
        else
            echo "; extension=$extension_name  ; Disabled" >> "$ini_file"
            echo "[$(date)] Disabled extension: $extension_name"
        fi
    done
    
    echo "[$(date)] PHP configuration generated at $ini_file"
}
# ...existing code...

# Generate PHP-FPM www.conf based on environment variables
generate_fpm_conf() {
    local conf_file="/usr/local/etc/php-fpm.d/www.conf"
    
    echo "[$(date)] Generating PHP-FPM configuration..."
    
    # Calculate defaults based on system resources if env vars are not set
    calculate_fpm_defaults() {
        # Get available memory in MB
        local available_memory=$(free -m | awk '/^Mem:/{print $2}')
        local cpu_cores=$(nproc)
        
        # Calculate max_children based on memory (assuming ~50MB per PHP process)
        local calculated_max_children=$((available_memory / 50))
        
        # Ensure reasonable limits
        if [ $calculated_max_children -lt 5 ]; then
            calculated_max_children=5
        elif [ $calculated_max_children -gt 100 ]; then
            calculated_max_children=100
        fi
        
        # Calculate other values based on max_children
        local calculated_start_servers=$((calculated_max_children / 10))
        [ $calculated_start_servers -lt 2 ] && calculated_start_servers=2
        
        local calculated_min_spare=$((calculated_max_children / 10))
        [ $calculated_min_spare -lt 1 ] && calculated_min_spare=1
        
        local calculated_max_spare=$((calculated_max_children / 3))
        [ $calculated_max_spare -lt 5 ] && calculated_max_spare=5
        
        # Export calculated values for logging
        echo "[$(date)] System resources: ${available_memory}MB RAM, ${cpu_cores} CPU cores"
        echo "[$(date)] Calculated FPM defaults: max_children=${calculated_max_children}, start_servers=${calculated_start_servers}"
    }
    
    # Calculate defaults first
    calculate_fpm_defaults
    
    # Set values based on environment or calculated defaults
    local pm_type=${FPM_PM:-dynamic}
    local pm_max_children=${FPM_PM_MAX_CHILDREN:-$calculated_max_children}
    local pm_start_servers=${FPM_PM_START_SERVERS:-$calculated_start_servers}
    local pm_min_spare_servers=${FPM_PM_MIN_SPARE_SERVERS:-$calculated_min_spare}
    local pm_max_spare_servers=${FPM_PM_MAX_SPARE_SERVERS:-$calculated_max_spare}
    local pm_max_requests=${FPM_PM_MAX_REQUESTS:-1000}
    local request_timeout=${FPM_REQUEST_TIMEOUT:-300}
    local listen_type=${FPM_LISTEN_TYPE:-port}
    
    # Log whether values are from env or calculated
    echo "[$(date)] FPM Configuration source:"
    echo "  pm_type: ${pm_type} $([ -n "$FPM_PM" ] && echo "(from env)" || echo "(default)")"
    echo "  pm_max_children: ${pm_max_children} $([ -n "$FPM_PM_MAX_CHILDREN" ] && echo "(from env)" || echo "(calculated)")"
    echo "  pm_start_servers: ${pm_start_servers} $([ -n "$FPM_PM_START_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    echo "  pm_min_spare_servers: ${pm_min_spare_servers} $([ -n "$FPM_PM_MIN_SPARE_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    echo "  pm_max_spare_servers: ${pm_max_spare_servers} $([ -n "$FPM_PM_MAX_SPARE_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    
    # Determine listen configuration
    local listen_config
    if [[ "$listen_type" == "socket" ]]; then
        listen_config="/var/run/php/php8.4-fpm.sock"
        listen_owner="www-data"
        listen_group="www-data"
        listen_mode="0660"
    else
        listen_config="0.0.0.0:9000"
        listen_owner=""
        listen_group=""
        listen_mode=""
    fi
    
    cat > "$conf_file" << EOF
; Generated PHP-FPM configuration
[www]

; Pool user and group
user = www-data
group = www-data

; Listen configuration
listen = $listen_config
EOF

    # Add socket-specific configurations if using socket
    if [[ "$listen_type" == "socket" ]]; then
        cat >> "$conf_file" << EOF
listen.owner = $listen_owner
listen.group = $listen_group
listen.mode = $listen_mode
EOF
    fi

    cat >> "$conf_file" << EOF

; Process manager configuration
pm = $pm_type
pm.max_children = $pm_max_children
pm.start_servers = $pm_start_servers
pm.min_spare_servers = $pm_min_spare_servers
pm.max_spare_servers = $pm_max_spare_servers
pm.max_requests = $pm_max_requests

; Timeouts
request_timeout = ${request_timeout}s

; Logging
access.log = /proc/self/fd/2
catch_workers_output = yes
decorate_workers_output = no

; Security
security.limit_extensions = .php
php_admin_value[disable_functions] = exec,passthru,shell_exec,system
php_admin_flag[allow_url_fopen] = off

; Environment variables
clear_env = no

; Status and ping pages
pm.status_path = /fpm-status
ping.path = /fpm-ping

; Slow log
slowlog = /proc/self/fd/2
request_slowlog_timeout = 10s

; Custom settings for your application
php_value[session.save_path] = /tmp
php_value[upload_tmp_dir] = /tmp
EOF

    echo "[$(date)] PHP-FPM configuration generated at $conf_file"
    echo "[$(date)] FPM Settings: pm=$pm_type, max_children=$pm_max_children, start_servers=$pm_start_servers"
}

# Check and setup Laravel application
setup_laravel() {
    local app_dir="/web"
    
    echo "[$(date)] Checking application directory: $app_dir"
    
    # Create directory if it doesn't exist
    mkdir -p "$app_dir"
    cd "$app_dir"
    
    # Check if directory is empty or just has hidden files
    if [ -z "$(ls -A "$app_dir" 2>/dev/null | grep -v '^\.')" ]; then
        echo "[$(date)] Application directory is empty. Installing Laravel..."
        
        # Install Laravel using Composer
        composer create-project laravel/laravel . --prefer-dist --no-dev
        
        if [ $? -eq 0 ]; then
            echo "[$(date)] Laravel installed successfully!"
            
            # Set proper permissions
            chown -R www-data:www-data "$app_dir"
            chmod -R 755 "$app_dir"
            chmod -R 775 "$app_dir/storage" "$app_dir/bootstrap/cache"
            
            # Generate application key if .env exists
            if [ -f ".env" ]; then
                php artisan key:generate --ansi
            fi
        else
            echo "[$(date)] ERROR: Failed to install Laravel" >&2
            exit 1
        fi
    else
        echo "[$(date)] Application directory contains files. Skipping Laravel installation."
        
        # Check if it's a Laravel project and run composer install
        if [ -f "composer.json" ] && [ -f "artisan" ]; then
            echo "[$(date)] Detected Laravel project. Running composer install..."
            composer install --no-dev --optimize-autoloader
            
            # Set proper permissions
            chown -R www-data:www-data "$app_dir"
            chmod -R 755 "$app_dir"
            chmod -R 775 "$app_dir/storage" "$app_dir/bootstrap/cache" 2>/dev/null || true
        fi
    fi
}

# Main execution
main() {
    echo "[$(date)] Starting PHP-FPM + Nginx container..."
    
    # Generate PHP configuration
    generate_php_ini
    
    # Generate PHP-FPM configuration
    generate_fpm_conf
    
    # Setup Laravel application
    setup_laravel
    
    echo "[$(date)] Starting services..."
    
    # Start supervisord (which will start nginx and php-fpm)
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
}

# Run main function
main "$@"