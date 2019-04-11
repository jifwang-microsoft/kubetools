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
        -c|--configFile)
            CONFIG_FILE="$2"
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

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/deploy.log"
touch $LOG_FILENAME

{
    # Github details.
    GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
    GIT_BRANCH="${GIT_BRANCH:-master}"
    HELM_INSTALL_FILENAME="install_helm.sh"
    WORDPRESS_INSTALL_FILEANME="install_wordpress_using_helm.sh"
    TEST_DIRECTORY="/home/$USER_NAME/wordpress"

    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Input Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "IDENTITY_FILE   : $IDENTITY_FILE"
    log_level -i "GIT_BRANCH      : $GIT_BRANCH"
    log_level -i "GIT_REPROSITORY : $GIT_REPROSITORY"
    log_level -i "MASTER_IP       : $MASTER_IP"
    log_level -i "OUTPUT_SUMMARYFILE     : $OUTPUT_SUMMARYFILE"
    log_level -i "USER_NAME       : $USER_NAME"
    log_level -i "------------------------------------------------------------------------"
    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "HELM_INSTALL_FILENAME       : $HELM_INSTALL_FILENAME"
    log_level -i "TEST_DIRECTORY              : $TEST_DIRECTORY"
    log_level -i "WORDPRESS_INSTALL_FILEANME  : $WORDPRESS_INSTALL_FILEANME"
    
    log_level -i "------------------------------------------------------------------------"
    
    curl -o $OUTPUT_FOLDER/$HELM_INSTALL_FILENAME \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/wordpress/$HELM_INSTALL_FILENAME
    if [ ! -f $OUTPUT_FOLDER/$HELM_INSTALL_FILENAME ]; then
        log_level -e "File($HELM_INSTALL_FILENAME) failed to download."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Download of file($HELM_INSTALL_FILENAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    curl -o $OUTPUT_FOLDER/$WORDPRESS_INSTALL_FILEANME \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/wordpress/$WORDPRESS_INSTALL_FILEANME
    if [ ! -f $OUTPUT_FOLDER/$WORDPRESS_INSTALL_FILEANME ]; then
        log_level -e "File($WORDPRESS_INSTALL_FILEANME) failed to download."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Download of file($HELM_INSTALL_FILENAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Create test folder($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"

    log_level -i "Copy files to K8s master node."
    scp -i $IDENTITY_FILE \
    $OUTPUT_FOLDER/$HELM_INSTALL_FILENAME \
    $OUTPUT_FOLDER/$WORDPRESS_INSTALL_FILEANME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/
    
    # Install Helm chart
    log_level -i "=========================================================================="
    log_level -i "Installing Helm chart."
    ssh -t -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP \
    "sudo chmod 744 $TEST_DIRECTORY/$HELM_INSTALL_FILENAME; cd $TEST_DIRECTORY; ./$HELM_INSTALL_FILENAME;"
    helmServerVer=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm version | grep -o 'Server: \(.*\)[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'")
    if [ -z "$helmServerVer" ]; then
        log_level -e "Helm install failed."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Helm install was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Helm got installed successfully. The version is: $helmServerVer"
    fi
    
    log_level -i "=========================================================================="
    log_level -i "Installing Wordpress app."
    # Install Wordpress app
    ssh -t -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP \
    "sudo chmod 744 $TEST_DIRECTORY/$WORDPRESS_INSTALL_FILEANME.sh; cd $TEST_DIRECTORY; ./$WORDPRESS_INSTALL_FILEANME;"
    wpRelease=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm ls -d -r | grep 'DEPLOYED\(.*\)wordpress' | grep -Eo '^[a-z,-]+'")
    if [ -z "$wpRelease" ]; then
        log_level -e "Wordpress deployment failed using Helm."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Wordpress deployment was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Helm deployed wordpress app with deployment name as: $wpRelease."
    fi
    log_level -i "=========================================================================="
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME