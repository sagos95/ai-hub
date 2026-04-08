---
description: "Login to Time via browser MCP (Google SSO) — securely extracts token without exposing it to LLM"
allowed-tools: ["Bash", "mcp"]
---

# Time Login — MCP-based browser login

Авторизация в Time через браузерный MCP-сервер. Не привязан к конкретному браузеру — работает с любым MCP, который умеет навигацию и cookies.

**Приоритет MCP:**
1. **Chrome DevTools MCP** (`chrome-devtools-mcp`) — особенно если у юзера он уже настроен.
2. **Playwright MCP** (`@playwright/mcp`) — fallback, если будет что-то не получаться с Chrome DevTools MCP, или если Playwright уже установлен, а Chrome DevTools – нет.
Если нет никакого из этих MCP, установить Chrome DevTools MCP.

Токен извлекается Bash-скриптом из storage-state файла и **НИКОГДА не попадает в контекст LLM**.

## Workflow

### Step 0: Проверь существующий токен

```bash
integrations/time/scripts/time-login.sh check
```

Если вывод `ok @username (email)` — токен валиден, дальше делать ничего не нужно. Покажи: «Токен ещё валиден. Залогинен как @username.»

Если `error:*` или ненулевой exit code — продолжай к Step 1.

### Step 1: Определи доступный MCP

Проверь, какой браузерный MCP доступен у юзера. Попробуй вызвать любой read-only MCP-тул:

**Вариант A — Chrome DevTools MCP:**
Попробуй `list_pages` или `take_snapshot`. Если MCP отвечает — используй его.

**Вариант B — Playwright MCP:**
Попробуй `browser_snapshot`. Если MCP отвечает — используй его.

**Вариант C — Нет MCP:**
Если ни один MCP недоступен, предложи юзеру установить Chrome DevTools MCP, и с его согласия автоматически, сам установи этот MCP.

Если юзер не хочет MCP — предложи ручной fallback:
```bash
integrations/time/scripts/time-login.sh sso
```

### Step 2: Открой Time в браузере через MCP

**Chrome DevTools MCP:**
Используй `navigate_page` с URL `$TIME_BASE_URL`

**Playwright MCP:**
Используй `browser_navigate` с URL `$TIME_BASE_URL`

Скажи юзеру: «Открылся браузер. Залогинься через Google SSO, если нужно. Скажи когда будет готово.»

### Step 3: Дождись логина и извлеки токен

Когда юзер подтвердит что залогинился:

**Chrome DevTools MCP:**
1. Используй `evaluate_script` чтобы проверить логин:
   - script: вызови fetch к `$TIME_BASE_URL/api/v4/users/me` и проверь что ответ 200
2. Если ответ 200 — юзер залогинен. Попроси юзера скопировать MMAUTHTOKEN cookie:
   - DevTools MCP не имеет прямого доступа к httpOnly cookies через JS
   - Попроси юзера: «Скопируй MMAUTHTOKEN из DevTools → Application → Cookies → $TIME_BASE_URL»
3. Запусти Bash-скрипт для сохранения токена из clipboard:
```bash
bash integrations/time/scripts/time-save-token-from-clipboard.sh
```

**Playwright MCP (fallback):**
1. Используй `browser_storage_state` чтобы сохранить cookies в файл:
   - filename: `integrations/time/.cache/storage-state.json`
2. Запусти Bash-скрипт для безопасного извлечения токена:
```bash
bash integrations/time/scripts/time-extract-token-from-storage.sh integrations/time/.cache/storage-state.json
```

### Step 4: Обработай результат

- `ok @username (email)` — покажи: «Залогинен как @username. Токен сохранён в .env.»
- `error:no_mmauthtoken` — юзер не залогинился или cookie не появилась. Предложи повторить.
- `error:validation_failed` — токен невалидный. Предложи перелогиниться.
- `error:no_storage_file` / `error:file_not_found` — проблема с файлом. Проверь путь.

## Ручной fallback

Если MCP не работает или юзер предпочитает терминал:
```bash
integrations/time/scripts/time-login.sh sso
```

## Security

- Токен: Browser MCP → storage-state файл → Bash script → .env
- LLM видит только статусные сообщения (`ok`, `error:*`)
- Storage-state файл удаляется сразу после извлечения токена
- Не привязан к конкретному браузеру — работает с любым MCP
