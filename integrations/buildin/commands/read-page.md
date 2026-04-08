---
name: read-page
description: Read a Buildin.ai page as markdown (by URL, page_id, or search query)
argument-hint: "<url_or_page_id_or_search_query>"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "AskUserQuestion"]
---

# Read Page — чтение страницы Buildin (UI API)

Читает страницу из Buildin.ai и выводит содержимое как markdown. UI API возвращает все блоки за один запрос.

## Константы

```
BUILDIN_DIR = integrations/buildin/scripts
BUILDIN_SPACE_ID = YOUR_SPACE_ID
```

### Известные корневые страницы

```
Root Page = YOUR_ROOT_PAGE_ID
```

## Входные параметры

Аргумент: `$ARGUMENTS`

Поддерживаемые форматы:
- URL: `https://buildin.ai/<space_id>/<page_id>`
- UUID: `2a904afe-42e9-4ebd-a94e-f6fe0cbacf58`
- Поисковый запрос: любой текст без UUID — ищет через UI Search API

## Workflow

### Фаза 0: Проверь авторизацию

```bash
bash integrations/buildin/scripts/buildin-login.sh check
```

Если `error:*` — запусти `/ai-hub:buildin-login` для логина.

### Фаза 1: Определить page_id

1. Если аргумент содержит UUID (8-4-4-4-12 hex) — это page_id, извлеки его
2. Если аргумент — текст без UUID — это поисковый запрос:
   - **Сначала** ищи в shadow-индексе (мгновенно):
     ```bash
     bash integrations/buildin/scripts/buildin-shadow.sh search "<query>"
     ```
   - Если не найдено — используй UI Search API (качество поиска низкое, результаты часто нерелевантные):
     ```bash
     bash integrations/buildin/scripts/buildin-nav.sh search "<query>"
     ```
   Используй найденный page_id. Если не найдено — сообщи пользователю.

### Фаза 2: Прочитать страницу

```bash
bash integrations/buildin/scripts/buildin-pages.sh read "<page_id>"
```

UI API возвращает все блоки страницы за один запрос (без пагинации).

### Фаза 3: Обновить shadow-индекс

После успешного чтения — обнови shadow-индекс:

```bash
bash integrations/buildin/scripts/buildin-shadow.sh update "<page_id>" "<title>" "<краткое саммари, 1-2 предложения>" "<parent_id>"
```

### Фаза 4: Вывод

1. Выведи полученный markdown пользователю
2. Если страница содержит дочерние страницы, предложи прочитать любую из них

## Обработка ошибок

- HTTP 401 → Токен истёк, запусти `/ai-hub:buildin-login`
- Пустой результат → Контент может быть в дочерних страницах:
  ```bash
  bash integrations/buildin/scripts/buildin-nav.sh children "<page_id>"
  ```
