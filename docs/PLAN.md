# Architecture Plan — Hermes Desktop

> **Статус:** Phase 2 — PLAN (на ревью)
> **Дата:** 2026-07-10

---

## 1. Component Dependency Graph

```
                    ┌─────────────────────────────────┐
                    │     HermesDesktopApp (@main)      │
                    │     AppState (DI container)        │
                    └──────────┬───────────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
  ┌───────▼──────┐   ┌────────▼───────┐   ┌───────▼──────┐
  │  Onboarding   │   │    Sidebar      │   │    Chat      │
  │  (setup API)  │   │  (projects list)│   │  (messages)   │
  └───────┬──────┘   └────────┬───────┘   └───────┬──────┘
          │                    │                    │
          └────────────────────┼────────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
  ┌───────▼──────┐   ┌────────▼───────┐   ┌───────▼──────┐
  │   RunsAPI     │   │ SearchService  │   │GitSyncService│
  │  (POST/GET)   │   │ (SwiftData)    │   │  (git pull)  │
  └───────┬──────┘   └────────┬───────┘   └──────────────┘
          │                    │
  ┌───────▼──────┐   ┌────────▼───────┐
  │HermesAPIClient│   │  SwiftData     │
  │ SSEClient    │   │  Models        │
  └───────┬──────┘   └────────┬───────┘
          │                    │
  ┌───────▼──────┐   ┌────────▼───────┐
  │KeychainManager│   │  DesignSystem  │
  │  APIError     │   │  (Colors/Fonts) │
  └───────────────┘   └────────────────┘
```

### Dependency Rules
- **App** → Features → Core → Foundation
- Никаких обратных зависимостей
- Foundation-слой: ноль зависимостей от других слоёв
- Core-слой: зависит только от Foundation
- Features: зависит от Core + Foundation
- App: зависит от всего

---

## 2. Implementation Phases

### Phase A: Foundation (4 компонента, параллельно)

| Компонент | Файлы | Зависимости | Верификация |
|---|---|---|---|
| **DesignSystem** | `Colors.swift`, `Typography.swift`, `Icons.swift` | Нет | SwiftUI Preview компилируется |
| **Models** | `Project.swift`, `Message.swift`, `RunEvent.swift`, `AgentStatus.swift` | Нет | SwiftData схема валидна |
| **KeychainManager** | `KeychainManager.swift` | Нет | Unit test: save/read/delete |
| **APIError** | `APIError.swift` | Нет | Enum с маппингом HTTP-статусов |

### Phase B: Core Services (3 компонента, параллельно)

| Компонент | Файлы | Зависимости | Верификация |
|---|---|---|---|
| **HermesAPIClient** | `HermesAPIClient.swift` | KeychainManager, APIError | Integration test с URLProtocol mock |
| **SSEClient** | `SSEClient.swift` | RunEvent | Парсит SSE-поток из тестовых данных |
| **GitSyncService** | `GitSyncService.swift` | Нет (standalone Process) | Dry-run: проверка наличия git |

### Phase C: API Layer

| Компонент | Файлы | Зависимости | Верификация |
|---|---|---|---|
| **RunsAPI** | `RunsAPI.swift` | HermesAPIClient, SSEClient | Integration: POST /v1/runs → mock SSE stream |

### Phase D: Search (параллельно с C)

| Компонент | Файлы | Зависимости | Верификация |
|---|---|---|---|
| **SearchService** | `SearchService.swift` | SwiftData Models | Unit: поиск по Mock-данным |

### Phase E: Features (Onboarding + Sidebar параллельно)

| Компонент | Зависимости | Верификация |
|---|---|---|
| **Onboarding** (View + ViewModel) | HermesAPIClient, KeychainManager | UI test: ввод URL+ключа → health check |
| **Sidebar** (View + ViewModel) | SwiftData Project модель | Preview с mock-проектами |

### Phase F: Chat Feature

| Компонент | Зависимости | Верификация |
|---|---|---|
| **Chat** (View + ViewModel + MessageBubble + MarkdownRenderer) | RunsAPI, Models, SearchService | Integration: send → receive SSE → display |

### Phase G: Settings + App Assembly

| Компонент | Зависимости | Верификация |
|---|---|---|
| **Settings** | KeychainManager, GitSyncService | Manual: сменить URL, переподключиться |
| **AppState + HermesDesktopApp** | Все Features | App запускается, показывает Onboarding или Sidebar |

---

## 3. Parallel vs Sequential

```
Phase A ────────────┐
  │ (4 parallel)     │
  ▼                  │
Phase B ────────────┐│
  │ (3 parallel)     ││
  ├──────────┐       ││
  ▼          ▼       ││
Phase C   Phase D    ││
  │          │       ││
  └────┬─────┘       ││
       ▼             ││
Phase E ─────────────┘│
  │ (2 parallel)       │
  └──────┬─────────────┘
         ▼
Phase F ───────────────
         │
         ▼
Phase G ───────────────
```

**Параллельно можно делать:**
- Внутри Phase A: все 4 компонента
- Внутри Phase B: все 3 компонента
- Phase C и Phase D — одновременно
- Onboarding и Sidebar в Phase E — одновременно

**Последовательно (зависимости):**
- Phase A → Phase B (Foundation нужна Core)
- Phase B → Phase C (APIClient нужен RunsAPI)
- Phase C + D → Phase E (API нужен фичам)
- Phase E → Phase F (Chat требует Onboarding + Sidebar для навигации)
- Phase F → Phase G (App собирает всё вместе)

---

## 4. Verification Checkpoints

| Фаза | Checkpoint | Что проверяем |
|---|---|---|
| A | Foundation компилируется | `swift build` (если SPM) или Xcode target |
| B | Core тесты проходят | `xcodebuild test` для Core-таргета |
| C | API mock integration | SSE-поток парсится без ошибок |
| D | Поиск работает | Поиск по 100 mock-сообщениям < 100ms |
| E | UI грузится | Onboarding принимает URL/ключ, Sidebar показывает проекты |
| F | Чат работает | Сообщение → SSE → Markdown рендерится |
| G | App запускается | Полный цикл: запуск → onboarding → чат |

---

## 5. Risks and Mitigations

| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| SSE-парсер глючит на реальном API | Средняя | Высокое | Mock-сервер в тестах + тест с реальным API на VPS |
| SwiftData миграции при изменении схемы | Низкая | Среднее | Lightweight migration, версионирование схемы |
| Swift 6 strict concurrency блокирует компиляцию | Средняя | Среднее | Actor для APIClient, @MainActor для ViewModel |
| Git-синк падает без git в PATH | Низкая | Низкое | Graceful degradation: показать warning, не блокировать |
| API-ключ не сохраняется в Keychain (sandbox) | Средняя | Высокое | Keychain Access Groups, entitlement |
| DeepSeek V4 Pro генерирует неправильный Swift-код | Высокая | Среднее | Code review агентом, build verification после каждого изменения |

---

## 6. Design System: Hallmark → SwiftUI

Адаптируем hallmark-токены (oklch) в SwiftUI Color assets:

```swift
// DesignSystem/Colors.swift
import SwiftUI

extension Color {
    // Map hallmark tokens → SwiftUI Color
    static let hkPaper    = Color(oklch: (0.12, 0.008, 270))
    static let hkSurface   = Color(oklch: (0.18, 0.012, 270))
    static let hkSurface2  = Color(oklch: (0.22, 0.014, 270))
    static let hkRule      = Color(oklch: (0.28, 0.015, 270))
    static let hkNeutral   = Color(oklch: (0.50, 0.012, 270))
    static let hkMuted     = Color(oklch: (0.65, 0.008, 270))
    static let hkInk       = Color(oklch: (0.93, 0.005, 270))
    static let hkAccent    = Color(oklch: (0.58, 0.22, 285))
    static let hkAccent2   = Color(oklch: (0.72, 0.18, 285))
}

// oklch → sRGB conversion helper
extension Color {
    init(oklch: (l: Double, c: Double, h: Double)) {
        // oklch → oklab → linear sRGB → sRGB
        // Implementation via NSColor or CGColor conversion
    }
}
```

### Typography
- Системный шрифт: SF Pro (body), SF Mono (code)
- Размеры: caption (11), body (13), title (16), heading (20)
- Межстрочный: 1.4 для body, 1.2 для heading

### Spacing (4px grid как в hallmark)
```swift
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}
```

---

## 7. Data Flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  User    │    │ ChatVM   │    │ RunsAPI  │    │ Hermes   │
│  types   │───▶│ .send()  │───▶│ POST     │───▶│ VPS      │
│          │    │          │    │ /v1/runs │    │ :8642    │
└──────────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘
                     │               │               │
                     │          ┌────▼─────┐    ┌────▼─────┐
                     │          │ SSEClient│◀───│ SSE      │
                     │          │ events   │    │ stream   │
                     │          └────┬─────┘    └──────────┘
                     │               │
                     │     ┌─────────▼──────────┐
                     │     │ text_delta → append │
                     │     │ tool_call → status   │
                     │     │ run_completed → done │
                     │     └─────────┬──────────┘
                     │               │
                     ▼               ▼
              ┌──────────────────────────┐
              │     SwiftData            │
              │     Message.save()       │
              └──────────────────────────┘
```

---

## 8. SwiftData Schema

```swift
@Model
final class Project {
    var name: String
    var conversationKey: String    // Hermes "conversation" param
    var createdAt: Date
    var lastActiveAt: Date
    @Relationship(deleteRule: .cascade) var messages: [Message]
}

@Model
final class Message {
    var content: String             // Markdown body
    var role: String                // "user" | "assistant" | "tool"
    var timestamp: Date
    var runId: String?              // Hermes run ID
    var project: Project?
}
```

---

## 9. Agent Pipeline for Implementation

Каждая фаза делегируется агенту:

```
For each Phase (A → G):
  ① delegate_task: IMPLEMENT phase
  ② delegate_task: CODE REVIEW (5-axis)
  ③ delegate_task: WRITE TESTS
  ④ Terminal: xcodebuild → verify build
  ⑤ Если build ❌ → feedback → agent fix → repeat
```

---

*План заморожен до ревью Тимом.*
