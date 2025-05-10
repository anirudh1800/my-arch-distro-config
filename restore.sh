eos-update
yay -S --needed - < pkglist.txt
xargs -a flatpaks.txt flatpak install -y
sudo pacman -Rns $(pacman -Qtdq)
