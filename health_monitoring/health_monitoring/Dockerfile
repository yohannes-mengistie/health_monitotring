FROM php:8.3-fpm-alpine AS base

RUN apk add --no-cache \
        bash \
        nginx \
        supervisor \
        gettext \
        git \
        curl \
        icu-dev \
        libzip-dev \
        libpng-dev \
        oniguruma-dev \
        postgresql-dev \
        autoconf \
        g++ \
        make \
    && docker-php-ext-install -j$(nproc) \
        pdo \
        pdo_pgsql \
        pdo_mysql \
        mbstring \
        bcmath \
        gd \
        zip \
        intl \
        pcntl \
        exif \
    && apk del autoconf g++ make \
    && rm -rf /var/cache/apk/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY composer.json composer.lock ./
RUN composer install \
        --no-dev \
        --no-scripts \
        --no-autoloader \
        --prefer-dist \
        --no-interaction

COPY . .

RUN composer dump-autoload --optimize --no-dev --classmap-authoritative \
    && mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

COPY docker/nginx.conf.template /etc/nginx/nginx.conf.template
COPY docker/php-fpm-pool.conf   /usr/local/etc/php-fpm.d/zz-app.conf
COPY docker/supervisord.conf    /etc/supervisord.conf
COPY docker/start-web.sh        /usr/local/bin/start-web
RUN chmod +x /usr/local/bin/start-web

ENV PORT=8080
EXPOSE 8080

CMD ["start-web"]
