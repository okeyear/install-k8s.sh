#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en

### 1. containerd
# download containerd & runc
containerd_ver='1.6.8'
sudo tar -xf cri-containerd-cni-${containerd_ver}-linux-amd64.tar.gz -C /
sudo install -m 755 runc.amd64 /usr/local/sbin/runc

# create default config
sudo mkdir /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# 主要改三个地方及镜像加速
# root = "/var/lib/containerd"
#     sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6"
#       bin_dir = "/opt/cni/bin"

# 配置containerd sandbox_image 
# 问题, Error getting node" err="node not found" 
# 解决办法, containerd配置中, 修改sandbox_image = "k8s.gcr.io/pause:3.6" 为可以拉取到的地址
grep k8s.gcr.io /etc/containerd/config.toml
sudo sed -i 's@k8s.gcr.io@registry.cn-hangzhou.aliyuncs.com/google_containers@' /etc/containerd/config.toml

# above Step 4: systemd cgroup driver
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
sed -i '/conf_template/s/=.*/= "\/etc\/cni\/net.d\/10-containerd-net.conflist"/' /etc/containerd/config.toml
grep conf_template /etc/containerd/config.toml

# 设置containerd的镜像加速 # imageRepository 
grep 'registry.mirrors' -C 5 /etc/containerd/config.toml
# 待更新: python toml模块安装之后的命令行去修改这些值, 比sed更好一点
sed -i.bak '/plugins."io.containerd.grpc.v1.cri".registry.mirrors/a    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]\n        endpoint = ["https://registry.docker-cn.com", "http://hub-mirror.c.163.com", "https://xc8hlpxv.mirror.aliyuncs.com", "https://docker.mirrors.ustc.edu.cn" ]\n        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."gcr.io"]\n          endpoint = ["https://gcr.mirrors.ustc.edu.cn"]\n        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."k8s.gcr.io"]\n          endpoint = ["https://gcr.mirrors.ustc.edu.cn/google-containers/"]\n        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]\n          endpoint = ["https://quay.mirrors.ustc.edu.cn"]' /etc/containerd/config.toml

sudo systemctl daemon-reload
sudo systemctl enable --now containerd.service

# 如果在内网,不能直接联网,需要设置下proxy
# /etc/systemd/system/containerd.service.d/http_proxy.conf 



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
    --network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin \
    --cert-dir=/etc/kubernetes/pki \
    --container-runtime=remote \
    --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
    --rotate-certificates \
    --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.6 \
    --node-labels=node.kubernetes.io/node='' \
    --root-dir=/etc/cni/net.d \
    --alsologtostderr=true \
    --logtostderr=false \
    --log-dir=/var/log/kubernetes \
    --v=2 
    
Restart=on-failure
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

#### 拷贝到本级对应目录
sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes /var/lib/kubelet
sudo cp kubelet-bootstrap.kubeconfig /etc/kubernetes/
sudo cp kubelet.service /usr/lib/systemd/system/

# 同步到其他节点
MasterNodes='k8s-master02 k8s-master03 k8s-node01'
for NODE in $MasterNodes
do 
    echo scp on $NODE;   
    ssh $SUDO_USER@$NODE 'sudo mkdir -p /etc/kubernetes/pki /var/log/kubernetes /var/lib/kubelet'; 
    rsync -av --progress --rsync-path="sudo rsync" kubelet-bootstrap.kubeconfig $SUDO_USER@$NODE:/etc/kubernetes/    
    rsync -av --progress --rsync-path="sudo rsync" kubelet.service $SUDO_USER@$NODE:/usr/lib/systemd/system/
done

# 所有节点
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

sudo systemctl daemon-reload
sudo systemctl enable --now kubelet



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
    --alsologtostderr=true \
    --logtostderr=false \
    --log-dir=/var/log/kubernetes \
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
kubeProxyIPTablesConfiguration:
  masqueradeAll: false
kubeProxyIPVSConfiguration:
  scheduler: rr
  excludeCIDRs: []
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now kube-proxy


### 4. calico 网络
# wget -c https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml
# grep CALICO_IPV4POOL_CIDR -C2 calico.yaml

sudo sed -i 's/#   value: "192.168./  value: "10.244./' calico.yaml
sudo sed -i '/CALICO_IPV4POOL_CID/s/# //' calico.yaml
kubectl apply -f calico.yaml
# 验证
kubectl get pods -A

### 5. coredns
git clone https://github.com/coredns/deployment.git
cd deployment/kubernetes/
./deploy.sh -i 10.96.0.2 | kubectl apply -f -

### 6. verify cluster



