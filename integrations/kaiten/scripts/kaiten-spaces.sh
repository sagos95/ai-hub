#!/bin/bash
# Kaiten Spaces & Boards API - быстрые команды для работы с пространствами и досками
# Usage: ./kaiten-spaces.sh <command> [args...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kaiten() {
    "$SCRIPT_DIR/kaiten.sh" "$@"
}

show_help() {
    cat << EOF
Kaiten Spaces & Boards CLI

Usage: ./kaiten-spaces.sh <command> [args...]

Commands:
  spaces                             - Список пространств
  space [space_id]                   - Получить пространство (default: \$KAITEN_SPACE)
  
  boards [space_id]                  - Список досок в пространстве (default: \$KAITEN_SPACE)
  board <board_id>                   - Получить доску
  
  columns <board_id>                 - Список колонок на доске
  lanes <board_id>                   - Список дорожек на доске
  
  users                              - Список пользователей
  me                                 - Текущий пользователь
  
  tags                               - Список тегов
  properties                         - Список кастомных свойств
  card-types                         - Список типов карточек

Examples:
  ./kaiten-spaces.sh spaces
  ./kaiten-spaces.sh boards 123
  ./kaiten-spaces.sh columns 456
EOF
}

# Use KAITEN_SPACE as default
SPACE_ID="${KAITEN_SPACE:-}"

case "${1:-help}" in
    spaces)
        kaiten GET "/spaces"
        ;;
    space)
        sid="${2:-$SPACE_ID}"
        [[ -z "$sid" ]] && { echo "Error: space_id required or set KAITEN_SPACE" >&2; exit 1; }
        kaiten GET "/spaces/$sid"
        ;;
    boards)
        sid="${2:-$SPACE_ID}"
        [[ -z "$sid" ]] && { echo "Error: space_id required or set KAITEN_SPACE" >&2; exit 1; }
        kaiten GET "/spaces/$sid/boards"
        ;;
    board)
        kaiten GET "/boards/$2"
        ;;
    columns)
        kaiten GET "/boards/$2/columns"
        ;;
    lanes)
        kaiten GET "/boards/$2/lanes"
        ;;
    users)
        kaiten GET "/users"
        ;;
    me)
        kaiten GET "/users/current"
        ;;
    tags)
        kaiten GET "/tags"
        ;;
    properties)
        kaiten GET "/properties"
        ;;
    card-types)
        kaiten GET "/card-types"
        ;;
    help|--help|-h|*)
        show_help
        ;;
esac
