# Gentoo Installer / Установщик Gentoo

<div align="center">

[![EN](https://img.shields.io/badge/lang-English-blue.svg)](#english)
[![RU](https://img.shields.io/badge/язык-Русский-red.svg)](#русский)

</div>

---

## English

### 📋 Description

Automated Gentoo Linux installer scripts inspired by archinstall. These scripts simplify the Gentoo installation process by automating partitioning, Stage 3 extraction, package installation, and system configuration.

### ✨ Features

- **Automated installation**: Minimal user interaction required
- **Multiple desktop profiles**:
  - `gentoo_base` - Base desktop-ready system (no WM/DE)
  - `gentoo_niri` - Base + Niri compositor + Waybar
  - `gentoo_hyprland` - Base + Hyprland + Waybar
  - `gentoo_kde` - Base + KDE Plasma desktop environment
- **Init system choice**: systemd or OpenRC
- **GPU support**: NVIDIA, AMD (AMDGPU), and Intel drivers
- **Kernel options**:
  - `distribution-kernel` (gentoo-kernel-bin) - Pre-built binary kernel (fastest)
  - `gentoo-kernel` - Auto-configured source kernel (builds locally)
  - `gentoo-sources` - Manual kernel configuration with menuconfig/localyesconfig/defconfig
- **Flexible partitioning**: Automatic or manual (cfdisk/fdisk/parted)
- **Binary packages**: Uses Gentoo binhost for faster installation
- **Hardware support**: GPU drivers, firmware, Bluetooth
- **Modern desktop stack**: PipeWire, Wayland, XWayland

### 🚀 Installation Methods

#### Method 1: Unified Script (Recommended)

Single script that handles both pre-chroot and chroot phases automatically:

```bash
# Download and run
git clone https://github.com/weedblya/gentoo-installer.git
cd gentoo-installer
chmod +x gentoo-install-unified.sh
./gentoo-install-unified.sh
```

#### Method 2: Two-Part Installation

Traditional approach with separate scripts for each phase:

**Part 1 (Live environment - before chroot):**
```bash
git clone https://github.com/weedblya/gentoo-installer.git
cd gentoo-installer
chmod +x install_part1.sh
./install_part1.sh
```

**Part 2 (Inside chroot):**
```bash
# After Part 1 completes, mount virtual filesystems and enter chroot:
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --rbind /run /mnt/gentoo/run
mount --make-rslave /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash
source /etc/profile

# Run Part 2
/root/install_part2.sh
```

### 📦 What Gets Installed

**Base System:**
- **Kernel** (choice of three options):
  - `distribution-kernel` (gentoo-kernel-bin) - Pre-compiled binary kernel
  - `gentoo-kernel` - Auto-configured source kernel built locally
  - `gentoo-sources` - Full manual configuration with menuconfig/localyesconfig/defconfig
- Essential tools: sudo, vim, nano, git, curl, wget, btop
- Network: NetworkManager, OpenSSH
- Audio: PipeWire, WirePlumber
- Graphics: Mesa, Vulkan
- GPU drivers:
  - **NVIDIA**: proprietary nvidia-drivers with Wayland support
  - **AMD**: AMDGPU/RadeonSI with Vulkan, VAAPI, VDPAU
  - **Intel**: Intel graphics with Vulkan, VAAPI
- Wayland: wayland, wayland-protocols, XWayland

**Profile-Specific Packages:**
- **Base**: No additional compositor or desktop environment
- **Niri**: Niri compositor, Waybar, Fuzzel, Mako, Swaybg, Swayidle, Swaylock, Ly display manager
- **Hyprland**: Hyprland, Waybar, Hyprlock, Hypridle, Hyprpaper, Hyprpicker, Ly display manager, xdg-desktop-portal-hyprland
- **KDE**: KDE Plasma Meta, Konsole, Dolphin, Kate, SDDM display manager, xdg-desktop-portal-kde

### 🔧 Kernel Options Explained

**1. distribution-kernel (gentoo-kernel-bin)** ⚡
- Pre-compiled binary kernel from Gentoo
- Fastest installation (5-10 minutes)
- Generic configuration works on most hardware
- Recommended for beginners and quick deployments

**2. gentoo-kernel** 🔨
- Auto-configured source kernel
- Builds locally based on your hardware
- Installation time: 30-90 minutes (depends on CPU)
- Good balance between optimization and convenience

**3. gentoo-sources** 🎯
- Full manual kernel configuration
- Complete control over kernel features
- Three configuration methods:
  - `menuconfig` - Interactive menu-based configuration (ncurses)
  - `localyesconfig` - Minimal config based on currently loaded modules
  - `defconfig` - Default generic configuration
- Installation time: 45-120+ minutes
- Recommended for advanced users who need specific features

### ⚙️ System Requirements

- **UEFI** boot mode (BIOS/Legacy is not supported)
- Minimum **2 GB RAM** (4 GB+ recommended)
- Minimum **20 GB disk space**
- Active **internet connection**

### 🖥️ Desktop Environment Profiles

**gentoo_base** 🔧
- Minimal desktop-ready system without compositor or DE
- Includes Wayland/X11 libraries and basic desktop stack
- Perfect base for custom setups or manual DE installation
- Fastest installation

**gentoo_niri** 🪟
- Niri - Scrollable-tiling Wayland compositor
- Waybar - Highly customizable status bar
- Fuzzel - Application launcher
- Mako - Notification daemon
- Swaybg, Swayidle, Swaylock - Background, idle, and lock screen
- Ly - TUI display manager
- Best for: Tiling workflow enthusiasts

**gentoo_hyprland** 🌊
- Hyprland - Dynamic tiling Wayland compositor with animations
- Waybar - Status bar
- Hyprlock - Screen locker
- Hypridle - Idle daemon
- Hyprpaper - Wallpaper utility
- Hyprpicker - Color picker
- Ly - TUI display manager
- xdg-desktop-portal-hyprland - Screen sharing support
- Hyproverlay repository enabled
- Best for: Modern, animated tiling experience

**gentoo_kde** 🎨
- KDE Plasma Meta - Full desktop environment
- Konsole - Terminal emulator
- Dolphin - File manager with semantic desktop
- Kate - Advanced text editor
- SDDM - Graphical display manager
- xdg-desktop-portal-kde - Portal implementation
- Best for: Full-featured desktop with GUI configuration

### 🔧 Configuration

The installer uses an "Arch-like" package availability approach:
- Global `~amd64` keywords enabled
- All packages unmasked (hard masks still apply)
- Binary packages from official Gentoo binhost
- Additional repositories: GURU, Hyproverlay (for Hyprland profile)

**GPU Support:** For detailed information about GPU drivers and configuration, see [GPU_SUPPORT.md](GPU_SUPPORT.md).

### 📝 After Installation

1. Exit the chroot environment
2. Unmount filesystems: `umount -R /mnt/gentoo`
3. Reboot: `reboot`
4. Log in with your created user account
5. Configure network: `nmtui` or `nmcli`
6. Update system: `emerge --sync && emerge -uDN @world`

**If you chose gentoo-sources (manual kernel):**
- If you skipped kernel configuration during installation, you must complete it before the system can boot
- Steps:
  ```bash
  cd /usr/src/linux
  make menuconfig  # or localyesconfig/defconfig
  make -j$(nproc) && make modules_install && make install
  genkernel --install --kernel-config=/usr/src/linux/.config initramfs
  grub-mkconfig -o /boot/grub/grub.cfg
  ```

### 🎯 Quick Start Guide

**For beginners:**
- Profile: `gentoo_kde` (full desktop environment)
- Init: `systemd` (more automated)
- Kernel: `distribution-kernel` (fastest)
- Partitioning: `automatic`

**For tiling WM enthusiasts:**
- Profile: `gentoo_hyprland` or `gentoo_niri`
- Init: Your preference
- Kernel: `gentoo-kernel` (optimized for your hardware)
- Partitioning: `automatic` or manual

**For advanced users:**
- Profile: `gentoo_base` (customize everything)
- Init: Your preference
- Kernel: `gentoo-sources` (full control)
- Partitioning: Manual with preferred tool

### 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

### 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

---

## Русский

### 📋 Описание

Автоматизированные скрипты установки Gentoo Linux, вдохновленные archinstall. Эти скрипты упрощают процесс установки Gentoo, автоматизируя разметку диска, извлечение Stage 3, установку пакетов и настройку системы.

### ✨ Возможности

- **Автоматическая установка**: минимальное участие пользователя
- **Несколько профилей рабочего стола**:
  - `gentoo_base` - базовая система, готовая к установке рабочего стола (без WM/DE)
  - `gentoo_niri` - база + композитор Niri + Waybar
  - `gentoo_hyprland` - база + Hyprland + Waybar
  - `gentoo_kde` - база + окружение рабочего стола KDE Plasma
- **Выбор init-системы**: systemd или OpenRC
- **Поддержка GPU**: драйверы NVIDIA, AMD (AMDGPU) и Intel
- **Варианты ядра**:
  - `distribution-kernel` (gentoo-kernel-bin) - Предсобранное бинарное ядро (самое быстрое)
  - `gentoo-kernel` - Автоматически настраиваемое ядро из исходников (собирается локально)
  - `gentoo-sources` - Ручная настройка ядра с menuconfig/localyesconfig/defconfig
- **Гибкая разметка диска**: автоматическая или ручная (cfdisk/fdisk/parted)
- **Бинарные пакеты**: использует Gentoo binhost для ускорения установки
- **Поддержка оборудования**: драйверы GPU, прошивки, Bluetooth
- **Современный стек рабочего стола**: PipeWire, Wayland, XWayland

### 🚀 Методы установки

#### Метод 1: Единый скрипт (рекомендуется)

Единый скрипт, который автоматически обрабатывает фазы до и после chroot:

```bash
# Скачать и запустить
git clone https://github.com/weedblya/gentoo-installer.git
cd gentoo-installer
chmod +x gentoo-install-unified.sh
./gentoo-install-unified.sh
```

#### Метод 2: Установка в два этапа

Традиционный подход с отдельными скриптами для каждой фазы:

**Часть 1 (Live окружение - до chroot):**
```bash
git clone https://github.com/weedblya/gentoo-installer.git
cd gentoo-installer
chmod +x install_part1.sh
./install_part1.sh
```

**Часть 2 (Внутри chroot):**
```bash
# После завершения части 1, смонтируйте виртуальные файловые системы и войдите в chroot:
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --rbind /run /mnt/gentoo/run
mount --make-rslave /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash
source /etc/profile

# Запустить часть 2
/root/install_part2.sh
```

### 📦 Что устанавливается

**Базовая система:**
- **Ядро** (на выбор три варианта):
  - `distribution-kernel` (gentoo-kernel-bin) - Предсобранное бинарное ядро
  - `gentoo-kernel` - Автонастраиваемое ядро из исходников, собранное локально
  - `gentoo-sources` - Полная ручная настройка с menuconfig/localyesconfig/defconfig
- Необходимые утилиты: sudo, vim, nano, git, curl, wget, btop
- Сеть: NetworkManager, OpenSSH
- Аудио: PipeWire, WirePlumber
- Графика: Mesa, Vulkan
- Драйверы GPU:
  - **NVIDIA**: проприетарные nvidia-drivers с поддержкой Wayland
  - **AMD**: AMDGPU/RadeonSI с Vulkan, VAAPI, VDPAU
  - **Intel**: Intel графика с Vulkan, VAAPI
- Wayland: wayland, wayland-protocols, XWayland

**Пакеты для конкретных профилей:**
- **Base**: Без дополнительного композитора или окружения рабочего стола
- **Niri**: композитор Niri, Waybar, Fuzzel, Mako, Swaybg, Swayidle, Swaylock, экранный менеджер Ly
- **Hyprland**: Hyprland, Waybar, Hyprlock, Hypridle, Hyprpaper, Hyprpicker, экранный менеджер Ly, xdg-desktop-portal-hyprland
- **KDE**: KDE Plasma Meta, Konsole, Dolphin, Kate, экранный менеджер SDDM, xdg-desktop-portal-kde

### 🔧 Варианты ядра — подробности

**1. distribution-kernel (gentoo-kernel-bin)** ⚡
- Предкомпилированное бинарное ядро от Gentoo
- Самая быстрая установка (5-10 минут)
- Универсальная конфигурация работает на большинстве систем
- Рекомендуется для начинающих и быстрого развертывания

**2. gentoo-kernel** 🔨
- Автоматически настраиваемое ядро из исходников
- Собирается локально под ваше оборудование
- Время установки: 30-90 минут (зависит от процессора)
- Хороший баланс между оптимизацией и удобством

**3. gentoo-sources** 🎯
- Полная ручная настройка ядра
- Полный контроль над функциями ядра
- Три метода конфигурации:
  - `menuconfig` - Интерактивная настройка через меню (ncurses)
  - `localyesconfig` - Минимальная конфигурация на основе загруженных модулей
  - `defconfig` - Универсальная конфигурация по умолчанию
- Время установки: 45-120+ минут
- Рекомендуется для опытных пользователей, которым нужны специфические функции

### 🖥️ Профили окружения рабочего стола

**gentoo_base** 🔧
- Минимальная система, готовая к установке рабочего стола без композитора или DE
- Включает библиотеки Wayland/X11 и базовый стек рабочего стола
- Идеальная база для пользовательских настроек или ручной установки DE
- Самая быстрая установка

**gentoo_niri** 🪟
- Niri - Прокручиваемый тайловый Wayland-композитор
- Waybar - Настраиваемая строка состояния
- Fuzzel - Лончер приложений
- Mako - Демон уведомлений
- Swaybg, Swayidle, Swaylock - Фон, бездействие и блокировка экрана
- Ly - TUI менеджер входа
- Лучше для: Энтузиастов тайловых менеджеров окон

**gentoo_hyprland** 🌊
- Hyprland - Динамический тайловый Wayland-композитор с анимацией
- Waybar - Строка состояния
- Hyprlock - Блокировка экрана
- Hypridle - Демон бездействия
- Hyprpaper - Утилита обоев
- Hyprpicker - Пипетка цвета
- Ly - TUI менеджер входа
- xdg-desktop-portal-hyprland - Поддержка скриншеринга
- Включён репозиторий Hyproverlay
- Лучше для: Современный анимированный тайловый опыт

**gentoo_kde** 🎨
- KDE Plasma Meta - Полное окружение рабочего стола
- Konsole - Эмулятор терминала
- Dolphin - Файловый менеджер с семантическим рабочим столом
- Kate - Продвинутый текстовый редактор
- SDDM - Графический менеджер входа
- xdg-desktop-portal-kde - Реализация портала
- Лучше для: Полнофункциональный рабочий стол с GUI-настройкой

### ⚙️ Системные требования

- Режим загрузки **UEFI** (BIOS/Legacy не поддерживается)
- Минимум **2 ГБ RAM** (рекомендуется 4 ГБ+)
- Минимум **20 ГБ** дискового пространства
- Активное **подключение к интернету**

### 🔧 Конфигурация

Установщик использует подход "как в Arch" для доступности пакетов:
- Глобально включены ключевые слова `~amd64`
- Все пакеты размаскированы (жесткие маски все еще применяются)
- Бинарные пакеты из официального Gentoo binhost
- Дополнительные репозитории: GURU, Hyproverlay (для профиля Hyprland)

**Поддержка GPU:** Для подробной информации о драйверах GPU и конфигурации, см. [GPU_SUPPORT.md](GPU_SUPPORT.md).

### 📝 После установки

1. Выйдите из chroot окружения
2. Размонтируйте файловые системы: `umount -R /mnt/gentoo`
3. Перезагрузитесь: `reboot`
4. Войдите под созданным пользователем
5. Настройте сеть: `nmtui` или `nmcli`
6. Обновите систему: `emerge --sync && emerge -uDN @world`

**Если вы выбрали gentoo-sources (ручная настройка ядра):**
- Если вы пропустили конфигурацию ядра во время установки, вы должны завершить её перед загрузкой системы
- Шаги:
  ```bash
  cd /usr/src/linux
  make menuconfig  # или localyesconfig/defconfig
  make -j$(nproc) && make modules_install && make install
  genkernel --install --kernel-config=/usr/src/linux/.config initramfs
  grub-mkconfig -o /boot/grub/grub.cfg
  ```

### 🎯 Руководство быстрого старта

**Для начинающих:**
- Профиль: `gentoo_kde` (полное окружение рабочего стола)
- Init: `systemd` (более автоматизированный)
- Ядро: `distribution-kernel` (самое быстрое)
- Разметка: `automatic`

**Для любителей тайловых WM:**
- Профиль: `gentoo_hyprland` или `gentoo_niri`
- Init: На ваше усмотрение
- Ядро: `gentoo-kernel` (оптимизировано под ваше железо)
- Разметка: `automatic` или ручная

**Для опытных пользователей:**
- Профиль: `gentoo_base` (настройте всё сами)
- Init: На ваше усмотрение
- Ядро: `gentoo-sources` (полный контроль)
- Разметка: Ручная с предпочитаемым инструментом

### 📄 Лицензия

Лицензия MIT - подробности в файле [LICENSE](LICENSE).

### 🤝 Участие в разработке

Приветствуются любые предложения! Не стесняйтесь создавать issues и pull requests.

---

<div align="center">

Made with ❤️ for the Gentoo community

</div>
