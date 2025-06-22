FROM debian:12

# Atualiza repositórios e instala Apache2 + PHP 8.2 + extensões
RUN apt-get update && apt-get install -y \
    apache2 \
    php8.2 \
    libapache2-mod-php8.2 \
    php8.2-mysql \
    php8.2-gd \
    php8.2-xml \
    php8.2-zip \
    php8.2-mbstring \
    php8.2-intl \
    php8.2-ldap \
    php8.2-bz2 \
    php8.2-curl \
    php8.2-opcache \
    php8.2-cli \
    php8.2-common \
    mariadb-client \
    wget \
    unzip \
    rsync \
    sudo \
    && a2enmod rewrite \
    && a2enmod php8.2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Baixa e instala GLPI 10.0.18
RUN cd /var/www/html && \
    wget https://github.com/glpi-project/glpi/releases/download/10.0.18/glpi-10.0.18.tgz && \
    tar -xzf glpi-10.0.18.tgz && \
    rm glpi-10.0.18.tgz && \
    chown -R www-data:www-data /var/www/html/glpi && \
    chmod -R 755 /var/www/html/glpi

# Configura Apache para GLPI
RUN echo '<VirtualHost *:80>\n\
    DocumentRoot /var/www/html/glpi\n\
    <Directory /var/www/html/glpi>\n\
        AllowOverride All\n\
        Require all granted\n\
    </Directory>\n\
    ErrorLog ${APACHE_LOG_DIR}/error.log\n\
    CustomLog ${APACHE_LOG_DIR}/access.log combined\n\
</VirtualHost>' > /etc/apache2/sites-available/000-default.conf

# Define diretório de trabalho
WORKDIR /var/www/html/glpi

# Configura entrada do container
CMD ["apache2ctl", "-D", "FOREGROUND"]

# Expõe porta
EXPOSE 80
