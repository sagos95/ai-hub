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

#### Вариант A (рекомендуется): markdown-файл через конвертер

Если контент — это markdown-файл, используй готовый конвертер. Он сам собирает
расширенные блоки (таблицы, сворачиваемые секции, вложенные списки, mermaid):

```bash
DIR=integrations/buildin/scripts
python3 $DIR/md-to-blocks.py "<path/to/doc.md>" > /tmp/blocks.json
bash $DIR/buildin-pages.sh append-blocks "<page_id>" "$(cat /tmp/blocks.json)"
```

Поддержка markdown:
- `#`…`###` → заголовок (7); `<!-- collapse -->` перед заголовком → сворачиваемая секция (38)
- `-`/`*` (вложенность по отступу) → список (4); `1.` → нумерованный (5); `- [ ]` → чек-лист (3)
- `> текст` (ведущий эмодзи → иконка) → callout (13)
- `---` → divider (9); ` ```lang ` → код (25); ` ```mermaid ` → диаграмма с preview
- `| таблица |` → нативная таблица (27 + строки 28)
- inline: `**bold**`, `*italic*`, `` `code` ``, `[t](url)`

#### Вариант B: ручная сборка блоков (JSON)

Block types (числовые):
- `1` — paragraph · `3` — todo · `4` — bulleted · `5` — numbered · `7` — heading (`level` 1–3)
- `9` — divider · `12` — quote · `13` — callout (`icon`) · `23` — equation
- `25` — code (`format.language`; mermaid + `format.codePreviewFormat:"preview"`)
- `38` — сворачиваемый заголовок-секция (`level` 1–4) · `27` — таблица + строки `28`

Вложенные блоки задаются полем `children` — `append-blocks` создаёт их с правильным
`parentId`/`subNodes` (toggle с детьми, строки таблицы, подпункты списков):

```json
{"type": 38, "data": {"level": 1, "segments": [{"type": 0, "text": "Секция", "enhancer": {}}]},
 "children": [{"type": 1, "data": {"segments": [{"type": 0, "text": "внутри", "enhancer": {}}]}}]}
```

Segment-формат: `{"type": 0, "text": "Hello", "enhancer": {"bold": true}}`;
inline-код `enhancer:{"code": true}`; ссылка `{"type": 3, "text": "click", "url": "https://…", "enhancer": {}}`.

Отправка блоков:

```bash
# В конец страницы
bash integrations/buildin/scripts/buildin-pages.sh append-blocks "<page_id>" '<json_array>'

# После конкретного блока (block_id получи через get-blocks)
bash integrations/buildin/scripts/buildin-pages.sh insert-blocks-after "<page_id>" "<after_block_id>" '<json_array>'
```

### Фаза 5: Результат

1. Выведи ссылку на созданную страницу
2. Покажи краткую сводку: заголовок, количество блоков, parent page

## Обработка ошибок

- HTTP 401 → Токен истёк, запусти `/ai-hub:buildin-login`
- API code 500 → Проверь формат транзакции
- Нет BUILDIN_UI_TOKEN → Запусти `/ai-hub:buildin-login`
