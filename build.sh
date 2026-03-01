#!/bin/bash
set -e
echo "=== Instalando herramientas ==="
sudo apt-get update -qq
sudo apt-get install -y -qq debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools wget ca-certificates

echo "=== PASO 1: Construyendo base mínima Devuan Daedalus ==="
sudo debootstrap --no-check-gpg --variant=minbase --include=linux-image-amd64,sysvinit-core,sudo,locales,tzdata daedalus ./chroot http://deb.devuan.org/merged /usr/share/debootstrap/scripts/sid

echo "=== Configurando entornos para evitar errores de dbus ==="
sudo chroot ./chroot mount -t proc none /proc
sudo chroot ./chroot mount -t sysfs none /sys
sudo chroot ./chroot mount -t devtmpfs none /dev

echo "=== PASO 2: Instalando LXDE y herramientas dentro del Chroot ==="
sudo chroot ./chroot apt-get update
sudo chroot ./chroot apt-get install -y --no-install-recommends lxde-core lightdm network-manager neofetch console-setup

echo "=== Configurando locales y timezone ==="
echo "es_MX.UTF-8 UTF-8" | sudo tee ./chroot/etc/locale.gen
sudo chroot ./chroot locale-gen
echo "LANG=es_MX.UTF-8" | sudo tee ./chroot/etc/locale.conf
echo "America/Monterrey" | sudo tee ./chroot/etc/timezone
DEBIAN_FRONTEND=noninteractive sudo chroot ./chroot dpkg-reconfigure tzdata

echo "=== Inyectando wallpaper ==="
sudo mkdir -p ./chroot/usr/share/backgrounds/
sudo cp wallpaperITCMOS.jpg ./chroot/usr/share/backgrounds/itcm-wallpaper.jpg

echo "=== Limpiando chroot ==="
sudo chroot ./chroot umount /proc /sys /dev
sudo chroot ./chroot apt-get clean

echo "=== Empaquetando squashfs ==="
mkdir -p image/live
sudo mksquashfs chroot image/live/filesystem.squashfs -comp xz -e boot

echo "=== Copiando kernel e initrd ==="
sudo cp chroot/boot/vmlinuz-* image/live/vmlinuz || echo "Error Kernel"
sudo cp chroot/boot/initrd.img-* image/live/initrd || echo "Error Initrd"

echo "=== Generando ISO ==="
grub-mkrescue -o ITCM_OS_v1.iso image
