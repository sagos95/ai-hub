---
description: "Reverse Product Analysis - full service functionality inventory from source code"
argument-hint: "<path-to-repository>"
---

# /ai-hub:rpa-analyze

Reverse Product Analysis — полная инвентаризация функционала сервиса по исходному коду.

## Arguments

$ARGUMENTS — путь к репозиторию для анализа

## Instructions

Ты — оркестратор Reverse Product Analysis. Твоя задача — запустить 9 субагентов волнами, собрать результаты и вывести summary.

### Идемпотентность (повторный запуск)

Плагин поддерживает повторный запуск. Каждый агент самостоятельно:
1. Проверяет, существует ли его выходная директория и файлы
2. Если файлы существуют — выполняет механический обход кода, ищет пробелы (упущенные сущности, endpoints, behaviors и т.д.)
3. Если нашёл пробелы — дополняет файлы, добавляя новые находки (не удаляя существующие)
4. Если всё уже описано исчерпывающе — оставляет файлы без изменений

Ты НЕ должен проверять наличие файлов за агентов — каждый агент делает это сам. Просто запускай волны как обычно.

### Шаг 1. Валидация

Проверь что путь `$ARGUMENTS` существует и является директорией. Если нет — сообщи ошибку и остановись.

Определи абсолютный путь к репозиторию (REPO_PATH). Если передан относительный путь — преобразуй в абсолютный.

### Шаг 2. Создание выходной структуры

Создай директорию `<REPO_PATH>/reverse-project-analysis/` и поддиректории для каждого шага:

```
reverse-project-analysis/
  01-domain-entities/
  02-entry-points/
  03-functional-behaviors/
  04-state-transitions/
  05-bdd-contracts/
  06-integrations/
  07-scenarios/
  08-feature-map/
  09-validation/
```

Если директории уже существуют — это нормально (повторный запуск).

### Шаг 3. Запуск агентов волнами

Используй инструмент Task для запуска субагентов. Каждому агенту передай:
- **REPO_PATH:** Абсолютный путь к репозиторию
- **OUTPUT_DIR:** Абсолютный путь к директории для результатов этого шага
- **ARTIFACTS_DIR:** Абсолютный путь к `reverse-project-analysis/` (для чтения артефактов других шагов)

**ВАЖНО:** Используй `subagent_type: "general-purpose"` и `model: "sonnet"` для каждого субагента.

---

**Волна 1 (запусти параллельно — два Task вызова в одном сообщении):**

1. **Шаг A — Доменные сущности** → `01-domain-entities/`
   Промпт из `agents/rpa-domain.md`, подставив пути.

2. **Шаг B — Точки входа** → `02-entry-points/`
   Промпт из `agents/rpa-entry-points.md`, аналогично.

Дождись завершения обоих агентов.

---

**Волна 2 (запусти параллельно после волны 1):**

3. **Шаг C1 — Functional Behaviors** → `03-functional-behaviors/`
   Зависит от A+B. Агент должен прочитать `01-domain-entities/00-index.md` и `02-entry-points/00-index.md`.

4. **Шаг D — Переходы состояний** → `04-state-transitions/`
   Зависит от A. Агент должен прочитать `01-domain-entities/00-index.md`.

Дождись завершения обоих агентов.

---

**Волна 3 (запусти параллельно после волны 2):**

5. **Шаг C2 — BDD-контракты** → `05-bdd-contracts/`
   Зависит от C1. Агент должен прочитать `03-functional-behaviors/00-index.md`.

6. **Шаг E — Интеграции** → `06-integrations/`
   Зависит от C1. Агент должен прочитать `03-functional-behaviors/00-index.md`.

Дождись завершения обоих агентов.

---

**Волна 4 (запусти параллельно после волны 3):**

7. **Шаг F — Ключевые сценарии** → `07-scenarios/`
   Зависит от C1+D+E. Агент должен прочитать `03-functional-behaviors/00-index.md`, `04-state-transitions/00-index.md`, `06-integrations/00-index.md`.

8. **Шаг G — Feature Map** → `08-feature-map/`
   Зависит от C1. Агент должен прочитать `03-functional-behaviors/00-index.md`.

Дождись завершения обоих агентов.

---

**Волна 5 (после волны 4):**

9. **Шаг H — Валидация** → `09-validation/`
   Зависит от всех предыдущих шагов. Агент должен прочитать все `00-index.md` из шагов A-G.

Дождись завершения агента.

### Шаг 4. Финализация

Собери краткий summary из статусов всех 9 агентов. Для каждого агента отметь: создан новый файл / дополнен / без изменений. Выведи пользователю:

```
Reverse Product Analysis завершён.

Результаты: <REPO_PATH>/reverse-project-analysis/

Директории:
  01-domain-entities/       — Доменные сущности (Шаг A)     [created/updated/unchanged]
  02-entry-points/          — Точки входа (Шаг B)           [created/updated/unchanged]
  03-functional-behaviors/  — Functional Behaviors (Шаг C1) [created/updated/unchanged]
  04-state-transitions/     — Переходы состояний (Шаг D)    [created/updated/unchanged]
  05-bdd-contracts/         — BDD-контракты (Шаг C2)        [created/updated/unchanged]
  06-integrations/          — Интеграции (Шаг E)            [created/updated/unchanged]
  07-scenarios/             — Ключевые сценарии (Шаг F)     [created/updated/unchanged]
  08-feature-map/           — Feature Map (Шаг G)           [created/updated/unchanged]
  09-validation/            — Валидация (Шаг H)             [created/updated/unchanged]

Валидация: <общий статус из шага H>
```

### Промпты агентов

При запуске каждого агента используй полный промпт из соответствующего файла в `agents/`. Чтобы получить промпт, прочитай файл агента с помощью Read tool. Путь к агентам: `integrations/reverse-product-analysis/agents/` (относительно корня проекта).

Список файлов агентов:
- `rpa-domain.md` — Шаг A
- `rpa-entry-points.md` — Шаг B
- `rpa-behaviors.md` — Шаг C1
- `rpa-states.md` — Шаг D
- `rpa-contracts.md` — Шаг C2
- `rpa-integrations.md` — Шаг E
- `rpa-scenarios.md` — Шаг F
- `rpa-features.md` — Шаг G
- `rpa-validation.md` — Шаг H

Пример запуска агента:
1. Прочитай файл `integrations/reverse-product-analysis/agents/rpa-domain.md` (из корня проекта)
2. Подставь в промпт конкретные пути:
   - `{repo_path}` → REPO_PATH
   - `{output_dir}` → OUTPUT_DIR для этого шага
   - `{artifacts_dir}` → ARTIFACTS_DIR
3. Запусти через Task tool с `subagent_type: "general-purpose"`, `model: "sonnet"`
