# Buildin MCP Server

MCP (Model Context Protocol) сервер для работы с [Buildin.ai](https://buildin.ai) — базой знаний команды. Позволяет Claude Code и Copilot напрямую читать, создавать и редактировать страницы через нативные MCP-инструменты, без bash-скриптов.

## Инструменты (8 штук)

| Инструмент | Описание |
|---|---|
| `buildin_get_title` | Получить заголовок страницы по ID/URL |
| `buildin_get_page_json` | Получить сырой JSON страницы (блоки, метаданные) |
| `buildin_read_page` | Прочитать страницу, рендерить в Markdown |
| `buildin_search_pages` | Поиск страниц по запросу (требует `space_id` или `BUILDIN_SPACE_ID`) |
| `buildin_create_page` | Создать дочернюю страницу |
| `buildin_update_page` | Обновить заголовок страницы |
| `buildin_append_blocks` | Добавить блоки в конец страницы |
| `buildin_delete_block` | Удалить (архивировать) блок или страницу |

## Установка

### Токен

Нужен `BUILDIN_UI_TOKEN` — JWT-токен из Google SSO. Получить через `/ai-hub:buildin-login`, затем сохранить:

```bash
bash integrations/hub-meta/scripts/env-manager.sh set BUILDIN_UI_TOKEN <token>
```

Опционально: `BUILDIN_SPACE_ID` — ID пространства для поиска по умолчанию.

### Claude Code (через плагин — автоматически)

Плагин содержит `.mcp.json`, поэтому MCP-сервер стартует **автоматически** при включении плагина. Ручная настройка не нужна.

Если плагин уже запущен, перезагрузите: `/reload-plugins`.

### Copilot (автоматически)

Extension в `.github/extensions/buildin/` регистрирует инструменты автоматически при перезагрузке расширений в Copilot.

## Запуск напрямую (CLI-режим)

```bash
node integrations/buildin-mcp/build/index.js cli buildin_get_title '{"page_id":"<uuid>"}'
node integrations/buildin-mcp/build/index.js cli buildin_read_page '{"query":"<uuid-or-url>"}'
node integrations/buildin-mcp/build/index.js cli buildin_search_pages '{"query":"текст","space_id":"<uuid>"}'
```

## Сборка (для разработчиков)

`build/index.js` закоммичен в репозиторий — пересобирать не нужно. При изменении `src/`:

```bash
cd integrations/buildin-mcp
npm install
npm run build
```

## Структура

```
integrations/buildin-mcp/
├── src/
│   ├── index.ts      # MCP-сервер (8 инструментов + CLI-режим)
│   └── shadow.ts     # Кеш страниц для поиска (shadow index)
├── build/
│   └── index.js      # Скомпилированный бандл (esbuild, self-contained, в git)
├── .mcp.json         # Plugin MCP конфиг — автостарт при включении плагина
├── package.json
└── tsconfig.json
```

