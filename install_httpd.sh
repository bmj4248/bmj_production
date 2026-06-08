#!/bin/bash

# 一键清理并重新安装 Apache
set -e

SOFT_DIR="/data/soft"
SRC_DIR="/root"
CPU=$(nproc)

echo "=== 1. 清理旧环境 ==="
systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true
rm -f /etc/systemd/system/apache2.service
systemctl daemon-reload

rm -rf ${SOFT_DIR}/apache2
rm -rf ${SOFT_DIR}/apr
rm -rf ${SOFT_DIR}/apr-util
rm -rf ${SOFT_DIR}/apr-1.7.5
rm -rf ${SOFT_DIR}/apr-util-1.6.3
rm -rf ${SOFT_DIR}/httpd-2.4.62
rm -f ${SOFT_DIR}/apr-1.7.5.tar.gz
rm -f ${SOFT_DIR}/apr-util-1.6.3.tar.gz
echo "清理完成"

echo "=== 2. 检查源码包 ==="
for pkg in apr-1.7.5.tar.gz apr-util-1.6.3.tar.gz httpd-2.4.62.tar.gz; do
    if [ ! -f "${SRC_DIR}/${pkg}" ]; then
        echo "ERROR: ${SRC_DIR}/${pkg} 不存在！"
        exit 1
    fi
done

echo "=== 3. 安装依赖 ==="
yum install -y gcc make pcre-devel openssl-devel expat-devel libtool autoconf

echo "=== 4. 创建用户 ==="
useradd -r -s /sbin/nologin apache 2>/dev/null || true

echo "=== 5. 复制并解压 ==="
cd ${SOFT_DIR}
cp ${SRC_DIR}/apr-1.7.5.tar.gz .
cp ${SRC_DIR}/apr-util-1.6.3.tar.gz .
cp ${SRC_DIR}/httpd-2.4.62.tar.gz .

tar -zxvf apr-1.7.5.tar.gz
tar -zxvf apr-util-1.6.3.tar.gz
tar -zxvf httpd-2.4.62.tar.gz

echo "=== 6. 生成 configure（APR/APR-Util 需要）==="
cd ${SOFT_DIR}/apr-1.7.5
./buildconf

cd ${SOFT_DIR}/apr-util-1.6.3
./buildconf --with-apr=${SOFT_DIR}/apr-1.7.5

echo "=== 7. 编译 APR ==="
cd ${SOFT_DIR}/apr-1.7.5
./configure --prefix=${SOFT_DIR}/apr
make -j${CPU} && make install


echo "=== 8. 编译 APR-Util ==="
cd ${SOFT_DIR}/apr-util-1.6.3
./configure --prefix=${SOFT_DIR}/apr-util --with-apr=${SOFT_DIR}/apr
make -j${CPU} && make install

echo "=== 9. 编译 Apache ==="
cd ${SOFT_DIR}/httpd-2.4.62
./configure \
  --prefix=${SOFT_DIR}/apache \
  --with-apr=${SOFT_DIR}/apr \
  --with-apr-util=${SOFT_DIR}/apr-util \
  --enable-so \
  --enable-ssl \
  --enable-rewrite \
  --enable-mpms-shared=all \
  --with-mpm=event
make -j${CPU} && make install

echo "=== 10. 配置 Apache ==="
sed -i 's|^Listen 80|Listen 0.0.0.0:80|' ${SOFT_DIR}/apache/conf/httpd.conf
sed -i 's|#ServerName www.example.com:80|ServerName localhost:80|' ${SOFT_DIR}/apache/conf/httpd.conf
sed -i 's|^User daemon|User apache|' ${SOFT_DIR}/apache/conf/httpd.conf
sed -i 's|^Group daemon|Group apache|' ${SOFT_DIR}/apache/conf/httpd.conf

mkdir -p ${SOFT_DIR}/apache/htdocs
echo "<h1>Apache is running</h1>" > ${SOFT_DIR}/apache/htdocs/index.html

echo "=== 11. 配置 systemd 服务 ==="
cat > /etc/systemd/system/apache.service << 'EOF'
[Unit]
Description=Apache HTTP Server
After=network.target

[Service]
Type=forking
PIDFile=/data/soft/apache/logs/httpd.pid
ExecStart=/data/soft/apache/bin/apachectl start
ExecStop=/data/soft/apache/bin/apachectl stop
ExecReload=/data/soft/apache/bin/apachectl graceful
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "=== 12. 启动服务 ==="
systemctl daemon-reload
systemctl start apache
systemctl enable apache

echo "=== 13. 验证 ==="
sleep 2
systemctl status apache --no-pager
ss -tlnp | grep 80
curl -s http://127.0.0.1/ | head -1

echo ""
echo "=== 14. 清理源码包 ==="
cd ${SOFT_DIR}
rm -f apr-1.7.5.tar.gz apr-util-1.6.3.tar.gz httpd-2.4.62.tar.gz
rm -rf apr-1.7.5 apr-util-1.6.3 httpd-2.4.62

echo ""
echo "=== 安装完成 ==="
echo "Apache 路径: ${SOFT_DIR}/apache"