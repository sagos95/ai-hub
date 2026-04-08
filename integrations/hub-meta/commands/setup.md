---
name: setup
description: "AI Hub initial setup — configure company environment and personal tokens"
argument-hint: "[buildin_config_page_url]"
allowed-tools: ["Bash", "Read", "AskUserQuestion", "mcp"]
---

# AI Hub Setup — initial environment configuration

Настройка окружения для AI Hub: компанейский конфиг + личные токены.

## Константы

```
ENV_MANAGER = integrations/hub-meta/scripts/env-manager.sh
BUILDIN_LOGIN = integrations/buildin/scripts/buildin-login.sh
BUILDIN_PAGES = integrations/buildin/scripts/buildin-pages.sh
DEFAULT_CONFIG_PAGE = https://buildin.ai/c7ec2023-9025-4c09-be09-e6f54cb07f7e
```

## Workflow

### Step 0: Миграция .env.local → .env

```bash
bash integrations/hub-meta/scripts/env-manager.sh migrate
```

Если вывод `migrated:*` — сообщи юзеру что файл переименован.
Если `warning:*` — предупреди что существуют оба файла, предложи объединить вручную.

### Step 1: Проверь текущий статус

```bash
bash integrations/hub-meta/scripts/env-manager.sh check
```

Покажи юзеру результат. Если все ключи `=set` → скажи «Всё настроено!» и предложи проверить токены (Step 6).

### Step 2: Company config

Если company config переменные `=missing` (KAITEN_DOMAIN, TIME_BASE_URL, BUILDIN_SPACE_ID):

**Вариант A — автоматический (через Buildin):**

Определи URL конфиг-страницы:
1. Если `$ARGUMENTS` содержит URL — используй его
2. Иначе — используй `DEFAULT_CONFIG_PAGE` (захардкожен выше)

В обоих случаях не спрашивай юзера — сразу перейди к Step 3.

**Вариант B — ручной ввод:**

Если юзер не имеет URL или не хочет логиниться в Buildin — предложи ввести значения вручную. Для каждой missing переменной спроси значение и сохрани:

```bash
bash integrations/hub-meta/scripts/env-manager.sh set KAITEN_DOMAIN "<value>"
bash integrations/hub-meta/scripts/env-manager.sh set TIME_BASE_URL "<value>"
bash integrations/hub-meta/scripts/env-manager.sh set BUILDIN_SPACE_ID "<value>"
```

После этого перейди к Step 6.

### Step 3: Логин в Buildin

```bash
bash integrations/buildin/scripts/buildin-login.sh check
```

Если `error:*` — нужен логин. Запусти `/ai-hub:buildin-login` (он сам определит MCP: Chrome DevTools → Playwright → manual fallback).

Если `ok *` — токен валиден, продолжай.

### Step 4: Прочитай конфиг-страницу

Извлеки `page_id` из URL (последний UUID в пути).

```bash
bash integrations/buildin/scripts/buildin-pages.sh read "<page_id>"
```

Страница должна содержать строки формата `KEY=VALUE` (внутри или вне code-блоков). Извлеки все строки, где:
- KEY — заглавные буквы и подчёркивания (`[A-Z_]+`)
- VALUE — непустое значение после `=`

### Step 5: Запиши конфиг в .env

Для каждой найденной пары KEY=VALUE:

```bash
bash integrations/hub-meta/scripts/env-manager.sh set KEY "VALUE"
```

Покажи юзеру что было записано (только ключи и статус `added`/`updated`).

Проверь результат:

```bash
bash integrations/hub-meta/scripts/env-manager.sh check
```

### Step 6: Личные токены

Для каждого personal token со статусом `=missing`:

**KAITEN_TOKEN:**
- Скажи: «Перейди в Kaiten → Настройки профиля → API/Интеграции → скопируй токен»
- Когда юзер даст токен:
  ```bash
  bash integrations/hub-meta/scripts/env-manager.sh set KAITEN_TOKEN "<token>"
  ```

**GENIE_TOKEN** (если GENIE_HOST настроен):
- Скажи: «Токен Databricks можно получить у администратора данных»
- Аналогично сохрани через env-manager.sh set

**BUILDIN_UI_TOKEN и TIME_TOKEN** — автоматически настраиваются через `/ai-hub:buildin-login` и `/ai-hub:time-login`. Не проси вводить вручную — предложи запустить соответствующие login-скиллы при необходимости.

### Step 7: Финальная проверка

```bash
bash integrations/hub-meta/scripts/env-manager.sh check
```

Покажи итоговый статус. Если остались `=missing` для optional — скажи что это нормально, настроить можно позже.

Скажи: «Готово! Попробуй любую команду, например `/ai-hub:buildin-read` или `/ai-hub:time-chat`.»

## Обработка ошибок

- Buildin login не удался → предложи ручной ввод (Вариант B в Step 2)
- Страница не содержит KEY=VALUE → предупреди, предложи ручной ввод
- env-manager.sh set вернул ошибку → покажи ошибку, предложи ручное редактирование `.env`
