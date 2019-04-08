#Connects to Kubernetes cluster Deploys SQL Aris, Runs tests and collects logs.

#! /bin/bash

set -e

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

function printUsage
{
    echo "      Usage:"
    echo "      $FILENAME --identity-file id_rsa --master 192.168.102.34 --user azureuser"
    echo  ""
    echo "            -i, --identity-file                         RSA Private Key file to connect kubernetes master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -m, --master                                Public ip of Kubernetes cluster master VM. Normally VM name starts with k8s-master- "
    echo "            -u, --user                                  User Name of Kubernetes cluster master VM "
    echo "            -o, --output-file                           Summary file providing result status of the deployment."
    echo "            -c, --configFile                            Parameter file for any extra parameters for the deployment"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
        ;;
        -m|--master)
            HOST="$2"
        ;;
        -u|--user)
            AZUREUSER="$2"
        ;;
        -o|--output-file)
            OUTPUT_SUMMARYFILE="$2"
        ;;
        -c|--configfile)
            PARAMETERFILE="$2"
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

{
    log_level -i "Checking script parameters"
    
    if [ ! -f $PARAMETERFILE ] || [ -z "$PARAMETERFILE" ]; then
        log_level -e "Parameter file does not exist"
        exit 1
    fi
    
    if [ ! -f $OUTPUT_SUMMARYFILE ] || [ -z "$OUTPUT_SUMMARYFILE" ]; then
        log_level -e "Output does not exist"
        exit 1
    fi
    
    if [ ! -f $IDENTITYFILE ] || [ -z "$IDENTITYFILE" ];
    then
        log_level -e "Identity file does not exist"
        exit 1
    fi
    
    if [ -z "$HOST" ];
    then
        log_level -e "Host IP is not set"
        exit 1
    fi
    
    if [ -z "$AZUREUSER" ];
    then
        log_level -e "Host Username is not set"
        exit 1
    fi
    
    log_level -i "Parameters passed"
    
    
    OUTPUTFOLDER=$(dirname $OUTPUT_SUMMARYFILE)
    LOGFILENAME=$OUTPUTFOLDER/clean.log
    
    echo "identity-file: $IDENTITYFILE"
    echo "host: $HOST"
    echo "user: $AZUREUSER"
    echo "FolderName: $OUTPUTFOLDER"
    echo "ParameterFile: $PARAMETERFILE"
    
    #Download assets to a location
    log_level -i "Downloading Assets"
    cd $OUTPUTFOLDER
    
    #Read parameters from json files
    log_level -i "Reading Parameters from Json"
    TEST_DIRECTORY=`cat "$PARAMETERFILE" | jq -r '.dvmAssetsFolder'`
    CLEAN_DVM_LOG_FILE=`cat "$PARAMETERFILE" | jq -r '.cleanDVMLogFile'`
    
    echo "TEST_DIRECTORY: $TEST_DIRECTORY"
    echo "CLEAN_DVM_LOG_FILE: $CLEAN_DVM_LOG_FILE"
    echo "JUNIT_FOLDER_LOCATION: $JUNIT_FOLDER_LOCATION"
    
    cd -
    
    IDENTITYFILEBACKUPPATH="/home/$AZUREUSER/IDENTITYFILEBACKUP"
    
    log_level -i "Run Clean Test Script"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/.ssh/id_rsa ]; then cd $TEST_DIRECTORY; chmod +x ./clean_test.sh; ./clean_test.sh -t $TEST_DIRECTORY 2>&1 | tee $CLEAN_DVM_LOG_FILE; fi;"
    
    log_level -i "Copying over clean logs"
    scp -i $IDENTITYFILE $AZUREUSER@$HOST:/home/$AZUREUSER/$TEST_DIRECTORY/$CLEAN_DVM_LOG_FILE $LOCAL_DIRECTORY
    
    log_level -i "Remove test Folder"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "if [ -f /home/$AZUREUSER/.ssh/id_rsa ]; then sudo rm -rf $TEST_DIRECTORY;fi;"
    
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    
} 2>&1 | tee $LOGFILENAME

