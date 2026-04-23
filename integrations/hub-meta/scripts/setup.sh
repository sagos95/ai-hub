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
    local mcp_status="ready"
    if is_skipped install_mcp; then
        mcp_status="failed"
    elif ! is_marked mcp_ready; then
        mcp_status="unknown"
    fi

    cat <<EOF
STATUS: DONE

AI Hub установлен. Buildin, Time и Kaiten уже работают в этом же сеансе.

Предложи юзеру что-нибудь попробовать прямо сейчас (без перезапуска), например:
  • «прочитай мне последние 20 сообщений в time-канале dev»
  • «покажи мои открытые карточки в Kaiten»
  • «открой страницу Buildin <ссылка> и суммаризируй»
  • «сделай spike по <карточка Kaiten>»

EOF

    case "$mcp_status" in
        ready)
            cat <<EOF
Holst: MCP установлен. Чтобы Holst-скиллы (/ai-hub:holst-export, /ai-hub:holst-write)
заработали, нужно ОДНОКРАТНО перезапустить сессию агента — MCP-серверы подгружаются
только при старте. Скажи юзеру:

  > «Для Holst перезапусти меня: выйди (Ctrl+C / /exit) и запусти снова. После
  >  рестарта первое что нужно — залогиниться в Holst (один раз): скажи «настрой Holst»,
  >  я открою app.holst.so через MCP и ты зайдёшь через Google SSO.»

Если Holst сейчас не нужен — рестарт можно отложить. Buildin/Time/Kaiten работают
без него.
EOF
            ;;
        failed)
            cat <<EOF
Holst: ⚠️ MCP установить не получилось (нет npx / нет claude CLI / permission denied —
смотри лог выше). Из-за этого /ai-hub:holst-export / /ai-hub:holst-write РАБОТАТЬ НЕ
БУДУТ. Остальное (Buildin, Time, Kaiten, spike, discovery, code-review и т.д.) — ок.

Если захочется починить Holst позже — установи Chrome DevTools MCP руками:
  claude mcp add chrome-devtools -- npx chrome-devtools-mcp@latest
(или аналог для своего агента), перезапусти сессию, потом $0 reset и пройди setup заново.
EOF
            ;;
        unknown)
            cat <<EOF
Holst: MCP не проверялся в этом запуске (шаг был отмечен вручную). Если /ai-hub:holst-*
не работают — поставь MCP и перезапусти сессию.
EOF
            ;;
    esac

    cat <<EOF

Если что-то сломается — \`$0 reset\` и пройди setup заново; \`$ENV_MGR check\` покажет
текущий статус переменных.
EOF
}

# ---------- step definitions ----------
# Each step has: check_<N>() returns 0 if done, 1 if TODO.
#                say_<N>() prints instructions (called only when check fails).

TOTAL=8

# Step 0 — миграция .env.local (если есть старый файл)
check_0() { [[ -f "$ROOT_DIR/.env.local" && ! -f "$ROOT_DIR/.env" ]] || return 0; return 1; }
say_0() {
    cat <<EOF
Найден устаревший .env.local. Мигрируй в .env:

  $ENV_MGR migrate

Затем снова: $0 next
EOF
}

# Step 6 (was 1) — Chrome DevTools MCP. Автоматическая установка.
# Buildin/Time уже работают через cookie extraction; MCP нужен ТОЛЬКО для Holst.
# Агент тихо ставит MCP (если нет); при неудаче — помечает как skipped и идёт
# к DONE с предупреждением что Holst работать не будет.
check_1() { is_marked mcp_ready || is_skipped install_mcp; }
say_1() {
    cat <<EOF
Финальный шаг — Chrome DevTools MCP. Автоматический, без вопросов юзеру.

MCP нужен ТОЛЬКО для /ai-hub:holst-export / /ai-hub:holst-write (доски Holst
работают через живую страницу внутри MCP-браузера). Buildin, Time, Kaiten и
вся остальная функциональность УЖЕ работает без MCP.

АЛГОРИТМ:

1. Проверь сначала — может MCP уже работает: попробуй вызвать
   mcp__chrome-devtools__list_pages (или любой другой mcp__chrome-devtools__*).

2a. Если MCP ОТВЕТИЛ — он уже установлен и загружен:
      $0 mark mcp_ready
      $0 next

2b. Если MCP НЕ ОТВЕТИЛ — поставь его автоматически, без вопросов юзеру:

      # Claude Code CLI:
      claude mcp add chrome-devtools -- npx chrome-devtools-mcp@latest

      # Codex / Cursor / Windsurf — добавь запись в их MCP-конфиг:
      { "chrome-devtools": { "command": "npx", "args": ["chrome-devtools-mcp@latest"] } }

    Если УСПЕХ (команда вернула 0 / запись добавилась):
      $0 mark mcp_ready
      $0 next
      (done_banner сам предупредит про рестарт для Holst)

    Если УСТАНОВКА НЕ УДАЛАСЬ (нет npx, нет claude CLI, permission denied и т.п.):
      $0 skip install_mcp
      $0 next
      (done_banner пометит что Holst работать не будет)

3. ЗАПРЕЩЕНО:
   • спрашивать юзера «поставить MCP?» — ставь сам, молча.
   • перезапускать сессию агента во время setup'а — рестарт нужен только ПОСЛЕ
     setup'а и только если юзер захочет Holst. Про это скажет done_banner.
EOF
}

# Step 2 — логин в Buildin
check_2() {
    bash "$ROOT_DIR/integrations/buildin/scripts/buildin-login.sh" check 2>&1 | grep -q '^ok '
}
say_2() {
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

# Step 7 (was 5) — Holst login. Опциональный, требует MCP из Step 6.
# Если MCP skipped — Holst auto-skip'ится (cascade).
check_5() { is_marked holst_ready || is_skipped holst || is_skipped install_mcp; }
say_5() {
    cat <<EOF
Holst — финальный опциональный шаг. Единственный в setup'е, где cookie extraction НЕ
помогает: у Holst нет API-токена, скиллы /ai-hub:holst-export/write работают через
живую страницу внутри MCP-браузера (evaluate_script).

MCP из Step 6 должен уже быть установлен и доступен.

Через Chrome DevTools MCP:

  1. navigate_page → https://app.holst.so/
  2. Скажи юзеру: «Залогинься в Holst через Google SSO, скажи "готово" когда будешь
     в рабочем пространстве.»
  3. После подтверждения юзера:
       $0 mark holst_ready
       $0 next

Если юзер не хочет настраивать Holst сейчас:
  $0 skip holst
  $0 next
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
# Step execution order. MCP+Holst are moved to the end because they are
# OPTIONAL (MCP is only needed for Holst). All the zero-MCP logins (Buildin,
# Time, Kaiten) complete first so the setup is usable even if MCP install
# fails or the user doesn't want Holst.
STEP_ORDER=(0 2 3 4 6 7 1 5)
STEP_NAMES=(
    "migrate_env_local"
    "buildin_login"
    "fetch_team_config"
    "time_login"
    "kaiten_token"
    "team_config"
    "install_mcp"
    "holst_login"
)
STEP_NOTES=(
    ""
    ""
    ""
    ""
    ""
    ""
    "(optional — only for Holst)"
    "(optional — requires MCP)"
)

cmd_next() {
    # First unfinished step in STEP_ORDER → print its instructions.
    local total=${#STEP_ORDER[@]}
    local i
    for i in "${!STEP_ORDER[@]}"; do
        local step="${STEP_ORDER[$i]}"
        if ! "check_$step"; then
            banner $((i+1)) $total "${STEP_NAMES[$i]}"
            "say_$step"
            return 0
        fi
    done
    done_banner
}

cmd_status() {
    echo "=== AI Hub Setup Status ==="
    local i
    for i in "${!STEP_ORDER[@]}"; do
        local step="${STEP_ORDER[$i]}"
        local name="${STEP_NAMES[$i]}"
        local note="${STEP_NOTES[$i]}"
        local mark="[ ]"
        if "check_$step"; then mark="[x]"; fi
        printf "  %s %d. %s %s\n" "$mark" "$((i+1))" "$name" "$note"
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
