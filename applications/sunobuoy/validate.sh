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
LOGFILENAME="$OUTPUTFOLDER/validate.log"
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
    
    
    i=0
    while [ $i -lt 10 ];do
        sonobuoyPod=$(ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "sudo kubectl get pods --all-namespaces | grep 'sonobuoy' | grep 'Running' || true")
        if [ -z "$sonobuoyPod" ]; then
            log_level -w "Sonobuoy deployment failed or sonobuoy pod is not running."
            sleep 30s
        else
            break
        fi
        
        let i=i+1
    done
    
    if [ -z "$sonobuoyPod" ]; then
        log_level -e "Sonobuoy deployment failed or sonobuoy pod is not running."
        exit 1
    else
        log_level -i "Sonobuoy deployment went through fine and it is running."
    fi
    
    while true
    do
        runStatus=$(ssh -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "./sonobuoy status | grep running || true")
        log_level -i "Status $runStatus"
        if [ -z "$runStatus" ]; then
            break
        else
            sleep 30
        fi
    done
    
    log_level -i "------------------------------------------------------------------------"
    ssh -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "./sonobuoy retrieve;"
    
    tarfile=$(ssh -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP 'ls | grep _sonobuoy_ | sort -r | head -1')

    if [ -z "$tarfile" ]; then
        log_level -e "Sonobuoy retrieve failed. No tar file got created"
        exit 1
    else
        log_level -i "Retriving run details from file ($tarfile)."
    fi

    resultfolder="${tarfile%.*.*}"
    
    log_level -i "Copy tar file($tarfile) locally to $OUTPUTFOLDER"
    scp -r -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP:/home/$AZUREUSER/$tarfile $OUTPUTFOLDER
    
    ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "mkdir $resultfolder"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "sudo tar -xvf $tarfile -C ~/$resultfolder"
    
    log_level -i "Copy junit file(junit_01.xml) locally to $OUTPUTFOLDER"
    scp -r -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP:/home/$AZUREUSER/$resultfolder/plugins/e2e/results/junit_01.xml $OUTPUTFOLDER
    
    # Todo Add a check by query to Kube cluster that app validate went through fine.
    
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_FILE
    
    # Create result file, even if script ends with an error
    trap final_changes EXIT
} 2>&1 | tee $LOGFILENAME