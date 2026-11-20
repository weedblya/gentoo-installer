# Changelog - Modular Refactoring

## 2026-11-20 - Modular Architecture

### 🎉 Major Refactoring

Переделан весь установщик под модульную архитектуру по образцу gentoo-installer-gum.

### 📦 Новая структура

**Главные скрипты:**
- `configure.sh` - Интерактивная конфигурация
- `setup.sh` - Главный установочный скрипт-оркестратор
- `gentoo-install-legacy.sh` - Оригинальный скрипт (бэкап)

**Модули (modules/):**
1. `common.sh` - Общие функции, логирование, цвета
2. `hardware-detect.sh` - Детект GPU, виртуализации, типа загрузки
3. `partition.sh` - Разметка диска (GPT/MBR)
4. `filesystem.sh` - Создание и монтирование ФС
5. `stage3.sh` - Загрузка и распаковка Stage3
6. `portage-config.sh` - Настройка Portage
7. `chroot-prepare.sh` - Подготовка chroot
8. `system-config.sh` - Настройка системы (hostname, locale, fstab)
9. `kernel-install.sh` - Установка ядра
10. `bootloader.sh` - Установка GRUB
11. `network.sh` - Настройка сети
12. `users.sh` - Создание пользователей
13. `desktop-install.sh` - Установка DE/WM

### ✨ Преимущества

- ✅ Модульность - каждый модуль независим
- ✅ Читаемость - 100-200 строк вместо 1100+
- ✅ Тестируемость - модули можно запускать отдельно
- ✅ Расширяемость - легко добавлять новые функции
- ✅ Отладка - проще найти баги
- ✅ Совместная разработка - можно работать над разными модулями

### 🔧 Улучшения

- Цветной вывод (красный/зелёный/жёлтый)
- Лучшая обработка ошибок
- Логирование в каждом модуле
- Статус-трекинг для отчётов
- Retry-логика для сетевых операций
- Проверка дискового пространства
- UUID-based fstab entries

### 📝 Использование

```bash
# 1. Конфигурация
./configure.sh

# 2. Установка
./setup.sh
```

### 🔄 Совместимость

- Вся функциональность из legacy-скрипта сохранена
- Legacy-скрипт доступен как `gentoo-install-legacy.sh`
- Конфиг сохраняется в `/tmp/gentoo-installer-config.env`

### 📚 Документация

- `README-MODULAR.md` - полная документация модульной версии
- Комментарии в каждом модуле
- Примеры использования

### 🐛 Исправленные проблемы

Все проблемы из legacy-скрипта исправлены:
- ✅ Dracut installation issues
- ✅ Kernel version detection in live environment
- ✅ Password handling
- ✅ fstab variable expansion
- ✅ EFI mount path
- ✅ Network timeout and retry

---

## Предыдущие версии

См. git history для истории изменений монолитного скрипта.
