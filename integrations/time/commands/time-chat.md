---
description: "Read/write Time (Mattermost) channels, messages, threads — dual auth (bot + personal)"
argument-hint: "<action> [channel_name_or_id]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Agent", "AskUserQuestion"]
---

# Time — работа с каналами и сообщениями

## Описание

Инструмент для работы с Time (Mattermost) с двумя режимами авторизации:
- **`--as me`** — от имени личного аккаунта (сессионная авторизация)
- **`--as bot`** — от имени бота (постоянный токен)

## Выбор режима авторизации

Перед выполнением действия определи, какой режим подходит:

**Используй `--as me` (личный аккаунт) когда:**
- Нужно уточнить что-то у коллеги (личное сообщение)
- Нужно задать вопрос в канале от лица пользователя
- Нужно прочитать каналы/сообщения, доступные только пользователю
- Пользователь явно просит написать «от своего имени»

**Используй `--as bot` когда:**
- Постинг changelog, release notes, автоматических уведомлений
- Отправка результатов spike-исследований
- Любые автоматизированные, «обезличенные» посты
- Пользователь явно просит запостить «от бота»

**Для чтения** (каналов, сообщений, поиска) — используй любой доступный режим. Если настроены оба, предпочитай `--as me` для чтения (больше каналов доступно).

**Если не уверен** — спроси пользователя: «Отправить от твоего имени или от бота?»

## Workflow

### Phase 0: Инициализация

```bash
chmod +x integrations/time/scripts/*.sh
```

Определи доступные режимы — проверь, кто отвечает:
```bash
integrations/time/scripts/time-channels.sh me | jq '{username, email}'
```
Если ошибка — попробуй другой режим:
```bash
integrations/time/scripts/time-channels.sh --as bot me | jq '{username}'
```

### Phase 1: Определи Team ID

```bash
integrations/time/scripts/time-channels.sh my-teams | jq '.[] | {id, display_name}'
```

### Phase 2: Выполни запрошенное действие

Аргумент пользователя: `$ARGUMENTS`

**Найти канал (включая приватные, с кэшем 30 мин):**
```bash
integrations/time/scripts/time-channels.sh find <team_id> "<term>"
```

**Прочитать сообщения канала:**
1. Найди канал: `time-channels.sh find <team_id> "<name>"`
2. Получи сообщения: `time-messages.sh posts <channel_id> 0 20`
3. Резолви usernames: `time-messages.sh user <user_id>`
4. Форматируй: `[YYYY-MM-DD HH:MM] @username: message`

**Прочитать тред:**
```bash
integrations/time/scripts/time-messages.sh thread <post_id>
```

**Найти сообщения:**
```bash
integrations/time/scripts/time-messages.sh search <team_id> "<terms>"
```

⚠️ **Ограничения Mattermost search** — учитывай ДО того, как делать вывод «ничего не найдено»:
- **Литеральный match по словам**: «не могу создать заявку» в канале `elma365-feedback` НЕ найдётся по запросу `elma` — контекст канала не индексируется.
- **Лимит ~60 результатов**: старые сообщения выпадают.
- **Модификаторы**: `from:username` работает только если стоит **первым** (`from:a.zhuravlev elma` — ок; `elma from:a.zhuravlev` — вернёт 0).
- **Wildcard**: `эльм*` матчит словоформы, но не спасает от литеральности.

**Поиск сообщений пользователя по теме (правильный порядок):**
1. **Сначала** найди тематические каналы — в названии/purpose: `time-channels.sh find <team_id> "<topic>"`.
2. В найденных каналах прочитай посты пользователя напрямую: `time-messages.sh my-posts <channel_id>` (фильтрует по текущему `me`).
3. **Потом** — полнотекстовый `search` как дополнение.
4. Если первый поиск не нашёл, а пользователь уверен что оно есть — **смени стратегию (другой канал/источник)**, а не перебирай варианты того же запроса.

**Мои посты в канале (с автопагинацией):**
```bash
integrations/time/scripts/time-messages.sh my-posts <channel_id> [max_posts]
```

**Отправить сообщение (выбери режим по контексту!):**
```bash
# От личного аккаунта — уточнение, вопрос коллеге
integrations/time/scripts/time-messages.sh --as me send <channel_id> "<message>" [root_id]

# От бота — changelog, уведомление, результат автоматизации
integrations/time/scripts/time-messages.sh --as bot send <channel_id> "<message>" [root_id]
```
⚠️ **ОБЯЗАТЕЛЬНО** подтверди у пользователя: текст, адресата и режим (бот/личный).

### Phase 3: Форматирование результата

Mattermost API возвращает сообщения в формате `{posts: {id: post}, order: [id1, id2]}`.
- `order` — ID в хронологическом порядке (новые первые)
- `posts` — словарь постов по ID
- Для каждого поста: `create_at` (unix ms), `user_id`, `message`, `root_id`

Преобразуй в читаемый формат:
1. Итерируй по `order`
2. Конвертируй `create_at`: `date -r $((create_at / 1000))`
3. Резолви `user_id` → username (кэшируй!)
4. Выводи: `[YYYY-MM-DD HH:MM] @username: message`

## Important Notes

- **Не отправляй сообщения без подтверждения пользователя**
- **Всегда уточняй режим** (bot/me) перед отправкой, если контекст неоднозначен
- User IDs кэшируй — не делай повторных запросов для одного user_id
- Пагинация: page=0 — первая страница, per_page — до 200
- Timestamps в миллисекундах (Unix epoch × 1000)
