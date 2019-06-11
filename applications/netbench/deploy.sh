#!/bin/bash -e

FILE_NAME=$0

SCRIPT_FOLDER="$(dirname $FILE_NAME)"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"
COMMON_SCRIPT_FILENAME="common.sh"

# Download common script file.
curl -o $SCRIPT_FOLDER/$COMMON_SCRIPT_FILENAME \
https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/common/$COMMON_SCRIPT_FILENAME
if [ ! -f $SCRIPT_FOLDER/$COMMON_SCRIPT_FILENAME ]; then
    log_level -e "File($COMMON_SCRIPT_FILENAME) failed to download."
    exit 1
fi

source $SCRIPT_FOLDER/$COMMON_SCRIPT_FILENAME
###########################################################################################################
# The function will read parameters and populate below global variables.
# IDENTITY_FILE, MASTER_IP, OUTPUT_SUMMARYFILE, USER_NAME
parse_commandline_arguments $@

log_level -i "------------------------------------------------------------------------"
log_level -i "                Input Parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "IDENTITY_FILE       : $IDENTITY_FILE"
log_level -i "CONFIG_FILE         : $CONFIG_FILE"
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
OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/deploy.log"
touch $LOG_FILENAME

{

    # Github details.
    APPLICATION_NAME="netperf"
    INSTALL_PREREQUISITE_FILE="install_prerequisite.sh"    
    
    TEST_FOLDER="/home/$USER_NAME/$APPLICATION_NAME"
    GO_FOLDER="/home/$USER_NAME/go"
    GO_SRC_FOLDER="$GO_FOLDER/src/k8s.io/"
    NETPERF_FOLDER="$GO_SRC_FOLDER/perf-tests/network/benchmarks/netperf"
    GIT_PERF_CODE="https://github.com/kubernetes/perf-tests.git"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "GIT_BRANCH                 : $GIT_BRANCH"
    log_level -i "GIT_PERF_CODE              : $GIT_PERF_CODE"    
    log_level -i "GIT_REPROSITORY            : $GIT_REPROSITORY"
    log_level -i "GO_FOLDER                  : $GO_FOLDER"
    log_level -i "GO_SRC_FOLDER              : $GO_SRC_FOLDER"
    log_level -i "INSTALL_PREREQUISITE_FILE  : $INSTALL_PREREQUISITE_FILE"
    log_level -i "NETPERF_FOLDER             : $NETPERF_FOLDER"
    log_level -i "TEST_FOLDER                : $TEST_FOLDER"
    log_level -i "------------------------------------------------------------------------"    

    # ----------------------------------------------------------------------------------------
    # INSTALL PREREQUISITE

    curl -o $SCRIPT_FOLDER/$INSTALL_PREREQUISITE_FILE \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/common/$INSTALL_PREREQUISITE_FILE
    if [ ! -f $SCRIPT_FOLDER/$INSTALL_PREREQUISITE_FILE ]; then
        log_level -e "File($INSTALL_PREREQUISITE_FILE) failed to download."
        printf '{"result":"%s","error":"%s"}\n' "failed" "File($INSTALL_PREREQUISITE_FILE) failed to download." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Create test folder($TEST_FOLDER)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_FOLDER"
    log_level -i "Copy file($INSTALL_PREREQUISITE_FILE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_FOLDER/$INSTALL_PREREQUISITE_FILE \
    $USER_NAME@$MASTER_IP:$TEST_FOLDER/
    scp -i $IDENTITY_FILE \
    $SCRIPT_FOLDER/$COMMON_SCRIPT_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_FOLDER/

    
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_FOLDER/$INSTALL_PREREQUISITE_FILE; "
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_FOLDER/$COMMON_SCRIPT_FILENAME; "
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_FOLDER; ./$INSTALL_PREREQUISITE_FILE;"
    goPath=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "go env | grep GOPATH || true")
    if [ -z "$goPath" ]; then
        log_level -e "GO is not installed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Go is not installed." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Go installed with GOPATH($goPath)"
    fi
    # ----------------------------------------------------------------------------------------
    log_level -i "Create go folder($GO_SRC_FOLDER)"
    goFolder=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "ls | grep go || true")
    log_level -i "GO folder status : $goFolder"
    if [ -z "$goFolder" ]; then

        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $GO_SRC_FOLDER"

        log_level -i "Install godep tool "
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "export GOPATH=$GO_FOLDER; go get github.com/tools/godep"

        log_level -i "Clone $APPLICATION_NAME repository "
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $GO_SRC_FOLDER; git clone $GIT_PERF_CODE"
    else
        log_level -i "Remove old results to temp folder."
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_FOLDER; mv results_netperf-latest/ results_netperf-latest_temp/ || true"
    fi

    log_level -i "Build $APPLICATION_NAME launch binary."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_FOLDER; go build launch.go"
    
    log_level -i "Check if build passed."
    fileType=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_FOLDER; stat --format '%a' launch")
    log_level -i "FileType value of launch is $fileType."

    if [[ $fileType != "775" ]]; then
        log_level -e "No $APPLICATION_NAME file got build. $APPLICATION_NAME build failed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "No $APPLICATION_NAME file got build. $APPLICATION_NAME build failed." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Result passed."
        printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
    fi
} 2>&1 | tee $LOG_FILENAME