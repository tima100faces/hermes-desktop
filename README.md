# Hermes Desktop

Нативный macOS-клиент для Hermes Agent (VPS), с git-синком личности,
топиками и мультиагентской оркестрацией.

## Зачем

**Проблемы текущего Telegram-интерфейса:**

1. Одна простыня чата — нельзя разбить на темы
2. Неудобно возвращаться к старым диалогам — линейная прокрутка
3. Не видно, какие subagent'ы работают и что делают
4. Telegram как платформа не предназначен для рабочего workflow

## Статус

MVP работает: темы (Runs API) и свободные чаты (Sessions API),
SSE-стриминг, статусы subagent'ов, git-синк личности. Дизайн — тёмная
тема по мотивам Obsidian с ржавым акцентом (в честь агента Ржавчика),
см. `docs/UI-SPEC.md`.

## Как запустить

```bash
git clone https://github.com/tima100faces/hermes-desktop.git
cd hermes-desktop
make run        # собрать и открыть HermesDesktop.app
```

Требования: macOS 14+, Xcode. При первом запуске — онбординг с URL и
ключом Hermes API.

## Для ИИ-агентов

Перед работой с кодом обязательно прочитать:

- **`CLAUDE.md`** — правила работы с репозиторием и владельцем
- **`docs/UI-SPEC.md`** — дизайн-спека; любое отклонение от неё — баг

## Связанные проекты

- [agents-hub](https://github.com/tima100faces/agents-hub) — git-синк личности, скиллы, память
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — сам Hermes

## Референсы

- [Obsidian design system (Refero)](https://styles.refero.design/style/e793a53c-537e-46b0-881d-b15b63b9ff26) — основа визуального стиля
- [dodo-reach/hermes-desktop](https://github.com/dodo-reach/hermes-desktop) — существующий SwiftUI-клиент (SSH)
- [AI Chat UI Best Practices](https://www.setproduct.com/blog/ai-chat-interface-ui-design) — паттерны интерфейсов
