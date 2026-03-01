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
sudo chroot ./chroot apt-get install -y --no-install-recommends \
    xserver-xorg lxde lightdm lightdm-gtk-greeter network-manager neofetch \
    console-setup live-boot live-config live-config-sysvinit git calamares \
    calamares-settings-debian plank mousepad galculator htop gparted qpdfview extrepo

echo "=== Instalando LibreWolf ==="
sudo chroot ./chroot extrepo enable librewolf
sudo chroot ./chroot apt-get update
sudo chroot ./chroot apt-get install -y librewolf

echo "=== Locales y Zona horaria ==="
echo "es_MX.UTF-8 UTF-8" | sudo tee ./chroot/etc/locale.gen
sudo chroot ./chroot locale-gen
echo "LANG=es_MX.UTF-8" | sudo tee ./chroot/etc/locale.conf
echo "America/Monterrey" | sudo tee ./chroot/etc/timezone
DEBIAN_FRONTEND=noninteractive sudo chroot ./chroot dpkg-reconfigure tzdata

echo "=== Customizando (Modo Skeleton) ==="
# Wallpaper Global
sudo mkdir -p ./chroot/usr/share/backgrounds/
sudo cp wallpaperITCMOS.jpg ./chroot/usr/share/backgrounds/itcm-wallpaper.jpg

# Tema Atmospheric
sudo chroot ./chroot git -c http.sslVerify=false clone https://github.com/Suazo-kun/LocOS-Atmospheric-Theme /tmp/LocOS-Atmospheric-Theme
sudo chroot ./chroot bash -c "cd /tmp/LocOS-Atmospheric-Theme && sed -i 's/sudo //g' install.sh && chmod +x install.sh && ./install.sh"
sudo rm -rf ./chroot/tmp/LocOS-Atmospheric-Theme

# Skeleton para el usuario "alumno"
sudo mkdir -p ./chroot/etc/skel/.config/pcmanfm/LXDE/
sudo mkdir -p ./chroot/etc/skel/.config/lxsession/LXDE/
sudo mkdir -p ./chroot/etc/skel/.config/openbox/
sudo mkdir -p ./chroot/etc/skel/.config/lxpanel/LXDE/panels/
sudo mkdir -p ./chroot/etc/skel/.config/autostart/
sudo mkdir -p ./chroot/etc/skel/Desktop/

# Wallpaper
cat << 'EOF' | sudo tee ./chroot/etc/skel/.config/pcmanfm/LXDE/desktop.conf
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

# Tema oscuro + sesión
cat << 'EOF' | sudo tee ./chroot/etc/skel/.config/lxsession/LXDE/desktop.conf
[Session]
window_manager=openbox-lxde
[GTK]
sNet/ThemeName=Atmospheric-Theme
EOF

sudo cp ./chroot/etc/xdg/openbox/LXDE-rc.xml ./chroot/etc/skel/.config/openbox/lxde-rc.xml || true
sudo sed -i 's/<name>.*<\/name>/<name>Atmospheric-Theme<\/name>/' ./chroot/etc/skel/.config/openbox/lxde-rc.xml || true

# Barra arriba + Plank automático
sudo cp ./chroot/usr/share/lxpanel/profile/LXDE/panels/panel ./chroot/etc/skel/.config/lxpanel/LXDE/panels/panel || true
sudo sed -i 's/edge=bottom/edge=top/g' ./chroot/etc/skel/.config/lxpanel/LXDE/panels/panel || true

cat << 'EOF' | sudo tee ./chroot/etc/skel/.config/autostart/plank.desktop
[Desktop Entry]
Type=Application
Exec=plank
Name=Plank
EOF

# Icono Instalar
cat << 'EOF' | sudo tee ./chroot/etc/skel/Desktop/Instalar_ITCM_OS.desktop
[Desktop Entry]
Version=1.0
Type=Application
Name=Instalar ITCM_OS
Exec=sudo calamares
Icon=drive-harddisk
Terminal=false
StartupNotify=true
EOF
sudo chmod +x ./chroot/etc/skel/Desktop/Instalar_ITCM_OS.desktop

sudo bash -c 'echo "neofetch" >> ./chroot/etc/skel/.bashrc'

# =============================================
# NUEVO: CONFIGURACIÓN DE AUTOLOGIN LIGHTDM
# =============================================
echo "=== Configurando AUTOLOGIN directo como alumno ==="
sudo mkdir -p ./chroot/etc/lightdm/lightdm.conf.d

cat << 'EOF' | sudo tee ./chroot/etc/lightdm/lightdm.conf.d/99-live-autologin.conf
[Seat:*]
autologin-user=alumno
autologin-user-timeout=0
greeter-hide-users=true
allow-guest=false
greeter-show-manual-login=false
user-session=LXDE
EOF

echo "=== Limpiando ==="
sudo chroot ./chroot umount /proc /sys /dev
sudo chroot ./chroot apt-get clean

echo "=== Empaquetando squashfs ==="
mkdir -p image/live
sudo mksquashfs chroot image/live/filesystem.squashfs -comp xz -e boot

echo "=== Kernel e Initrd ==="
sudo cp chroot/boot/vmlinuz-* image/live/vmlinuz
sudo cp chroot/boot/initrd.img-* image/live/initrd

echo "=== Creando Menu GRUB (con live-config mejorado) ==="
mkdir -p image/boot/grub
cat << 'EOF' | sudo tee image/boot/grub/grub.cfg
set default=0
set timeout=2

menuentry "ITCM_OS - Instituto Tecnologico de Ciudad Madero" {
    linux /live/vmlinuz boot=live components quiet splash \
        live-config.username=alumno \
        live-config.user-fullname="Alumno ITCM" \
        live-config.user-default-groups="audio cdrom dip floppy video plugdev netdev scanner bluetooth sudo" \
        live-config.hostname=itcm-os \
        live-config.locales=es_MX.UTF-8 \
        live-config.keyboard-layouts=latam
    initrd /live/initrd
}
EOF

echo "=== Generando ISO (Listo para Live USB) ==="
grub-mkrescue -o ITCM_OS_v25_Fix_LightDM.iso image

echo "¡ISO generada correctamente! → ITCM_OS_v25_Fix_LightDM.iso"
echo "Ahora puedes grabarla con Rufus, Ventoy, balenaEtcher o dd."
