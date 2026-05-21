---
name: kaiten-card
description: Read, comment, move, or update a Kaiten card by URL or ID
argument-hint: "<card_url_or_id> [action: read|comment|move|assign]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "AskUserQuestion"]
---

# Kaiten Card — работа с карточкой

Читает, комментирует, перемещает и обновляет карточки Kaiten по ссылке или ID.

## Константы

```
KAITEN_SCRIPTS = integrations/kaiten/scripts
```

## Получение ID из ссылки

Ссылки вида `https://<domain>.kaiten.ru/space/.../card/<id>` — извлекай последний числовой сегмент как `card_id`.

## Чтение карточки

```bash
# Получить карточку целиком
integrations/kaiten/scripts/kaiten-cards.sh get <card_id>

# Получить комментарии
integrations/kaiten/scripts/kaiten-cards.sh comments <card_id>

# Получить чек-листы
integrations/kaiten/scripts/kaiten-cards.sh checklists <card_id>
```

После чтения выведи: заголовок, статус (колонка), описание, ответственных, чек-листы (если есть), последние комментарии.

## Добавить комментарий

```bash
integrations/kaiten/scripts/kaiten-cards.sh comment <card_id> "Текст комментария"
```

## Переместить в колонку

Если `column_id` не известен — сначала получи список колонок доски:

```bash
integrations/kaiten/scripts/kaiten-spaces.sh columns <board_id>
```

Если есть `team-config.json` — используй колонки оттуда (`.kaiten.boards.sprint.columns.*`).

```bash
integrations/kaiten/scripts/kaiten-cards.sh move <card_id> <column_id>
```

## Назначить ответственного

```bash
# Получить участников карточки
integrations/kaiten/scripts/kaiten-cards.sh members <card_id>

# Список пользователей пространства
integrations/kaiten/scripts/kaiten-spaces.sh users

# Назначить
integrations/kaiten/scripts/kaiten-cards.sh assign <card_id> <user_id>
```

## Обновить поля карточки

```bash
# Изменить заголовок / описание / размер / тип
integrations/kaiten/scripts/kaiten-cards.sh update <card_id> '{"title": "Новый заголовок"}'
integrations/kaiten/scripts/kaiten-cards.sh update <card_id> '{"description": "Новое описание"}'
```

## Поиск карточек

```bash
integrations/kaiten/scripts/kaiten-cards.sh search "<текст>" [space_id]
```

## Работа с чек-листами

```bash
# Создать чек-лист
integrations/kaiten/scripts/kaiten-cards.sh checklist <card_id> "Название"

# Добавить пункт
integrations/kaiten/scripts/kaiten-cards.sh check-item <card_id> <checklist_id> "Пункт"

# Отметить выполненным
integrations/kaiten/scripts/kaiten-cards.sh toggle-check-item <card_id> <checklist_id> <item_id> true
```

## Настройка

В `.env` должны быть:

```bash
KAITEN_TOKEN=your_api_token
KAITEN_DOMAIN=your_domain.kaiten.ru
```

| Ошибка | Причина |
|--------|---------|
| 401 | Неверный или истёкший токен |
| 404 | Неверный card_id или домен |
| 429 | Превышен лимит 100 req/min — подожди минуту |

$ARGUMENTS
