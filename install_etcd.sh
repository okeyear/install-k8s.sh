#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en


### 1. on etcd01/k8s-master01
## 下载 解压etcd https://github.com/etcd-io/etcd/releases
export ETCD_VER='v3.5.9'
sudo tar -xf etcd-${ETCD_VER}-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin etcd-${ETCD_VER}-linux-amd64/etcd{,ctl}
etcd --version
etcdctl version


# 证书从当前目录拷贝到本机对应目录
# https://github.com/okeyear/scripts/blob/main/k8s/create_k8s_pki_ssl.sh
sudo mkdir -p /etc/etcd/ssl /var/lib/etcd
sudo cp ca.pem /etc/etcd/ssl/
sudo cp etcd*.pem /etc/etcd/ssl/


# 发送组件到其他节点
sudo yum install -y rsync
Nodes='etcd02 etcd03'
for NODE in $Nodes
do 
    echo scp on $NODE; 
    # scp /usr/local/bin/etcd* $NODE:/usr/local/bin/; 
    # 用rsync替代scp,解决目标机器 需要sudu权限的问题
    # 部分证书没同步过去,还有问题,待测试, 可能需要手工传 /etc/etcd/ssl/etcd-key.pem
    SUDO_USER='vagrant'
    ssh $SUDO_USER@$NODE "sudo mkdir -p /etc/etcd/ssl /var/lib/etcd /var/lib/etcd"
    ssh $SUDO_USER@$NODE "sudo yum install -yq rsync"
    rsync -av --progress --rsync-path="sudo rsync" /usr/local/bin/etcd* $SUDO_USER@$NODE:/usr/local/bin/; 
    rsync -av --progress --rsync-path="sudo rsync" ca.pem $SUDO_USER@$NODE:/etc/etcd/ssl/;
    rsync -av --progress --rsync-path="sudo rsync" etcd*.pem $SUDO_USER@$NODE:/etc/etcd/ssl/;
done

# 配置文件/etc/etcd/etcd.conf说明:
# ETCD_HEARTBEAT_INTERVAL 客户端连接后的心跳间隔（毫秒）
# ETCD_NAME=节点名称,集群中唯一
# ETCD_DATA_DIR=数据目录
# ETCD_LISTEN_PEER_URLS=集群通信监听地址
# ETCD_LISTEN_CLIENT_URLS=客户端访问监听地址
# #[cluster]
# ETCD_INITIAL_ADVERTISE_PEER_URLS=集群通告地址
# ETCD_ADVERTISE_CLIENT_URLS=客户端通告地址
# ETCD_INITIAL_CLUSTER=集群节点地址
# ETCD_INITIAL_CLUSTER_TOKEN=集群token
# ETCD_INITIAL_CLUSTER_STATE=加入集群的当前状态, new是新集群, existing表示加入已有集群


### 2. on k8s-master01/02/03 

# etcd所有节点, 创建etcd配置文件, 之后同时启动
sudo tee /etc/etcd/etcd.conf <<EOF
# [member]
# ETCD_HEARTBEAT_INTERVAL=1000
ETCD_NAME=$(grep "$(hostname)" /etc/hosts | grep -o 'etcd[0-9]*')
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_PEER_URLS="https://$(grep "$(hostname)" /etc/hosts | awk '{print $1}'):2380" 
ETCD_LISTEN_CLIENT_URLS="https://$(grep "$(hostname)" /etc/hosts | awk '{print $1}'):2379,https://127.0.0.1:2379"
#[cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://$(grep "$(hostname)" /etc/hosts | awk '{print $1}'):2380"
ETCD_ADVERTISE_CLIENT_URLS="https://$(grep "$(hostname)" /etc/hosts | awk '{print $1}'):2379"
# notice: hostname & ip position in /etc/hosts
ETCD_INITIAL_CLUSTER="$(awk '/etcd/{printf $2"=https://"$1":2380,"}' /etc/hosts | sed 's/,$//')"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-token"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF


# etcd所有节点, 创建etcd配置文件, 之后同时启动
# source /etc/etcd/etcd.conf
sudo tee /usr/lib/systemd/system/etcd.service  <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd
EnvironmentFile=-/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd \
  --cert-file=/etc/etcd/ssl/etcd.pem \
  --key-file=/etc/etcd/ssl/etcd-key.pem \
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \
  --trusted-ca-file=/etc/etcd/ssl/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ssl/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --auto-compaction-mode=periodic \
  --auto-compaction-retention=1 \
  --max-request-bytes=33554432 \
  --quota-backend-bytes=6442450944 \
  --heartbeat-interval 1000 \
  --election-timeout 5000

Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
#  --data-dir="/var/lib/etcd" \
#   --wal-dir=/data/k8s/etcd/wal \
# 启动etcd服务
sudo systemctl daemon-reload
sudo systemctl enable --now etcd.service
sudo systemctl restart etcd.service
sudo systemctl status etcd.service

# 参数说明
# --initial-cluster：集群当中的其他节点
# --cert-file：etcd证书路径
# --key-file：etcd私钥路径
# --peer-cert-file：对等证书(双向证书)路径
# --peer-key-file：对等证书(双向证书)私钥路径
# --trusted-ca-file：作为客户端时的CA证书路径
# --peer-trusted-ca-file：对等证书的CA证书路径
# --initial-advertise-peer-urls：列出集群成员通信的URL，用于通告集群其他成员
# --listen-peer-urls：用于监听集群其他成员的URL列表
# --listen-client-urls：用于监听客户端通讯的URL列表
# --advertise-client-urls：通告客户端的URL，用于列出所有客户端
# --initial-cluster-token：etcd集群的初始集群令牌，服务器必须通过令牌才能加入etcd集群


### 3. 测试etcd集群是否正常
# cluster
ETCDCTL_API=3 /usr/local/bin/etcdctl \
    --write-out=table \
    --cacert=ca.pem \
    --cert=etcd.pem \
    --key=etcd-key.pem \
    --endpoints="$(awk '/etcd/{printf "https://"$1":2379,"}' /etc/hosts | sed 's/,$//')" \
    endpoint health
    # endpoint status
    # member list
    # check perf

# /usr/local/bin/cfssl-certinfo --cert /etc/etcd/ssl/

