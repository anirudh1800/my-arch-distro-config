eos-update
yay -S --needed - < pkglist.txt
xargs -a flatpaks.txt flatpak install -y
xargs -a extensions.txt code --install-extension 