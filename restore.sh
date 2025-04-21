eos-update
yay -S --needed - < pkglist.txt
sudo systemctl enable snapd --now
sudo systemctl enable keyd --now
cp ./default.conf /etc/keyd/default.conf
sudo keyd reload