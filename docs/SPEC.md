# Spec: Hermes Desktop — macOS SwiftUI Client

> **Статус:** Phase 1 — SPECIFY (на ревью)  
> **Дата:** 2026-07-10  
> **Модель для имплементации:** DeepSeek V4 Pro

---

## 1. Objective

**Что:** Нативный macOS-клиент для удалённого Hermes Agent (VPS, порт 8642).

**Проблемы, которые решаем (vs Telegram):**
- Одна простыня чата → разбивка на проекты/топики (как Claude Desktop)
- Неудобный возврат к истории → сайдбар с проектами + поиск
- Не видно subagent'ов → инлайн-статус в чате
- Нет быстрых действий → кнопки Review/Code/Test

**Кто пользователь:** Тим (один пользователь, одно подключение к API).

**Что такое «готово» (Success Criteria):**
- Приложение запускается на macOS 14+, подключается к Hermes API по ключу
- Можно создать проект, отправить сообщение, получить streaming-ответ с Markdown
- История сохраняется локально, поиск работает офлайн
- Git-синк agents-hub при старте

---

## 2. Tech Stack

| Слой | Технология | Почему |
|---|---|---|
| Язык | Swift 6 | Native macOS, strict concurrency |
| UI | SwiftUI | Нативно, легковесно (ADR-1) |
| Архитектура | MVVM + Use Cases | Не переусложняем (ADR-3) |
| Сеть | URLSession + async/await | SSE streaming без сторонних библиотек |
| Хранение | SwiftData (SQLite) | Нативно, @Query, офлайн (ADR-4) |
| Ключи | macOS Keychain | Безопасно, системно |
| Структура | Feature-based | Изоляция фич (ADR-5) |
| Зависимости | **Ноль** сторонних библиотек | Только Apple SDK |
| Тесты | XCTest + Swift Testing | Нативно |
| Минимальная OS | macOS 14 Sonoma | @Observable, SwiftData |

---

## 3. Commands

```bash
# Генерация Xcode проекта
xcodebuild -project HermesDesktop.xcodeproj -list

# Сборка
xcodebuild -project HermesDesktop.xcodeproj \
  -scheme HermesDesktop \
  -configuration Debug \
  build

# Тесты
xcodebuild -project HermesDesktop.xcodeproj \
  -scheme HermesDesktop \
  -configuration Debug \
  test

# Архив для Release
xcodebuild -project HermesDesktop.xcodeproj \
  -scheme HermesDesktop \
  -configuration Release \
  archive -archivePath ./build/HermesDesktop.xcarchive
```

---

## 4. API Surface (Hermes)

Все endpoint'ы требуют `Authorization: Bearer <API_SERVER_KEY>`.

### Используемые endpoint'ы

| Метод | Endpoint | Зачем |
|---|---|---|
| `POST` | `/v1/runs` | Отправить сообщение, создать run |
| `GET` | `/v1/runs/{run_id}/events` | SSE-стриминг ответа |
| `GET` | `/v1/runs/{run_id}` | Проверить статус run'а |
| `POST` | `/v1/runs/{run_id}/stop` | Остановить генерацию |
| `GET` | `/v1/capabilities` | Проверить доступные фичи |
| `GET` | `/health` | Проверка соединения |

### Параметры Runs API

```json
// POST /v1/runs
{
  "input": "текст сообщения",
  "conversation": "project-name",
  "session_id": "optional-custom-session-id"
}
```

### SSE Events (из /v1/runs/{id}/events)

Поддерживаемые типы событий:
- `text_delta` — токен текста (Markdown)
- `tool_call` — агент вызвал инструмент
- `tool_result` — результат вызова инструмента
- `run_completed` — run завершён
- `run_failed` — ошибка

### Проекты = Conversations

- Проект в сайдбаре ↔ параметр `conversation` в Runs API
- Локально SwiftData хранит: `id`, `name`, `conversationKey`, `createdAt`, `lastActiveAt`
- История сообщений хранится локально для офлайн-доступа

---

## 5. Project Structure

```
HermesDesktop/
├── App/
│   ├── HermesDesktopApp.swift       ← @main, DI
│   └── AppState.swift               ← глобальное состояние
│
├── Features/
│   ├── Sidebar/
│   │   ├── SidebarView.swift         ← список проектов
│   │   ├── SidebarViewModel.swift
│   │   └── ProjectRow.swift
│   │
│   ├── Chat/
│   │   ├── ChatView.swift            ← основной чат + поле ввода
│   │   ├── ChatViewModel.swift
│   │   ├── MessageBubble.swift       ← пузырь сообщения
│   │   ├── MarkdownRenderer.swift    ← рендер Markdown
│   │   └── StreamingText.swift       ← анимированный streaming
│   │
│   ├── Onboarding/
│   │   ├── OnboardingView.swift      ← ввод API URL и ключа
│   │   └── OnboardingViewModel.swift
│   │
│   └── Settings/
│       ├── SettingsView.swift
│       └── SettingsViewModel.swift
│
├── Core/
│   ├── API/
│   │   ├── HermesAPIClient.swift     ← HTTP-клиент
│   │   ├── RunsAPI.swift             ← /v1/runs/*
│   │   ├── SSEClient.swift           ← SSE парсер
│   │   └── APIError.swift            ← ошибки API
│   │
│   ├── Auth/
│   │   └── KeychainManager.swift     ← чтение/запись API-ключа
│   │
│   ├── Sync/
│   │   └── GitSyncService.swift      ← git pull agents-hub
│   │
│   └── Search/
│       └── SearchService.swift       ← поиск по истории
│
├── Models/
│   ├── Project.swift                 ← SwiftData модель проекта
│   ├── Message.swift                 ← SwiftData модель сообщения
│   ├── RunEvent.swift                ← SSE-события
│   └── AgentStatus.swift             ← статус subagent'а
│
├── DesignSystem/
│   ├── Colors.swift                  ← цветовая схема (из hallmark)
│   ├── Typography.swift              ← шрифты
│   ├── Icons.swift                   ← SF Symbols каталог
│   └── Components/
│       ├── PrimaryButton.swift
│       ├── StatusBadge.swift
│       └── SidebarItemStyle.swift
│
├── Shared/
│   ├── Extensions/
│   │   ├── String+Markdown.swift
│   │   └── Date+Relative.swift
│   └── Utilities/
│       ├── Debouncer.swift
│       └── Logger.swift
│
└── Tests/
    ├── HermesDesktopTests/
    │   ├── API/
    │   │   ├── HermesAPIClientTests.swift
    │   │   └── SSEClientTests.swift
    │   ├── Features/
    │   │   ├── ChatViewModelTests.swift
    │   │   └── SidebarViewModelTests.swift
    │   └── Models/
    │       └── ProjectTests.swift
    │
    └── HermesDesktopUITests/
        └── ChatFlowUITests.swift
```

---

## 6. Code Style

```swift
// MARK: - View
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                InputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    onSend: { viewModel.sendMessage() },
                    onStop: { viewModel.stopStreaming() }
                )
            }
        }
    }
}

// MARK: - ViewModel
@Observable
final class ChatViewModel {
    private let apiClient: HermesAPIClient
    private let project: Project

    var messages: [Message] = []
    var inputText = ""
    var isStreaming = false
    var streamingContent = ""

    func sendMessage() async { ... }
    func stopStreaming() { ... }
}
```

### Конвенции
- **Нейминг:** Swift API Design Guidelines. `sendMessage()`, не `send_message`. `isStreaming`, не `streaming`
- **Файлы:** Один тип на файл (исключение: мелкие вложенные enum/struct)
- **MARK-комментарии:** `// MARK: - Properties`, `// MARK: - Public`, `// MARK: - Private`
- **@Observable:** для ViewModel (Swift 6, macOS 14+)
- **protocol + actor:** для сервисов (APIClient как actor)
- **async/await:** без completion handler'ов и GCD
- **guard let:** вместо force-unwrap. `fatalError` только для programmer errors
- **Локализация:** только английский в коде, без `.strings` в MVP

---

## 7. Testing Strategy

### Уровни тестирования

| Уровень | Что тестируем | Инструмент | Где |
|---|---|---|---|
| Unit | ViewModel-логика, парсеры, модели | XCTest | `Tests/HermesDesktopTests/` |
| Integration | API-клиент (mock-сервер), SSE-парсер | XCTest | `Tests/HermesDesktopTests/API/` |
| UI | Критический путь (онбординг → чат) | XCTest UI | `Tests/HermesDesktopUITests/` |

### Покрытие
- Unit: каждый ViewModel и парсер
- Integration: API-клиент с `URLProtocol` mock'ом
- UI: smoke-тест основного flow

### Моки
- `URLProtocol` для API (без сторонних библиотек)
- `@Previewable` для SwiftUI Preview с mock-данными

---

## 8. Boundaries

### Always do:
- Тесты перед коммитом
- Swift 6 strict concurrency (без `@unchecked Sendable`)
- Keychain для API-ключа (никогда в UserDefaults)
- `guard let` без force-unwrap
- Обработка ошибок API (нет соединения, 401, 500)

### Ask first:
- Добавление любой сторонней зависимости
- Изменение схемы SwiftData
- Добавление нового экрана/фичи не из спеки
- Изменение минимальной версии macOS
- Коммит в main

### Never do:
- Хранить API-ключ в UserDefaults/plist/коде
- Force-unwrap опциональные значения
- Блокировать main thread сетевыми запросами
- Игнорировать ошибки API (try? без обработки)
- Использовать WebView для чата

---

## 9. Success Criteria (testable)

- [ ] Приложение собирается без ошибок: `xcodebuild ... build`
- [ ] Все тесты проходят: `xcodebuild ... test`
- [ ] Можно ввести API URL + ключ, подключиться к `/health`
- [ ] Можно создать проект, отправить сообщение, увидеть streaming ответ
- [ ] Сообщения сохраняются в SwiftData и видны после перезапуска
- [ ] Поиск по истории находит сообщения
- [ ] Git-синк agents-hub при старте
- [ ] API-ключ хранится в Keychain, не в UserDefaults

---

## 10. Open Questions

- [ ] Точный дизайн сайдбара — ждём референсов из hallmark/popular-web-designs
- [ ] Формат subagent-статуса инлайн (tool_call event? кастомный формат?)
- [ ] Spotlight-интеграция для поиска — MVP или v1.1?
- [x] API-ключ: Bearer token из `API_SERVER_KEY` на VPS

---

## 11. Design References (собрать через скиллы)

- [hallmark](skill:custom/hallmark) — дизайн-система, тёмная тема, токены
- [popular-web-designs](skill:custom/popular-web-designs) — референсы: Claude Desktop, Cursor, Linear
- SF Symbols 6 — системные иконки
- macOS Human Interface Guidelines — sidebar, toolbar, menus

---

## 12. Implementation Pipeline

```
Phase 1: SPECIFY (← сейчас)
Phase 2: PLAN — архитектурный план, диаграммы
Phase 3: TASKS  — атомарные задачи для delegate_task
Phase 4: IMPLEMENT — параллельные агенты
  ├─ Agent: Implement feature
  ├─ Agent: Code Review (5-axis)
  ├─ Agent: Tests
  └─ Agent: Build verify
```

---

*Спека заморожена до ревью Тимом. Изменения после апрува — через ADR.*
