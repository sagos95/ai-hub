# Code Review — Autonomous C#/.NET Code Review Pipeline

Fail-fast pipeline для ревью C#/.NET кода (включая Blazor). 6 стадий от дешёвых механических проверок к дорогим AI-ревью. Проверяет **только diff** (изменения). Первая критическая проблема → стоп, фикс, повторный запуск.

## Quick Start

```bash
# С контекстом Kaiten-карточки
/ai-hub:code-review /path/to/your-service --card 12345

# С контекстом GitHub PR
/ai-hub:code-review /path/to/your-service --pr https://github.com/your-org/your-service/pull/42

# С текстовым описанием
/ai-hub:code-review /path/to/your-service --desc "Added /languages page with language overview"

# Без контекста — скилл спросит, что именно ревьюим
/ai-hub:code-review /path/to/your-service
```

## Pipeline

```
Stage 0: Build & Analyzers      ⚡ shell script     ~10 sec
Stage 1: Security Patterns      ⚡ shell + grep      ~5 sec
Stage 2: Performance Review     🤖 AI agent (sonnet)  ~30 sec
Stage 3: Architecture Review    🤖 AI agent (sonnet)  ~30 sec
Stage 4: Correctness Review     🤖 AI agent (sonnet)  ~30 sec
Stage 5: UI/Blazor Review       🤖 AI agent (sonnet)  ~30 sec (skip if no .razor)
```

**Fail-fast**: первый BLOCK → стоп. Повторный запуск → пропуск пройденных стадий.

## Фокус на изменениях

Все стадии проверяют **только diff** (`git diff base...HEAD`):
- Shell-скрипты анализируют только добавленные/изменённые строки
- AI-агенты получают diff + контекст задачи, и инструкцию не трогать pre-existing код
- Контекст задачи (Kaiten/PR/описание) помогает агентам понять намерение и оценить критичность

## Baseline (мьют pre-existing issues)

Если скрипты ловят pre-existing warning не связанный с твоей доработкой — добавь в `.code-review-baseline.json`:

```json
{
  "muted": [
    {"rule": "SEC005", "file": "src/Legacy/ProcessRunner.cs", "reason": "Pre-existing, #12345"},
    {"pattern": "warning CS0618", "reason": "Obsolete API, planned for Q3"}
  ]
}
```

## Structure

```
integrations/code-review/
├── commands/
│   └── code-review.md           # Orchestrator (fail-fast pipeline)
├── agents/
│   ├── review-performance.md    # N+1, batch queries, pagination
│   ├── review-architecture.md   # Layers, DI, interfaces, consistency
│   ├── review-correctness.md    # Edge cases, ranges, culture, nulls
│   └── review-ui-blazor.md      # a11y, navigation, CSS, lifecycle
├── scripts/
│   ├── stage0-build.sh          # dotnet build + analyzer warnings
│   ├── stage1-security.sh       # grep-based security anti-patterns
│   └── collect-diff-context.sh  # Prepare diff context for AI agents
├── .claude-plugin/
│   └── plugin.json
└── README.md
```

## RPA Integration

Если в целевом репо есть `reverse-project-analysis/` (от `/ai-hub:rpa-analyze`), AI-агенты используют его для:
- Оценки кардинальности данных на проде (N+1 severity)
- Проверки архитектурной согласованности с документированной моделью
- Валидации паттернов интеграций

## Origin

Создано для автоматизации code review в C#/.NET проектах. Pipeline делает BLOCK findings actionable.
