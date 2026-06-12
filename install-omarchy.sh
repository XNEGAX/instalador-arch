#!/bin/bash
# Script de Automatización para Arch Linux - Optimizado para IA (RTX 5060) y Gaming
# Usuario: Carlos | Hardware: Ryzen 5 9600X, RTX 5060, 16GB RAM, MT7922

set -e # Salir inmediatamente si un comando falla

# ==========================================
# CONFIGURACIÓN PERSONALIZABLE
# ==========================================
USER_NAME="carlos"
USER_PASSWORD="753951"
ROOT_PASSWORD="753951"
HOSTNAME="ngamer"
KEYBOARD_LAYOUT="la-latin1" # O 'es' dependiendo de tu teclado
TIMEZONE="America/Santiago" # Ajusta a tu país (ej. America/Bogota, America/Argentina/Buenos_Aires)
LOCALE="es_CL.UTF-8" # Ajusta a tu región (ej. es_CO.UTF-8, es_AR.UTF-8)

# Entorno: 'hyprland' (recomendado, ligero y moderno) o 'xfce4' (más tradicional)
DESKTOP_ENV="hyprland"

# ==========================================
# 1. CONFIGURACIÓN BASE DEL SISTEMA
# ==========================================
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

# ==========================================
# 2. CONFIGURACIÓN DE RED (CRÍTICO PARA MEDIATEK)
# ==========================================
echo "[*] Instalando y habilitando NetworkManager (mejor soporte para MediaTek MT7922)..."
pacman -S --noconfirm networkmanager network-manager-applet
systemctl enable NetworkManager

# ==========================================
# 3. MICROCODE Y BOOTLOADER
# ==========================================
echo "[*] Instalando microcode de AMD y systemd-boot..."
pacman -S --noconfirm amd-ucode
bootctl install

cat <<EOF > /boot/loader/loader.conf
default arch.conf
timeout 3
console-mode max
editor no
EOF

cat <<EOF > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/root | head -n 1) rw
EOF
# Nota: Si usaste cfdisk sin etiquetas, reemplaza la línea 'options root=' con:
# options root=/dev/nvme0n1p3 rw

# ==========================================
# 4. DRIVERS NVIDIA (BLACKWELL / SERIE 50) Y AUDIO
# ==========================================
echo "[*] Instalando drivers NVIDIA de última generación y utilidades..."
# nvidia-open es el módulo abierto, recomendado para nuevas arquitecturas como Blackwell
pacman -S --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader

echo "[*] Instalando PipeWire (Audio de baja latencia para juegos/IA)..."
pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber

# ==========================================
# 5. ENTORNO DE ESCRITORIO (OPTIMIZADO PARA 16GB RAM)
# ==========================================
echo "[*] Instalando entorno de escritorio ligero..."
if [ "$DESKTOP_ENV" == "hyprland" ]; then
    pacman -S --noconfirm hyprland kitty waybar wofi polkit-gnome xdg-desktop-portal-hyprland
elif [ "$DESKTOP_ENV" == "xfce4" ]; then
    pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
    systemctl enable lightdm
fi

# ==========================================
# 6. HERRAMIENTAS DE DESARROLLO, IA Y GAMING
# ==========================================
echo "[*] Instalando herramientas esenciales, Docker y soporte de IA..."
pacman -S --noconfirm base-devel git curl wget zsh fzf neovim
pacman -S --noconfirm docker docker-compose
systemctl enable docker

# Herramientas específicas de IA
pacman -S --noconfirm python python-pip python-virtualenv
# Opcional: ollama (para correr LLMs locales fácilmente)
# pacman -S --noconfirm ollama
# systemctl enable ollama

# Gaming
pacman -S --noconfirm steam lutris mangohud lib32-mangohud goverlay

# ==========================================
# 7. CONFIGURACIÓN DE USUARIO Y SWAP
# ==========================================
echo "[*] Creando usuario y configurando sudo..."
useradd -m -G wheel,audio,video,storage,optical,docker -s /bin/bash $USER_NAME
echo "root:$ROOT_PASSWORD" | chpasswd
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# Habilitar sudo sin contraseña para wheel (opcional, o usa visudo manualmente después)
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Ajuste de Swappiness (Crítico para tus 16GB de RAM con IA)
# Valor 10: usa la swap solo cuando la RAM esté casi llena, evitando lentitud innecesaria
echo "vm.swappiness=10" >> /etc/sysctl.d/99-sysctl.conf

# ==========================================
# 8. OPTIMIZACIONES FINALES DE KERNEL
# ==========================================
echo "[*] Aplicando parámetros de kernel para NVIDIA y MediaTek..."
cat <<EOF > /etc/modprobe.d/nvidia.conf
options nvidia-drm modeset=1 fbdev=1
EOF

# Forzar el driver de MediaTek para evitar problemas de suspensión
cat <<EOF > /etc/modprobe.d/mediatek.conf
options mt7921e disable_aspm=1
EOF

echo "[*] ¡Instalación completada con éxito!"
echo "[*] Por favor, ejecuta 'exit' para salir del chroot, luego 'reboot'."
echo "[*] Recuerda retirar el USB antes de que inicie el sistema."
