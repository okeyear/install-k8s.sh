# install-k8s.sh
Install k8s offline via kubeadm

## Roadmap

[ x ] Only support: CentOS 7, Alma/Rocky Linux 8/9

[  ]  Not ready yet.

## Requirement
Requirement: ssh no need password to master/worker node

Requirement: ssh no need password to master/worker node

Requirement: ssh no need password to master/worker node

yum/apt repo: to install packages wget curl vim jq etc

## Offline Install

### Step 1. On the server (Access Internet direct/proxy)
```shell
# dowload k8s.sh, git clone or curl raw, only need single file k8s.sh
bash k8s.sh download
# in China, instead of "downloadcn"
```
### Step 2. Copy Files
Copy these files:
- containerd.tar.zst
- calico.tar.zst
- k8simages.tar.zst
- k8srpms.tar.zst
- k8s.sh

To your destination server (or jumpserver/client/ansible)

### Step 3. On Destination server (Can Not Access Internet)
#### Step 3.1 Install on Single Server

`Master Node(Your are here)`

```shell
# install controlplane on localhost
bash k8s.sh install
```
#### Step 3.2 Install on Destination Server

`Client(Your are here) --> Master Node --> Worker Node`


```shell
# install control plane
bash k8s.sh controlplane ip1
bash k8s.sh controlplane ip1,ip2,ip3

# install worker node
bash k8s.sh worker ip2,ip3
bash k8s.sh worker ip4,ip5,ip6

# install master & worker
bash k8s.sh controlplane ip1,ip2,ip3 worker ip4,ip5,ip6
```