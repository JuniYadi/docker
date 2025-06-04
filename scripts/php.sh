#!/bin/bash

# Global PHP Configuration Script
# This script contains reusable configuration functions for PHP containers
# It should be sourced by entrypoint scripts to provide consistent behavior

# Ensure all output goes to stdout/stderr for proper Kubernetes logging
set -e

# Ensure output is not buffered
export PYTHONUNBUFFERED=1

# Global Configuration Variables (can be overridden by environment)
export DEFAULT_PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-512M}
export DEFAULT_PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE:-50M}
export DEFAULT_PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE:-50M}
export DEFAULT_PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME:-300}
export DEFAULT_PHP_OPCACHE_ENABLE=${PHP_OPCACHE_ENABLE:-1}
export DEFAULT_PHP_OPCACHE_MEMORY=${PHP_OPCACHE_MEMORY:-256}
export DEFAULT_PHP_OPCACHE_MAX_FILES=${PHP_OPCACHE_MAX_FILES:-20000}
export DEFAULT_PHP_OPCACHE_VALIDATE=${PHP_OPCACHE_VALIDATE:-0}

# FPM Global Defaults
export DEFAULT_FPM_PM=${FPM_PM:-dynamic}
export DEFAULT_FPM_PM_MAX_REQUESTS=${FPM_PM_MAX_REQUESTS:-1000}
export DEFAULT_FPM_LISTEN_TYPE=${FPM_LISTEN_TYPE:-port}

# Application Defaults
export DEFAULT_APP_DIR=${APP_DIR:-/var/www/html}

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

# Check for required and optional commands
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

# Generate PHP configuration
generate_php_ini() {
    local ini_file="/usr/local/etc/php/conf.d/php-custom.ini"
    
    log "Generating PHP configuration..."
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$ini_file")"
    
    # Start with base configuration
    cat > "$ini_file" << EOF
; Generated PHP configuration
memory_limit=${PHP_MEMORY_LIMIT:-$DEFAULT_PHP_MEMORY_LIMIT}
upload_max_filesize=${PHP_UPLOAD_MAX_FILESIZE:-$DEFAULT_PHP_UPLOAD_MAX_FILESIZE}
post_max_size=${PHP_POST_MAX_SIZE:-$DEFAULT_PHP_POST_MAX_SIZE}
max_execution_time=${PHP_MAX_EXECUTION_TIME:-$DEFAULT_PHP_MAX_EXECUTION_TIME}

; OPcache settings
opcache.enable=${PHP_OPCACHE_ENABLE:-$DEFAULT_PHP_OPCACHE_ENABLE}
opcache.memory_consumption=${PHP_OPCACHE_MEMORY:-$DEFAULT_PHP_OPCACHE_MEMORY}
opcache.max_accelerated_files=${PHP_OPCACHE_MAX_FILES:-$DEFAULT_PHP_OPCACHE_MAX_FILES}
opcache.validate_timestamps=${PHP_OPCACHE_VALIDATE:-$DEFAULT_PHP_OPCACHE_VALIDATE}

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

# Calculate system resource-based defaults for FPM
calculate_fpm_system_defaults() {
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
    export CALCULATED_MAX_CHILDREN=$((available_memory / 50))
    
    # Ensure reasonable limits
    if [ $CALCULATED_MAX_CHILDREN -lt 5 ]; then
        export CALCULATED_MAX_CHILDREN=5
    elif [ $CALCULATED_MAX_CHILDREN -gt 100 ]; then
        export CALCULATED_MAX_CHILDREN=100
    fi
    
    # Calculate other values based on max_children
    export CALCULATED_START_SERVERS=$((CALCULATED_MAX_CHILDREN / 10))
    [ $CALCULATED_START_SERVERS -lt 2 ] && export CALCULATED_START_SERVERS=2
    
    export CALCULATED_MIN_SPARE=$((CALCULATED_MAX_CHILDREN / 10))
    [ $CALCULATED_MIN_SPARE -lt 1 ] && export CALCULATED_MIN_SPARE=1
    
    export CALCULATED_MAX_SPARE=$((CALCULATED_MAX_CHILDREN / 3))
    [ $CALCULATED_MAX_SPARE -lt 5 ] && export CALCULATED_MAX_SPARE=5
    
    # Log system information
    log "System resources: ${available_memory}MB RAM, ${cpu_cores} CPU cores"
    log "Calculated FPM defaults: max_children=${CALCULATED_MAX_CHILDREN}, start_servers=${CALCULATED_START_SERVERS}"
}

# Generate PHP-FPM www.conf based on environment variables
generate_fpm_conf() {
    local conf_file="/usr/local/etc/php-fpm.d/laravel.conf"
    
    log "Generating PHP-FPM configuration..."
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$conf_file")"
    
    # Calculate system defaults first
    calculate_fpm_system_defaults
    
    # Set values based on environment or calculated defaults
    local pm_type=${FPM_PM:-$DEFAULT_FPM_PM}
    local pm_max_children=${FPM_PM_MAX_CHILDREN:-$CALCULATED_MAX_CHILDREN}
    local pm_start_servers=${FPM_PM_START_SERVERS:-$CALCULATED_START_SERVERS}
    local pm_min_spare_servers=${FPM_PM_MIN_SPARE_SERVERS:-$CALCULATED_MIN_SPARE}
    local pm_max_spare_servers=${FPM_PM_MAX_SPARE_SERVERS:-$CALCULATED_MAX_SPARE}
    local pm_max_requests=${FPM_PM_MAX_REQUESTS:-$DEFAULT_FPM_PM_MAX_REQUESTS}
    local listen_type=${FPM_LISTEN_TYPE:-$DEFAULT_FPM_LISTEN_TYPE}
    
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
    
    # Log configuration source
    log "FPM Configuration source:"
    log "  pm_type: ${pm_type} $([ -n "$FPM_PM" ] && echo "(from env)" || echo "(default)")"
    log "  pm_max_children: ${pm_max_children} $([ -n "$FPM_PM_MAX_CHILDREN" ] && echo "(from env)" || echo "(calculated)")"
    log "  pm_start_servers: ${pm_start_servers} $([ -n "$FPM_PM_START_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    log "  pm_min_spare_servers: ${pm_min_spare_servers} $([ -n "$FPM_PM_MIN_SPARE_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    log "  pm_max_spare_servers: ${pm_max_spare_servers} $([ -n "$FPM_PM_MAX_SPARE_SERVERS" ] && echo "(from env)" || echo "(calculated)")"
    
    cat >> "$conf_file" << EOF
; Process manager configuration
pm = $pm_type
pm.max_children = $pm_max_children
pm.start_servers = $pm_start_servers
pm.min_spare_servers = $pm_min_spare_servers
pm.max_spare_servers = $pm_max_spare_servers
pm.max_requests = $pm_max_requests

; Status and ping pages
pm.status_path = /fpm-status
ping.path = /fpm-ping
EOF

    log "PHP-FPM configuration generated at $conf_file"
    log "FPM Settings: pm=$pm_type, max_children=$pm_max_children, start_servers=$pm_start_servers"
}

# Check and setup Laravel application
setup_laravel() {
    local app_dir=${APP_DIR:-$DEFAULT_APP_DIR}
    local index_html="index.nginx-debian.html"
    
    log "Checking application directory: $app_dir"
    
    # Create directory if it doesn't exist
    if [ ! -d "$app_dir" ]; then
        log "Application directory does not exist. Creating: $app_dir"
        mkdir -p "$app_dir"
    fi

    cd "$app_dir"

    if [ -f "$index_html" ]; then
        log "$index_html found in application directory. Removing it."
        rm -f "$index_html"
    fi
    
    # Check if directory is empty or just has hidden files
    if [ -z "$(ls -A "$app_dir" 2>/dev/null | grep -v '^\.')" ]; then
        log "Application directory is empty. Installing Laravel..."
        
        # Install Laravel using Composer
        composer create-project laravel/laravel . --prefer-dist --no-dev --quiet
        
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
            composer install --no-dev --optimize-autoloader --quiet
            
            # Set proper permissions
            chown -R www-data:www-data "$app_dir"
            chmod -R 755 "$app_dir"
            chmod -R 775 "$app_dir/storage" "$app_dir/bootstrap/cache" 2>/dev/null || true
        fi
    fi
}

# Initialize global PHP configurations
init_php_global_config() {
    log "=== Initializing Global PHP Configuration ==="
    
    # Check for required commands
    check_commands
    
    # Generate PHP configuration
    generate_php_ini
    
    # Generate PHP-FPM configuration
    generate_fpm_conf
    
    # Setup Laravel application if needed
    if [[ "${SETUP_LARAVEL:-true}" == "true" ]]; then
        setup_laravel
    fi
    
    log "=== Global PHP Configuration Complete ==="
}

# Export functions for use in other scripts
export -f log
export -f log_error
export -f check_commands
export -f generate_php_ini
export -f calculate_fpm_system_defaults
export -f generate_fpm_conf
export -f setup_laravel
export -f init_php_global_config

log "Global PHP configuration script loaded successfully"