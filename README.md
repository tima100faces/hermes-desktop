# Hermes Desktop

Нативный macOS-клиент для Hermes Agent (VPS), с git-синком личности, топиками и мультиагентской оркестрацией.

## Зачем

**Проблемы текущего Telegram-интерфейса:**

1. Одна простыня чата — нельзя разбить на темы/проекты
2. Неудобно возвращаться к старым диалогам — линейная прокрутка
3. Не видно, какие subagent'ы работают и что делают
4. Нет быстрых действий (ревью, имплементация) — всё через текст
5. Telegram как платформа не предназначен для девелоперского workflow

**Что хотим:**

- Разбивка на топики/треды — каждый проект или задача в своём контексте
- Нативная macOS-скорость — SwiftUI, не Electron
- Подключение к удалённому Hermes API (порт 8642)
- Git-синк личности через agents-hub — тот же Rusty, что в Telegram
- Мультиагентская оркестрация: запуск subagent'ов, просмотр их прогресса
- Удобный поиск по истории сессий

## Как запустить (будет)

```bash
git clone git@github.com:tima100faces/hermes-desktop.git
cd hermes-desktop
open HermesDesktop.xcodeproj
# Cmd+R
```

## Связанные проекты

- [agents-hub](https://github.com/tima100faces/agents-hub) — git-синк личности, скиллы, память
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — сам Hermes

## Референсы

- [dodo-reach/hermes-desktop](https://github.com/dodo-reach/hermes-desktop) — существующий SwiftUI-клиент (SSH, 2k звёзд)
- [AI Chat UI Best Practices](https://www.setproduct.com/blog/ai-chat-interface-ui-design) — паттерны интерфейсов
