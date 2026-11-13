#!/bin/bash
# Gentoo Automated Installer - Part 2 (Improved)
# This script runs inside the chroot environment
# It handles package installation, configuration, and system setup

set -Eeuo pipefail

# ============================================
# Configuration and initialization
# ============================================

LOG="/root/gentoo-install-part2-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

CONF="/root/gentoo-installer.conf"

# ============================================
# Utility functions
# ============================================

die() {
    echo "[FATAL] $*" >&2
    exit 1
}

# ============================================
# Pre-flight checks
# ============================================

echo
echo "=============================================="
echo " Gentoo Automated Installer — PART 2"
echo " Inside chroot: packages + configuration"
echo "=============================================="
echo

# Verify we're running as root
[[ $EUID -eq 0 ]] || die "This script must be run as root."

# Verify we're in a Gentoo system
[[ -f /etc/gentoo-release ]] || die "This does not appear to be a Gentoo system."

# Verify config file exists
[[ -f "$CONF" ]] || die "Configuration file not found: $CONF"

# Verify critical mounts
[[ -d /proc ]] || die "/proc is not mounted."
mountpoint -q /sys || die "/sys is not mounted."
mountpoint -q /dev || die "/dev is not mounted."

# Load configuration
source "$CONF"

echo "Configuration loaded:"
echo "  Profile: $PROFILE"
echo "  Init:    $INIT"
echo "  GPU:     $GPU"
echo "  Kernel:  ${KERNEL_TYPE:-gentoo-kernel}"
echo "  Root:    $ROOT"
echo "  EFI:     $EFI"
echo "  Swap:    $SWAP"
echo

# Set default kernel type if not specified
KERNEL_TYPE="${KERNEL_TYPE:-gentoo-kernel}"

# ============================================
# Calculate build parameters
# ============================================

THREADS="$(nproc)"
RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
JOBS="$THREADS"

# Adjust MAKEOPTS based on available RAM
if (( RAM_MB < 4096 )); then
    JOBS=2
    echo "[INFO] Low RAM detected (${RAM_MB}MB). Limiting MAKEOPTS to -j${JOBS}"
elif (( RAM_MB < 8192 && THREADS > 4 )); then
    JOBS=$(( (THREADS + 1) / 2 ))
    echo "[INFO] Moderate RAM (${RAM_MB}MB). Limiting MAKEOPTS to -j${JOBS}"
fi
(( JOBS < 1 )) && JOBS=1

echo "Build configuration:"
echo "  CPU threads: $THREADS"
echo "  RAM:         ${RAM_MB} MiB"
echo "  MAKEOPTS:    -j${JOBS}"
echo

# ============================================
# Portage directory structure
# ============================================

echo "Creating Portage directory structure..."
mkdir -p \
    /etc/portage/package.use \
    /etc/portage/package.accept_keywords \
    /etc/portage/package.unmask \
    /etc/portage/package.mask \
    /etc/portage/repos.conf \
    /etc/portage/binrepos.conf

# ============================================
# Portage configuration
# ============================================

echo "Configuring Portage..."

# Enable "Arch-like" package availability:
# Unmask all packages and accept ~amd64
cat > /etc/portage/package.unmask/99-installer-unmask-all <<'EOF'
# Allow all packages (hard masks still apply)
*/*
EOF

cat > /etc/portage/package.accept_keywords/99-installer-unstable-all <<'EOF'
# Accept testing branch packages globally
*/* ~amd64
EOF

# Backup and convert make.conf to directory if needed
if [[ -f /etc/portage/make.conf && ! -d /etc/portage/make.conf ]]; then
    echo "Converting make.conf to directory format..."
    cp -a /etc/portage/make.conf /etc/portage/make.conf.gentoo-installer.bak
    mv /etc/portage/make.conf /etc/portage/make.conf.stage3
    mkdir -p /etc/portage/make.conf
    mv /etc/portage/make.conf.stage3 /etc/portage/make.conf/00-stage3
fi

mkdir -p /etc/portage/make.conf

cat > /etc/portage/make.conf/00-installer <<EOF
# Gentoo Installer Settings
# Generated on $(date)

MAKEOPTS="-j${JOBS}"
GRUB_PLATFORMS="efi-64"
FEATURES="\${FEATURES-} getbinpkg binpkg-request-signature"

# Common flags for desktop systems
USE="pulseaudio alsa bluetooth wifi networkmanager dbus policykit"
EOF

# ============================================
# Package-specific USE flags
# ============================================

echo "Configuring package USE flags..."

# GPU-specific configuration
case "$GPU" in
    NVIDIA)
        cat > /etc/portage/package.use/00-video_cards <<'EOF'
# NVIDIA drivers
*/* VIDEO_CARDS: -* nvidia
EOF

        cat > /etc/portage/package.use/10-nvidia <<'EOF'
# NVIDIA driver configuration
x11-drivers/nvidia-drivers X wayland dist-kernel
EOF
        ;;
    AMD)
        cat > /etc/portage/package.use/00-video_cards <<'EOF'
# AMD drivers
*/* VIDEO_CARDS: -* amdgpu radeonsi
EOF

        cat > /etc/portage/package.use/10-amd <<'EOF'
# AMD GPU configuration
media-libs/mesa vulkan vaapi vdpau
x11-libs/libdrm video_cards_amdgpu video_cards_radeon
EOF
        ;;
    Intel)
        cat > /etc/portage/package.use/00-video_cards <<'EOF'
# Intel drivers
*/* VIDEO_CARDS: -* intel iris
EOF

        cat > /etc/portage/package.use/10-intel <<'EOF'
# Intel GPU configuration
media-libs/mesa vulkan vaapi
x11-libs/libdrm video_cards_intel
EOF
        ;;
esac

# Desktop stack USE flags
cat > /etc/portage/package.use/20-desktop-installer <<'EOF'
# PipeWire audio server
media-video/pipewire dbus sound-server pipewire-alsa pipewire-pulse bluetooth

# Wayland support
sys-apps/xdg-desktop-portal wayland
x11-base/xwayland libei
media-libs/mesa vulkan wayland
gui-apps/waybar wayland
EOF

# Init-specific USE flags
if [[ "$INIT" == systemd ]]; then
    cat > /etc/portage/package.use/05-init <<'EOF'
# systemd configuration
sys-apps/dbus systemd
media-video/pipewire systemd
media-video/wireplumber systemd
EOF
else
    cat > /etc/portage/package.use/05-init <<'EOF'
# OpenRC configuration (using elogind)
sys-apps/dbus elogind
media-video/pipewire elogind
media-video/wireplumber elogind
EOF
fi

# Profile-specific USE flags
case "$PROFILE" in
    gentoo_niri)
        cat > /etc/portage/package.use/30-niri <<'EOF'
# Niri-specific configuration
gui-apps/waybar niri
EOF
        ;;
    gentoo_hyprland)
        cat > /etc/portage/package.use/30-hyprland <<'EOF'
# Hyprland-specific configuration
gui-apps/waybar
EOF
        ;;
    gentoo_kde)
        cat > /etc/portage/package.use/30-kde <<'EOF'
# KDE Plasma configuration
kde-plasma/plasma-meta bluetooth networkmanager pulseaudio
kde-apps/dolphin semantic-desktop
media-libs/phonon pulseaudio
EOF
        ;;
esac

# ============================================
# Sync Portage tree
# ============================================

echo
echo "Syncing Portage tree (this may take several minutes)..."
emerge --sync || die "Failed to sync Portage tree"

# ============================================
# Select Gentoo profile
# ============================================

echo
echo "Selecting Gentoo profile..."

if command -v eselect >/dev/null 2>&1; then
    if [[ "$INIT" == systemd ]]; then
        PROFILE_TARGET="default/linux/amd64/23.0/desktop/systemd"
    else
        PROFILE_TARGET="default/linux/amd64/23.0/desktop"
    fi

    if eselect profile list | grep -q "$PROFILE_TARGET"; then
        eselect profile set "$PROFILE_TARGET"
        echo "Profile set to: $PROFILE_TARGET"
    else
        echo "[WARN] Profile not found: $PROFILE_TARGET"
        echo "[WARN] Keeping the Stage 3 default profile"
    fi

    echo "Current profile:"
    eselect profile show
fi

# ============================================
# Install eselect-repository
# ============================================

echo
echo "Installing eselect-repository..."
emerge --ask=n --verbose --getbinpkg \
    --autounmask=y --autounmask-write=y --autounmask-unrestricted-atoms=y \
    --backtrack=30 \
    app-eselect/eselect-repository \
    || die "Failed to install eselect-repository"

# ============================================
# Enable additional repositories
# ============================================

echo
echo "Enabling additional repositories..."

# Enable GURU for all profiles
eselect repository enable guru || die "Failed to enable GURU repository"
emaint sync -r guru || echo "[WARN] GURU sync failed, will retry later"

# Enable Hyprland overlay if needed
if [[ "$PROFILE" == gentoo_hyprland ]]; then
    eselect repository enable hyproverlay || die "Failed to enable hyproverlay"
    emaint sync -r hyproverlay || echo "[WARN] hyproverlay sync failed, will retry later"

    cat > /etc/portage/package.accept_keywords/hyproverlay <<'EOF'
# Accept all packages from hyproverlay
*/*::hyproverlay
EOF
fi

# Apply any auto-generated config changes
etc-update --automode -5 || true

# ============================================
# Smart emerge wrapper with retry logic
# ============================================

portage_emerge() {
    local tries=1
    local max=4
    local -a args=("$@")

    while (( tries <= max )); do
        echo
        echo ">>> Emerge attempt $tries/$max: ${args[*]}"

        if emerge --ask=n --verbose \
            --autounmask=y \
            --autounmask-write=y \
            --autounmask-unrestricted-atoms=y \
            --backtrack=30 \
            --with-bdeps=y \
            --getbinpkg \
            "${args[@]}"; then
            return 0
        fi

        echo "[WARN] Emerge failed on attempt $tries/$max"
        echo "[INFO] Applying generated Portage configuration and retrying..."
        etc-update --automode -5 || true
        ((tries++))
    done

    echo "[ERROR] Emerge failed after $max attempts"
    return 1
}

# ============================================
# Install base system packages
# ============================================

echo
echo "Installing base system packages..."
echo "This will take a significant amount of time..."

portage_emerge \
    app-admin/sudo \
    app-editors/vim \
    app-editors/nano \
    dev-vcs/git \
    net-misc/curl \
    net-misc/wget \
    net-misc/rsync \
    sys-process/btop \
    sys-apps/man-pages \
    sys-apps/pciutils \
    sys-apps/usbutils \
    net-misc/openssh \
    net-misc/networkmanager \
    sys-apps/dbus \
    sys-auth/polkit \
    sys-auth/seatd \
    media-video/pipewire \
    media-video/wireplumber \
    media-libs/mesa \
    media-libs/libglvnd \
    media-libs/vulkan-loader \
    dev-libs/wayland \
    dev-libs/wayland-protocols \
    dev-libs/libinput \
    app-misc/wayland-utils \
    x11-base/xwayland \
    x11-base/xorg-proto \
    x11-libs/libX11 \
    x11-libs/libXext \
    x11-libs/libXrandr \
    x11-libs/libXrender \
    x11-libs/libXi \
    x11-libs/libXfixes \
    sys-apps/xdg-desktop-portal \
    app-shells/bash-completion \
    || die "Failed to install base packages"

# ============================================
# Install hardware support packages
# ============================================

echo
echo "Installing hardware support (GPU drivers, firmware, Bluetooth)..."

# GPU-specific drivers
case "$GPU" in
    NVIDIA)
        echo "Installing NVIDIA drivers..."
        portage_emerge x11-drivers/nvidia-drivers || true
        ;;
    AMD)
        echo "Installing AMD drivers..."
        portage_emerge \
            x11-drivers/xf86-video-amdgpu \
            dev-libs/amdgpu-pro-opencl \
            || true
        ;;
    Intel)
        echo "Installing Intel drivers..."
        portage_emerge \
            x11-drivers/xf86-video-intel \
            media-libs/intel-mediasdk \
            || true
        ;;
esac

portage_emerge \
    sys-kernel/linux-firmware \
    net-wireless/bluez \
    || die "Failed to install hardware support packages"

# ============================================
# Hostname configuration
# ============================================

echo
echo "==================================="
echo " HOSTNAME CONFIGURATION"
echo "==================================="
read -r -p "Enter hostname (default: gentoo): " HOSTNAME

HOSTNAME="${HOSTNAME:-gentoo}"
[[ "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] || die "Invalid hostname format"

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
# /etc/hosts: static host lookup table
# Generated by Gentoo Installer

127.0.0.1   $HOSTNAME localhost
::1         $HOSTNAME localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

if [[ "$INIT" == systemd ]]; then
    hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || true
else
    mkdir -p /etc/conf.d
    echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname
fi

echo "Hostname set to: $HOSTNAME"

# ============================================
# User account setup
# ============================================

echo
echo "==================================="
echo " USER ACCOUNT SETUP"
echo "==================================="
echo
echo "Setting root password..."
passwd root || die "Failed to set root password"

echo
read -r -p "Enter new username: " USERNAME
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username format"

if id "$USERNAME" >/dev/null 2>&1; then
    die "User '$USERNAME' already exists"
fi

# Ensure required groups exist
for g in wheel video audio render input; do
    getent group "$g" >/dev/null || groupadd "$g"
done

# Add 'seat' group if it exists (for seatd)
EXTRA_GROUPS=""
if getent group seat >/dev/null; then
    EXTRA_GROUPS=",seat"
fi

echo "Creating user: $USERNAME"
useradd -m -s /bin/bash -G "wheel,video,audio,render,input${EXTRA_GROUPS}" "$USERNAME" \
    || die "Failed to create user"

echo
echo "Setting password for $USERNAME..."
passwd "$USERNAME" || die "Failed to set user password"

# Configure sudo for wheel group
install -d -m 0750 /etc/sudoers.d
cat > /etc/sudoers.d/10-wheel <<'EOF'
# Allow members of group wheel to execute any command
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/10-wheel

# Validate sudoers configuration
visudo -c || die "Sudoers configuration is invalid"

echo "User '$USERNAME' created successfully"

# ============================================
# Kernel installation
# ============================================

echo
echo "==================================="
echo " KERNEL INSTALLATION"
echo "==================================="

case "$KERNEL_TYPE" in
    distribution-kernel)
        echo "Installing gentoo-kernel-bin (binary kernel)..."
        portage_emerge sys-kernel/gentoo-kernel-bin \
            || die "Failed to install binary kernel"
        ;;

    gentoo-kernel)
        echo "Installing gentoo-kernel (auto-configured source kernel)..."
        echo "This will take a considerable amount of time..."
        portage_emerge --usepkg=n --buildpkg=n sys-kernel/gentoo-kernel \
            || die "Failed to install kernel"
        ;;

    gentoo-sources)
        echo "Installing gentoo-sources (manual configuration required)..."
        portage_emerge sys-kernel/gentoo-sources \
            || die "Failed to install kernel sources"

        echo
        echo "Installing kernel build tools..."
        portage_emerge sys-apps/pciutils sys-kernel/genkernel \
            || die "Failed to install build tools"

        echo
        echo "=============================================="
        echo " MANUAL KERNEL CONFIGURATION"
        echo "=============================================="
        echo
        echo "The kernel sources are installed at /usr/src/linux"
        echo "You will need to configure and build the kernel manually."
        echo
        read -r -p "Do you want to configure the kernel now? [yes/NO]: " CONFIGURE_NOW

        if [[ "$CONFIGURE_NOW" == "yes" ]]; then
            cd /usr/src/linux || die "Failed to change to kernel directory"

            echo
            echo "Kernel configuration methods:"
            echo "  1) menuconfig       - Interactive menu-based configuration"
            echo "  2) localyesconfig   - Minimal config based on current hardware"
            echo "  3) defconfig        - Default generic configuration"
            select KCONFIG in menuconfig localyesconfig defconfig; do
                [[ -n "${KCONFIG:-}" ]] && break
            done

            case "$KCONFIG" in
                menuconfig)
                    make menuconfig || die "Kernel configuration failed"
                    ;;
                localyesconfig)
                    make localyesconfig || die "Kernel configuration failed"
                    echo "Configuration completed with localyesconfig"
                    ;;
                defconfig)
                    make defconfig || die "Kernel configuration failed"
                    echo "Configuration completed with defconfig"
                    ;;
            esac

            echo
            echo "Building kernel (this will take a very long time)..."
            make -j${JOBS} || die "Kernel build failed"
            make modules_install || die "Module installation failed"
            make install || die "Kernel installation failed"

            echo
            echo "Generating initramfs with genkernel..."
            genkernel --install --kernel-config=/usr/src/linux/.config initramfs \
                || die "Initramfs generation failed"

            echo "Kernel built and installed successfully"
        else
            echo
            echo "================================================================"
            echo " KERNEL CONFIGURATION SKIPPED"
            echo "================================================================"
            echo
            echo "IMPORTANT: You must manually configure and build the kernel"
            echo "after installation before the system can boot!"
            echo
            echo "Steps to complete kernel setup:"
            echo "  1. cd /usr/src/linux"
            echo "  2. make menuconfig  (or localyesconfig/defconfig)"
            echo "  3. make -j${JOBS} && make modules_install && make install"
            echo "  4. genkernel --install --kernel-config=/usr/src/linux/.config initramfs"
            echo "  5. grub-mkconfig -o /boot/grub/grub.cfg"
            echo
            echo "================================================================"
            read -r -p "Press Enter to continue installation..."
        fi
        ;;

    *)
        die "Unknown kernel type: $KERNEL_TYPE"
        ;;
esac

# ============================================
# System services configuration
# ============================================

echo
echo "Configuring system services..."

if [[ "$INIT" == systemd ]]; then
    echo "Configuring systemd services..."

    systemd-machine-id-setup || true
    systemctl preset-all --preset-mode=enable-only || true

    systemctl enable NetworkManager.service || echo "[WARN] Failed to enable NetworkManager"
    systemctl enable sshd.service || echo "[WARN] Failed to enable sshd"
    systemctl enable bluetooth.service || echo "[WARN] Failed to enable bluetooth"

    echo "systemd services configured"
else
    echo "Configuring OpenRC services..."

    rc-update add dbus default || echo "[WARN] Failed to add dbus to default runlevel"
    rc-update add NetworkManager default || echo "[WARN] Failed to add NetworkManager"
    rc-update add sshd default || echo "[WARN] Failed to add sshd"
    rc-update add bluetooth default || echo "[WARN] Failed to add bluetooth"
    rc-update add elogind boot || echo "[WARN] Failed to add elogind to boot runlevel"

    echo "OpenRC services configured"
fi

# ============================================
# Profile-specific packages
# ============================================

echo
echo "Installing profile-specific packages..."

case "$PROFILE" in
    gentoo_base)
        echo "Base profile: no additional compositor packages"
        ;;

    gentoo_niri)
        echo "Installing Niri and related packages..."
        portage_emerge \
            gui-wm/niri::guru \
            gui-apps/waybar \
            gui-apps/fuzzel \
            gui-apps/mako \
            gui-apps/swaybg \
            gui-apps/swayidle \
            gui-apps/swaylock \
            x11-misc/ly::guru \
            || echo "[WARN] Some Niri packages failed to install"
        ;;

    gentoo_hyprland)
        echo "Installing Hyprland and related packages..."
        portage_emerge \
            gui-wm/hyprland \
            gui-apps/waybar \
            sys-apps/xdg-desktop-portal-hyprland \
            gui-apps/hyprlock \
            gui-apps/hypridle \
            gui-apps/hyprpaper \
            gui-apps/hyprpicker \
            x11-misc/ly::guru \
            || echo "[WARN] Some Hyprland packages failed to install"
        ;;

    gentoo_kde)
        echo "Installing KDE Plasma and related packages..."
        portage_emerge \
            kde-plasma/plasma-meta \
            kde-apps/konsole \
            kde-apps/dolphin \
            kde-apps/kate \
            sys-apps/xdg-desktop-portal-kde \
            kde-plasma/sddm-kcm \
            x11-misc/sddm \
            || echo "[WARN] Some KDE packages failed to install"
        ;;
esac

# ============================================
# Display manager configuration
# ============================================

if [[ "$PROFILE" != gentoo_base ]]; then
    if [[ "$PROFILE" == gentoo_kde ]]; then
        echo "Configuring display manager (SDDM)..."

        if [[ "$INIT" == systemd ]]; then
            if systemctl list-unit-files sddm.service >/dev/null 2>&1; then
                systemctl enable sddm.service
                echo "SDDM service enabled"
            else
                echo "[WARN] sddm.service not found."
            fi
        else
            if [[ -x /etc/init.d/sddm ]]; then
                rc-update add sddm default
                echo "SDDM service enabled"
            else
                echo "[WARN] /etc/init.d/sddm not found."
            fi
        fi
    else
        echo "Configuring display manager (Ly)..."

        if [[ "$INIT" == systemd ]]; then
            if systemctl list-unit-files ly.service >/dev/null 2>&1; then
                systemctl enable ly.service
                echo "Ly service enabled"
            else
                echo "[WARN] ly.service not found. You may need to configure a display manager manually."
            fi
        else
            if [[ -x /etc/init.d/ly ]]; then
                rc-update add ly default
                echo "Ly service enabled"
            else
                echo "[WARN] /etc/init.d/ly not found. You may need to configure a display manager manually."
            fi
        fi
    fi
fi

# ============================================
# Locale configuration
# ============================================

echo
echo "Configuring locales..."

if [[ -f /etc/locale.gen ]]; then
    # Enable en_US.UTF-8
    sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    locale-gen || true
fi

# Set default locale
printf 'LANG="en_US.UTF-8"\n' > /etc/env.d/02locale
env-update

echo "Locale set to en_US.UTF-8"

# ============================================
# Final world rebuild
# ============================================

echo
echo "==================================="
echo " FINAL SYSTEM REBUILD"
echo "==================================="
echo "Rebuilding @world with new USE flags and profile..."
echo "This ensures all packages are properly configured..."
echo

portage_emerge @world || echo "[WARN] World rebuild had some issues"

# ============================================
# Bootloader installation
# ============================================

echo
echo "==================================="
echo " BOOTLOADER INSTALLATION"
echo "==================================="
echo "Installing and configuring GRUB..."

portage_emerge sys-boot/grub || die "Failed to install GRUB"

echo "Installing GRUB to EFI..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo --recheck \
    || die "Failed to install GRUB"

echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg \
    || die "Failed to generate GRUB config"

echo "GRUB installation complete"

# ============================================
# Generate installation summary
# ============================================

cat > /root/gentoo-install-summary.txt <<EOF
================================================================================
                     GENTOO INSTALLATION SUMMARY
================================================================================

Installation completed: $(date)

SYSTEM CONFIGURATION
--------------------
Hostname:       $HOSTNAME
User:           $USERNAME
Profile:        $PROFILE
Init system:    $INIT

HARDWARE
--------
CPU threads:    $THREADS
RAM:            ${RAM_MB} MiB
MAKEOPTS:       -j${JOBS}

PARTITIONS
----------
Root:           $ROOT
EFI:            $EFI
Swap:           $SWAP

REPOSITORIES
------------
- gentoo (main)
- guru
$( [[ "$PROFILE" == gentoo_hyprland ]] && echo "- hyproverlay" )

IMPORTANT NOTES
---------------
1. sys-kernel/gentoo-kernel is installed (source-based, not gentoo-kernel-bin)
2. x11-base/xwayland is installed for compatibility
3. NVIDIA drivers are configured via package.use
4. Global ~amd64 keywords are enabled (Arch-like package availability)
5. sudo is configured for the wheel group

KERNEL
------
Kernel type: $KERNEL_TYPE
$( [[ "$KERNEL_TYPE" == "gentoo-sources" && "$CONFIGURE_NOW" != "yes" ]] && echo "WARNING: Manual kernel configuration required!" )
$(ls -1 /boot/vmlinuz-* 2>/dev/null | tail -1 || echo "Kernel files not found (manual build required)")

NEXT STEPS
----------
1. Exit the chroot environment:
   $ exit

2. Unmount all filesystems:
   $ umount -R /mnt/gentoo

3. Reboot:
   $ reboot

4. After reboot:
   - Log in as $USERNAME
   - Check network: nmtui or nmcli
   - Update system: emerge --sync && emerge -uDN @world

LOGS
----
Part 1 log: /root/gentoo-install-part1.log
Part 2 log: $LOG

================================================================================
EOF

# Save final log
cp "$LOG" /root/gentoo-install-part2-final.log || true

# ============================================
# Display completion message
# ============================================

echo
echo "=============================================="
echo " INSTALLATION COMPLETED SUCCESSFULLY"
echo "=============================================="
echo
cat /root/gentoo-install-summary.txt
echo
echo "Installation summary saved to: /root/gentoo-install-summary.txt"
echo "Log saved to: /root/gentoo-install-part2-final.log"
echo
echo "To inspect the system before rebooting, you can run:"
echo "  emerge --info"
echo "  eselect profile show"
echo "  eselect repository list"
echo "  emerge -pv @world"
echo
echo "When ready to reboot:"
echo "  1. exit        # Exit chroot"
echo "  2. umount -R /mnt/gentoo"
echo "  3. reboot"
echo
