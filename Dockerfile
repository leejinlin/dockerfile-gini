FROM alpine:3.21
LABEL maintainer=iamfat@gmail.com

ENV TERM="xterm-color" \
    MAIL_HOST="172.17.0.1" \
    MAIL_FROM="sender@gini" \
    GINI_ENV="production" \
    COMPOSER_PROCESS_TIMEOUT=40000 \
    COMPOSER_HOME="/usr/local/share/composer"

RUN apk update \
    && apk add bash curl gettext jq php83 php83-fpm \
    && apk add php83-session php83-intl php83-gd php83-pdo php83-pdo_mysql php83-pdo_sqlite \
      php83-curl php83-soap php83-sockets php83-phar php83-openssl php83-bcmath php83-ldap php83-posix php83-pcntl \
      php83-ctype php83-iconv php83-gettext php83-mbstring php83-fileinfo php83-zip \
      php83-dom php83-simplexml php83-tokenizer php83-xml php83-xmlreader php83-xmlwriter \
      php83-pecl-yaml php83-pecl-redis php83-pecl-igbinary \
      php83-pecl-amqp php83-pecl-imagick \
      php83-pecl-mcrypt php83-pecl-ssh2 php83-gmp \
      php83-opcache php83-mysqlnd php83-mysqli \
      && sed -i 's/^listen\s*=.*$/listen = 0.0.0.0:9000/' /etc/php83/php-fpm.d/www.conf \
      && echo 'catch_workers_output = yes' >> /etc/php83/php-fpm.d/www.conf \
      && echo 'decorate_workers_output = no' >> /etc/php83/php-fpm.d/www.conf \
      && sed -i 's/^\;error_log\s*=.*$/error_log = \/dev\/stderr/' /etc/php83/php-fpm.conf \
      && sed -i 's/^\;error_log\s*=\s*syslog\s*$/error_log = \/dev\/stderr/' /etc/php83/php.ini \
      && ln -sf /usr/sbin/php-fpm83 /usr/sbin/php-fpm \
      && ln -sf /usr/bin/php83 /usr/bin/php \
    # ZMQ: pecl 版本不兼容 PHP 8，从 GitHub master 编译（含 PHP 8.0-8.3 修复）
    && apk add php83-dev php83-pear build-base zeromq-dev autoconf git \
    && git clone --depth 1 https://github.com/zeromq/php-zmq.git /tmp/php-zmq \
    && cd /tmp/php-zmq && phpize83 && ./configure --with-php-config=php-config83 \
    && make -j$(nproc) && make install \
    && echo "extension=zmq.so" > /etc/php83/conf.d/50-zmq.ini \
    && cd / && rm -rf /tmp/php-zmq \
    && apk del php83-dev php83-pear build-base autoconf \
    && apk add npm && npm install -g less less-plugin-clean-css uglify-js \
    && apk add msmtp && ln -sf /usr/bin/msmtp /usr/sbin/sendmail \
    && apk add git \
    && mkdir -p /usr/local/bin && (curl -sL https://getcomposer.org/installer | php) \
      && mv composer.phar /usr/local/bin/composer \
    && mkdir -p /data/gini-modules && git clone --depth 1 https://github.com/iamfat/gini.git /usr/local/share/gini \
        && cd /usr/local/share/gini && bin/gini composer init -f \
        && /usr/local/bin/composer install --no-dev \
        && bin/gini cache \
    && rm -rf /var/cache/apk/*

ADD msmtprc /etc/msmtprc

EXPOSE 9000

ENV PATH="/usr/local/share/gini/bin:/usr/local/share/composer/vendor/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
GINI_MODULE_BASE_PATH="/data/gini-modules"

ADD start /start
WORKDIR /data/gini-modules
CMD ["/start"]
