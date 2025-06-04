#!/bin/bash

# Ensure all output goes to stdout/stderr for proper Kubernetes logging
# Remove any existing redirections that might interfere with container logging
set -e

# Ensure output is not buffered
export PYTHONUNBUFFERED=1

# Function to log with timestamp to stdout
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    # Force flush to ensure immediate output in Kubernetes
    exec 1>&1
}

# Function to log errors with timestamp to stderr
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    # Force flush to ensure immediate output in Kubernetes
    exec 2>&2
}

check_commands() {
    local missing_commands=()
    
    # Essential commands that should be available
    local required_commands=("php" "composer" "nginx" "supervisord")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please ensure the Docker image is built correctly with all dependencies"
        exit 1
    fi
    
    # Optional commands with warnings
    local optional_commands=("free" "nproc" "awk")
    for cmd in "${optional_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "WARNING: Command '$cmd' not found. Using fallback methods."
        fi
    done
    
    log "Command availability check completed successfully"
}

generate_php_ini() {
    local ini_file="/usr/local/etc/php/conf.d/php-custom.ini"
    
    log "Generating PHP configuration..."
    
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
            log "Enabled extension: $extension_name"
        else
            echo "; extension=$extension_name  ; Disabled" >> "$ini_file"
            log "Disabled extension: $extension_name"
        fi
    done
    
    log "PHP configuration generated at $ini_file"
}
# ...existing code...

# Generate PHP-FPM www.conf based on environment variables
generate_fpm_conf() {
    local conf_file="/usr/local/etc/php-fpm.d/www.conf"
    
    log "Generating PHP-FPM configuration..."
    
    # Calculate defaults based on system resources if env vars are not set
    calculate_fpm_defaults() {
        # Get available memory in MB with fallback
        local available_memory
        if command -v free >/dev/null 2>&1; then
            available_memory=$(free -m | awk '/^Mem:/{print $2}' 2>/dev/null)
        fi
        
        # If free command failed or not available, try /proc/meminfo
        if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ] 2>/dev/null; then
            if [ -r /proc/meminfo ]; then
                available_memory=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
            fi
        fi
        
        # Final fallback to a reasonable default
        if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ] 2>/dev/null; then
            available_memory=1024
            log "WARNING: Could not determine system memory. Using default: ${available_memory}MB"
        fi
        
        # Get CPU cores with fallback
        local cpu_cores
        if command -v nproc >/dev/null 2>&1; then
            cpu_cores=$(nproc 2>/dev/null)
        fi
        
        # If nproc failed or not available, try /proc/cpuinfo
        if [ -z "$cpu_cores" ] || [ "$cpu_cores" -eq 0 ] 2>/dev/null; then
            if [ -r /proc/cpuinfo ]; then
                cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
            fi
        fi
        
        # Final fallback to 1 core
        if [ -z "$cpu_cores" ] || [ "$cpu_cores" -eq 0 ] 2>/dev/null; then
            cpu_cores=1
            log "WARNING: Could not determine CPU cores. Using default: ${cpu_cores}"
        fi
        
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
        log "System resources: ${available_memory}MB RAM, ${cpu_cores} CPU cores"
        log "Calculated FPM defaults: max_children=${calculated_max_children}, start_servers=${calculated_start_servers}"
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
    local listen_type=${FPM_LISTEN_TYPE:-port}
    
    # Validate that pm_max_children is a positive integer
    if ! [[ "$pm_max_children" =~ ^[0-9]+$ ]] || [ "$pm_max_children" -le 0 ]; then
        log_error "pm_max_children must be a positive integer, got: $pm_max_children"
        pm_max_children=5
        log "Using fallback value: pm_max_children=$pm_max_children"
    fi
    
    # Validate other PM values are positive integers
    if ! [[ "$pm_start_servers" =~ ^[0-9]+$ ]] || [ "$pm_start_servers" -le 0 ]; then
        pm_start_servers=2
        log "Invalid pm_start_servers, using fallback: $pm_start_servers"
    fi
    
    if ! [[ "$pm_min_spare_servers" =~ ^[0-9]+$ ]] || [ "$pm_min_spare_servers" -le 0 ]; then
        pm_min_spare_servers=1
        log "Invalid pm_min_spare_servers, using fallback: $pm_min_spare_servers"
    fi
    
    if ! [[ "$pm_max_spare_servers" =~ ^[0-9]+$ ]] || [ "$pm_max_spare_servers" -le 0 ]; then
        pm_max_spare_servers=5
        log "Invalid pm_max_spare_servers, using fallback: $pm_max_spare_servers"
    fi
    
    if ! [[ "$pm_max_requests" =~ ^[0-9]+$ ]] || [ "$pm_max_requests" -le 0 ]; then
        pm_max_requests=1000
        log "Invalid pm_max_requests, using fallback: $pm_max_requests"
    fi
    
    # Log whether values are from env or calculated
    log "FPM Configuration source:"
    log "  pm_type: ${pm_type} $([ -n "$FPM_PM" ] && echo "(from env)" || echo "(default)")"
    log "  pm_max_children: ${pm_max_children} $([ -n "$FPM_PM_MAX_CHILDREN" ] && echo "(from env)" || echo "(calculated)")"
    log "  pm_start_servers: ${pm_start_servers} $([ -n "$FPM_PM_START_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    log "  pm_min_spare_servers: ${pm_min_spare_servers} $([ -n "$FPM_PM_MIN_SPARE_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    log "  pm_max_spare_servers: ${pm_max_spare_servers} $([ -n "$FPM_PM_MAX_SPARE_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    
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

    log "PHP-FPM configuration generated at $conf_file"
    log "FPM Settings: pm=$pm_type, max_children=$pm_max_children, start_servers=$pm_start_servers"
}

# Check and setup Laravel application
setup_laravel() {
    local app_dir="/var/www"
    
    log "Checking application directory: $app_dir"
    
    # Create directory if it doesn't exist
    mkdir -p "$app_dir"
    cd "$app_dir"
    
    # Check if directory is empty or just has hidden files
    if [ -z "$(ls -A "$app_dir" 2>/dev/null | grep -v '^\.')" ]; then
        log "Application directory is empty. Installing Laravel..."
        
        # Install Laravel using Composer
        composer create-project laravel/laravel . --prefer-dist --no-dev
        
        if [ $? -eq 0 ]; then
            log "Laravel installed successfully!"
            
            # Set proper permissions
            chown -R www-data:www-data "$app_dir"
            chmod -R 755 "$app_dir"
            chmod -R 775 "$app_dir/storage" "$app_dir/bootstrap/cache"
            
            # Generate application key if .env exists
            if [ -f ".env" ]; then
                php artisan key:generate --ansi
            fi
        else
            log_error "Failed to install Laravel"
            exit 1
        fi
    else
        log "Application directory contains files. Skipping Laravel installation."
        
        # Check if it's a Laravel project and run composer install
        if [ -f "composer.json" ] && [ -f "artisan" ]; then
            log "Detected Laravel project. Running composer install..."
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
    log "=== PHP-FPM + Nginx Container Starting ==="
    log "Starting PHP-FPM + Nginx container..."
    log "Container PID: $$"
    log "Environment: $(printenv | grep -E '^(KUBERNETES|POD_|SERVICE_)' | head -3 || echo 'Not running in Kubernetes')"
    
    # Check for required commands
    check_commands
    
    # Generate PHP configuration
    generate_php_ini
    
    # Generate PHP-FPM configuration
    generate_fpm_conf
    
    # Setup Laravel application
    setup_laravel
    
    log "Starting services..."
    log "About to execute supervisord..."
    
    # Add some debugging information
    log "Supervisord config file exists: $([ -f /etc/supervisor/conf.d/supervisord.conf ] && echo 'YES' || echo 'NO')"
    log "PHP-FPM config file exists: $([ -f /usr/local/etc/php-fpm.d/www.conf ] && echo 'YES' || echo 'NO')"
    log "Nginx config file exists: $([ -f /etc/nginx/nginx.conf ] && echo 'YES' || echo 'NO')"
    
    # Test that services can be started
    log "Testing PHP-FPM configuration..."
    php-fpm -t && log "PHP-FPM configuration test passed" || log_error "PHP-FPM configuration test failed"
    
    log "Testing Nginx configuration..."
    nginx -t && log "Nginx configuration test passed" || log_error "Nginx configuration test failed"
    
    # Start supervisord (which will start nginx and php-fpm)
    log "Executing supervisord with PID $$"
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

}

# Run main function
main "$@"