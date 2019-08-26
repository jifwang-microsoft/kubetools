#!/bin/bash -e


deploy_and_validate()
{
    local git_repository=$1
    local git_branch=$2
    local deployment_config_path=$3
    local script_directory=$4
    local deployment_file_name=$5
    local deployment_event_name=$6
    local deployment_kind=$7
    local deployment_name=$8
    local common_script_file_name=$9
    local test_directory=${10}

    download_file_locally $git_repository $git_branch \
    $deployment_config_path \
    $script_directory \
    $deployment_file_name
    
    log_level -i "Copy file($deployment_file_name) to VM."
    scp -i $IDENTITY_FILE \
    $script_directory/$deployment_file_name \
    $USER_NAME@$MASTER_IP:$test_directory/
    
    replicaCount=$(cat $script_directory/$deployment_file_name | grep replicas | cut -d':' -f2 | xargs |  cut -d' ' -f1)

    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP \
    "cd $test_directory; source $common_script_file_name; deploy_application $deployment_file_name $deployment_event_name $deployment_name $deployment_kind $replicaCount"
}

FILE_NAME=$0

SCRIPT_DIRECTORY="$(dirname $FILE_NAME)"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"
COMMON_SCRIPT_FILENAME="common.sh"

# Download common script file.
curl -o $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME \
https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/common/$COMMON_SCRIPT_FILENAME
if [ ! -f $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME ]; then
    log_level -e "File($COMMON_SCRIPT_FILENAME) failed to download."
    exit 1
fi

source $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME
###########################################################################################################
# The function will read parameters and populate below global variables.
# IDENTITY_FILE, MASTER_IP, OUTPUT_SUMMARYFILE, USER_NAME
parse_commandline_arguments $@

log_level -i "------------------------------------------------------------------------"
log_level -i "                Input Parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "IDENTITY_FILE       : $IDENTITY_FILE"
log_level -i "MASTER_IP           : $MASTER_IP"
log_level -i "OUTPUT_SUMMARYFILE  : $OUTPUT_SUMMARYFILE"
log_level -i "USER_NAME           : $USER_NAME"
log_level -i "------------------------------------------------------------------------"

if [[ -z "$IDENTITY_FILE" ]] || \
[[ -z "$MASTER_IP" ]] || \
[[ -z "$USER_NAME" ]] || \
[[ -z "$OUTPUT_SUMMARYFILE" ]]; then
    log_level -e "One of the mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi

###########################################################################################################
# Define all inner varaibles.
OUTPUT_DIRECTORY="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_DIRECTORY/deploy.log"
touch $LOG_FILENAME

{
    # Details.
    APPLICATION_NAME="aspnet"
    START_CONTAINR_EVENT="Started"
    DEPLOYMENT_EVENT_NAME="ScalingReplicaSet"
    DEPLOYMENT_KIND="Deployment"
    DEPLOYMENT_ASPNET_FILE="aspnet.yaml"
    DEPLOYMENT_PVC_FILE="aspnet_pvc.yaml"

    ASPNET_PVC_LABEL="aspnetpvc"
    ASPNET_SERVICE_LABEL="aspnetapp"
    

    DEPLOYMENT_CONFIG_PATH="applications/common/deploymentConfig/windows"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    POD_KIND="Pod"
    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME               : $APPLICATION_NAME"    
    log_level -i "ASPNET_PVC_LABEL               : $ASPNET_PVC_LABEL"
    log_level -i "ASPNET_SERVICE_LABEL           : $ASPNET_SERVICE_LABEL"
    log_level -i "DEPLOYMENT_ASPNET_FILE         : $DEPLOYMENT_ASPNET_FILE"
    log_level -i "DEPLOYMENT_CONFIG_PATH         : $DEPLOYMENT_CONFIG_PATH"
    log_level -i "DEPLOYMENT_EVENT_NAME          : $DEPLOYMENT_EVENT_NAME"
    log_level -i "DEPLOYMENT_KIND                : $DEPLOYMENT_KIND"
    log_level -i "DEPLOYMENT_PVC_FILE            : $DEPLOYMENT_PVC_FILE"
    log_level -i "GIT_BRANCH                     : $GIT_BRANCH"
    log_level -i "GIT_REPROSITORY                : $GIT_REPROSITORY"    
    log_level -i "START_CONTAINR_EVENT           : $START_CONTAINR_EVENT"
    log_level -i "TEST_DIRECTORY                 : $TEST_DIRECTORY"
    log_level -i "POD_KIND                       : $POD_KIND"
    log_level -i "------------------------------------------------------------------------"
    
    # ----------------------------------------------------------------------------------------
    # Copy all files inside master VM for execution.
    log_level -i "Create test directory($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"
    
    log_level -i "Copy file($COMMON_SCRIPT_FILENAME) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/
    

    deploy_and_validate $GIT_REPROSITORY $GIT_BRANCH \
    $DEPLOYMENT_CONFIG_PATH \
    $SCRIPT_DIRECTORY \
    $DEPLOYMENT_ASPNET_FILE \
    $DEPLOYMENT_EVENT_NAME \
    $DEPLOYMENT_KIND \
    $ASPNET_SERVICE_LABEL \
    $COMMON_SCRIPT_FILENAME \
    $TEST_DIRECTORY


    deploy_and_validate $GIT_REPROSITORY $GIT_BRANCH \
    $DEPLOYMENT_CONFIG_PATH \
    $SCRIPT_DIRECTORY \
    $DEPLOYMENT_PVC_FILE \
    $START_CONTAINR_EVENT \
    $POD_KIND \
    $ASPNET_PVC_LABEL \
    $COMMON_SCRIPT_FILENAME \
    $TEST_DIRECTORY

    log_level -i "aspnet deployment done."
    printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
} 2>&1 | tee $LOG_FILENAME