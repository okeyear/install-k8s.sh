#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en

### 1. install cfssl
# cfssl required, https://github.com/cloudflare/cfssl/releases
: <<EOF
cfssl_ver='1.6.4'
sudo install -m 755 "cfssl_${cfssl_ver/v/}_linux_amd64" /bin/cfssl
sudo install -m 755 "cfssljson_${cfssl_ver/v/}_linux_amd64" /bin/cfssljson
sudo install -m 755 "cfssl-certinfo_${cfssl_ver/v/}_linux_amd64" /bin/cfssl-certinfo
cfssl version
EOF


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
    "10.10.10.101",
    "10.10.10.102",
    "10.10.10.103",
    "10.10.10.111",
    "10.10.10.112",
    "10.10.10.113",
    "10.10.10.114",
    "10.10.10.115",
    "10.10.10.200",
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
    "10.10.10.101",
    "10.10.10.102",
    "10.10.10.103",
    "10.10.10.105",
    "10.10.10.106",
    "10.10.10.200"
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
