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

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/cleanup.log"
touch $LOG_FILENAME

{
    log_level -i "------------------------------------------------------------------------"
    log_level -i "Input Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "IDENTITY_FILE         : $IDENTITY_FILE"
    log_level -i "MASTER_IP             : $MASTER_IP"
    log_level -i "OUTPUT_SUMMARYFILE    : $OUTPUT_SUMMARYFILE"
    log_level -i "USER_NAME             : $USER_NAME"
    log_level -i "------------------------------------------------------------------------"
    
    log_level -i "Deleting Namespace for sonobuoy..."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "./sonobuoy delete;"
    log_level -i "------------------------------------------------------------------------"
    
    i=0
    while [ $i -lt 10 ];do
        sonobuoyPod=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pods --all-namespaces | grep 'sonobuoy' || true")
        if [ ! -z "$sonobuoyPod" ]; then
            log_level -i "Sonobuoy pods are still up and running($sonobuoyPod)."
            sleep 30s
        else
            break
        fi
        
        let i=i+1
    done
    
    if [ ! -z "$sonobuoyPod" ]; then
        log_level -e "Sonobuoy pods($sonobuoyPod) are still up and running. Cleanup failed."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Sonobuoy pods($sonobuoyPod) are still up and running. Cleanup failed." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Sonobuoy app cleanup done."
    fi
    
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    
    # Todo Remove files copied to master.
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME