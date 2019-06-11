#!/bin/bash -e




FILE_NAME=$0

SCRIPT_FOLDER="$(dirname $FILE_NAME)"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"
COMMON_SCRIPT_FILENAME="common.sh"

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
    log_level -e "One of mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi

###########################################################################################################
# Define all inner varaibles.
OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/validate.log"
touch $LOG_FILENAME

{
    APPLICATION_NAME="netperf"
    EXPECTED_RESULT_FILE="expectedresults.json"
    GO_FOLDER="/home/$USER_NAME/go"
    GO_SRC_FOLDER="$GO_FOLDER/src/k8s.io/"
    NETPERF_FOLDER="$GO_SRC_FOLDER/perf-tests/network/benchmarks/netperf"    
    TEST_FOLDER="/home/$USER_NAME/$APPLICATION_NAME"
    RESULTS_FILENAME="results.json"
    JQ_INSTALL_LINK="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "EXPECTED_RESULT_FILE       : $EXPECTED_RESULT_FILE"
    log_level -i "JQ_INSTALL_LINK            : $JQ_INSTALL_LINK"    
    log_level -i "GO_FOLDER                  : $GO_FOLDER"
    log_level -i "GO_SRC_FOLDER              : $GO_SRC_FOLDER"
    log_level -i "NETPERF_FOLDER             : $NETPERF_FOLDER"
    log_level -i "RESULTS_FILENAME           : $RESULTS_FILENAME"    
    log_level -i "TEST_FOLDER                : $TEST_FOLDER"
    log_level -i "------------------------------------------------------------------------"

    # ----------------------------------------------------------------------------------------
    log_level -i "Launch netperf run."
    TIMEOUT=108000
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_FOLDER; timeout $TIMEOUT $NETPERF_FOLDER/launch -hostnetworking -kubeConfig /home/$USER_NAME/.kube/config -iterations 3"

    log_level -i "Copy results file."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_FOLDER; cp results_netperf-latest/* $TEST_FOLDER/ "

    i=0
    while [ $i -lt 10 ];do
        netperfFile=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP 'ls -R netperf | grep netperf | sort -r | head -1')
        if [ -z "$netperfFile" ]; then
            log_level -e "No netperf results file found."
            sleep 30s
        else
            break
        fi
        let i=i+1
    done

    if [ -z "$netperfFile" ]; then
        log_level -e "No run results file found."
        printf '{"result":"%s","error":"%s"}\n' "failed" "No run results file found." > $OUTPUT_SUMMARYFILE
    else
        log_level -i "Copy csv files locally to $OUTPUT_FOLDER "
        scp -r -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:$TEST_FOLDER/*.csv $OUTPUT_FOLDER
        log_level -i "Parse files and validate if expected results."
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_FOLDER; source $COMMON_SCRIPT_FILENAME; perf_process_net_files $TEST_FOLDER $RESULTS_FILENAME ;"
        scp -r -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:$TEST_FOLDER/$RESULTS_FILENAME $OUTPUT_FOLDER
        RESULTS_FILE=$OUTPUT_FOLDER/$RESULTS_FILENAME
        if [ ! -f $RESULTS_FILE ]; then
            log_level -e "File($RESULTS_FILE) failed to copy."
            exit 1
        fi

        # Download test result file.
        MINVALUE_RESULT_FILE=$SCRIPT_FOLDER/$EXPECTED_RESULT_FILE
        curl -o $MINVALUE_RESULT_FILE \
        https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/netbench/$EXPECTED_RESULT_FILE
        if [ ! -f $MINVALUE_RESULT_FILE ]; then
            log_level -e "File($EXPECTED_RESULT_FILE) failed to download."
            exit 1
        fi

        log_level -i "Converting parameters file($MINVALUE_RESULT_FILE) to unix format"
        dos2unix $MINVALUE_RESULT_FILE
        
        apt_install_jq $JQ_INSTALL_LINK

        log_level -i "Start validating the results"
        FAILED_CASES=""
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_TCP_SameVM_Pod_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_TCP_SameVM_Virtual_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_TCP_RemoteVM_Pod_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_TCP_RemoteVM_Virtual_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_TCP_Hairpin_Pod_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_UDP_SameVM_Pod_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_UDP_SameVM_Virtual_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_UDP_RemoteVM_Pod_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Iperf_UDP_RemoteVM_Virtual_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "NetPerf_SameVM_Pod_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "NetPerf_SameVM_Virtual_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "NetPerf_RemoteVM_Pod_IP"
        validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "NetPerf_RemoteVM_Virtual_IP"

        if [ -z "$FAILED_CASES" ]; then
            log_level -i "Result file processed."
            printf '{"result":"%s","error":"%s"}\n' "pass" "" > $OUTPUT_SUMMARYFILE
        else
            log_level -e "Some test cases failed."
            printf '{"result":"%s","error":"%s"}\n' "failed" "$FAILED_CASES" > $OUTPUT_SUMMARYFILE
        fi
    fi

} 2>&1 | tee $LOG_FILENAME