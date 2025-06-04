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
        sockets

# Install Redis extension
RUN pecl install redis \
    && docker-php-ext-enable redis

# Install APCu (optional but recommended for caching)
RUN pecl install apcu \
    && docker-php-ext-enable apcu

# Install Composer globally
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy configurations
COPY ./entrypoint.sh /entrypoint.sh
COPY conf/nginx.conf /etc/nginx/sites-available/default
COPY conf/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY conf/php.ini /usr/local/etc/php/conf.d/php-custom.ini

# Create a non-root user
RUN groupadd -g 1000 www && \
    useradd -u 1000 -ms /bin/bash -g www www

# Create directory for PHP-FPM socket with proper ownership
RUN mkdir -p /var/run/php && \
    chown -R www:www /var/run/php && \
    chown -R www:www /var/www && \
    rm -rf /var/www/html

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

EXPOSE 80
USER www

ENTRYPOINT ["/entrypoint.sh"]