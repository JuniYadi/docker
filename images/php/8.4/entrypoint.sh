#!/bin/bash

# Entrypoint for PHP-FPM + Nginx container
set -e

# Configuration variables
PHP_CONFIG_URL=${PHP_CONFIG_URL:-"https://raw.githubusercontent.com/JuniYadi/docker/refs/heads/master/scripts/php.sh"}
NGINX_CONFIG_URL=${NGINX_CONFIG_URL:-"https://raw.githubusercontent.com/JuniYadi/docker/refs/heads/master/scripts/nginx.sh"}
SUPERVISOR_CONFIG_URL=${SUPERVISOR_CONFIG_URL:-"https://raw.githubusercontent.com/JuniYadi/docker/refs/heads/master/scripts/supervisor.sh"}
VHOST_CONFIG_URL=${VHOST_CONFIG_URL:-"https://raw.githubusercontent.com/JuniYadi/docker/refs/heads/master/scripts/nginx-vhost.sh"}

PHP_CONFIG_LOCAL="/tmp/php-global-config.sh"
NGINX_CONFIG_LOCAL="/tmp/nginx-global-config.sh"
SUPERVISOR_CONFIG_LOCAL="/tmp/supervisor-global-config.sh"
VHOST_CONFIG_LOCAL="/tmp/vhost-global-config.sh"

# Simple logging function (before sourcing global config)
simple_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Generic function to fetch configuration files
fetch_config_file() {
    local config_name="$1"
    local config_url="$2"
    local config_local="$3"
    
    simple_log "=== Fetching $config_name Configuration ==="

    if [ -f "$config_local" ]; then
        simple_log "$config_name configuration already exists at $config_local. Deleting old file."
        rm -f "$config_local"
    fi

    if command -v curl >/dev/null 2>&1; then
        simple_log "Downloading $config_name configuration using curl..."
        if curl -fsSL -o "$config_local" "$config_url"; then
            simple_log "$config_name configuration downloaded successfully"
        else
            simple_log "WARNING: Failed to download $config_name config via curl."
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        simple_log "Downloading $config_name configuration using wget..."
        if wget -q -O "$config_local" "$config_url"; then
            simple_log "$config_name configuration downloaded successfully"
        else
            simple_log "WARNING: Failed to download $config_name config via wget."
            return 1
        fi
    else
        simple_log "WARNING: Neither curl nor wget available."
        return 1
    fi
    
    # Validate the downloaded file
    if [[ -f "$config_local" ]] && [[ -s "$config_local" ]]; then
        if head -1 "$config_local" | grep -q "#!/bin/bash"; then
            simple_log "$config_name configuration validated successfully"
            chmod +x "$config_local"
            source "$config_local"
            simple_log "$config_name configuration loaded successfully"
            return 0
        else
            simple_log "WARNING: Downloaded $config_name file is not a valid bash script."
            return 1
        fi
    else
        simple_log "WARNING: Downloaded $config_name file is empty or missing."
        return 1
    fi
}

# Fetch and source global PHP configuration
fetch_global_config() {
    if ! fetch_config_file "PHP" "$PHP_CONFIG_URL" "$PHP_CONFIG_LOCAL"; then
        fetch_fallback_config
    fi
}

# Fetch additional configuration scripts
fetch_nginx_config() {
    if ! fetch_config_file "Nginx" "$NGINX_CONFIG_URL" "$NGINX_CONFIG_LOCAL"; then
        simple_log "WARNING: Failed to fetch Nginx configuration. Nginx will use default settings."
    fi
}

fetch_supervisor_config() {
    if ! fetch_config_file "Supervisor" "$SUPERVISOR_CONFIG_URL" "$SUPERVISOR_CONFIG_LOCAL"; then
        simple_log "WARNING: Failed to fetch Supervisor configuration. Supervisor will use default settings."
    fi
}

fetch_vhost_config() {
    if ! fetch_config_file "VHost" "$VHOST_CONFIG_URL" "$VHOST_CONFIG_LOCAL"; then
        simple_log "WARNING: Failed to fetch VHost configuration. VHost will use default settings."
    fi
}

# Fallback config if download fails
fetch_fallback_config() {
    simple_log "Using fallback global PHP configuration..."
    cat > "$PHP_CONFIG_LOCAL" << 'EOF'
#!/bin/bash
set -e
export PYTHONUNBUFFERED=1
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
init_php_global_config() {
    log "=== Using Fallback PHP Configuration ==="
    log "Global PHP configuration could not be fetched. Using basic fallback."
    log "Consider checking network connectivity or PHP_CONFIG_URL setting."
}
export -f log
export -f log_error
export -f init_php_global_config
EOF
    chmod +x "$PHP_CONFIG_LOCAL"
    source "$PHP_CONFIG_LOCAL"
    simple_log "Fallback configuration loaded"
}

# Entrypoint main logic
main() {
    # Fetch all configuration scripts
    fetch_global_config
    fetch_nginx_config
    fetch_supervisor_config
    fetch_vhost_config
    
    # Now all functions are available from the loaded configuration scripts
    log "=== PHP-FPM + Nginx Container Starting ==="
    log "Starting PHP-FPM + Nginx container..."
    log "Container PID: $$"
    log "Environment: $(printenv | grep -E '^(KUBERNETES|POD_|SERVICE_)' | head -3 || echo 'Not running in Kubernetes')"
    
    # Initialize all configurations
    log "=== Initializing All Configurations ==="
    
    # Initialize PHP configuration (from php.sh)
    if declare -f init_php_global_config >/dev/null; then
        init_php_global_config
    else
        log "WARNING: init_php_global_config function not available, using basic PHP setup"
        check_commands
        generate_php_ini
        generate_fpm_conf
        setup_laravel
    fi
    
    # Initialize Nginx configuration (from nginx.sh)
    if declare -f init_nginx_config >/dev/null; then
        init_nginx_config
    else
        log "WARNING: init_nginx_config function not available, using default Nginx configuration"
    fi
    
    # Initialize VHost configuration (from nginx-vhost.sh)
    if declare -f init_vhost_config >/dev/null; then
        init_vhost_config
    else
        log "WARNING: init_vhost_config function not available, using default VHost configuration"
    fi
    
    # Initialize Supervisor configuration (from supervisor.sh) - Must be last
    if declare -f init_supervisor_config >/dev/null; then
        init_supervisor_config
    else
        log "WARNING: init_supervisor_config function not available, using default Supervisor configuration"
    fi
    
    log "=== All Configurations Initialized ==="
    
    # Final configuration tests
    log "Starting services..."
    log "About to execute supervisord..."
    log "Supervisord config file exists: $([ -f /etc/supervisor/conf.d/supervisord.conf ] && echo 'YES' || echo 'NO')"
    log "PHP-FPM config file exists: $([ -f /usr/local/etc/php-fpm.d/laravel.conf ] && echo 'YES' || echo 'NO')"
    log "Nginx config file exists: $([ -f /etc/nginx/nginx.conf ] && echo 'YES' || echo 'NO')"
    
    log "Testing PHP-FPM configuration..."
    php-fpm -t && log "PHP-FPM configuration test passed" || log_error "PHP-FPM configuration test failed"
    
    log "Testing Nginx configuration..."
    nginx -t && log "Nginx configuration test passed" || log_error "Nginx configuration test failed"
    
    log "Executing supervisord with PID $$"
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
}

main "$@"