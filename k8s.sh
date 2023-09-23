#!/bin/bash
export PATH=/snap/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:~/.local/bin:$PATH
export LANG=en_US.UTF8
# exit shell when error
# set -e
echo 'export PATH=/usr/local/bin:$PATH' | sudo tee /etc/profile.d/localbin.sh &>/dev/null
# source /etc/profile.d/localbin.sh
###################

# If User is root or sudo install
# if [ $(id -u) -eq 0 ]; then
if [ "$EUID" -eq "0" ]; then
    SUDO='sh -c'
elif command -v sudo &>/dev/null; then
    SUDO='sudo -E sh -c'
elif command -v su &>/dev/null; then
    SUDO='su -c'
else
    cat >&2 <<-'EOF'
    echo Error: this installer needs the ability to run commands as root.
    echo We are unable to find either "sudo" or "su" available to make this happen.
EOF
    exit 1
fi

#####################
# functions part
#####################
function echo_color() {
    test $# -le 1 && echo -ne "Usage: echo_color [dark_]red|green|yellow|blue|cyan|white|none|black|magenta|purple|[light_]gray  somewords  -r  success|failure|passed|warning"
    while [ $# -gt 1 ]; do
        # local LOWERCASE=$(echo -n "$1" | tr '[A-Z]' '[a-z]')
        case "$1" in
        none) echo -ne "\e[m${2}\e[0m " ;;
        black) echo -ne "\e[0;30m${2}\e[0m " ;;
        red) echo -ne "\e[0;91m${2}\e[0m " ;;
        dark_red) echo -ne "\e[0;31m${2}\e[0m " ;;
        green) echo -ne "\e[0;92m${2}\e[0m " ;;
        dark_green) echo -ne "\e[0;32m${2}\e[0m " ;;
        yellow) echo -ne "\e[0;93m${2}\e[0m " ;;
        dark_yellow) echo -ne "\e[0;33m${2}\e[0m " ;;
        blue) echo -ne "\e[0;94m${2}\e[0m " ;;
        dark_blue) echo -ne "\e[0;34m${2}\e[0m " ;;
        cyan) echo -ne "\e[0;96m${2}\e[0m " ;;
        dark_cyan) echo -ne "\e[0;36m${2}\e[0m " ;;
        magenta) echo -ne "\e[0;95m${2}\e[0m " ;;
        purple) echo -ne "\e[0;35m${2}\e[0m " ;;
        white) echo -ne "\e[0;97m${2}\e[0m " ;;
        gray) echo -ne "\e[0;90m${2}\e[0m " ;;
        light_gray) echo -ne "\e[0;37m${2}\e[0m " ;;
        -r)
            RES_COL=90
            MOVE_TO_COL="echo -en \\033[${RES_COL}G"
            SETCOLOR_SUCCESS="echo -en \\033[1;32m"
            SETCOLOR_FAILURE="echo -en \\033[1;31m"
            SETCOLOR_WARNING="echo -en \\033[1;93m"
            SETCOLOR_PASSED="echo -en \\033[1;93m"
            SETCOLOR_NORMAL="echo -en \\033[0;39m"
            $MOVE_TO_COL
            echo -n "["
            case $2 in
            success | ok)
                $SETCOLOR_SUCCESS
                echo -n $" SUCCESS "
                ;;
            failure | fail | error | err)
                $SETCOLOR_FAILURE
                echo -n $" FAILED  "
                ;;
            passed | pass | skip)
                $SETCOLOR_PASSED
                echo -n $" PASSED  "
                ;;
            warning | warn)
                echo -n $" WARNING "
                $SETCOLOR_WARNING
                ;;
            *)
                echo -ne "\n"
                ;;
            esac
            $SETCOLOR_NORMAL
            echo -n "]"
            ;;
        *)
            echo -ne "Usage: echo_color [dark_]red|green|yellow|blue|cyan|white|none|black|magenta|purple|[light_]gray  somewords  -r  success|failure|passed|warning"
            shift 2
            ;;
        esac
        shift 2
    done

    echo -ne "\n"
    return 0
}

function echo_line() {
    printf "%-80s\n" "=" | sed 's/\s/=/g'
}

function install_soft() {
    if command -v dnf >/dev/null; then
        $SUDO dnf -q -y install "$1"
    elif command -v yum >/dev/null; then
        $SUDO yum -q -y install "$1"
    elif command -v apt >/dev/null; then
        $SUDO apt-get -qqy install "$1"
    elif command -v zypper >/dev/null; then
        $SUDO zypper -q -n install "$1"
    elif command -v apk >/dev/null; then
        $SUDO apk add -q "$1"
        command -v gettext >/dev/null || {
            $SUDO apk add -q gettext-dev python2
        }
    else
        echo -e "[\033[31m ERROR \033[0m] Please install it first (请先安装) $1 "
        exit 1
    fi
}

function prepare_install() {
    for i in curl wget tar; do
        command -v $i &>/dev/null || install_soft $i
    done
}

function get_github_latest_release() {
    curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' |                                          # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/'                                  # Pluck JSON value
}

# get OS release and version
# OS: release, ubuntu centos oracle rhel debian alpine,etc
# OSver: small version, 6.10, 7.9, 22.04, etc
# OSVer: big   version, 6 7 8 9 20 22, etc
function get_os() {
    # get OS major version, minor version, ID , relaserver
    # rpm -q --qf %{version} $(rpm -qf /etc/issue)
    # rpm -E %{rhel} # supported on rhel 6 , 7 , 8
    # python -c 'import yum, pprint; yb = yum.YumBase(); pprint.pprint(yb.conf.yumvar["releasever"])'
    if [ -r /etc/os-release ]; then
        OS=$(. /etc/os-release && echo "$ID")
        OSver=$(. /etc/os-release && echo "$VERSION_ID")
    elif test -x /usr/bin/lsb_release; then
        /usr/bin/lsb_release -i 2>/dev/null
        echo
    else
        OS=$(ls /etc/{*-release,issue} | xargs grep -Eoi 'Centos|Oracle|Debian|Ubuntu|Red\ hat' | awk -F":" 'gsub(/[[:blank:]]*/,"",$0){print $NF}' | sort -uf | tr '[:upper:]' '[:lower:]')
        OSver=$([ -f /etc/${OS}-release ] && \grep -oE "[0-9.]+" /etc/${OS}-release || \grep -oE "[0-9.]+" /etc/issue)
    fi
    OSVer=${OSver%%.*}
    OSmajor="${OSver%%.*}"
    OSminor="${OSver#$OSmajor.}"
    OSminor="${OSminor%%.*}"
    OSpatch="${OSver#$OSmajor.$OSminor.}"
    OSpatch="${OSpatch%%[-.]*}"
    # Package Manager:  yum / apt
    case $OS in
    centos | redhat | oracle | ol | rhel) PM='yum' ;;
    debian | ubuntu) PM='apt' ;;
    *) echo -e "\e[0;31mNot supported OS\e[0m, \e[0;32m${OS}\e[0m" ;;
    esac
    echo -e "\e[0;32mOS: $OS, OSver: $OSver, OSVer: $OSVer, OSmajor: $OSmajor\e[0m"
}

function help_message() {
    # todo
    cat <<EOF
    Deploy local k8s cluster via kubeadm.

    Deploy Commands:
    install         Deploy Control Plane on localhost
    controlplanes   Deploy Control Plane on following ipaddress, if the number of ip > 1 , need args vip
    vip             The VirtualServer IP for HA of Control Plane, Load Balancer IP
    workers         Deploy Worker Node on following ipaddress


    Cluster Management Commands:
    # reset         Reset all, everything in the cluster
    # status        state of sealos

    Node Management Commands:
    # add           Add nodes into cluster
    # delete        Remove nodes from cluster

    Container and Image Commands:
    download        Download kubefile and container images
    downloadcn      Download kubefile and container images on China
    # images        List images in local storage
    # load          Load image(s) from archive file
    # manifest      Manipulate manifest lists and image indexes

    Other Commands:
    # completion    Generate the autocompletion script for the specified shell
    version         Print version info

    Use "bash k8s.sh <command> --help" for more information about a given command.
EOF

}

#####################
# functions init (pre_install.sh)
#####################

function pre_install() {
    # packages
    for s in wget curl tar vim jq git lvm2 rsync zstd; do
        install_soft $s
    done
    #
    # 3. firewall
    # centos7 禁用NetworkManager, rhel8+不用禁用
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
    # TODO
    # Swap has been supported since v1.22. And since v1.28, Swap is supported for cgroup v2 only
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
    sudo yum install -y ipset ipvsadm sysstat conntrack libseccomp
    sudo mkdir -pv /etc/systemd/system/kubelet.service.d
    # kernel 4.19+中 nf_conntrack_ipv4 改为 nf_conntrack
    cat <<EOF | sudo tee /etc/modules-load.d/ipvs.conf
ip_vs
# ip_vs_lc
# ip_vs_wlc
ip_vs_rr
ip_vs_wrr
# ip_vs_lblc
# ip_vs_lblcr
# ip_vs_dh
ip_vs_sh
# ip_vs_fo
# ip_vs_nq
# ip_vs_sed
# ip_vs_ftp
# ip_vs_sh
nf_conntrack
# ip_tables
# ip_set
# xt_set
# ipt_set
# ipt_rpfilter
# ipt_REJECT
# ipip
EOF

}

#####################
# functions download part
#####################

function download_docker_image() {
    # todo
    install_soft jq
    install_soft wget
    install_soft curl
    folder=$1
    image=$2
    [ -s download-frozen-image-v2.sh ] || wget https://raw.githubusercontent.com/moby/moby/master/contrib/download-frozen-image-v2.sh
    bash download-frozen-image-v2.sh "$folder" "$image"
}

function download_containerd() {
    containerd_ver=$(get_github_latest_release "containerd/containerd")
    # containerd
    containerd_ver=${containerd_ver/v/}
    # cri-containerd-cni 包含containerd
    download_filename="cri-containerd-cni-${containerd_ver}-linux-amd64.tar.gz"
    [ ! -s "${download_filename}" ] && wget -c "https://github.com/containerd/containerd/releases/download/v${containerd_ver}/${download_filename}"

    # download runc
    runc_ver=$(get_github_latest_release opencontainers/runc)
    wget -c https://github.com/opencontainers/runc/releases/download/${runc_ver}/runc.amd64

    # download nerdctl
    nerdctl_ver=$(get_github_latest_release "containerd/nerdctl")
    wget -c "https://github.com/containerd/nerdctl/releases/download/${nerdctl_ver}/nerdctl-${nerdctl_ver/v/}-linux-amd64.tar.gz"
}

function download_calico() {
    calico_ver=$(get_github_latest_release "projectcalico/calico")
    wget -c "https://raw.githubusercontent.com/projectcalico/calico/${calico_ver}/manifests/calico.yaml"
    # wget -O calicoctl-linux-amd64.${calico_ver} https://github.com/projectcalico/calico/releases/download/${calico_ver}/calicoctl-linux-amd64
}

# function download_cni() {
#     # cni
#     CNI_VER=$(get_github_latest_release "containernetworking/plugins")
#     [ ! -s "cni-plugins-linux-amd64-${CNI_VER}.tgz" ] && wget -c "https://github.com/containernetworking/plugins/releases/download/${CNI_VER}/cni-plugins-linux-amd64-${CNI_VER}.tgz"
# }

function download_helm() {
    # helm
    helm_ver=$(get_github_latest_release helm/helm)
    wget -c https://get.helm.sh/helm-${helm_ver}-linux-amd64.tar.gz
}

function download_kubeadm() {
    # k8s
    k8s_ver=$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    wget -c "https://dl.k8s.io/${k8s_ver}/bin/linux/amd64/kubeadm"
}

# function download_k8s() {
#     # k8s
#     k8s_ver=$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)
#     wget -c https://dl.k8s.io/${k8s_ver}/kubernetes-server-linux-amd64.tar.gz
#     # download from # https://www.downloadkubernetes.com/
#     # for pkg in {apiextensions-apiserver,kube-{aggregator,apiserver,controller-manager,log-runner,proxy,scheduler},kubeadm,kubectl,kubectl-convert,kubelet,mounter}
#     for pkg in {kubeadm,kubectl,kubelet}; do
#         wget -c "https://dl.k8s.io/${k8s_ver}/bin/linux/amd64/${pkg}"
#         # wget -c "https://dl.k8s.io/${k8s_ver}/bin/linux/amd64/${pkg}.sha256"
#     done
# }

# require containerd zstd
# temp folder
# trap 'rm -rf "$TMPFILE"' EXIT
# TMPFILE=$(mktemp -d) || exit 1
# cd $TMPFILE

function export_images() {
    # export
    keyword=$1
    # for i in $(./kubeadm config images list -config kubeadm.yml); do
    for i in $(ctr -n k8s.io images ls | grep $keyword | awk '{print $1}' | sed 's|@sha256.*||g' | grep ':'); do
        ctr -n k8s.io images export $(echo ${i}.tar | sed 's@/@+@g') "${i}" --platform linux/amd64
    done
}

function download_k8simages() {
    echo
    # download from registry.k8s.io
    download_kubeadm
    chmod a+x kubeadm
    k8s_ver=$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    k8s_ver=${k8s_ver/v/}
    ./kubeadm config print init-defaults --component-configs KubeletConfiguration | sudo tee kubeadm.yml
    # kubernetesVersion: 1.28.0
    sudo sed -i "/kubernetesVersion:/ckubernetesVersion: ${k8s_ver}" kubeadm.yml
    # ./kubeadm config images list --config kubeadm.yml | sed 's/^/ctr image pull /g'
    ./kubeadm config images pull --v=5 --config kubeadm.yml
    # curl -Ls "https://sbom.k8s.io/$(curl -Ls https://dl.k8s.io/release/stable.txt)/release" | grep "SPDXID: SPDXRef-Package-registry.k8s.io" |  grep -v sha256 | cut -d- -f3- | sed 's/-/\//' | sed 's/-v1/:v1/' | grep amd64
    export_images "registry.k8s.io"
}

function download_k8simagescn() {
    echo
    # download from registry.k8s.io
    download_kubeadm
    chmod a+x kubeadm
    k8s_ver=$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    k8s_ver=${k8s_ver/v/}
    ./kubeadm config print init-defaults --component-configs KubeletConfiguration | sudo tee kubeadm.yml
    # kubernetesVersion: 1.28.0
    sudo sed -i "/kubernetesVersion:/ckubernetesVersion: ${k8s_ver}" kubeadm.yml
    # Aliyun China mirrors
    sudo sed -i 's@registry.k8s.io@registry.cn-hangzhou.aliyuncs.com/google_containers@' kubeadm.yml
    # ./kubeadm config images list --config kubeadm.yml | sed 's/^/ctr image pull /g'
    ./kubeadm config images pull --v=5 --config kubeadm.yml

    # tag registry.cn-hangzhou.aliyuncs.com/google_containers --> registry.k8s.io
    for i in $(ctr -n k8s.io images ls | awk '/aliyun/{print $1}' | sed 's|@sha256.*||g' | grep ':'); do
        ctr -n k8s.io image tag "$i" "$(echo $i | sed 's|registry.cn-hangzhou.aliyuncs.com/google_containers|registry.k8s.io|')"
    done

    # export
    export_images "registry.k8s.io"
}

function download_calicoimages() {
    echo
    download_calico
    # calico images
    download_calico
    for i in $(grep 'image:' calico.yaml | awk '{print $2}'); do
        ctr -n k8s.io images pull $i
    done
    # export
    export_images "calico"
}

function download_k8srpms() {
    echo
    # set k8s repo
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${k8s_ver%.*}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${k8s_ver%.*}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
    # download k8s repo rpms
    sudo yum install -y yum-download yum-plugin-downloadonly createrepo
    sudo yum install -y --downloadonly --disableexcludes=kubernetes --downloaddir=./kubernetes.repo.rpms kubelet kubeadm kubectl
    # createrepo ./kubernetes.repo.rpms
}

function download_k8srpmscn() {
    echo
    # set k8s repo
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
    # download k8s repo rpms
    sudo yum install -y yum-download yum-plugin-downloadonly createrepo
    # a. 如果下载的包包含了任何没有满足的依赖关系，yum将会把所有的依赖关系包下载，但是都不会被安装。
    # sudo yum install -y --downloadonly --disableexcludes=kubernetes --downloaddir=./kubernetes.repo.rpms kubelet kubeadm kubectl
    # b. yumdownloader会在下载过程中更新包索引文件。与yum命令不同的是，任何依赖包不会被下载。
    sudo yum -y install yum-utils
    yumdownloader --disableexcludes=kubernetes --downloaddir=./kubernetes.repo.rpms kubelet kubeadm kubectl kubernetes-cni cri-tools
    # createrepo ./kubernetes.repo.rpms
}

function download_offline() {

    # containerd & runc
    download_containerd
    tar --remove-files --zstd -cf containerd.tar.zst ./cri-containerd-cni-*-linux-amd64.tar.gz ./runc.amd64 ./nerdctl-*-linux-amd64.tar.gz

    download_calicoimages
    tar --remove-files --zstd -cf calico.tar.zst ./docker.io+calico*.tar ./calico.yaml

    download_k8simages
    tar --remove-files --zstd -cf k8simages.tar.zst ./registry.k8s.io*.tar

    download_k8srpms
    tar --remove-files --zstd -cf k8srpms.tar.zst ./kubernetes.repo.rpms

    # clean
    rm -f ./kubeadm ./kubeadm.yml
    # cd -

}

function download_offlinecn() {
    # download from aliyun China

    # containerd & runc
    download_containerd
    # todo: download image from China mirrors
    tar --remove-files --zstd -cf containerd.tar.zst ./cri-containerd-cni-*-linux-amd64.tar.gz ./runc.amd64 ./nerdctl-*-linux-amd64.tar.gz

    download_calicoimages
    # todo: download image from China mirrors
    tar --remove-files --zstd -cf calico.tar.zst ./docker.io+calico*.tar ./calico.yaml

    download_k8simagescn
    tar --remove-files --zstd -cf k8simages.tar.zst ./registry.k8s.io*.tar

    download_k8srpmscn
    tar --remove-files --zstd -cf k8srpms.tar.zst ./kubernetes.repo.rpms

    # clean
    rm -f ./kubeadm ./kubeadm.yml
    # cd -
}

function install_containerd() {
    # Install containerd and runc
    # unzip
    sudo tar -I zstd -xvf containerd.tar.zst
    # install containerd
    sudo tar -xvf cri-containerd-cni-*-linux-amd64.tar.gz -C /
    # install runc
    sudo install -m 755 runc.amd64* /usr/local/sbin/runc
    sudo mkdir /etc/containerd
    sudo /usr/local/bin/containerd config default | sudo tee /etc/containerd/config.toml
    # config containerd
    grep pause /etc/containerd/config.toml
    # systemd cgroup driver
    sudo sed -i.bak '/SystemdCgroup/s/false/true/' /etc/containerd/config.toml
    sudo grep containerd.runtimes.runc.options /etc/containerd/config.toml -A 20
    # cni
    sudo sed -i '/conf_template/s/=.*/= "\/etc\/cni\/net.d\/10-containerd-net.conflist"/' /etc/containerd/config.toml
    grep conf_template /etc/containerd/config.toml
    # service
    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd.service
    # install nerdctl
    sudo tar -xvf ./nerdctl-*-linux-amd64.tar.gz nerdctl
    sudo install nerdctl /usr/bin/nerdctl
    # alias docker
    # echo "alias docker='nerdctl'" | sudo tee -a /etc/profile.d/alias.sh
}

function install_k8srpms() {
    sudo tar -I zstd -xvf k8srpms.tar.zst
    sudo yum install -y ./kubernetes.repo.rpms/*.rpm
}

function install_base() {
    # kernel args
    pre_install
    # sudo bash pre_install.sh
    # runtime containerd
    install_containerd
    # rpm package: kubeadm kubectl kubelet
    install_k8srpms
}

function scp_files() {
    # scp or rsync
    local des=$1
    ssh "$des" "mkdir /tmp/k8s"
    scp containerd.tar.zst "$des:/tmp/k8s/"
    scp calico.tar.zst "$des:/tmp/k8s/"
    scp k8simages.tar.zst "$des:/tmp/k8s/"
    scp k8srpms.tar.zst "$des:/tmp/k8s/"
    scp k8s.sh "$des:/tmp/k8s/"
}

function install_controlplane() {
    # TODO: kube-vip multi master node
    if [ "${1}x" = "localhostx" ]; then
        install_base
        # k8s images from registry.k8s.io
        sudo tar -I zstd -xvf k8simages.tar.zst
        # kubeadm init config file
        kubeadm config print init-defaults --component-configs KubeletConfiguration | sudo tee /etc/kubernetes/kubeadm.yml
        sudo sed -i "/name:/s/node/$(hostname)/" /etc/kubernetes/kubeadm.yml
        # TODO: kube-vip
        # 修改apiserver-advertise-address为本机的地址
        defaultip=$(ip r get 1.1.1.1 | awk '/src/{print $7}')
        sudo sed -i "/advertiseAddress/s/:.*$/: $defaultip/" /etc/kubernetes/kubeadm.yml
        # get latest version
        k8s_ver=$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)
        k8s_ver=${k8s_ver/v/}
        sudo sed -i "/kubernetesVersion:/ckubernetesVersion: ${k8s_ver}" /etc/kubernetes/kubeadm.yml
        # import downloaded images
        for i in $(ls ./*:*.tar); do
            sudo /usr/local/bin/ctr -n k8s.io images import "${i}" --platform linux/amd64
        done
        # sudo /usr/local/bin/ctr -n k8s.io images ls
        # sudo nerdctl -n k8s.io images

        # 列出所需要的镜像列表
        kubeadm config images list --config /etc/kubernetes/kubeadm.yml | sed 's/^/ctr image pull /g'
        # 拉取镜像到本地
        # sudo kubeadm config images pull --v=5 --config /etc/kubernetes/kubeadm.yml
        # cluster init
        # skip image verify (it need access internet to registry.k8s.io): --ignore-preflight-errors=* or ImagePull
        sudo kubeadm init --v=9 --config /etc/kubernetes/kubeadm.yml --upload-certs --ignore-preflight-errors=ImagePull
        # after successful init
        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        # export KUBECONFIG=/etc/kubernetes/admin.conf
        export KUBECONFIG=$HOME/.kube/config
        kubectl create -f calico.yaml
        # worker node join command
        # kubeadm token create --print-join-command
        # worker node join command: recreate
    else
        IFS=','                   # space is set as delimiter
        read -ra ADDR <<<"$1"     # str is read into an array as tokens separated by IFS
        for i in "${ADDR[@]}"; do # access each element of array
            echo "Working on controlplane $i:"
            scp_files "$i"
            # install runtime & kubelet kubeadm kebectl
            ssh $i "sudo bash /tmp/k8s/k8s.sh install_base"
            # todo
        done
    fi
}

function get_kubeadm_join_cmd() {
    echo
    local join_token=$(kubeadm token generate)
    kubeadm token create "${join_token}" --print-join-command --ttl=240h0m0s # --ttl=0 # default 24h0m0s
    unset token
}

function install_workernode() {
    IFS=','                   # space is set as delimiter
    read -ra ADDR <<<"$1"     # str is read into an array as tokens separated by IFS
    for i in "${ADDR[@]}"; do # access each element of array
        echo "Working on worker $i:"
        scp_files "$i"
        # install runtime & kubelet kubeadm kebectl
        ssh $i "sudo bash /tmp/k8s/k8s.sh install_base"
        # join to k8s cluster
        joincmd=$(get_kubeadm_join_cmd)
        ssh $i "sudo ${joincmd}"
    done
    # exec get_kubeadm_join_cmd
}

# function read_ip() {
#     IFS=','                   # space is set as delimiter
#     read -ra ADDR <<<"$1"     # str is read into an array as tokens separated by IFS
#     for i in "${ADDR[@]}"; do # access each element of array
#         echo "$i"
#     done
# }

#####################
# functions main part
#####################

case $1 in
--download | download)
    download_offline
    shift
    ;;
--downloadcn | --cn | downloadcn)
    download_offlinecn
    shift
    ;;
--controlplanes | controlplanes | --masters | masters)
    ipaddrs=$2
    install_controlplane "$ipaddrs"
    shift 2
    ;;
--install | install)
    install_controlplane "localhost"
    shift
    ;;
--install_base | install_base)
    install_base
    shift
    ;;
--workers | workers)
    ipaddrs=$2
    install_workernode "$ipaddrs"
    shift 2
    ;;
-v | --version | version)
    tmp_version='0.0.1'
    echo "${tmp_version}"
    shift
    ;;
-h | --help | *)
    echo_color green "$(echo_line)"
    help_message
    echo_color green "$(echo_line)"
    ;;
esac

# download_offline
# rclone copy calico.tar.zst webdav:Src/k8s/offline
# rclone copy containerd.tar.zst webdav:Src/k8s/offline
# rclone copy k8simages.tar.zst webdav:Src/k8s/offline
# rclone copy k8srpms.tar.zst webdav:Src/k8s/offline
