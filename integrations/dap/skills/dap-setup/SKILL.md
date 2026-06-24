---
name: dap-setup
description: >
  Bootstrap the Dodo AI-Platform (DAP) skills and prepare the machine to work
  with the platform. Triggers when the user asks to set up DAP / Dodo AI
  platform, install platform skills, run dap-doctor / dap-shipmaster, "подготовь
  машину к работе с Dodo AI-платформой", "поставь скиллы платформы", "настрой
  dap", "забутстрапь доктора". Installs dap-doctor + dap-shipmaster into
  ~/.claude/skills/ and brings the environment up to spec via the doctor's
  Tier-1 diagnostics. Ask before every install or login.
---

# DAP Setup skill

Готовит машину к работе с **Dodo AI-платформой**: ставит платформенные скиллы
`dap-doctor` и `dap-shipmaster` в `~/.claude/skills/` и приводит окружение в порядок
строго по выводу `dap-doctor`.

## Trigger

Активируйся, когда юзер просит подготовить машину к Dodo AI-платформе, поставить/обновить
скиллы платформы, запустить диагностику доктора, или упоминает `dap-doctor` / `dap-shipmaster`.

## Что делать

Следуй пошаговому флоу из канонического файла команды:
**`integrations/dap/commands/dap-setup.md`** (доступен как `/ai-hub:dap-setup`).

Кратко, 4 шага:

1. **git** — убедись, что установлен (на macOS — Command Line Tools `xcode-select --install`,
   не Homebrew). Доступ к GitHub-орг `dodo-ai-platform` должен быть уже выдан.
2. **Бутстрап** — `git clone --depth 1 https://github.com/dodo-ai-platform/project-template
   /tmp/dap-template && bash /tmp/dap-template/.agents/skills/dap-doctor/scripts/install-skills.sh`.
3. **Tier-1 диагностика** — `bash ~/.claude/skills/dap-doctor/scripts/check-env.sh`, затем для
   каждого `[MISS]`/`[WARN]` выполняй ровно его `fix:` (по одному, с согласия юзера) и
   перезапускай, пока всё не станет зелёным. На не-macOS ничего не ставь сам — показывай команду.
4. **Обновление** — периодически `install-skills.sh --check` и `install-skills.sh`.

## Главное правило

**Спрашивай юзера перед КАЖДОЙ установкой или логином.** Ничего не ставь и не логинься молча.
