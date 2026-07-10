# Hermes Desktop Documentation

> Как хранится и читается документация между сессиями.

---

## Структура

```
hermes-desktop/docs/
├── README.md      ← этот файл (конвенции)
├── ADR.md         ← Architecture Decision Records (решения)
├── SPEC.md        ← Техническое задание (что строим)
├── PLAN.md        ← Архитектурный план (как строим)
└── TASKS.md       ← Атомарные задачи (в каком порядке)

source code/       ← имплементация (Swift)
```

## Как агенты читают документацию

### Между сессиями
1. При старте сессии: `git pull` в `~/Projects/hermes-desktop`
2. Агенты читают: SPEC.md → PLAN.md → TASKS.md (в этом порядке)
3. После сессии: коммит изменений + пуш

### Внутри сессии (delegate_task)
Каждый агент получает в context:
- Полный путь к файлам: `~/Projects/hermes-desktop/docs/SPEC.md`, `PLAN.md`, `TASKS.md`
- Описание конкретной задачи (из TASKS.md)
- Правила: code-review-and-quality, spec-driven-development

### Файловая конвенция
- `docs/*.md` — вся проектная документация
- Формат: Markdown с GitHub Flavored Markdown
- Фронтматтер: Status, Date в начале каждого файла
- Все решения → ADR.md (формат: ADR-N: заголовок)
- Все изменения в спеке/плане → новый ADR

## Связанные репозитории

- [agents-hub](https://github.com/tima100faces/agents-hub) — вики, память, скиллы
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) — сам Hermes API

## Текущий статус (2026-07-10)

- [x] Phase 0: Обсуждение подхода
- [x] Phase 1: SPEC.md
- [x] Phase 2: PLAN.md
- [x] Phase 3: TASKS.md
- [ ] Phase 4: IMPLEMENT
