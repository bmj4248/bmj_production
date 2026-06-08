#!/bin/bash
set -e

SOFT_DIR="/data/soft"
SRC_DIR="/root"
CPU=$(nproc)

echo "=== 使用 ${CPU} 核心并行编译 ==="

echo "=== 1. 检查源码包 ==="
if [ ! -f "${SRC_DIR}/php-8.2.31.tar.gz" ]; then
    echo "ERROR: ${SRC_DIR}/php-8.2.31.tar.gz 不存在，请先上传！"
    exit 1
fi

echo "=== 2. 清理旧环境 ==="
systemctl stop php-fpm 2>/dev/null || true
systemctl disable php-fpm 2>/dev/null || true
rm -f /etc/systemd/system/php-fpm.service
systemctl daemon-reload

rm -rf ${SOFT_DIR}/php ${SOFT_DIR}/php-8.2.31
rm -f ${SOFT_DIR}/php-8.2.31.tar.gz
rm -rf ${SOFT_DIR}/onig-6.9.9 ${SOFT_DIR}/onig-6.9.9.tar.gz
echo "清理完成"

echo "=== 3. 安装编译依赖 ==="
yum install -y epel-release 2>/dev/null || true
yum install -y gcc make libxml2-devel openssl-devel curl-devel \
    libjpeg-devel libpng-devel freetype-devel libzip-devel \
    sqlite-devel libtool

echo "=== 3.1 检查并安装 oniguruma ==="
if command -v onig-config >/dev/null 2>&1 || [ -f "/usr/lib64/libonig.so" ]; then
    echo "oniguruma 已安装，跳过"
else
    echo "准备源码编译 oniguruma..."
    cd ${SOFT_DIR}
    wget -q https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz
    tar -zxf onig-6.9.9.tar.gz
    cd onig-6.9.9
    ./configure --prefix=/usr
    make -j${CPU} && make install
    ldconfig
    cd ${SOFT_DIR}
    rm -rf onig-6.9.9 onig-6.9.9.tar.gz
    echo "oniguruma 安装完成"
fi

echo "=== 4. 创建运行用户 ==="
useradd -r -s /sbin/nologin php-fpm 2>/dev/null || true

echo "=== 5. 复制并解压 PHP ==="
cd ${SOFT_DIR}
cp ${SRC_DIR}/php-8.2.31.tar.gz .
tar -zxf php-8.2.31.tar.gz

echo "=== 6. 编译 PHP（${CPU}核）==="
cd ${SOFT_DIR}/php-8.2.31
./configure \
  --prefix=${SOFT_DIR}/php \
  --with-config-file-path=${SOFT_DIR}/php/etc \
  --enable-fpm \
  --enable-mysqlnd \
  --with-mysqli \
  --with-pdo-mysql \
  --enable-gd \
  --with-jpeg \
  --with-png \
  --with-freetype \
  --enable-bcmath \
  --enable-mbstring \
  --enable-opcache \
  --enable-zip \
  --with-curl \
  --with-openssl \
  --with-zlib \
  --enable-sockets
make -j${CPU} && make install

echo "=== 7. 复制配置文件 ==="
cp ${SOFT_DIR}/php-8.2.31/php.ini-production ${SOFT_DIR}/php/etc/php.ini
cp ${SOFT_DIR}/php/etc/php-fpm.conf.default ${SOFT_DIR}/php/etc/php-fpm.conf
cp ${SOFT_DIR}/php/etc/php-fpm.d/www.conf.default ${SOFT_DIR}/php/etc/php-fpm.d/www.conf

echo "=== 8. 配置 PHP-FPM ==="
sed -i 's|^listen =.*|listen = 127.0.0.1:9000|' ${SOFT_DIR}/php/etc/php-fpm.d/www.conf
sed -i 's|^user =.*|user = php-fpm|' ${SOFT_DIR}/php/etc/php-fpm.d/www.conf
sed -i 's|^group =.*|group = php-fpm|' ${SOFT_DIR}/php/etc/php-fpm.d/www.conf

echo "=== 9. 配置 systemd 服务 ==="
cat > /etc/systemd/system/php-fpm.service << 'EOF'
[Unit]
Description=PHP FastCGI Process Manager
After=network.target

[Service]
Type=forking
PIDFile=/data/soft/php/var/run/php-fpm.pid
ExecStart=/data/soft/php/sbin/php-fpm
ExecStop=/bin/kill -QUIT $MAINPID
ExecReload=/bin/kill -USR2 $MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "=== 10. 启动服务 ==="
systemctl daemon-reload
systemctl start php-fpm
systemctl enable php-fpm

echo "=== 11. 验证 ==="
sleep 2
systemctl status php-fpm --no-pager
ss -tlnp | grep 9000
${SOFT_DIR}/php/bin/php -v

echo "=== 12. 清理源码 ==="
cd ${SOFT_DIR}
rm -f php-8.2.31.tar.gz
rm -rf php-8.2.31

echo ""
echo "=== 安装完成 ==="
echo "PHP 路径: ${SOFT_DIR}/php"
echo "PHP-FPM 监听: 127.0.0.1:9000"
echo ""
echo "=== Apache 配置提示（后续手动添加）==="
echo "LoadModule proxy_module modules/mod_proxy.so"
echo "LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so"
echo ""
echo "<FilesMatch \"\\.php$\">"
echo "    SetHandler \"proxy:fcgi://127.0.0.1:9000\""
echo "</FilesMatch>"
