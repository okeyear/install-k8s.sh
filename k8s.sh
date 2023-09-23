#!/bin/bash
export PATH=/snap/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:~/.local/bin:$PATH
export LANG=en_US.UTF8
# exit shell when error
# set -e
echo 'export PATH=/usr/local/bin:$PATH' | sudo tee /etc/profile.d/localbin.sh
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
    cat <<EOF
    Deploy local k8s cluster via kubeadm.

    Cluster Management Commands:
    apply         Run cloud images within a kubernetes cluster with Clusterfile
    cert          update Kubernetes API server's cert
    run           Run cloud native applications with ease, with or without a existing cluster
    reset         Reset all, everything in the cluster
    status        state of sealos

    Node Management Commands:
    add           Add nodes into cluster
    delete        Remove nodes from cluster

    Remote Operation Commands:
    exec          Execute shell command or script on specified nodes
    scp           Copy file to remote on specified nodes

    Experimental Commands:
    registry      registry related

    Container and Image Commands:
    download      Download kubefile and container images
    downloadcn    Download kubefile and container images on China
    build         Build an image using instructions in a Containerfile or Kubefile
    create        Create a cluster without running the CMD, for inspecting image
    diff          Inspect changes to the object's file systems
    inspect       Inspect the configuration of a container or image
    images        List images in local storage
    load          Load image(s) from archive file
    login         Login to a container registry
    logout        Logout of a container registry
    manifest      Manipulate manifest lists and image indexes
    merge         merge multiple images into one
    pull          Pull images from the specified location
    push          Push an image to a specified destination
    rmi           Remove one or more images from local storage
    save          Save image into archive file
    tag           Add an additional name to a local image

    Other Commands:
    completion    Generate the autocompletion script for the specified shell
    docs          generate API reference
    env           prints out all the environment information in use by sealos
    gen           generate a Clusterfile with all default settings
    version       Print version info

    Use "sealos <command> --help" for more information about a given command.
EOF

}

#####################
# download part
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
    # wget -c https://github.com/containerd/containerd/releases/download/$containerd_ver/containerd-${containerd_ver/v/}-linux-amd64.tar.gz
    # containerd service
    # wget -c https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    containerd_ver=${containerd_ver/v/}
    # cri-containerd-cni 包含containerd
    download_filename="cri-containerd-cni-${containerd_ver}-linux-amd64.tar.gz"
    [ ! -s "${download_filename}" ] && wget -c "https://github.com/containerd/containerd/releases/download/v${containerd_ver}/${download_filename}"
    # download runc
    runc_ver=$(get_github_latest_release opencontainers/runc)
    wget -c https://github.com/opencontainers/runc/releases/download/${runc_ver}/runc.amd64
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

#####################
# functions download part
#####################

# require containerd zstd
# temp folder
# trap 'rm -rf "$TMPFILE"' EXIT
# TMPFILE=$(mktemp -d) || exit 1
# cd $TMPFILE

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
    for i in $(./kubeadm config images list --config kubeadm.yml); do
        ctr -n k8s.io images export $(echo ${i/registry.k8s.io\//}.tar | sed 's@/@+@g') "${i}" --platform linux/amd64
    done
}

function download_calicoimages() {
    echo
    download_calico
    # calico images
    download_calico
    for i in $(grep 'image:' calico.yaml | awk '{print $2}'); do
        ctr -n k8s.io images pull $i
        ctr -n k8s.io images export $(echo ${i/docker.io\//}.tar | sed 's@/@+@g') "${i}" --platform linux/amd64
    done
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

function download_offline() {
    # yum install -y zstd
    pwd

    # containerd & runc
    download_containerd
    tar --zstd -cf containerd.tar.zst ./cri-containerd-cni-*-linux-amd64.tar.gz ./runc.amd64
    rm -rf cri-containerd-cni-*-linux-amd64.tar.gz runc.amd64

    download_calicoimages
    tar --zstd -cf calico.tar.zst ./calico*.tar ./calico.yaml
    rm -rf calico*.tar calico.yaml

    download_k8simages
    tar --zstd -cf kubenetes.tar.zst ./kube*.tar ./coredns*.tar ./etcd*.tar ./pause*.tar
    rm -rf ./kube*.tar ./coredns*.tar ./etcd*.tar ./pause*.tar

    download_k8srpms
    tar --zstd -cf kubernetes.repo.rpms.tar.zst ./kubernetes.repo.rpms
    rm -rf ./kubernetes.repo.rpms

    # clean
    # rm -f ./*.tar calico.yaml kubeadm kubeadm.yml
    # cd -

}

function download_offlinecn() {
    # download from aliyun China
    echo
}

function install_containerd() {
    echo
    sudo tar -xvf cri-containerd-cni-*-linux-amd64.tar.gz -C /
    sudo install -m 755 runc.amd64* /usr/local/sbin/runc
    sudo mkdir /etc/containerd
    sudo /usr/local/bin/containerd config default | sudo tee /etc/containerd/config.toml
    # config
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
}

function install_k8srpms() {
    echo
    sudo tar -I zstd -xvf kubernetes.repo.rpms.tar.zst
    sudo yum install -y ./kubernetes.repo.rpms/*.rpm
}

function install_controlplane() {
    echo
    sudo bash pre_install.sh
    install_containerd
    install_k8srpms
    sudo tar -I zstd -xvf kubenetes.tar.zst
    #
    kubeadm config print init-defaults --component-configs KubeletConfiguration | sudo tee /etc/kubernetes/kubeadm.yml
    sudo sed -i "/name:/s/node/$(hostname)/" /etc/kubernetes/kubeadm.yml

    # 修改apiserver-advertise-address为本机的地址
    defaultip=$(ip r get 1.1.1.1 | awk '/src/{print $7}')
    sudo sed -i "/advertiseAddress/s/:.*$/: $defaultip/" /etc/kubernetes/kubeadm.yml
    #
    k8s_ver=$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    k8s_ver=${k8s_ver/v/}
    sudo sed -i "/kubernetesVersion:/ckubernetesVersion: ${k8s_ver}" /etc/kubernetes/kubeadm.yml
    # import images
    for i in $(ls *:*.tar); do
        sudo /usr/local/bin/ctr -n k8s.io images import "${i}" --platform linux/amd64
    done
    # sudo /usr/local/bin/ctr -n k8s.io images ls
    # sudo nerdctl -n k8s.io images

    # 列出所需要的镜像列表
    kubeadm config images list --config /etc/kubernetes/kubeadm.yml | sed 's/^/ctr image pull /g'
    # 拉取镜像到本地
    # sudo kubeadm config images pull --v=5 --config /etc/kubernetes/kubeadm.yml
    sudo kubeadm init --v=9 --config /etc/kubernetes/kubeadm.yml --upload-certs --ignore-preflight-errors=ImagePull

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    # export KUBECONFIG=/etc/kubernetes/admin.conf
    export KUBECONFIG=$HOME/.kube/config
    kubectl create -f calico.yaml
    # worker node join command
    kubeadm token create --print-join-command
    # worker node join command: recreate
}

function get_kubeadm_join_cmd() {
    echo
    local join_token=$(kubeadm token generate)
    kubeadm token create "${join_token}" --print-join-command --ttl=240h0m0s # --ttl=0 # default 24h0m0s
    unset token
}

function install_workernode() {
    echo
    sudo bash pre_install.sh
    install_containerd
    install_k8srpms
    # exec get_kubeadm_join_cmd
}

#####################
# functions main part
#####################

download_offline
# rclone copy kubenetes.tar.zst webdav:Src/k8s/
# rclone copy kubernetes.repo.rpms.tar.zst webdav:Src/k8s/
