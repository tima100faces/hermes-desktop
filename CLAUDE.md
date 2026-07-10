# CLAUDE.md — Hermes Desktop

Правила для Claude Code при работе с этим репозиторием.

## О проекте

Нативный macOS-клиент (SwiftUI, Swift Package) для Hermes Agent,
работающего на VPS (порт 8642). Личность агента («Ржавчик») синкуется
через git из репозитория agents-hub. Стриминг ответов — SSE.
Минимальная версия macOS — 14.0, Swift 6 strict concurrency.

## Hermes — внешний сервис

Hermes — внешний сервис. Его код мы не изменяем никогда: Hermes на
VPS — стандартная установка. Взаимодействие — только через его
документированный HTTP API; сам API использовать можно полноценно,
включая создающие и изменяющие эндпоинты (сессии и т.п.).

Изменение конфигурации Hermes на сервере (env, config.yaml),
обновление его версии или любые действия по SSH на VPS — только по
явному разрешению Тима, полученному в этой сессии, и никогда по
собственной инициативе. Если для задачи кажется необходимым изменить
что-то на сервере — остановись и спроси.

## О владельце

Тим — графический дизайнер, **не программист**. Это значит:

- Объясняй решения простым языком, без жаргона. По-русски.
- Перед заметными визуальными изменениями — опиши словами, что
  изменится на экране, и дождись подтверждения.
- Не предлагай фичи по собственной инициативе — только то, что
  просили, плюс беклог в docs/UI-SPEC.md §10.
- Решения из раздела «Решено и закрыто» в UI-SPEC.md не пересматривать
  и не предлагать заново.

## Команды

```bash
make build      # сборка (xcodebuild, scheme HermesDesktop, Debug)
make run        # собрать .app и запустить
make test       # юнит-тесты
make test-all   # юнит + интеграционные (scripts/test-integration.sh)
make clean      # очистка .build и build/
```

После любого изменения кода — `make build` и убедись, что сборка
проходит, прежде чем коммитить.

## Структура

```
HermesDesktop/
  App/            — HermesDesktopApp (@main, ContentView), AppState (DI)
  Core/API/       — HermesAPIClient (actor), RunsAPI, SSEClient,
                    ConnectionMonitor (health-поллинг), APIError
  Core/Auth/      — KeychainManager
  Core/Sync/      — GitSyncService (git pull agents-hub)
  DesignSystem/   — Colors.swift, Typography.swift, Spacing.swift
                    ЕДИНСТВЕННЫЙ источник цветов/шрифтов/отступов
  Features/
    Chat/         — ChatView (+ InputBar, ThinkingIndicator,
                    AgentStatusRow), MessageBubble, CodeBlockView,
                    MarkdownRenderer, StreamingText, ChatViewModel
    Sidebar/      — SidebarView, ProjectRow, CreateProjectSheet
    Settings/     — SettingsView (секция General — точка роста настроек)
    Onboarding/   — OnboardingView
  Models/         — SwiftData: Project, Message; AgentStatus
docs/UI-SPEC.md   — дизайн-спека (ЗАКОН для UI-кода)
```

## Железные правила UI

Перед ЛЮБЫМ изменением UI прочитай `docs/UI-SPEC.md` целиком и пройди
чек-лист в его конце. Самое важное:

1. Цвета — только токены `Color.hk*`; отступы — `Space.*`; шрифты —
   `Font.hk*`. Никаких hex в компонентах.
2. Никакой цветовой математики (oklch и пр.) — только литеральный hex
   в Colors.swift через `Color(hk:)`.
3. Drop shadows запрещены — только inset glow.
4. Каркас: обычный HStack, НЕ NavigationSplitView; сайдбар —
   ScrollView + кнопки, НЕ List. Оба запрета — из-за системных
   материалов/выделений macOS, ломающих дизайн.
5. У каждого `.onHover`-контейнера — `.contentShape(Rectangle())`.
6. `repeatForever`-анимации запускать через `withAnimation` в `.task`.

## Git workflow

- Каждая задача — в feature-ветке (`feature/...`, `fix/...`,
  `design/...`). В main — только после того, как Тим собрал билд и
  подтвердил.
- Коммиты небольшие, сообщения на английском, в повелительном
  наклонении («Fix …», «Add …»).
- Изменил UI — обнови docs/UI-SPEC.md в том же коммите (или следующим).

## Беклог

Актуальный список — в `docs/UI-SPEC.md` §10. На момент написания:
Retry в hover-ряду, Cmd+K палитра проектов, Shift+Enter по позиции
курсора, подсветка синтаксиса в блоках кода.
