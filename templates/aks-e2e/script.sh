#!/bin/bash -ex

ERR_APT_INSTALL_TIMEOUT=9 # Timeout installing required apt packages
ERR_AKSE_DOWNLOAD=10 # Failure downloading AKS-Engine binaries
ERR_AKSE_DEPLOY=12 # Failure calling AKS-Engine's deploy operation
ERR_TEMPLATE_DOWNLOAD=13 # Failure downloading AKS-Engine template
ERR_INVALID_AGENT_COUNT_VALUE=14 # Both Windows and Linux agent value is zero 
ERR_TEMPLATE_GENERATION=15 # The default api model could not be generated
ERR_CACERT_INSTALL=20 # Failure moving CA certificate
ERR_METADATA_ENDPOINT=30 # Failure calling the metadata endpoint
ERR_API_MODEL=40 # Failure building API model using user input
ERR_AZS_CLOUD_REGISTER=50 # Failure calling az cloud register
ERR_APT_UPDATE_TIMEOUT=99 # Timeout waiting for apt-get update to complete
#ERR_AKSE_GENERATE=11 # Failure calling AKS-Engine's generate operation
#ERR_MS_GPG_KEY_DOWNLOAD_TIMEOUT=26 # Timeout waiting for Microsoft's GPG key download
#ERR_AZS_CLOUD_ENVIRONMENT=51 # Failure setting az cloud environment
#ERR_AZS_CLOUD_PROFILE=52 # Failure setting az cloud profile
#ERR_AZS_LOGIN_AAD=53 # Failure to log in to AAD environment
#ERR_AZS_LOGIN_ADFS=54 # Failure to log in to ADFS environment
#ERR_AZS_ACCOUNT_SUB=55 # Failure setting account default subscription

function collect_deployment_and_operations
{
    # Store main exit code
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -ne 0 ]; then
        log_level -i "CustomScript extension failed with exit code $EXIT_CODE"
    fi
    
    log_level -i "CustomScript extension run to completion."
    exit $EXIT_CODE
}

# Collect deployment logs always, even if the script ends with an error
trap collect_deployment_and_operations EXIT

cleanUpGPUDrivers() {
    rm -f /etc/apt/sources.list.d/nvidia-docker.list
    apt-key del $(apt-key list | grep NVIDIA -B 1 | head -n 1 | cut -d "/" -f 2 | cut -d " " -f 1)
}

###
#   <summary>
#       Logs output by prepending date and log level type(Error, warning, info or verbose).
#   </summary>
#   <param name="1">Type to log. (Valid values are: -e for error, -w for warning, -i for info, else verbose)</param>
#   <param name="...">Output echo string.</param>
#   <returns>None</returns>
#   <exception>None</exception>
#   <remarks>Called within same scripts.</remarks>
###
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

###
#   <summary>
#      Validate if file exist and it has non zero bytes. If validation passes moves file to new location.
#   </summary>
#   <param name="1">Source File Name.</param>
#   <param name="2">Destination File Name.</param>
#   <returns>None</returns>
#   <exception>Can exit with error code 1 in case file does not exist or size is zero.</exception>
#   <remarks>Called within same scripts.</remarks>
###
validate_and_restore_cluster_definition()
{
    if [ ! -s $1 ]; then
        log_level -e "Cluster definition file '$1' does not exist or it is empty. An error happened while manipulating its json content."
        exit 1
    fi
    mv $1 $2
}

###
#   <summary>
#       Copies Azure Stack root certificate to the appropriate store.
#   </summary>
#   <returns>None</returns>
#   <exception>None</exception>
#   <remarks>Called within same scripts.</remarks>
###
ensure_certificates()
{
    log_level -i "Moving certificates to appropriate store"
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH="/var/lib/waagent/Certificates.pem"
    AZURESTACK_ROOT_CERTIFICATE_DEST_PATH="/usr/local/share/ca-certificates/azsCertificate.crt"
    
    log_level -i "Copy ca-cert from '$AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH' to '$AZURESTACK_ROOT_CERTIFICATE_DEST_PATH' "
    cp $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH
    
    AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH -noout -fingerprint`
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT"
    
    AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH -noout -fingerprint`
    log_level -i "AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT: $AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT"
    
    update-ca-certificates
    
    # Required by Azure CLI
    export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    echo "REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt" | tee -a /etc/environment > /dev/null
}

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
# Function taken from the AKSe's code based
apt_get_update()
{
    log_level -i "Updating apt cache."
    
    retries=10
    apt_update_output=/tmp/apt-get-update.out
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        dpkg --configure -a
        apt-get -f -y install
        apt-get update 2>&1 | tee $apt_update_output | grep -E "^([WE]:.*)|([eE]rr.*)$"
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
# Function taken from the AKSe's code based
apt_get_install()
{
    retries=$1; wait_sleep=$2; timeout=$3;
    shift && shift && shift
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        dpkg --configure -a
        apt-get install --no-install-recommends -y ${@}
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

#####################################################################################
# start

log_level -i "Starting Kubernetes cluster deployment: v1.0.3"
log_level -i "Running script as:  $(whoami)"
log_level -i "System information: $(uname -a)"

log_level -i "------------------------------------------------------------------------"
log_level -i "ARM parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "IDENTITY_SYSTEM:                          $IDENTITY_SYSTEM"
log_level -i "PUBLICIP_FQDN:                            $PUBLICIP_FQDN"
log_level -i "REGION_NAME:                              $REGION_NAME"
log_level -i "SPN_CLIENT_ID:                            ----"
log_level -i "SPN_CLIENT_SECRET:                        ----"
log_level -i "TENANT_ID:                                $TENANT_ID"
log_level -i "TENANT_SUBSCRIPTION_ID:                   $TENANT_SUBSCRIPTION_ID"

log_level -i "------------------------------------------------------------------------"
log_level -i "Constants"
log_level -i "------------------------------------------------------------------------"

ENVIRONMENT_NAME=AzureStackCloud
AUTH_METHOD="client_secret"
IDENTITY_SYSTEM_LOWER="azure_ad"

log_level -i "ENVIRONMENT_NAME: $ENVIRONMENT_NAME"

WAIT_TIME_SECONDS=20
log_level -i "Waiting for $WAIT_TIME_SECONDS seconds to allow the system to stabilize.";
sleep $WAIT_TIME_SECONDS

#####################################################################################
# apt packages
# leaving this part connected until the modules are added to vhd

cleanUpGPUDrivers
if [ ! $DISCONNECTED_AKS_ENGINE_URL ]
then
    log_level -i "Updating apt cache."
    apt_get_update || exit $ERR_APT_UPDATE_TIMEOUT

    log_level -i "Installing azure-cli and dependencies."
    apt_get_install 30 1 600  \
    pax \
    ca-certificates \
    gnupg-agent \
    jq \
    curl \
    apt-transport-https \
    lsb-release \
    software-properties-common \
    dirmngr \
    || exit $ERR_APT_INSTALL_TIMEOUT
fi

# log_level -i "Installing Docker"

# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# add-apt-repository \
#    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
#    $(lsb_release -cs) \
#    stable"

# apt_get_install 30 1 600 \
# docker-ce \
# docker-ce-cli \
# containerd.io \

# log_level -i "Docker install Complete"

#####################################################################################
# certificates

log_level -i "Moving certificates to the expected locations as required by AKSe"
ensure_certificates || exit $ERR_CACERT_INSTALL


#####################################################################################
# downloading repository

git clone https://github.com/jadarsie/e2e-ci-poc.git

cd e2e-ci-poc

cat > env/sample.env <<EOL
export IDENTITY_SYSTEM="${IDENTITY_SYSTEM}"
export CLOUD_FQDN="${PUBLICIP_FQDN}"
export CLOUD_AZCLI_NAME="${ENVIRONMENT_NAME}"
export AZURE_LOCATION="${REGION_NAME}"
export AZURE_CLIENT_ID="${SPN_CLIENT_ID}"
export AZURE_CLIENT_SECRET="${SPN_CLIENT_SECRET}"
export AZURE_SUBSCRIPTION_ID="${TENANT_SUBSCRIPTION_ID}"
export AZURE_TENANT_ID="${TENANT_ID}"
EOL

sudo chmod +x ./scripts/setup-dvm.sh

./scripts/setup-dvm.sh

make run-local INPUT=env/sample.env