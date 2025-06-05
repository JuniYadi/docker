#!/bin/bash

# Global Nginx Configuration Script
# This script contains reusable configuration functions for Nginx in PHP containers
# It should be sourced by entrypoint scripts to provide consistent behavior

# Ensure all output goes to stdout/stderr for proper Kubernetes logging
set -e

# Global Nginx Configuration Variables (can be overridden by environment)
export DEFAULT_NGINX_WORKER_PROCESSES=${NGINX_WORKER_PROCESSES:-auto}
export DEFAULT_NGINX_WORKER_CONNECTIONS=${NGINX_WORKER_CONNECTIONS:-1024}
export DEFAULT_NGINX_KEEPALIVE_TIMEOUT=${NGINX_KEEPALIVE_TIMEOUT:-65}
export DEFAULT_NGINX_CLIENT_MAX_BODY_SIZE=${NGINX_CLIENT_MAX_BODY_SIZE:-50M}
export DEFAULT_NGINX_GZIP=${NGINX_GZIP:-on}
export DEFAULT_NGINX_GZIP_COMP_LEVEL=${NGINX_GZIP_COMP_LEVEL:-6}
export DEFAULT_NGINX_SERVER_TOKENS=${NGINX_SERVER_TOKENS:-off}

# Generate main nginx.conf
generate_nginx_conf() {
    local nginx_conf="/etc/nginx/nginx.conf"
    local backup_conf="/etc/nginx/nginx.conf.backup"
    
    log "Generating Nginx main configuration..."
    
    # Backup original config if it exists and no backup exists
    if [ -f "$nginx_conf" ] && [ ! -f "$backup_conf" ]; then
        log "Backing up original nginx.conf to nginx.conf.backup"
        cp "$nginx_conf" "$backup_conf"
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$nginx_conf")"
    
    cat > "$nginx_conf" << EOF
user www-data;
worker_processes ${NGINX_WORKER_PROCESSES:-$DEFAULT_NGINX_WORKER_PROCESSES};
pid /run/nginx.pid;

events {
    worker_connections ${NGINX_WORKER_CONNECTIONS:-$DEFAULT_NGINX_WORKER_CONNECTIONS};
    use epoll;
    multi_accept on;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout ${NGINX_KEEPALIVE_TIMEOUT:-$DEFAULT_NGINX_KEEPALIVE_TIMEOUT};
    types_hash_max_size 2048;
    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE:-$DEFAULT_NGINX_CLIENT_MAX_BODY_SIZE};

    # Security headers
    server_tokens ${NGINX_SERVER_TOKENS:-$DEFAULT_NGINX_SERVER_TOKENS};

    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format json_combined escape=json
        '{'
            '"time_local":"\$time_local",'
            '"remote_addr":"\$remote_addr",'
            '"remote_user":"\$remote_user",'
            '"request":"\$request",'
            '"status": "\$status",'
            '"body_bytes_sent":"\$body_bytes_sent",'
            '"request_time":"\$request_time",'
            '"http_referrer":"\$http_referer",'
            '"http_user_agent":"\$http_user_agent",'
            '"http_x_forwarded_for":"\$http_x_forwarded_for"'
        '}';

    # Logging
    access_log ${NGINX_ACCESS_LOG:-/dev/stdout} ${NGINX_LOG_FORMAT:-json_combined};
    error_log ${NGINX_ERROR_LOG:-/dev/stderr} ${NGINX_ERROR_LOG_LEVEL:-warn};

EOF

    # Add gzip configuration if enabled
    if [[ "${NGINX_GZIP:-$DEFAULT_NGINX_GZIP}" == "on" ]]; then
        cat >> "$nginx_conf" << EOF
    # Gzip compression
    gzip ${NGINX_GZIP:-$DEFAULT_NGINX_GZIP};
    gzip_vary on;
    gzip_comp_level ${NGINX_GZIP_COMP_LEVEL:-$DEFAULT_NGINX_GZIP_COMP_LEVEL};
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        application/xml
        image/svg+xml;

EOF
    fi

    # Add custom nginx configuration if provided
    if [ -n "$NGINX_CUSTOM_CONFIG" ]; then
        echo "    # Custom configuration" >> "$nginx_conf"
        echo "$NGINX_CUSTOM_CONFIG" | sed 's/^/    /' >> "$nginx_conf"
        echo "" >> "$nginx_conf"
    fi

    cat >> "$nginx_conf" << EOF
    # VHost configuration
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

    log "Nginx main configuration generated at $nginx_conf"
    log "Nginx settings: worker_processes=${NGINX_WORKER_PROCESSES:-$DEFAULT_NGINX_WORKER_PROCESSES}, worker_connections=${NGINX_WORKER_CONNECTIONS:-$DEFAULT_NGINX_WORKER_CONNECTIONS}"
}

# Generate default site configuration
generate_nginx_default_site() {
    local site_conf="/etc/nginx/conf.d/default.conf"
    local app_dir=${APP_DIR:-$DEFAULT_APP_DIR}
    
    log "Generating Nginx default site configuration..."
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$site_conf")"
    
    # Determine FastCGI pass method
    local fastcgi_pass
    if [[ "${FPM_LISTEN_TYPE:-$DEFAULT_FPM_LISTEN_TYPE}" == "socket" ]]; then
        fastcgi_pass="unix:/var/run/php/php8.4-fpm.sock"
    else
        fastcgi_pass="127.0.0.1:9000"
    fi
    
    cat > "$site_conf" << EOF
server {
    listen ${NGINX_LISTEN_PORT:-80};
    server_name ${NGINX_SERVER_NAME:-_};
    root ${app_dir}/public;
    index ${NGINX_INDEX_FILES:-index.php index.html};

    # Security headers
    add_header X-Frame-Options "${NGINX_X_FRAME_OPTIONS:-SAMEORIGIN}" always;
    add_header X-Content-Type-Options "${NGINX_X_CONTENT_TYPE_OPTIONS:-nosniff}" always;
    add_header X-XSS-Protection "${NGINX_X_XSS_PROTECTION:-1; mode=block}" always;

EOF

    # Add custom security headers if provided
    if [ -n "$NGINX_CUSTOM_HEADERS" ]; then
        echo "    # Custom headers" >> "$site_conf"
        echo "$NGINX_CUSTOM_HEADERS" | sed 's/^/    /' >> "$site_conf"
        echo "" >> "$site_conf"
    fi

    cat >> "$site_conf" << EOF
    # Laravel specific
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP handling
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass $fastcgi_pass;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        include fastcgi_params;
        
        # FastCGI timeout settings
        fastcgi_connect_timeout ${NGINX_FASTCGI_CONNECT_TIMEOUT:-60s};
        fastcgi_send_timeout ${NGINX_FASTCGI_SEND_TIMEOUT:-180s};
        fastcgi_read_timeout ${NGINX_FASTCGI_READ_TIMEOUT:-180s};
        fastcgi_buffer_size ${NGINX_FASTCGI_BUFFER_SIZE:-128k};
        fastcgi_buffers ${NGINX_FASTCGI_BUFFERS:-4 256k};
        fastcgi_busy_buffers_size ${NGINX_FASTCGI_BUSY_BUFFERS_SIZE:-256k};
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Deny access to sensitive files
    location ~ /(?:web\.config|\.htaccess|\.env) {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Handle static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires ${NGINX_STATIC_EXPIRES:-1y};
        add_header Cache-Control "${NGINX_STATIC_CACHE_CONTROL:-public, immutable}";
        access_log off;
    }

EOF

    # Add FPM status pages if enabled
    if [[ "${NGINX_FPM_STATUS_ENABLED:-true}" == "true" ]]; then
        cat >> "$site_conf" << EOF
    # PHP-FPM status pages (optional, for monitoring)
    location ~ ^/(fpm-status|fpm-ping)$ {
        access_log off;
        fastcgi_pass $fastcgi_pass;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

EOF
    fi

    # Add custom location blocks if provided
    if [ -n "$NGINX_CUSTOM_LOCATIONS" ]; then
        echo "    # Custom locations" >> "$site_conf"
        echo "$NGINX_CUSTOM_LOCATIONS" | sed 's/^/    /' >> "$site_conf"
        echo "" >> "$site_conf"
    fi

    echo "}" >> "$site_conf"

    log "Nginx default site configuration generated at $site_conf"
    log "FastCGI pass: $fastcgi_pass"
}

# Initialize Nginx configurations
init_nginx_config() {
    log "=== Initializing Nginx Configuration ==="
    
    # Generate main nginx configuration
    generate_nginx_conf
    
    # Generate default site configuration
    generate_nginx_default_site
    
    # Test nginx configuration
    if command -v nginx >/dev/null 2>&1; then
        log "Testing Nginx configuration..."
        if nginx -t 2>/dev/null; then
            log "Nginx configuration test passed"
        else
            log_error "Nginx configuration test failed"
            nginx -t || true
        fi
    else
        log "WARNING: nginx command not found, skipping configuration test"
    fi
    
    log "=== Nginx Configuration Complete ==="
}

# Export functions for use in other scripts
export -f generate_nginx_conf
export -f generate_nginx_default_site
export -f init_nginx_config

log "Global Nginx configuration script loaded successfully"