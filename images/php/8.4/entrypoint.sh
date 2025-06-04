#!/bin/bash

# Entrypoint for PHP-FPM + Nginx container
set -e

# Configuration variables
PHP_CONFIG_URL=${PHP_CONFIG_URL:-"https://raw.githubusercontent.com/JuniYadi/docker/refs/heads/master/scripts/php.sh"}
PHP_CONFIG_LOCAL="/tmp/php-global-config.sh"

# Simple logging function (before sourcing global config)
simple_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Fetch and source global PHP configuration
fetch_global_config() {
    simple_log "=== Fetching Global PHP Configuration ==="
    if command -v curl >/dev/null 2>&1; then
        simple_log "Downloading global PHP configuration using curl..."
        if curl -fsSL -o "$PHP_CONFIG_LOCAL" "$PHP_CONFIG_URL"; then
            simple_log "Global PHP configuration downloaded successfully"
        else
            simple_log "WARNING: Failed to download global config via curl. Using fallback method."
            fetch_fallback_config
        fi
    elif command -v wget >/dev/null 2>&1; then
        simple_log "Downloading global PHP configuration using wget..."
        if wget -q -O "$PHP_CONFIG_LOCAL" "$PHP_CONFIG_URL"; then
            simple_log "Global PHP configuration downloaded successfully"
        else
            simple_log "WARNING: Failed to download global config via wget. Using fallback method."
            fetch_fallback_config
        fi
    else
        simple_log "WARNING: Neither curl nor wget available. Using fallback method."
        fetch_fallback_config
    fi
    # Validate the downloaded file
    if [[ -f "$PHP_CONFIG_LOCAL" ]] && [[ -s "$PHP_CONFIG_LOCAL" ]]; then
        if head -1 "$PHP_CONFIG_LOCAL" | grep -q "#!/bin/bash"; then
            simple_log "Global PHP configuration validated successfully"
            chmod +x "$PHP_CONFIG_LOCAL"
            source "$PHP_CONFIG_LOCAL"
            simple_log "Global PHP configuration loaded successfully"
            return 0
        else
            simple_log "WARNING: Downloaded file is not a valid bash script. Using fallback."
            fetch_fallback_config
        fi
    else
        simple_log "WARNING: Downloaded file is empty or missing. Using fallback."
        fetch_fallback_config
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
    fetch_global_config
    # Now all functions (log, log_error, check_commands, generate_php_ini, generate_fpm_conf, setup_laravel, etc) are available
    log "=== PHP-FPM + Nginx Container Starting ==="
    log "Starting PHP-FPM + Nginx container..."
    log "Container PID: $$"
    log "Environment: $(printenv | grep -E '^(KUBERNETES|POD_|SERVICE_)' | head -3 || echo 'Not running in Kubernetes')"
    check_commands
    generate_php_ini
    generate_fpm_conf
    setup_laravel
    log "Starting services..."
    log "About to execute supervisord..."
    log "Supervisord config file exists: $([ -f /etc/supervisor/conf.d/supervisord.conf ] && echo 'YES' || echo 'NO')"
    log "PHP-FPM config file exists: $([ -f /usr/local/etc/php-fpm.d/www.conf ] && echo 'YES' || echo 'NO')"
    log "Nginx config file exists: $([ -f /etc/nginx/nginx.conf ] && echo 'YES' || echo 'NO')"
    log "Testing PHP-FPM configuration..."
    php-fpm -t && log "PHP-FPM configuration test passed" || log_error "PHP-FPM configuration test failed"
    log "Testing Nginx configuration..."
    nginx -t && log "Nginx configuration test passed" || log_error "Nginx configuration test failed"
    log "Executing supervisord with PID $$"
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
}

main "$@"