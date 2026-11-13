#!/bin/bash
# Gentoo Unified Installer (All-in-One)
# Inspired by archinstall - handles everything in a single script
# Automatically handles both pre-chroot and chroot phases

set -Eeuo pipefail

# ============================================
# GLOBAL CONFIGURATION
# ============================================

VERSION="1.0.0"
LOG_DIR="/tmp"
TARGET="/mnt/gentoo"
DIST="https://distfiles.gentoo.org/releases/amd64/autobuilds"
MIN_RAM_MB=2048
MIN_DISK_GB=20

# State file to track installation progress
STATE_FILE="/tmp/gentoo-install-state.conf"

# ============================================
# UTILITY FUNCTIONS
# ============================================

die() {
    echo "[FATAL] $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

confirm() {
    local prompt="$1" ans
    read -r -p "$prompt [yes/NO]: " ans
    [[ "$ans" == "yes" ]]
}

print_header() {
    echo
    echo "=============================================="
    echo " $*"
    echo "=============================================="
    echo
}

print_section() {
    echo
    echo "==================================="
    echo " $*"
    echo "==================================="
}

check_network() {
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        die "No network connectivity. Please check your connection."
    fi
}

check_requirements() {
    local ram_mb
    ram_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
    if (( ram_mb < MIN_RAM_MB )); then
        die "Insufficient RAM: ${ram_mb}MB (minimum ${MIN_RAM_MB}MB required)"
    fi

    check_network
}

# ============================================
# PHASE DETECTION
# ============================================

detect_phase() {
    # Determine if we're in the live environment or chroot
    if [[ -f "$STATE_FILE" ]]; then
        # State file exists, check what phase we're in
        source "$STATE_FILE"
        if [[ "${PHASE:-}" == "chroot" ]]; then
            return 1  # In chroot
        fi
    fi

    # Check if we're in chroot by looking at root filesystem
    if [[ -f /root/gentoo-installer.conf && -f /etc/gentoo-release ]]; then
        return 1  # In chroot
    fi

    return 0  # In live environment
}

# ============================================
# DISK MANAGEMENT FUNCTIONS
# ============================================

cleanup_disk_state() {
    local disk="$1"
    local part target
    echo "Releasing old mount/swap state for $disk..."

    while read -r part; do
        [[ -n "$part" ]] || continue
        while read -r target; do
            [[ -n "$target" ]] || continue
            echo "  Unmounting: $target"
            umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null || true
        done < <(findmnt -rn -S "$part" -o TARGET 2>/dev/null || true)
    done < <(lsblk -nrpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}')

    while read -r part; do
        [[ -n "$part" ]] || continue
        if grep -qE "^$part " /proc/swaps 2>/dev/null; then
            echo "  Disabling swap: $part"
            swapoff "$part" || true
        fi
    done < <(lsblk -nrpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}')

    sync
    sleep 1
}

reread_partition_table() {
    local disk="$1"
    echo "Refreshing kernel partition table..."
    partprobe "$disk" 2>/dev/null || true
    partx -u "$disk" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 2
}

validate_disk() {
    local disk="$1"
    [[ -b "$disk" ]] || die "Not a block device: $disk"
    [[ "$(lsblk -dn -o TYPE "$disk")" == "disk" ]] || die "A whole disk is required, not a partition."

    local size_gb
    size_gb="$(lsblk -dn -o SIZE -b "$disk" | awk '{print int($1/1024/1024/1024)}')"
    if (( size_gb < MIN_DISK_GB )); then
        die "Disk too small: ${size_gb}GB (minimum ${MIN_DISK_GB}GB required)"
    fi
}

# ============================================
# PORTAGE EMERGE WRAPPER
# ============================================

portage_emerge() {
    local tries=1
    local max=4
    local -a args=("$@")

    while (( tries <= max )); do
        echo ">>> Emerge attempt $tries/$max"

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
        etc-update --automode -5 || true
        ((tries++))
    done

    return 1
}

# ============================================
# PHASE 1: PRE-CHROOT (LIVE ENVIRONMENT)
# ============================================

phase1_live_environment() {
    local LOG="$LOG_DIR/gentoo-install-phase1-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$LOG") 2>&1
    trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

    print_header "Gentoo Unified Installer v${VERSION} - PHASE 1"

    # Root check
    [[ $EUID -eq 0 ]] || die "This script must be run as root."

    # UEFI check
    [[ -d /sys/firmware/efi ]] || die "System not booted in UEFI mode."

    # Check required tools
    for cmd in awk curl findmnt lsblk mount umount mkfs.fat mkfs.ext4 mkswap swapoff sfdisk partprobe partx udevadm wipefs blkid tar sha256sum sed grep; do
        need "$cmd"
    done

    check_requirements

    # ================================
    # User Input
    # ================================

    echo "Available block devices:"
    lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
    echo

    read -r -p "Installation disk (e.g. /dev/nvme0n1 or /dev/sda): " DISK
    validate_disk "$DISK"

    echo
    echo "Profile selection:"
    echo "  1) gentoo_base     - Base desktop-ready system"
    echo "  2) gentoo_niri     - Base + Niri compositor"
    echo "  3) gentoo_hyprland - Base + Hyprland"
    echo "  4) gentoo_kde      - Base + KDE Plasma"
    select PROFILE in gentoo_base gentoo_niri gentoo_hyprland gentoo_kde; do
        [[ -n "${PROFILE:-}" ]] && break
    done

    echo
    echo "Init system:"
    select INIT in systemd OpenRC; do
        [[ -n "${INIT:-}" ]] && break
    done

    echo
    echo "GPU vendor:"
    select GPU in NVIDIA AMD Intel; do
        [[ -n "${GPU:-}" ]] && break
    done

    echo
    echo "Kernel type:"
    echo "  1) distribution-kernel    - Gentoo binary kernel (fast, recommended)"
    echo "  2) gentoo-kernel          - Auto-configured source kernel (builds locally)"
    echo "  3) gentoo-sources         - Manual kernel configuration (advanced)"
    select KERNEL_TYPE in distribution-kernel gentoo-kernel gentoo-sources; do
        [[ -n "${KERNEL_TYPE:-}" ]] && break
    done

    echo
    echo "Partitioning mode:"
    select PARTMODE in automatic cfdisk; do
        [[ -n "${PARTMODE:-}" ]] && break
    done

    if [[ "$PARTMODE" == automatic ]]; then
        echo
        echo "Swap configuration:"
        select SWAP_CHOICE in yes no; do
            [[ -n "${SWAP_CHOICE:-}" ]] && break
        done

        if [[ "$SWAP_CHOICE" == yes ]]; then
            local ram_gb
            ram_gb="$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)"
            local suggested_swap="${ram_gb}G"
            (( ram_gb >= 16 )) && suggested_swap="16G"

            read -r -p "Swap size (suggested: ${suggested_swap}): " SWAP_SIZE
            SWAP_SIZE="${SWAP_SIZE:-$suggested_swap}"
            SWAP_SIZE="${SWAP_SIZE// /}"
            [[ "$SWAP_SIZE" =~ ^[1-9][0-9]*[MG]$ ]] || die "Invalid swap size"
        else
            SWAP_SIZE="NONE"
        fi
    fi

    echo
    echo "Configuration summary:"
    echo "  Disk:    $DISK"
    echo "  Profile: $PROFILE"
    echo "  Init:    $INIT"
    echo "  GPU:     $GPU"
    echo "  Kernel:  $KERNEL_TYPE"
    echo "  Mode:    $PARTMODE"
    [[ "${SWAP_SIZE:-}" != "" ]] && echo "  Swap:    ${SWAP_SIZE}"
    echo

    # ================================
    # Partitioning
    # ================================

    if [[ "$PARTMODE" == automatic ]]; then
        confirm "WARNING: $DISK will be COMPLETELY ERASED. Continue?" || die "Cancelled."

        cleanup_disk_state "$DISK"
        umount -R "$TARGET" 2>/dev/null || true
        mkdir -p "$TARGET"

        echo "Wiping disk..."
        wipefs -af "$DISK"
        sfdisk --delete "$DISK" 2>/dev/null || true
        sync

        echo "Creating partitions..."
        if [[ "$SWAP_SIZE" == "NONE" ]]; then
            sfdisk "$DISK" <<EOF
label: gpt
,1G,U
,,L
EOF
        else
            sfdisk "$DISK" <<EOF
label: gpt
,1G,U
,$SWAP_SIZE,S
,,L
EOF
        fi
        reread_partition_table "$DISK"

        mapfile -t PARTS < <(lsblk -nrpo NAME,TYPE "$DISK" | awk '$2=="part"{print $1}')
        if [[ "$SWAP_SIZE" == "NONE" ]]; then
            EFI="${PARTS[0]}"
            SWAP="NONE"
            ROOT="${PARTS[1]}"
        else
            EFI="${PARTS[0]}"
            SWAP="${PARTS[1]}"
            ROOT="${PARTS[2]}"
        fi
    else
        cleanup_disk_state "$DISK"
        cfdisk "$DISK"
        reread_partition_table "$DISK"

        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"
        echo

        read -r -p "EFI partition: " EFI
        read -r -p "ROOT partition: " ROOT
        read -r -p "SWAP partition (or NONE): " SWAP
        [[ -n "$SWAP" ]] || SWAP="NONE"

        [[ -b "$EFI" ]] || die "EFI partition not found"
        [[ -b "$ROOT" ]] || die "ROOT partition not found"
        [[ "$SWAP" == "NONE" || -b "$SWAP" ]] || die "SWAP partition not found"
    fi

    # ================================
    # Format filesystems
    # ================================

    echo
    echo "Formatting filesystems..."
    mkfs.fat -F 32 "$EFI"
    mkfs.ext4 -F "$ROOT"
    if [[ "$SWAP" != "NONE" ]]; then
        mkswap "$SWAP"
        swapon "$SWAP"
    fi

    # ================================
    # Mount
    # ================================

    echo "Mounting filesystems..."
    mkdir -p "$TARGET"
    mount "$ROOT" "$TARGET"
    mkdir -p "$TARGET/efi"
    mount "$EFI" "$TARGET/efi"

    mkdir -p "$TARGET/var/cache/binpkgs" \
             "$TARGET/etc/portage/repos.conf" \
             "$TARGET/etc/portage/binrepos.conf"

    # ================================
    # Download and extract Stage 3
    # ================================

    case "$INIT" in
        systemd) STAGE_DIR="current-stage3-amd64-systemd"; BIN_PROFILE="23.0/x86-64" ;;
        OpenRC)  STAGE_DIR="current-stage3-amd64-openrc";  BIN_PROFILE="23.0/x86-64" ;;
    esac

    META_URL="$DIST/$STAGE_DIR/latest-stage3-amd64-${INIT,,}.txt"
    TMPDIR="$(mktemp -d /tmp/gentoo-stage3.XXXXXX)"
    trap 'rm -rf "$TMPDIR"' EXIT

    echo
    echo "Downloading Stage 3..."
    curl -fL --retry 5 --retry-all-errors --connect-timeout 30 -o "$TMPDIR/latest.txt" "$META_URL" \
        || die "Failed to download Stage 3 metadata"

    STAGE_FILE="$(awk '$1 ~ /^stage3-amd64-.*\.tar\.xz$/ {print $1; exit}' "$TMPDIR/latest.txt")"
    [[ -n "$STAGE_FILE" ]] || die "Stage 3 file not found"

    STAGE_URL="$DIST/$STAGE_DIR/$STAGE_FILE"
    SHA_URL="$STAGE_URL.sha256"

    echo "Downloading: $STAGE_FILE"
    curl -fL --retry 5 --retry-all-errors --connect-timeout 30 -o "$TMPDIR/$STAGE_FILE" "$STAGE_URL" \
        || die "Failed to download Stage 3"
    curl -fL --retry 5 --retry-all-errors --connect-timeout 30 -o "$TMPDIR/$STAGE_FILE.sha256" "$SHA_URL" \
        || die "Failed to download checksum"

    cd "$TMPDIR"
    echo "Verifying checksum..."
    sha256sum -c "$STAGE_FILE.sha256" || die "Checksum verification failed"

    echo "Extracting Stage 3..."
    tar xpf "$TMPDIR/$STAGE_FILE" -C "$TARGET" --xattrs-include='*.*' --numeric-owner \
        || die "Failed to extract Stage 3"

    # ================================
    # Configure Portage
    # ================================

    cat > "$TARGET/etc/portage/repos.conf/gentoo.conf" <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-webrsync-verify-signature = true
EOF

    cat > "$TARGET/etc/portage/binrepos.conf/gentoobinhost.conf" <<EOF
[binhost]
priority = 9999
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/${BIN_PROFILE}/
EOF

    # ================================
    # Generate fstab
    # ================================

    cat > "$TARGET/etc/fstab" <<EOF
# /etc/fstab
UUID=$(blkid -s UUID -o value "$ROOT") / ext4 defaults,noatime 0 1
UUID=$(blkid -s UUID -o value "$EFI") /efi vfat defaults,noatime 0 2
EOF
    if [[ "$SWAP" != "NONE" ]]; then
        echo "UUID=$(blkid -s UUID -o value "$SWAP") none swap sw 0 0" >> "$TARGET/etc/fstab"
    fi

    # ================================
    # Save configuration
    # ================================

    cat > "$TARGET/root/gentoo-installer.conf" <<EOF
PROFILE="$PROFILE"
INIT="$INIT"
GPU="$GPU"
KERNEL_TYPE="$KERNEL_TYPE"
DISK="$DISK"
EFI="$EFI"
ROOT="$ROOT"
SWAP="$SWAP"
STAGE3="$STAGE_FILE"
EOF

    # Copy this script to chroot
    SCRIPT_PATH="$(readlink -f "$0")"
    cp "$SCRIPT_PATH" "$TARGET/root/gentoo-install-unified.sh"
    chmod +x "$TARGET/root/gentoo-install-unified.sh"

    # Copy resolv.conf
    [[ -f /etc/resolv.conf ]] && cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf"

    # Save state
    cat > "$STATE_FILE" <<EOF
PHASE="chroot"
DISK="$DISK"
PROFILE="$PROFILE"
INIT="$INIT"
EOF
    cp "$STATE_FILE" "$TARGET/tmp/"

    print_header "PHASE 1 COMPLETE"

    echo "Preparing to enter chroot..."
    echo "Mounting virtual filesystems..."

    mount --types proc /proc "$TARGET/proc"
    mount --rbind /sys "$TARGET/sys"
    mount --make-rslave "$TARGET/sys"
    mount --rbind /dev "$TARGET/dev"
    mount --make-rslave "$TARGET/dev"
    mount --rbind /run "$TARGET/run"
    mount --make-rslave "$TARGET/run"

    echo
    echo "Entering chroot and continuing installation..."
    echo

    # Enter chroot and run phase 2
    chroot "$TARGET" /bin/bash -c "source /etc/profile && /root/gentoo-install-unified.sh"

    # After chroot completes
    print_header "INSTALLATION COMPLETE"
    echo
    echo "To finalize:"
    echo "  1. exit (if needed)"
    echo "  2. umount -R /mnt/gentoo"
    echo "  3. reboot"
    echo
}

# ============================================
# PHASE 2: IN-CHROOT
# ============================================

phase2_chroot() {
    local LOG="/root/gentoo-install-phase2-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$LOG") 2>&1
    trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR

    print_header "Gentoo Unified Installer - PHASE 2 (Chroot)"

    [[ $EUID -eq 0 ]] || die "Must be run as root"
    [[ -f /etc/gentoo-release ]] || die "Not in a Gentoo system"
    [[ -f /root/gentoo-installer.conf ]] || die "Configuration file not found"

    source /root/gentoo-installer.conf

    echo "Configuration loaded:"
    echo "  Profile: $PROFILE"
    echo "  Init:    $INIT"

    # ================================
    # Calculate build parameters
    # ================================

    THREADS="$(nproc)"
    RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
    JOBS="$THREADS"

    if (( RAM_MB < 4096 )); then
        JOBS=2
    elif (( RAM_MB < 8192 && THREADS > 4 )); then
        JOBS=$(( (THREADS + 1) / 2 ))
    fi
    (( JOBS < 1 )) && JOBS=1

    echo "Build config: -j${JOBS} (${THREADS} threads, ${RAM_MB}MB RAM)"

    # ================================
    # Portage setup
    # ================================

    print_section "Portage Configuration"

    mkdir -p /etc/portage/{package.use,package.accept_keywords,package.unmask,package.mask,repos.conf,binrepos.conf}

    cat > /etc/portage/package.unmask/99-installer-unmask-all <<'EOF'
*/*
EOF

    cat > /etc/portage/package.accept_keywords/99-installer-unstable-all <<'EOF'
*/* ~amd64
EOF

    if [[ -f /etc/portage/make.conf && ! -d /etc/portage/make.conf ]]; then
        cp -a /etc/portage/make.conf /etc/portage/make.conf.bak
        mv /etc/portage/make.conf /etc/portage/make.conf.stage3
        mkdir -p /etc/portage/make.conf
        mv /etc/portage/make.conf.stage3 /etc/portage/make.conf/00-stage3
    fi

    mkdir -p /etc/portage/make.conf
    cat > /etc/portage/make.conf/00-installer <<EOF
MAKEOPTS="-j${JOBS}"
GRUB_PLATFORMS="efi-64"
FEATURES="\${FEATURES-} getbinpkg binpkg-request-signature"
USE="pulseaudio alsa bluetooth wifi networkmanager dbus policykit"
EOF

    # GPU-specific configuration
    case "$GPU" in
        NVIDIA)
            cat > /etc/portage/package.use/00-video_cards <<'EOF'
*/* VIDEO_CARDS: -* nvidia
EOF

            cat > /etc/portage/package.use/10-nvidia <<'EOF'
x11-drivers/nvidia-drivers X wayland dist-kernel
EOF
            ;;
        AMD)
            cat > /etc/portage/package.use/00-video_cards <<'EOF'
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
*/* VIDEO_CARDS: -* intel iris
EOF

            cat > /etc/portage/package.use/10-intel <<'EOF'
# Intel GPU configuration
media-libs/mesa vulkan vaapi
x11-libs/libdrm video_cards_intel
EOF
            ;;
    esac

    cat > /etc/portage/package.use/20-desktop <<'EOF'
media-video/pipewire dbus sound-server pipewire-alsa pipewire-pulse bluetooth
sys-apps/xdg-desktop-portal wayland
x11-base/xwayland libei
media-libs/mesa vulkan wayland
gui-apps/waybar wayland
EOF

    if [[ "$INIT" == systemd ]]; then
        cat > /etc/portage/package.use/05-init <<'EOF'
sys-apps/dbus systemd
media-video/pipewire systemd
media-video/wireplumber systemd
EOF
    else
        cat > /etc/portage/package.use/05-init <<'EOF'
sys-apps/dbus elogind
media-video/pipewire elogind
media-video/wireplumber elogind
EOF
    fi

    # ================================
    # Sync and profile
    # ================================

    echo "Syncing Portage tree..."
    emerge --sync

    if [[ "$INIT" == systemd ]]; then
        PROFILE_TARGET="default/linux/amd64/23.0/desktop/systemd"
    else
        PROFILE_TARGET="default/linux/amd64/23.0/desktop"
    fi

    if eselect profile list | grep -q "$PROFILE_TARGET"; then
        eselect profile set "$PROFILE_TARGET"
    fi

    # ================================
    # Repositories
    # ================================

    echo "Installing eselect-repository..."
    portage_emerge app-eselect/eselect-repository

    eselect repository enable guru
    emaint sync -r guru || true

    if [[ "$PROFILE" == gentoo_hyprland ]]; then
        eselect repository enable hyproverlay
        emaint sync -r hyproverlay || true
        cat > /etc/portage/package.accept_keywords/hyproverlay <<'EOF'
*/*::hyproverlay
EOF
    fi

    etc-update --automode -5 || true

    # ================================
    # Install base packages
    # ================================

    print_section "Installing Base Packages"

    portage_emerge \
        app-admin/sudo app-editors/vim app-editors/nano \
        dev-vcs/git net-misc/curl net-misc/wget net-misc/rsync \
        sys-process/btop sys-apps/man-pages sys-apps/pciutils sys-apps/usbutils \
        net-misc/openssh net-misc/networkmanager \
        sys-apps/dbus sys-auth/polkit sys-auth/seatd \
        media-video/pipewire media-video/wireplumber \
        media-libs/mesa media-libs/vulkan-loader \
        dev-libs/wayland dev-libs/wayland-protocols \
        x11-base/xwayland sys-apps/xdg-desktop-portal \
        app-shells/bash-completion

    print_section "Installing Hardware Support"

    # GPU-specific drivers
    case "$GPU" in
        NVIDIA)
            portage_emerge x11-drivers/nvidia-drivers || true
            ;;
        AMD)
            portage_emerge \
                x11-drivers/xf86-video-amdgpu \
                dev-libs/amdgpu-pro-opencl \
                || true
            ;;
        Intel)
            portage_emerge \
                x11-drivers/xf86-video-intel \
                media-libs/intel-mediasdk \
                || true
            ;;
    esac

    portage_emerge \
        sys-kernel/linux-firmware \
        net-wireless/bluez

    # ================================
    # Hostname and users
    # ================================

    print_section "System Configuration"

    read -r -p "Hostname (default: gentoo): " HOSTNAME
    HOSTNAME="${HOSTNAME:-gentoo}"
    echo "$HOSTNAME" > /etc/hostname

    cat > /etc/hosts <<EOF
127.0.0.1   $HOSTNAME localhost
::1         $HOSTNAME localhost
EOF

    if [[ "$INIT" == systemd ]]; then
        hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || true
    else
        echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname
    fi

    echo "Setting root password..."
    passwd root

    read -r -p "Username: " USERNAME
    [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username"

    for g in wheel video audio render input; do
        getent group "$g" >/dev/null || groupadd "$g"
    done

    EXTRA_GROUPS=""
    getent group seat >/dev/null && EXTRA_GROUPS=",seat"

    useradd -m -s /bin/bash -G "wheel,video,audio,render,input${EXTRA_GROUPS}" "$USERNAME"
    passwd "$USERNAME"

    install -d -m 0750 /etc/sudoers.d
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
    chmod 0440 /etc/sudoers.d/10-wheel
    visudo -c

    # ================================
    # Kernel
    # ================================

    print_section "Installing Kernel"

    case "$KERNEL_TYPE" in
        distribution-kernel)
            echo "Installing gentoo-kernel-bin (binary kernel)..."
            portage_emerge sys-kernel/gentoo-kernel-bin
            ;;
        gentoo-kernel)
            echo "Installing gentoo-kernel (auto-configured source kernel)..."
            echo "This will take considerable time..."
            portage_emerge --usepkg=n --buildpkg=n sys-kernel/gentoo-kernel
            ;;
        gentoo-sources)
            echo "Installing gentoo-sources (manual configuration required)..."
            portage_emerge sys-kernel/gentoo-sources

            echo
            echo "Installing kernel build tools..."
            portage_emerge sys-apps/pciutils sys-kernel/genkernel

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
                cd /usr/src/linux
                echo "Starting kernel configuration..."
                echo "Tip: Use 'make localyesconfig' for a minimal config based on current hardware"
                echo
                PS3="Select configuration method: "
                select KCONFIG in menuconfig localyesconfig defconfig; do
                    [[ -n "${KCONFIG:-}" ]] && break
                done

                case "$KCONFIG" in
                    menuconfig)
                        make menuconfig
                        ;;
                    localyesconfig)
                        make localyesconfig
                        echo "Configuration completed with localyesconfig"
                        ;;
                    defconfig)
                        make defconfig
                        echo "Configuration completed with defconfig"
                        ;;
                esac

                echo
                echo "Building kernel (this will take a long time)..."
                make -j${JOBS} || die "Kernel build failed"
                make modules_install || die "Module installation failed"
                make install || die "Kernel installation failed"

                echo "Generating initramfs with genkernel..."
                genkernel --install --kernel-config=/usr/src/linux/.config initramfs || die "Initramfs generation failed"
            else
                echo
                echo "Kernel configuration skipped."
                echo "After installation, you must:"
                echo "  1. cd /usr/src/linux"
                echo "  2. make menuconfig  (or localyesconfig/defconfig)"
                echo "  3. make -j${JOBS} && make modules_install && make install"
                echo "  4. genkernel --install --kernel-config=/usr/src/linux/.config initramfs"
                echo
                read -r -p "Press Enter to continue..."
            fi
            ;;
    esac

    # ================================
    # Services
    # ================================

    if [[ "$INIT" == systemd ]]; then
        systemd-machine-id-setup || true
        systemctl preset-all --preset-mode=enable-only || true
        systemctl enable NetworkManager.service sshd.service bluetooth.service || true
    else
        rc-update add dbus default || true
        rc-update add NetworkManager default || true
        rc-update add sshd default || true
        rc-update add bluetooth default || true
        rc-update add elogind boot || true
    fi

    # ================================
    # Profile-specific packages
    # ================================

    case "$PROFILE" in
        gentoo_niri)
            portage_emerge gui-wm/niri::guru gui-apps/waybar gui-apps/fuzzel \
                gui-apps/mako gui-apps/swaybg x11-misc/ly::guru || true
            ;;
        gentoo_hyprland)
            portage_emerge gui-wm/hyprland gui-apps/waybar \
                sys-apps/xdg-desktop-portal-hyprland \
                gui-apps/hyprlock gui-apps/hypridle x11-misc/ly::guru || true
            ;;
        gentoo_kde)
            portage_emerge kde-plasma/plasma-meta kde-apps/konsole \
                kde-apps/dolphin kde-apps/kate sys-apps/xdg-desktop-portal-kde \
                kde-plasma/sddm-kcm || true
            ;;
    esac

    if [[ "$PROFILE" != gentoo_base ]]; then
        if [[ "$PROFILE" == gentoo_kde ]]; then
            # KDE uses SDDM
            if [[ "$INIT" == systemd ]]; then
                systemctl enable sddm.service 2>/dev/null || true
            else
                rc-update add sddm default 2>/dev/null || true
            fi
        else
            # Other profiles use Ly
            if [[ "$INIT" == systemd ]]; then
                systemctl enable ly.service 2>/dev/null || true
            else
                rc-update add ly default 2>/dev/null || true
            fi
        fi
    fi

    # ================================
    # Locale
    # ================================

    if [[ -f /etc/locale.gen ]]; then
        sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        locale-gen || true
    fi
    printf 'LANG="en_US.UTF-8"\n' > /etc/env.d/02locale
    env-update

    # ================================
    # World rebuild
    # ================================

    print_section "Final System Rebuild"
    portage_emerge @world || true

    # ================================
    # GRUB
    # ================================

    print_section "Installing Bootloader"

    portage_emerge sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo --recheck
    grub-mkconfig -o /boot/grub/grub.cfg

    # ================================
    # Summary
    # ================================

    cat > /root/gentoo-install-summary.txt <<EOF
Gentoo Installation Complete
============================
Date:       $(date)
Hostname:   $HOSTNAME
User:       $USERNAME
Profile:    $PROFILE
Init:       $INIT
CPU/RAM:    ${THREADS} threads / ${RAM_MB}MB
Partitions: Root=$ROOT, EFI=$EFI, Swap=$SWAP

Next steps:
  1. exit
  2. umount -R /mnt/gentoo
  3. reboot
EOF

    print_header "INSTALLATION COMPLETE"
    cat /root/gentoo-install-summary.txt
    echo
}

# ============================================
# MAIN ENTRY POINT
# ============================================

main() {
    if detect_phase; then
        # Phase 1: Live environment
        phase1_live_environment
    else
        # Phase 2: Chroot
        phase2_chroot
    fi
}

main "$@"
