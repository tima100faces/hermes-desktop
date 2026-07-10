# Implementation Tasks — Hermes Desktop

> **Статус:** Phase 3 — TASKS (на ревью)
> **Дата:** 2026-07-10
> **Модель:** DeepSeek V4 Pro (все агенты)
> **Параллельно:** до 5 агентов через delegate_task

---

## Правила исполнения

- Каждая задача = один delegate_task с изолированным контекстом
- После каждой задачи: xcodebuild → PASS обязательно
- Если build ❌ → агент фиксит (self-correcting loop)
- Задачи внутри фазы выполняются параллельно
- Фазы — последовательно (зависимости из PLAN.md)

---

## Phase A: Foundation

### ✅ A1: DesignSystem
- **Что:** Colors.swift, Typography.swift, Spacing.swift. hallmark oklch-токены в SwiftUI Color extension.
- **Acceptance:** Все токены из PLAN.md §6 реализованы. oklch→sRGB конвертация корректна.
- **Verify:** SwiftUI Preview с hkPaper/hkAccent/hkInk рендерится без ошибок.
- **Files:** `DesignSystem/Colors.swift`, `DesignSystem/Typography.swift`, `DesignSystem/Spacing.swift`

### ✅ A2: SwiftData Models
- **Что:** Project, Message (SwiftData @Model). Схема из PLAN.md §8. cascade delete для messages.
- **Acceptance:** Схема компилируется, relationships корректны. Message.role — enum String.
- **Verify:** `xcodebuild` + unit test: создать Project, добавить Message, прочитать обратно.
- **Files:** `Models/Project.swift`, `Models/Message.swift`, `Models/RunEvent.swift`, `Models/AgentStatus.swift`

### ✅ A3: KeychainManager
- **Что:** Чтение/запись/удаление API-ключа в macOS Keychain. SecItemAdd/SecItemCopyMatching/SecItemDelete.
- **Acceptance:** Ключ сохраняется, читается, удаляется. После удаления read возвращает nil.
- **Verify:** Unit test с временным ключом.
- **Files:** `Core/Auth/KeychainManager.swift`

### ✅ A4: APIError
- **Что:** Enum с HTTP-статусами (unauthorized, notFound, serverError, networkError, decodingError). LocalizedError.
- **Acceptance:** Все кейсы мапятся с HTTPURLResponse.statusCode. errorDescription осмысленное.
- **Verify:** Unit test: HTTP 401 → .unauthorized, URLError.notConnectedToInternet → .networkError.
- **Files:** `Core/API/APIError.swift`

---

## Phase B: Core Services

### ✅ B1: HermesAPIClient
- **Что:** Actor. Базовый HTTP-клиент: `request<T: Decodable>(_ endpoint: Endpoint) async throws -> T`. Endpoint — enum с path, method, query. Bearer token из KeychainManager. Без сторонних библиотек.
- **Acceptance:** GET /health возвращает статус. 401 → выброс APIError.unauthorized. Таймаут 30с.
- **Verify:** Integration test с URLProtocol mock: 200 → декодинг, 401 → APIError.
- **Files:** `Core/API/HermesAPIClient.swift`

### ✅ B2: SSEClient
- **Что:** AsyncStream<RunEvent>. Парсит SSE-поток (text/event-stream). Поддерживает: text_delta, tool_call, tool_result, run_completed, run_failed. Разделитель: двойной \n.
- **Acceptance:** Поток из тестовых данных парсится в корректные RunEvent. run_completed закрывает стрим.
- **Verify:** Unit test с mock-стримом (5 событий → 5 RunEvent, стрим закрыт).
- **Files:** `Core/API/SSEClient.swift`

### ✅ B3: GitSyncService
- **Что:** Process.run("git", "pull", "--ff-only") в ~/Projects/agents-hub. Асинхронно. Graceful degradation — ошибка не блокирует запуск.
- **Acceptance:** Вызов git pull. При отсутствии git — warning, не crash. Результат логируется.
- **Verify:** Dry-run на реальной директории ~/Projects/agents-hub.
- **Files:** `Core/Sync/GitSyncService.swift`

---

## Phase C: API Layer

### ✅ C1: RunsAPI
- **Что:** Высокоуровневый API для работы с Hermes Runs. Методы: `createRun(input:conversation:) -> RunResponse`, `streamEvents(runId:) -> AsyncStream<RunEvent>`, `getRunStatus(runId:) -> RunStatus`, `stopRun(runId:)`.
- **Acceptance:** createRun возвращает run_id. streamEvents возвращает поток SSE-событий. stopRun отправляет POST /v1/runs/{id}/stop.
- **Verify:** Integration test с URLProtocol mock: POST /v1/runs → ответ с run_id, GET /v1/runs/{id}/events → mock SSE-поток.
- **Files:** `Core/API/RunsAPI.swift`

---

## Phase D: Search

### ✅ D1: SearchService
- **Что:** Полнотекстовый поиск по Message.content в SwiftData. Предикат: CONTAINS. Асинхронно. Дебаунс 300ms.
- **Acceptance:** Поиск по 100 mock-сообщениям < 100ms. Результаты отсортированы по timestamp desc.
- **Verify:** Unit test: создать 100 сообщений, поиск "fibonacci" → правильные результаты.
- **Files:** `Core/Search/SearchService.swift`

---

## Phase E: Features

### ✅ E1: Onboarding
- **Что:** OnboardingView + OnboardingViewModel. Два поля: API URL (TextField) + API Key (SecureField). Кнопка "Connect". При нажатии: сохраняет URL в UserDefaults, ключ в KeychainManager, проверяет GET /health. При успехе — переход к Sidebar.
- **Acceptance:** URL и ключ сохраняются. Health check → success → переход. Health check → fail → ошибка. Валидация: URL не пустой, ключ не пустой.
- **Verify:** UI test: ввод валидного URL+ключа → переход. Невалидного → ошибка (alert).
- **Files:** `Features/Onboarding/OnboardingView.swift`, `Features/Onboarding/OnboardingViewModel.swift`

### ✅ E2: Sidebar
- **Что:** SidebarView + SidebarViewModel. Список проектов (SwiftData @Query). "+" кнопка для создания. Удаление через контекстное меню. Выбор проекта → ChatView. SwiftUI NavigationSplitView.
- **Acceptance:** Проекты отображаются. Создание: name + conversationKey. Удаление с подтверждением. Активный проект выделен.
- **Verify:** Preview с mock-проектами. UI test: создать 3 проекта, выбрать второй, удалить.
- **Files:** `Features/Sidebar/SidebarView.swift`, `Features/Sidebar/SidebarViewModel.swift`, `Features/Sidebar/ProjectRow.swift`

---

## Phase F: Chat

### ✅ F1: ChatViewModel
- **Что:** @Observable. Управление сообщениями: sendMessage(), stopStreaming(). SSE через RunsAPI.streamEvents(). text_delta → append к streamingContent. run_completed → сохранить Message в SwiftData. Обработка tool_call/tool_result (инлайн-статус). inputText binding с debounce-валидацией.
- **Acceptance:** Сообщение отправляется → SSE стримится → сохраняется в SwiftData. Stop останавливает стрим. Пустой ввод игнорируется.
- **Verify:** Unit test с mock RunsAPI: send → получаем SSE → streamingContent заполняется → run_completed → Message в базе.
- **Files:** `Features/Chat/ChatViewModel.swift`

### ✅ F2: ChatView + InputBar
- **Что:** ChatView — ScrollView с LazyVStack сообщений + InputBar в safeAreaInset. InputBar: TextField, кнопка Send (бумажный самолётик SF Symbol), кнопка Stop (квадрат) при стриминге. Автоскролл к последнему сообщению.
- **Acceptance:** Сообщения отображаются. ScrollView прокручивается. Send отправляет. Stop прерывает. Клавиша Enter отправляет.
- **Verify:** UI test: ввести текст, нажать Send → сообщение появляется.
- **Files:** `Features/Chat/ChatView.swift`

### ✅ F3: MessageBubble + MarkdownRenderer
- **Что:** MessageBubble — пузырь сообщения (user: accent справа, assistant: surface слева). MarkdownRenderer — AttributedString из Markdown (iOS 15+ native). Поддержка: **bold**, *italic*, `code`, ```code blocks```, > quotes.
- **Acceptance:** Markdown рендерится корректно. Code blocks моноширинным шрифтом. Пузыри выровнены (user trailing, assistant leading).
- **Verify:** Preview с разными типами сообщений. Markdown-контент рендерится.
- **Files:** `Features/Chat/MessageBubble.swift`, `Features/Chat/MarkdownRenderer.swift`

### ✅ F4: StreamingText
- **Что:** Анимированный текст при стриминге. Мигающий курсор в конце. Плавное появление новых токенов.
- **Acceptance:** Текст появляется посимвольно/потоково. Курсор мигает. При run_completed курсор исчезает.
- **Verify:** Preview с симуляцией streaming-текста.
- **Files:** `Features/Chat/StreamingText.swift`

---

## Phase G: Assembly

### ✅ G1: Settings
- **Что:** SettingsView + SettingsViewModel. Поля: API URL, API Key. Git Sync статус + кнопка "Sync Now". Версия приложения. About.
- **Acceptance:** URL меняется → сохраняется. Ключ меняется → Keychain. Sync показывает результат.
- **Verify:** UI test: открыть Settings, изменить URL, проверить сохранение.
- **Files:** `Features/Settings/SettingsView.swift`, `Features/Settings/SettingsViewModel.swift`

### ✅ G2: AppState + HermesDesktopApp
- **Что:** AppState — @Observable, DI-контейнер: инициализация APIClient, KeychainManager, GitSyncService. Проверка при старте: есть ключ в Keychain → Sidebar. Нет → Onboarding. HermesDesktopApp — @main, WindowGroup, NavigationSplitView(Sidebar, Chat). GitSync при запуске.
- **Acceptance:** Приложение запускается. С ключом → Sidebar. Без ключа → Onboarding. Git-синк при старте.
- **Verify:** Запуск приложения, полный цикл.
- **Files:** `App/HermesDesktopApp.swift`, `App/AppState.swift`

---

## Task Summary

| Фаза | Задач | Параллельно | Оценка токенов* |
|---|---|---|---|
| A: Foundation | 4 | 4 агента | ~8K output |
| B: Core Services | 3 | 3 агента | ~12K output |
| C: API Layer | 1 | 1 агент (с D1) | ~4K output |
| D: Search | 1 | 1 агент (с C1) | ~3K output |
| E: Features | 2 | 2 агента | ~10K output |
| F: Chat | 4 | 2-4 агента** | ~20K output |
| G: Assembly | 2 | 2 агента | ~6K output |
| **Total** | **17** | **5 waves** | **~63K output** |

\* Приблизительно. DeepSeek V4 Pro: ~$0.22 за всю имплементацию.
\** Chat зависит от Sidebar (навигация), но ChatViewModel можно параллельно с UI компонентами.

---

*Задачи заморожены до ревью Тимом. После апрува — Phase 4: IMPLEMENT.*
