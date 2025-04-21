eos-update
yay -S --needed - < pkglist.txt
sudo systemctl enable --now snapd
sudo systemctl enable --now keyd