#!/bin/bash

# Global Nginx VHost Configuration Script
# This script contains reusable configuration functions for Nginx virtual hosts in PHP containers
# It should be sourced by entrypoint scripts to provide consistent behavior

# Ensure all output goes to stdout/stderr for proper Kubernetes logging
set -e

# Global VHost Configuration Variables (can be overridden by environment)
export DEFAULT_VHOST_LISTEN_PORT=${VHOST_LISTEN_PORT:-80}
export DEFAULT_VHOST_SERVER_NAME=${VHOST_SERVER_NAME:-_}
export DEFAULT_VHOST_ROOT=${VHOST_ROOT:-/var/www/html/public}
export DEFAULT_VHOST_INDEX=${VHOST_INDEX:-index.php index.html}
export DEFAULT_VHOST_TYPE=${VHOST_TYPE:-laravel}

# Generate custom virtual host configuration
generate_vhost_config() {
    local vhost_name=${1:-default}
    local vhost_conf="/etc/nginx/conf.d/${vhost_name}.conf"
    
    log "Generating virtual host configuration for: $vhost_name"
    
    # Create directories if they don't exist
    mkdir -p /etc/nginx/conf.d
    
    # Get vhost-specific environment variables or use defaults
    local listen_port_var="VHOST_${vhost_name^^}_LISTEN_PORT"
    local server_name_var="VHOST_${vhost_name^^}_SERVER_NAME"
    local root_var="VHOST_${vhost_name^^}_ROOT"
    local index_var="VHOST_${vhost_name^^}_INDEX"
    local type_var="VHOST_${vhost_name^^}_TYPE"
    local ssl_var="VHOST_${vhost_name^^}_SSL"
    local ssl_cert_var="VHOST_${vhost_name^^}_SSL_CERT"
    local ssl_key_var="VHOST_${vhost_name^^}_SSL_KEY"
    
    local listen_port=$(eval echo \$$listen_port_var)
    local server_name=$(eval echo \$$server_name_var)
    local root_dir=$(eval echo \$$root_var)
    local index_files=$(eval echo \$$index_var)
    local vhost_type=$(eval echo \$$type_var)
    local ssl_enabled=$(eval echo \$$ssl_var)
    local ssl_cert=$(eval echo \$$ssl_cert_var)
    local ssl_key=$(eval echo \$$ssl_key_var)
    
    # Use defaults if not set
    listen_port=${listen_port:-$DEFAULT_VHOST_LISTEN_PORT}
    server_name=${server_name:-$DEFAULT_VHOST_SERVER_NAME}
    root_dir=${root_dir:-${APP_DIR:-/var/www/html}/public}
    index_files=${index_files:-$DEFAULT_VHOST_INDEX}
    vhost_type=${vhost_type:-$DEFAULT_VHOST_TYPE}
    
    # Determine FastCGI pass method
    local fastcgi_pass
    if [[ "${FPM_LISTEN_TYPE:-$DEFAULT_FPM_LISTEN_TYPE}" == "socket" ]]; then
        fastcgi_pass="unix:/var/run/php/php8.4-fpm.sock"
    else
        fastcgi_pass="127.0.0.1:9000"
    fi
    
    # Start generating vhost configuration
    cat > "$vhost_conf" << EOF
server {
    listen $listen_port;
EOF

    # Add SSL configuration if enabled
    if [[ "$ssl_enabled" == "true" && -n "$ssl_cert" && -n "$ssl_key" ]]; then
        cat >> "$vhost_conf" << EOF
    listen 443 ssl http2;
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
EOF
    fi

    cat >> "$vhost_conf" << EOF
    server_name $server_name;
    root $root_dir;
    index $index_files;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

EOF

    # Add custom headers for this vhost if provided
    local custom_headers_var="VHOST_${vhost_name^^}_CUSTOM_HEADERS"
    local custom_headers=$(eval echo \$$custom_headers_var)
    if [ -n "$custom_headers" ]; then
        echo "    # Custom headers for $vhost_name" >> "$vhost_conf"
        echo "$custom_headers" | sed 's/^/    /' >> "$vhost_conf"
        echo "" >> "$vhost_conf"
    fi

    # Generate configuration based on vhost type
    case "$vhost_type" in
        "laravel")
            generate_laravel_vhost_config "$vhost_conf" "$fastcgi_pass"
            ;;
        "wordpress")
            generate_wordpress_vhost_config "$vhost_conf" "$fastcgi_pass"
            ;;
        "symfony")
            generate_symfony_vhost_config "$vhost_conf" "$fastcgi_pass"
            ;;
        "static")
            generate_static_vhost_config "$vhost_conf"
            ;;
        "custom")
            generate_custom_vhost_config "$vhost_conf" "$fastcgi_pass" "$vhost_name"
            ;;
        *)
            log "Unknown vhost type: $vhost_type, using Laravel configuration"
            generate_laravel_vhost_config "$vhost_conf" "$fastcgi_pass"
            ;;
    esac

    # Add common configurations
    generate_common_vhost_config "$vhost_conf" "$fastcgi_pass"

    # Close server block
    echo "}" >> "$vhost_conf"

    log "Virtual host configuration generated: $vhost_conf"
    log "VHost $vhost_name: server_name=$server_name, root=$root_dir, type=$vhost_type"
}

# Generate Laravel-specific configuration
generate_laravel_vhost_config() {
    local vhost_conf="$1"
    local fastcgi_pass="$2"
    
    cat >> "$vhost_conf" << EOF
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
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 180s;
        fastcgi_read_timeout 180s;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

EOF
}

# Generate WordPress-specific configuration
generate_wordpress_vhost_config() {
    local vhost_conf="$1"
    local fastcgi_pass="$2"
    
    cat >> "$vhost_conf" << EOF
    # WordPress specific
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # WordPress rewrite rules
    location ~ ^/wp-content/.*\.php$ {
        deny all;
    }

    # PHP handling
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass $fastcgi_pass;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # FastCGI timeout settings
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 180s;
        fastcgi_read_timeout 180s;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

EOF
}

# Generate Symfony-specific configuration
generate_symfony_vhost_config() {
    local vhost_conf="$1"
    local fastcgi_pass="$2"
    
    cat >> "$vhost_conf" << EOF
    # Symfony specific
    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    # PHP handling
    location ~ ^/index\.php(/|$) {
        fastcgi_pass $fastcgi_pass;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        internal;
    }

    # Return 404 for all other php files not matching the front controller
    location ~ \.php$ {
        return 404;
    }

EOF
}

# Generate static site configuration
generate_static_vhost_config() {
    local vhost_conf="$1"
    
    cat >> "$vhost_conf" << EOF
    # Static site configuration
    location / {
        try_files \$uri \$uri/ =404;
    }

EOF
}

# Generate custom vhost configuration
generate_custom_vhost_config() {
    local vhost_conf="$1"
    local fastcgi_pass="$2"
    local vhost_name="$3"
    
    local custom_config_var="VHOST_${vhost_name^^}_CUSTOM_CONFIG"
    local custom_config=$(eval echo \$$custom_config_var)
    
    if [ -n "$custom_config" ]; then
        echo "    # Custom configuration for $vhost_name" >> "$vhost_conf"
        echo "$custom_config" | sed 's/^/    /' >> "$vhost_conf"
        echo "" >> "$vhost_conf"
    else
        # Fallback to basic PHP configuration
        generate_laravel_vhost_config "$vhost_conf" "$fastcgi_pass"
    fi
}

# Generate common configurations for all vhost types
generate_common_vhost_config() {
    local vhost_conf="$1"
    local fastcgi_pass="$2"
    
    cat >> "$vhost_conf" << EOF
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
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # PHP-FPM status pages (optional, for monitoring)
    location ~ ^/(fpm-status|fpm-ping)$ {
        access_log off;
        fastcgi_pass $fastcgi_pass;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

EOF
}

# Generate multiple virtual hosts from environment variables
generate_multiple_vhosts() {
    log "Checking for multiple virtual host configurations..."
    
    # Look for VHOST_<NAME>_SERVER_NAME environment variables
    for var in $(env | grep '^VHOST_.*_SERVER_NAME=' | cut -d= -f1); do
        local vhost_name=$(echo "$var" | sed 's/VHOST_//' | sed 's/_SERVER_NAME$//' | tr '[:upper:]' '[:lower:]')
        
        # Skip if it's the default vhost (already handled)
        if [ "$vhost_name" != "default" ]; then
            generate_vhost_config "$vhost_name"
        fi
    done
}

# Remove default nginx site if it exists
remove_default_nginx_site() {
    local default_site="/etc/nginx/sites-enabled/default"
    local default_conf="/etc/nginx/conf.d/default.conf"
    
    if [ -f "$default_site" ] || [ -L "$default_site" ]; then
        log "Removing default nginx site configuration"
        rm -f "$default_site"
    fi
    
    if [ -f "$default_conf" ]; then
        log "Removing existing default.conf"
        rm -f "$default_conf"
    fi
}

# Initialize virtual host configurations
init_vhost_config() {
    log "=== Initializing Virtual Host Configuration ==="
    
    # Remove default nginx site
    remove_default_nginx_site
    
    # Always generate default vhost first
    log "Generating default vhost configuration"
    generate_vhost_config "default"
    
    # Generate multiple virtual hosts if configured
    generate_multiple_vhosts
    
    log "=== Virtual Host Configuration Complete ==="
}

# Export functions for use in other scripts
export -f generate_vhost_config
export -f generate_laravel_vhost_config
export -f generate_wordpress_vhost_config
export -f generate_symfony_vhost_config
export -f generate_static_vhost_config
export -f generate_custom_vhost_config
export -f generate_common_vhost_config
export -f generate_multiple_vhosts
export -f remove_default_nginx_site
export -f init_vhost_config

log "Global Nginx VHost configuration script loaded successfully"