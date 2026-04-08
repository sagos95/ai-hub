# Data Pseudo-MCP

CLI инструменты для интеграции LLM агентов с Databricks Genie API — запросы аналитических данных на естественном языке.

## Структура

```
├── GENIE_API.md             # Документация REST API
├── MCP_INTEGRATION.md       # Документация MCP подключения
├── README.md                # Этот файл
└── scripts/
    ├── genie-config.sh      # Конфигурация
    └── genie.sh             # CLI для запросов данных
```

## Быстрый старт

### 1. Настройка окружения

```bash
# Из корня проекта
# Добавьте в .env:
GENIE_TOKEN=your_databricks_token_here
```

Токен можно получить у администратора Databricks вашей компании.

### 2. Сделайте скрипты исполняемыми

```bash
chmod +x Plugins/data-pseudo-mcp/scripts/*.sh
```

### 3. Примеры использования

```bash
# Простой запрос (показывает SQL и таблицы)
./Plugins/data-pseudo-mcp/scripts/genie.sh "how many orders yesterday?"

# Топ локаций
./Plugins/data-pseudo-mcp/scripts/genie.sh "top-10 locations by revenue this week"

# Без SQL деталей (чистый ответ)
./Plugins/data-pseudo-mcp/scripts/genie.sh --no-sql "how many orders yesterday?"

# Полный JSON ответ
./Plugins/data-pseudo-mcp/scripts/genie.sh --raw "how many orders yesterday?"
```

### Пример вывода

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
```

## Использование с LLM агентами

### Оценка импакта фичи

```bash
./Plugins/data-pseudo-mcp/scripts/genie.sh "what is the average daily revenue per location?"
./Plugins/data-pseudo-mcp/scripts/genie.sh "how many delivery orders were there last month?"
```

### Анализ метрик

```bash
./Plugins/data-pseudo-mcp/scripts/genie.sh "what is the average order value?"
./Plugins/data-pseudo-mcp/scripts/genie.sh "top-5 regions by number of orders"
```

## Доступные данные

Genie имеет доступ к аналитическим данным, сконфигурированным в вашем Genie Space:

| Категория | Примеры метрик |
|-----------|----------------|
| Orders | count, revenue, average check |
| Geography | regions, locations |
| Time | yesterday, week, month, custom periods |
| Channels | delivery, pickup, etc. |

## API Reference

- REST API: [GENIE_API.md](./GENIE_API.md)
- MCP Integration: [MCP_INTEGRATION.md](./MCP_INTEGRATION.md)

## Troubleshooting

### Ошибка авторизации (401)

Проверьте `GENIE_TOKEN` в `.env`

### Пустой ответ

Попробуйте переформулировать вопрос или добавить контекст (страна, период)

### Таймаут

Сложные запросы могут выполняться дольше, попробуйте упростить запрос
