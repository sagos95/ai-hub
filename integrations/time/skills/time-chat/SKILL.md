---
name: time-chat
description: >
  Read a Time (Mattermost) post, thread, or DM when the user shares a
  permalink URL like https://<host>/<team>/pl/<post_id> or asks to look up
  a conversation by @handle. Triggers on Time/Mattermost permalinks, on
  any "time-messenger" / "тайм" / "Mattermost" mention paired with a link
  or @username, and on requests to read direct messages with a specific
  user.
---

# Time (Mattermost) read skill

When a Time permalink or a "read DMs with @user" request appears, fetch the
content via the plugin's bash wrappers and summarise it for the user.

## Trigger

Activate on any of:

- A permalink URL: `https://<host>/<team>/pl/<post_id>` (query/fragment ok)
- A request to read DMs / личные сообщения with a specific `@user`
- A search request against Time/Mattermost ("найди в тайме …")

## Read

First resolve the helper once — independent of the current directory. The skill is
activated by its `SKILL.md` from an arbitrary CWD (Claude Code skill / agent context),
so a bare `integrations/time/scripts/...` path does not resolve; derive it from the
repo root (works from anywhere inside the clone) with a Copilot-install fallback:

```bash
TIME_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/integrations/time"
[ -d "$TIME_DIR" ] || TIME_DIR="$(readlink -f "$HOME/.copilot/installed-plugins/_direct/time" 2>/dev/null)"
TIME_MESSAGES="$TIME_DIR/scripts/time-messages.sh"
```

The scripts accept permalinks directly — no manual id extraction.

```bash
# Single post by permalink or raw id
"$TIME_MESSAGES" get "<permalink_or_post_id>"

# Full thread (preferred — gives complete context)
"$TIME_MESSAGES" thread "<permalink_or_post_id>" --resolve-users

# DMs with a user (auto-enriched)
"$TIME_MESSAGES" dm @<username> [limit]

# Search in a team
"$TIME_MESSAGES" search <team_id> "<query>" --resolve-users
```

`--resolve-users` inlines `{username, nickname, first_name, last_name}` next
to every `user_id` so authors are human-readable. Cached at
`integrations/time/.cache/users.json` (7-day TTL).

## Summarise

After fetching, give the user a concise wrap-up: who participated, key
decisions, action items, anything relevant to the current task. For long
threads (50+ messages) summarise rather than repeat verbatim.

## See also

- `commands/time-chat.md` — full interactive workflow, including posting
- `README.md` — auth setup, all actions, troubleshooting
