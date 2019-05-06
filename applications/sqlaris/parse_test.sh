#!/bin/bash

#merge junit test into one
#Return Output

set -e

validate_and_restore_cluster_configuration()
{
    if [ ! -s $1 ]; then
        log_level -e "Cluster configuration file '$1' does not exist or it is empty. An error happened while manipulating its json content."
        exit 1
    fi
    mv $1 $2
}


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
    echo "            -c, --configFile                            Parameter file for any extra parameters for the deployment"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -c|--configfile)
            PARAMETER_FILE="$2"
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

#Checking Variables

if [ ! -f $PARAMETER_FILE ] || [ -z "$PARAMETER_FILE" ]; then
    log_level -e "Parameter file does not exist"
    exit 1
fi

#Cluster settings
CLUSTER_CONTROLLER_USERNAME=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.controllerUsername'`
CLUSTER_CONTROLLER_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.controllerPassword'`
CLUSTER_KNOX_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.knoxPassword'`
CLUSTER_MSSQL_SA_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.mssqlPassword'`
CLUSTER_NAME=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.clusterName'`

#Docker settings
DOCKER_IMAGE_TAG=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.imageTag'`
DOCKER_REGISTRY=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.registry'`
DOCKER_REPOSITORY=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.repository'`
DOCKER_USERNAME=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.username'`
DOCKER_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.password'`

#Test settings
TEST_DIRECTORY=`cat "$PARAMETER_FILE" | jq -r '.dvmAssetsFolder'`
TEST_OUTPUT_DIRECTORY=`cat "$PARAMETER_FILE" | jq -r '.junitFileLocation'`


log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "CLUSTER_NAME: $CLUSTER_NAME"
log_level -i "CLUSTER_CONTROLLER_USERNAME: $CLUSTER_CONTROLLER_USERNAME"
log_level -i "DOCKER_IMAGE_TAG: $DOCKER_IMAGE_TAG"
log_level -i "DOCKER_REGISTRY: $DOCKER_REGISTRY"
log_level -i "DOCKER_REPOSITORY: $DOCKER_REPOSITORY"
log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
log_level -i "TEST_OUTPUT_DIRECTORY: $TEST_OUTPUT_DIRECTORY"
log_level -i "-----------------------------------------------------------------------------"

log_level -i "Installing Dependencies"
sudo apt-get install python3-venv -y

log_level -i "Finding Kubeconfig"
#There is a dependancy on the _output folder to use to connect to the cluster
KUBE_CONFIG_LOCATION=`sudo find  /var/lib/waagent/custom-script/download/0/ -type f -iname "kubeconfig*"`

log_level -i "Finding Kubeconfig file from path ($KUBE_CONFIG_LOCATION)"
KUBE_CONFIG_FILENAME=$(basename $KUBE_CONFIG_LOCATION)

log_level -i "Copy kubeconfig($KUBE_CONFIG_LOCATION) to home directory"
sudo cp $KUBE_CONFIG_LOCATION $HOME/$TEST_DIRECTORY

log_level -i "Checking if file ($KUBE_CONFIG_FILENAME) exists"
if [[ ! -f $HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME ]]; then
    log_level -e "File($KUBE_CONFIG_FILENAME) does not exist at $HOME/$TEST_DIRECTORY"
    exit 1
else
    log_level -i "File($KUBE_CONFIG_FILENAME) exist at $HOME/$TEST_DIRECTORY"
fi

log_level -i "Changing permissions of the config file"
sudo chmod a+r $HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME

log_level -i "Setting Kubectl config variable as per required by k8s"
export KUBECONFIG="$HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME"

log_level -i "Changing directories into aris"
cd $HOME/$TEST_DIRECTORY/aris

# export environment variables
log_level -i "Exporting enviroment variables for mssqlctl testing"
export CONTROLLER_USERNAME=$CLUSTER_CONTROLLER_USERNAME
export CONTROLLER_PASSWORD=$CLUSTER_CONTROLLER_PASSWORD
export DOCKER_REGISTRY=$DOCKER_REGISTRY
export DOCKER_REPOSITORY=$DOCKER_REPOSITORY
export DOCKER_USERNAME=$DOCKER_USERNAME
export DOCKER_PASSWORD=$DOCKER_PASSWORD
export MSSQL_SA_PASSWORD=$CLUSTER_MSSQL_SA_PASSWORD
export KNOX_PASSWORD=$CLUSTER_KNOX_PASSWORD
export DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG
export CLUSTER_NAME=$CLUSTER_NAME

# copy and overwrite configurations fror azure
PATCH_CONFIG="$HOME/$TEST_DIRECTORY/aris/projects/platform/patch-config/azure-latest-patch.json"
if [[ ! -f $PATCH_CONFIG ]]; then
    log_level -e "Config file not found at ($PATCH_CONFIG)"
    exit 1
fi

PATCH_CONFIG_TEMP="$HOME/$TEST_DIRECTORY/aris/projects/platform/patch-config/azure-latest-patch.tmp"
if [[ ! -f $PATCH_CONFIG_TEMP ]]; then
    log_level -e "Config file not found at ($PATCH_CONFIG_TEMP) creating"
    touch $PATCH_CONFIG_TEMP
fi

log_level -i "Overwriting test configurations"
cat $PATCH_CONFIG | \
jq --arg DOCKER_REGISTRY $DOCKER_REGISTRY '.patch[0].value.registry = $DOCKER_REGISTRY'| \
jq --arg DOCKER_REPOSITORY $DOCKER_REPOSITORY '.patch[0].value.repository = $DOCKER_REPOSITORY'| \
jq --arg DOCKER_IMAGE_TAG $DOCKER_IMAGE_TAG '.patch[0].value.imageTag = $DOCKER_IMAGE_TAG' \
> $PATCH_CONFIG_TEMP

validate_and_restore_cluster_configuration $PATCH_CONFIG_TEMP $PATCH_CONFIG

log_level -i "Logging current patch configuration"
cat $PATCH_CONFIG

# run tests

#The make run-tests-azure command returns an error status when there is one or more test failure.
#We mark the command as true to allow the script the collect the logs even if there are test failures
log_level -i "Running SQL Aris Tests"
make run-tests-azure || true

log_level -i "SQL Aris Tests Completed"

#This command may cause an error where one or more log locations is/are not available. We mark this as true since this error should not case the script to fail
log_level -i "Running log collection"
make copy-logs || true

LOG_LOCATION="$HOME/$TEST_DIRECTORY/aris/output/logs"

log_level -i "Checking if folder($LOG_LOCATION) exists"
if [[ -d $LOG_LOCATION ]]; then
    log_level -i "Directory ($LOG_LOCATION) exists"
else
    log_level -e "Directory ($LOG_LOCATION) does not exist"
    exit 1
fi

sudo cp -r $LOG_LOCATION $HOME/$TEST_DIRECTORY

log_level -i "Log collection complete"

log_level -i "Making output directory($HOME/$TEST_DIRECTORY/$TEST_OUTPUT_DIRECTORY)"
mkdir $HOME/$TEST_DIRECTORY/$TEST_OUTPUT_DIRECTORY

ARIS_TEST_RESULTS="$HOME/$TEST_DIRECTORY/aris/projects/test/output/junit"

log_level -i "Checking if folder($ARIS_TEST_RESULTS) exists"
if [[ -d $ARIS_TEST_RESULTS ]]; then
    log_level -i "Directory ($ARIS_TEST_RESULTS) exists"
else
    log_level -e "Directory ($ARIS_TEST_RESULTS) does not exist"
    exit 1
fi

log_level -i "Moving Test Results into a test directory"
sudo cp -r $ARIS_TEST_RESULTS/* $HOME/$TEST_DIRECTORY/$TEST_OUTPUT_DIRECTORY

log_level -i "Change directory to folder ($TEST_OUTPUT_DIRECTORY)"
cd $HOME/$TEST_DIRECTORY/$TEST_OUTPUT_DIRECTORY

log_level -i "Collecting junit merge file"
curl -O https://gist.githubusercontent.com/cgoldberg/4320815/raw/efcf6830f516f79b82e7bd631b076363eda3ed99/merge_junit_results.py

if [ ! -f "merge_junit_results.py" ]; then
    log_level -e "File(merge_junit_results.py) failed to download."
    exit 1
fi

log_level -i "Merge junit files"
FILES=""
for entry in *
do
    if [ $entry == "merge_junit_results.py" ];
    then
        log_level -w "Not Merging $entry"
    else
        log_level -i "Merging $entry"
        FILES="$FILES $entry"
    fi
done
python merge_junit_results.py $FILES > results.xml

log_level -i "Remove merger script"
rm -rf merge_junit_results.py

echo 0

