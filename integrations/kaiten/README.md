# Kaiten Integration

Универсальный CLI-клиент для работы с [Kaiten API](https://www.kaiten.ru/). Не привязан к конкретной команде или проекту — можно подключить к любому пространству.

## Структура

```
├── docs/
│   └── KAITEN_API.md           # Документация API endpoints
├── scripts/
│   ├── kaiten.sh               # Универсальный CLI для любых API-вызовов
│   ├── kaiten-cards.sh         # Работа с карточками (CRUD, комментарии, чек-листы)
│   ├── kaiten-spaces.sh        # Пространства, доски, колонки
│   ├── kaiten-config.space.sh  # Конфигурация пространства по умолчанию
│   └── kaiten-export-board.sh  # Экспорт доски
└── README.md
```

## Быстрый старт

### 1. Настройка токена

```bash
# В .env в корне репозитория (или экспортируйте переменные окружения)
KAITEN_TOKEN=your_api_token_here
KAITEN_DOMAIN=your_domain.kaiten.ru
```

> Токен можно получить в Kaiten: Настройки профиля → API / Интеграции → Создать токен.

### 2. Права на запуск

```bash
chmod +x integrations/kaiten/scripts/*.sh
```

### 3. Проверка подключения

```bash
./integrations/kaiten/scripts/kaiten-spaces.sh me
```

## Использование

### Универсальный API-клиент (`kaiten.sh`)

Обёртка над `curl` для любых запросов к Kaiten REST API:

```bash
./kaiten.sh GET /cards/123
./kaiten.sh POST /cards '{"title": "Задача", "board_id": 1, "column_id": 2}'
./kaiten.sh PATCH /cards/123 '{"column_id": 5}'
./kaiten.sh DELETE /cards/123
```

### Карточки (`kaiten-cards.sh`)

```bash
# Список карточек на доске
./kaiten-cards.sh list <board_id>

# Получить карточку
./kaiten-cards.sh get <card_id>

# Создать карточку
./kaiten-cards.sh create <board_id> <column_id> "Название" "Описание"

# Переместить в другую колонку
./kaiten-cards.sh move <card_id> <column_id>

# Комментарий
./kaiten-cards.sh comment <card_id> "Текст"

# Назначить ответственного
./kaiten-cards.sh assign <card_id> <user_id>

# Чек-лист
./kaiten-cards.sh checklist <card_id> "Название чек-листа"
./kaiten-cards.sh check-item <card_id> <checklist_id> "Пункт"
```

### Пространства и доски (`kaiten-spaces.sh`)

```bash
./kaiten-spaces.sh spaces            # Список пространств
./kaiten-spaces.sh boards <space_id> # Доски в пространстве
./kaiten-spaces.sh columns <board_id> # Колонки на доске
```

### Блокеры

```bash
./kaiten.sh POST "/cards/<card_id>/blockers" '{"reason": "Причина"}'
./kaiten.sh GET "/cards/<card_id>/blockers"
./kaiten.sh DELETE "/cards/<card_id>/blockers/<blocker_id>"
```

## API Reference

Полная документация endpoints — в [docs/KAITEN_API.md](./docs/KAITEN_API.md).

| Ресурс | Описание |
|--------|----------|
| `/spaces` | Пространства |
| `/boards` | Доски |
| `/columns` | Колонки |
| `/lanes` | Дорожки |
| `/cards` | Карточки |
| `/users` | Пользователи |
| `/tags` | Теги |
| `/properties` | Кастомные свойства |

### Rate Limits

- 100 запросов в минуту
- При превышении — HTTP 429

## Troubleshooting

| Ошибка | Причина |
|--------|---------|
| 401 | Неверный или истёкший токен в `.env` |
| 404 | Неверный домен или endpoint |
| 429 | Превышен лимит запросов — подождите минуту |
