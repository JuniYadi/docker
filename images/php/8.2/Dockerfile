FROM unit:1.32.0-php8.3

# Create web directory and phpinfo file
RUN mkdir -p /var/www/html && \
    echo '<?php phpinfo(); ?>' > /var/www/html/index.php && \
    chown -R unit:unit /var/www/html

# Copy Unit configuration
COPY unit-config.json /docker-entrypoint.d/

EXPOSE 80

CMD ["unitd", "--no-daemon", "--control", "unix:/var/run/control.sock"]