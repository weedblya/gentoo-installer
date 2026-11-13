# GPU Support / Поддержка GPU

## English

### Supported GPU Vendors

The installer supports three major GPU vendors with automatic driver installation and configuration.

#### 🟢 NVIDIA

**Drivers installed:**
- `x11-drivers/nvidia-drivers` - Proprietary NVIDIA drivers with Wayland support

**Features:**
- Full Wayland compositor support
- X11 compatibility via XWayland
- Vulkan support
- Hardware video acceleration (NVENC/NVDEC)

**Recommended for:**
- GeForce GTX 600 series and newer
- GeForce RTX series (full ray tracing support)
- Quadro and Tesla workstation/server cards

**Configuration:**
```
VIDEO_CARDS: nvidia
```

---

#### 🔴 AMD

**Drivers installed:**
- `x11-drivers/xf86-video-amdgpu` - Open-source AMDGPU driver
- `dev-libs/amdgpu-pro-opencl` - OpenCL support (optional)

**Features:**
- Native open-source drivers with excellent Wayland support
- Vulkan via RADV (RadeonSI)
- Hardware video acceleration (VAAPI, VDPAU)
- AMD FreeSync support

**Recommended for:**
- Radeon RX 400 series and newer (Polaris, Vega, RDNA, RDNA2, RDNA3)
- Radeon VII
- Ryzen APUs with Vega/RDNA graphics

**Configuration:**
```
VIDEO_CARDS: amdgpu radeonsi
```

---

#### 🔵 Intel

**Drivers installed:**
- `x11-drivers/xf86-video-intel` - Intel graphics driver
- `media-libs/intel-mediasdk` - Hardware video acceleration

**Features:**
- Open-source drivers with good Wayland support
- Vulkan via ANV (Intel's Vulkan driver)
- Hardware video acceleration (VAAPI)
- Intel Quick Sync Video support

**Recommended for:**
- Intel HD Graphics 2000 and newer
- Intel Iris Graphics
- Intel Arc discrete GPUs

**Configuration:**
```
VIDEO_CARDS: intel iris
```

---

### Switching GPU Drivers

If you need to change GPU drivers after installation:

1. Edit `/etc/portage/package.use/00-video_cards`
2. Edit `/etc/portage/package.use/10-{nvidia|amd|intel}`
3. Rebuild affected packages:
   ```bash
   emerge -avuDN @world
   ```
4. Reboot

---

## Русский

### Поддерживаемые производители GPU

Установщик поддерживает три основных производителя GPU с автоматической установкой и настройкой драйверов.

#### 🟢 NVIDIA

**Устанавливаемые драйверы:**
- `x11-drivers/nvidia-drivers` - Проприетарные драйверы NVIDIA с поддержкой Wayland

**Возможности:**
- Полная поддержка композиторов Wayland
- Совместимость с X11 через XWayland
- Поддержка Vulkan
- Аппаратное ускорение видео (NVENC/NVDEC)

**Рекомендуется для:**
- GeForce GTX 600 серии и новее
- GeForce RTX серии (полная поддержка трассировки лучей)
- Карты Quadro и Tesla для рабочих станций/серверов

**Конфигурация:**
```
VIDEO_CARDS: nvidia
```

---

#### 🔴 AMD

**Устанавливаемые драйверы:**
- `x11-drivers/xf86-video-amdgpu` - Открытый драйвер AMDGPU
- `dev-libs/amdgpu-pro-opencl` - Поддержка OpenCL (опционально)

**Возможности:**
- Нативные открытые драйверы с отличной поддержкой Wayland
- Vulkan через RADV (RadeonSI)
- Аппаратное ускорение видео (VAAPI, VDPAU)
- Поддержка AMD FreeSync

**Рекомендуется для:**
- Radeon RX 400 серии и новее (Polaris, Vega, RDNA, RDNA2, RDNA3)
- Radeon VII
- Ryzen APU с графикой Vega/RDNA

**Конфигурация:**
```
VIDEO_CARDS: amdgpu radeonsi
```

---

#### 🔵 Intel

**Устанавливаемые драйверы:**
- `x11-drivers/xf86-video-intel` - Драйвер Intel графики
- `media-libs/intel-mediasdk` - Аппаратное ускорение видео

**Возможности:**
- Открытые драйверы с хорошей поддержкой Wayland
- Vulkan через ANV (драйвер Vulkan от Intel)
- Аппаратное ускорение видео (VAAPI)
- Поддержка Intel Quick Sync Video

**Рекомендуется для:**
- Intel HD Graphics 2000 и новее
- Intel Iris Graphics
- Дискретные GPU Intel Arc

**Конфигурация:**
```
VIDEO_CARDS: intel iris
```

---

### Переключение драйверов GPU

Если нужно изменить драйверы GPU после установки:

1. Отредактируйте `/etc/portage/package.use/00-video_cards`
2. Отредактируйте `/etc/portage/package.use/10-{nvidia|amd|intel}`
3. Пересоберите затронутые пакеты:
   ```bash
   emerge -avuDN @world
   ```
4. Перезагрузитесь

---

<div align="center">

**Note:** The installer automatically detects and configures the selected GPU during installation.

**Примечание:** Установщик автоматически определяет и настраивает выбранный GPU во время установки.

</div>
