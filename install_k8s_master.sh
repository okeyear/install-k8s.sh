#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export LANG=en


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
    --enable-swagger-ui=true \
    --apiserver-count=3 \
    --audit-log-maxage=30 \
    --audit-log-maxbackup=3 \
    --audit-log-maxsize=100 \
    --audit-log-path=/var/log/kubernetes/kube-apiserver-audit.log \
    --event-ttl=1h \
    --alsologtostderr=true \
    --logtostderr=false \
    --log-dir=/var/log/kubernetes \
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
KUBE_CONTROLLER_MANAGER_OPTS="      --port=10252 \
    --secure-port=10257 \
    --v=2 \
    --alsologtostderr=true \
    --logtostderr=false \
    --log-dir=/var/log/kubernetes \
    --address=127.0.0.1 \
    --tls-cert-file=/etc/kubernetes/pki/kube-controller-manager.pem \
    --tls-private-key-file=/etc/kubernetes/pki/kube-controller-manager-key.pem \
    --root-ca-file=/etc/kubernetes/pki/ca.pem \
    --cluster-name=kubernetes \
    --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \
    --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
    --service-account-private-key-file=/etc/kubernetes/pki/ca-key.pem \
    --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
    --experimental-cluster-signing-duration=87600h \
    --feature-gates=RotateKubeletServerCertificate=true \
    --leader-elect=true \
    --use-service-account-credentials=true \
    --node-monitor-grace-period=40s \
    --node-monitor-period=5s \
    --pod-eviction-timeout=2m0s \
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

# 同步到其他节点
MasterNodes='k8s-master02 k8s-master03'
for NODE in $MasterNodes
do 
    echo scp on $NODE;   
    rsync -av --progress --rsync-path="sudo rsync" kube-controller-manager.conf kube-controller-manager.kubeconfig $SUDO_USER@$NODE:/etc/kubernetes/    
    rsync -av --progress --rsync-path="sudo rsync" kube-controller-manager.service $SUDO_USER@$NODE:/usr/lib/systemd/system/
    rsync -av --progress --rsync-path="sudo rsync" kube-controller-manager*.pem  $SUDO_USER@$NODE:/etc/kubernetes/pki/
done

# 所有节点
sudo systemctl daemon-reload
sudo systemctl enable --now kube-controller-manager



### 4. kube-scheduler 服务和配置

# master01节点

kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true \
    --server=https://$(grep "lb-vip" /etc/hosts | grep -v ^127 | awk '{print $1}'):8443 --kubeconfig=kube-scheduler.kubeconfig
    
kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem --client-key=kube-scheduler-key.pem --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig
    
kubectl config set-context system:kube-scheduler --cluster=kubernetes \
    --user=system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig
    
kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

sudo tee kube-scheduler.conf <<EOF
KUBE_SCHEDULER_OPTS="  --logtostderr=true \
    --v=2 \
    --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
    --log-dir=/var/log/kubernetes \
    --address=127.0.0.1 \
    --leader-elect=true  \
    --alsologtostderr=true \
    --logtostderr=false "
EOF

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
sudo cp kube-scheduler.service /usr/lib/systemd/system/

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
# sudo systemctl status kube-scheduler


