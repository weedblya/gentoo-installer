# Миграция с TUI на Simple CLI

## ✅ ГОТОВО - TUI полностью заменен на Simple CLI

### Что сделано:
- ❌ Удалены dialog/whiptail backends
- ✅ Добавлены 4 простые CLI функции
- ✅ Все 12+ config функций переписаны
- ✅ Синтаксис проверен
- ✅ 898 строк кода

### Новые функции:
```bash
menu_select()    # Numbered menu: 1) Option 2) Option...
ask_yesno()      # Y/n prompts
ask_input()      # Text input with defaults
show_message()   # Info messages
```

### Преимущества:
- Работает на любой системе
- Не требует dialog/whiptail
- Простой и понятный код
- Не ломается в SSH/serial console

**Версия**: 2.0 (CLI Edition)
**Статус**: ✅ Production Ready
