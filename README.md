# Gentoo Interactive Installer

Modular, CLI-based Gentoo Linux installer with comprehensive hardware support, flexible desktop environment configuration, and advanced package management options.

## Features

### Core Features
- **Interactive CLI Menu**: Dialog/whiptail-based configuration wizard with fallback to `select`
- **Comprehensive Logging**: All operations logged to `/tmp/gentoo-install-*.log` for troubleshooting
- **Error Handling**: Strict mode (`set -euo pipefail`), trap-based cleanup, status tracking
- **Hardware Detection**: Automatic virtualization and GPU detection
- **Virtual Machine Support**: Special configurations for VirtualBox, QEMU/KVM, VMware

### System Configuration
- **Init Systems**: OpenRC (default) or systemd
- **Filesystems**: ext4, btrfs (with subvolumes), xfs
- **Boot Types**: UEFI (GPT) or BIOS/MBR
- **Partitioning**: Automatic three-partition layout (EFI/root/swap)
- **Swap**: Dynamically sized based on disk and root partition selection

### Desktop Environments
- **KDE Plasma**: Full-featured Wayland-capable desktop with XWayland
- **Hyprland**: Modern Wayland tiling window manager
- **Niri**: Wayland compositor
- **MangoWM**: Lightweight tiling window manager
- **Minimal**: CLI-only setup (no DE/WM)

### Package Management
- **Kernel Selection**:
  - `distribution-kernel-bin`: Precompiled, fastest deployment
  - `gentoo-kernel`: Compiled on target with flexible configuration
  - `gentoo-sources`: Full manual control via menuconfig
  
- **Kernel Compilation** (for gentoo-sources and gentoo-kernel):
  - `menuconfig`: Interactive kernel configuration
  - `localyesconfig`: Based on running kernel configuration
  - `defconfig`: Minimal defaults
  
- **Binary Packages** (`binhost`):
  - **Yes**: Configures official Gentoo binary repository with `--getbinpkg` / `--usepkg` flags in EMERGE_DEFAULT_OPTS for dramatically faster installation
  - **No**: Pure source compilation (traditional Gentoo experience)

- **Package Policy**:
  - **Stable**: Standard conservative `amd64` without global unmasking (individual packages unmasked per profile needs)
  - **Testing**: Global `ACCEPT_KEYWORDS="~amd64"` with selective unmasking for cutting-edge software

### Graphics Support
- **Automatic Detection**:
  - NVIDIA (proprietary nvidia-drivers with modeset for Wayland)
  - AMD (amdgpu + radeonsi)
  - Intel (Mesa iris/ANV)
  - Hybrid configurations (Intel+NVIDIA, AMD+NVIDIA)
  
- **Virtual Machine Support**:
  - VirtualBox (virtualbox + vmware drivers)
  - QEMU/KVM (virgl/virtio-gpu)
  - VMware (vmware driver)
  
- **Manual GPU Selection**: Override auto-detection if needed

### System Configuration
- **Hostname & User**: Custom hostname, primary user account, group assignment
- **Timezone & Keymap**: Full timezone database support, console keymap selection
- **Bluetooth**: Optional bluez installation
- **Networking**: NetworkManager for flexible network configuration
- **Audio**: PipeWire + WirePlumber (modern audio server)

## Requirements

- Gentoo minimal installation media (amd64)
- Root privileges
- Internet connection
- Target disk with at least 24 GiB (40+ GiB recommended)
- Tools required: `parted`, `mkfs.*`, `curl`/`wget`, `dialog`/`whiptail` (optional but recommended for TUI)

## Installation

### Clone the Repository
```bash
git clone https://github.com/zahen3469/gentoo-kde-installer.git
cd gentoo-kde-installer
```

### Run the Installer
```bash
chmod +x gentoo-install.sh
sudo ./gentoo-install.sh
```

## Configuration Walkthrough

### 1. Boot Type
Choose UEFI (modern, EFI) or BIOS/MBR based on your hardware.

### 2. Init System
- **OpenRC**: Lightweight, traditional init system
- **systemd**: Feature-rich, modern init system

### 3. Desktop Environment
- **KDE Plasma**: Full desktop suite with applications
- **Hyprland**: Tiling window manager for Wayland
- **Niri**: Lightweight Wayland compositor
- **MangoWM**: Minimal tiling manager
- **Minimal**: Console-only system

### 4. Kernel Configuration
- **distribution-kernel-bin**: Fastest (5-10 minutes)
- **gentoo-kernel**: Balanced (automatic compilation, ~1-2 hours)
- **gentoo-sources**: Maximum flexibility (requires menuconfig interaction)

For `gentoo-sources`, choose compilation method:
- `menuconfig`: Full interactive configuration
- `localyesconfig`: Automatic based on live environment
- `defconfig`: Minimal defaults

### 5. Binary Packages
- **Yes**: Dramatically speeds up installation (5-15 minutes vs hours)
- **No**: Pure source compilation (traditional Gentoo, ~4-8 hours for full desktop)

### 6. Package Policy
- **Stable**: Conservative, well-tested packages
- **Testing**: Bleeding-edge with `~amd64` keyword acceptance

### 7. Filesystem
- **ext4**: Reliable, widely compatible
- **btrfs**: Modern features, snapshot support, subvolumes
- **xfs**: High-performance for large files

### 8. Disk Selection
Select target disk. **All data will be erased.**

### 9. Root Partition Size
Allocate space for root (minimum 20 GiB recommended for KDE). Remainder becomes swap.

### 10. System Identity
- **Hostname**: Machine name
- **User**: Primary user account
- **Timezone**: Full `/usr/share/zoneinfo` paths supported
- **Keymap**: Console keymap (e.g., `us`, `de`, `fr`)

### 11. Passwords
- Root password (minimum 8 characters)
- User password (minimum 8 characters)

## Partition Layout

### UEFI Boot
```
/dev/sdX1  EFI partition (FAT32, 1 GiB)
/dev/sdX2  Root partition (ext4/btrfs/xfs, configured size)
/dev/sdX3  Swap partition (linux-swap, remaining)
```

### BIOS Boot
```
/dev/sdX1  Root partition (ext4/btrfs/xfs, configured size)
/dev/sdX2  Swap partition (linux-swap, remaining)
```

## Binary Packages (binhost)

### When Enabled
The installer configures:
```bash
# /etc/portage/binrepos.conf
[gentoo]
priority = 9999
sync-uri = https://distfiles.gentoo.org/releases/amd64/autobuilds/x86-64-v3/binpkgs/default/linux/17.1/x86-64-v3/

# /etc/portage/make.conf
EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg --usepkg"
```

### When Disabled
Pure source compilation from Portage tree.

## Package Masking

### Stable Policy
```bash
ACCEPT_KEYWORDS="amd64"  # Only stable packages by default
# Individual packages unmasked in /etc/portage/package.unmask as needed
```

### Testing Policy
```bash
ACCEPT_KEYWORDS="~amd64"  # Accept unstable (~) keyword globally
# Hard-masked packages still blocked
```

## Build Times (Approximate)

Without binary packages:
- **Minimal system**: 1-2 hours
- **With KDE Plasma**: 4-8 hours
- **With Hyprland**: 2-4 hours

With binary packages:
- **Full KDE system**: 5-15 minutes (network-limited)

## Troubleshooting

### Installation Fails
1. Check the log: `cat /tmp/gentoo-install-*.log`
2. Common issues:
   - Disk is mounted: use `lsblk` to verify
   - Network connectivity: test `ping distfiles.gentoo.org`
   - Disk too small: need minimum 24 GiB

### Dialog/Whiptail Not Available
The script automatically falls back to `select`-based CLI menus if neither dialog/whiptail is available.

### GPU Not Detected
Manual selection is available during interactive configuration.

### Kernel Compilation Fails
- For `gentoo-sources`, review kernel config with `menuconfig`
- Ensure sufficient disk space in `/tmp`
- Check `/var/tmp/portage/` for build artifacts

### Boot Issues
- Verify UEFI/BIOS mode matches your firmware
- Check GRUB configuration: `mount /boot/efi && grub-mkconfig -o /boot/grub/grub.cfg`

## Testing Status

- Static bash syntax validation: ✓
- Hardware detection: Tested on multiple VMs and physical systems
- Partitioning & formatting: Validated on UEFI/BIOS systems
- Stage3 extraction: Confirmed with official Gentoo releases
- Chroot environment: Framework prepared (full installation sequence in development)

## Design Principles

1. **Modularity**: Each configuration aspect is independent and testable
2. **Strict Error Handling**: `set -euo pipefail`, ERR trap, cleanup on exit
3. **Security**: Passwords never logged, secrets passed to chroot via stdin only
4. **Hardware-Aware**: Detects virtualization and GPU; user can override
5. **Logging**: Every operation recorded for debugging
6. **User Choice**: Extensive menu options for customization
7. **Reversibility**: Installation can be cleaned up if interrupted

## Supported Systems

- Physical AMD64 (Intel/AMD processors)
- VirtualBox
- QEMU/KVM with virtio
- VMware
- Hyper-V (basic support)
- Xen (basic support)

## Contributions

For bug reports, feature requests, or contributions, please use the project's issue tracker.

## References

- [Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
- [Portage Documentation](https://wiki.gentoo.org/wiki/Portage)
- [Binary Package Guide](https://wiki.gentoo.org/wiki/Binary_package_guide)
- [KDE on Gentoo](https://wiki.gentoo.org/wiki/KDE)
- [Wayland Support](https://wiki.gentoo.org/wiki/Wayland)
