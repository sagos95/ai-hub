# Buildin Integration

Интеграция с [Buildin.ai](https://buildin.ai) — вики-платформа для документации.

## Структура

```
integrations/buildin/
├── .claude-plugin/
│   └── plugin.json           # Манифест плагина
├── scripts/
│   ├── buildin.sh            # Level 1: HTTP-клиент (curl + Bearer JWT, UI API)
│   ├── buildin-pages.sh      # Level 2: CRUD + read (markdown) + delete-block
│   ├── buildin-nav.sh        # Level 2: Навигация и поиск по дереву
│   ├── buildin-shadow.sh     # Level 2: Shadow-индекс (локальный кеш)
│   └── buildin-login.sh      # Проверка и сохранение JWT-токена
├── shadow-index.json          # Локальный кеш структуры и саммари страниц
├── commands/
│   ├── read-page.md          # Скилл: чтение страницы (URL/UUID/поиск)
│   ├── publish-page.md       # Скилл: создание/обновление страницы
│   └── buildin-login.md      # Скилл: логин через browser MCP (Google SSO)
└── README.md
```

## Быстрый старт

### 1. Логин

Используй скилл `/ai-hub:buildin-login` — он откроет Buildin через Chrome DevTools MCP, выполнит Google SSO и сохранит JWT-токен в `.env` как `BUILDIN_UI_TOKEN`.

Или вручную:
```bash
# Проверить текущий токен
./integrations/buildin/scripts/buildin-login.sh check

# Сохранить токен из буфера обмена
./integrations/buildin/scripts/buildin-login.sh clipboard
```

JWT-токен живёт ~30 дней.

### 2. Проверь подключение

```bash
./integrations/buildin/scripts/buildin.sh GET /api/users/me
```

## Использование

Все команды принимают UUID или URL buildin.ai:

```bash
# Обе формы эквивалентны:
./integrations/buildin/scripts/buildin-pages.sh read 2a904afe-42e9-4ebd-a94e-f6fe0cbacf58
./integrations/buildin/scripts/buildin-pages.sh read https://buildin.ai/2a904afe-42e9-4ebd-a94e-f6fe0cbacf58
```

### Чтение и навигация

```bash
# Прочитать страницу как markdown (рекурсивно раскрывает columns, toggles)
./integrations/buildin/scripts/buildin-pages.sh read <id|url>

# Заголовок
./integrations/buildin/scripts/buildin-pages.sh title <id|url>

# Родительская страница
./integrations/buildin/scripts/buildin-nav.sh parent <id|url>

# Дочерние страницы (включая вложенные в columns/toggles)
./integrations/buildin/scripts/buildin-nav.sh children <id|url>

# Дерево страниц (2 уровня вглубь)
./integrations/buildin/scripts/buildin-nav.sh tree <id|url> 2

# Поиск по названию (до 4 уровней вглубь)
./integrations/buildin/scripts/buildin-nav.sh search <id|url> "query" 4
```

### Создание и редактирование

```bash
# Создать дочернюю страницу
./integrations/buildin/scripts/buildin-pages.sh create <parent_id|url> "Заголовок"

# Обновить заголовок
./integrations/buildin/scripts/buildin-pages.sh update <id|url> "Новый заголовок"

# Добавить текст
./integrations/buildin/scripts/buildin-pages.sh append-text <id|url> "Новый параграф"

# Добавить блоки (JSON)
./integrations/buildin/scripts/buildin-pages.sh append-blocks <id|url> '<json_blocks>'

# Удалить конкретный блок (не страницу!)
./integrations/buildin/scripts/buildin-pages.sh delete-block <block_uuid> [parent_id]

# Архивировать
./integrations/buildin/scripts/buildin-pages.sh archive <id|url>
```

### Shadow-индекс (локальный кеш)

Локальный кеш структуры и саммари страниц для мгновенного поиска без API-запросов. Растёт органически: каждое чтение страницы автоматически обновляет индекс.

```bash
# Мгновенный поиск по title + summary
./integrations/buildin/scripts/buildin-shadow.sh search "RFC"

# Дерево из кеша (без API)
./integrations/buildin/scripts/buildin-shadow.sh tree

# Полный дамп для LLM-анализа (субагент может прочитать и понять структуру)
./integrations/buildin/scripts/buildin-shadow.sh dump

# Статистика и устаревшие записи
./integrations/buildin/scripts/buildin-shadow.sh stats
./integrations/buildin/scripts/buildin-shadow.sh stale 30
```

Поиск через `buildin-nav.sh search` автоматически проверяет shadow-индекс перед обращением к API.

## Известные страницы

| Название | Page ID |
|----------|---------|
| _(add your root page here)_ | `YOUR_ROOT_PAGE_ID` |

## Особенности Buildin API

- **Поле `parent`** — `GET /v1/pages/{id}` возвращает `parent` объект: `{"type": "page_id", "page_id": "..."}` для дочерних страниц или `{"type": "space_id", "space_id": "..."}` для корневых. API пространств (`/v1/spaces`) недоступен.
- **Два формата блоков** — новый API хранит контент в `data`, legacy — в именованных полях (`heading_1`, `paragraph`). Скрипты поддерживают оба.
- **Нет `plain_text`** — заголовки берутся из `text.content` внутри `rich_text` items.
- **Поиск** — официальный API (`/v1/search`) сломан (500). UI API `/api/search` работает, но качество низкое — результаты часто нерелевантные. Рекомендуется shadow-индекс.
- **Доступ** — UI API (JWT из Google SSO) видит все страницы пользователя. Официальный API-токен видит только расшаренные боту страницы (иначе 403).
- **SDK** — [GitHub: next-space/buildin-api-sdk](https://github.com/next-space/buildin-api-sdk) (Java + TypeScript, OpenAPI spec)

## API Reference

Интеграция использует **UI API** (не официальный API). Base URL: `https://buildin.ai`, авторизация через JWT-токен из Google SSO.

| Метод | Endpoint | Описание |
|-------|----------|----------|
| GET | /api/users/me | Текущий пользователь |
| GET | /api/pages/{id} | Получить страницу с блоками |
| POST | /api/pages/{id}/transactions | Создание/редактирование (транзакции) |
| GET | /api/blocks/{id} | Получить блок по UUID |
| POST | /api/search | Поиск по пространству |

Официальный API (`api.buildin.ai`, `/v1/...`) также существует, но имеет ограничения: поиск сломан (500), нет доступа к пространствам, видит только расшаренные боту страницы.
