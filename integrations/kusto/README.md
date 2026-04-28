# Kusto Integration

CLI инструменты для выполнения read-only KQL запросов к Azure Data Explorer (Kusto).

## Структура

```
├── README.md
├── scripts/
│   └── kusto.sh        # Универсальный CLI для KQL запросов
└── commands/
    └── kusto-query.md  # Claude slash-команда /ai-hub:kusto-query
```

## Быстрый старт

### 1. Настройка

Добавь в `.env.local`:

```bash
KUSTO_CLUSTER=https://your-cluster.region.kusto.windows.net
KUSTO_DATABASE=your-database
```

### 2. Авторизация

```bash
az login
```

### 3. Запрос

```bash
./integrations/kusto/scripts/kusto.sh "Logs | take 5"
```

## Конфигурация

| Переменная | Обязательная | Описание |
|------------|-------------|----------|
| `KUSTO_CLUSTER` | ✅ | URL кластера: `https://name.region.kusto.windows.net` |
| `KUSTO_DATABASE` | ✅ | Название базы данных |

## Форматы вывода

| Формат | Описание |
|--------|----------|
| `table` (по умолчанию) | Таблица в ASCII |
| `json` | JSON массив объектов |
| `raw` | Сырой ответ Kusto REST API |

## Требования

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- `curl`
- Python 3
- Доступ к кластеру Kusto под своим AAD аккаунтом
