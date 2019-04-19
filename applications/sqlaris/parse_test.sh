#merge junit test into one
#Return Output

set -e

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
    echo "            -o, --output                         Location for test output files "
    echo "            -t, --test-assets                    Location of all test assets"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -o|--output)
            TEST_OUTPUT_DIRECTORY="$2"
        ;;
        -t|--test-assets)
            TEST_DIRECTORY="$2"
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

if [ -z "$TEST_OUTPUT_DIRECTORY" ];
then
    log_level -e "TEST_OUTPUT_DIRECTORY not set"
    exit 1
fi

if [ -z "$TEST_DIRECTORY" ];
then
    log_level -e "TEST_DIRECTORY not set"
    exit 1
fi

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
log_level -i "TEST_OUTPUT_DIRECTORY: $TEST_OUTPUT_DIRECTORY"
log_level -i "-----------------------------------------------------------------------------"

KUBE_CONFIG_LOCATION=`sudo find  $HOME/$TEST_DIRECTORY/ -type f -iname "kubeconfig*"`

log_level -i "Finding Kubeconfig file from path ($KUBE_CONFIG_LOCATION)"
KUBE_CONFIG_FILENAME=$(basename $KUBE_CONFIG_LOCATION)

log_level -i "Setting Kubectl config variable as per required by k8s"
export KUBECONFIG="$HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME"
export DOCKER_IMAGE_TAG=latest

log_level -i "Changing directories into aris"
cd $HOME/$TEST_DIRECTORY/aris

#The make run-tests-azure command returns an error status when there is one or more test failure. 
#We mark the command as true to allow the script the collect the logs even if there are test failures
log_level -i "Running SQL Aris Tests"
make run-tests-azure || true

log_level -i "SQL Aris Tests Completed"

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

