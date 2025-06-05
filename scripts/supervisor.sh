#!/bin/bash

# Global Supervisor Configuration Script
# This script contains reusable configuration functions for Supervisor in PHP containers
# It should be sourced by entrypoint scripts to provide consistent behavior

# Ensure all output goes to stdout/stderr for proper Kubernetes logging
set -e

# Global Supervisor Configuration Variables (can be overridden by environment)
export DEFAULT_SUPERVISOR_NODAEMON=${SUPERVISOR_NODAEMON:-true}
export DEFAULT_SUPERVISOR_SILENT=${SUPERVISOR_SILENT:-true}
export DEFAULT_SUPERVISOR_LOGFILE=${SUPERVISOR_LOGFILE:-/dev/stdout}
export DEFAULT_SUPERVISOR_PIDFILE=${SUPERVISOR_PIDFILE:-/tmp/supervisord.pid}
export DEFAULT_SUPERVISOR_LOGLEVEL=${SUPERVISOR_LOGLEVEL:-info}

# Program-specific defaults
export DEFAULT_NGINX_AUTOSTART=${NGINX_AUTOSTART:-true}
export DEFAULT_NGINX_AUTORESTART=${NGINX_AUTORESTART:-true}
export DEFAULT_PHP_FPM_AUTOSTART=${PHP_FPM_AUTOSTART:-true}
export DEFAULT_PHP_FPM_AUTORESTART=${PHP_FPM_AUTORESTART:-true}

# Generate supervisord main configuration
generate_supervisor_conf() {
    local supervisor_conf="/etc/supervisor/conf.d/supervisord.conf"
    local backup_conf="/etc/supervisor/conf.d/supervisord.conf.backup"
    
    log "Generating Supervisor configuration..."
    
    # Backup original config if it exists and no backup exists
    if [ -f "$supervisor_conf" ] && [ ! -f "$backup_conf" ]; then
        log "Backing up original supervisord.conf to supervisord.conf.backup"
        cp "$supervisor_conf" "$backup_conf"
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$supervisor_conf")"
    
    cat > "$supervisor_conf" << EOF
[supervisord]
nodaemon=${SUPERVISOR_NODAEMON:-$DEFAULT_SUPERVISOR_NODAEMON}
silent=${SUPERVISOR_SILENT:-$DEFAULT_SUPERVISOR_SILENT}
logfile=${SUPERVISOR_LOGFILE:-$DEFAULT_SUPERVISOR_LOGFILE}
logfile_maxbytes=${SUPERVISOR_LOGFILE_MAXBYTES:-0}
pidfile=${SUPERVISOR_PIDFILE:-$DEFAULT_SUPERVISOR_PIDFILE}
loglevel=${SUPERVISOR_LOGLEVEL:-$DEFAULT_SUPERVISOR_LOGLEVEL}

EOF

    # Add custom supervisord configuration if provided
    if [ -n "$SUPERVISOR_CUSTOM_CONFIG" ]; then
        echo "# Custom supervisord configuration" >> "$supervisor_conf"
        echo "$SUPERVISOR_CUSTOM_CONFIG" >> "$supervisor_conf"
        echo "" >> "$supervisor_conf"
    fi

    log "Supervisor main configuration generated at $supervisor_conf"
}

# Generate nginx program configuration
generate_nginx_program() {
    local supervisor_conf="/etc/supervisor/conf.d/supervisord.conf"
    
    log "Adding Nginx program to Supervisor configuration..."
    
    cat >> "$supervisor_conf" << EOF
[program:nginx]
command=${NGINX_COMMAND:-nginx -g "daemon off;"}
autostart=${NGINX_AUTOSTART:-$DEFAULT_NGINX_AUTOSTART}
autorestart=${NGINX_AUTORESTART:-$DEFAULT_NGINX_AUTORESTART}
stdout_logfile=${NGINX_STDOUT_LOGFILE:-/dev/stdout}
stdout_logfile_maxbytes=${NGINX_STDOUT_LOGFILE_MAXBYTES:-0}
stderr_logfile=${NGINX_STDERR_LOGFILE:-/dev/stderr}
stderr_logfile_maxbytes=${NGINX_STDERR_LOGFILE_MAXBYTES:-0}
priority=${NGINX_PRIORITY:-100}
startsecs=${NGINX_STARTSECS:-1}
startretries=${NGINX_STARTRETRIES:-3}

EOF

    # Add custom nginx program configuration if provided
    if [ -n "$NGINX_SUPERVISOR_CUSTOM_CONFIG" ]; then
        echo "# Custom nginx program configuration" >> "$supervisor_conf"
        echo "$NGINX_SUPERVISOR_CUSTOM_CONFIG" | sed 's/^//' >> "$supervisor_conf"
        echo "" >> "$supervisor_conf"
    fi

    log "Nginx program configuration added"
}

# Generate php-fpm program configuration
generate_php_fpm_program() {
    local supervisor_conf="/etc/supervisor/conf.d/supervisord.conf"
    
    log "Adding PHP-FPM program to Supervisor configuration..."
    
    cat >> "$supervisor_conf" << EOF
[program:php-fpm]
command=${PHP_FPM_COMMAND:-php-fpm -F}
autostart=${PHP_FPM_AUTOSTART:-$DEFAULT_PHP_FPM_AUTOSTART}
autorestart=${PHP_FPM_AUTORESTART:-$DEFAULT_PHP_FPM_AUTORESTART}
stdout_logfile=${PHP_FPM_STDOUT_LOGFILE:-/dev/stdout}
stdout_logfile_maxbytes=${PHP_FPM_STDOUT_LOGFILE_MAXBYTES:-0}
stderr_logfile=${PHP_FPM_STDERR_LOGFILE:-/dev/stderr}
stderr_logfile_maxbytes=${PHP_FPM_STDERR_LOGFILE_MAXBYTES:-0}
priority=${PHP_FPM_PRIORITY:-200}
startsecs=${PHP_FPM_STARTSECS:-1}
startretries=${PHP_FPM_STARTRETRIES:-3}

EOF

    # Add custom php-fpm program configuration if provided
    if [ -n "$PHP_FPM_SUPERVISOR_CUSTOM_CONFIG" ]; then
        echo "# Custom php-fpm program configuration" >> "$supervisor_conf"
        echo "$PHP_FPM_SUPERVISOR_CUSTOM_CONFIG" | sed 's/^//' >> "$supervisor_conf"
        echo "" >> "$supervisor_conf"
    fi

    log "PHP-FPM program configuration added"
}

# Generate additional programs from environment variables
generate_additional_programs() {
    local supervisor_conf="/etc/supervisor/conf.d/supervisord.conf"
    
    # Check for additional programs defined in environment variables
    # Format: SUPERVISOR_PROGRAM_<NAME>_COMMAND=command
    for var in $(env | grep '^SUPERVISOR_PROGRAM_.*_COMMAND=' | cut -d= -f1); do
        local program_name=$(echo "$var" | sed 's/SUPERVISOR_PROGRAM_//' | sed 's/_COMMAND$//' | tr '[:upper:]' '[:lower:]')
        local command_var="SUPERVISOR_PROGRAM_${program_name^^}_COMMAND"
        local command=$(eval echo \$$command_var)
        
        if [ -n "$command" ]; then
            log "Adding custom program '$program_name' to Supervisor configuration..."
            
            # Get program-specific configuration or use defaults
            local autostart_var="SUPERVISOR_PROGRAM_${program_name^^}_AUTOSTART"
            local autorestart_var="SUPERVISOR_PROGRAM_${program_name^^}_AUTORESTART"
            local priority_var="SUPERVISOR_PROGRAM_${program_name^^}_PRIORITY"
            local startsecs_var="SUPERVISOR_PROGRAM_${program_name^^}_STARTSECS"
            local startretries_var="SUPERVISOR_PROGRAM_${program_name^^}_STARTRETRIES"
            local stdout_logfile_var="SUPERVISOR_PROGRAM_${program_name^^}_STDOUT_LOGFILE"
            local stderr_logfile_var="SUPERVISOR_PROGRAM_${program_name^^}_STDERR_LOGFILE"
            
            local autostart=$(eval echo \$$autostart_var)
            local autorestart=$(eval echo \$$autorestart_var)
            local priority=$(eval echo \$$priority_var)
            local startsecs=$(eval echo \$$startsecs_var)
            local startretries=$(eval echo \$$startretries_var)
            local stdout_logfile=$(eval echo \$$stdout_logfile_var)
            local stderr_logfile=$(eval echo \$$stderr_logfile_var)
            
            cat >> "$supervisor_conf" << EOF
[program:$program_name]
command=$command
autostart=${autostart:-true}
autorestart=${autorestart:-true}
stdout_logfile=${stdout_logfile:-/dev/stdout}
stdout_logfile_maxbytes=0
stderr_logfile=${stderr_logfile:-/dev/stderr}
stderr_logfile_maxbytes=0
priority=${priority:-300}
startsecs=${startsecs:-1}
startretries=${startretries:-3}

EOF
            
            log "Custom program '$program_name' configuration added"
        fi
    done
}

# Initialize Supervisor configurations
init_supervisor_config() {
    log "=== Initializing Supervisor Configuration ==="
    
    # Generate main supervisor configuration
    generate_supervisor_conf
    
    # Generate program configurations
    generate_nginx_program
    generate_php_fpm_program
    
    # Generate additional programs if any
    generate_additional_programs
    
    # Test supervisor configuration if supervisord is available
    if command -v supervisord >/dev/null 2>&1; then
        log "Testing Supervisor configuration..."
        local supervisor_conf="/etc/supervisor/conf.d/supervisord.conf"
        if supervisord -c "$supervisor_conf" -t 2>/dev/null; then
            log "Supervisor configuration test passed"
        else
            log_error "Supervisor configuration test failed"
            supervisord -c "$supervisor_conf" -t || true
        fi
    else
        log "WARNING: supervisord command not found, skipping configuration test"
    fi
    
    log "=== Supervisor Configuration Complete ==="
    log "Supervisor will manage: nginx, php-fpm"
    
    # Log additional programs if any
    local additional_programs=$(env | grep '^SUPERVISOR_PROGRAM_.*_COMMAND=' | cut -d= -f1 | sed 's/SUPERVISOR_PROGRAM_//' | sed 's/_COMMAND$//' | tr '[:upper:]' '[:lower:]' | tr '\n' ', ' | sed 's/, $//')
    if [ -n "$additional_programs" ]; then
        log "Additional programs: $additional_programs"
    fi
}

# Export functions for use in other scripts
export -f generate_supervisor_conf
export -f generate_nginx_program
export -f generate_php_fpm_program
export -f generate_additional_programs
export -f init_supervisor_config

log "Global Supervisor configuration script loaded successfully"