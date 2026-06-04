---
name: publish-page
description: Create or update a page in Buildin.ai wiki (UI API)
argument-hint: "<parent_page_id_or_url> [page_title]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Write", "Edit", "Task", "AskUserQuestion"]
---

# Publish Page — создание и обновление страницы в Buildin (UI API)

Создаёт или обновляет страницу в Buildin.ai. Поддерживает создание из markdown-файлов, текста или структурированного контента.

## Константы

```
BUILDIN_DIR = integrations/buildin/scripts
```

## Входные параметры

Аргумент: `$ARGUMENTS` — parent_page_id и опционально заголовок.

Формат: `<parent_page_id> [page_title]`

## Workflow

### Фаза 0: Проверь авторизацию

```bash
bash integrations/buildin/scripts/buildin-login.sh check
```

Если `error:*` — запусти `/ai-hub:buildin-login` для логина.

### Фаза 1: Подготовка

1. Разбери аргументы:
   - Первый аргумент — `parent_page_id` (UUID родительской страницы)
   - Второй аргумент (опционально) — заголовок страницы
2. Если заголовок не указан, спроси пользователя через AskUserQuestion

### Фаза 2: Сбор контента

1. Спроси пользователя, что опубликовать:
   - **Файл** — путь к markdown/текстовому файлу в репозитории
   - **Текст** — пользователь введёт текст напрямую
   - **Пустая страница** — создать страницу только с заголовком
2. Если указан файл, прочитай его содержимое через Read

### Фаза 3: Создание страницы

```bash
bash integrations/buildin/scripts/buildin-pages.sh create "<parent_page_id>" "<title>"
```

Запомни ID созданной страницы из вывода.

### Фаза 4: Наполнение контентом

Если есть контент для публикации:

1. Преобразуй markdown/текст в блоки Buildin UI API:

   Block types (числовые):
   - `5` — paragraph (текст с segments)
   - `6` — heading (level: 1/2/3)
   - `4` — bulleted list item
   - `25` — code block
   - `13` — callout
   - `26` — divider

   Segment format:
   ```json
   {"type": 0, "text": "Hello", "enhancer": {"bold": true}}
   ```

   Link segment (type 3):
   ```json
   {"type": 3, "text": "click", "url": "https://...", "enhancer": {}}
   ```

2. Отправляй блоки батчами:
   ```bash
   bash integrations/buildin/scripts/buildin-pages.sh append-blocks "<page_id>" '<json_array>'
   ```

   Каждый элемент массива:
   ```json
   {"type": 5, "data": {"segments": [{"type": 0, "text": "Hello", "enhancer": {}}]}}
   ```

   Heading:
   ```json
   {"type": 6, "data": {"level": 2, "segments": [{"type": 0, "text": "Title", "enhancer": {}}]}}
   ```

### Фаза 5: Результат

1. Выведи ссылку на созданную страницу
2. Покажи краткую сводку: заголовок, количество блоков, parent page

## Обработка ошибок

- HTTP 401 → Токен истёк, запусти `/ai-hub:buildin-login`
- API code 500 → Проверь формат транзакции
- Нет BUILDIN_UI_TOKEN → Запусти `/ai-hub:buildin-login`
