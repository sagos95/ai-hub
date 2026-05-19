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

The scripts accept permalinks directly — no manual id extraction.

```bash
# Single post by permalink or raw id
integrations/time/scripts/time-messages.sh get "<permalink_or_post_id>"

# Full thread (preferred — gives complete context)
integrations/time/scripts/time-messages.sh thread "<permalink_or_post_id>" --resolve-users

# DMs with a user (auto-enriched)
integrations/time/scripts/time-messages.sh dm @<username> [limit]

# Search in a team
integrations/time/scripts/time-messages.sh search <team_id> "<query>" --resolve-users
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
