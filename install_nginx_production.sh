#!/bin/bash
# ============================================
# Nginx 生产环境源码安装 + 系统调优脚本
# Rocky/CentOS/RHEL 8+
# ============================================

set -e

# --- 可配置变量 ---
ver="1.24.0"                    # 生产环境建议 1.24.x（stable）
prefix="/data/soft/nginx"
source_file="/root/nginx-${ver}.tar.gz"
user="nginx"
group="nginx"
conf_file="${prefix}/conf/nginx.conf"
pid_file="${prefix}/run/nginx.pid"
service_file="/usr/lib/systemd/system/nginx.service"

# Tomcat 后端地址（按需修改）
TOMCAT_BACKEND="10.0.1.10:8080 10.0.1.11:8080"

echo "=========================================="
echo "Nginx ${ver} 生产环境安装"
echo "=========================================="

# --- 1. 清理系统原有 nginx ---
echo "=== 1. 清理原有环境 ==="
systemctl stop nginx 2>/dev/null || true
pkill -9 nginx 2>/dev/null || true
sleep 2

dnf remove -y nginx nginx-all-modules nginx-filesystem nginx-mod-* 2>/dev/null || true
yum remove -y nginx nginx-all-modules nginx-filesystem nginx-mod-* 2>/dev/null || true

groupdel ${group} 2>/dev/null || true
userdel -r ${user} 2>/dev/null || true

rm -rf /etc/nginx /usr/share/nginx /var/log/nginx /var/cache/nginx /var/lib/nginx
rm -rf /run/nginx /usr/local/nginx /tmp/nginx*
rm -f /usr/sbin/nginx /usr/local/sbin/nginx /usr/bin/nginx /usr/local/bin/nginx
rm -f /etc/systemd/system/nginx.service /usr/lib/systemd/system/nginx.service
systemctl daemon-reload 2>/dev/null || true
rm -rf ${prefix}

echo "清理完成"

# --- 2. 系统级调优（sysctl + limits）===
echo "=== 2. 系统级内核调优 ==="

cat > /etc/sysctl.d/99-nginx-production.conf << 'EOFSYSCTL'
# === 文件句柄 ===
fs.file-max = 1048576
fs.nr_open = 1048576

# === TCP 连接优化 ===
net.ipv4.tcp_max_tw_buckets = 6000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15

# === 连接队列 ===
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# === 内存与缓存 ===
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 65536 6291456
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# === 虚拟内存 ===
vm.swappiness = 10
EOFSYSCTL

sysctl --system

cat > /etc/security/limits.d/nginx.conf << 'EOFLIMITS'
nginx   soft    nofile      65535
nginx   hard    nofile      65535
*       soft    nofile      65535
*       hard    nofile      65535
EOFLIMITS

# --- 3. 安装编译依赖 ===
echo "=== 3. 安装编译依赖 ==="
dnf install -y gcc make gcc-c++ glibc glibc-devel pcre2 pcre2-devel openssl openssl-devel systemd-devel zlib-devel libxml2 libxml2-devel libxslt libxslt-devel 2>/dev/null || \
yum install -y gcc make gcc-c++ glibc glibc-devel pcre2 pcre2-devel openssl openssl-devel systemd-devel zlib-devel libxml2 libxml2-devel libxslt libxslt-devel

# --- 4. 创建运行用户 ===
echo "=== 4. 创建运行用户 ==="
groupadd ${group}
useradd -r -g ${group} -s /usr/sbin/nologin ${user}

# --- 5. 下载并解压源码 ===
echo "=== 5. 准备源码 ==="
if [ ! -f "${source_file}" ]; then
    cd /root
    wget -q https://nginx.org/download/nginx-${ver}.tar.gz -O ${source_file}
fi

cd /usr/local/src
rm -rf nginx-${ver}
tar xf ${source_file}
cd nginx-${ver}

# --- 6. 编译配置（生产级模块）===
echo "=== 6. 编译配置 ==="
./configure \
    --prefix=${prefix} \
    --user=${user} \
    --group=${group} \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-pcre \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_auth_request_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_degradation_module \
    --with-http_slice_module \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-cc-opt='-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong' \
    --with-ld-opt='-Wl,-z,relro -Wl,-z,now -pie'

# --- 7. 编译安装 ===
echo "=== 7. 编译安装 ==="
make -j$(nproc)
make install

# --- 8. 创建生产级目录结构 ===
echo "=== 8. 创建目录结构 ==="
mkdir -p ${prefix}/conf/conf.d
mkdir -p ${prefix}/run
mkdir -p ${prefix}/logs
mkdir -p ${prefix}/temp/{client_body,proxy,fastcgi,uwsgi,scgi}_temp
mkdir -p ${prefix}/html
mkdir -p /var/nginx/proxy_cache        # proxy_cache 磁盘缓存
mkdir -p /var/log/nginx                # 统一日志目录
mkdir -p /data/static                  # 本地静态资源
mkdir -p /data/download                # 下载文件目录
mkdir -p /data/soft/nginx/web1         # 默认站点目录

chown -R ${user}:${group} ${prefix}
chown -R ${user}:${group} /var/nginx
chown -R ${user}:${group} /var/log/nginx
chown -R ${user}:${group} /data/static
chown -R ${user}:${group} /data/download
chown -R ${user}:${group} /data/soft/nginx/web1

# --- 9. 生成生产级主配置 ===
echo "=== 9. 生成 nginx.conf ==="
cat > ${conf_file} << 'EOFCONF'
user nginx nginx;
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 65535;

error_log /var/log/nginx/error.log warn;
pid run/nginx.pid;

# 工作进程绑定与调度
events {
    use epoll;
    worker_connections 65535;
    multi_accept on;
    accept_mutex on;
    accept_mutex_delay 500ms;
}

http {
    include mime.types;
    include /data/soft/nginx/conf/conf.d/*.conf;
    default_type application/octet-stream;

    # 日志格式（带 upstream 耗时，生产排障必备）
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time" '
                    'cache="$upstream_cache_status"';

    access_log /var/log/nginx/access.log main buffer=64k flush=10s;

    # === 核心性能 ===
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 60;
    keepalive_requests 1000;

    # 文件句柄缓存（静态文件服务必开）
    open_file_cache max=65535 inactive=60s;
    open_file_cache_valid 80s;
    open_file_cache_min_uses 1;
    open_file_cache_errors on;

    # === 客户端限制 ===
    client_max_body_size 50m;
    client_body_buffer_size 512k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 8k;
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;

    # === Gzip（源站建议 level 5，CDN 回源场景视情况关闭）===
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 5;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_min_length 1k;
    gzip_buffers 16 8k;

    # === 代理缓存目录 ===
    proxy_cache_path /var/nginx/proxy_cache levels=1:2 keys_zone=proxy_cache:500m 
                     inactive=7d max_size=50g use_temp_path=off;

    # === 限流与连接控制（防刷）===
    limit_req_zone $binary_remote_addr zone=req_limit:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    # === Upstream：Tomcat 业务后端 ===
    upstream tomcat_backend {
        server 10.0.1.10:8080 weight=5 max_fails=3 fail_timeout=30s;
        server 10.0.1.11:8080 weight=5 max_fails=3 fail_timeout=30s;
        
        keepalive 300;
        keepalive_timeout 60s;
        keepalive_requests 1000;
    }

    # === Upstream：阿里云 OSS（内网 Endpoint）===
    upstream oss_backend {
        server your-bucket.oss-cn-beijing-internal.aliyuncs.com:443;
        keepalive 100;
    }

    # === HTTP 80（统一入口，强制跳转 HTTPS 或分流）===
    server {
        listen 80 default_server;
        server_name _;

        # 可选：强制跳转 HTTPS（生产环境建议开启）
        # return 301 https://$host$request_uri;

        location / {
            proxy_pass http://tomcat_backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            proxy_connect_timeout 5s;
            proxy_send_timeout 30s;
            proxy_read_timeout 60s;
            proxy_next_upstream error timeout http_502 http_503;
        }
    }

    # === HTTPS 443（生产开启）===
    #server {
    #    listen 443 ssl http2;
    #    server_name origin.yourdomain.com;
    #
    #    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    #    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    #    ssl_protocols TLSv1.2 TLSv1.3;
    #    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    #    ssl_prefer_server_ciphers on;
    #    ssl_session_cache shared:SSL:50m;
    #    ssl_session_timeout 1d;
    #    ssl_session_tickets off;
    #    ssl_stapling on;
    #    ssl_stapling_verify on;
    #    resolver 223.5.5.5 114.114.114.114 valid=300s;
    #
    #    # 真实 IP（CDN 回源）
    #    set_real_ip_from 0.0.0.0/0;
    #    real_ip_header X-Forwarded-For;
    #    real_ip_recursive on;
    #
    #    location / {
    #        proxy_pass http://tomcat_backend;
    #        proxy_http_version 1.1;
    #        proxy_set_header Connection "";
    #        proxy_set_header Host $host;
    #        proxy_set_header X-Real-IP $remote_addr;
    #        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #        proxy_set_header X-Forwarded-Proto $scheme;
    #    }
    #}
}
EOFCONF

# --- 10. 生成默认虚拟主机（生产模板）===
echo "=== 10. 生成虚拟主机模板 ==="
cat > ${prefix}/conf/conf.d/vhost-production.conf << 'EOFVHOST'
# 生产环境虚拟主机模板
# 静态资源 + 动态代理 + 状态监控

server {
    listen 80;
    server_name localhost;

    root /data/soft/nginx/web1;
    index index.html;

    # 1. 本地静态文件（不走 Tomcat）
    location /static/ {
        alias /data/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
        log_not_found off;
    }

    # 2. 大文件下载（sendfile 优化）
    location /download/ {
        alias /data/download/;
        sendfile on;
        tcp_nopush on;
        expires 7d;
        add_header Accept-Ranges bytes;
        
        # 限速防刷（可选）
        # limit_rate_after 10m;
        # limit_rate 2m;
    }

    # 3. 代理 OSS（CDN 未命中时回源到 OSS）
    location /oss/ {
        proxy_pass https://oss_backend;
        proxy_set_header Host your-bucket.oss-cn-beijing-internal.aliyuncs.com;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        proxy_cache proxy_cache;
        proxy_cache_valid 200 302 7d;
        proxy_cache_valid 404 1m;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_use_stale error timeout invalid_header updating http_500 http_502;
        
        add_header X-Cache-Status $upstream_cache_status;
    }

    # 4. 动态 API → Tomcat
    location /api/ {
        limit_req zone=req_limit burst=50 nodelay;
        limit_conn conn_limit 100;
        
        proxy_pass http://tomcat_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        proxy_connect_timeout 5s;
        proxy_send_timeout 30s;
        proxy_read_timeout 60s;
        
        # 动态内容禁止缓存
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        expires off;
    }

    # 5. Nginx 状态页（内网限制）
    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        allow 192.168.0.0/16;
        deny all;
        access_log off;
    }

    # 6. 健康检查（负载均衡探针）
    location /health {
        access_log off;
        return 200 "nginx-ok\n";
        add_header Content-Type text/plain;
    }
}
EOFVHOST

# --- 11. 复制 man 手册 ===
echo "=== 11. 复制手册 ==="
cp /usr/local/src/nginx-${ver}/man/nginx.8 /usr/share/man/man8/ 2>/dev/null || true
gzip -f /usr/share/man/man8/nginx.8 2>/dev/null || true

# --- 12. 环境变量 ===
echo "=== 12. 环境变量 ==="
echo "export PATH=${prefix}/sbin:\$PATH" > /etc/profile.d/nginx.sh
source /etc/profile.d/nginx.sh

# --- 13. 生成 systemd 服务 ===
echo "=== 13. 生成 systemd 服务 ==="
cat > ${service_file} << EOFSERVICE
[Unit]
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=${pid_file}
ExecStartPre=${prefix}/sbin/nginx -t -c ${conf_file}
ExecStart=${prefix}/sbin/nginx -c ${conf_file}
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
ExecStartPost=/bin/sleep 0.1
LimitNOFILE=65535
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOFSERVICE

# --- 14. 启动 ===
echo "=== 14. 启动服务 ==="
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

# --- 15. 验证 ===
echo ""
echo "=========================================="
echo "安装完成"
echo "=========================================="
echo "版本: ${ver}"
echo "路径: ${prefix}"
echo "配置: ${conf_file}"
echo "虚拟主机: ${prefix}/conf/conf.d/"
echo "日志: /var/log/nginx/"
echo "缓存: /var/nginx/proxy_cache/"
echo ""

${prefix}/sbin/nginx -V 2>&1 | head -5

echo ""
echo "服务状态:"
systemctl status nginx --no-pager || true

echo ""
echo "端口监听:"
ss -tlnp | grep -E ":80|:443" || true

echo ""
echo "系统调优已写入:"
echo "  /etc/sysctl.d/99-nginx-production.conf"
echo "  /etc/security/limits.d/nginx.conf"
echo ""
echo "请执行以下命令使 limits 立即生效（或重新登录）："
echo "  ulimit -n 65535"
echo ""
echo "Tomcat/JVM 优化脚本请见回复中的 install_tomcat_production.sh"
echo "=========================================="