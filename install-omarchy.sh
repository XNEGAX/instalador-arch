#!/bin/bash
# Script Unificado de Instalación Arch Linux - Optimizado para IA (RTX 5060) y Gaming
# Usuario: Carlos | Hardware: Ryzen 5 9600X, RTX 5060, 16GB RAM, MT7922

set -e # Salir inmediatamente si un comando falla

# ==========================================
# FASE 1: ENTORNO LIVE USB (Particionado y Montaje)
# ==========================================
TARGET_DISK="/dev/nvme0n1"

echo "========================================================"
echo " ⚠️ ADVERTENCIA CRÍTICA ⚠️"
echo " Este script BORRARA COMPLETAMENTE el disco: $TARGET_DISK"
echo " Todos los datos, juegos y sistemas operativos previos se perderán."
echo "========================================================"
read -p "¿Estás 100% seguro de que quieres continuar? (Escribe 'SI' en mayúsculas): " CONFIRM

if [ "$CONFIRM" != "SI" ]; then
    echo "Instalación cancelada por el usuario."
    exit 1
fi

echo "[*] 1. Limpiando y particionando $TARGET_DISK..."
wipefs -a $TARGET_DISK
sgdisk -Z $TARGET_DISK
sgdisk -n 1:0:+550M -t 1:ef00 -c 1:"EFI" $TARGET_DISK
sgdisk -n 2:0:+16G -t 2:8200 -c 2:"Swap" $TARGET_DISK
sgdisk -n 3:0:0 -t 3:8304 -c 3:"Root" $TARGET_DISK

echo "[*] 2. Formateando particiones..."
mkfs.fat -F32 ${TARGET_DISK}p1
mkswap ${TARGET_DISK}p2
mkfs.ext4 -L "ArchRoot" ${TARGET_DISK}p3

echo "[*] 3. Montando sistemas de archivos..."
swapon ${TARGET_DISK}p2
mount ${TARGET_DISK}p3 /mnt
mkdir -p /mnt/boot
mount ${TARGET_DISK}p1 /mnt/boot

echo "[*] 4. Instalando sistema base (descargando paquetes, esto puede tardar)..."
pacstrap -K /mnt base linux linux-firmware sudo nano

echo "[*] 5. Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "[*] 6. Preparando script de configuración interna (Fase 2)..."
cat << 'PHASE2_SCRIPT' > /mnt/root/configurar_sistema.sh
#!/bin/bash
set -e

# ==========================================
# CONFIGURACIÓN PERSONALIZABLE (FASE 2)
# ==========================================
USER_NAME="carlos"
USER_PASSWORD="753951"
ROOT_PASSWORD="753951"
HOSTNAME="ngamer"
KEYBOARD_LAYOUT="la-latin1"
TIMEZONE="America/Santiago"
LOCALE="es_CL.UTF-8"
DESKTOP_ENV="hyprland"

echo "[*] Configurando zona horaria y locales..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYBOARD_LAYOUT" > /etc/vconsole.conf

echo "[*] Configurando nombre de host y hosts..."
echo "$HOSTNAME" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

echo "[*] Instalando y habilitando NetworkManager (Mejor soporte para MediaTek MT7922)..."
pacman -S --noconfirm networkmanager network-manager-applet
systemctl enable NetworkManager

echo "[*] Instalando microcode de AMD y bootloader..."
pacman -S --noconfirm amd-ucode
bootctl install

cat <<EOF > /boot/loader/loader.conf
default arch.conf
timeout 3
console-mode max
editor no
EOF

# Usamos /dev/nvme0n1p3 directamente para evitar fallos de parsing de blkid en scripts
cat <<EOF > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=/dev/nvme0n1p3 rw
EOF

echo "[*] Instalando drivers NVIDIA (Blackwell/Serie 50) y utilidades..."
pacman -S --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader

echo "[*] Instalando PipeWire (Audio de baja latencia)..."
pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber

echo "[*] Instalando entorno de escritorio ligero (Hyprland)..."
pacman -S --noconfirm hyprland kitty waybar wofi polkit polkit-gnome xdg-desktop-portal-hyprland

echo "[*] Instalando herramientas de desarrollo, Docker e IA..."
pacman -S --noconfirm base-devel git curl wget zsh fzf neovim
pacman -S --noconfirm docker docker-compose
systemctl enable docker

echo "[*] Instalando soporte Python para IA..."
pacman -S --noconfirm python python-pip python-virtualenv

echo "[*] Instalando herramientas de Gaming..."
pacman -S --noconfirm steam lutris mangohud lib32-mangohud goverlay

echo "[*] Creando usuario y configurando contraseñas..."
useradd -m -G wheel,audio,video,storage,optical,docker -s /bin/bash $USER_NAME
echo "root:$ROOT_PASSWORD" | chpasswd
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

echo "[*] Configurando sudo..."
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

echo "[*] Ajuste de Swappiness (Crítico para 16GB de RAM con IA)..."
echo "vm.swappiness=10" >> /etc/sysctl.d/99-sysctl.conf

echo "[*] Aplicando parámetros de kernel para NVIDIA y MediaTek..."
cat <<EOF > /etc/modprobe.d/nvidia.conf
options nvidia-drm modeset=1 fbdev=1
EOF

cat <<EOF > /etc/modprobe.d/mediatek.conf
options mt7921e disable_aspm=1
EOF

echo "[*] ¡Configuración interna completada con éxito!"
PHASE2_SCRIPT

chmod +x /mnt/root/configurar_sistema.sh

echo "[*] 7. Entrando al entorno chroot para ejecutar la Fase 2..."
arch-chroot /mnt /root/configurar_sistema.sh

# Limpieza final del script temporal
rm /mnt/root/configurar_sistema.sh

echo "========================================================"
echo " 🎉 ¡INSTALACIÓN COMPLETADA CON ÉXITO! 🎉"
echo " 1. Escribe: reboot"
echo " 2. Retira el USB inmediatamente."
echo " 3. Disfruta tu sistema optimizado para IA y Gaming."
echo "========================================================"
