foldername=$(date +%Y%m%d)
sudo rm -Rf ~/logs/"$foldername"
mkdir -p  ~/logs/"$foldername"
sudo cp -r /var/log/ ~/logs/"$foldername"
sudo cp -r /var/lib/docker/containers ~/logs/"$foldername"
sudo tar -zcvf ~/logs/$foldername.tar.gz ~/logs/"$foldername"
sudo rm -Rf ~/logs/"$foldername" 
