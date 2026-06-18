#!/usr/bin/env bash
# CI-гейт резолва пути к скриптам buildin по всем сценариям потребления хаба.
#
# Зачем: командные .md плагина buildin указывают агенту, каким путём звать скрипты.
# Жёсткий относительный путь работает только из корня репо ai-hub; голый
# ${CLAUDE_PLUGIN_ROOT} — только в плагин-контексте. Этот тест проверяет, что
# резолвер из реальных командных .md находит скрипты во всех сценариях:
#   standalone-клон, subtree-overlay (cwd ≠ корень ai-hub), marketplace-install.
#
# Как: для каждого сценария задаются (cwd, CLAUDE_PLUGIN_ROOT), из .md вырезается
# строка-резолвер и выполняется в этом окружении; проверяется, что найденный
# каталог содержит buildin-pages.sh. Любой провал REQUIRED → exit≠0 → CI красный.
set -u

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
MARK="buildin-pages.sh"

# ---- Фикстуры под каждый layout --------------------------------------------
STANDALONE="$TMP/standalone"                 # git clone ai-hub, запуск внутри
OVERLAY="$TMP/overlay"                        # subtree в чужом репо
CACHE="$TMP/cache"                            # ~/.claude/plugins/cache/<mp>/...
UNRELATED="$TMP/unrelated/some/project"       # произвольный cwd при plugin-install
mk(){ mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n' > "$1"; }
mk "$STANDALONE/integrations/buildin/scripts/$MARK"
mk "$OVERLAY/integrations/team-overlay/integrations/buildin/scripts/$MARK"
mk "$CACHE/buildin/9.9.9/scripts/$MARK"
mkdir -p "$UNRELATED"

# ---- Эталонные резолверы (для информационной матрицы) -----------------------
SNIP_OLD='BUILDIN_SCRIPTS="integrations/buildin/scripts"'          # относительный
SNIP_NEW='BUILDIN_SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"'         # только плагин-контекст

run(){ # $1=snippet $2=cwd $3=root → OK/FAIL
  local dir
  dir=$( cd "$2" && CLAUDE_PLUGIN_ROOT="$3" bash -c "$1"$'\n''printf %s "$BUILDIN_SCRIPTS"' )
  ( cd "$2" && [[ -f "$dir/$MARK" ]] ) && echo OK || echo FAIL
}
glyph(){ [[ "$1" == OK ]] && echo "PASS" || echo "FAIL"; }

# ---- Сценарии: name|cwd|root (все REQUIRED) ---------------------------------
SCN=(
  "standalone, симлинк-команда (var нет)   |$STANDALONE|"
  "standalone, плагин (/plugin)            |$STANDALONE|$STANDALONE/integrations/buildin"
  "overlay-subtree, симлинк-команда (нет)  |$OVERLAY|"
  "overlay-subtree, плагин (/plugin)       |$OVERLAY|$OVERLAY/integrations/team-overlay/integrations/buildin"
  "marketplace-install (кеш плагина)       |$UNRELATED|$CACHE/buildin/9.9.9"
)

gate_snippet(){ # $1=snippet $2=label → число провалов
  local snip="$1" lbl="$2" fails=0
  for row in "${SCN[@]}"; do
    IFS='|' read -r name cwd root <<< "$row"
    [[ "$(run "$snip" "$cwd" "$root")" == OK ]] || { ((fails++)); echo "  FAIL [$lbl]: $(echo "$name" | sed 's/ *$//')"; }
  done
  return $fails
}

extract_resolver(){ # $1=md → строка(и) резолвера
  if grep -q 'resolve-buildin-dir:start' "$1"; then
    sed -n '/resolve-buildin-dir:start/,/resolve-buildin-dir:end/p' "$1"
  elif grep -qE '^[[:space:]]*BUILDIN_SCRIPTS="' "$1"; then
    grep -m1 -E '^[[:space:]]*BUILDIN_SCRIPTS="' "$1"
  else
    echo 'BUILDIN_SCRIPTS="integrations/buildin/scripts"'
  fi
}

SUM="${GITHUB_STEP_SUMMARY:-/dev/null}"
{ echo "### buildin — резолв пути к скриптам по сценариям"; echo
  echo "Колонки: каталог-кандидат найден (PASS) или нет (FAIL)."; echo
  echo "| Сценарий | относит. | \${CLAUDE_PLUGIN_ROOT} | резолвер из .md |"
  echo "|---|---|---|---|"; } >> "$SUM"

echo "== Информационная матрица =="
printf '%-42s | %-9s | %-12s | %s\n' "СЦЕНАРИЙ" "относит." "PLUGIN_ROOT" "резолвер .md"
printf -- '-%.0s' {1..86}; echo

# Берём резолвер из read-page.md как репрезентативный для матрицы (все три одинаковы).
REF_MD=$(find . -path '*/integrations/buildin/commands/read-page.md' -print 2>/dev/null | head -1)
REF_SNIP=$([[ -n "$REF_MD" ]] && extract_resolver "$REF_MD" || echo "$SNIP_OLD")
for row in "${SCN[@]}"; do
  IFS='|' read -r name cwd root <<< "$row"; name="$(echo "$name" | sed 's/ *$//')"
  o=$(run "$SNIP_OLD" "$cwd" "$root"); n=$(run "$SNIP_NEW" "$cwd" "$root"); r=$(run "$REF_SNIP" "$cwd" "$root")
  printf '%-42s | %-9s | %-12s | %s\n' "$name" "$(glyph "$o")" "$(glyph "$n")" "$(glyph "$r")"
  echo "| $name | $(glyph "$o") | $(glyph "$n") | $(glyph "$r") |" >> "$SUM"
done

# ---- ГЕЙТ: резолвер из каждого реального командного .md ----------------------
echo
echo "== ГЕЙТ: резолвер из реальных командных .md =="
FAILS=0
CMD=()
while IFS= read -r line; do CMD+=("$line"); done < <(find . \( \
  -path '*/integrations/buildin/commands/read-page.md' -o \
  -path '*/integrations/buildin/commands/publish-page.md' -o \
  -path '*/integrations/buildin/commands/buildin-login.md' \) -print 2>/dev/null)
if [[ ${#CMD[@]} -eq 0 ]]; then
  echo "  командные .md не найдены"; exit 1
fi
for f in "${CMD[@]}"; do
  gate_snippet "$(extract_resolver "$f")" "$(basename "$f")"; rc=$?
  [[ $rc -eq 0 ]] && echo "  PASS $f" || ((FAILS+=rc))
done

echo
if [[ $FAILS -eq 0 ]]; then
  echo "ИТОГ: PASS — все командные .md резолвят путь во всех сценариях"
  { echo; echo "**ИТОГ: PASS** — все сценарии зелёные."; } >> "$SUM"
else
  echo "ИТОГ: FAIL — провалов REQUIRED: $FAILS"
  { echo; echo "**ИТОГ: FAIL** — провалов: $FAILS."; } >> "$SUM"
fi
exit $FAILS
