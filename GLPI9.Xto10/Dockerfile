# Base
FROM debian:10

# Environment
ENV DEBIAN_FRONTEND=noninteractive

# Update & install packages
RUN apt-get update && apt-get -y dist-upgrade \
    && apt-get -y install \
    apache2 \
    php7.3 \
    php7.3-mysql \
    php7.3-ldap \
    php7.3-xmlrpc \
    php7.3-imap \
    php7.3-curl \
    php7.3-gd \
    php7.3-mbstring \
    php7.3-xml \
    php7.3-intl \
    php7.3-zip \
    php7.3-bz2 \
    php7.3-apcu \
    php7.3-opcache \
    php-cas \
    cron \
    wget \
    ca-certificates \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download and install GLPI
RUN cd /tmp \
    && wget https://github.com/glpi-project/glpi/releases/download/9.4.4/glpi-9.4.4.tgz \
    && tar -xzf glpi-9.4.4.tgz \
    && mv glpi /var/www/html/ \
    && rm /tmp/glpi-9.4.4.tgz

# Copy configuration files
COPY apache.conf /etc/apache2/conf-available/glpi.conf
COPY glpi-php.ini /etc/php/7.3/apache2/conf.d/99-glpi.ini
COPY glpi_cron /etc/cron.d/glpi
COPY foreground.sh /etc/apache2/foreground.sh

# Configure Apache
RUN a2enmod rewrite headers \
    && a2enconf glpi \
    && chmod +x /etc/apache2/foreground.sh \
    && chmod 0644 /etc/cron.d/glpi

# Set permissions
RUN chown -R www-data:www-data /var/www/html/glpi \
    && chmod 755 /var/www/html/glpi

# Ports and Volumes
VOLUME ["/var/www/html/glpi/files", "/var/www/html/glpi/config"]
EXPOSE 80 443

ENTRYPOINT ["/etc/apache2/foreground.sh"]
