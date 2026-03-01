#!/bin/bash
set -e
echo "=== Instalando herramientas ==="
sudo apt-get update -qq
sudo apt-get install -y -qq debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools wget ca-certificates

echo "=== PASO 1: Construyendo base mínima ==="
sudo debootstrap --no-check-gpg --variant=minbase --include=linux-image-amd64,sysvinit-core,sudo,locales,tzdata daedalus ./chroot http://deb.devuan.org/merged /usr/share/debootstrap/scripts/sid

echo "=== Montando sistemas ==="
sudo chroot ./chroot mount -t proc none /proc
sudo chroot ./chroot mount -t sysfs none /sys
sudo chroot ./chroot mount -t devtmpfs none /dev

echo "=== PASO 2: Instalando Entorno y LIVE BOOT ==="
sudo chroot ./chroot apt-get update
sudo chroot ./chroot apt-get install -y --no-install-recommends xserver-xorg lxde lightdm lightdm-gtk-greeter network-manager neofetch console-setup live-boot live-config live-config-sysvinit git calamares calamares-settings-debian

echo "=== Configurando Autologin ROOT Absoluto ==="
echo "root:root" | sudo chroot ./chroot chpasswd

# 1. Le decimos a LightDM que el usuario por defecto es root
sudo mkdir -p ./chroot/etc/lightdm/lightdm.conf.d/
cat << 'EOF' | sudo tee ./chroot/etc/lightdm/lightdm.conf.d/01_autologin.conf
[Seat:*]
autologin-guest=false
autologin-user=root
autologin-user-timeout=0
user-session=lxde
EOF

# 2. EL HACK: Desactivamos la regla de PAM que bloquea a root en la interfaz gráfica
sudo chroot ./chroot bash -c "sed -i 's/.*user != root.*/#&/' /etc/pam.d/lightdm-autologin || true"

echo "=== Locales ==="
echo "es_MX.UTF-8 UTF-8" | sudo tee ./chroot/etc/locale.gen
sudo chroot ./chroot locale-gen
echo "LANG=es_MX.UTF-8" | sudo tee ./chroot/etc/locale.conf
echo "America/Monterrey" | sudo tee ./chroot/etc/timezone
DEBIAN_FRONTEND=noninteractive sudo chroot ./chroot dpkg-reconfigure tzdata

echo "=== Customizando LXDE (Wallpaper y Tema) ==="
sudo mkdir -p ./chroot/usr/share/backgrounds/
sudo cp wallpaperITCMOS.jpg ./chroot/usr/share/backgrounds/itcm-wallpaper.jpg

sudo mkdir -p ./chroot/etc/xdg/pcmanfm/LXDE/
cat << 'EOF' | sudo tee ./chroot/etc/xdg/pcmanfm/LXDE/pcmanfm.conf
[desktop]
wallpaper_mode=crop
wallpaper_common=1
wallpaper=/usr/share/backgrounds/itcm-wallpaper.jpg
bgcolor=#000000
fgcolor=#ffffff
show_wm_menu=0
sort=mtime;ascending;
show_documents=0
show_trash=1
show_mounts=1
EOF

echo "Clonando e instalando el tema..."
sudo chroot ./chroot git -c http.sslVerify=false clone https://github.com/Suazo-kun/LocOS-Atmospheric-Theme /tmp/LocOS-Atmospheric-Theme
sudo chroot ./chroot bash -c "cd /tmp/LocOS-Atmospheric-Theme && sed -i 's/sudo //g' install.sh && chmod +x install.sh && ./install.sh"
sudo rm -rf ./chroot/tmp/LocOS-Atmospheric-Theme
sudo chroot ./chroot bash -c "sed -i 's/sNet\/ThemeName=.*/sNet\/ThemeName=Atmospheric-Theme/g' /etc/xdg/lxsession/LXDE/desktop.conf || true"

echo "=== Creando Icono de Instalador en el Escritorio ==="
# Como somos root, la carpeta Desktop ahora vive en /root/Desktop
sudo mkdir -p ./chroot/root/Desktop
cat << 'EOF' | sudo tee ./chroot/root/Desktop/Instalar_ITCM_OS.desktop
[Desktop Entry]
Version=1.0
Type=Application
Name=Instalar ITCM_OS
Comment=Instalar el sistema de Madero en el disco duro
Exec=calamares
Icon=drive-harddisk
Terminal=false
StartupNotify=true
EOF
sudo chmod +x ./chroot/root/Desktop/Instalar_ITCM_OS.desktop

echo "=== Limpiando ==="
sudo chroot ./chroot umount /proc /sys /dev
sudo chroot ./chroot apt-get clean

echo "=== Empaquetando squashfs ==="
mkdir -p image/live
sudo mksquashfs chroot image/live/filesystem.squashfs -comp xz -e boot

echo "=== Kernel e Initrd ==="
sudo cp chroot/boot/vmlinuz-* image/live/vmlinuz
sudo cp chroot/boot/initrd.img-* image/live/initrd

echo "=== Creando Menu GRUB ==="
mkdir -p image/boot/grub
cat << 'EOF' | sudo tee image/boot/grub/grub.cfg
set default=0
set timeout=5
menuentry "ITCM_OS Live (Root Session) - Tec de Madero" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd
}
EOF

echo "=== Generando ISO ==="
grub-mkrescue -o ITCM_OS_v1.iso image
