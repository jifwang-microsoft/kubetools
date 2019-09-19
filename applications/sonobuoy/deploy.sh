#!/bin/bash -e

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

printUsage()
{
    echo "      Usage:"
    echo "      $FILENAME --identity-file id_rsa --master 192.168.102.34 --user azureuser"
    echo  ""
    echo "            -i, --identity-file                         RSA Private Key file to connect kubernetes master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -m, --master                                Public ip of Kubernetes cluster master VM. Normally VM name starts with k8s-master- "
    echo "            -u, --user                                  User Name of Kubernetes cluster master VM "
    echo "            -o, --output-file                           Summary file providing result status of the deployment."
    exit 1
}

function final_changes {
    if [ ! -f "$OUTPUT_SUMMARYFILE" ]; then
        printf '{"result":"%s"}\n' "failed" > $OUTPUT_SUMMARYFILE
    fi
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITY_FILE="$2"
        ;;
        -m|--master)
            MASTER_IP="$2"
        ;;
        -u|--user)
            USER_NAME="$2"
        ;;
        -o|--output-file)
            OUTPUT_SUMMARYFILE="$2"
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

FILE_NAME=$0

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/deploy.log"
touch $LOG_FILENAME

{
    # Github details.
    COMMON_SCRIPT_FILENAME="common.sh"
    GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
    GIT_BRANCH="${GIT_BRANCH:-master}"
    INSTALL_PREREQUISITE="install_prerequisite.sh"
    SCRIPT_DIRECTORY="$(dirname $FILE_NAME)"

    TEST_DIRECTORY="/home/$USER_NAME/sonobuoy"

    log_level -i "------------------------------------------------------------------------"
    log_level -i "Input Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "IDENTITY_FILE         : $IDENTITY_FILE"
    log_level -i "GIT_BRANCH            : $GIT_BRANCH"
    log_level -i "GIT_REPROSITORY       : $GIT_REPROSITORY"
    log_level -i "MASTER_IP             : $MASTER_IP"
    log_level -i "OUTPUT_SUMMARYFILE    : $OUTPUT_SUMMARYFILE"
    log_level -i "USER_NAME             : $USER_NAME"    
    log_level -i "------------------------------------------------------------------------"
    
    log_level -i "Based on K8s define which version of SONOBUOY to be used."
    KUBERNETES_VERSION=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP 'kubectl version -o json | jq -r .serverVersion.gitVersion | cut -c 2-')
    KUBERNETES_MAJOR_VERSION="${KUBERNETES_VERSION%.*}"

    case "$KUBERNETES_MAJOR_VERSION" in

    1.11)  SONOBUOY_VERSION="0.13.0"
        ;;
    1.15)  SONOBUOY_VERSION="0.15.0"
        ;;
    1.16)  SONOBUOY_VERSION="0.16.0"
        ;;
    *) SONOBUOY_VERSION="0.14.0"
        ;;
    esac

    SONOBUOY_TAR_FILENAME="sonobuoy_"$SONOBUOY_VERSION"_linux_amd64.tar.gz"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "COMMON_SCRIPT_FILENAME   : $COMMON_SCRIPT_FILENAME"    
    log_level -i "INSTALL_PREREQUISITE     : $INSTALL_PREREQUISITE"
    log_level -i "KUBERNETES_MAJOR_VERSION : $KUBERNETES_MAJOR_VERSION"
    log_level -i "KUBERNETES_VERSION       : $KUBERNETES_VERSION"
    log_level -i "SCRIPT_DIRECTORY         : $SCRIPT_DIRECTORY"
    log_level -i "SONOBUOY_TAR_FILENAME    : $SONOBUOY_TAR_FILENAME"
    log_level -i "SONOBUOY_VERSION         : $SONOBUOY_VERSION"
    log_level -i "TEST_DIRECTORY           : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"
    
    # ----------------------------------------------------------------------------------------
    # INSTALL PREREQUISITE
    curl -o $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/common/$COMMON_SCRIPT_FILENAME
    if [ ! -f $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME ]; then
        log_level -e "File($COMMON_SCRIPT_FILENAME) failed to download."
        exit 1
    fi

    source $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME
    download_file_locally $GIT_REPROSITORY \
    $GIT_BRANCH \
    "applications/common" \
    $SCRIPT_DIRECTORY \
    $INSTALL_PREREQUISITE
    
    if [[ $? != 0 ]]; then
        log_level -e "Download of file($INSTALL_PREREQUISITE) failed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Download of file($INSTALL_PREREQUISITE) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    log_level -i "Create test folder($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"
    log_level -i "Copy file($INSTALL_PREREQUISITE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$INSTALL_PREREQUISITE \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/
    
    # INSTALL PREREQUISITE
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_DIRECTORY/$INSTALL_PREREQUISITE; "
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $INSTALL_PREREQUISITE; apt_install_important_packages ;"
    goPath=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "go env | grep GOPATH || true")
    if [ -z "$goPath" ]; then
        log_level -e "GO is not installed."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Go is not installed." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Go installed with GOPATH($goPath)"
    fi
    # ----------------------------------------------------------------------------------------
    # Install Sonobuoy
    curl -L -o $OUTPUT_FOLDER/$SONOBUOY_TAR_FILENAME \
    https://github.com/heptio/sonobuoy/releases/download/v$SONOBUOY_VERSION/$SONOBUOY_TAR_FILENAME
    if [ ! -f $OUTPUT_FOLDER/$SONOBUOY_TAR_FILENAME ]; then
        log_level -e "File($SONOBUOY_TAR_FILENAME) failed to download."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "File($SONOBUOY_TAR_FILENAME) failed to download." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Copy file($SONOBUOY_TAR_FILENAME) to VM."
    scp -i $IDENTITY_FILE \
    $OUTPUT_FOLDER/$SONOBUOY_TAR_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; sudo tar -xvf $SONOBUOY_TAR_FILENAME"
    # ----------------------------------------------------------------------------------------
    # Launch Sonobuoy
    
    #ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; ./sonobuoy run --mode quick;"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; ./sonobuoy run;"
    
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    
    #Create result file, even if script ends with an error
    #trap final_changes EXIT
    
} 2>&1 | tee $LOG_FILENAME