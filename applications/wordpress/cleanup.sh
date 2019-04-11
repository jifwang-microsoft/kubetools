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
        -c|--configFile)
            CONFIG_FILE="$2"
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

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/cleanup.log"
touch $LOG_FILENAME

{
    WORDPRESS_LOG_FOLDERNAME="var_log"
    WORDPRESS_TAR_FILENAME="var_log.tar.gz"
    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Input Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "IDENTITY_FILE       : $IDENTITY_FILE"
    log_level -i "MASTER_IP           : $MASTER_IP"
    log_level -i "OUTPUT_SUMMARYFILE  : $OUTPUT_SUMMARYFILE"
    log_level -i "USER_NAME           : $USER_NAME"
    log_level -i "------------------------------------------------------------------------"
    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "WORDPRESS_LOG_FOLDERNAME : $WORDPRESS_LOG_FOLDERNAME"
    log_level -i "WORDPRESS_TAR_FILENAME   : $WORDPRESS_TAR_FILENAME"
    log_level -i "------------------------------------------------------------------------"
    
    # Cleanup Word press app.
    wordPressDeploymentName=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm ls -d -r | grep 'DEPLOYED\(.*\)wordpress' | grep -Eo '^[a-z,-]+' || true")
    if [ -z "$wordPressDeploymentName" ]; then
        log_level -w "No deployment found."
    else
        log_level -i "Removing helm deployment($wordPressDeploymentName)"
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm delete --purge $wordPressDeploymentName"
        log_level -i "Wait for 30s for all pods to be deleted and removed."
        sleep 30s
    fi
    
    log_level -i "Delete previous created log data($WORDPRESS_LOG_FOLDERNAME, $WORDPRESS_TAR_FILENAME) "
    ssh -t -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP \
    "sudo rm -f -r $WORDPRESS_LOG_FOLDERNAME $WORDPRESS_TAR_FILENAME || true"
    
    log_level -i "Create folder $WORDPRESS_LOG_FOLDERNAME "
    ssh -t -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP \
    "mkdir -p $WORDPRESS_LOG_FOLDERNAME"
    
    log_level -i "Copy logs to $WORDPRESS_LOG_FOLDERNAME "
    ssh -t -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP \
    "sudo cp -R /var/log /home/$USER_NAME/$WORDPRESS_LOG_FOLDERNAME;"
    
    ssh -t -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP \
    "sudo tar -zcvf $WORDPRESS_TAR_FILENAME $WORDPRESS_LOG_FOLDERNAME;"
    
    log_level -i "Copy log file($WORDPRESS_TAR_FILENAME) to $OUTPUT_FOLDER"
    scp -r -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP:/home/$USER_NAME/$WORDPRESS_TAR_FILENAME $OUTPUT_FOLDER
    log_level -i "Logs are copied into $OUTPUT_FOLDER"
    
    # Rechecking to make sure deployment cleanup done successfully.
    wpRelease=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm ls -d -r | grep 'DEPLOYED\(.*\)wordpress' | grep -Eo '^[a-z,-]+' || true")
    if [ ! -z "$wpRelease" ]; then
        log_level -e "Removal of wordpress app failed($wpRelease)."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "App($wordPressDeploymentName) cleanup was not successfull." > $OUTPUT_SUMMARYFILE
    else
        log_level -i "Wordpress app($wordPressDeploymentName) removed successfully."
        result="pass"
        printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    fi
    
    # Todo Remove files copied to master.
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME