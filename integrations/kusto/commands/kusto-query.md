---
name: kusto-query
description: "Execute read-only KQL queries against Azure Data Explorer (Kusto) — logs, traces, errors"
argument-hint: "<KQL query or description of what to look for>"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
---

# Kusto Query Tool

Инструмент для выполнения read-only запросов к Azure Data Explorer (Kusto).

## Настройка

Добавь в `.env.local` в корне репозитория:

```bash
KUSTO_CLUSTER=https://your-cluster.region.kusto.windows.net
KUSTO_DATABASE=your-database
```

Авторизация через Azure CLI:
```bash
az login
```

## Использование

```bash
# Произвольный KQL запрос (таблица)
./integrations/kusto/scripts/kusto.sh "<KQL>"

# JSON формат
./integrations/kusto/scripts/kusto.sh "<KQL>" --format json

# Сырой ответ API
./integrations/kusto/scripts/kusto.sh "<KQL>" --format raw
```

## Примеры запросов

```kql
// Последние записи
Logs | take 10

// Ошибки за последний час
Logs
| where Timestamp > ago(1h)
| where Level == "Error"
| project Timestamp, Level, Payload
| order by Timestamp desc
| take 50

// Топ ошибок по типу
Logs
| where Timestamp > ago(1h)
| where Level == "Error"
| extend ExType = tostring(Payload.ExceptionDetail.Type)
| extend ExMsg = tostring(Payload.ExceptionDetail.Message)
| summarize Count = count() by ExType, ExMsg
| order by Count desc

// Найти по TraceID
Logs
| where TraceID == "abc123def456"
| project Timestamp, Level, Payload
| order by Timestamp asc
```

## Важные ограничения

- **READ-ONLY** — только SELECT/query
- **Всегда фильтруй по времени**: `where Timestamp > ago(Xh)` — без этого запрос может быть очень долгим
- Если токен истёк: `az login`

$ARGUMENTS
