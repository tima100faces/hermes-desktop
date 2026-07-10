# Hermes Desktop — Project Status

> **Дата:** 2026-07-10  
> **Сессия:** 2026-07-10 (имплементация)

---

## Статус: ✅ MVP работает

Чат функционирует end-to-end: отправка сообщений → SSE-стриминг → рендеринг ответов.

## Принятые решения

| # | Решение | Почему |
|---|---|---|
| 1 | **Модель:** DeepSeek V4 Pro | SWE-bench 80.6%, LiveCodeBench 93.5%, $3.48/1M |
| 2 | **Пайплайн:** 6 волн delegate_task | 16 агентов, $0.30 за всю имплементацию |
| 3 | **API URL:** `https://storozhev.me/hermes-api` | HTTPS + nginx, быстрее прямого IP на ~100ms |
| 4 | **Ключ:** Bearer token через macOS Keychain | `AfterFirstUnlock` — без повторных запросов |
| 5 | **SSE формат:** `event` внутри JSON | API шлёт `{"event": "message.delta", "delta": "..."}` |
| 6 | **URL-конструкция:** строковая конкатенация | `appendingPathComponent` и `relativeTo` ломают пути |

## Баги, обнаруженные и исправленные

1. **SSE-формат не совпадал** — ожидали `event: message.delta` как SSE-заголовок, а API шлёт `event` внутри JSON
2. **`appendingPathComponent` кодировал слэши** — путь `/v1/runs/{id}/events` превращался в `%2F`
3. **`URL(string:relativeTo:)` дропал `/hermes-api`** — абсолютный путь заменял базовый
4. **`BubbleShape` давал артефакты** — заменён на `RoundedRectangle`
5. **Дублирующиеся `#Preview` оверлеи** — `replace_all` создал копии
6. **Keychain `WhenUnlocked`** — запрашивал пароль при каждом запуске

## Текущий код

- **Файлов:** 29 Swift + тесты
- **Строк:** ~3 800 production + тесты
- **Зависимости:** 0 (только Apple SDK)
- **Билд:** `make app` → BUILD SUCCEEDED

## Тесты

- **Unit:** 30 тестов (APIError, Models, ViewModels, DesignSystem, SSEClient, Search)
- **Integration:** `scripts/test-integration.sh` (7/8 pass)
- **Автотест:** cron каждые 6ч через delegate_task

## Nginx на VPS

Требуется для SSE-стриминга:
```nginx
location /hermes-api/ {
    proxy_pass http://127.0.0.1:8642/;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    chunked_transfer_encoding on;
}
```

## Что дальше (v1.1)

- [ ] Кнопка Stop в чате
- [ ] Markdown-рендеринг (жирный, код, списки)
- [ ] Subagent-мониторинг
- [ ] Темы оформления (светлая)
- [ ] Spotlight-поиск по истории

---

*Документ обновляется каждую сессию.*
