#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en

sudo yum -y install haproxy keepalived
##########################
# haproxy 配置 ha1和ha2
sudo tee /etc/haproxy/haproxy.cfg <<EOF
global
    maxconn     2000
    ulimit-n 16384
    log         127.0.0.1 local0 err
    stats timeout 30s

defaults
    mode                    http
    log                     global
    option                  httplog
    retries                 3
    timeout http-request    15s
    timeout connect         5000
    timeout client          50000
    timeout server          50000
    timeout http-keep-alive 15s

frontend monitor-in
    bind *:33305
    mode http
    option httplog
    monitor-uri /monitor

frontend k8s-master
    bind 0.0.0.0:8443
    bind 127.0.0.1:8443
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    default_backend k8s-master

backend k8s-master
    mode tcp
    option tcplog
    option tcp-check
    balance     roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server  k8s-master01 $(grep "k8s-master01" /etc/hosts | grep -v ^127 | awk '{print $1}'):6443 check
    server  k8s-master02 $(grep "k8s-master02" /etc/hosts | grep -v ^127 | awk '{print $1}'):6443 check
    server  k8s-master03 $(grep "k8s-master03" /etc/hosts | grep -v ^127 | awk '{print $1}'):6443 check
EOF

###############
# ha1 ha2上的检测脚本
sudo tee /etc/keepalived/chk_haproxy.sh <<EOF
#!/bin/bash
err=0
for k in \$(seq 1 3)
do
    check_code=\$(pgrep haproxy)
    if [[ \$check_code == "" ]]; then
        err=\$(expr \$err + 1)
        sleep 1
        continue
    else
        err=0
        break
    fi

    if [[ \$err != "0" ]]; then
        echo "systemctl stop keepalived"
        /usr/bin/systemctl stop keepalived
    else
        exit 0
    fi   
done
EOF

sudo chmod +x /etc/keepalived/chk_haproxy.sh
###########################
# keepalived ha01 ha02配置:
sudo tee /etc/keepalived/keepalived.conf <<EOF
global_defs {
   router_id LVS_DEVEL
   enable_script_security

}

vrrp_script chk_haproxy {
    script "/etc/keepalived/chk_haproxy.sh"  # haproxy 检测
    interval 5  # 每2秒执行一次检测
    weight -5 # 权重变化
    fail 2
    rise 1
}

vrrp_instance VI_1 {
  # interface $(cd /sys/class/net/; echo e*)
  interface $(ip -o -4 a | grep $(grep "$(hostname)" /etc/hosts | awk '{print $1}') | awk '{print $2}')
  state $([ "$( grep "$(hostname)" /etc/hosts| grep -c etcd01)" -eq 1 ] && echo MASTER || echo BACKUP ) # MASTER # backup节点设为BACKUP
  virtual_router_id 51 # id设为相同，表示是同一个虚拟路由组
  priority $([ "$( grep "$(hostname)" /etc/hosts| grep -c etcd01)" -eq 1 ]  ] && echo 100 || echo 99 ) #初始权重
  nopreempt #可抢占
  advert_int 2 # 同步时间间隔，秒。
  authentication {
    auth_type PASS
    auth_pass ChangeMe@2022
  }
  virtual_ipaddress {
    $(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}')  # vip
  }
  track_script {
      chk_haproxy
  }
}
EOF

# 启动ha1 ha2上的服务
sudo systemctl enable --now haproxy keepalived
sudo systemctl restart haproxy keepalived
