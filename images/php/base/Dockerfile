FROM unit:1.34.2-php8.4

ENV TZ="Asia/Jakarta"

# Install additional packages for CLI operations
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create web directory and phpinfo file
RUN mkdir -p /var/www/html && \
    echo '<?php phpinfo(); ?>' > /var/www/html/index.php && \
    chown -R unit:unit /var/www/html

# Copy Unit configuration
COPY unit-config.json /docker-entrypoint.d/config.json

EXPOSE 80

CMD ["unitd", "--no-daemon", "--control", "unix:/var/run/control.sock"]
