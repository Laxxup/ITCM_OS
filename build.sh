#!/usr/bin/env bash
# build.sh - Construcción de DiosnicioOS (Live + Instalador Calamares)
# Basado en Devuan Daedalus + LXDE + inspirado en Loc-OS
# Usuario live: diosnicio  → sin contraseña, sudo sin pass, autologin

set -euo pipefail
set -x
IFS=$'\n\t'

# ────────────────────────────────────────────────
# CONFIGURACIÓN PRINCIPAL
# ────────────────────────────────────────────────

ISO_NAME="DiosnicioOS_v1.iso"
CHROOT_DIR="$(pwd)/chroot"
IMAGE_DIR="$(pwd)/image"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="daedalus"
MIRROR="http://deb.devuan.org/merged"

# Colores para salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Construyendo ${ISO_NAME} - DiosnicioOS ===${NC}"

# ────────────────────────────────────────────────
# 0. Dependencias host
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Instalando herramientas necesarias...${NC}"
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
    debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
    grub-efi-amd64-signed shim-signed mtools dosfstools wget ca-certificates \
    git || { echo -e "${RED}Error instalando paquetes${NC}"; exit 1; }

# ────────────────────────────────────────────────
# Cleanup automático al salir o fallar
# ────────────────────────────────────────────────
cleanup() {
    echo -e "${YELLOW}→ Limpiando el entorno chroot y desmontando sistemas virtuales...${NC}"
    
    # 1. Matar cualquier proceso que se haya quedado colgado en el chroot
    sudo fuser -k "${CHROOT_DIR}" 2>/dev/null || true
    sleep 1
    
    # 2. Desmontar en orden inverso (del más profundo al más general) usando lazy unmount (-l)
    for dir in dev/pts run sys proc dev; do
        if mountpoint -q "${CHROOT_DIR}/${dir}"; then
            sudo umount -l "${CHROOT_DIR}/${dir}" 2>/dev/null || true
        fi
    done
    
    # (Opcional) No te recomiendo poner el rm -rf de todo el CHROOT_DIR en el trap 
    # porque si el script falla, a veces es útil revisar qué quedó adentro para depurar.
}
trap cleanup EXIT INT TERM

# ────────────────────────────────────────────────
# 1. Sistema base
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Paso 1: debootstrap minbase${NC}"
sudo rm -rf "${CHROOT_DIR}"

sudo ln -sf /usr/share/debootstrap/scripts/bookworm \
           /usr/share/debootstrap/scripts/${SUITE} 2>/dev/null || true

sudo debootstrap --variant=minbase \
    --include=linux-image-amd64,sysvinit-core,sudo,locales,tzdata,initramfs-tools \
    --no-check-gpg \
    "${SUITE}" "${CHROOT_DIR}" "${MIRROR}" || { echo -e "${RED}debootstrap falló${NC}"; exit 1; }

# ────────────────────────────────────────────────
# 2. Montajes
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Montando /proc /sys /dev${NC}"
sudo mkdir -p "${CHROOT_DIR}"/{proc,sys,dev/pts}
sudo mount -t proc     proc     "${CHROOT_DIR}/proc"
sudo mount -t sysfs    sysfs    "${CHROOT_DIR}/sys"
sudo mount --rbind     /dev     "${CHROOT_DIR}/dev"
sudo mount --make-rslave        "${CHROOT_DIR}/dev"
sudo mount --bind      /dev/pts "${CHROOT_DIR}/dev/pts"
sudo mount --make-slave         "${CHROOT_DIR}/dev/pts"



# ────────────────────────────────────────────────
# 3. Configuración dentro chroot (paquetes + usuario sin pass)
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Instalando paquetes y configurando usuario live${NC}"
sudo mount --bind /run "${CHROOT_DIR}/run"
sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# Instalar gnupg primero para que apt-key pueda funcionar
apt-get install -y --no-install-recommends gnupg

apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 94532124541922FB
apt-get update -qq
apt-get install -y --no-install-recommends \
    live-boot live-config live-config-sysvinit \
    xserver-xorg lxde lightdm lightdm-gtk-greeter \
    network-manager-gnome neofetch console-setup \
    calamares calamares-settings-debian \
    plank mousepad galculator htop gparted qpdfview \
    git extrepo || exit 10

# Locales y zona horaria (Tampico / Cd. Madero)
echo "es_MX.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=es_MX.UTF-8" > /etc/locale.conf
echo "America/Monterrey" > /etc/timezone
dpkg-reconfigure --frontend noninteractive tzdata

# Usuario live SIN CONTRASEÑA
groupadd -r autologin     2>/dev/null || true
groupadd -r nopasswdlogin 2>/dev/null || true

useradd -m -c "Usuario DiosnicioOS" \
    -G sudo,video,audio,netdev,plugdev,cdrom,dip,autologin,nopasswdlogin \
    -s /bin/bash diosnicio

passwd -d diosnicio   # ¡Sin contraseña!

echo "diosnicio ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/01-diosnicio-nopasswd
chmod 0440 /etc/sudoers.d/01-diosnicio-nopasswd

# Autologin LightDM
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<'EOC' > /etc/lightdm/lightdm.conf.d/99-autologin.conf
[Seat:*]
autologin-user=diosnicio
autologin-user-timeout=0
user-session=xfce
EOC

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

exit 0
EOF


# ────────────────────────────────────────────────
# 4. Personalización: wallpaper + launcher Calamares + skel
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Copiando wallpaper y configurando skel${NC}"

if [[ -f "${SCRIPT_DIR}/wallpaperITCMOS.jpg" ]]; then
    # ASEGURAR QUE EL DIRECTORIO DESTINO EXISTA ANTES DE COPIAR
    sudo mkdir -p "${CHROOT_DIR}/usr/share/backgrounds"
    sudo cp "${SCRIPT_DIR}/wallpaperITCMOS.jpg" "${CHROOT_DIR}/usr/share/backgrounds/diosnicio-wallpaper.jpg"
    echo "Wallpaper copiado correctamente"
else
    echo -e "${YELLOW}Advertencia: wallpaperITCMOS.jpg no encontrado${NC}"
fi

# ────────────────────────────────────────────────
# 4.5 Desmontar sistemas de archivos virtuales
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Desmontando /proc /sys /dev antes de comprimir...${NC}"
sudo umount "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
sudo umount -l "${CHROOT_DIR}/dev"  2>/dev/null || true
sudo umount "${CHROOT_DIR}/sys"     2>/dev/null || true
sudo umount "${CHROOT_DIR}/proc"    2>/dev/null || true

# Configuración dinámica de fondo de pantalla para XFCE
sudo mkdir -p "${CHROOT_DIR}/etc/skel/.config/autostart"
sudo mkdir -p "${CHROOT_DIR}/usr/local/bin"

# Creamos un script que busca todos los monitores activos en XFCE y les pone tu wallpaper
cat <<'EOF' | sudo tee "${CHROOT_DIR}/usr/local/bin/set-diosnicio-wallpaper" >/dev/null
#!/bin/bash
sleep 2 # Esperamos a que el escritorio cargue
for prop in $(xfconf-query -c xfce4-desktop -l | grep "last-image"); do
    xfconf-query -c xfce4-desktop -p "$prop" -s /usr/share/backgrounds/diosnicio-wallpaper.jpg
done
EOF
sudo chmod +x "${CHROOT_DIR}/usr/local/bin/set-diosnicio-wallpaper"

# Hacemos que el script se ejecute al iniciar sesión
cat <<'EOF' | sudo tee "${CHROOT_DIR}/etc/skel/.config/autostart/diosnicio-wallpaper.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=Aplicar Fondo DiosnicioOS
Exec=/usr/local/bin/set-diosnicio-wallpaper
Hidden=false
NoDisplay=true
Terminal=false
EOF

# Launcher Instalar en Desktop
sudo mkdir -p "${CHROOT_DIR}/etc/skel/Desktop"
cat <<'EOF' | sudo tee "${CHROOT_DIR}/etc/skel/Desktop/Instalar_DiosnicioOS.desktop" >/dev/null
[Desktop Entry]
Version=1.0
Type=Application
Name=Instalar DiosnicioOS
Exec=pkexec calamares
Icon=drive-harddisk
Terminal=false
StartupNotify=true
EOF
sudo chmod +x "${CHROOT_DIR}/etc/skel/Desktop/Instalar_DiosnicioOS.desktop"

# Copiar skel a home del usuario
sudo cp -rT "${CHROOT_DIR}/etc/skel/." "${CHROOT_DIR}/home/diosnicio/"
sudo chroot "${CHROOT_DIR}" chown -R diosnicio:diosnicio /home/diosnicio

# ────────────────────────────────────────────────
# 5. SquashFS
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Creando filesystem.squashfs${NC}"
mkdir -p "${IMAGE_DIR}/live"
sudo rm -f "${IMAGE_DIR}/live/filesystem.squashfs"

sudo mksquashfs "${CHROOT_DIR}" "${IMAGE_DIR}/live/filesystem.squashfs" \
    -comp zstd -b 1M \
    -e boot || { echo -e "${RED}Fallo squashfs${NC}"; exit 1; }

# ────────────────────────────────────────────────
# 6. Kernel + initrd
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Copiando kernel e initrd${NC}"
KERNEL=$(ls -v1 "${CHROOT_DIR}"/boot/vmlinuz-*   | tail -n1)
INITRD=$(ls -v1 "${CHROOT_DIR}"/boot/initrd.img-* | tail -n1)

[[ -f "$KERNEL" && -f "$INITRD" ]] || { echo -e "${RED}Kernel/initrd no encontrados${NC}"; exit 1; }

sudo cp "$KERNEL" "${IMAGE_DIR}/live/vmlinuz"
sudo cp "$INITRD" "${IMAGE_DIR}/live/initrd"
# ────────────────────────────────────────────────
# 7. GRUB + EFI + Legacy BIOS + Imagen EFI
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Preparando GRUB BIOS+UEFI e imagen EFI${NC}"
mkdir -p "${IMAGE_DIR}/boot/grub/i386-pc" "${IMAGE_DIR}/EFI/BOOT"

# -- 7.1 Archivos para BIOS Legacy --
sudo cp -r /usr/lib/grub/i386-pc/* "${IMAGE_DIR}/boot/grub/i386-pc/"
sudo grub-mkimage -O i386-pc-eltorito -d /usr/lib/grub/i386-pc \
    -o "${IMAGE_DIR}/boot/grub/i386-pc/eltorito.img" \
    -p /boot/grub biosdisk iso9660 normal search

# -- 7.2 Configuración de GRUB --
cat <<'EOF' | sudo tee "${IMAGE_DIR}/boot/grub/grub.cfg" >/dev/null
set default=0
set timeout=4

menuentry "DiosnicioOS - Live" {
    linux /live/vmlinuz boot=live components quiet splash noeject nosplash locales=es_MX.UTF-8 keyboard-layouts=latam
    initrd /live/initrd
}
EOF

# -- 7.3 Archivos para UEFI --
sudo cp /usr/lib/grub/x86_64-efi/bootx64.efi    "${IMAGE_DIR}/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
sudo cp /usr/lib/shim/shimx64.efi.signed        "${IMAGE_DIR}/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
sudo cp /usr/lib/grub/x86_64-efi/grubx64.efi    "${IMAGE_DIR}/EFI/BOOT/grubx64.efi"  2>/dev/null || true

# -- 7.4 Crear imagen FAT32 para la partición EFI (¡La clave para xorriso!) --
echo -e "${YELLOW}→ Creando efi.img...${NC}"
dd if=/dev/zero of="${IMAGE_DIR}/boot/grub/efi.img" bs=1M count=4
mkfs.vfat "${IMAGE_DIR}/boot/grub/efi.img"
# Copiamos la carpeta EFI recursivamente dentro de la imagen
mcopy -s -i "${IMAGE_DIR}/boot/grub/efi.img" "${IMAGE_DIR}/EFI" ::/

# ────────────────────────────────────────────────
# 8. ISO híbrida
# ────────────────────────────────────────────────
echo -e "${YELLOW}→ Generando ISO...${NC}"
rm -f "${ISO_NAME}"

# Usamos banderas estándar de isohybrid en lugar de offsets manuales
sudo xorriso -as mkisofs \
    -r -V 'DiosnicioOS_v1' \
    -o "${ISO_NAME}" \
    -isohybrid-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -c boot/boot.cat \
    -b boot/grub/i386-pc/eltorito.img \
        -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
        -no-emul-boot -isohybrid-gpt-basdat \
    "${IMAGE_DIR}"

echo -e "${GREEN}SIUUU LISTOOOO${NC}"
ls -lh "${ISO_NAME}"
echo "Usuario: diosnicio   → sin contraseña"
echo "Prueba en VM: abre Calamares desde el escritorio (debería lanzarse sin pedir pass)"
