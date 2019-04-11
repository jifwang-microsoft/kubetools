#!/bin/bash

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
            IDENTITY_FILE="$2"
        ;;
        -m|--master)
            HOST="$2"
        ;;
        -u|--user)
            AZURE_USER="$2"
        ;;
        -o|--output-file)
            OUTPUT_SUMMARY_FILE="$2"
        ;;
        -c|--configfile)
            PARAMETER_FILE="$2"
        ;;
        *)
            log_level -i ""
            log_level -i "Incorrect parameter $1"
            log_level -i ""
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

OUTPUT_FOLDER=$(dirname $OUTPUT_SUMMARY_FILE)
LOG_FILE_NAME=$OUTPUT_FOLDER/clean.log
touch $LOG_FILE_NAME

{
    log_level -i "Checking script parameters"
    
    if [ ! -f $PARAMETER_FILE ] || [ -z "$PARAMETER_FILE" ]; then
        log_level -e "Parameter file does not exist"
        exit 1
    fi
    if [ ! -f $IDENTITY_FILE ] || [ -z "$IDENTITY_FILE" ];
    then
        log_level -e "Identity file does not exist"
        exit 1
    fi
    
    if [ -z "$HOST" ];
    then
        log_level -e "Host IP is not set"
        exit 1
    fi
    
    if [ -z "$AZURE_USER" ];
    then
        log_level -e "Host Username is not set"
        exit 1
    fi
    
    log_level -i "Parameters passed"
    
    GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
    GIT_BRANCH="${GIT_BRANCH:-master}"
    CLEAN_SCRIPT="clean_test.sh"
    
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "Script Parameters"
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "GIT_REPROSITORY: $GIT_REPROSITORY"
    log_level -i "GIT_BRANCH: $GIT_BRANCH"
    log_level -i "HOST: $HOST"
    log_level -i "IDENTITY_FILE: $IDENTITY_FILE"
    log_level -i "OUTPUT_FOLDER: $OUTPUT_FOLDER"
    log_level -i "PARAMETER_FILE: $PARAMETER_FILE"
    log_level -i "CLEAN_SCRIPT: $CLEAN_SCRIPT"
    log_level -i "USER: $AZURE_USER"
    log_level -i "-----------------------------------------------------------------------------"
    
    #Read parameters from json files
    log_level -i "Reading Parameters from Json"
    TEST_DIRECTORY=`cat "$PARAMETER_FILE" | jq -r '.dvmAssetsFolder'`
    CLEAN_DVM_LOG_FILE=`cat "$PARAMETER_FILE" | jq -r '.cleanDVMLogFile'`
    
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "Config Parameters"
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
    log_level -i "CLEAN_DVM_LOG_FILE: $CLEAN_DVM_LOG_FILE"
    log_level -i "-----------------------------------------------------------------------------"
    
    curl -o $OUTPUT_FOLDER/$CLEAN_SCRIPT \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/sqlaris/$CLEAN_SCRIPT
    if [ ! -f $OUTPUT_FOLDER/$CLEAN_SCRIPT ]; then
        log_level -e "File($CLEAN_SCRIPT) failed to download."
        exit 1
    fi
    
    log_level -i "Copy script($CLEAN_SCRIPT) to test folder($TEST_DIRECTORY)"
    scp -i $IDENTITY_FILE $OUTPUT_FOLDER/$CLEAN_SCRIPT $AZURE_USER@$HOST:/home/$AZURE_USER/$TEST_DIRECTORY
    
    log_level -i "Change file($CLEAN_SCRIPT) to unix format"
    ssh -t -i $IDENTITY_FILE $AZURE_USER@$HOST "dos2unix $TEST_DIRECTORY/$CLEAN_SCRIPT;"
    
    log_level -i "Running clean test script ($CLEAN_SCRIPT)"
    ssh -t -i $IDENTITY_FILE $AZURE_USER@$HOST "cd $TEST_DIRECTORY; chmod +x ./$CLEAN_SCRIPT; ./$CLEAN_SCRIPT -t $TEST_DIRECTORY 2>&1 | tee $CLEAN_DVM_LOG_FILE;"
    
    log_level -i "Copying over deployment logs locally"
    scp -i $IDENTITY_FILE $AZURE_USER@$HOST:/home/$AZURE_USER/$TEST_DIRECTORY/$CLEAN_DVM_LOG_FILE $OUTPUT_FOLDER
    
    log_level -i "Removing test folder($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $AZURE_USER@$HOST "sudo rm -rf $TEST_DIRECTORY;"
    
    #Checking status of the deployment
    CLEAN_STATUS=`awk '/./{line=$0} END{print line}' $OUTPUT_FOLDER/$CLEAN_DVM_LOG_FILE`
    
    if [ "$CLEAN_STATUS" == "0" ];
    then
        result="pass"
        printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARY_FILE
    else
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "$CLEAN_STATUS" > $OUTPUT_SUMMARY_FILE
    fi
    
} 2>&1 | tee $LOG_FILE_NAME

