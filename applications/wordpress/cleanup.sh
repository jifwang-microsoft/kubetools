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
    if [ ! -f "$OUTPUT_FILE" ]; then
        printf '{"result":"%s"}\n' "fail" > $OUTPUT_FILE
    fi
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
        ;;
        -m|--master)
            MASTERVMIP="$2"
        ;;
        -u|--user)
            AZUREUSER="$2"
        ;;
        -c|--configFile)
            PARAMETERFILE="$2"
        ;;
        -o|--output-file)
            OUTPUT_FILE="$2"
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

OUTPUTFOLDER="$(dirname $OUTPUT_FILE)"
LOGFILENAME="$OUTPUTFOLDER/cleanup.log"
touch $LOGFILENAME

{
    log_level -i "------------------------------------------------------------------------"
    log_level -i "Input Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "Identity-file   : $IDENTITYFILE"
    log_level -i "Master IP       : $MASTERVMIP"
    log_level -i "OUTPUT_FILE     : $OUTPUT_FILE"
    log_level -i "User            : $AZUREUSER"
    log_level -i "------------------------------------------------------------------------"
    
    # Cleanup Word press app.
    wpRelease=$(ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "helm ls -d -r | grep 'DEPLOYED\(.*\)wordpress' | grep -Eo '^[a-z,-]+' || true")
    if [ -z "$wpRelease" ]; then
        log_level -w "Helm deployment not found."
    else
        log_level -i "Removing helm deployment($wpRelease)"
        ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "helm delete --purge $wpRelease"
        log_level -i "Wait for 30s for all pods to be deleted and removed."
        sleep 30s
    fi
    
    ssh -t -i $IDENTITYFILE \
    $AZUREUSER@$MASTERVMIP \
    "sudo rm -f -r var_log var_log.tar.gz || true"

    ssh -t -i $IDENTITYFILE \
    $AZUREUSER@$MASTERVMIP \
    "mkdir -p var_log"

    ssh -t -i $IDENTITYFILE \
    $AZUREUSER@$MASTERVMIP \
    "sudo cp -R /var/log /home/$AZUREUSER/var_log;"

    ssh -t -i $IDENTITYFILE \
    $AZUREUSER@$MASTERVMIP \
    "sudo tar -zcvf var_log.tar.gz var_log;"
    
    log_level -i "Copy log file(var_log.tar.gz) to $OUTPUTFOLDER"
    scp -r -i $IDENTITYFILE \
    $AZUREUSER@$MASTERVMIP:/home/$AZUREUSER/var_log.tar.gz $OUTPUTFOLDER
    log_level -i "Logs are copied into $OUTPUTFOLDER"
    
    wpRelease=$(ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "helm ls -d -r | grep 'DEPLOYED\(.*\)wordpress' | grep -Eo '^[a-z,-]+' || true")
    if [ ! -z "$wpRelease" ]; then
        log_level -e "Removal of wordpress app failed($wpRelease)."
        exit 1
    else
        log_level -i "Wordpress app removed successfully."
    fi
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_FILE
    
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOGFILENAME