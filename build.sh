#!/bin/bash
set -e
echo "=== Instalando herramientas ==="
sudo apt-get update -qq
sudo apt-get install -y -qq debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools wget ca-certificates

echo "=== Construyendo base Devuan ==="
sudo debootstrap --variant=minbase --include=linux-image-amd64,systemd-sysv,lxde-core,lightdm,network-manager,sudo,fastfetch,locales,tzdata,console-setup bookworm ./chroot http://deb.devuan.org/merged

echo "=== Configurando locales y timezone ==="
echo "es_MX.UTF-8 UTF-8" | sudo tee ./chroot/etc/locale.gen
sudo chroot ./chroot locale-gen
echo "LANG=es_MX.UTF-8" | sudo tee ./chroot/etc/locale.conf
echo "America/Monterrey" | sudo tee ./chroot/etc/timezone
sudo chroot ./chroot dpkg-reconfigure -f noninteractive tzdata

echo "=== Inyectando wallpaper ==="
sudo mkdir -p ./chroot/usr/share/backgrounds/
sudo cp wallpaperITCMOS.jpg ./chroot/usr/share/backgrounds/itcm-wallpaper.jpg

echo "=== Empaquetando squashfs ==="
mkdir -p image/live
sudo mksquashfs chroot image/live/filesystem.squashfs -comp xz -e boot

echo "=== Copiando kernel e initrd ==="
sudo cp chroot/boot/vmlinuz-* image/live/vmlinuz || echo "Error Kernel"
sudo cp chroot/boot/initrd.img-* image/live/initrd || echo "Error Initrd"

echo "=== Generando ISO ==="
grub-mkrescue -o ITCM_OS.iso image
