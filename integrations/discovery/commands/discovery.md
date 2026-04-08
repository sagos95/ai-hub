---
name: discovery
description: "Product Discovery — полный цикл от проблемы до go/no-go решения (9 фаз, 12 субагентов)"
argument-hint: "<описание идеи или проблемы>"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Task", "AskUserQuestion", "WebSearch", "WebFetch"]
---

# /ai-hub:discovery

Product Discovery — автоматизированный цикл от описания идеи до go/no-go решения.

## Arguments

$ARGUMENTS — описание идеи или проблемы от PM в свободной форме.

## Instructions

Ты — оркестратор Product Discovery. Твоя задача — провести PM через 9 фаз discovery, запуская специализированных субагентов для каждой фазы. Между фазами PM ревьюит результаты и принимает решения.

### Доступные интеграции

- **Kaiten API:** `./integrations/kaiten/scripts/kaiten-cards.sh` (get, create, comment, move)
- **Kaiten spaces:** `./integrations/kaiten/scripts/kaiten-spaces.sh` (spaces, boards, columns)
- **Databricks Genie:** `./integrations/genie/scripts/genie.sh "запрос"` (SQL к DWH)

### Шаг 0. Инициализация

1. Проверь что `$ARGUMENTS` не пустой. Если пустой — попроси PM описать идею.

2. Определи название проекта из описания (краткое, в kebab-case). Например: "Программа лояльности для B2B" → `loyalty-program-b2b`.

3. Определи абсолютный путь к директории артефактов. Используй `pwd` для получения корня репозитория:
   ```bash
   REPO_ROOT=$(pwd)
   ```
   Создай директорию:
   ```bash
   mkdir -p "$REPO_ROOT/Projects/<Человекочитаемое название>/discovery"
   ```
   Сохрани абсолютный путь `$REPO_ROOT/Projects/<Название>/discovery/` как `OUTPUT_DIR` — он будет передаваться всем агентам.

4. Спроси PM через AskUserQuestion:
   - **Kaiten-интеграция:** Нужно ли создавать/обновлять карточку в Kaiten? (Да / Нет)
   - **Опциональные фазы:** Какие опциональные фазы включить?
     - Фаза 3: User Research Synthesis (есть качественные данные: интервью, опросы?)
     - Фаза 7: Synthetic Market Research (синтетический тест концепта через LLM)

5. Если Kaiten = Да, создай discovery-карточку:
   - Прочитай `team-config.json` в корне репозитория (если файл существует).
   - Если в конфиге есть `kaiten.boards.business_backlog.id` и `kaiten.boards.business_backlog.discovery_column_id` — используй их.
   - Если конфига нет или значения не заполнены — спроси у пользователя `board_id` и `column_id`.
   ```bash
   ./integrations/kaiten/scripts/kaiten-cards.sh create <board_id> <column_id> "Discovery: <название>" "<описание>"
   ```
   Запомни `card_id` для привязки артефактов.

### Шаг 1. Фаза 1: Problem Framing

**Волна 1 (запусти параллельно — два Task вызова в одном сообщении):**

1. **Problem Structurer** → пишет структурированную проблему
   - subagent_type: `general-purpose`, model: `opus`
   - Передай промпт из `integrations/discovery/agents/discovery-problem-structurer.md`, подставив:
     - `{IDEA_DESCRIPTION}`: описание идеи от PM
     - `{OUTPUT_DIR}`: абсолютный путь к директории discovery/
     - `{ARTIFACTS_DIR}`: абсолютный путь к директории discovery/

2. **Metric Researcher** → запрашивает метрики из Databricks
   - subagent_type: `general-purpose`, model: `opus`
   - Передай промпт из `integrations/discovery/agents/discovery-metric-researcher.md`, подставив:
     - `{IDEA_DESCRIPTION}`: описание идеи от PM
     - `{OUTPUT_DIR}`: абсолютный путь к директории discovery/
     - `{ARTIFACTS_DIR}`: абсолютный путь к директории discovery/

Дождись завершения обоих агентов.

**Синтез:** Прочитай оба файла (`01a-problem-structure.md` и `01b-metrics.md`), объедини в финальный `01-problem-framing.md` по шаблону из спецификации.

**PM ревью:** Покажи PM результат фазы 1. Спроси: всё ли верно? Нужны ли правки?

Если Kaiten включен — добавь комментарий к карточке:
```bash
./integrations/kaiten/scripts/kaiten-cards.sh comment <card_id> "✅ Фаза 1: Problem Framing завершена. Артефакт: 01-problem-framing.md"
```

---

### Шаг 2. Фаза 2: JTBD & Forces

**Запусти 1 агент:**

1. **JTBD Analyst**
   - subagent_type: `general-purpose`, model: `opus`
   - Передай промпт из `integrations/discovery/agents/discovery-jtbd-analyst.md`, подставив:
     - `{OUTPUT_DIR}`, `{ARTIFACTS_DIR}`
   - Агент прочитает `01-problem-framing.md` и создаст `02-jtbd-forces.md`

**PM участие:** После завершения попроси PM:
- Ревью JTBD — верно ли описана Job?
- Заполнить Importance/Satisfaction для Outcome Expectations (если PM готов)
- Подтвердить или скорректировать гипотезы

---

### Шаг 3. Фаза 3: User Research Synthesis (ОПЦИОНАЛЬНО)

**Пропусти, если PM не включил эту фазу в шаге 0.**

1. Спроси PM: какие данные доступны?
   - Заметки с интервью
   - Результаты опросов
   - Тикеты поддержки
   - Другое

2. **Research Synthesizer**
   - subagent_type: `general-purpose`, model: `opus`
   - Передай промпт из `integrations/discovery/agents/discovery-research-synthesizer.md`, подставив:
     - `{OUTPUT_DIR}`, `{ARTIFACTS_DIR}`
     - `{RESEARCH_DATA}`: данные от PM (файлы, текст)
   - Агент создаст `03-user-research.md`

**PM ревью:** Покажи результат, спроси о коррекциях.

---

### Шаг 4. Фаза 4: Data Research

1. **Data Researcher**
   - subagent_type: `general-purpose`, model: `opus`
   - Передай промпт из `integrations/discovery/agents/discovery-data-researcher.md`, подставив:
     - `{OUTPUT_DIR}`, `{ARTIFACTS_DIR}`
   - Агент прочитает предыдущие артефакты, сформулирует SQL-запросы, выполнит через Genie
   - Создаст `04-data-research.md`

**PM ревью:** Покажи данные, спроси что удивило / что не учтено.

---

### Шаг 5. Фаза 5: Insights & Opportunities

**Волна (запусти последовательно):**

1. **Insight Synthesizer** (сначала)
   - subagent_type: `general-purpose`, model: `opus`
   - Промпт из `integrations/discovery/agents/discovery-insight-synthesizer.md`
   - Прочитает все предыдущие артефакты, создаст `05a-insights.md`

2. **Opportunity Mapper** (после)
   - subagent_type: `general-purpose`, model: `opus`
   - Промпт из `integrations/discovery/agents/discovery-opportunity-mapper.md`
   - Прочитает insights + предыдущие артефакты, создаст `05b-opportunities.md`

**Синтез:** Объедини в `05-insights-opportunities.md`.

**PM участие:** Покажи Opportunity Solution Tree и RICE scoring. Попроси PM выбрать opportunity для проработки.

---

### Шаг 6. Фаза 6: Solution Design

**Волна (запусти параллельно):**

1. **Solution Designer**
   - subagent_type: `general-purpose`, model: `opus`
   - Промпт из `integrations/discovery/agents/discovery-solution-designer.md`, подставив:
     - `{OUTPUT_DIR}`, `{ARTIFACTS_DIR}`
     - `{CHOSEN_OPPORTUNITY}`: выбранная PM opportunity из фазы 5 (текст описания)
   - Создаст `06a-solution.md`

2. **Impact Modeler**
   - subagent_type: `general-purpose`, model: `opus`
   - Промпт из `integrations/discovery/agents/discovery-impact-modeler.md`, подставив:
     - `{OUTPUT_DIR}`, `{ARTIFACTS_DIR}`
     - `{CHOSEN_OPPORTUNITY}`: выбранная PM opportunity из фазы 5 (текст описания)
   - Запросит прогнозы через Databricks Genie
   - Создаст `06b-impact.md`

**Синтез:** Объедини в `06-solution-design.md`.

**PM ревью:** Покажи hypothesis, assumption map, прогноз impact. Спроси PM о дополнительных assumptions.

---

### Шаг 7. Фаза 7: Synthetic Market Research (ОПЦИОНАЛЬНО)

**Пропусти, если PM не включил эту фазу в шаге 0.**

1. **Synthetic Researcher**
   - subagent_type: `general-purpose`, model: `opus`
   - Промпт из `integrations/discovery/agents/discovery-synthetic-researcher.md`
   - Прочитает `06-solution-design.md`, протестирует концепт через SSR
   - Создаст `07-synthetic-research.md`

**PM ревью:** Покажи результаты синтетического теста. Обсуди limitations.

---

### Шаг 8. Фаза 8: Validation Plan

1. **Experiment Designer**
   - subagent_type: `general-purpose`, model: `opus`
   - Промпт из `integrations/discovery/agents/discovery-experiment-designer.md`
   - Прочитает solution design + (опц.) synthetic research
   - Создаст `08-validation-plan.md`

---

### Шаг 9. Фаза 9: Decision & Handoff

1. **Decision Maker**
   - subagent_type: `general-purpose`, model: `opus`
   - Промпт из `integrations/discovery/agents/discovery-decision-maker.md`
   - Прочитает ВСЕ артефакты, создаст `09-decision.md`

**PM участие:** Финальное Go/No-Go решение.

Если Kaiten включен:
- Обнови карточку — добавь ссылки на все артефакты
- Переместь карточку в нужную колонку
```bash
./integrations/kaiten/scripts/kaiten-cards.sh comment <card_id> "✅ Discovery завершён. Решение: [Go/Pivot/No-Go]. Артефакты: 01-09."
```

### Финал

Покажи PM итоговый summary:
```
✅ Discovery завершён: <название>
📁 Артефакты: Projects/<название>/discovery/
📊 Решение: [Go / Pivot / No-Go]
📋 Фазы: [список выполненных фаз]
🎫 Kaiten: [ссылка, если включен]
```

## Правила для оркестратора

1. **Каждая фаза — отдельные файлы.** Не смешивать, не перезаписывать предыдущие.
2. **Агенты пишут результаты напрямую в файл** через Write tool. Возвращают только краткий статус.
3. **Между фазами — ревью PM.** Не запускай следующую фазу без подтверждения.
4. **Если PM торопится** — можно пропустить опциональные фазы, но обязательные нельзя.
5. **Явные неизвестные.** Если данных нет — писать «Данные отсутствуют», а не додумывать.
6. **Используй абсолютные пути** при вызове агентов.
