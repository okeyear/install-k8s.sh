# install-k8s.sh
Install k8s online offline via kubeadm

## Roadmap
[ x ] Only support: CentOS 7, Alma/Rocky Linux 8/9
[  ]  Not ready yet.

## Offline Install

```shell
bash k8s.sh download
# in China, instead of "downloadcn"
```

Copy these files:
- containerd.tar.zst
- calico.tar.zst
- k8simages.tar.zst
- k8srpms.tar.zst

To your destination server (or jumpserver/client/ansible server)


On destination server
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