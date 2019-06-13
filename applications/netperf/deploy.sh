#!/bin/bash -e

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

    # Github details.
    APPLICATION_NAME="netperf"
    INSTALL_PREREQUISITE_FILE="install_prerequisite.sh"    
    EXPECTED_RESULT_FILE="expectedresults.json"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    GO_DIRECTORY="/home/$USER_NAME/go"
    GO_SRC_DIRECTORY="$GO_DIRECTORY/src/k8s.io/"
    NETPERF_DIRECTORY="$GO_SRC_DIRECTORY/perf-tests/network/benchmarks/netperf"
    GIT_PERF_CODE="https://github.com/kubernetes/perf-tests.git"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "EXPECTED_RESULT_FILE       : $EXPECTED_RESULT_FILE"
    log_level -i "GIT_BRANCH                 : $GIT_BRANCH"
    log_level -i "GIT_PERF_CODE              : $GIT_PERF_CODE"    
    log_level -i "GIT_REPROSITORY            : $GIT_REPROSITORY"
    log_level -i "GO_DIRECTORY               : $GO_DIRECTORY"
    log_level -i "GO_SRC_DIRECTORY           : $GO_SRC_DIRECTORY"
    log_level -i "INSTALL_PREREQUISITE_FILE  : $INSTALL_PREREQUISITE_FILE"
    log_level -i "NETPERF_DIRECTORY          : $NETPERF_DIRECTORY"
    log_level -i "TEST_DIRECTORY             : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"    

    # ----------------------------------------------------------------------------------------
    # INSTALL PREREQUISITE

    apt_install_jq
        
    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/$APPLICATION_NAME" \
    $SCRIPT_DIRECTORY \
    $EXPECTED_RESULT_FILE

    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/common" \
    $SCRIPT_DIRECTORY \
    $INSTALL_PREREQUISITE_FILE
    
    if [[ $? != 0 ]]; then
        log_level -e "Download of file($INSTALL_PREREQUISITE_FILE) failed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Download of file($INSTALL_PREREQUISITE_FILE) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    # ----------------------------------------------------------------------------------------
    # Copy all files inside master VM for execution.
    log_level -i "Create test DIRECTORY($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"
    log_level -i "Copy file($INSTALL_PREREQUISITE_FILE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$INSTALL_PREREQUISITE_FILE \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    # ----------------------------------------------------------------------------------------
    # Launch prequisite files to install required components.
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_DIRECTORY/$COMMON_SCRIPT_FILENAME; "
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_DIRECTORY/$INSTALL_PREREQUISITE_FILE; "
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $INSTALL_PREREQUISITE_FILE; apt_install_important_packages ;"
    sleep 30s
    # This is needed as latest version of go lang gets install in second pass.
    # Todo need to debug and resolve why
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $INSTALL_PREREQUISITE_FILE; apt_install_important_packages ;"
    goPath=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "go env | grep GOPATH || true")
    if [ -z "$goPath" ]; then
        log_level -e "GO is not installed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Go is not installed." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Go installed with GOPATH($goPath)"
    fi
    
    # ----------------------------------------------------------------------------------------
    log_level -i "Create go DIRECTORY($GO_SRC_DIRECTORY)"
    goDIRECTORY=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "ls | grep go || true")
    log_level -i "GO DIRECTORY status : $goDIRECTORY"
    if [ -z "$goDIRECTORY" ]; then

        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $GO_SRC_DIRECTORY"
        log_level -i "Install godep tool "
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "export GOPATH=$GO_DIRECTORY; go get github.com/tools/godep"

        log_level -i "Clone $APPLICATION_NAME repository "
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $GO_SRC_DIRECTORY; git clone $GIT_PERF_CODE"
    else
        log_level -i "Remove old results to temp DIRECTORY."
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_DIRECTORY; mv results_netperf-latest/ results_netperf-latest_temp/ || true"
    fi

    log_level -i "Build $APPLICATION_NAME launch binary."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_DIRECTORY; go build launch.go"
    
    log_level -i "Check if build passed."
    fileType=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_DIRECTORY; stat --format '%a' launch")
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