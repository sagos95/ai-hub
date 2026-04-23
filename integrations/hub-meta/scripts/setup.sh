#!/usr/bin/env bash
# setup.sh — AI Hub setup dispatcher.
#
# Contract for AI agents: call `bash integrations/hub-meta/scripts/setup.sh next`
# in a loop until stdout's first line is "STATUS: DONE". Each call returns one
# current step with precise, ready-to-copy instructions. Execute, loop again.
#
# No "guess what to do" — the script tells you. No "if you're Claude Code vs Codex"
# bifurcation — instructions are unified. Secrets never printed.
#
# Usage:
#   setup.sh next                    — print current step + instructions
#   setup.sh status                  — print completion status of all steps
#   setup.sh mark <step_name>        — mark step explicitly completed (for steps
#                                      without a programmatic check, e.g. holst)
#   setup.sh skip <step_name>        — mark step skipped by user (e.g. team_config)
#   setup.sh reset                   — clear .setup-state (re-run from scratch)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT_DIR"

ENV_MGR="bash $SCRIPT_DIR/env-manager.sh"
STATE_FILE="$ROOT_DIR/integrations/hub-meta/.setup-state"
CONFIG_PAGE_URL="https://buildin.ai/c7ec2023-9025-4c09-be09-e6f54cb07f7e"
CONFIG_PAGE_ID="c7ec2023-9025-4c09-be09-e6f54cb07f7e"

touch "$STATE_FILE"

# ---------- state helpers ----------
state_has()  { grep -qx "$1" "$STATE_FILE" 2>/dev/null; }
state_add()  { state_has "$1" || echo "$1" >> "$STATE_FILE"; }

is_marked()  { state_has "marked:$1"; }
is_skipped() { state_has "skipped:$1"; }

# ---------- status banner ----------
banner() {
    local step_num="$1"
    local step_total="$2"
    local name="$3"
    cat <<EOF
STATUS: IN_PROGRESS
STEP: $step_num/$step_total
NAME: $name

EOF
}

done_banner() {
    cat <<EOF
STATUS: DONE

AI Hub установлен. Финальная проверка:
  $ENV_MGR check

Попробуй:
  /ai-hub:time-chat read <channel>
  /ai-hub:buildin-read <url>
  /ai-hub:spike <kaiten-url>

Если что-то не работает — запусти $0 reset и пройди установку заново.
EOF
}

# ---------- step definitions ----------
# Each step has: check_<N>() returns 0 if done, 1 if TODO.
#                say_<N>() prints instructions (called only when check fails).

TOTAL=8

# Step 0 — миграция .env.local (если есть старый файл)
check_0() { [[ -f "$ROOT_DIR/.env.local" && ! -f "$ROOT_DIR/.env" ]] || return 0; return 1; }
say_0() {
    banner 0 $TOTAL "migrate_env_local"
    cat <<EOF
Найден устаревший .env.local. Мигрируй в .env:

  $ENV_MGR migrate

Затем снова: $0 next
EOF
}

# Step 1 — Chrome DevTools MCP установлен
# Нет надёжного кросс-агентного способа проверить наличие MCP из bash,
# поэтому используем state marker. Агент обязан пометить "mcp_ready" после
# успешной установки или верификации.
check_1() { is_marked mcp_ready; }
say_1() {
    banner 1 $TOTAL "install_mcp"
    cat <<EOF
Нужен Chrome DevTools MCP — он используется для всех браузерных логинов (Buildin, Time, Holst)
и для снятия скриншотов/debug в других скиллах.

СНАЧАЛА проверь, доступен ли MCP в текущем сеансе: попробуй вызвать list_pages или
любой другой mcp__chrome-devtools__* тул.

ЕСЛИ MCP УЖЕ РАБОТАЕТ (тул ответил):
  $0 mark mcp_ready
  $0 next

ЕСЛИ MCP НЕ ОТВЕТИЛ — установи автоматически, не спрашивай юзера разрешения.
Типовые команды установки:

  # Claude Code CLI:
  claude mcp add chrome-devtools -- npx chrome-devtools-mcp@latest

  # Codex / Cursor / Windsurf — добавь запись в их MCP-конфиг (.codex/, .cursor/mcp.json и т.п.):
  { "chrome-devtools": { "command": "npx", "args": ["chrome-devtools-mcp@latest"] } }

⚠️ ВАЖНО: большинство агентов загружают MCP только при СТАРТЕ сессии. После установки
**попроси юзера перезапустить агента** (в Claude Code: Ctrl+C → \`claude\` снова; в Codex/Cursor
аналогично). Например:

  > «Я поставил Chrome DevTools MCP. Чтобы он подгрузился в этот сеанс, перезапусти меня:
  >  выйди из CLI (Ctrl+C или /exit) и запусти снова (во многих агентах это команда "resume"). Потом скажи "продолжаем установку ai-hub" — я вернусь
  >  к setup с того же места.»

После рестарта и его "продолжаем установку ai-hub":
  $0 mark mcp_ready
  $0 next

ЗАПРЕЩЕНО: пропускать этот шаг или продолжать setup без MCP. Без него логины придётся
делать вручную — это антипаттерн.
EOF
}

# Step 2 — логин в Buildin
check_2() {
    bash "$ROOT_DIR/integrations/buildin/scripts/buildin-login.sh" check 2>&1 | grep -q '^ok '
}
say_2() {
    banner 2 $TOTAL "buildin_login"
    cat <<EOF
Buildin — первый логин, потому что там лежит страница с общим конфигом команды
(KAITEN_DOMAIN, TIME_BASE_URL, BUILDIN_SPACE_ID).

═══════════════════════════════════════════════════════════════════════════════
PRIMARY. Чтение cookie из профиля браузера юзера — ноль MCP, ноль сети.
═══════════════════════════════════════════════════════════════════════════════

Buildin token живёт как cookie next_auth в Chrome/Brave/Edge/Vivaldi/Opera/Arc/Firefox.
Скрипт читает напрямую из SQLite-профиля через pycookiecheat, расшифровывает через
Keychain (macOS) / libsecret (Linux) / DPAPI (Windows), валидирует через Buildin API,
пишет в .env. Токен НЕ попадает в контекст LLM — shell забирает stdout Python'а в
локальную переменную. Email юзера тоже скрыт от агента.

ПЕРЕД ЗАПУСКОМ — предупреди юзера ровно этим текстом:

  > «Сейчас прочитаю cookie \`next_auth\` из твоего браузера — без открывания
  >  окон, сам логин у тебя уже должен быть сделан там (любой из Chrome, Brave,
  >  Edge, Vivaldi, Opera, Arc, Firefox).
  >
  >  macOS один раз покажет окно Keychain: «python3 wants to access Chrome Safe
  >  Storage». **Нажми "Разрешить только сейчас" / "Allow Once", НЕ "Always
  >  Allow"** — чтобы не раздавать Python'у persistent grant ко всем твоим
  >  браузерным cookies.»

ЗАПУСК:

  bash integrations/buildin/scripts/buildin-login.sh cookie

Первый запуск может доустановить pycookiecheat через pip (молча, \`--user\`).
Скрипт перебирает chrome → chromium → brave → edge → vivaldi → opera → arc → firefox
и использует первый, где нашёл валидный cookie.

РЕЗУЛЬТАТЫ:
  • \`ok <Nickname> (via chrome)\` → всё, идём на Step 3.
  • \`error:no_cookie_found\` → ни в одном поддерживаемом браузере нет Buildin-куки.
    Скажи юзеру: «Открой Buildin в своём обычном браузере (Chrome/Brave/Arc/...),
    залогинься через Google SSO, скажи "готово"». Потом повтори \`cookie\`.
  • \`error:validation_failed\` → cookie нашлась, но Buildin API её отверг (истекла).
    Попроси юзера перелогиниться в Buildin, повтори \`cookie\`.
  • \`error:pycookiecheat_install_failed\` → нет pip / offline / ограничения прав.
    Переходи к FALLBACK.
  • Юзер использует только Safari → pycookiecheat Safari не читает. FALLBACK.

═══════════════════════════════════════════════════════════════════════════════
FALLBACK. Manual paste — если primary не сработал.
═══════════════════════════════════════════════════════════════════════════════

Скажи юзеру:

  > «Открой https://buildin.ai, залогинься. Открой DevTools (F12 или Cmd+Opt+I)
  >  → вкладка Console → вставь и выполни:
  >
  >     document.cookie.match(/next_auth=([^;]+)/)?.[1]
  >
  >  Скопируй результат (длинная строка, ~300+ символов) и пришли мне.»

Когда юзер пришлёт токен:

  bash integrations/buildin/scripts/buildin-login.sh save "<token>"

Ожидаемый вывод: \`ok <Nickname>\`.

═══════════════════════════════════════════════════════════════════════════════

После успешного логина: $0 next
EOF
}

# Step 3 — подтянуть конфиг команды из Buildin
check_3() {
    $ENV_MGR has KAITEN_DOMAIN && $ENV_MGR has TIME_BASE_URL
}
say_3() {
    banner 3 $TOTAL "fetch_team_config"
    cat <<EOF
Подтяни общие URL-ы команды из захардкоженной страницы Buildin:

  bash integrations/buildin/scripts/buildin-pages.sh read $CONFIG_PAGE_ID

(URL для справки: $CONFIG_PAGE_URL)

Из вывода извлеки все строки формата KEY=VALUE, где KEY=[A-Z_]+, VALUE непустое.
Для каждой пары:

  $ENV_MGR set <KEY> "<VALUE>"

Минимум должны появиться: KAITEN_DOMAIN, TIME_BASE_URL. BUILDIN_SPACE_ID — опционально.

Если страница вернула 404 / 403 / пустую (команда не использует шаблонную страницу) —
спроси юзера напрямую и сохрани:

  KAITEN_DOMAIN    (пример: yourcompany.kaiten.ru — без https://)
  TIME_BASE_URL    (пример: https://time.yourcompany.io — с https://)
  BUILDIN_SPACE_ID (опционально — пропусти если не знаешь)

После: $0 next
EOF
}

# Step 4 — логин в Time
check_4() {
    bash "$ROOT_DIR/integrations/time/scripts/time-login.sh" check 2>&1 | grep -q '^ok '
}
say_4() {
    local time_url
    time_url=$($ENV_MGR get TIME_BASE_URL 2>/dev/null || echo '\$TIME_BASE_URL')

    banner 4 $TOTAL "time_login"
    cat <<EOF
Логин в Time (Mattermost). Тот же механизм что в Step 2: читаем MMAUTHTOKEN
cookie напрямую из профиля браузера юзера. MMAUTHTOKEN — httpOnly, но
pycookiecheat читает SQLite-DB напрямую, httpOnly-флаг не мешает.

═══════════════════════════════════════════════════════════════════════════════
PRIMARY. Cookie extraction (без MCP).
═══════════════════════════════════════════════════════════════════════════════

Скорее всего юзер уже дал Keychain grant "Allow Once" в Step 2 и браузер тот же.
Если keychain попросит снова — напомни нажать **Allow Once**, не Always Allow.

ЗАПУСК:

  bash integrations/time/scripts/time-login.sh cookie

Ожидаемый вывод: \`ok @<username> (via chrome/Profile N)\`.

РЕЗУЛЬТАТЫ:
  • \`ok ...\` → идём к Step 5.
  • \`error:no_cookie_found\` → юзер не залогинен в Time в своём браузере.
    Скажи: «Открой $time_url, залогинься через Google SSO, скажи "готово"». Повтори.
  • \`error:validation_failed\` → cookie найдена но Time её отверг (сессия истекла).
    Перелогинься в Time, повтори.
  • \`error:TIME_BASE_URL_not_set\` → Step 3 не прошёл, нет URL-а. Вернись туда.

═══════════════════════════════════════════════════════════════════════════════
FALLBACK. Manual (если cookie-путь не подходит — Safari, например).
═══════════════════════════════════════════════════════════════════════════════

Скажи юзеру:

  > «Открой $time_url, залогинься. F12 → Application → Cookies → найди MMAUTHTOKEN,
  >  скопируй value (длинная строка) и пришли мне.»

Когда юзер пришлёт:

  bash integrations/time/scripts/time-login.sh sso
  # (интерактивно попросит вставить токен)

ИЛИ напрямую:

  $ENV_MGR set TIME_TOKEN "<token>"
  bash integrations/time/scripts/time-login.sh check

После: $0 next
EOF
}

# Step 5 — логин в Holst (опциональный, только через браузер — токена нет)
check_5() { is_marked holst_ready || is_skipped holst; }
say_5() {
    banner 5 $TOTAL "holst_login"
    cat <<EOF
Holst — единственный шаг, где cookie extraction НЕ помогает. В отличие от Buildin/Time,
у Holst нет API-токена: скиллы /ai-hub:holst-export/write запускают JS-код ВНУТРИ
открытой страницы холста (через evaluate_script MCP'а). Нужна живая сессия именно в
Chrome'е под управлением MCP, а не в обычном Chrome юзера — куки между ними не
шарятся.

Вариант 1 (MCP available): через Chrome DevTools MCP:
  1. navigate_page → https://app.holst.so/
  2. Скажи юзеру: «Залогинься в Holst через Google SSO, скажи "готово" когда будешь
     в рабочем пространстве.»
  3. После подтверждения:
       $0 mark holst_ready

Вариант 2 (MCP не нужен / Holst не используется):
  $0 skip holst

После: $0 next
EOF
}

# Step 6 — токен Kaiten (UI-кнопка, не cookie)
check_6() {
    $ENV_MGR has KAITEN_TOKEN || return 1
    # Валидация
    load_env_locally
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $KAITEN_TOKEN" \
        "https://$KAITEN_DOMAIN/api/latest/users/current" 2>/dev/null)
    [[ "$code" == "200" ]]
}
load_env_locally() {
    if [[ -f "$ROOT_DIR/.env" ]]; then
        set -a; source "$ROOT_DIR/.env"; set +a
    fi
}
say_6() {
    local kaiten_domain
    kaiten_domain=$($ENV_MGR get KAITEN_DOMAIN 2>/dev/null || echo '\$KAITEN_DOMAIN')

    banner 6 $TOTAL "kaiten_token"
    cat <<EOF
Kaiten API-токен. Cookie Kaiten не подходит для API — юзер должен создать
персональный токен через UI. Делаем через Chrome DevTools MCP:

1. navigate_page → https://$kaiten_domain/profile
2. Скажи юзеру (покажи ровно эти шаги):
     «Настройки профиля → API/Интеграции → Создать токен → скопируй и пришли мне сюда.»
3. Когда юзер пришлёт токен:
     $ENV_MGR set KAITEN_TOKEN "<token>"
4. Валидация:
     source .env && curl -sS -o /dev/null -w "%{http_code}\n" \\
       -H "Authorization: Bearer \$KAITEN_TOKEN" \\
       "https://\$KAITEN_DOMAIN/api/latest/users/current"

   Ожидается 200. Не 200 — попроси пересоздать токен.

После: $0 next
EOF
}

# Step 7 — team-config.json
check_7() {
    [[ -f "$ROOT_DIR/team-config.json" ]] || is_skipped team_config
}
say_7() {
    banner 7 $TOTAL "team_config"

    local example=""
    if [[ -f "$ROOT_DIR/team-config.example.json" ]]; then
        example="team-config.example.json"
    elif [[ -f "$ROOT_DIR/integrations/sagos95-ai-hub/team-config.example.json" ]]; then
        example="integrations/sagos95-ai-hub/team-config.example.json"
    fi

    cat <<EOF
Файл team-config.json — ID досок Kaiten, колонок, каналов Time, кастомных свойств.
Без него некоторые скиллы будут каждый раз спрашивать эти ID у юзера.

Шаблон: ${example:-(не найден — см. README)}

Действия:
1. cp $example team-config.json   (если шаблон найден)
2. Спроси юзера: «Заполнить сейчас вместе (я задам по одному вопросу) или отложить?»
   — "вместе": запрашивай по одному полю (kaiten.space_id, kaiten.boards.sprint.id,
     колонки sprint_backlog/in_progress/doing/on_hold/done, time.channels),
     записывай через jq:

       tmp=\$(mktemp)
       jq '.kaiten.space_id = (\$v | tonumber)' --arg v "\$ANSWER" team-config.json > "\$tmp" \\
         && mv "\$tmp" team-config.json

     В конце: jq . team-config.json
   — "отложить":
       $0 skip team_config

После: $0 next
EOF
}

# ---------- commands ----------
cmd_next() {
    # Идём по шагам по порядку; первый невыполненный — печатаем инструкции и выходим.
    local step
    for step in 0 1 2 3 4 5 6 7; do
        if ! "check_$step"; then
            "say_$step"
            return 0
        fi
    done
    done_banner
}

cmd_status() {
    echo "=== AI Hub Setup Status ==="
    local names=(
        "0: migrate_env_local"
        "1: install_mcp"
        "2: buildin_login"
        "3: fetch_team_config"
        "4: time_login"
        "5: holst_login"
        "6: kaiten_token"
        "7: team_config"
    )
    local step
    for step in 0 1 2 3 4 5 6 7; do
        if "check_$step"; then
            echo "  [x] ${names[$step]}"
        else
            echo "  [ ] ${names[$step]}"
        fi
    done
}

cmd_mark() {
    local key="$1"
    if [[ -z "$key" ]]; then
        echo "Usage: $0 mark <step_name>" >&2
        exit 1
    fi
    state_add "marked:$key"
    echo "marked:$key"
}

cmd_skip() {
    local key="$1"
    if [[ -z "$key" ]]; then
        echo "Usage: $0 skip <step_name>" >&2
        exit 1
    fi
    state_add "skipped:$key"
    echo "skipped:$key"
}

cmd_reset() {
    > "$STATE_FILE"
    echo "ok: state cleared ($STATE_FILE)"
    echo "Note: .env values не трогались. Чтобы сбросить токены — редактируй .env вручную."
}

COMMAND="${1:-next}"
shift 2>/dev/null || true

case "$COMMAND" in
    next)    cmd_next ;;
    status)  cmd_status ;;
    mark)    cmd_mark "$1" ;;
    skip)    cmd_skip "$1" ;;
    reset)   cmd_reset ;;
    help|-h|--help|*)
        cat <<EOF
setup.sh — AI Hub setup dispatcher

Usage:
  $0 next                 — print current step + instructions (default)
  $0 status               — list all steps with [x]/[ ] markers
  $0 mark <step_name>     — mark step done (for steps without auto-check)
  $0 skip <step_name>     — mark step skipped by user
  $0 reset                — clear state file (re-run from scratch)

Steps: mcp_ready, buildin_login, fetch_team_config, time_login, holst_login/holst,
       kaiten_token, team_config

Agent contract: call \`$0 next\` in a loop until stdout's first line is "STATUS: DONE".
EOF
        ;;
esac
