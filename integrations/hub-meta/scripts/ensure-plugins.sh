#!/usr/bin/env bash
# Проверяет наличие обязательных плагинов из маркетплейса.
# Если плагин не установлен — устанавливает автоматически.
#
# Использование:
#   ./integrations/hub-meta/scripts/ensure-plugins.sh feature-dev code-review
#   ./integrations/hub-meta/scripts/ensure-plugins.sh  # все обязательные
#
# Exit codes:
#   0 — все плагины установлены (или были установлены сейчас)
#   1 — не удалось установить один или более плагинов

set -euo pipefail

MARKETPLACE="claude-plugins-official"
REGISTRY="$HOME/.claude/plugins/installed_plugins.json"

# Обязательные плагины по умолчанию
DEFAULT_PLUGINS=(feature-dev code-review)

plugins=("${@:-${DEFAULT_PLUGINS[@]}}")

check_installed() {
  local plugin="$1"
  local key="${plugin}@${MARKETPLACE}"
  if [[ -f "$REGISTRY" ]] && jq -e ".plugins[\"$key\"] | length > 0" "$REGISTRY" &>/dev/null; then
    return 0
  fi
  return 1
}

install_plugin() {
  local plugin="$1"
  echo "Installing ${plugin}@${MARKETPLACE}..."
  if claude plugin install "${plugin}@${MARKETPLACE}" 2>&1; then
    echo "OK: ${plugin} installed"
    return 0
  else
    echo "FAIL: could not install ${plugin}" >&2
    return 1
  fi
}

failed=0
for plugin in "${plugins[@]}"; do
  if check_installed "$plugin"; then
    echo "OK: ${plugin} already installed"
  else
    if ! install_plugin "$plugin"; then
      failed=1
    fi
  fi
done

exit $failed
