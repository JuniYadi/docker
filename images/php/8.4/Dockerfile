FROM php:8.4-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libonig-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libreadline-dev \
    unzip \
    nginx \
    supervisor \
    curl \
    procps \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j$(nproc) \
        gd \
        zip \
        pdo \
        pdo_mysql \
        mysqli \
        mbstring \
        xml \
        curl \
        intl \
        bcmath \
        opcache \
        exif \
        pcntl \
        sockets && \
        pecl install redis && docker-php-ext-enable redis && \
        pecl install apcu && docker-php-ext-enable apcu

# Install Composer globally
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy configurations
COPY ./entrypoint.sh /entrypoint.sh

# Create directories with proper ownership
RUN mkdir -p /var/run/php && \
    mkdir -p /var/log/nginx && \
    mkdir -p /run && \
    chown -R www-data:www-data /var/run/php

# Make entrypoint executable
RUN chmod +x /entrypoint.sh
EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]