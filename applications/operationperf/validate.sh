#!/bin/bash -e



e2e_perf_scenario_test()
{
    local deploymentFileName=$1;
    local kind=$2;
    local deploymentName=$3;
    local startEventName=$4;
    local endEventName=$5;    
    local resultsFileName=$6;
    local testName=$7;

    i=0
    previousName=$deploymentName
    while [ $i -lt 3 ];do
        randomName=$(cat /dev/urandom | tr -dc 'a-z' | fold -w 3 | head -n 1)
        currentName=$deploymentName$randomName
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; rename_string_infile $TEST_DIRECTORY/$deploymentFileName $previousName $currentName"

        if [[ "$kind" == "$POD_KIND" ]]; then
            ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; deploy_and_measure_event_time $deploymentFileName $startEventName $endEventName $currentName-0 $kind"
        else
            ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; deploy_and_measure_event_time $deploymentFileName $startEventName $endEventName $currentName $kind"
        fi

        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; cleanup_deployment $deploymentFileName 30"
        previousName=$currentName
        let i=i+1
    done
    currentName=$deploymentName
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; rename_string_infile $TEST_DIRECTORY/$deploymentFileName $previousName $currentName"

    log_level -i "Parse files and validate expected results."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; process_perflog_files $TEST_DIRECTORY $resultsFileName $testName $currentName;"
    scp -r -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/$resultsFileName $OUTPUT_DIRECTORY
    scp -r -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/$currentName*.log $OUTPUT_DIRECTORY
    OUTPUT_RESULTS_FILE=$OUTPUT_DIRECTORY/$resultsFileName
    if [ ! -f $OUTPUT_RESULTS_FILE ]; then
        log_level -e "File($OUTPUT_RESULTS_FILE) failed to copy."
        return 1
    fi

    return 0
}

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
    # Details.
    APPLICATION_NAME="operationperf"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    DEPLOYMENT_PVC_FILE="nginx_pvc_test.yaml"
    DEPLOYMENT_LOADBALANCER_FILE="nginx_loadbalancer.yaml"
    DEPLOYMENT_LOADBALANCER_FILE_2="nginx_loadbalancer_2.yaml"
    EXPECTED_RESULT_FILENAME="expectedresults.json"
    DISK_RESULTS_FILENAME="diskattachperfresults.json"
    SECOND_PUBLIC_IP_RESULTS_FILENAME="publicipallocationperfresults.json"
    FAIL_SCHEDULE_EVENT_NAME="FailedScheduling"
    ATTACH_VOLUME_EVENT_NAME="SuccessfulAttachVolume"
    CREATE_LOADBALANCER_EVENT_NAME="EnsuringLoadBalancer"
    END_LOADBALANCER_EVENT_NAME="EnsuredLoadBalancer"
    SERVICE_KIND="Service"
    POD_KIND="Pod"
    DISK_PERF_TEST_NAME="DISK_ATTACH_TIME"
    PUBLIC_IP_ALLOCATION_PERF_TEST_NAME="SECOND_PUBLIC_IP_ALLOCATION_TIME"
    FAILED_CASES=""
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME               : $APPLICATION_NAME"
    log_level -i "DEPLOYMENT_PVC_FILE            : $DEPLOYMENT_PVC_FILE"
    log_level -i "DEPLOYMENT_LOADBALANCER_FILE   : $DEPLOYMENT_LOADBALANCER_FILE"
    log_level -i "DEPLOYMENT_LOADBALANCER_FILE_2 : $DEPLOYMENT_LOADBALANCER_FILE_2"
    log_level -i "EXPECTED_RESULT_FILENAME       : $EXPECTED_RESULT_FILENAME"
    log_level -i "TEST_DIRECTORY                 : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"

    # ----------------------------------------------------------------------------------------
    EXPECTED_RESULT_FILE=$SCRIPT_DIRECTORY/$EXPECTED_RESULT_FILENAME
    
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_DIRECTORY/$COMMON_SCRIPT_FILENAME; "

    e2e_perf_scenario_test \
    $DEPLOYMENT_PVC_FILE \
    $POD_KIND \
    "web" \
    $FAIL_SCHEDULE_EVENT_NAME \
    $ATTACH_VOLUME_EVENT_NAME \
    $DISK_RESULTS_FILENAME \
    $DISK_PERF_TEST_NAME

    if [[ $? != 0 ]]; then
        log_level -e "Failed to run $DISK_PERF_TEST_NAME test."
    else
        DISK_RESULTS_FILE=$OUTPUT_DIRECTORY/$DISK_RESULTS_FILENAME
        validate_testcase_result $DISK_RESULTS_FILE $EXPECTED_RESULT_FILE $DISK_PERF_TEST_NAME
    fi
    # ----------------------------------------------------------------------------------------
    currentName=nginxlb
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $COMMON_SCRIPT_FILENAME; deploy_and_measure_event_time $DEPLOYMENT_LOADBALANCER_FILE $CREATE_LOADBALANCER_EVENT_NAME $SECOND_PUBLIC_IP_RESULTS_FILENAME $currentName $SERVICE_KIND"
    
    e2e_perf_scenario_test \
    $DEPLOYMENT_LOADBALANCER_FILE_2 \
    $SERVICE_KIND \
    "nginxsvc2" \
    $CREATE_LOADBALANCER_EVENT_NAME \
    $END_LOADBALANCER_EVENT_NAME \
    $SECOND_PUBLIC_IP_RESULTS_FILENAME \
    $PUBLIC_IP_ALLOCATION_PERF_TEST_NAME


    if [[ $? != 0 ]]; then
        log_level -e "Failed to run $PUBLIC_IP_ALLOCATION_PERF_TEST_NAME test."
    else
        SECOND_PUBLIC_IP_RESULTS_FILE=$OUTPUT_DIRECTORY/$SECOND_PUBLIC_IP_RESULTS_FILENAME
        validate_testcase_result $SECOND_PUBLIC_IP_RESULTS_FILE $EXPECTED_RESULT_FILE $PUBLIC_IP_ALLOCATION_PERF_TEST_NAME
    fi

    if [ -z "$FAILED_CASES" ]; then
        log_level -i "All test cases passes."
        printf '{"result":"%s","error":"%s"}\n' "pass" "" > $OUTPUT_SUMMARYFILE
    else
        log_level -e "Some test cases failed. Please refer logs for more details."
        printf '{"result":"%s","error":"%s"}\n' "failed" "$FAILED_CASES" > $OUTPUT_SUMMARYFILE
    fi
} 2>&1 | tee $LOG_FILENAME