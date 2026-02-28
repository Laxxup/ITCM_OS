#!/bin/bash
apt update && apt install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools -y
debootstrap --variant=minbase --include=linux-image-amd64,lxde-core,network-manager,sudo,fastfetch,firmware-linux daedalus ./chroot http://deb.devuan.org/merged
# Aqui van tus configuraciones manuales (Usuario, Locales, Temas)
# ... (GitHub ejecutara esto desde cero)
mkdir -p image/live
mksquashfs chroot image/live/filesystem.squashfs -comp xz -e boot
cp chroot/boot/vmlinuz* image/live/vmlinuz
cp chroot/boot/initrd* image/live/initrd
grub-mkrescue -o ITCM_OS_v1.iso image
