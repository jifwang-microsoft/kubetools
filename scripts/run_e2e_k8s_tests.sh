
printUsage()
{
    echo "      Usage:"
    echo "      $FILENAME --clientID 844d0ce5-4523-48a9-b0f3-5533da7f4170 --location local --portalURL https://portal.local.azurestack.external/ --clientSecret xxx --tenantID 844d0ce5-4523-48a9-b0f3-5533da7f4170 --subscriptionID 844d0ce5-4523-48a9-b0f3-5533da7f4170 --identityType adfs"
    echo  ""
    echo "            --clientID                         Client Id to be used."
    echo "            --clientSecret                     Client Secret to be used."
    echo "            --identityType                     Identity type of given Azs deployment."
    echo "            --location                         Location of Azs deployment."
    echo "            --portalURL                        Portal URL of Azs deployment."    
    echo "            --subscriptionID                   Subscription Id to be used."
    echo "            --tenantID                         Tenant Id to be used."
    exit 1
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
    sudo apt-get install -y pkg-config zip g++ zlib1g-dev unzip python3
    wget -q "${downloadURL}" && chmod +x "${installer}"
    sudo "./${installer}"
    rm "${installer}"
    bazel version
}

install_docker()
{
    apt-get -y update
    apt install -y docker.io
    systemctl start docker
    systemctl enable docker
}

install_go()
{
    local goVersion=$1

    if [ -z "$goVersion" ]; then
        goVersion=1.12.6
    fi
    sudo apt-get -y update
    sudo apt-get -y upgrade
    wget https://dl.google.com/go/go${goVersion}.linux-amd64.tar.gz
    sudo tar -xvf go${goVersion}.linux-amd64.tar.gz
    sudo mv go /usr/local
    export GOROOT=/usr/local/go
    export GOPATH=$HOME/go
    export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
}


create_secretfile()
{
    echo "Creds.ClientID = $CLIENT_ID" >> $AZURE_CREDS_PATH
    echo "Creds.ClientSecret = $CLIENT_SECRET" >> $AZURE_CREDS_PATH
    if [$IDENTITY_TYPE -eq "adfs"]; then
        echo "Creds.TenantID = adfs" >> $AZURE_CREDS_PATH
    else
        echo "Creds.TenantID = $TENANT_ID" >> $AZURE_CREDS_PATH
    fi
    echo "Creds.SubscriptionID = $SUBSCRIPTION_ID" >> $AZURE_CREDS_PATH
    echo "Creds.StorageAccountName = none" >> $AZURE_CREDS_PATH
    echo "Creds.StorageAccountKey = none" >> $AZURE_CREDS_PATH
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        --clientID)
            CLIENT_ID="$2"
        ;;
        --clientSecret)
            CLIENT_SECRET="$2"
        ;;
        --identityType)
            IDENTITY_TYPE="$2"
        ;;
        --location)
            LOCATION="$2"
        ;;
        --portalURL)
            PORTAL_URL="$2"
        ;;
        --subscriptionID)
            SUBSCRIPTION_ID="$2"
        ;;
        --tenantID)
            TENANT_ID="$2"
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

if [[ -z "$CLIENT_ID" ]] || \
[[ -z "$CLIENT_SECRET" ]] || \
[[ -z "$IDENTITY_TYPE" ]] || \
[[ -z "$PORTAL_URL" ]] || \
[[ -z "$LOCATION" ]] || \
[[ -z "$SUBSCRIPTION_ID" ]] || \
[[ -z "$TENANT_ID" ]]; then
    log_level -e "One of mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi


ensure_certificates
install_docker
install_go
install_bazel 0.28.0

K8S_PATH="$HOME/go/src/k8s.io"
mkdir -p $K8S_PATH
mkdir -p $HOME/secret

KUBERNETES_GIT_REPO="${KUBERNETES_GIT_REPO:-https://github.com/msazurestackworkloads/kubernetes.git}"
KUBERNETES_GIT_BRANCH="${KUBERNETES_GIT_BRANCH:-release-1.13}"
KUBERNETES_REPO_PATH="${K8S_PATH}/kubernetes"
KUBERNETES_BIN_PATH="${KUBERNETES_REPO_PATH}/_output/local/bin/linux/amd64"
ssh-keygen -b 2048 -t rsa -f $HOME/.ssh/id_rsa -q -N ''

KUBERNETES_E2E__GIT_REPO="${KUBERNETES_E2E__GIT_REPO:-https://github.com/rjaini/test-infra.git}"
KUBERNETES_E2E_GIT_BRANCH="${KUBERNETES_E2E_GIT_BRANCH:-azurestack}"
KUBERNETES_E2E_REPO_PATH="${K8S_PATH}/test-infra"
git clone -b ${KUBERNETES_E2E_GIT_BRANCH} ${KUBERNETES_E2E__GIT_REPO} ${KUBERNETES_E2E_REPO_PATH}
cd ${KUBERNETES_E2E_REPO_PATH}
go install k8s.io/test-infra/kubetest

git clone -b ${KUBERNETES_GIT_BRANCH} ${KUBERNETES_GIT_REPO} ${KUBERNETES_REPO_PATH}
cd ${KUBERNETES_REPO_PATH}
make WHAT=cmd/kubectl
sudo mv ${KUBERNETES_BIN_PATH}/kubectl /usr/local/bin

export TMPDIR=$HOME/secret/
ACK_PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub"
AGENT_VM_SIZE="${AGENT_VM_SIZE:-Standard_D2_v2}"
AKS_ENGINE_VERSION="${AKS_ENGINE_VERSION:-v0.38.4}"
AZURE_CREDS_PATH="$HOME/secret/azure_creds.toml"
AZURE_ENV="${AZURE_ENV:-AzureStackCloud}"
BUILD_CUSTOM_CLOUD_CONTROLLER="${BUILD_CUSTOM_CLOUD_CONTROLLER:-false}"
BUILD_HYPERKUBE="${BUILD_HYPERKUBE:-false}"
CLUSTER_DEFINITION="${CLUSTER_DEFINITION:-https://raw.githubusercontent.com/Azure/aks-engine/master/examples/azure-stack/kubernetes-azurestack.json}"
CUSTOM_CLOUD_URL=$PORTAL_URL
DEPLOY_REGION=$LOCATION
FLAKE_ATTEMPTS=2
GINKGO_PARALLEL_ARG="--ginkgo-parallel=32"

LOG_DIR="$HOME/logs"
MASTER_VM_SIZE="${MASTER_VM_SIZE:-Standard_D2_v2}"
NODE_OS_ARG="--node-os-distro=ubuntu"
NUMBER_OF_AGENTS="${NUMBER_OF_AGENTS:-3}"
ORCHESTRATOR_VERSION="${ORCHESTRATOR_VERSION:-1.13}"
SKIP_TEST_ARG='--ginkgo.skip=".*\\[Slow\\].*|.*\\[Flaky\\].*"'
TEAR_DOWN="${TEAR_DOWN:-false}"
TESTS_TO_RUN=".*\\[NodeConformance\\].*|.*\\[Conformance\\].*"
VERBOSE=false

mkdir -p $LOG_DIR
install_bazel 0.23.2
create_secretfile

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
	--acsengine-agentpoolcount=${NUMBER_OF_AGENTS} \
	--acsengine-admin-username=azureuser \
	--acsengine-creds=${AZURE_CREDS_PATH} \
	--acsengine-orchestratorRelease=${ORCHESTRATOR_VERSION} \
	--acsengine-mastervmsize=${MASTER_VM_SIZE} \
	--acsengine-agentvmsize=${AGENT_VM_SIZE} \
	--acsengine-hyperkube=${BUILD_HYPERKUBE} \
	--acsengine-public-key=${ACK_PUBLIC_KEY_PATH} \
	--acsengine-ccm=${BUILD_CUSTOM_CLOUD_CONTROLLER} \
	--acsengine-location=${DEPLOY_REGION} \
	--acsengine-template-url=${CLUSTER_DEFINITION} \
	--acsengine-azure-env=${AZURE_ENV} \
	--acsengine-identity-system=${IDENTITY_TYPE} \
	--acsengine-custom-cloud-url=${CUSTOM_CLOUD_URL} \
	--acsengine-download-url=https://github.com/Azure/aks-engine/releases/download/${AKS_ENGINE_VERSION}/aks-engine-${AKS_ENGINE_VERSION}-linux-amd64.tar.gz \
	--test_args="--ginkgo.flakeAttempts=${FLAKE_ATTEMPTS} \
		--num-nodes=${NUMBER_OF_AGENTS} \
		--ginkgo.succinct \
		--ginkgo.noisyPendings=false \
		--log_dir=${LOG_DIR} \
		--log_file=kubetest.log \
		-report-dir=${LOG_DIR}/reports \
		--ginkgo.focus=${TESTS_TO_RUN} \
		${SKIP_TEST_ARG} \
		${NODE_OS_ARG}"