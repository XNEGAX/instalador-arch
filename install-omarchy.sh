#!/bin/bash
#===============================================================================
# OMARCHY AUTO-INSTALLER v2.0
# Optimizado para: Ryzen 5 9600X + RTX 5060 + 16GB RAM
# Autor: Carlos
# Fecha: 2026
#===============================================================================

set -e  # Salir si hay error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuración
USERNAME="carlos"
HOSTNAME="arch-omarchy"
TIMEZONE="America/Bogota"
LOCALE="es_MX.UTF-8"
KEYMAP="la-latin1"

# Funciones de utilidad
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Verificar que se ejecute como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root (usa sudo)"
fi

#===============================================================================
# DETECCIÓN DE DISCO (MEJORADA)
#===============================================================================
log_info "Buscando discos disponibles..."

# Si se pasó el disco como argumento, usarlo
if [ -n "$1" ]; then
    DISK="$1"
    log_info "Usando disco proporcionado: ${DISK}"
else
    # Detectar discos automáticamente
    AVAILABLE_DISKS=()
    
    # Buscar NVMe
    for disk in /dev/nvme[0-9]n[0-9]; do
        if [ -b "$disk" ]; then
            AVAILABLE_DISKS+=("$disk")
        fi
    done
    
    # Buscar SATA/SCSI
    for disk in /dev/sd[a-z]; do
        if [ -b "$disk" ]; then
            # Verificar que sea un disco, no una partición
            if lsblk -d -n -o TYPE "$disk" 2>/dev/null | grep -q "disk"; then
                AVAILABLE_DISKS+=("$disk")
            fi
        fi
    done
    
    # Si no se encontró nada, error
    if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
        log_error "No se encontraron discos disponibles. Especifica el disco manualmente: ./script.sh /dev/nvme0n1"
    fi
    
    # Si hay un solo disco, usarlo
    if [ ${#AVAILABLE_DISKS[@]} -eq 1 ]; then
        DISK="${AVAILABLE_DISKS[0]}"
        log_info "Disco único detectado: ${DISK}"
    else
        # Múltiples discos - mostrar menú
        echo -e "${YELLOW}Se encontraron múltiples discos:${NC}"
        for i in "${!AVAILABLE_DISKS[@]}"; do
            disk="${AVAILABLE_DISKS[$i]}"
            size=$(lsblk -d -n -o SIZE "$disk" 2>/dev/null)
            model=$(cat /sys/block/$(basename "$disk")/device/model 2>/dev/null | xargs || echo "Unknown")
            echo -e "  ${BLUE}[$i]${NC} $disk - $size - $model"
        done
        echo ""
        read -p "Selecciona el número del disco a usar [0-$(( ${#AVAILABLE_DISKS[@]} - 1 ))]: " selection
        
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 0 ] || [ "$selection" -ge ${#AVAILABLE_DISKS[@]} ]; then
            log_error "Selección inválida"
        fi
        
        DISK="${AVAILABLE_DISKS[$selection]}"
    fi
fi

# Validar que el disco exista
if [ ! -b "$DISK" ]; then
    log_error "El disco $DISK no existe o no es un dispositivo de bloque válido"
fi

# Mostrar información del disco
DISK_SIZE=$(lsblk -d -n -o SIZE "$DISK" 2>/dev/null)
DISK_MODEL=$(cat /sys/block/$(basename "$DISK")/device/model 2>/dev/null | xargs || echo "Unknown")

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}DISCO SELECCIONADO:${NC}"
echo -e "  Dispositivo: ${YELLOW}${DISK}${NC}"
echo -e "  Tamaño: ${YELLOW}${DISK_SIZE}${NC}"
echo -e "  Modelo: ${YELLOW}${DISK_MODEL}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""
read -p "⚠️  ESTO BORRARÁ TODO EL DISCO. ¿Continuar? (escribe 'SI' en mayúsculas): " CONFIRM
if [ "$CONFIRM" != "SI" ]; then
    log_error "Instalación cancelada por el usuario"
fi

# Detectar si es NVMe o SATA para nombrar particiones correctamente
if [[ "$DISK" == *"nvme"* ]]; then
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    BOOT_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

log_info "Particiones a crear:"
log_info "  EFI: ${BOOT_PART} (1GB)"
log_info "  Root: ${ROOT_PART} (resto del disco)"

# Verificar conexión a internet
log_info "Verificando conexión a internet..."
ping -c3 google.com > /dev/null 2>&1 || log_error "Sin conexión a internet. Conecta por Ethernet o configura Wi-Fi con: iwctl"

# Sincronizar reloj
log_info "Sincronizando reloj del sistema..."
timedatectl set-ntp true

#===============================================================================
# PARTICIONAMIENTO
#===============================================================================
log_info "Iniciando particionamiento de ${DISK}..."

# Limpiar disco (CUIDADO: BORRA TODO)
wipefs -a ${DISK}

# Crear particiones con sgdisk
sgdisk --zap-all ${DISK}
sgdisk -n1:0:+1G -t1:EF00 -c1:"EFI" ${DISK}
sgdisk -n2:0:0 -t2:8300 -c2:"Root" ${DISK}

log_info "Particiones creadas:"
lsblk ${DISK}

#===============================================================================
# FORMATEO
#===============================================================================
log_info "Formateando particiones..."

# EFI en FAT32
mkfs.fat -F32 ${BOOT_PART}

# Root en Btrfs
mkfs.btrfs -L "ArchRoot" ${ROOT_PART}

# Montar particiones
log_info "Montando particiones..."
mount ${ROOT_PART} /mnt

# Crear subvolúmenes Btrfs
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots

# Desmontar y remontar con subvolúmenes
umount /mnt
mount -o compress=zstd,subvol=@ ${ROOT_PART} /mnt
mkdir -p /mnt/{home,boot,snapshots}
mount -o compress=zstd,subvol=@home ${ROOT_PART} /mnt/home
mount -o compress=zstd,subvol=@snapshots ${ROOT_PART} /mnt/snapshots
mount ${BOOT_PART} /mnt/boot

# Crear swapfile de 16GB
log_info "Creando swapfile de 16GB..."
touch /mnt/swapfile
chattr +C /mnt/swapfile  # Desactivar COW para swap en Btrfs
dd if=/dev/zero of=/mnt/swapfile bs=1M count=16384 status=progress
chmod 600 /mnt/swapfile
mkswap /mnt/swapfile
swapon /mnt/swapfile

#===============================================================================
# INSTALACIÓN DEL SISTEMA BASE
#===============================================================================
log_info "Instalando sistema base Arch Linux..."

pacstrap -K /mnt \
    base \
    base-devel \
    linux-zen \
    linux-zen-headers \
    linux-firmware \
    nano \
    git \
    wget \
    curl \
    networkmanager \
    sudo \
    btrfs-progs \
    snapper \
    grub \
    efibootmgr \
    os-prober \
    sof-firmware \
    alsa-firmware \
    alsa-utils \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    pavucontrol \
    bluez \
    bluez-utils \
    networkmanager-bluetooth \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    nvidia-open-dkms \
    nvidia-utils \
    lib32-nvidia-utils \
    libva-nvidia-driver \
    cuda \
    docker \
    docker-compose \
    python \
    python-pip \
    git \
    steam \
    lutris \
    gamemode \
    lib32-gamemode \
    mangohud \
    lib32-mangohud \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    vulkan-tools

# Generar fstab
log_info "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

#===============================================================================
# CONFIGURACIÓN DEL SISTEMA (CHROOT)
#===============================================================================
log_info "Configurando sistema..."

# Crear script de configuración para chroot
cat << 'CHROOT_SCRIPT' > /mnt/root/setup.sh
#!/bin/bash
set -e

USERNAME="${USERNAME}"
HOSTNAME="${HOSTNAME}"
TIMEZONE="${TIMEZONE}"
LOCALE="${LOCALE}"
KEYMAP="${KEYMAP}"
DISK="${DISK}"

# Hostname
echo ${HOSTNAME} > /etc/hostname

# Hosts
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Locale
sed -i 's/^#'"${LOCALE}"'/'"${LOCALE}"'/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# NetworkManager
systemctl enable NetworkManager

# Enable os-prober para dual boot
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub

# Configurar GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Crear usuario
useradd -m -G wheel,audio,video,storage,optical,input,kvm,docker -s /bin/bash ${USERNAME}
echo "${USERNAME} ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/${USERNAME}
chmod 0440 /etc/sudoers.d/${USERNAME}

# Configurar swap en fstab
echo "/swapfile none swap sw 0 0" >> /etc/fstab

# Configurar módulos NVIDIA
cat > /etc/modprobe.d/nvidia.conf << 'EOF'
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

# Early KMS para NVIDIA
sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

# Rebuild initramfs
mkinitcpio -P

# Habilitar servicios
systemctl enable docker
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# Configurar ZRAM
cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
EOF

# Configurar swappiness
echo "vm.swappiness=60" >> /etc/sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf

# Deshabilitar power management para MediaTek Wi-Fi
cat > /etc/modprobe.d/mt7921e.conf << 'EOF'
options mt7921e disable_aspm=1
EOF

# Configurar Btrfs compression
btrfs property set / compression zstd

# Instalar yay (AUR helper)
su - ${USERNAME} -c "cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"

# Instalar Omarchy
echo "Instalando Omarchy..."
su - ${USERNAME} -c "cd /tmp && git clone https://github.com/basecamp/omarchy.git && cd omarchy && ./install.sh"

# Configurar Hyprland para NVIDIA
cat >> /home/${USERNAME}/.config/hypr/hyprland.conf << 'EOF'

# NVIDIA Optimizations
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = WLR_DRM_NO_ATOMIC,0
env = NIXOS_OZONE_WL,1

# Variables para IA y Gaming
env = __NV_PRIME_RENDER_OFFLOAD,1
env = __VK_LAYER_NV_optimus,NVIDIA_only
EOF

# Crear script de lanzamiento para juegos
mkdir -p /home/${USERNAME}/.local/bin
cat > /home/${USERNAME}/.local/bin/nvidia-game.sh << 'EOF'
#!/bin/bash
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia "$@"
EOF
chmod +x /home/${USERNAME}/.local/bin/nvidia-game.sh
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local

# Configurar Git
su - ${USERNAME} -c "git config --global user.name 'Carlos'"
su - ${USERNAME} -c "git config --global user.email 'carlos@email.com'"

# Instalar herramientas de desarrollo adicionales
su - ${USERNAME} -c "yay -S --noconfirm \
    visual-studio-code-bin \
    brave-bin \
    neovim \
    tmux \
    zsh \
    starship \
    fzf \
    ripgrep \
    bat \
    lsd \
    zoxide \
    tldr \
    htop \
    btop \
    neofetch"

# Configurar ZSH como shell por defecto
chsh -s /bin/zsh ${USERNAME}

# Crear snapshot inicial de Btrfs
snapper -c root create --description "Initial system installation"

echo "Instalación completada exitosamente!"
echo "Usuario: ${USERNAME}"
echo "Contraseña: (debes establecerla con passwd)"
CHROOT_SCRIPT

# Reemplazar variables en el script
sed -i "s/\${USERNAME}/${USERNAME}/g" /mnt/root/setup.sh
sed -i "s/\${HOSTNAME}/${HOSTNAME}/g" /mnt/root/setup.sh
sed -i "s/\${TIMEZONE}/${TIMEZONE}/g" /mnt/root/setup.sh
sed -i "s/\${LOCALE}/${LOCALE}/g" /mnt/root/setup.sh
sed -i "s/\${KEYMAP}/${KEYMAP}/g" /mnt/root/setup.sh
sed -i "s|\${DISK}|${DISK}|g" /mnt/root/setup.sh

chmod +x /mnt/root/setup.sh

# Ejecutar script en chroot
arch-chroot /mnt /root/setup.sh

# Limpiar
rm /mnt/root/setup.sh

#===============================================================================
# FINALIZACIÓN
#===============================================================================
log_info "Desmontando particiones..."
umount -R /mnt

log_info "=============================================="
log_info "¡INSTALACIÓN COMPLETADA EXITOSAMENTE!"
log_info "=============================================="
log_info "Usuario: ${USERNAME}"
log_info "Hostname: ${HOSTNAME}"
log_info "=============================================="
log_info "PRÓXIMOS PASOS:"
log_info "1. Reiniciar: reboot"
log_info "2. Remover USB de instalación"
log_info "3. Loguearte con tu usuario"
log_info "4. Configurar contraseña: passwd"
log_info "5. Configurar Wi-Fi: nmtui"
log_info "=============================================="
log_info "Atajos de Omarchy:"
log_info "Super + Alt + Space : Menú principal"
log_info "Super + Enter : Terminal"
log_info "Super + / : Ver atajos"
log_info "=============================================="

# Reiniciar
read -p "Presiona Enter para reiniciar..."
reboot
