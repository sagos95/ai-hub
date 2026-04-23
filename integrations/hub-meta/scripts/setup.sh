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
  >  выйди из CLI (Ctrl+C или /exit) и запусти снова. Потом скажи "продолжаем" — я вернусь
  >  к setup с того же места.»

После рестарта и его "продолжаем":
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

Путь: browser → локальный HTTP-bridge на 127.0.0.1:<port> → .env. Clipboard НЕ используется
(ненадёжно на macOS с DevTools MCP). Токен не проходит через контекст LLM.

ШАГ 1/4. Подними мост:

  bash integrations/buildin/scripts/buildin-login.sh bridge-start

Вывод содержит строку \`port:<NNNNN>\` — запомни этот порт, он нужен в ШАГЕ 3.

ШАГ 2/4. Через Chrome DevTools MCP открой Buildin:
  navigate_page → https://buildin.ai/login
  Скажи юзеру: «Залогинься через Google SSO. Скажи "готово" когда будешь внутри.»
  Дождись подтверждения.

ШАГ 3/4. Передай токен в мост. evaluate_script (подставь PORT из ШАГА 1):

  async () => {
    const m = document.cookie.match(/next_auth=([^;]+)/);
    if (!m) return { status: 'error', reason: 'no_cookie' };
    try {
      const r = await fetch('http://127.0.0.1:<PORT>/', {
        method: 'POST',
        body: m[1],
        mode: 'cors'
      });
      return { status: r.ok ? 'sent' : 'http_error', http: r.status, length: m[1].length };
    } catch (e) {
      return { status: 'fetch_error', msg: String(e) };
    }
  }

LLM получит только {status, http, length} — сам токен останется в границах браузер↔bridge.

ШАГ 4/4. Прими и сохрани токен:

  bash integrations/buildin/scripts/buildin-login.sh bridge-wait

(блокируется до 3 мин, возвращает \`ok Name (email)\` на успех)

Если любой шаг упал:
  • bridge-start вернул error:no_free_port → повтори через минуту;
  • evaluate_script вернул fetch_error → проверь что bridge ещё жив
    (\`lsof -iTCP:<PORT>\`), возможно Chrome блокирует http-запросы из https-страницы —
    попробуй в DevTools Console вручную: \`fetch('http://127.0.0.1:<PORT>/', {method:'POST', body: 'test'})\`;
  • bridge-wait вернул error:timeout — юзер не дошёл до логина, повтори ШАГ 2 и 3;
  • bridge-wait вернул error:validation_failed — cookie не валидна, юзер не залогинен.

Manual fallback (если bridge не работает в принципе):
  попроси юзера открыть https://buildin.ai, залогиниться, F12 → Console →
  \`document.cookie.match(/next_auth=([^;]+)/)?.[1]\` → прислать тебе результат;
  bash integrations/buildin/scripts/buildin-login.sh save "<token>"

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
Логин в Time (Mattermost). Через Chrome DevTools MCP:

1. navigate_page → $time_url
2. Скажи юзеру: «Залогинься через Google SSO, скажи "готово".»
3. evaluate_script — проверь что ты внутри:
     async () => (await fetch('$time_url/api/v4/users/me')).status

   Ожидается 200.
4. DevTools MCP не читает httpOnly cookies через JS, поэтому:
   Скажи юзеру: «DevTools (F12) → Application → Cookies → найди MMAUTHTOKEN на домене Time →
   скопируй ЗНАЧЕНИЕ (длинная строка) и пришли мне.»
5. Когда юзер пришлёт:
     $ENV_MGR set TIME_TOKEN "<token>"
6. Проверь: bash integrations/time/scripts/time-login.sh check
   Ожидается "ok @username (email)".

После: $0 next
EOF
}

# Step 5 — логин в Holst (опциональный, только через браузер — токена нет)
check_5() { is_marked holst_ready || is_skipped holst; }
say_5() {
    banner 5 $TOTAL "holst_login"
    cat <<EOF
Holst хранит сессию в самом браузере — отдельного токена нет. Достаточно,
чтобы юзер залогинился один раз в том же Chrome, который использует MCP.

Через Chrome DevTools MCP:

1. navigate_page → https://app.holst.so/
2. Скажи юзеру: «Залогинься в Holst, скажи "готово" когда будешь в рабочем пространстве.»
3. После подтверждения:
     $0 mark holst_ready

Если юзер не пользуется Holst и хочет пропустить:
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
