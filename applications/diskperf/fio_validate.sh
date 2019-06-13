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
    APPLICATION_NAME="fio"
    RESULTS_FILENAME="results.json"
    RESULTS_FILE=$OUTPUT_DIRECTORY/$RESULTS_FILENAME
    EXPECTED_RESULT_FILE="expectedresults.json"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    MINVALUE_RESULT_FILE=$SCRIPT_DIRECTORY/$EXPECTED_RESULT_FILE
    FAILED_CASES=""
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "EXPECTED_RESULT_FILE       : $EXPECTED_RESULT_FILE"
    log_level -i "RESULTS_FILENAME           : $RESULTS_FILENAME"
    log_level -i "TEST_DIRECTORY             : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"
    # Wait for pod to stop after the runs are complete.
    check_app_pod_status $IDENTITY_FILE \
    $USER_NAME \
    $MASTER_IP \
    "job-name=$APPLICATION_NAME" \
    "Completed"
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Pod related to App($APPLICATION_NAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    # Get logs from container.
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; kubectl logs -f job/$APPLICATION_NAME > $TEST_DIRECTORY/log.txt;"
    scp -r -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/log.txt $OUTPUT_DIRECTORY
    READ_IOPS_VALUE=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; cat log.txt | grep 'Random Read IOPS Value:' | cut -d':' -f2 | xargs;")
    WRITE_IOPS_VALUE=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; cat log.txt | grep 'Random Write IOPS Value:' | cut -d':' -f2 | xargs;")
    MIX_READ_IOPS_VALUE=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; cat log.txt | grep 'Mixed Read IOPS Value:' | cut -d':' -f2 | xargs;")
    MIX_WRITE_IOPS_VALUE=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; cat log.txt | grep 'Mixed Write IOPS Value:' | cut -d':' -f2 | xargs;")
    READ_SEQ_VALUE=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; cat log.txt | grep 'Sequential Read IOPS Value:' | cut -d':' -f2 | xargs | grep -Eo '[+-]?[0-9]+([.][0-9]+)?'")
    WRITE_SEQ_VALUE=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; cat log.txt | grep 'Sequential Write IOPS Value:' | cut -d':' -f2 | xargs | grep -Eo '[+-]?[0-9]+([.][0-9]+)?'")

    json_string='{ "testSuite": [ {"testname":"Random_Read_IOPS", "value":"%s" },{"testname":"Random_Write_IOPS", "value":"%s"},'
    json_string=$json_string'{"testname":"Mixed_Read_IOPS", "value":"%s"},{"testname":"Mixed_Write_IOPS", "value":"%s"},'
    json_string=$json_string'{"testname":"Sequential_Read_IOPS", "value":"%s"},{"testname":"Sequential_Write_IOPS", "value":"%s"} ] }'
    printf "$json_string" "$READ_IOPS_VALUE" "$WRITE_IOPS_VALUE" \
                          "$MIX_READ_IOPS_VALUE" "$MIX_WRITE_IOPS_VALUE" \
                          "$READ_SEQ_VALUE" "$WRITE_SEQ_VALUE" > $RESULTS_FILE

    log_level -i "Validate results with minimum expected results."
    validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Random_Read_IOPS"
    validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Random_Write_IOPS"
    validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Mixed_Read_IOPS"
    validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Mixed_Write_IOPS"
    validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Sequential_Read_IOPS"
    validate_testcase_result $RESULTS_FILE $MINVALUE_RESULT_FILE "Sequential_Write_IOPS"

    if [ -z "$FAILED_CASES" ]; then
        log_level -i "All test cases passes."
        printf '{"result":"%s","error":"%s"}\n' "pass" "" > $OUTPUT_SUMMARYFILE
    else
        log_level -e "Some test cases failed. Please refer logs for more details."
        printf '{"result":"%s","error":"%s"}\n' "failed" "$FAILED_CASES" > $OUTPUT_SUMMARYFILE
    fi

} 2>&1 | tee $LOG_FILENAME