# Spike from Meeting

Превращает запись встречи + транскрипт в готовый markdown-артефакт со скриншотами, привязанными к таймкодам.

## Использование

```
/ai-hub:spike-from-meeting [путь_или_URL] [формат]
```

Аргументы опциональны — если не указаны, скилл сам спросит.

**Что можно дать:**
- Путь к `.mp4` + путь к транскрипт-файлу (`.txt` / `.vtt` / `.srt`)
- URL записи в Контур.Толк (например `https://talk.kontur.ru/r/<id>`) — транскрипт заберётся через API
- Формат документа: `spike`, `recap`, `plan`, `instruction`, `custom`

## Результат

```
<artifact_dir>/
├── <artifact-name>.md          # главный документ со встроенными скриншотами
├── transcript.txt              # копия транскрипта
└── pictures/                   # все скриншоты + GIF
```

## Ключевые фичи

- **Самоверификация скриншотов** — после извлечения каждого кадра скилл читает PNG и сравнивает с тем, что обсуждалось в этот момент в транскрипте; если кадр не подходит — итеративно корректирует таймкод (`+10s` / `-10s` / середина интервала) до 3 попыток.
- **GIF для динамики** — для моментов навигации (переключение вкладок, скролл, hover) скилл предлагает сделать короткий GIF на 3–5 сек вместо статичного скриншота.
- **PII-редакция через `ffmpeg drawbox`** — если на кадрах видны имена + телефоны / клиентские данные, скилл сначала спрашивает разрешение и закрывает их непрозрачными чёрными прямоугольниками. Unredacted-копии удаляются с диска.
- **Контур.Толк API** — при наличии API-ключа транскрипт забирается автоматически, не нужно вручную экспортировать.

## Форматы документов

| Формат | Когда |
|--------|-------|
| `spike` | Спайк-исследование по задаче из таск-трекера |
| `recap` | Конспект регулярной встречи (что обсудили / решения / action items) |
| `plan` | План правок по категориям и приоритетам (для встреч со стейкхолдером) |
| `instruction` | Пошаговая инструкция «как сделать X» |
| `dual-artifact` | Длинная статья + короткий пост-анонс для Slack/Time (два файла + одна папка `pictures/`) |
| `custom` | Любая структура по описанию пользователя |

## Зависимости

- `ffmpeg` — для извлечения кадров и GIF. Установка: `brew install ffmpeg`
- `curl`, `jq` — для Kontur.Talk API
- `KTALK_SESSION_TOKEN` env var — значение cookie `sessionToken` из Chrome для tenant'а (например `<tenant>.ktalk.ru`). Получить: залогиниться в браузере → DevTools → Application → Cookies → скопировать. Для агентов в Claude Code — через `chrome-devtools` MCP можно автоматически.

## Скрипты

- `scripts/extract-frame.sh <video> <HH:MM:SS> <output.png>` — один кадр
- `scripts/extract-gif.sh <video> <HH:MM:SS> <duration_sec> <output.gif>` — короткий GIF
- `scripts/kontur-talk-transcript.sh <recording_url>` — забор транскрипта через API (`KTALK_SESSION_TOKEN` из env)
- `scripts/kontur-talk-video.sh <recording_url> <out.mp4> [quality]` — скачать MP4

## Карта Контур.Толк API (верифицирована 2026-05-12)

| Эндпоинт | Зачем |
|----------|-------|
| `GET /api/recordings/{id}` | Метаданные: title, duration, qualities[], participants[] |
| `GET /api/recordings/v2/{id}/summary` | Полный транскрипт (`transcriptionV2`) + AI-протокол + summary |
| `GET /api/conferenceshistory/v2/{conferenceKey}` | Chat-сообщения и участники |
| `GET /recording-blob/{id}/{quality}` | MP4 (с Range) |

Auth для всех: `Authorization: Session <sessionToken>` + `x-platform: web`.

## Версия

- **0.3.0** (2026-05-12) — Урок-driven итерация после двух реальных прогонов:
  - **Новый пресет `dual-artifact`** (длинная статья + короткий Slack-пост в одной папке) — типовой запрос
  - **Phrase-based timecode hints** (Этап 4.3): таблица «фраза в транскрипте → типовое смещение» — экономит 1-2 итерации на кадр
  - **ktalk-specific patterns** (Этап 4.4): распознавание placeholder `"You are sharing the screen"` как сигнала «сдвинь +20s»
  - **Interleaved extract+verify** вместо batch — экономит контекст
  - **Ориентир на длинные встречи** (60-90 мин → 8-15 кадров) с принципом «один скриншот = одна новая идея»
  - **Lessons from past runs** — секция с эмпирикой от Ksenia 2026-04-27 (plan, 30 мин, 9 кадров) и WorkShop AI MAGIC 2026-05-07 (dual-artifact, 65 мин, 8 кадров)
- **0.2.0** (2026-05-12) — Kontur.Talk API верифицирован на реальном ktalk-tenant'е; добавлен `kontur-talk-video.sh`; переход с API-ключа на session token из Chrome cookies; рабочий end-to-end на реальной записи 65-минутной встречи.
- **0.1.0** — первая итерация: workflow, верификация скриншотов, форматные пресеты, GIF, PII-редакция, scaffold Kontur.Talk API.
