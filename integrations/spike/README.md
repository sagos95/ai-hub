# Spike Plugin v2.0

Плагин для spike-исследований по задачам из Kaiten.

## Использование

```
/ai-hub:spike <card_id>
```

Где `<card_id>` — числовой ID карточки в Kaiten.

## Workflow

| Фаза | Действие |
|------|----------|
| 1. Discovery | Получить карточку, создать spike-файл |
| 2. Setup | Найти и клонировать репозитории |
| 3. Research | spike-explorer + spike-researcher |
| 4. Analysis | spike-architect формирует решение |
| 5. Summary | Финализация отчёта |

## Агенты

| Агент | Секция | Инструменты |
|-------|--------|-------------|
| spike-explorer | 4.1 Кодовая база | Glob, Grep, Read, Edit |
| spike-researcher | 4.2 Best Practices | WebSearch, WebFetch, Read, Edit |
| spike-architect | 5. Решение | Read, Edit |

## Особенности

- Агенты пишут результаты **напрямую в файл**
- Возвращают только краткий статус (5-7 строк)
- Экономия контекста для больших исследований

## Результат

Spike-файл в `Spikes/YYYY-MM-DD_<name>_<card_id>.md` с:
- Вопрос исследования
- Scope (в/вне скоупа)
- Findings из кода и best practices
- Рекомендованное решение с trade-offs
- Next steps и open questions

## Зависимости

- Kaiten API (настроен в `.env`)
- GitHub CLI (`gh`)
- `jq` для парсинга JSON
