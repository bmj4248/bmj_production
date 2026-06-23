#!/bin/bash
#
#********************************************************************
#Author:            bmj
#QQ:                29308620
#Date:              2022-10-14
#FileName:          install_docker_offline.sh
#URL:               http://www.itbmj.com
#Description:       The test script
#Copyright (C):     2024 All rights reserved
#********************************************************************

#支持在线和离线安装

DOCKER_VERSION=29.6.0
#DOCKER_VERSION=29.3.1
#DOCKER_VERSION=29.1.5
#DOCKER_VERSION=28.5.1
#DOCKER_VERSION=28.3.3
#DOCKER_VERSION=28.2.2
#DOCKER_VERSION=28.0.4
#DOCKER_VERSION=27.5.1
#DOCKER_VERSION=26.1.4
#DOCKER_VERSION=26.0.0
#DOCKER_VERSION=24.0.7
#DOCKER_VERSION=24.0.5
#DOCKER_VERSION=23.0.3
#DOCKER_VERSION=20.10.19

#URL=https://mirrors.tuna.tsinghua.edu.cn/docker-ce
URL=https://mirrors.aliyun.com/docker-ce
#URL=https://download.docker.com

color () {
    RES_COL=60
    MOVE_TO_COL="echo -en \\033[${RES_COL}G"
    SETCOLOR_SUCCESS="echo -en \\033[1;32m"
    SETCOLOR_FAILURE="echo -en \\033[1;31m"
    SETCOLOR_WARNING="echo -en \\033[1;33m"
    SETCOLOR_NORMAL="echo -en \E[0m"
    echo -n "$1" && $MOVE_TO_COL
    echo -n "["
    if [ $2 = "success" -o $2 = "0" ] ;then
        ${SETCOLOR_SUCCESS}
        echo -n $"  OK  "    
    elif [ $2 = "failure" -o $2 = "1"  ] ;then 
        ${SETCOLOR_FAILURE}
        echo -n $"FAILED"
    else
        ${SETCOLOR_WARNING}
        echo -n $"WARNING"
    fi
    ${SETCOLOR_NORMAL}
    echo -n "]"
    echo 
}

prepare () {
    if [ ! -e docker-${DOCKER_VERSION}.tgz ];then
        #wget ${URL}/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz
        wget ${URL}/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz
    fi
    [ $? -ne 0  ] && { echo "文件下载失败"; exit; }
}

install_docker () {
    tar xf docker-${DOCKER_VERSION}.tgz -C /data/soft/
    cp /data/sotf/docker/* /usr/local/bin/
    cat > /lib/systemd/system/docker.service <<-EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/local/bin/dockerd -H unix://var/run/docker.sock
ExecReload=/bin/kill -s HUP \$MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
# restart the docker process if it exits prematurely
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

config_docker () {
    mkdir -p /etc/docker
    tee /etc/docker/daemon.json <<-'EOF'
    {
      "registry-mirrors": ["https://docker.m.daocloud.io","https://docker.1panel.live","https://docker.1ms.run","https://docker.xuanyuan.me"],
      "insecure-registries": ["harbor.wang.org"]
     }
EOF
    #systemctl restart docker

}

start_docker (){
    systemctl enable --now docker
    docker version && color "Docker 安装成功" 0 ||  color "Docker 安装失败" 1
}


config_docker_completion () {
    #wget -P /etc/bash_completion.d http://www.wangxiaochun.com:8888/testdir/docker/docker_completion.sh
    curl https://raw.githubusercontent.com/docker/docker-ce/master/components/cli/contrib/completion/bash/docker -o /etc/bash_completion.d/docker.sh
    #source /etc/bash_completion.d/docker_completion.sh
}


prepare

install_docker

config_docker

start_docker

config_docker_completion
