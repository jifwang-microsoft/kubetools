#!/bin/bash -e

ERR_METADATA_ENDPOINT=30 # Failure calling the metadata endpoint
ERR_KUBETEST_FAILED=31 # Failure calling the metadata endpoint



# Avoid apt failures by first checking if the lock files are around
# Function taken from the AKSe's code based
wait_for_apt_locks()
{
    while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo 'Waiting for release of apt locks'
        sleep 3
    done
}

# Avoid transcient apt-update failures
# Function taken from gallery code based
apt_get_update()
{
    echo "Updating apt cache."
    
    retries=10
    apt_update_output=/tmp/apt-get-update.out
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        sudo dpkg --configure -a
        sudo apt-get -f -y install
        sudo apt-get update 2>&1 | tee $apt_update_output | grep -E "^([WE]:.*)|([eE]rr.*)$"
        [ $? -ne 0  ] && cat $apt_update_output && break || \
        cat $apt_update_output
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep 30
        fi
    done
    
    echo "Executed apt-get update $i time/s"
    wait_for_apt_locks
}

# Avoid transcient apt-install failures
# Function taken from gallery code based
apt_get_install()
{
    retries=$1; wait_sleep=$2; timeout=$3;
    shift && shift && shift
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        sudo dpkg --configure -a
        sudo apt-get install --no-install-recommends -y ${@}
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep $wait_sleep
            apt_get_update
        fi
    done
    
    echo "Executed apt-get install --no-install-recommends -y \"$@\" $i times";
    wait_for_apt_locks
}

log_level()
{
    case "$1" in
        -e) echo "$(date) [Err]  " ${@:2}
        ;;
        -w) echo "$(date) [Warn] " ${@:2}
        ;;
        -i) echo "$(date) [Info] " ${@:2}
        ;;
        *)  echo "$(date) [Debug] " ${@:2}
        ;;
    esac
}

ensure_certificates()
{
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH="/var/lib/waagent/Certificates.pem"
    AZURESTACK_ROOT_CERTIFICATE_DEST_PATH="/usr/local/share/ca-certificates/azsCertificate.crt"

    log_level -i "Copy ca-cert from '$AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH' to '$AZURESTACK_ROOT_CERTIFICATE_DEST_PATH' "
    cp $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH

    AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH -noout -fingerprint`
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT"

    AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH -noout -fingerprint`
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT"

    update-ca-certificates
}

install_bazel()
{
    local bazelVersion=$1

    if [ -z "$bazelVersion" ]; then
        bazelVersion=0.23.2
    fi

    local installer="bazel-${bazelVersion}-installer-linux-x86_64.sh"
    local downloadURL="https://github.com/bazelbuild/bazel/releases/download/${bazelVersion}/${installer}"
    #Install prerequisites    
    apt_get_install 30 1 600  \
    pkg-config \
    zip \
    g++ \
    zlib1g-dev \
    unzip \
    python3 \
    || exit 0
    log_level -i "Installing bazel from : $downloadURL"
    wget -q "${downloadURL}" && chmod +x "${installer}"
    "./${installer}"
    rm "${installer}"
    bazel version
}

install_docker()
{
    apt_get_install 30 1 600  \
    docker.io \
    || exit 0
    systemctl start docker
    systemctl enable docker
}

install_go()
{
    local goVersion=$1
    if [ -z "$goVersion" ]; then
        goVersion=1.12.6
    fi

    apt_get_update || exit 0
    wget https://dl.google.com/go/go${goVersion}.linux-amd64.tar.gz
    tar -xvf go${goVersion}.linux-amd64.tar.gz
    rm go${goVersion}.linux-amd64.tar.gz
    mv -f go /usr/local
    export GOROOT=/usr/local/go
    export GOPATH=$HOME/go
    export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
    go env
}

create_secretfile()
{
    echo "Creds.ClientID = \"$SPN_CLIENT_ID\"" >> $AZURE_CREDS_PATH
    echo "Creds.ClientSecret = \"$SPN_CLIENT_SECRET\"" >> $AZURE_CREDS_PATH
    echo "Creds.TenantID = \"$TENANT_ID\"" >> $AZURE_CREDS_PATH
    echo "Creds.SubscriptionID = \"$TENANT_SUBSCRIPTION_ID\"" >> $AZURE_CREDS_PATH
    echo "Creds.StorageAccountName = \"none\"" >> $AZURE_CREDS_PATH
    echo "Creds.StorageAccountKey = \"none\"" >> $AZURE_CREDS_PATH
}



#####################################################################################
# start

log_level -i "Starting Kubernetes cluster deployment: v0.5.1"
log_level -i "Running script as:  $(whoami)"
log_level -i "System information: $(uname -a)"

log_level -i "------------------------------------------------------------------------"
log_level -i "ARM parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "ADMIN_USERNAME:                           $ADMIN_USERNAME"
log_level -i "AGENT_COUNT:                              $AGENT_COUNT"
log_level -i "AGENT_SIZE:                               $AGENT_SIZE"
log_level -i "AKSE_BASE_URL:                            $AKSE_BASE_URL"
log_level -i "AKSE_RELEASE_VERSION:                     $AKSE_RELEASE_VERSION"
log_level -i "BAZEL_BUILD_VERSION:                      $BAZEL_BUILD_VERSION"
log_level -i "BAZEL_TEST_VERSION:                       $BAZEL_TEST_VERSION"
log_level -i "BUILD_HYPERKUBE:                          $BUILD_HYPERKUBE"
log_level -i "CLUSTER_DEFINITION_BASE_URL:              $CLUSTER_DEFINITION_BASE_URL"
log_level -i "DEFINITION_TEMPLATE_NAME:                 $DEFINITION_TEMPLATE_NAME"
log_level -i "GO_VERSION:                               $GO_VERSION"
log_level -i "IDENTITY_SYSTEM:                          $IDENTITY_SYSTEM"
log_level -i "KUBERNETES_GIT_BRANCH:                    $KUBERNETES_GIT_BRANCH"
log_level -i "KUBERNETES_GIT_REPOSITORY:                $KUBERNETES_GIT_REPOSITORY"
log_level -i "KUBERNETES_TEST_GIT_BRANCH:               $KUBERNETES_TEST_GIT_BRANCH"
log_level -i "KUBERNETES_TEST_GIT_REPOSITORY:           $KUBERNETES_TEST_GIT_REPOSITORY"
log_level -i "MASTER_COUNT:                             $MASTER_COUNT"
log_level -i "MASTER_SIZE:                              $MASTER_SIZE"
log_level -i "K8S_ORCHESTRATOR_VERSION:                 $K8S_ORCHESTRATOR_VERSION"
log_level -i "NODE_DISTRO:                              $NODE_DISTRO"
log_level -i "SPN_CLIENT_ID:                            ----"
log_level -i "SPN_CLIENT_SECRET:                        ----"
log_level -i "SSH_PUBLICKEY:                            ----"
log_level -i "PUBLICIP_DNS:                             $PUBLICIP_DNS"
log_level -i "PUBLICIP_FQDN:                            $PUBLICIP_FQDN"
log_level -i "REGION_NAME:                              $REGION_NAME"
log_level -i "TENANT_ID:                                $TENANT_ID"
log_level -i "TENANT_SUBSCRIPTION_ID:                   $TENANT_SUBSCRIPTION_ID"
log_level -i "RESOURCE_GROUP_NAME:                      $RESOURCE_GROUP_NAME"

log_level -i "------------------------------------------------------------------------"
log_level -i "Constants"
log_level -i "------------------------------------------------------------------------"

export HOME=/root
LOG_PATH="$HOME/logs"
SECRET_PATH="$HOME/secret"
ACK_PUBLIC_KEY_PATH="$SECRET_PATH/id_rsa.pub"
AZURE_CREDS_PATH="$HOME/secret/azure_creds.toml"
ENVIRONMENT_NAME=AzureStackCloud
IDENTITY_SYSTEM_TYPE="azure_ad"
K8S_PATH="$HOME/go/src/k8s.io"
KUBERNETES_LOCAL_PATH="${K8S_PATH}/kubernetes"
KUBERNETES_BIN_PATH="${KUBERNETES_LOCAL_PATH}/_output/local/bin/linux/amd64"
KUBERNETES_GIT_REPO="https://github.com/${KUBERNETES_GIT_REPOSITORY}"
KUBERNETES_E2E_TEST_LOCAL_PATH="${K8S_PATH}/test-infra"
KUBERNETES_E2E_TEST_GIT_REPO="https://github.com/${KUBERNETES_TEST_GIT_REPOSITORY}"

# Kube test specific parameters
BUILD_CUSTOM_CLOUD_CONTROLLER="${BUILD_CUSTOM_CLOUD_CONTROLLER:-false}"
CLUSTER_DEFINITION="$CLUSTER_DEFINITION_BASE_URL/$DEFINITION_TEMPLATE_NAME"
FLAKE_ATTEMPTS=2
GINKGO_PARALLEL_ARG="--ginkgo-parallel=32"
NODE_OS_ARG="--node-os-distro=ubuntu"
SKIP_TEST_ARG='--ginkgo.skip=".*\\[Slow\\].*|.*\\[Flaky\\].*"'
TEAR_DOWN="${TEAR_DOWN:-false}"
TESTS_TO_RUN=".*\\[NodeConformance\\].*|.*\\[Conformance\\].*"
VERBOSE=false

if [ $IDENTITY_SYSTEM == "ADFS" ]; then
    IDENTITY_SYSTEM_TYPE="adfs"
fi

log_level -i "------------------------------------------------------------------------"
log_level -i "ACK_PUBLIC_KEY_PATH:                $ACK_PUBLIC_KEY_PATH"
log_level -i "AZURE_CREDS_PATH:                   $AZURE_CREDS_PATH"
log_level -i "ENVIRONMENT_NAME:                   $ENVIRONMENT_NAME"
log_level -i "IDENTITY_SYSTEM_TYPE:               $IDENTITY_SYSTEM_TYPE"
log_level -i "K8S_PATH:                           $K8S_PATH"
log_level -i "KUBERNETES_BIN_PATH:                $KUBERNETES_BIN_PATH"
log_level -i "KUBERNETES_GIT_REPO:                $KUBERNETES_GIT_REPO"
log_level -i "KUBERNETES_LOCAL_PATH:              $KUBERNETES_LOCAL_PATH"
log_level -i "KUBERNETES_E2E_TEST_GIT_REPO:       $KUBERNETES_E2E_TEST_GIT_REPO"
log_level -i "KUBERNETES_E2E_TEST_LOCAL_PATH:     $KUBERNETES_E2E_TEST_LOCAL_PATH"
log_level -i "LOG_PATH:                           $LOG_PATH"
log_level -i "SECRET_PATH:                        $SECRET_PATH"
log_level -i "------------------------------------------------------------------------"
log_level -i "BUILD_CUSTOM_CLOUD_CONTROLLER:      $BUILD_CUSTOM_CLOUD_CONTROLLER"
log_level -i "CLUSTER_DEFINITION:                 $CLUSTER_DEFINITION"
log_level -i "FLAKE_ATTEMPTS:                     $FLAKE_ATTEMPTS"
log_level -i "GINKGO_PARALLEL_ARG:                $GINKGO_PARALLEL_ARG"
log_level -i "NODE_OS_ARG:                        $NODE_OS_ARG"
log_level -i "SKIP_TEST_ARG:                      $SKIP_TEST_ARG"
log_level -i "TEAR_DOWN:                          $TEAR_DOWN"
log_level -i "TESTS_TO_RUN:                       $TESTS_TO_RUN"
log_level -i "VERBOSE:                            $VERBOSE"
log_level -i "------------------------------------------------------------------------"

WAIT_TIME_SECONDS=20
log_level -i "Waiting for $WAIT_TIME_SECONDS seconds to allow the system to stabilize.";
sleep $WAIT_TIME_SECONDS

log_level -i "Install all prerequisite"
ensure_certificates
install_docker
install_go $GO_VERSION
install_bazel $BAZEL_BUILD_VERSION
apt_get_install 30 1 600  \
jq \
|| exit 0

log_level -i "Get custom portal URL"
EXTERNAL_FQDN="${PUBLICIP_FQDN//$PUBLICIP_DNS.$REGION_NAME.cloudapp.}"
TENANT_ENDPOINT="https://management.$REGION_NAME.$EXTERNAL_FQDN"
AZURESTACK_RESOURCE_METADATA_ENDPOINT="$TENANT_ENDPOINT/metadata/endpoints?api-version=2015-01-01"
log_level -i "EXTERNAL_FQDN: $EXTERNAL_FQDN"
log_level -i "TENANT_ENDPOINT: $TENANT_ENDPOINT"
log_level -i "AZURESTACK_RESOURCE_METADATA_ENDPOINT: $AZURESTACK_RESOURCE_METADATA_ENDPOINT"
log_level -i "Computing cluster definition values."
METADATA=`curl -s -f --retry 10 $AZURESTACK_RESOURCE_METADATA_ENDPOINT` || exit $ERR_METADATA_ENDPOINT
echo $METADATA > metadata.json
ENDPOINT_PORTAL=`echo $METADATA | jq '.portalEndpoint' | xargs`
rm metadata.json
log_level -i "ENDPOINT_PORTAL: $ENDPOINT_PORTAL"

log_level -i "Create all folders"
mkdir -p $K8S_PATH
mkdir -p $SECRET_PATH
mkdir -p $LOG_PATH

log_level -i "Enlist K8s and test repository"
git clone -b ${KUBERNETES_TEST_GIT_BRANCH} ${KUBERNETES_E2E_TEST_GIT_REPO} ${KUBERNETES_E2E_TEST_LOCAL_PATH}
cd ${KUBERNETES_E2E_TEST_LOCAL_PATH}
go install k8s.io/test-infra/kubetest

git clone -b ${KUBERNETES_GIT_BRANCH} ${KUBERNETES_GIT_REPO} ${KUBERNETES_LOCAL_PATH}
cd ${KUBERNETES_LOCAL_PATH}
make WHAT=cmd/kubectl
mv ${KUBERNETES_BIN_PATH}/kubectl /usr/local/bin

export TMPDIR=$LOG_PATH
echo $SSH_PUBLICKEY >> $ACK_PUBLIC_KEY_PATH

install_bazel 0.23.2
create_secretfile

log_level -i "Launch kube tests."
$GOPATH/bin/kubetest \
	${GINKGO_PARALLEL_ARG} \
	--timeout=400m \
	--verbose-commands=${VERBOSE} \
	--test \
	--check-version-skew=false \
	--test=true \
	--up=true \
	--down=${TEAR_DOWN} \
	--deployment=acsengine \
	--build=bazel \
	--provider=skeleton \
	--acsengine-agentpoolcount=${AGENT_COUNT} \
	--acsengine-admin-username=${ADMIN_USERNAME} \
	--acsengine-creds=${AZURE_CREDS_PATH} \
	--acsengine-orchestratorRelease=${K8S_ORCHESTRATOR_VERSION} \
	--acsengine-mastervmsize=${MASTER_SIZE} \
	--acsengine-agentvmsize=${AGENT_SIZE} \
	--acsengine-hyperkube=${BUILD_HYPERKUBE} \
	--acsengine-public-key=${ACK_PUBLIC_KEY_PATH} \
	--acsengine-ccm=${BUILD_CUSTOM_CLOUD_CONTROLLER} \
	--acsengine-location=${REGION_NAME} \
	--acsengine-template-url=${CLUSTER_DEFINITION} \
	--acsengine-azure-env=${ENVIRONMENT_NAME} \
	--acsengine-identity-system=${IDENTITY_SYSTEM_TYPE} \
	--acsengine-custom-cloud-url=${ENDPOINT_PORTAL} \
	--acsengine-download-url=https://github.com/Azure/aks-engine/releases/download/${AKSE_RELEASE_VERSION}/aks-engine-${AKSE_RELEASE_VERSION}-linux-amd64.tar.gz \
	--test_args="--ginkgo.flakeAttempts=${FLAKE_ATTEMPTS} \
		--num-nodes=${AGENT_COUNT} \
		--ginkgo.succinct \
		--ginkgo.noisyPendings=false \
		--log_dir=${LOG_PATH} \
		--log_file=kubetest.log \
		-report-dir=${LOG_PATH}/reports \
		--ginkgo.focus=${TESTS_TO_RUN} \
		${SKIP_TEST_ARG} \
		${NODE_OS_ARG}" || exit $ERR_KUBETEST_FAILED