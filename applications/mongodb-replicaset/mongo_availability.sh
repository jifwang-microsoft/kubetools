#!/bin/bash
ROOT_PATH=/home/azureuser
ssh -t -i $IDENTITY_FILE $USER@$DVM_IP "while true;do echo $(date +"%Y-%m-%d-%H:%M:%S") >> mongo-availability_logs; mongo --host $APP_IP:27017 < /home/azureuser/testmongodb.js >> mongo-availability_logs;sleep 20;done"
