#!/bin/bash
# 1. Instalar herramientas de empaquetado
sudo apt-get update
sudo apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools

# 2. Crear un sistema base minimo (Esto es lo que faltaba)
sudo debootstrap --variant=minbase --include=linux-image-amd64,lxde-core,network-manager,sudo,fastfetch daedalus ./chroot http://deb.devuan.org/merged

# 3. Inyectar tu wallpaper
sudo mkdir -p ./chroot/usr/share/images/desktop-base/
sudo cp wallpaperITCMOS.jpg ./chroot/usr/share/images/desktop-base/

# 4. Crear la estructura de la ISO
mkdir -p image/live
sudo mksquashfs chroot image/live/filesystem.squashfs -comp xz -e boot

# 5. Copiar archivos de arranque
sudo cp chroot/boot/vmlinuz* image/live/vmlinuz
sudo cp chroot/boot/initrd* image/live/initrd

# 6. Generar la ISO final
grub-mkrescue -o ITCM_OS_v1.iso image
