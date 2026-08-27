FROM php:8.3-fpm-bookworm

ARG MOODLE_BRANCH=MOODLE_502_STABLE

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        libxml2-dev \
        libzip-dev \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        curl \
        exif \
        gd \
        intl \
        mbstring \
        opcache \
        pcntl \
        pgsql \
        pdo_pgsql \
        soap \
        zip \
    && git clone --depth 1 --branch "${MOODLE_BRANCH}" https://github.com/moodle/moodle.git /usr/src/moodle \
    && rm -rf /usr/src/moodle/.git \
    && apt-get purge -y --auto-remove git \
    && rm -rf /var/lib/apt/lists/*

COPY php.ini /usr/local/etc/php/conf.d/99-1upmoodleserve.ini

RUN mkdir -p /var/moodledata /var/www/html \
    && chown -R www-data:www-data /var/moodledata /var/www/html /usr/src/moodle

COPY docker-entrypoint.sh /usr/local/bin/1upmoodleserve-moodle-entrypoint

RUN chmod +x /usr/local/bin/1upmoodleserve-moodle-entrypoint

ENTRYPOINT ["1upmoodleserve-moodle-entrypoint"]
CMD ["php-fpm"]
