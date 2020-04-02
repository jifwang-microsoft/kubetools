#!/bin/bash -e

FILE_NAME=$0

SCRIPT_FOLDER=$(dirname $FILE_NAME)
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
OUTPUT_FOLDER=$(dirname $OUTPUT_SUMMARYFILE)
LOG_FILENAME="$OUTPUT_FOLDER/deploy.log"
MONGO_SERVICE="$OUTPUT_FOLDER/mongodb-replicaset-service.txt"
touch $LOG_FILENAME

{
    HELM_INSTALL_FILENAME="install_helm.sh"
    APPLICATION_NAME="mongodb-replicaset"
    TEST_FOLDER="/home/$USER_NAME/$APPLICATION_NAME"
    APPLICATION_FOLDER="applications/common"
    # Github details.
    
    MONGODB_SERVICE_FILENAME="mongodb-replicaset-service.yaml"
    
    curl -o $OUTPUT_FOLDER/$MONGODB_SERVICE_FILENAME \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/mongodb-replicaset/$MONGODB_SERVICE_FILENAME
    if [ ! -f $OUTPUT_FOLDER/$MONGODB_SERVICE_FILENAME ]; then
        log_level -e "File($MONGODB_SERVICE_FILENAME) failed to download."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Download of file($MONGODB_SERVICE_FILENAM) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_FOLDER          : $APPLICATION_FOLDER"
    log_level -i "APPLICATION_NAME            : $APPLICATION_NAME"
    log_level -i "HELM_INSTALL_FILENAME       : $HELM_INSTALL_FILENAME"
    log_level -i "GIT_BRANCH                  : $GIT_BRANCH"
    log_level -i "GIT_REPROSITORY             : $GIT_REPROSITORY"
    log_level -i "TEST_FOLDER                 : $TEST_FOLDER"
    log_level -i "------------------------------------------------------------------------"
    
    ###########################################################################################################
    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    $APPLICATION_FOLDER \
    $SCRIPT_FOLDER \
    $HELM_INSTALL_FILENAME
    
    if [[ $? != 0 ]]; then
        log_level -e "Download of file($HELM_INSTALL_FILENAME) failed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Download of file($HELM_INSTALL_FILENAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Create test folder($TEST_FOLDER)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_FOLDER"
    
    log_level -i "Copy file($HELM_INSTALL_FILENAME) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_FOLDER/$HELM_INSTALL_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_FOLDER/

 
    
    # Install Helm chart
    install_helm_chart $IDENTITY_FILE \
        $USER_NAME \
        $MASTER_IP \
        $TEST_FOLDER \
    $HELM_INSTALL_FILENAME
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Installing Helm was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    install_helm_app $IDENTITY_FILE \
        $USER_NAME \
        $MASTER_IP \
    $APPLICATION_NAME
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Installing App($APPLICATION_NAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
    fi

    scp -i $IDENTITY_FILE \
    $OUTPUT_FOLDER/$MONGODB_SERVICE_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_FOLDER/

    ssh -t -i $IDENTITY_FILE \
    $USER_NAME@$MASTER_IP \
    "sudo chmod 744 $TEST_FOLDER/$MONGODB_SERVICE_FILENAME"
    
    MONGORELEASE=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm ls -d -r --all-namespaces | grep 'deployed\(.*\)mongodb-replicaset' | grep -Eo '^[a-z,-]+\w+'")
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sed -e 's,RELEASE-NAME,$MONGORELEASE,g' < $TEST_FOLDER/$MONGODB_SERVICE_FILENAME > $TEST_FOLDER/mongodb-service.yaml;sudo chmod +x $TEST_FOLDER/mongodb-service.yaml"
    
    mongo=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_FOLDER;sleep 10m;kubectl apply -f mongodb-service.yaml";sleep 5m)
    app_mongo=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get services mongodb-replicaset-service -o=custom-columns=NAME:.status.loadBalancer.ingress[0].ip | grep -oP '(\d{1,3}\.){1,3}\d{1,3}'")
    log_level -i "App_mongo: ($app_mongo)."
    echo $app_mongo > $MONGO_SERVICE

    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo apt-get install mongodb-clients -y"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl exec --namespace default $MONGORELEASE-0 -- sh -c 'mongo --eval=\"printjson(rs.isMaster())\"' >> test_res"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl exec --namespace default $MONGORELEASE-1 -- sh -c 'mongo --eval=\"printjson(rs.isMaster())\"' >> test_res"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl exec --namespace default $MONGORELEASE-2 -- sh -c 'mongo --eval=\"printjson(rs.isMaster())\"' >> test_res"

    PRIMARY_MONGODB=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cat test_res | grep 'primary' | head -n 1 | cut -b 15- | cut -d. -f1")
    
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl exec --namespace default $PRIMARY_MONGODB -- mongo --eval=\"db.createCollection('fruits');db.fruits.insert({ name: 'apples', quantity: '5' });db.fruits.insert({ name: 'oranges', quantity: '3' });db.fruits.find()\""
     
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME
