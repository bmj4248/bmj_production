#!/bin/bash
#==============================================================
# Linux 内核参数企业级场景化优化脚本
# 适用: RHEL/CentOS 7+ / Ubuntu 18+ / 国产麒麟/龙蜥等
# 版本: v1.1 (含6大场景)
#==============================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SYSCTL_CONF="/etc/sysctl.d/99-enterprise-tuning.conf"
BACKUP_DIR="/etc/sysctl.d/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

#==============================================================
# 场景定义函数
#==============================================================

# 场景1: Web/反向代理/负载均衡 (Nginx/HAProxy/APISIX)
scene_web() {
    cat <<'EOF'
# === 场景1: Web服务/网关/负载均衡 ===
# 目标: 高并发连接、快速端口回收、低延迟响应

# ---- 网络连接队列 ----
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# ---- TCP 端口与回收 ----
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.ip_local_port_range = 1024 65535

# ---- Keepalive 与超时 ----
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# ---- 缓冲区调优 ----
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_notsent_lowat = 16384

# ---- 拥塞控制 (内核4.9+建议bbr) ----
net.ipv4.tcp_congestion_control = bbr

# ---- 文件句柄 ----
fs.file-max = 2097152
fs.nr_open = 1048576

# ---- 内存 ----
vm.swappiness = 10
EOF
}

# 场景2: 数据库/OLTP (MySQL/PostgreSQL/Oracle)
scene_database() {
    cat <<'EOF'
# === 场景2: 数据库/事务处理 ===
# 目标: 大内存利用、低swap、稳定IO、NUMA亲和

# ---- 内存管理 ----
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
vm.overcommit_ratio = 90

# ---- NUMA 优化 (数据库建议手动绑核，关闭自动平衡) ----
vm.zone_reclaim_mode = 0
kernel.numa_balancing = 0

# ---- 网络 (数据库间通信/客户端连接) ----
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.ip_local_port_range = 1024 65535

# ---- 文件句柄与进程 ----
fs.file-max = 2097152
fs.nr_open = 1048576
kernel.pid_max = 65536
kernel.threads-max = 1032256

# ---- 安全基线 ----
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
EOF
}

# 场景3: 缓存/NoSQL/消息队列 (Redis/Kafka/RabbitMQ)
scene_cache() {
    cat <<'EOF'
# === 场景3: 缓存/消息队列/实时流 ===
# 目标: 内存优先、零swap、高吞吐网络、低延迟调度

# ---- 内存 (Redis 必须 overcommit_memory=1) ----
vm.swappiness = 1
vm.overcommit_memory = 1
vm.overcommit_ratio = 95
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.vfs_cache_pressure = 50

# ---- 网络 (高吞吐、快速重传) ----
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 500000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_tw_reuse = 1

# ---- 文件句柄 ----
fs.file-max = 4194304
fs.nr_open = 2097152

# ---- 进程与调度 ----
kernel.pid_max = 65536
kernel.threads-max = 2064512
kernel.sched_migration_cost_ns = 5000000

# ---- 禁用透明大页 (Redis/MongoDB 建议) ----
# 注意: 透明大页需通过 /sys/kernel/mm/transparent_hugepage/enabled 关闭
# 本脚本仅提示，请手动执行: echo never > /sys/kernel/mm/transparent_hugepage/enabled
EOF
}

# 场景4: 大数据/批处理/通用企业 (Hadoop/Spark/ELK)
scene_bigdata() {
    cat <<'EOF'
# === 场景4: 大数据/通用企业级 ===
# 目标: 高吞吐IO、大内存页缓存、容器兼容、安全基线

# ---- 内存 ----
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 1000
vm.dirty_writeback_centisecs = 500
vm.vfs_cache_pressure = 100
vm.overcommit_memory = 1

# ---- 网络 ----
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = cubic
net.ipv4.tcp_tw_reuse = 1

# ---- 文件句柄 ----
fs.file-max = 4194304
fs.nr_open = 2097152

# ---- 进程 ----
kernel.pid_max = 65536
kernel.threads-max = 2064512

# ---- 容器/K8s 兼容 ----
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
user.max_inotify_instances = 8192
user.max_inotify_watches = 524288

# ---- 安全基线 ----
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF
}

# 场景5: 自定义调试 (空模板，用户手动编辑)
scene_custom() {
    cat <<'EOF'
# === 场景5: 自定义调试模式 ===
# 请在此区域手动添加参数，或先选其他场景生成后修改
# 示例:
# vm.swappiness = 5
# net.core.somaxconn = 65535
EOF
}

# 场景6: Java应用服务器 / Tomcat / SpringBoot
scene_tomcat() {
    cat <<'EOF'
# === 场景6: Java应用服务器 / Tomcat / SpringBoot ===
# 目标: JVM内存保护、高并发线程、快速GC、网络吞吐

# ---- 内存 (JVM 生死线) ----
vm.swappiness = 1           # 绝对低swap，防止JVM被换出
vm.overcommit_memory = 1    # 允许内存超分配，JVM堆+堆外内存
vm.overcommit_ratio = 90
vm.dirty_ratio = 10         # 低脏页，减少IO突刺干扰GC
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 500
vm.vfs_cache_pressure = 50  # 保留文件缓存，Tomcat读class/jar快

# ---- 网络 (Tomcat Connector 高并发) ----
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15

# ---- TCP 缓冲区 (动态请求通常比静态小) ----
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# ---- 文件句柄 (Tomcat 线程数 = 连接数 = 句柄数) ----
fs.file-max = 2097152
fs.nr_open = 1048576

# ---- 进程与线程 (Tomcat 线程池) ----
kernel.pid_max = 65536
kernel.threads-max = 1032256

# ---- 安全基线 ----
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
EOF
}

#==============================================================
# 工具函数
#==============================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║     Linux 内核参数企业级场景化优化工具              ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_menu() {
    echo -e "${BLUE}请选择优化场景:${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Web服务/网关/负载均衡  (Nginx/HAProxy/APISIX)"
    echo -e "  ${GREEN}[2]${NC} 数据库/OLTP           (MySQL/PostgreSQL/Oracle)"
    echo -e "  ${GREEN}[3]${NC} 缓存/消息队列         (Redis/Kafka/RabbitMQ)"
    echo -e "  ${GREEN}[4]${NC} 大数据/通用企业       (Hadoop/Spark/K8s/ELK)"
    echo -e "  ${GREEN}[5]${NC} 自定义调试模式        (空模板，手动编辑)"
    echo -e "  ${GREEN}[6]${NC} Java应用服务器        (Tomcat/SpringBoot/WebLogic)"
    echo ""
    echo -e "  ${YELLOW}[b]${NC} 查看当前已应用的参数"
    echo -e "  ${YELLOW}[r]${NC} 回滚到上一次配置"
    echo -e "  ${YELLOW}[q]${NC} 退出"
    echo ""
}

backup_current() {
    mkdir -p "$BACKUP_DIR"
    if [ -f "$SYSCTL_CONF" ]; then
        cp "$SYSCTL_CONF" "$BACKUP_DIR/sysctl.conf.$TIMESTAMP"
        echo -e "${YELLOW}已备份当前配置到: $BACKUP_DIR/sysctl.conf.$TIMESTAMP${NC}"
    fi
}

rollback() {
    local latest
    latest=$(ls -t "$BACKUP_DIR"/sysctl.conf.* 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        echo -e "${RED}没有找到可回滚的备份！${NC}"
        exit 1
    fi
    echo -e "${YELLOW}准备回滚到: $(basename "$latest")${NC}"
    cp "$latest" "$SYSCTL_CONF"
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    echo -e "${GREEN}回滚完成并已生效！${NC}"
}

apply_sysctl() {
    local content="$1"
    
    # 写入配置
    echo "$content" > "$SYSCTL_CONF"
    
    # 验证语法
    if ! sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1; then
        echo -e "${RED}错误: sysctl 参数语法验证失败，请检查配置！${NC}"
        echo -e "${YELLOW}配置文件位置: $SYSCTL_CONF${NC}"
        exit 1
    fi
    
    # 生效
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    
    echo -e "${GREEN}配置已生成并生效: $SYSCTL_CONF${NC}"
    echo -e "${CYAN}提示: 永久生效，重启后依然保持${NC}"
}

show_current() {
    echo -e "${CYAN}当前生效的关键参数:${NC}"
    echo -e "${YELLOW}--- 网络 ---${NC}"
    sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_tw_reuse 2>/dev/null || true
    echo -e "${YELLOW}--- 内存 ---${NC}"
    sysctl vm.swappiness vm.dirty_ratio vm.overcommit_memory 2>/dev/null || true
    echo -e "${YELLOW}--- 文件句柄 ---${NC}"
    sysctl fs.file-max fs.nr_open 2>/dev/null || true
}

#==============================================================
# 主逻辑
#==============================================================

main() {
    print_banner
    
    while true; do
        print_menu
        read -rp "请输入选项 (1-6/b/r/q): " choice
        echo ""
        
        case "$choice" in
            1)
                echo -e "${CYAN}>>> 场景1: Web服务/网关/负载均衡${NC}"
                backup_current
                apply_sysctl "$(scene_web)"
                show_current
                ;;
            2)
                echo -e "${CYAN}>>> 场景2: 数据库/OLTP${NC}"
                backup_current
                apply_sysctl "$(scene_database)"
                show_current
                ;;
            3)
                echo -e "${CYAN}>>> 场景3: 缓存/消息队列${NC}"
                backup_current
                apply_sysctl "$(scene_cache)"
                show_current
                ;;
            4)
                echo -e "${CYAN}>>> 场景4: 大数据/通用企业${NC}"
                backup_current
                apply_sysctl "$(scene_bigdata)"
                show_current
                ;;
            5)
                echo -e "${CYAN}>>> 场景5: 自定义调试模式${NC}"
                echo -e "${YELLOW}将生成空模板，请手动编辑: $SYSCTL_CONF${NC}"
                backup_current
                apply_sysctl "$(scene_custom)"
                echo -e "${GREEN}请执行: vi $SYSCTL_CONF 进行调试${NC}"
                ;;
            6)
                echo -e "${CYAN}>>> 场景6: Java应用服务器 / Tomcat / SpringBoot${NC}"
                backup_current
                apply_sysctl "$(scene_tomcat)"
                show_current
                ;;
            b|B)
                show_current
                ;;
            r|R)
                rollback
                ;;
            q|Q)
                echo -e "${GREEN}退出。${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新输入！${NC}"
                ;;
        esac
        
        echo ""
        read -rp "按 Enter 键返回主菜单..."
        clear
    done
}

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本！${NC}"
    exit 1
fi

main