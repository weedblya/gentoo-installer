# Gentoo Linux Modular Installer

Automated Gentoo Linux installer with modular architecture.

## 🏗️ Architecture

This installer uses a modular architecture where each component is a separate, reusable script:

```
gentoo-installer/
├── configure.sh              # Interactive configuration
├── setup.sh                  # Main installation orchestrator
├── gentoo-install-legacy.sh  # Original monolithic script (backup)
└── modules/
    ├── common.sh             # Shared functions and utilities
    ├── hardware-detect.sh    # Hardware detection (GPU, boot type, etc)
    ├── partition.sh          # Disk partitioning
    ├── filesystem.sh         # Filesystem creation and mounting
    ├── stage3.sh             # Stage3 download and extraction
    ├── portage-config.sh     # Portage configuration
    ├── chroot-prepare.sh     # Chroot environment preparation
    ├── system-config.sh      # System configuration (hostname, locale, etc)
    ├── kernel-install.sh     # Kernel installation
    ├── bootloader.sh         # GRUB installation
    ├── network.sh            # Network configuration
    ├── users.sh              # User creation and passwords
    └── desktop-install.sh    # Desktop environment installation
```

## 🚀 Quick Start

### 1. Configure Installation

Run the interactive configuration:

```bash
./configure.sh
```

This will:
- Detect hardware (GPU, virtualization, boot type)
- Ask for system configuration
- Save settings to `/tmp/gentoo-installer-config.env`

### 2. Start Installation

Run the installation:

```bash
./setup.sh
```

This will:
- Execute all installation stages automatically
- Log everything to `/tmp/gentoo-install-YYYYMMDD-HHMMSS.log`
- Show progress and status

## 📋 Installation Stages

### Stage 1: Disk Preparation
- Partition disk (GPT for UEFI, MBR for BIOS)
- Create filesystems (ext4/xfs/btrfs)
- Mount partitions

### Stage 2: Base System
- Download and extract Stage3 tarball
- Configure Portage (make.conf, repos.conf)
- Prepare chroot environment

### Stage 3: System Configuration (in chroot)
- Sync Portage repository
- Select system profile
- Configure system (hostname, timezone, locale, fstab)
- Install kernel
- Install bootloader (GRUB)
- Configure network
- Create users
- Install desktop environment (optional)

### Stage 4: Finalization
- Show installation summary
- Display next steps

## 🔧 Module Usage

Each module can be run independently for testing or recovery:

```bash
# Run hardware detection
./modules/hardware-detect.sh

# Create filesystems (requires config)
./modules/filesystem.sh

# Install kernel (inside chroot)
./modules/kernel-install.sh
```

## 📝 Configuration

Configuration is saved to `/tmp/gentoo-installer-config.env`:

```bash
HOSTNAME="gentoo"
USERNAME="user"
TIMEZONE="UTC"
INIT_SYSTEM="openrc"
DESKTOP_PROFILE="kde"
KERNEL_TYPE="distribution-kernel-bin"
# ... and more
```

## 🎯 Supported Features

### Init Systems
- OpenRC (default)
- systemd

### Desktop Environments
- Minimal (no DE/WM)
- KDE Plasma
- Hyprland (Wayland)
- Niri (Wayland)

### Filesystems
- ext4 (default)
- XFS
- Btrfs

### Kernels
- distribution-kernel-bin (fastest)
- gentoo-kernel-bin
- gentoo-kernel (compile from source)

### Boot Types
- UEFI (auto-detected)
- BIOS (auto-detected)

## 🛠️ Advantages of Modular Architecture

1. **Maintainability** - Each module is small and focused
2. **Reusability** - Modules can be used independently
3. **Testability** - Easy to test individual components
4. **Extensibility** - Simple to add new features
5. **Debugging** - Easier to locate and fix issues
6. **Collaboration** - Multiple developers can work on different modules

## 📚 Adding New Modules

To add a new module:

1. Create `modules/your-module.sh`
2. Source common functions:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/common.sh"
   ```
3. Add your functionality
4. Update `setup.sh` or `configure.sh` to call your module

## 🔄 Migrating from Legacy Script

The original monolithic script is preserved as `gentoo-install-legacy.sh`.

Key differences:
- **Old**: One 1100+ line script
- **New**: 13 focused modules + 2 orchestrators

All functionality from the legacy script is preserved and improved.

## 🐛 Troubleshooting

### View installation log
```bash
tail -f /tmp/gentoo-install-*.log
```

### Re-run specific module (inside chroot)
```bash
chroot /mnt/gentoo /bin/bash
source /tmp/installer-modules/common.sh
source /tmp/installer-modules/kernel-install.sh
install_kernel
```

### Clean up after failed installation
```bash
umount -R /mnt/gentoo
swapoff /dev/sdX3  # if swap was enabled
```

## 📄 License

GPL-2.0 (see LICENSE file)

## 🤝 Contributing

Contributions are welcome! Each module is independent, making it easy to:
- Fix bugs in specific modules
- Add new desktop environments
- Improve hardware detection
- Add new features

## 📞 Support

- Check installation logs in `/tmp/gentoo-install-*.log`
- Review Gentoo Handbook: https://wiki.gentoo.org/wiki/Handbook
- Report issues with detailed logs

---

**Note**: This installer automates the Gentoo installation process but requires basic Linux knowledge. Always test in a virtual machine first!
