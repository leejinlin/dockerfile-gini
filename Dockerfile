##############################################################################
# Stage 1: 编译 CVE-2026-109618/109619 补丁版 PHP 7.4 (Ubuntu/glibc)
##############################################################################
FROM --platform=linux/amd64 ubuntu:20.04 AS php-builder

ENV DEBIAN_FRONTEND=noninteractive

# 允许过期签名的仓库（Ubuntu 20.04 已 EOL，签名可能过期）
RUN apt-get -q update -o Acquire::AllowInsecureRepositories=true \
        -o Acquire::AllowDowngradeToInsecureRepositories=true 2>/dev/null; \
    apt-get install -yq --allow-unauthenticated \
        build-essential autoconf bison re2c git pkg-config \
        libxml2-dev libssl-dev libcurl4-openssl-dev libpng-dev libjpeg-dev \
        libfreetype6-dev libwebp-dev libxpm-dev libzip-dev libonig-dev \
        libicu-dev libldap2-dev libsasl2-dev libsqlite3-dev libedit-dev \
        libkrb5-dev libpcre2-dev libargon2-dev zlib1g-dev \
    || true

# 拉取官方补丁分支
RUN git clone --depth 1 -b PHP-7.4-CVE-2026-109618-109619 \
    https://github.com/php/php-src.git /php-src

# 使用与 Ubuntu 20.04 php7.4 包对齐的编译参数
RUN cd /php-src && ./buildconf --force && ./configure \
    --prefix=/usr \
    --with-config-file-path=/etc/php/7.4/cli \
    --with-config-file-scan-dir=/etc/php/7.4/cli/conf.d \
    --libdir=/usr/lib/php \
    --datadir=/usr/share/php/7.4 \
    --with-layout=GNU \
    --with-pic \
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
FROM --platform=linux/amd64 ubuntu:20.04
LABEL maintainer=maintain@geneegroup.com

ENV DEBIAN_FRONTEND=noninteractive \
    TERM="xterm-color" \
    MAIL_HOST="172.17.0.1" \
    MAIL_FROM="sender@gini" \
    GINI_ENV="production" \
    COMPOSER_PROCESS_TIMEOUT=40000 \
    APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 \
    COMPOSER_HOME="/usr/local/share/composer"

RUN apt-get -q update && \
    # Install Locales
    apt-get install -yq locales gettext && \
        sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
        sed -i 's/# zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen && \
        locale-gen && \
        /usr/sbin/update-locale LANG="en_US.UTF-8" LANGUAGE="en_US:en" && \
    # Install PHP
    apt-get install -yq php7.4-fpm php7.4-cli && \
        sed -i 's/^listen\s*=.*$/listen = 0.0.0.0:9000/' /etc/php/7.4/fpm/pool.d/www.conf && \
        echo 'catch_workers_output = yes' >> /etc/php/7.4/fpm/pool.d/www.conf && \
        sed -i 's/^error_log\s*=.*$/error_log = \/dev\/stderr/' /etc/php/7.4/fpm/php-fpm.conf && \
        sed -i 's/^\;error_log\s*=\s*syslog\s*$/error_log = \/dev\/stderr/' /etc/php/7.4/fpm/php.ini && \
    # Install PHP modules
    apt-get install -yq php7.4-intl php7.4-gd php7.4-mysqlnd php7.4-redis \
        php7.4-sqlite php7.4-curl php7.4-zip php7.4-mbstring php7.4-ldap php7.4-yaml \
        php7.4-zmq php7.4-xml php7.4-xmlreader php7.4-xmlwriter php7.4-soap && \
    # Install NodeJS
    apt-get install -yq curl && \
    curl -sL https://deb.nodesource.com/setup_16.x | bash - && \
        apt-get install -yq nodejs && \
        npm install -g less less-plugin-clean-css uglify-js && \
    # Install msmtp-mta
    apt-get install -yq msmtp-mta && \
    # Clean Up
    apt-get -yq --purge autoremove software-properties-common && \
    apt-get -yq autoclean && apt-get -yq clean

RUN apt-get install -yq git && \
    # Install Composer
    mkdir -p /usr/local/bin && (curl -sL https://getcomposer.org/installer | php) && \
        mv composer.phar /usr/local/bin/composer && \
        echo 'export PATH="/usr/local/share/composer/vendor/bin:$PATH"' >> /etc/profile.d/composer.sh && \
    # Install Gini
    mkdir -p /usr/local/share && git clone https://github.com/iamfat/gini /usr/local/share/gini \
        && cd /usr/local/share/gini && bin/gini composer init -f \
        && /usr/local/bin/composer update --prefer-dist --no-dev \
        && mkdir -p /data/gini-modules && \
    # Clean Up
    apt-get -yq --purge autoremove git && \
    apt-get -yq autoclean && apt-get -yq clean

# 用编译好的补丁版 PHP 替换 apt 安装的原版
COPY --from=php-builder /php-src/sapi/fpm/php-fpm /usr/sbin/php-fpm7.4
COPY --from=php-builder /php-src/sapi/cli/php /usr/bin/php7.4

# apt 的 .so 在 /usr/lib/php/20190902/，与源码编译的 extension_dir 一致，无需额外链接

# 固化 session.upload_progress 关闭（双重保险，FPM 和 CLI 都生效）
RUN echo 'session.upload_progress.enabled=0' > /etc/php/7.4/mods-available/cve2026-fix.ini \
    && ln -sf /etc/php/7.4/mods-available/cve2026-fix.ini /etc/php/7.4/fpm/conf.d/99-cve2026-fix.ini \
    && ln -sf /etc/php/7.4/mods-available/cve2026-fix.ini /etc/php/7.4/cli/conf.d/99-cve2026-fix.ini

ADD msmtprc /etc/msmtprc

EXPOSE 9000

ENV PATH="/usr/local/share/gini/bin:/usr/local/share/composer/vendor/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
GINI_MODULE_BASE_PATH="/data/gini-modules"

ADD start /start
WORKDIR /data/gini-modules
CMD ["/start"]
