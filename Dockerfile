##############################################################################
# Stage 1: 编译 CVE-2026-109618/109619 补丁版 PHP 7.4
##############################################################################
FROM --platform=linux/amd64 alpine:3.15 AS php-builder

# 安装编译依赖（与 Alpine 3.15 php7 包的构建依赖对齐）
RUN apk update && apk add \
    autoconf automake bison build-base curl-dev freetype-dev gd-dev gettext-dev \
    gmp-dev icu-dev libjpeg-turbo-dev libpng-dev libwebp-dev libxml2-dev \
    libxpm-dev libzip-dev musl-dev oniguruma-dev openldap-dev openssl-dev \
    pcre-dev pcre2-dev re2c sqlite-dev yaml-dev zeromq-dev argon2-dev libedit-dev \
    krb5-dev \
    git

# 拉取官方补丁分支
RUN git clone --depth 1 -b PHP-7.4-CVE-2026-109618-109619 \
    https://github.com/php/php-src.git /php-src

# 使用与 Alpine php7 包相同的核心编译参数
RUN cd /php-src && ./buildconf --force && ./configure \
    --build=x86_64-alpine-linux-musl \
    --host=x86_64-alpine-linux-musl \
    --prefix=/usr \
    --program-suffix=7 \
    --libdir=/usr/lib/php7 \
    --datadir=/usr/share/php7 \
    --sysconfdir=/etc/php7 \
    --localstatedir=/var \
    --with-layout=GNU \
    --with-pic \
    --with-config-file-path=/etc/php7 \
    --with-config-file-scan-dir=/etc/php7/conf.d \
    --disable-short-tags \
    --with-libxml \
    --with-openssl \
    --with-kerberos \
    --with-system-ciphers \
    --with-password-argon2 \
    --with-external-pcre \
    --with-libedit \
    --with-zlib \
    --enable-bcmath=shared \
    --enable-ctype=shared \
    --with-curl=shared \
    --enable-dom=shared \
    --enable-fileinfo=shared \
    --enable-gd=shared --with-freetype --with-jpeg --with-webp --with-xpm --disable-gd-jis-conv \
    --with-gettext=shared \
    --with-iconv=shared \
    --enable-intl=shared \
    --enable-json=shared \
    --with-ldap=shared --with-ldap-sasl \
    --enable-mbstring=shared \
    --enable-mysqlnd=shared \
    --with-mysqli=shared,mysqlnd \
    --enable-opcache=shared \
    --enable-pcntl=shared \
    --enable-pdo=shared \
    --with-pdo-mysql=shared,mysqlnd \
    --with-pdo-sqlite=shared \
    --enable-phar=shared \
    --enable-posix=shared \
    --enable-session=shared \
    --enable-simplexml=shared \
    --enable-soap=shared \
    --enable-sockets=shared \
    --with-sqlite3=shared \
    --enable-tokenizer=shared \
    --enable-xml=shared \
    --enable-xmlreader=shared \
    --enable-xmlwriter=shared \
    --with-zip=shared \
    --enable-fpm \
    && make -j$(nproc)

##############################################################################
# Stage 2: 运行时镜像（与原 Dockerfile 一致，仅替换 PHP 二进制）
##############################################################################
FROM --platform=linux/amd64 alpine:3
LABEL maintainer=iamfat@gmail.com

ENV TERM="xterm-color" \
    MAIL_HOST="172.17.0.1" \
    MAIL_FROM="sender@gini" \
    GINI_ENV="production" \
    COMPOSER_PROCESS_TIMEOUT=40000 \
    COMPOSER_HOME="/usr/local/share/composer"

RUN apk update \
    && apk add bash curl gettext jq php7 php7-fpm \
    && apk add php7-session php7-intl php7-gd php7-pdo php7-pdo_mysql php7-pdo_sqlite \
      php7-curl php7-soap php7-sockets php7-json php7-phar php7-openssl php7-bcmath php7-ldap php7-posix php7-pcntl \
      php7-ctype php7-iconv php7-gettext php7-mbstring php7-fileinfo php7-zip php7-zlib \
      php7-dom php7-simplexml php7-tokenizer php7-xml php7-xmlreader php7-xmlwriter \
      php7-pecl-yaml php7-pecl-zmq php7-pecl-redis \
      && sed -i 's/^listen\s*=.*$/listen = 0.0.0.0:9000/' /etc/php7/php-fpm.d/www.conf \
      && echo 'catch_workers_output = yes' >> /etc/php7/php-fpm.d/www.conf \
      && echo 'decorate_workers_output = no' >> /etc/php7/php-fpm.d/www.conf \
      && sed -i 's/^\;error_log\s*=.*$/error_log = \/dev\/stderr/' /etc/php7/php-fpm.conf \
      && sed -i 's/^\;error_log\s*=\s*syslog\s*$/error_log = \/dev\/stderr/' /etc/php7/php.ini \
      && ln -sf /usr/sbin/php-fpm7 /usr/sbin/php-fpm \
      && ln -sf /usr/bin/php7 /usr/bin/php \
    && apk add nodejs-less nodejs-less-plugin-clean-css uglify-js \
    && apk add msmtp && ln -sf /usr/bin/msmtp /usr/sbin/sendmail \
    && apk add git \
    && mkdir -p /usr/local/bin && (curl -sL https://getcomposer.org/installer | php) \
      && mv composer.phar /usr/local/bin/composer \
    && mkdir -p /data/gini-modules && git clone --depth 1 https://github.com/iamfat/gini.git -b 1.13.2 /usr/local/share/gini \
        && cd /usr/local/share/gini && bin/gini composer init -f \
        && /usr/local/bin/composer install --no-dev \
        && bin/gini cache \
    && rm -rf /var/cache/apk/*

# 用编译好的补丁版 PHP 替换 apk 安装的原版
COPY --from=php-builder /php-src/sapi/fpm/php-fpm /usr/sbin/php-fpm7
COPY --from=php-builder /php-src/sapi/cli/php /usr/bin/php7

# apk 的 .so 在 /usr/lib/php7/modules/，源码编译的 PHP 找 /usr/lib/php7/20190902/
RUN ln -sf /usr/lib/php7/modules /usr/lib/php7/20190902

# 固化 session.upload_progress 关闭（双重保险）
RUN echo 'session.upload_progress.enabled=0' > /etc/php7/conf.d/99-cve2026-fix.ini

ADD msmtprc /etc/msmtprc

EXPOSE 9000

ENV PATH="/usr/local/share/gini/bin:/usr/local/share/composer/vendor/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
GINI_MODULE_BASE_PATH="/data/gini-modules"

ADD start /start
WORKDIR /data/gini-modules
CMD ["/start"]
