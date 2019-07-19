

print_usage()
{
    echo "      Usage:"
    echo "      $FILENAME --k8s-version v1.14.4 --windows-directory-name k --user azureuser --git-repository-name msazurestackworkloads"
    echo  ""
    echo "            -k, --k8s-version                         Kubernetes version to be used to builf binaries."
    echo "            -w, --windows-directory-name              Windows target directory name. "
    echo "            -u, --user                                User Name of the given vm."
    echo "            -g, --git-repository-name                 Repository Name from which binary will be build."
    echo "            -b, --build-revision-version              Windows binary revision version."
    exit 1
}
parse_commandline_arguments()
{

    while [[ "$#" -gt 0 ]]
    do
        case $1 in
            -k|--k8s-version)
                KUBERNETES_VERSION="$2"
            ;;
            -w|--windows-directory-name)
                WINDOWS_DIRECTORY_NAME="$2"
            ;;
            -u|--user)
                USER_NAME="$2"
            ;;
            -g|--git-repository-name)
                GIT_REPOSITORY="$2"
            ;;
            -b|--build-revision-version)
                BUILD_REVISION_VERSION="$2"
            ;;
            *)
                echo ""
                echo "Incorrect parameter $1"
                echo ""
                printUsage
            ;;
        esac
        
        if [ "$#" -ge 2 ]
        then
            shift 2
        else
            shift
        fi
    done
}

download_nssm() {
    local destinationDirectory=$1
    local nssmVersion=2.24
    local nssmUrl=https://nssm.cc/release/nssm-${nssmVersion}.zip
    echo "downloading nssm ..."
    curl ${nssmUrl} -o /tmp/nssm-${nssmVersion}.zip
    unzip -q -d /tmp /tmp/nssm-${nssmVersion}.zip
    cp /tmp/nssm-${nssmVersion}/win64/nssm.exe "${destinationDirectory}"
    chmod 775 "${destinationDirectory}"/nssm.exe
    rm -rf /tmp/nssm-${nssmVersion}*
}

download_wincni() {
    local destinationDirectory=$1
    local winSDNUrl=https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/
    local winCNI=cni/wincni.exe
    local hnsScript=hns.psm1
    mkdir -p "${destinationDirectory}"/cni/config
    curl -L ${winSDNUrl}${winCNI} -o "${destinationDirectory}"/${winCNI}
    curl -L ${winSDNUrl}${hnsScript} -o "${destinationDirectory}"/${hnsScript}
}

create_zip() {
    local destinationDirectory=$1
    local k8sVersion=$2
    local subVersion=$3
    local baseDirectoryName=$(basename "${destinationDirectory}")
    local zipName="$k8sVersion-v${subVersion}int.zip"
    cd "${destinationDirectory}"/..
    zip -r "${zipName}" $baseDirectoryName/*
    cd -
}

build_kubelet() {
    local destinationDirectory=$1
    local kubePath=$2
    echo "building kubelet.exe..."
    cd $kubePath
    ./build/run.sh make WHAT=cmd/kubelet KUBE_BUILD_PLATFORMS=windows/amd64
    cp "$kubePath"/_output/dockerized/bin/windows/amd64/kubelet.exe "${destinationDirectory}"
}

build_kubeproxy() {
    local destinationDirectory=$1
    local kubePath=$2
    echo "building kube-proxy.exe..."
    cd $kubePath
    ./build/run.sh make WHAT=cmd/kube-proxy KUBE_BUILD_PLATFORMS=windows/amd64
    cp "$kubePath"/_output/dockerized/bin/windows/amd64/kube-proxy.exe "${destinationDirectory}"
}

build_kubectl() {
    local destinationDirectory=$1
    local kubePath=$2
    echo "building kubectl.exe..."
    cd $kubePath
    ./build/run.sh make WHAT=cmd/kubectl KUBE_BUILD_PLATFORMS=windows/amd64
    cp "$kubePath"/_output/dockerized/bin/windows/amd64/kubectl.exe "${destinationDirectory}"
}

build_kube_binaries_for_upstream_e2e() {
    local destinationDirectory=$1
    local kubePath=$2
    cd $kubePath
    ./build/run.sh make WHAT=cmd/kubelet KUBE_BUILD_PLATFORMS=linux/amd64

    build_kubelet $destinationDirectory $kubePath
    build_kubeproxy $destinationDirectory $kubePath
    build_kubectl $destinationDirectory $kubePath
}

create_dist_dir() {
    local destinationDirectory=$1
    mkdir -p "${destinationDirectory}"
}

fetch_k8s() {
    local gitCodePath=$1
    local gitRepository=$2
    cd "$gitCodePath"
    git clone git@github.com:$gitRepository/kubernetes.git || true
}

create_version_branch() {
    local k8sCodePath=$1
    local tagName=$2
    cd $k8sCodePath
    git fetch -p
    git checkout -b win-"${tagName}" "tags/${tagName}" || true
}


parse_commandline_arguments $@


if [[ -z "$KUBERNETES_VERSION" ]] || \
[[ -z "$USER_NAME" ]]; then
    echo "One of the mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi

if [[ -z "$WINDOWS_DIRECTORY_NAME" ]]; then
    WINDOWS_DIRECTORY_NAME="k"
fi

if [[ -z "$GIT_REPOSITORY" ]]; then
    GIT_REPOSITORY="msazurestackworkloads"
fi

if [[ -z "$BUILD_REVISION_VERSION" ]]; then
    BUILD_REVISION_VERSION="1"
fi

HOME_DIRECTORY="/home/$USER_NAME"
GIT_CODE_PATH=$HOME_DIRECTORY/github.com
WINDOWS_DESTINATION_DIRECTORY=$GIT_CODE_PATH/$WINDOWS_DIRECTORY_NAME
KUBE_PATH=$GIT_CODE_PATH/kubernetes
GIT_REPOSITORY="msazurestackworkloads"

cd $HOME_DIRECTORY
sudo rm -r -f $WINDOWS_DESTINATION_DIRECTORY
sudo rm -r -f $KUBE_PATH

create_dist_dir $GIT_CODE_PATH
create_dist_dir $WINDOWS_DESTINATION_DIRECTORY

fetch_k8s $GIT_CODE_PATH $GIT_REPOSITORY
create_version_branch $KUBE_PATH $KUBERNETES_VERSION

build_kube_binaries_for_upstream_e2e $WINDOWS_DESTINATION_DIRECTORY $KUBE_PATH
download_nssm $WINDOWS_DESTINATION_DIRECTORY
download_wincni $WINDOWS_DESTINATION_DIRECTORY
create_zip $WINDOWS_DESTINATION_DIRECTORY $KUBERNETES_VERSION $BUILD_REVISION_VERSION
