#!/bin/bash

# This script connects to the dvm on a kubernetes cluster and deploys SQL aris to the cluster from source code.
# It does using the following steps
# - Read configuration file and parse the parameters
# - sample file contents
#     {
#     "gitUrl":  "git url with login credentials to sqlaris repo",
#     "deployDVMLogFile":  "name of logfile in dvm for deployment",
#     "parseDVMLogFile":  "name of logfile in dvm for deployment parsing",
#     "cleanDVMLogFile":  "name of logfile in dvm for deployment clean up",
#     "dvmAssetsFolder":  "name of test assets folder",
#     "junitFileLocation":  "name of test result location"
#     }

# - Download deployment scripts to a specified location specified with -o parameter
# Copy over the required scripts to test artifact location (dvmAssetsFolder)
# Change script format to unix fromat
# run script on dvm passing in the required parameters
# Deploy script parameters
# -u the github token
# -t test directory



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
            OUTPUT_SUMMARYFILE="$2"
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

OUTPUT_FOLDER=$(dirname $OUTPUT_SUMMARYFILE)
LOG_FILE_NAME=$OUTPUT_FOLDER/deploy.log
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
    
    # Github details.
    GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
    GIT_BRANCH="${GIT_BRANCH:-master}"
    DEPLOYMENT_SCRIPT="deploy_test.sh"
    
    #use capitals and sort
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "Script Parameters"
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "DEPLOYMENT_SCRIPT: $DEPLOYMENT_SCRIPT"
    log_level -i "GIT_REPROSITORY: $GIT_REPROSITORY"
    log_level -i "GIT_BRANCH: $GIT_BRANCH"
    log_level -i "HOST: $HOST"
    log_level -i "IDENTITY_FILE: $IDENTITY_FILE"
    log_level -i "OUTPUT_FOLDER: $OUTPUT_FOLDER"
    log_level -i "PARAMETER_FILE: $PARAMETER_FILE"
    log_level -i "USER: $AZURE_USER"
    log_level -i "-----------------------------------------------------------------------------"
    
    #Install jq
    #make jq version a variable
    log_level -i "Install jq"
    curl -O -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe
    if [ ! -f jq-win64.exe ]; then
        log_level -e "File(jq-win64.exe) failed to download."
        exit 1
    fi
    mv jq-win64.exe /usr/bin/jq
    
    
    log_level -i "Reading parameters from json($PARAMETER_FILE)"
    GITURL=`cat "$PARAMETER_FILE" | jq -r '.gitUrl'`
    
    if [[ $GITURL == "https://"* ]]; then
        log_level -i "Giturl is valid"
    else
        log_level -e "Giturl is not valid"
        exit 1
    fi
    
    TEST_DIRECTORY=`cat "$PARAMETER_FILE" | jq -r '.dvmAssetsFolder'`
    DEPLOY_DVM_LOG_FILE=`cat "$PARAMETER_FILE" | jq -r '.deployDVMLogFile'`
    IDENTITY_FILE_BACKUP_PATH="/home/$AZURE_USER/IDENTITY_FILEBACKUP"
    
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "Config Parameters"
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
    log_level -i "DEPLOY_DVM_LOG_FILE: $DEPLOY_DVM_LOG_FILE"
    log_level -i "IDENTITY_FILE_BACKUP_PATH: $IDENTITY_FILE_BACKUP_PATH"
    log_level -i "-----------------------------------------------------------------------------"
    
    curl -o $OUTPUT_FOLDER/$DEPLOYMENT_SCRIPT \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/sqlaris/$DEPLOYMENT_SCRIPT
    if [ ! -f $OUTPUT_FOLDER/$DEPLOYMENT_SCRIPT ]; then
        log_level -e "File($DEPLOYMENT_SCRIPT) failed to download."
        exit 1
    fi
    
    #Read parameters from json files
    log_level -i "Converting parameters file($PARAMETER_FILE) to unix format"
    dos2unix $PARAMETER_FILE
    
    log_level -i "Backing up identity files at ($IDENTITY_FILE_BACKUP_PATH)"
    ssh -t -i $IDENTITY_FILE $AZURE_USER@$HOST "if [ -f /home/$AZURE_USER/.ssh/id_rsa ]; then mkdir -p $IDENTITY_FILE_BACKUP_PATH;  sudo mv /home/$AZURE_USER/.ssh/id_rsa $IDENTITY_FILE_BACKUP_PATH; fi;"
    
    log_level -i "Copying over new identity file"
    scp -i $IDENTITY_FILE $IDENTITY_FILE $AZURE_USER@$HOST:/home/$AZURE_USER/.ssh/id_rsa
    
    log_level -i "Create test folder($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $AZURE_USER@$HOST "mkdir $TEST_DIRECTORY"
    
    log_level -i "Copy script($DEPLOYMENT_SCRIPT) to test folder($TEST_DIRECTORY)"
    scp -i $IDENTITY_FILE $OUTPUT_FOLDER/$DEPLOYMENT_SCRIPT $AZURE_USER@$HOST:/home/$AZURE_USER/$TEST_DIRECTORY
    
    log_level -i "Install and Modify to unix format"
    ssh -t -i $IDENTITY_FILE $AZURE_USER@$HOST "sudo apt install dos2unix; dos2unix $TEST_DIRECTORY/$DEPLOYMENT_SCRIPT;"
    
    log_level -i "Run SQL aris deployment and test"
    ssh -t -i $IDENTITY_FILE $AZURE_USER@$HOST "cd $TEST_DIRECTORY; chmod +x ./$DEPLOYMENT_SCRIPT; ./$DEPLOYMENT_SCRIPT -u $GITURL -t $TEST_DIRECTORY 2>&1 | tee $DEPLOY_DVM_LOG_FILE;"
    
    log_level -i "Copying over deployment logs locally"
    scp -i $IDENTITY_FILE $AZURE_USER@$HOST:/home/$AZURE_USER/$TEST_DIRECTORY/$DEPLOY_DVM_LOG_FILE $OUTPUT_FOLDER
    
    #Checking status of the deployment
    DEPLOYMENT_STATUS=`awk '/./{line=$0} END{print line}' $OUTPUT_FOLDER/$DEPLOY_DVM_LOG_FILE`
    
    if [ "$DEPLOYMENT_STATUS" == "0" ];
    then
        result="pass"
        printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    else
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "$DEPLOYMENT_STATUS" > $OUTPUT_SUMMARYFILE
    fi
    
} 2>&1 | tee $LOG_FILE_NAME

