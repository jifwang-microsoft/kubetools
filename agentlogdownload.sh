agent=${1}
foldername=$(date +%Y%m%d)
sudo rm -Rf ~/logs/"$foldername"/"$agent"
mkdir -p  ~/logs/"$foldername"/"$agent"
sudo scp -r azureuser@$agent:/var/log/ ~/logs/"$foldername"/"$agent"
sudo scp -r azureuser@$agent:/var/lib/docker/containers ~/logs/"$foldername"/"$agent"
sudo tar -zcvf ~/logs/"$foldername"+"$agent".tar.gz ~/logs/"$foldername"/"$agent"
sudo rm -Rf ~/logs/"$foldername"/"$agent"
