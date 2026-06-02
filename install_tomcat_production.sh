#!/bin/bash
# ============================================
# Tomcat 9/10 + OpenJDK 11/17 生产环境安装脚本
# ============================================

set -e

TOMCAT_VER="9.0.89"
JDK_VER="17"
TOMCAT_HOME="/data/soft/tomcat"
JDK_HOME="/usr/lib/jvm/java-17-openjdk"
APP_USER="tomcat"
APP_GROUP="tomcat"

echo "=========================================="
echo "Tomcat ${TOMCAT_VER} + OpenJDK ${JDK_VER} 生产环境安装"
echo "=========================================="

# --- 1. 安装 OpenJDK ---
echo "=== 1. 安装 JDK ==="
dnf install -y java-17-openjdk java-17-openjdk-devel 2>/dev/null || \
yum install -y java-17-openjdk java-17-openjdk-devel

# --- 2. 创建用户 ===
echo "=== 2. 创建运行用户 ==="
groupadd ${APP_GROUP} 2>/dev/null || true
id ${APP_USER} &>/dev/null || useradd -r -g ${APP_GROUP} -s /usr/sbin/nologin ${APP_USER}

# --- 3. 下载 Tomcat ===
echo "=== 3. 下载 Tomcat ==="
cd /usr/local/src
rm -rf apache-tomcat-${TOMCAT_VER}
if [ ! -f "apache-tomcat-${TOMCAT_VER}.tar.gz" ]; then
    wget -q https://dlcdn.apache.org/tomcat/tomcat-9/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz
fi
tar xf apache-tomcat-${TOMCAT_VER}.tar.gz
mv apache-tomcat-${TOMCAT_VER} ${TOMCAT_HOME}
mkdir -p ${TOMCAT_HOME}/webapps/ROOT

# --- 4. 部署健康检查接口 ===
echo "=== 4. 部署探针应用 ==="
cat > ${TOMCAT_HOME}/webapps/ROOT/health.jsp << 'EOF'
<%@ page contentType="application/json;charset=UTF-8" language="java" %>
{"status":"ok","server":"<%=request.getServerName()%>","time":<%=System.currentTimeMillis()%>}
EOF

# --- 5. 优化 server.xml ===
echo "=== 5. 优化 server.xml ==="
cat > ${TOMCAT_HOME}/conf/server.xml << 'EOFSERVER'
<?xml version="1.0" encoding="UTF-8"?>
<<Server port="8005" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

  <GlobalNamingResources>
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database that can be updated and saved"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>

  <Service name="Catalina">
    <!-- 生产级 Connector：NIO2 + 线程池优化 -->
    <Connector port="8080" 
               protocol="org.apache.coyote.http11.Http11Nio2Protocol"
               maxThreads="800"
               minSpareThreads="100"
               maxConnections="10000"
               acceptCount="1000"
               connectionTimeout="20000"
               maxHttpHeaderSize="8192"
               compression="on"
               compressionMinSize="2048"
               compressableMimeType="text/html,text/xml,text/plain,text/css,text/javascript,application/javascript,application/json"
               enableLookups="false"
               disableUploadTimeout="true"
               URIEncoding="UTF-8"
               keepAliveTimeout="30000"
               maxKeepAliveRequests="1000"
               scheme="http"
               proxyPort="80" />

    <Engine name="Catalina" defaultHost="localhost">
      <Realm className="org.apache.catalina.realm.LockOutRealm">
        <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
      </Realm>

      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true">
        <!-- 获取 Nginx 真实 IP -->
        <Valve className="org.apache.catalina.valves.RemoteIpValve"
               remoteIpHeader="X-Forwarded-For"
               protocolHeader="X-Forwarded-Proto"
               protocolHeaderHttpsValue="https"
               internalProxies="10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.1[6-9]\.\d{1,3}\.\d{1,3}|172\.2[0-9]\.\d{1,3}\.\d{1,3}|172\.3[0-1]\.\d{1,3}\.\d{1,3}|127\.\d{1,3}\.\d{1,3}\.\d{1,3}" />

        <Context path="" docBase="ROOT" reloadable="false">
          <JarScanner scanClassPath="false" scanAllFiles="false" scanAllDirectories="false"/>
        </Context>
      </Host>
    </Engine>
  </Service>
</Server>
EOFSERVER

# --- 6. JVM 优化 setenv.sh ===
echo "=== 6. 配置 JVM ==="
cat > ${TOMCAT_HOME}/bin/setenv.sh << 'EOFJVM'
#!/bin/bash
# ============================================
# Tomcat JVM 生产环境参数
# 服务器配置：4C8G ~ 8C16G（按实际调整）
# ============================================

# 堆内存（建议给 Tomcat 机器内存的 60%~70%）
JAVA_OPTS="-server"
JAVA_OPTS="$JAVA_OPTS -Xms4g"
JAVA_OPTS="$JAVA_OPTS -Xmx4g"
JAVA_OPTS="$JAVA_OPTS -Xmn1536m"
JAVA_OPTS="$JAVA_OPTS -XX:MetaspaceSize=256m"
JAVA_OPTS="$JAVA_OPTS -XX:MaxMetaspaceSize=512m"

# G1 垃圾收集器
JAVA_OPTS="$JAVA_OPTS -XX:+UseG1GC"
JAVA_OPTS="$JAVA_OPTS -XX:MaxGCPauseMillis=200"
JAVA_OPTS="$JAVA_OPTS -XX:G1HeapRegionSize=16m"
JAVA_OPTS="$JAVA_OPTS -XX:InitiatingHeapOccupancyPercent=45"

# GC 日志（JDK 17 统一参数）
JAVA_OPTS="$JAVA_OPTS -Xlog:gc*:file=/var/log/tomcat/gc.log:time,uptime,level,tags:filecount=10,filesize=100m"

# OOM 自动 dump
JAVA_OPTS="$JAVA_OPTS -XX:+HeapDumpOnOutOfMemoryError"
JAVA_OPTS="$JAVA_OPTS -XX:HeapDumpPath=/var/log/tomcat/heapdump.hprof"

# 性能优化
JAVA_OPTS="$JAVA_OPTS -XX:+UseStringDeduplication"
JAVA_OPTS="$JAVA_OPTS -XX:+AlwaysPreTouch"
JAVA_OPTS="$JAVA_OPTS -XX:+DisableExplicitGC"

# 系统参数
JAVA_OPTS="$JAVA_OPTS -Djava.net.preferIPv4Stack=true"
JAVA_OPTS="$JAVA_OPTS -Dfile.encoding=UTF-8"
JAVA_OPTS="$JAVA_OPTS -Djava.security.egd=file:/dev/./urandom"

export JAVA_OPTS
EOFJVM
chmod +x ${TOMCAT_HOME}/bin/setenv.sh

# --- 7. 目录权限 ===
echo "=== 7. 设置权限 ==="
mkdir -p /var/log/tomcat
chown -R ${APP_USER}:${APP_GROUP} ${TOMCAT_HOME}
chown -R ${APP_USER}:${APP_GROUP} /var/log/tomcat

# --- 8. Systemd 服务 ===
echo "=== 8. 生成 systemd ==="
cat > /usr/lib/systemd/system/tomcat.service << 'EOFSERVICE'
[Unit]
Description=Apache Tomcat
After=network.target

[Service]
Type=forking
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk
Environment=CATALINA_HOME=/data/soft/tomcat
Environment=CATALINA_BASE=/data/soft/tomcat
Environment=CATALINA_PID=/data/soft/tomcat/temp/tomcat.pid

User=tomcat
Group=tomcat

ExecStart=/data/soft/tomcat/bin/startup.sh
ExecStop=/data/soft/tomcat/bin/shutdown.sh
ExecStartPre=/bin/rm -f /data/soft/tomcat/temp/tomcat.pid

Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOFSERVICE

# --- 9. 启动 ===
echo "=== 9. 启动 Tomcat ==="
systemctl daemon-reload
systemctl enable tomcat
systemctl start tomcat

sleep 5

# --- 10. 验证 ===
echo ""
echo "=========================================="
echo "Tomcat 安装完成"
echo "=========================================="
echo "路径: ${TOMCAT_HOME}"
echo "JDK:  ${JDK_HOME}"
echo "用户: ${APP_USER}"
echo ""
echo "JVM 参数:"
grep "^JAVA_OPTS" ${TOMCAT_HOME}/bin/setenv.sh | head -1
echo ""
echo "服务状态:"
systemctl status tomcat --no-pager || true
echo ""
echo "本地测试:"
curl -s http://127.0.0.1:8080/health.jsp || echo "（请等待 10 秒后重试）"
echo ""
echo "=========================================="