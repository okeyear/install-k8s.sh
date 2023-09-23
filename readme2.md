# k8s之二进制安装new


## 规划
master node节点的IP, 以及service的IP, 和pod的IP段, 都不能冲突.

* os: almalinux8
* k8s小版本用5以后的,比较稳定
* 3个master节点 2C2G40G,同时安装etcd， 前两个节点同时安装haproxy keepalived
* 1个node节点2C2G40G
* k8s service网段: 10.96.0.0/12
* k8s pod网段: 10.244.0.0/16
* k8s node网段: 10.10.10.0/24





### 主机规划
|hostname|cpu mem|type|ip|service|
| ----- | ----- | ----- | ----- | ----- |
|k8s-mater01|2C4G|master, etcd,haproxy, keepalived| |kube-apiserver, kube-controllder-manager, kube-scheduler, etcd, kubelet, kube-proxy, containerd, runc|
|k8s-mater02|2C4G|master, etcd,haproxy, keepalived| |kube-apiserver, kube-controllder-manager, kube-scheduler, etcd, kubelet, kube-proxy, containerd, runc|
|k8s-mater03|2C4G|master, etcd| |kube-apiserver, kube-controllder-manager, kube-scheduler, etcd, kubelet, kube-proxy, containerd, runc|
|k8s-node01|2C4G|worker| |kubelet, kube-proxy, containerd, runc|
|NA|NA|LB-VIP(虚拟IP)| |haproxy, keepalived 的 vip|

### 软件版本
|software|version|remark|
| ----- | ----- | ----- |
|OS|AlmaLinux 8| |
|kubernetes|v1.27.1| |
|etcd|v3.5.8| |
|calico| | |
|coredns| | |
|containerd|v1.7.0| |
|runc|v1.1.3| |
|haproxy| |yum/apt default|
|keepalived| |yum/apt default|



### Vagrantfile
两个网卡，一个默认的nat， 一个是私有网络；

nat网络用于vagrant连接

私有网络用于vm之间通信，固定IP，k8s之间的业务IP

```bash
# -*- mode: ruby -*-
# vi: set ft=ruby :
boxes = [
    {
        :hostname => "k8s-master01",
        :mem => "4096",
        :cpu => 2,
        :ipaddr => "192.168.137.101"
    },
    {
        :hostname => "k8s-master02",
        :mem => "4096",
        :cpu => 2,
        :ipaddr => "192.168.137.102"
    },
    {
        :hostname => "k8s-master03",
        :mem => "4096",
        :cpu => 2,
        :ipaddr => "192.168.137.103"
    },
    {
        :hostname => "k8s-node01",
        :mem => "2048",
        :cpu => 2,
        :ipaddr => "192.168.137.111"
    }
]

# ENV
ENV["LC_ALL"] = "en_US.UTF-8"
# All Vagrant configuration is done below.
Vagrant.configure("2") do |config|
  # OS????
  # config.vm.box = "CentOS-7"
  config.vm.box = "AlmaLinux-8.VMwareFusion"
  # config.vm.disk :dvd, name: "Tools", file: "D:/Program Files/Oracle/VirtualBox/VBoxGuestAdditions.iso"
  # box proxy setting
  if Vagrant.has_plugin?("vagrant-proxyconf")
    config.proxy.http     = "http://6.86.3.12:3128/"
    config.proxy.https    = "http://6.86.3.12:3128/"
    config.proxy.no_proxy = "localhost,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.0/8,6.86.0.0/16"
  end
  boxes.each do |opts|
    config.vm.define opts[:hostname] do |config|
      # ??hostname
      config.vm.hostname = opts[:hostname]
      # ?????IP
      config.vm.network "private_network", ip: opts[:ipaddr]
      # share folder
      config.vm.synced_folder "../data", "/vagrant_data"
      # ????provide??cpu mem
      config.vm.provider "vmware_desktop" do |v|
        v.vmx["memsize"] = opts[:mem]
        v.vmx["numvcpus"] = opts[:cpu]
        v.gui = true 
      end
      config.vm.provider "virtualbox" do |v|
        v.customize ["modifyvm", :id, "--memory", opts[:mem]]
        v.customize ["modifyvm", :id, "--cpus", opts[:cpu]]
        v.gui = true         
        if Vagrant.has_plugin?("vagrant-vbguest")
          config.vbguest.auto_update = false
        end
      end
      config.vm.provider "hyperv" do |v|
        v.cpus = opts[:cpu]
        v.maxmemory = opts[:mem]
        v.memory = opts[:mem]
        v.gui = true         
      end
    end
  end
  # ??shell??
  # config.vm.provision "shell", privileged: false, path: "./setup.sh"
  config.vm.provision "shell", run: "always", inline: <<-SHELL
    echo $(date +%FT%T) shell begin
    # echo 'PermitRootLogin yes' | sudo tee -a /etc/ssh/sshd_config
    # sudo service sshd restart
    # echo vagrant | sudo passwd --stdin root
    sudo sed -i '/\-/d' /etc/hosts
    echo '192.168.137.101 k8s-master01 etcd01 ha01' | sudo tee -a /etc/hosts
    echo '192.168.137.102 k8s-master02 etcd02 ha02' | sudo tee -a /etc/hosts
    echo '192.168.137.103 k8s-master03 etcd03' | sudo tee -a /etc/hosts
    echo '192.168.137.111 k8s-node01' | sudo tee -a /etc/hosts
    echo '192.168.137.200 lb-vip' | sudo tee -a /etc/hosts
    # curl -sSL http://6.86.2.25/scripts/set_yum_repos.sh | sudo sh -
    echo $(date +%FT%T) shell end
    # sudo reboot
  SHELL
end

# vagrant up --provider virtualbox
# vagrant up --provider virtualbox
# vagrant ssh-config > ~/.ssh/config
```


### CentOS 7升级内核
仅用于CentOS 7, 其他OS可选

```bash
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en
# set -e

# 1. update kernel
# config repo: epel & elrepo
sudo yum install -y epel-release
sudo yum install -y yum-plugin-elrepo
if [ ! -s /etc/yum.repos.d/elrepo.repo ] ; then
    sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    sudo yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
fi

# replace to tuna mirrors
elrepo_mirror='https://mirrors.tuna.tsinghua.edu.cn/elrepo'
sudo sed -e 's|^mirrorlist=|#mirrorlist=|g' \
    -e "s|^baseurl=http://elrepo.org/linux|baseurl=${elrepo_mirror}|g" \
    -i.bak.$(date +%FT%T) \
    /etc/yum.repos.d/elrepo.repo

# install elrepo kernel
sudo yum --disablerepo=* --enablerepo=elrepo-kernel install -y kernel-ml

# set grub2 default boot menu
sudo grub2-editenv list

# elrepo_menu=$(awk -F"'" '/menuentry.*elrepo/{print $2}' /boot/grub2/grub.cfg | head -n 1)
# awk -F"'" '/^menuentry/{print $2}'  /boot/efi/EFI/redhat/grub.cfg
# grub2-set-default "${elrepo_menu}"

sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo grub2-set-default 0
sudo grub2-editenv list

# install kernel-headers
sudo yum remove -y kernel-tools kernel-tools-libs kernel-headers
sudo yum --enablerepo=elrepo-kernel \
    install -y  kernel-ml{,-tools,-devel,-headers}

# reboot 
# waiting for reboot
# uname -r
```


## 所有节点VM基本调整
### 设置yum/apt源
设置公司内部源

```bash
curl -sSL http://6.86.2.25/scripts/set_yum_repos.sh | sudo sh -
```
设置公网源

```bash
# 2. set yum/apt mirror
echo 'export PATH=/usr/local/bin:$PATH' | sudo tee /etc/profile.d/localbin.sh
source /etc/profile.d/localbin.sh

if [ -r /etc/os-release ]; then
	. /etc/os-release
else
	# if not existed /etc/os-release, the script will exit
	echo -e "\e[0;31mNot supported OS\e[0m, \e[0;32m${OS}\e[0m"
	exit
fi

# Package Manager:  yum / apt / apk
case $ID in 	
	centos) 
		export PM='yum' 
    sudo curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-$(rpm -E %{rhel}).repo
    # curl -sSL https://raw.githubusercontent.com/okeyear/scripts/main/shell/update_kernel_el.sh | sudo sh - 
		;;
	almalinux) 
		export PM='yum' 
		# set mirrors
		sudo sed -e 's|^mirrorlist=|#mirrorlist=|g' \
		  -e 's|^#.*baseurl=https://repo.almalinux.org|baseurl=https://mirrors.aliyun.com|g' \
		  -i.bak \
		  /etc/yum.repos.d/almalinux*.repo
		  ;;
esac


```
安装必备软件

```bash
sudo yum install -y wget vim jq psmisc vim net-tools telnet git yum-utils device-mapper-persistent-data lvm2 lrzsz rsync bind-utils
```


### 参数调整


```bash
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en
# set -e

echo 'export PATH=/usr/local/bin:$PATH' | sudo tee /etc/profile.d/localbin.sh
source /etc/profile.d/localbin.sh

# 3. firewall
# centos7 禁用NetworkManager, centos8不用禁用
# systemctl disable --now firewalld dnsmasq NetworkManager
sudo systemctl disable --now firewalld
sudo firewall-cmd --state
# master节点
# sudo firewall-cmd --permanent --add-port={53,179,5000,2379,2380,6443,10248,10250,10251,10252,10255}/tcp
# node节点
# sudo firewall-cmd --permanent --add-port={10250,30000-32767}/tcp
# 重新加载防火墙
# sudo firewall-cmd --reload

# 4. selinux
sudo setenforce 0
sudo sed -i '/^SELINUX=/cSELINUX=disabled' /etc/selinux/config /etc/sysconfig/selinux
sudo sestatus

# 5. swap
sudo swapoff -a && sudo sysctl -w vm.swappiness=0
# sed -i 's/.*swap.*/#&/' /etc/fstab
sudo sed -e '/swap/s/^/#/g' -i /etc/fstab

# 6. timezone
sudo timedatectl set-timezone Asia/Shanghai

# 7. ntp chrony
sudo yum install -y chrony
sudo sed -i '/^server/d' /etc/chrony.conf
sudo sed -i '/^pool/d' /etc/chrony.conf
sudo tee -a /etc/chrony.conf <<EOF
#server ntp.aliyun.com iburst
server time.windows.com iburst
#server ntp.tencent.com iburst
#server cn.ntp.org.cn iburst
EOF
sudo systemctl enable --now chronyd
sudo systemctl restart chronyd

# 8. limits, nofile nproc
sudo ulimit -SHn 65535
sudo tee /etc/security/limits.d/20-nproc.conf <<EOF
*          soft    nproc     655350
*          hard    nproc     655350
root       soft    nproc     unlimited
EOF

sudo tee /etc/security/limits.d/nofile.conf <<EOF
*          soft    nofile     655350
*          hard    nofile     655350
EOF

sudo tee /etc/security/limits.d/memlock.conf <<EOF
*          soft    memlock    unlimited
*          hard    memlock    unlimited
EOF

# 9. kernel 设置内核参数
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
# ERROR FileContent--proc-sys-net-ipv4-ip_forward
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

net.ipv4.tcp_tw_recycle=0
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_max_tw_buckets=36000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_orphans=327680
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=16384
net.ipv4.ip_conntrack_max=131072
net.ipv4.tcp_timestamps=0
net.core.somaxconn=16384

vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
fs.may_detach_mounts=1
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720  
EOF
sudo sysctl --system

###################
# 10. ipvsadm 
# kube-proxy支持 iptables 和 ipvs 两种模式
# http://www.linuxvirtualserver.org/software/
sudo yum install -y ipset ipvsadm ipset sysstat conntrack libseccomp
sudo mkdir -pv /etc/systemd/system/kubelet.service.d
# kernel 4.19+中 nf_conntrack_ipv4 改为 nf_conntrack
cat <<EOF | sudo tee /etc/modules-load.d/ipvs.conf
ip_vs
ip_vs_lc
ip_vs_wlc
ip_vs_rr
ip_vs_wrr
ip_vs_lblc
ip_vs_lblcr
ip_vs_dh
ip_vs_sh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
EOF
# sudo ls /lib/modules/$(uname -r)/kernel/net/netfilter/ipvs|grep -o "^[^.]*" | sudo tee -a /etc/modules-load.d/ipvs.conf
# systemctl status systemd-modules-load.service

# sudo tee /etc/systemd/system/kubelet.service.d/10-proxy-ipvs.conf <<EOF
# [Service]
# ExecStartPre=-/sbin/modprobe ip_vs
# ExecStartPre=-/sbin/modprobe ip_vs_rr
# ExecStartPre=-/sbin/modprobe ip_vs_wrr
# ExecStartPre=-/sbin/modprobe ip_vs_sh
# ExecStartPre=-/sbin/modprobe nf_conntrack
# EOF

# after reboot, check below:
lsmod | grep -e ip_vs -e nf_conntrack 
lsmod | grep -e overlay -e br_netfilter

# dns
# sudo sed -i '/nameserver/cnameserver 6.86.3.12'  /etc/resolv.conf
```


### 下载软件
用到的软件大部分会从github下载，如果不能连接，请先离线下载，放入master01节点

```bash
# 后续在线下载，很多时候会用到本函数
function get_github_latest_release() {
    # 如果用自己的token可以解除调用api次数限制
    # token='github_pat_11xxx'
    # curl -u okeyear:$token --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}
```
### 证书准备 cfssl工具
master01上

下载生成证书工具cfss. [https://github.com/cloudflare/cfssl](https://github.com/cloudflare/cfssl)

cfssl是用go编写, 由CloudFlare开源的一款PKI/TLS工具,主要程序有:

* cfssl 命令行工具
* cfssljson 用来从cfssl程序获取json输出,并将证书,密钥,CSR和bundle写入文件中



需要的证书: [https://kubernetes.io/docs/setup/best-practices/certificates/](https://kubernetes.io/docs/setup/best-practices/certificates/)

k8s证书签发工具: [https://kubernetes.io/docs/tasks/administer-cluster/certificates/](https://kubernetes.io/docs/tasks/administer-cluster/certificates/)



下载cfssl工具并安装: 

```bash
function download_cfssl(){
    cfssl_ver=$(get_github_latest_release "cloudflare/cfssl")
	# github.com/cloudflare/cfssl
	wget -c "https://github.com/cloudflare/cfssl/releases/download/${cfssl_ver}/cfssl_${cfssl_ver/v/}_linux_amd64"
	wget -c "https://github.com/cloudflare/cfssl/releases/download/${cfssl_ver}/cfssljson_${cfssl_ver/v/}_linux_amd64"
	wget -c "https://github.com/cloudflare/cfssl/releases/download/${cfssl_ver}/cfssl-certinfo_${cfssl_ver/v/}_linux_amd64"
}

### 1. install cfssl
# cfssl required, https://github.com/cloudflare/cfssl/releases
: <<EOF
cfssl_ver='1.6.4' # $(get_github_latest_release "cloudflare/cfssl")
sudo install -m 755 "cfssl_${cfssl_ver/v/}_linux_amd64" /bin/cfssl
sudo install -m 755 "cfssljson_${cfssl_ver/v/}_linux_amd64" /bin/cfssljson
sudo install -m 755 "cfssl-certinfo_${cfssl_ver/v/}_linux_amd64" /bin/cfssl-certinfo
cfssl version
EOF
```


### 证书签发
```bash
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en

### 2. CA Cert
# 设置一个环境变量，用于后续处理证书， 完全搭建好集群之后，可选取消这个变量
export SUBJ='/C=CN/ST=Beijing/L=Beijing/O=kubernetes/OU=CN/CN=www.devsecops.com.cn'
eval $(echo "${SUBJ}" |sed 's@^/@@' | sed 's@/@;eval @g')
# -subj 用于设置 Subject Name
# 其中 C 表示 Country or Region
# ST 表示 State/Province
# L 表示 Locality
# O 表示 Organization
# OU 表示 Organization Unit
# CN 表示 Common Name

# CA CSR
# cfssl print-defaults csr > csr.json # 这个可以参考,可以在这个基础上进行修改
sudo tee ca-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
      "C": "$C",
      "ST": "$ST",
      "L": "$L",
      "O": "$O",
      "OU": "$OU"
    }],
  "CA": {
    "expiry": "87600h"
  }
}
EOF

# 生成CA证书
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
# 会生成以下三个文件
# ca-key.pem  私钥PKEY
# ca.csr  CSR文件
# ca.pem  证书CERT

# 配置ca证书策略
# cfssl print-defaults config | sudo tee ca-config.json # 这个可以参考,可以在这个基础上进行修改
sudo tee ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "expiry": "87600h",
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ]
      }
    }
  }
}
EOF

# server auth 表示client可以对,使用该CA的server提供的证书,进行验证
# client auth 表示server可以对,使用该CA的client提供的证书,进行验证


### 3. etcd cert

# 配置etcd csr请求文件
sudo tee etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "$(grep "etcd01" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "etcd02" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "etcd03" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "etcd01",
    "etcd02",
    "etcd03"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
      "C": "$C",
      "ST": "$ST",
      "L": "$L",
      "O": "$O",
      "OU": "$OU"
    }]
}
EOF

# 签发生成etcd证书
cfssl gencert -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

#  openssl x509 -in /etc/etcd/ssl/etcd.pem -text -noout


### 4. kube-apiserver CSR
# 当前IP地址, 预留一些以后用, 这里只需要master, etcd, lb即可, node节点IP没必要写进去
sudo tee kube-apiserver-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "$(grep "etcd01" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "etcd02" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "etcd03" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master01" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master02" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master03" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "10.96.0.1", 
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
      "C": "$C",
      "ST": "$ST",
      "L": "$L",
      "O": "$O",
      "OU": "$OU"
    }]
}
EOF

# 签发证书, 注意?? 是否需要加 hostname加etcd的地址ip1,ip2..ipn
cfssl gencert -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes kube-apiserver-csr.json | cfssljson -bare kube-apiserver
# kube-apiserver-key.pem  kube-apiserver.csr  kube-apiserver.pem

# 生成token
sudo tee token.csv <<EOF
$(head -c 16 /dev/urandom | od -An -t x | tr -d ' '),kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF


### 5. kubectl CSR
# 当前IP地址, 预留一些以后用, 注意这地方的O 和OU
sudo tee admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [
    "127.0.0.1",
    "$(grep "etcd01" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "etcd02" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "etcd03" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master01" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master02" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master03" /etc/hosts | grep -v ^127 | awk '{print $1}')"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
      "C": "$C",
      "ST": "$ST",
      "L": "$L",
      "O": "system:masters",
      "OU": "system"
    }]
}
EOF

# 签发证书
cfssl gencert -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes admin-csr.json | cfssljson -bare admin


### 6. kube-controller-manager cert , 注意O OU

sudo tee kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "hosts": [
    "127.0.0.1",
    "$(grep "k8s-master01" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master02" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master03" /etc/hosts | grep -v ^127 | awk '{print $1}')"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
      "C": "$C",
      "ST": "$ST",
      "L": "$L",
      "O": "system:kube-controller-manager",
      "OU": "system"
    }]
}
EOF

# 签发证书
cfssl gencert -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager


### 7. kube-scheduler cert
sudo tee kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "hosts": [
    "127.0.0.1",
    "$(grep "k8s-master01" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master02" /etc/hosts | grep -v ^127 | awk '{print $1}')",
    "$(grep "k8s-master03" /etc/hosts | grep -v ^127 | awk '{print $1}')"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
      "C": "$C",
      "ST": "$ST",
      "L": "$L",
      "O": "system:kube-scheduler",
      "OU": "system"
    }]
}
EOF

# 签发证书
cfssl gencert -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler


### 8. kube-proxy cert

sudo tee kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
      "C": "$C",
      "ST": "$ST",
      "L": "$L",
      "O": "$O",
      "OU": "$OU"
    }]
}
EOF

# 签发证书
cfssl gencert -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
    
    
### 9. token
# 生成token
sudo tee token.csv <<EOF
$(head -c 16 /dev/urandom | od -An -t x | tr -d ' '),kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

# 说明
# 创建TLS机制所需TOKEN
# TLS Bootstraping: Master apiserver启用TLS认证后, Node节点kubelet 和 kube-proxy域kube-apiserver进行通信,
# 必须使用CA签发的有效证书才可以.当Node节点很多时候, 这种客户端证书颁发需要大量工作, 同样也会增加集群扩展复杂度.
# 为了简化流程, kubernetes 引入了TLS Bootstraping机制来自动颁发客户端证书, kubelet会以一个低权限用户自动向apiserver申请证书, kubelet的证书由apiserver动态签发.
# 所以强烈建议在Node上使用这种方式.
# 目前主要用于Kubelet, kube-proxy还是由我们统一颁发一个证书.

# rm -f *.pem *.csr *-csr.json
```


### master01配置ssh免密码到其他节点
```bash
# on mster01
# 阿里云或者aws上需要一台单独节点安装kubectl,不能在master上,(lb后端的机器不允许反向连lb)

# 选项1： sudo到root用户,在root下免密码到其他节点
sudo -i
echo -e "y\n\n"| ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
ssh-copy-id $SUDO_USER@k8s-master02
ssh-copy-id $SUDO_USER@k8s-master03
ssh-copy-id $SUDO_USER@k8s-node01
# ssh-copy-id $SUDO_USER@k8s-node02

# 选项2： 当前非root用户（有免密码sudo权限）免密码到其他节点
# echo -e "y\n\n"| ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
# ssh-copy-id k8s-master02
# ssh-copy-id k8s-master03
```


## 安装etcd
### 安装etcd01
```bash
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en


### 1. on etcd01/k8s-master01
## 下载 解压etcd https://github.com/etcd-io/etcd/releases
export ETCD_VER='v3.5.8'
sudo tar -xf etcd-${ETCD_VER}-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin etcd-${ETCD_VER}-linux-amd64/etcd{,ctl}
etcd --version
etcdctl version


# 证书从当前目录拷贝到本机对应目录
# https://github.com/okeyear/scripts/blob/main/k8s/create_k8s_pki_ssl.sh
sudo mkdir -p /etc/etcd/ssl /var/lib/etcd
sudo cp ca.pem /etc/etcd/ssl/
sudo cp etcd*.pem /etc/etcd/ssl/
```


### 从etcd01拷贝到etcd02 etcd03
```bash
# 发送组件到其他节点
Nodes='etcd02 etcd03'
for NODE in $Nodes
do 
    echo scp on $NODE; 
    # scp /usr/local/bin/etcd* $NODE:/usr/local/bin/; 
    # 用rsync替代scp,解决目标机器 需要sudu权限的问题
    # 部分证书没同步过去,还有问题,待测试, 可能需要手工传 /etc/etcd/ssl/etcd-key.pem
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
```


### etcd所有节点的配置及启动
```bash
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
ETCD_INITIAL_CLUSTER="$(awk '/etcd/{printf $3"=https://"$1":2380,"}' /etc/hosts | sed 's/,$//')"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
# ETCD_INITIAL_CLUSTER_STATE="new"
# ETCD_INITIAL_CLUSTER_STATE="exist"
ETCD_INITIAL_CLUSTER_STATE="$([ "$( grep "$(hostname)" /etc/hosts| grep -c etcd01)" -eq 1 ] && echo new || echo existing)"
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

```


### etcd集群的验证
```bash
### 3. 测试etcd集群是否正常
# cluster
ETCDCTL_API=3 /usr/local/bin/etcdctl \
    --write-out=table \
    --cacert=ca.pem \
    --cert=etcd.pem \
    --key=etcd-key.pem \
    --endpoints="$(awk '/etcd/{printf "https://"$1":2379,"}' /etc/hosts | sed 's/,$//')" \
    member list
    # endpoint status
    # endpoint health
    # check perf

# cfssl-certinfo --cert /etc/etcd/ssl/etcd.pem
```


## k8s master部署
主要包括 

* apiserver 
* kubectl 
* kube-controller-manager
* kube-scheduler



### 解压并拷贝文件到其他节点
```bash
############# k8s-master01上操作
### 解压出需要的组件
# 解压出二进制文件
sudo tar -xf kubernetes-server-linux-amd64.tar.gz --strip-components=3 -C /usr/local/bin kubernetes/server/bin/kube{adm,let,ctl,-apiserver,-controller-manager,-scheduler,-proxy}
# sudo cp -axf kubernetes/server/bin/* /usr/local/bin/
# sudo rm -rf kubernetes
kubelet --version

# 证书拷贝到本机
sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes
sudo cp token.csv ca.pem ca-key.pem kube-apiserver-key.pem kube-apiserver.pem /etc/kubernetes/pki

# 发送组件到其他节点
MasterNodes='k8s-master02 k8s-master03'
for NODE in $MasterNodes
do 
    echo scp on $NODE; 
    ssh $SUDO_USER@$NODE 'sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes';     
    # 用rsync替代scp,解决目标机器 需要sudu权限的问题.master几点如果不跑负载, 不需要拷贝kubelet, kube-proxy过去;
    rsync -av --progress --rsync-path="sudo rsync" /usr/local/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy} $SUDO_USER@$NODE:/usr/local/bin/; 
    rsync -av --progress  --rsync-path="sudo rsync" token.csv ca.pem ca-key.pem kube-apiserver-key.pem kube-apiserver.pem $SUDO_USER@$NODE:/etc/kubernetes/pki; 
done

```


### 安装apiserver
```bash

############# 所有 k8s-master01/02/03 上操作
# 只需要注意apiserver的监听地址, 其他两个组件都是连接本地的8080端口

### 1. kube-apiserver 配置文件和启动脚本
# apiserver 服务配置文件
sudo tee /etc/kubernetes/kube-apiserver.conf <<EOF
KUBE_APISERVER_OPTS=" --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota \
    --anonymous-auth=false \
    --bind-address=$(grep "$(hostname)" /etc/hosts| grep -v ^127 | awk '{print $1}')  \
    --secure-port=6443  \
    --allow-privileged=true \
    --advertise-address=$(grep "$(hostname)" /etc/hosts| grep -v ^127 | awk '{print $1}') \
    --authorization-mode=Node,RBAC  \
    --runtime-config=api/all=true \
    --enable-bootstrap-token-auth=true  \
    --service-cluster-ip-range=10.96.0.0/12  \
    --service-node-port-range=30000-32767  \
    --token-auth-file=/etc/kubernetes/pki/token.csv \
    --client-ca-file=/etc/kubernetes/pki/ca.pem  \
    --tls-cert-file=/etc/kubernetes/pki/kube-apiserver.pem  \
    --tls-private-key-file=/etc/kubernetes/pki/kube-apiserver-key.pem  \
    --kubelet-client-certificate=/etc/kubernetes/pki/kube-apiserver.pem  \
    --kubelet-client-key=/etc/kubernetes/pki/kube-apiserver-key.pem  \
    --service-account-key-file=/etc/kubernetes/pki/ca-key.pem \
    --service-account-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
    --service-account-issuer=https://kubernetes.default.svc.cluster.local \
    --etcd-servers=https://$(grep "$(hostname)" /etc/hosts| grep -v ^127 | awk '{print $1}'):2379 \
    --etcd-cafile=/etc/etcd/ssl/ca.pem  \
    --etcd-certfile=/etc/etcd/ssl/etcd.pem  \
    --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem  \
    --allow-privileged=true \
    --apiserver-count=3 \
    --audit-log-maxage=30 \
    --audit-log-maxbackup=3 \
    --audit-log-maxsize=100 \
    --audit-log-path=/var/log/kubernetes/kube-apiserver-audit.log \
    --event-ttl=1h \
    --v=2 "
EOF



# apiserver 服务脚本
# service script
sudo tee /usr/lib/systemd/system/kube-apiserver.service << EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=etcd.service
wants=etcd.service
[Service]
EnvironmentFile=-/etc/kubernetes/kube-apiserver.conf
ExecStart=/usr/local/bin/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure
RestartSec=10s
Type=notify
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now kube-apiserver


# test
curl --noproxy "*" --insecure https://k8s-master01:6443/
curl --noproxy "*" --insecure https://k8s-master02:6443/
curl --noproxy "*" --insecure https://k8s-master03:6443/
curl --noproxy "*" --insecure https://lb-vip:8443/

```


### 安装kubectl
```bash

### 2. kubectl 安装配置
# 设置集群参数, 此处lb haproxy也安装在master阶段,为了避免冲突, vip用的8443端口, 不是6443
kubectl config set-cluster kubernetes --certificate-authority=ca.pem \
    --embed-certs=true --server=https://$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}'):8443 --kubeconfig=kubectl.kubeconfig
    
# 设置客户端认证参数
kubectl config set-credentials admin --client-certificate=admin.pem --client-key=admin-key.pem --embed-certs=true --kubeconfig=kubectl.kubeconfig
# 设置上下文参数,包含集群名称和访问集群的用户名字
kubectl config set-context kubernetes --cluster=kubernetes --user=admin --kubeconfig=kubectl.kubeconfig
# 使用默认上下文
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig

############
# 准备kubectl配置文件并进行角色绑定
mkdir ~/.kube
cp kubectl.kubeconfig ~/.kube/config
kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes --kubeconfig=$HOME/.kube/config

# 查看集群状态
export KUBECONFIG=$HOME/.kube/config
kubectl cluster-info
kubectl get componentstatuses
kubectl get all --all-namespaces

######################
# 同步到其他节点
MasterNodes='k8s-master02 k8s-master03'
for NODE in $MasterNodes
do 
    echo scp on $NODE; 
    ssh $SUDO_USER@$NODE 'sudo mkdir -p /root/.kube';     
    rsync -av --progress --rsync-path="sudo rsync" kubectl.kubeconfig $SUDO_USER@$NODE:/root/.kube/config; 
done
```


### 安装kube-controller-manager
主节点安装检查

```bash

### 3. kube-controller-manager 服务和配置
# master01节点

kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true \
    --server=https://$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}'):8443 --kubeconfig=kube-controller-manager.kubeconfig
    
kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.pem --client-key=kube-controller-manager-key.pem --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig
    
kubectl config set-context system:kube-controller-manager --cluster=kubernetes \
    --user=system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig
    
kubectl config use-context system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig

sudo tee kube-controller-manager.conf <<EOF
KUBE_CONTROLLER_MANAGER_OPTS=" --secure-port=10257 \
    --v=2 \
    --tls-cert-file=/etc/kubernetes/pki/kube-controller-manager.pem \
    --tls-private-key-file=/etc/kubernetes/pki/kube-controller-manager-key.pem \
    --root-ca-file=/etc/kubernetes/pki/ca.pem \
    --cluster-name=kubernetes \
    --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \
    --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
    --service-account-private-key-file=/etc/kubernetes/pki/ca-key.pem \
    --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
    --cluster-signing-duration=87600h \
    --feature-gates=RotateKubeletServerCertificate=true \
    --leader-elect=true \
    --use-service-account-credentials=true \
    --node-monitor-grace-period=40s \
    --node-monitor-period=5s \
    --controllers=*,bootstrapsigner,tokencleaner \
    --horizontal-pod-autoscaler-sync-period=10s \
    --allocate-node-cidrs=true \
    --cluster-cidr=10.244.0.0/16 \
    --service-cluster-ip-range=10.96.0.0/12  \
    --node-cidr-mask-size=24 "
EOF
#     --master=127.0.0.1:8080 \

sudo tee kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=network.target
[Service]
EnvironmentFile=-/etc/kubernetes/kube-controller-manager.conf
ExecStart=/usr/local/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

#### 拷贝到本级对应目录
sudo cp kube-controller-manager.conf /etc/kubernetes/
sudo cp kube-controller-manager.kubeconfig /etc/kubernetes/
sudo cp kube-controller-manager*.pem /etc/kubernetes/pki/
sudo cp kube-controller-manager.service /usr/lib/systemd/system/

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable --now kube-controller-manager
sudo systemctl status kube-controller-manager
```
主节点没问题后， 同步到其他节点

```bash
# 主节点没问题后， 同步到其他节点
MasterNodes='k8s-master02 k8s-master03'
for NODE in $MasterNodes
do 
    echo scp on $NODE;   
    rsync -av --progress --rsync-path="sudo rsync" kube-controller-manager.conf kube-controller-manager.kubeconfig $SUDO_USER@$NODE:/etc/kubernetes/    
    rsync -av --progress --rsync-path="sudo rsync" kube-controller-manager.service $SUDO_USER@$NODE:/usr/lib/systemd/system/
    rsync -av --progress --rsync-path="sudo rsync" kube-controller-manager*.pem  $SUDO_USER@$NODE:/etc/kubernetes/pki/
done
```
其他节点启动服务

```bash
# 所有节点
sudo systemctl daemon-reload
sudo systemctl enable --now kube-controller-manager
sudo systemctl status kube-controller-manager
```


### 安装kube-scheduler


```bash
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en

### 4. kube-scheduler 服务和配置

# master01节点

# 设置集群 
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true \
    --server=https://$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}'):8443 --kubeconfig=kube-scheduler.kubeconfig

# 设置认证    
kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem --client-key=kube-scheduler-key.pem --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

# 设置上下文    
kubectl config set-context system:kube-scheduler --cluster=kubernetes \
    --user=system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

# 且换上下文    
kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

sudo tee kube-scheduler.conf <<EOF
KUBE_SCHEDULER_OPTS=" --v=2 \
    --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
    --leader-elect=true 
EOF

#    --authentication-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
#    --authorization-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
#    --client-ca-file=/etc/kubernetes/pki/ca.pem \
#    --tls-cert-file=/etc/kubernetes/pki/kube-scheduler.pem \
#    --tls-private-key-file=/etc/kubernetes/pki/kube-scheduler-key.pem \

sudo tee kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=network.target
[Service]
EnvironmentFile=-/etc/kubernetes/kube-scheduler.conf
ExecStart=/usr/local/bin/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

#### 拷贝到本级对应目录
sudo cp kube-scheduler.kubeconfig /etc/kubernetes/
sudo cp kube-scheduler.conf /etc/kubernetes/
sudo cp kube-scheduler*.pem /etc/kubernetes/pki/
# sudo cp ca.pem /etc/kubernetes/pki/
sudo cp kube-scheduler.service /usr/lib/systemd/system/

```




```bash

# 同步到其他节点
MasterNodes='k8s-master02 k8s-master03'
for NODE in $MasterNodes
do 
    echo scp on $NODE;   
    rsync -av --progress --rsync-path="sudo rsync" kube-scheduler.conf kube-scheduler.kubeconfig $SUDO_USER@$NODE:/etc/kubernetes/
    rsync -av --progress --rsync-path="sudo rsync" kube-scheduler.service $SUDO_USER@$NODE:/usr/lib/systemd/system/
    rsync -av --progress --rsync-path="sudo rsync" kube-scheduler*.pem  $SUDO_USER@$NODE:/etc/kubernetes/pki/
done

# 所有节点
sudo systemctl daemon-reload
sudo systemctl enable --now kube-scheduler
sudo systemctl restart kube-scheduler
sudo systemctl status kube-scheduler
```


### k8s master的HA（haproxy keepalived）
简介

由于ha01 ha02写了hosts, 脚本中判断master和slave的方式是， hosts中同一行存在etcd01和ha01， 那么这个是master；待优化会更号的方式

比如getent hosts ha01或者别的



```bash
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
```




### k8s master的检查
```bash
# 查看集群状态
export KUBECONFIG=$HOME/.kube/config
kubectl cluster-info
kubectl get componentstatuses
kubectl get all --all-namespaces
```
## k8s node部署
主要包括

* containerd
* kubelet

**为了方便，实际操作实在k8s-master01上操作，然后把执行文件和配置文件拷贝到其他master和node**



### k8s master安装containerd
```bash
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en

### 1. master01上containerd
# cri-containerd-cni开头的的这个版本包含 containerd & runc 
containerd_ver='1.7.0'
sudo tar -xf cri-containerd-cni-${containerd_ver}-linux-amd64.tar.gz -C /
sudo install -m 755 runc.amd64 /usr/local/sbin/runc

# create default config
sudo mkdir /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# 主要改三个地方及镜像加速
# root = "/var/lib/containerd"
#     sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6"
#       bin_dir = "/opt/cni/bin"

### 配置containerd sandbox_image 
# 注意，从v1.27开始k8s.gcr.io 更改为 registry.k8s.io
# 问题, Error getting node" err="node not found" 
# 解决办法, containerd配置中, 修改sandbox_image = "k8s.gcr.io/pause:3.6" 为可以拉取到的地址
# a. v1.27以前版本
# grep k8s.gcr.io /etc/containerd/config.toml
# sudo sed -i 's@k8s.gcr.io@registry.cn-hangzhou.aliyuncs.com/google_containers@' /etc/containerd/config.toml
# a. v1.27以后版本
grep registry.k8s.io /etc/containerd/config.toml
sudo sed -i 's@registry.k8s.io@registry.cn-hangzhou.aliyuncs.com/google_containers@' /etc/containerd/config.toml


# above Step 4: systemd cgroup driver
sudo grep SystemdCgroup /etc/containerd/config.toml
sudo sed -i.bak '/SystemdCgroup/s/false/true/' /etc/containerd/config.toml
sudo grep containerd.runtimes.runc.options /etc/containerd/config.toml -A 20

# 错误处理 runc没安装，安装即可
#Unfortunately, an error has occurred:
#        timed out waiting for the condition

# 错误解决 containerd.service is masked
# systemctl unmask containerd

# 错误处理0.1
grep cri /etc/containerd/config.toml
# sed -i '/cri/s/^/#/' /etc/containerd/config.toml

#
grep conf_template /etc/containerd/config.toml
sed -i '/conf_template/s/=.*/= "\/etc\/cni\/net.d\/10-containerd-net.conflist"/' /etc/containerd/config.toml
grep conf_template /etc/containerd/config.toml

# 设置containerd的镜像加速 # imageRepository 
grep 'registry.mirrors' -C 5 /etc/containerd/config.toml
# 待更新: 用python 安装toml模块之后的命令行，去修改这些值, 应该比sed更好一点
# 注意，从v1.27开始k8s.gcr.io 更改为 registry.k8s.io， 下面配置也要更新，待找到新的源
sed -i.bak '/plugins."io.containerd.grpc.v1.cri".registry.mirrors/a    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]\n        endpoint = ["https://registry.docker-cn.com", "http://hub-mirror.c.163.com", "https://xc8hlpxv.mirror.aliyuncs.com", "https://docker.mirrors.ustc.edu.cn" ]\n        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."gcr.io"]\n          endpoint = ["https://gcr.mirrors.ustc.edu.cn"]\n        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."k8s.gcr.io"]\n          endpoint = ["https://gcr.mirrors.ustc.edu.cn/google-containers/"]\n        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]\n          endpoint = ["https://quay.mirrors.ustc.edu.cn"]' /etc/containerd/config.toml

## 如果在内网,不能直接联网,需要设置下proxy
# /etc/systemd/system/containerd.service.d/http_proxy.conf 
# set proxy for containerd
# sudo mkdir -pv /etc/systemd/system/containerd.service.d
# sudo tee /etc/systemd/system/containerd.service.d/http_proxy.conf << EOF
# [Service]
# Environment="HTTP_PROXY=http://6.86.3.12:3128/"
# Environment="HTTPS_PROXY=http://6.86.3.12:3128/"
# Environment="NO_PROXY=10.10.10.101,10.96.0.0/16,127.0.0.1,192.168.0.0/16,localhost"
# EOF

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable --now containerd.service
sudo systemctl restart containerd.service
sudo systemctl status containerd.service
```


同步到其他节点

```bash
# 同步到其他节点
MasterNodes='k8s-master02 k8s-master03 k8s-node01'
for NODE in $MasterNodes
do 
    echo scp on $NODE;   
    ssh $SUDO_USER@$NODE 'sudo mkdir -p /etc/containerd /etc/systemd/system/containerd.service.d'; 
    rsync -av --progress --rsync-path="sudo rsync" /etc/containerd/config.toml $SUDO_USER@$NODE:/etc/containerd/   
    rsync -av --progress --rsync-path="sudo rsync" /usr/local/sbin/runc $SUDO_USER@$NODE:/usr/local/sbin/
    rsync -av --progress --rsync-path="sudo rsync" /etc/systemd/system/containerd.service.d/* $SUDO_USER@$NODE:/etc/systemd/system/containerd.service.d/  
    rsync -av --progress --rsync-path="sudo rsync" cri-containerd-cni-${containerd_ver}-linux-amd64.tar.gz $SUDO_USER@$NODE:/home/$SUDO_USER/
    ssh $SUDO_USER@$NODE "sudo tar -xf cri-containerd-cni-${containerd_ver}-linux-amd64.tar.gz -C /"
done

# 所有节点启动服务
sudo systemctl daemon-reload
sudo systemctl enable --now containerd.service
sudo systemctl status containerd.service
```


### k8s master安装kubelet
```bash
### 2. kubelet 安装配置
# 在master01上操作
BOOTSTRAP_TOKEN=$(awk -F',' '{print $1}' token.csv)
# 设置集群参数, 此处lb haproxy也安装在master阶段,为了避免冲突, vip用的8443端口, 不是6443
kubectl config set-cluster kubernetes --certificate-authority=ca.pem \
    --embed-certs=true --server=https://$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}'):8443 \
    --kubeconfig=kubelet-bootstrap.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kubelet-bootstrap --token=${BOOTSTRAP_TOKEN} --kubeconfig=kubelet-bootstrap.kubeconfig
# 设置上下文参数,包含集群名称和访问集群的用户名字
kubectl config set-context default --cluster=kubernetes --user=kubelet-bootstrap --kubeconfig=kubelet-bootstrap.kubeconfig
# 使用默认上下文
kubectl config use-context default --kubeconfig=kubelet-bootstrap.kubeconfig
# 进行角色绑定
kubectl create clusterrolebinding cluster-system-anonymous --clusterrole=cluster-admin --user kubelet-bootstrap 
# kubectl delete clusterrolebinding cluster-system-anonymous
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper \
  --user kubelet-bootstrap \
  --kubeconfig=kubelet-bootstrap.kubeconfig
# 查看
kubectl describe clusterrolebinding cluster-system-anonymous
kubectl describe clusterrolebinding kubelet-bootstrap


# 创建kubelet服务管理文件, /etc/kubernetes/kubelet.kubeconfig 不用手工生成

sudo tee kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service
[Service]
workingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \
    --bootstrap-kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig \
    --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
    --config=/etc/kubernetes/kubelet.conf.json \
    --cert-dir=/etc/kubernetes/pki \
    --containerd=/run/containerd/containerd.sock \
    --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
    --node-labels=node.kubernetes.io/node='' \
    --root-dir=/etc/cni/net.d/ \
    --v=2 
    
Restart=on-failure
StartLimitInterval=0
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

# --rotate-certificates \
# --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.6 \


#### 拷贝到本级对应目录
sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes /var/lib/kubelet
sudo cp kubelet-bootstrap.kubeconfig /etc/kubernetes/
sudo cp kubelet.service /usr/lib/systemd/system/


####  同步到其他节点
MasterNodes='k8s-master02 k8s-master03 k8s-node01'
for NODE in $MasterNodes
do 
    echo scp on $NODE;   
    rsync -av --progress --rsync-path="sudo rsync" /usr/local/bin/kubelet $SUDO_USER@$NODE:/usr/local/bin/; 
    ssh $SUDO_USER@$NODE 'sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes /var/lib/kubelet /etc/systemd/system/containerd.service.d'; 
    rsync -av --progress --rsync-path="sudo rsync" kubelet-bootstrap.kubeconfig $SUDO_USER@$NODE:/etc/kubernetes/    
    rsync -av --progress --rsync-path="sudo rsync" kubelet.service $SUDO_USER@$NODE:/usr/lib/systemd/system/
done
```


所有节点配置和启动

```bash
####  所有节点
# kubelet配置文件
sudo tee /etc/kubernetes/kubelet.conf.json <<EOF
{
    "kind": "KubeletConfiguration",
    "apiVersion": "kubelet.config.k8s.io/v1beta1",
    "authentication": {
        "x509": {
            "clientCAFile": "/etc/kubernetes/pki/ca.pem"
        }
    },
    "webhook": {
        "enabled": true,
        "cacheTTL": "2m0s"
    },
    "anonymous": {
        "enabled": false
    },
    "authorization": {
        "mode": "Webhook",
        "webhook": {
            "cacheAuthorizedTTL": "5m0s",
            "cacheUnauthorizedTTL": "30s"
        }
    },
    "address": "$(grep "$(hostname)" /etc/hosts| grep -v ^127 | awk '{print $1}')",
    "port": 10250,
    "readOnlyPort": 10255,
    "cgroupDriver": "systemd",
    "hairpinMode": "promiscuous-bridge",
    "serializeImagePulls": false,
    "clusterDomain": "cluster.local",
    "clusterDNS": [
        "10.96.0.2"
    ]
}
EOF

# 启动服务
sudo systemctl daemon-reload
sudo systemctl unmask kubelet.service
sudo systemctl enable --now kubelet
sudo systemctl restart kubelet
sudo systemctl status kubelet

```


kubelet日志为解决

```bash
1.
Apr 18 16:23:25 k8s-master01 kubelet[36033]: I0418 16:23:25.077724   36033 manager.go:455] "Failed to read data from checkpoint" checkpoint="kubelet_internal_checkpoint" err="checkpoint is not found"

2.
Apr 18 16:23:26 k8s-master01 kubelet[36033]: I0418 16:23:26.116999   36033 provider.go:82] Docker config file not found: couldn't find valid .dockercfg after checking in [/etc/cni/net.d/   /]
```
## k8s网络相关部署
### k8s master安装kube-proxy
```bash
### 3. kube-proxy 安装配置
# 在master01上操作

# 设置集群参数, 此处lb haproxy也安装在master阶段,为了避免冲突, vip用的8443端口, 不是6443
kubectl config set-cluster kubernetes --certificate-authority=ca.pem \
    --embed-certs=true --server=https://$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}'):8443 \
    --kubeconfig=kube-proxy.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kube-proxy --client-certificate=kube-proxy.pem \
    --client-key=kube-proxy-key.pem --embed-certs=true --kubeconfig=kube-proxy.kubeconfig
# 设置上下文参数,包含集群名称和访问集群的用户名字
kubectl config set-context default --cluster=kubernetes --user=kubelet-proxy --kubeconfig=kube-proxy.kubeconfig
# 使用默认上下文
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

sudo tee kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target
[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \
  --config=/etc/kubernetes/kube-proxy.config.yaml \
  --v=2 
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF


#### 拷贝到本级对应目录
sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes /var/lib/kube-proxy
sudo cp kube-proxy.kubeconfig kube-proxy*.pem /etc/kubernetes/
sudo cp kube-proxy.service /usr/lib/systemd/system/

# 同步到其他节点
MasterNodes='k8s-master02 k8s-master03'
for NODE in $MasterNodes
do 
    echo scp on $NODE;   
    ssh $SUDO_USER@$NODE 'sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes /var/lib/kube-proxy'; 
    rsync -av --progress --rsync-path="sudo rsync" kube-proxy.kubeconfig kube-proxy*.pem $SUDO_USER@$NODE:/etc/kubernetes/    
    rsync -av --progress --rsync-path="sudo rsync" kube-proxy.service $SUDO_USER@$NODE:/usr/lib/systemd/system/
done

```


所有节点配置和启动服务

```bash
# 所有节点
# kubelet配置文件
sudo tee /etc/kubernetes/kube-proxy.config.yaml <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  burst: 200
  kubeconfig: "/etc/kubernetes/kube-proxy.kubeconfig"
  qps: 100
bindAddress: $(grep "$(hostname)" /etc/hosts| grep -v ^127 | awk '{print $1}')
healthzBindAddress: $(grep "$(hostname)" /etc/hosts| grep -v ^127 | awk '{print $1}'):10256
metricsBindAddress: $(grep "$(hostname)" /etc/hosts| grep -v ^127 | awk '{print $1}'):10249
enableProfiling: true
clusterCIDR: 10.244.0.0/16
mode: "ipvs"
portRange: ""
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now kube-proxy
sudo systemctl restart kube-proxy
sudo systemctl status kube-proxy
```




### k8s master部署calico网络
在受限网络中这么部署有问题，需要进一步测试

```bash

### 4. calico 网络
# wget -c https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml
# grep CALICO_IPV4POOL_CIDR -C2 calico.yaml

sudo sed -i 's/#   value: "192.168./  value: "10.244./' calico.yaml
sudo sed -i '/CALICO_IPV4POOL_CID/s/# //' calico.yaml
kubectl apply -f calico.yaml
# 验证
kubectl get pods -A
```
### k8s master部署CoreDNS
在受限网络中这么部署有问题，需要进一步测试

```bash
### 5. coredns
git clone https://github.com/coredns/deployment.git
cd deployment/kubernetes/
./deploy.sh -i 10.96.0.2 | kubectl apply -f -
cd -
```
## 测试
```bash
### 6. verify cluster
export KUBECONFIG=$HOME/.kube/config
kubectl cluster-info
kubectl get componentstatuses
# kubectl get cs
kubectl get all --all-namespaces
```
### 集群验证-部署nginx测试
### 部署Kuboard
