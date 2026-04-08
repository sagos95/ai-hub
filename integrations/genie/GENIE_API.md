# Databricks Genie API

Документация API для запросов аналитических данных через Databricks Genie Conversation API.

## Endpoint

Используется официальный Genie Conversation API:

```
POST https://${GENIE_HOST}/api/2.0/genie/spaces/{space_id}/start-conversation
GET  https://${GENIE_HOST}/api/2.0/genie/spaces/{space_id}/conversations/{conversation_id}/messages/{message_id}
```

**Space ID:** `${GENIE_SPACE_ID}` (configure in `.env`)

## Авторизация

```
Authorization: Bearer {GENIE_TOKEN}
Content-Type: application/json
```

## Как это работает

1. **Start Conversation** — отправляем вопрос, получаем `conversation_id` и `message_id`
2. **Poll for Result** — опрашиваем API пока `status` не станет `COMPLETED`
3. **Parse Response** — извлекаем текст, SQL, таблицы, suggested questions

## CLI Usage

```bash
# Базовый запрос (показывает SQL)
./genie.sh "your natural language question"

# Без SQL деталей
./genie.sh --no-sql "top-10 locations by revenue"

# Полный JSON ответ
./genie.sh --raw "compare revenue across regions"

# Справка
./genie.sh --help
```

## Пример вывода

```
Yesterday there were **27,599 orders**.

──────────────────────────────────────────────────
📊 SQL Query:
SELECT COUNT(DISTINCT `OrderId`) AS Orders_Count
FROM `analytics`.`gold`.`orders`
WHERE `SaleDate` = current_date - 1

📁 Tables: analytics.gold.orders

💡 Suggested questions:
   • What was the revenue yesterday?
   • How many new customers placed orders yesterday?
```

## Формат запроса

### Start Conversation

```bash
curl -X POST "https://${GENIE_HOST}/api/2.0/genie/spaces/${SPACE_ID}/start-conversation" \
  -H "Authorization: Bearer $GENIE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "your natural language question"}'
```

Response:
```json
{
  "conversation_id": "01f0f78e46ff12bab6e729b1a82c2942",
  "message_id": "01f0f78e4706148cb73d875dfefe30fe",
  "message": {
    "status": "SUBMITTED",
    "content": "your natural language question"
  }
}
```

### Poll for Result

```bash
curl -X GET "https://${GENIE_HOST}/api/2.0/genie/spaces/${SPACE_ID}/conversations/${CONVERSATION_ID}/messages/${MESSAGE_ID}" \
  -H "Authorization: Bearer $GENIE_TOKEN"
```

## Формат ответа

```json
{
  "id": "message_id",
  "conversation_id": "conversation_id",
  "status": "COMPLETED",
  "content": "your natural language question",
  "attachments": [
    {
      "query": {
        "query": "SELECT COUNT(*) FROM table WHERE ...",
        "description": "Описание что Genie понял из вопроса",
        "statement_id": "uuid",
        "query_result_metadata": {"row_count": 1}
      },
      "attachment_id": "uuid"
    },
    {
      "suggested_questions": {
        "questions": ["Вопрос 1?", "Вопрос 2?", "Вопрос 3?"]
      },
      "attachment_id": "uuid"
    },
    {
      "text": {
        "content": "Текстовый ответ на естественном языке"
      }
    }
  ],
  "query_result": {
    "statement_id": "uuid",
    "row_count": 1
  }
}
```

### Ключевые поля

| Поле | Описание |
|------|----------|
| `status` | `SUBMITTED`, `IN_PROGRESS`, `COMPLETED`, `FAILED`, `CANCELLED` |
| `attachments[].query.query` | **SQL запрос** который выполнил Genie |
| `attachments[].query.description` | Как Genie интерпретировал вопрос |
| `attachments[].text.content` | Текстовый ответ |
| `attachments[].suggested_questions.questions` | Предложенные follow-up вопросы |

## Известные таблицы

Genie использует следующие таблицы из Unity Catalog:

| Таблица | Описание |
|---------|----------|
| `analytics.gold.orders` | Orders fact table — main metrics table |

### Example columns

| Колонка | Описание |
|---------|----------|
| `OrderId` | Order ID |
| `SaleDate` | Sale date |
| `BusinessId` | Business unit |
| `RegionId` | Region code |
| `Revenue` | Revenue |
| ... | (depends on your Genie space configuration) |

## Дефолтные значения Genie

Если не указано явно, Genie применяет:
- Configured by the Genie space administrator (business, country, date range defaults)

## Ошибки

| HTTP Code | Описание |
|-----------|----------|
| 401 | Неверный или отсутствующий токен |
| 404 | Space/Conversation/Message не найден |
| 429 | Превышен лимит запросов |
| 500 | Внутренняя ошибка сервиса |

## Ссылки

- [Genie Conversation API Docs](https://docs.databricks.com/aws/en/genie/conversation-api)
- [Unity Catalog Information Schema](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-information-schema)
