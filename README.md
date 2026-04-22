# AI Hub

Набор AI-инструментов для интеграции с разными полезными сервисами: Kaiten, Time (Mattermost), Buildin, Genie, Holst. Плюс автоматизация spike-исследований, product discovery, тестирования и диагностики.

---

## Установка

### Claude Code — через marketplace (рекомендуемый способ)

Добавь ai-hub как marketplace и установи нужные плагины:

```bash
# Добавить marketplace (один раз)
claude /plugin marketplace add sagos95/ai-hub

# Установить конкретный плагин
claude /plugin install spike@ai-hub
claude /plugin install kaiten@ai-hub
claude /plugin install time@ai-hub
# ... или всё сразу:
claude /plugin install buildin@ai-hub code-review@ai-hub discovery@ai-hub \
  genie@ai-hub holst@ai-hub hub-meta@ai-hub kaiten@ai-hub \
  reverse-product-analysis@ai-hub spike@ai-hub test-factory@ai-hub time@ai-hub
```

Доступные плагины marketplace: `buildin`, `code-review`, `discovery`, `genie`, `holst`, `hub-meta`, `kaiten`, `reverse-product-analysis`, `spike`, `test-factory`, `time`.

### Claude Code — через git clone (для разработки или full repo)

```bash
git clone https://github.com/sagos95/ai-hub.git
cd ai-hub
cp .env.example .env   # заполнить токены
```

Все скиллы доступны сразу через `/ai-hub:*` команды.

### Другие AI-агенты (Copilot, Codex, Windsurf, Cursor...)

Просто склонируй репозиторий — агент подхватит инструкции и структуру интеграций автоматически. Все скрипты и промпты доступны из коробки.

### Настройка токенов

Kaiten требует ручной настройки токена в `.env`:

```bash
KAITEN_API_TOKEN=...      # Kaiten (задачи, доски, спринты)
```

Для остальных интеграций есть установочные скиллы:
- Time — `/ai-hub:time-login` (browser-based SSO)
- Buildin — `/ai-hub:buildin-login` (browser-based SSO)

Скиллы без токенов (ai-test, rpa-analyze, retro, code-review) работают сразу.

### Кастомизация под команду

Скопируй `team-config.example.json` → `team-config.json` и заполни ID своих досок, колонок и каналов. Скрипты и команды подхватят конфиг автоматически.

---

## Структура

```
├── .claude-plugin/
│   └── plugin.json               # Манифест плагина
├── .claude/commands/ai-hub/      # Slash-команды (симлинки → integrations/)
├── integrations/                 # Модули скиллов
│   ├── kaiten/                   #   Kaiten API — универсальный клиент
│   ├── buildin/                  #   Buildin — wiki
│   ├── time/                     #   Time (Mattermost)
│   ├── genie/                    #   Databricks Genie (аналитика)
│   ├── holst/                    #   Holst.so — визуальные доски
│   ├── spike/                    #   Spike-исследования
│   ├── discovery/                #   Product Discovery (9 фаз)
│   ├── reverse-product-analysis/ #   Реверс-анализ сервисов
│   ├── test-factory/             #   AI-тестирование
│   ├── code-review/              #   Code review workflow
│   └── hub-meta/                 #   Мета-команды хаба
├── team-config.example.json      # Шаблон конфига команды
└── CLAUDE.md                     # Инструкции для AI-агента
```

### Архитектура

Каждая интеграция — самодостаточный модуль (scripts/, commands/, skills/, agents/). Нет общих папок-свалок — каждый файл живёт в папке своей интеграции. Можно взять отдельный модуль и переиспользовать его целиком.

```
integrations/
├── integration-1/
│   ├── commands/
│   └── skills/...
├── integration-2/
│   ├── README.md
│   ├── commands/
│   └── skills/...
```

---

## Интеграции

Главная идея — **дать AI-агенту полный контекст из командных систем**, чтобы он мог работать автономно. Агент не ограничен только кодом и git-историей — он читает задачи, обсуждения, wiki, метрики и диагностирует проблемы сам.

### Источники контекста

- **[Kaiten](integrations/kaiten/)** — универсальный клиент для Kaiten API. Чтение и запись карточек, комментариев, чек-листов, свойств, структуры досок и колонок. Фундамент для большинства других интеграций.

- **[Time](integrations/time/)** `/ai-hub:time-chat` — полный доступ к мессенджеру Time (Mattermost). Чтение каналов и тредов, отправка сообщений. Логин через browser-based SSO — токен не попадает в контекст LLM.

- **[Buildin](integrations/buildin/)** `/ai-hub:buildin-read` `/ai-hub:buildin-publish` — чтение и запись во внутреннюю wiki Buildin.ai. Рекурсивное раскрытие вложенных блоков, навигация по дереву, поиск по названию.

- **[Holst](integrations/holst/)** `/ai-hub:holst-export` — экспорт данных с визуальных досок Holst.so (аналог Miro). Фреймы, стикеры, тексты — для превращения брейнштормов в структурированные документы.

- **[Genie](integrations/genie/)** — запросы к DWH на естественном языке через Databricks Genie. Валидация гипотез, сбор метрик, анализ данных прямо в потоке работы.

### Автоматизация процессов

- **[Spike](integrations/spike/)** `/ai-hub:spike` — полный цикл spike-исследования. Три агента (explorer → researcher → architect) последовательно изучают код, ищут best practices и формулируют варианты решения. Структурированный отчёт за 10–20 минут вместо дней ручного погружения.

- **[Discovery](integrations/discovery/)** `/ai-hub:discovery` — Product Discovery в 9 фаз: от формулировки проблемы до go/no-go решения. 12 субагентов передают артефакты друг другу, подтягивая данные из Kaiten и Genie автоматически.

- **[Reverse Analysis](integrations/reverse-product-analysis/)** `/ai-hub:rpa-analyze` — реверс-анализ сервиса по исходному коду. 9 агентов в 4 волны: домен, эндпоинты, поведение, контракты, интеграции, сценарии. Полная карта того, что сервис делает.

### Разработка и качество

- **[Test Factory](integrations/test-factory/)** `/ai-hub:ai-test` — AI-генерация тестов. Два агента в Ralph-loop: coder пишет, reviewer критикует — до 5 итераций до достаточного качества.

- **[Code Review](integrations/code-review/)** `/ai-hub:code-review` — автономный code review через fail-fast pipeline (build → security → performance → architecture → correctness).

---

## Использование как team overlay

AI Hub задуман как **generic-ядро**, которое команда может расширить своей спецификой. Паттерн:

1. Подключи ai-hub в свой overlay-репозиторий как git subtree (см. ниже)
2. Добавь свой `team-config.json` с ID досок и каналов
3. Добавь команднo-специфичные интеграции (например, свой kaiten-workflow с нужными колонками)
4. Добавь `AI_CONTEXT.md` с описанием своей команды и продуктов

Generic-интеграции получают обновления из ai-hub, а командная специфика живёт отдельно.

### Установка как git subtree (одной командой)

Из корня своего overlay-репозитория:

```bash
curl -sL https://raw.githubusercontent.com/sagos95/ai-hub/main/scripts/install-as-subtree.sh | bash
```

Это добавит remote `ai-hub`, сделает `git subtree add --prefix=integrations/sagos95-ai-hub` и подскажет, как зарегистрировать плагин в `.claude/settings.json`. Свой prefix можно передать аргументом:

```bash
curl -sL https://raw.githubusercontent.com/sagos95/ai-hub/main/scripts/install-as-subtree.sh | bash -s integrations/ai-hub
```

### Обновление subtree

```bash
curl -sL https://raw.githubusercontent.com/sagos95/ai-hub/main/scripts/update-from-ai-hub.sh | bash
# либо с локальным скриптом (если сохранил его в своём репо):
./scripts/update-from-ai-hub.sh [prefix]
```

### Альтернатива — вручную

```bash
# установка
git remote add ai-hub https://github.com/sagos95/ai-hub.git
git fetch ai-hub
git subtree add --prefix=integrations/sagos95-ai-hub ai-hub main --squash

# обновление
git subtree pull --prefix=integrations/sagos95-ai-hub ai-hub main --squash
```

### Пример структуры overlay-репозитория

```
your-team-repo/
├── integrations/
│   ├── sagos95-ai-hub/         ← subtree (read-only для команды; правки → PR в sagos95/ai-hub)
│   ├── <your-team>-workflow/   ← команднo-специфичные скиллы
│   └── <other-vendor>/         ← при желании — другой публичный hub как ещё один subtree
├── .claude/
│   ├── settings.json           ← plugins: ["./integrations/sagos95-ai-hub", "."]
│   └── commands/<ns>/          ← симлинки на команды из integrations/*
├── team-config.json            ← локальный (gitignore или без секретов)
├── AI_CONTEXT.md               ← описание команды и продуктов
└── CLAUDE.md                   ← корневые инструкции (vendor-CLAUDE.md игнорятся)
```

**Инвариант:** `integrations/sagos95-ai-hub/` — read-only. Любые правки generic-скиллов идут PR в upstream `sagos95/ai-hub`, затем `update-from-ai-hub.sh` в overlay-репо.

---

## Добавить новый скилл

```bash
# Создать команду (файл + симлинк + запись в registry)
claude /ai-hub:create-command my-integration my-command

# Написать логику в integrations/my-integration/
```

## Лицензия

MIT
