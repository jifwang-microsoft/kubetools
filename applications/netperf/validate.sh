#!/bin/bash -e

FILE_NAME=$0

SCRIPT_DIRECTORY="$(dirname $FILE_NAME)"
COMMON_SCRIPT_FILENAME="common.sh"

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
LOG_FILENAME="$OUTPUT_DIRECTORY/validate.log"
touch $LOG_FILENAME

{
    APPLICATION_NAME="netperf"
    EXPECTED_RESULT_FILE="expectedresults.json"
    GO_DIRECTORY="/home/$USER_NAME/go"
    GO_SRC_DIRECTORY="$GO_DIRECTORY/src/k8s.io/"
    NETPERF_DIRECTORY="$GO_SRC_DIRECTORY/perf-tests/network/benchmarks/netperf"    
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    RESULTS_FILENAME="results.json"    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "EXPECTED_RESULT_FILE       : $EXPECTED_RESULT_FILE"
    log_level -i "JQ_INSTALL_LINK            : $JQ_INSTALL_LINK"    
    log_level -i "GO_DIRECTORY               : $GO_DIRECTORY"
    log_level -i "GO_SRC_DIRECTORY           : $GO_SRC_DIRECTORY"
    log_level -i "NETPERF_DIRECTORY          : $NETPERF_DIRECTORY"
    log_level -i "RESULTS_FILENAME           : $RESULTS_FILENAME"    
    log_level -i "TEST_DIRECTORY             : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"

    # ----------------------------------------------------------------------------------------
    log_level -i "Launch netperf run."
    TIMEOUT=108000
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_DIRECTORY; timeout $TIMEOUT $NETPERF_DIRECTORY/launch -hostnetworking -kubeConfig /home/$USER_NAME/.kube/config -iterations 3"

    log_level -i "Copy results file."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $NETPERF_DIRECTORY; cp results_netperf-latest/* $TEST_DIRECTORY/ "

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
        log_level -i "Copy csv files locally to $OUTPUT_DIRECTORY "
        scp -r -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/*.csv $OUTPUT_DIRECTORY
        log_level -i "Parse files and validate if expected results."
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; perf_process_net_files $TEST_DIRECTORY $RESULTS_FILENAME ;"
        scp -r -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/$RESULTS_FILENAME $OUTPUT_DIRECTORY
        RESULTS_FILE=$OUTPUT_DIRECTORY/$RESULTS_FILENAME
        if [ ! -f $RESULTS_FILE ]; then
            log_level -e "File($RESULTS_FILE) failed to copy."
            exit 1
        fi

        MINVALUE_RESULT_FILE=$SCRIPT_DIRECTORY/$EXPECTED_RESULT_FILE

        log_level -i "Validate results with minimum expected results."
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
            log_level -i "All test cases passes."
            printf '{"result":"%s","error":"%s"}\n' "pass" "" > $OUTPUT_SUMMARYFILE
        else
            log_level -e "Some test cases failed. Please refer logs for more details."
            printf '{"result":"%s","error":"%s"}\n' "failed" "$FAILED_CASES" > $OUTPUT_SUMMARYFILE
        fi
    fi

} 2>&1 | tee $LOG_FILENAME