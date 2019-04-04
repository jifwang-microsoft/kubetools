#Connects to Kubernetes cluster Deploys SQL Aris, Runs tests and collects logs.

#! /bin/bash

set -e

log_level()
{
    echo "#####################################################################################"
    case "$1" in
        -e) echo "$(date) [Error]  : " ${@:2}
        ;;
        -w) echo "$(date) [Warning]: " ${@:2}
        ;;
        -i) echo "$(date) [Info]   : " ${@:2}
        ;;
        *)  echo "$(date) [Verbose]: " ${@:2}
        ;;
    esac
    echo "#####################################################################################"
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
    echo "            -f, --parameterFile                         Parameter file for any extra parameters for the deployment"
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
        -f|--parameterFile)
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

OUTPUTFOLDER=$(dirname $OUTPUT_SUMMARYFILE)
LOGFILENAME=$OUTPUTFOLDER/parse.log
{
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
    GITURL=`cat $PARAMETERFILE | jq -r '.gitUrl'`
    TEST_DIRECTORY=`cat $PARAMETERFILE | jq -r '.dvmAssetsFolder'`
    PARSE_DVM_LOG_FILE=`cat $PARAMETERFILE | jq -r '.parseDVMLogFile'`
    JUNIT_FOLDER_LOCATION=`cat $PARAMETERFILE | jq -r '.junitFileLocation'`
    
    echo "TEST_DIRECTORY: $TEST_DIRECTORY"
    echo "PARSE_DVM_LOG_FILE: $PARSE_DVM_LOG_FILE"
    echo "JUNIT_FOLDER_LOCATION: $JUNIT_FOLDER_LOCATION"
    
    cd -
    
    IDENTITYFILEBACKUPPATH="/home/$AZUREUSER/IDENTITYFILEBACKUP"
    
    log_level -i "Run Parse Test Script"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "cd $TEST_DIRECTORY; chmod +x ./parse_test.sh; ./parse_test.sh -t $TEST_DIRECTORY -o $JUNIT_FOLDER_LOCATION 2>&1 | tee $PARSE_DVM_LOG_FILE;"
    
    log_level -i "Copying over parsed logs"
    scp -i $IDENTITYFILE $AZUREUSER@$HOST:/home/$AZUREUSER/$TEST_DIRECTORY/$PARSE_DVM_LOG_FILE $OUTPUTFOLDER
    
    log_level -i "Copying over test results"
    scp -r -i $IDENTITYFILE $AZUREUSER@$HOST:/home/$AZUREUSER/$TEST_DIRECTORY/$JUNIT_FOLDER_LOCATION $OUTPUTFOLDER
    
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    
} 2>&1 | tee $LOGFILENAME
