#!/bin/bash
# ============================================
# Nginx 精简安装脚本 - 适配 /data/soft/nginx
# ============================================

set -e

ver="1.22.1"
prefix="/data/soft/nginx"
source_file="/data/soft/nginx-${ver}.tar.gz"
user="www-data"
group="www-data"
conf_file="${prefix}/conf/nginx.conf"
service_file="/etc/systemd/system/nginx.service"

echo "=========================================="
echo "Nginx ${ver} 安装"
echo "=========================================="

# --- 1. 清理原有环境 ---
echo "=== 1. 清理原有环境 ==="
systemctl stop nginx 2>/dev/null || true
pkill -9 nginx 2>/dev/null || true
sleep 1

rm -rf ${prefix}
rm -f ${service_file}
systemctl daemon-reload 2>/dev/null || true

echo "清理完成"

# --- 2. 安装编译依赖 ---
echo "=== 2. 安装编译依赖 ==="
yum install -y gcc make gcc-c++ pcre pcre-devel openssl openssl-devel zlib-devel 2>/dev/null || dnf install -y gcc make gcc-c++ pcre pcre-devel openssl openssl-devel zlib-devel

# --- 3. 创建运行用户 ---
echo "=== 3. 创建运行用户 ==="
groupadd -g 33 ${group} 2>/dev/null || true
useradd -r -u 33 -g ${group} -s /sbin/nologin ${user} 2>/dev/null || true

# --- 4. 解压源码 ---
echo "=== 4. 解压源码 ==="
cd /data/soft
if [ ! -f "${source_file}" ]; then
    wget -q https://nginx.org/download/nginx-${ver}.tar.gz -O ${source_file}
fi

tar -xzf ${source_file}
cd nginx-${ver}

# --- 5. 编译配置 ---
echo "=== 5. 编译配置 ==="
./configure     --prefix=${prefix}     --user=${user}     --group=${group}     --with-http_ssl_module     --with-http_v2_module     --with-http_realip_module     --with-http_stub_status_module     --with-http_gzip_static_module     --with-pcre     --with-stream     --with-stream_ssl_module     --with-file-aio     --with-threads

# --- 6. 编译安装 ---
echo "=== 6. 编译安装 ==="
make -j$(nproc)
make install

# --- 7. 创建目录结构 ---
echo "=== 7. 创建目录结构 ==="
mkdir -p ${prefix}/conf/conf.d
mkdir -p ${prefix}/run
mkdir -p ${prefix}/logs
mkdir -p ${prefix}/temp

chown -R ${user}:${group} ${prefix}

# --- 8. 生成 nginx.conf ---
echo "=== 8. 生成 nginx.conf ==="
cat > ${conf_file} << 'EOFCONF'
user www-data;
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 65535;

error_log /data/soft/nginx/logs/error.log warn;
pid /data/soft/nginx/run/nginx.pid;

events {
    use epoll;
    worker_connections 65535;
    multi_accept on;
}

http {
    include mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /data/soft/nginx/logs/access.log main;

    # 性能优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;

    # 文件缓存
    open_file_cache max=65535 inactive=60s;
    open_file_cache_valid 80s;
    open_file_cache_min_uses 1;
    open_file_cache_errors on;

    # 客户端限制
    client_max_body_size 50m;
    client_body_buffer_size 512k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 8k;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 5;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
    gzip_min_length 1k;

    # 虚拟主机
    include /data/soft/nginx/conf/conf.d/*.conf;
}
EOFCONF

# --- 9. 生成 vhost.conf ---
echo "=== 9. 生成 vhost.conf ==="
cat > ${prefix}/conf/conf.d/vhost.conf << 'EOFVHOST'
server {
    listen 80 default_server;
    server_name localhost;
    root /data/discuz;
    index index.php index.html;

    access_log /data/soft/nginx/logs/discuz-access.log main;
    error_log /data/soft/nginx/logs/discuz-error.log warn;

    # 禁止访问敏感文件
    location ~ /(\.user.ini|\.htaccess|\.git|\.svn|\.project|LICENSE|README.md) {
        return 404;
    }

    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|eot|svg)$ {
        expires 30d;
        access_log off;
    }

    # PHP 处理
    location ~ \.php$ {
        fastcgi_pass unix:/data/soft/php/var/run/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location / {
        try_files $uri $uri/ =404;
    }

    # 状态页
    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
        access_log off;
    }
}
EOFVHOST

# --- 10. 生成 systemd 服务 ---
echo "=== 10. 生成 systemd 服务 ==="
cat > ${service_file} << 'EOFSERVICE'
[Unit]
Description=nginx - high performance web server
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/data/soft/nginx/run/nginx.pid
ExecStartPre=/data/soft/nginx/sbin/nginx -t
ExecStart=/data/soft/nginx/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
LimitNOFILE=65535
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOFSERVICE

# --- 11. 启动服务 ---
echo "=== 11. 启动服务 ==="
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

# --- 12. 验证 ---
echo ""
echo "=========================================="
echo "安装完成"
echo "=========================================="
echo "版本: ${ver}"
echo "路径: ${prefix}"
echo "配置: ${conf_file}"
echo "虚拟主机: ${prefix}/conf/conf.d/vhost.conf"
echo "日志: ${prefix}/logs/"
echo ""

${prefix}/sbin/nginx -v

echo ""
echo "服务状态:"
systemctl status nginx --no-pager || true

echo ""
echo "端口监听:"
ss -tlnp | grep :80 || true

echo ""
echo "=========================================="
