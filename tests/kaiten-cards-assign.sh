#!/usr/bin/env bash
# Регресс-гейт на семантику `assign` в kaiten-cards.sh: команда обязана делать пользователя
# ОТВЕТСТВЕННЫМ за карточку, а не просто участником.
#
# В Kaiten «ответственный» — участник карточки с type 2 (type 1 — обычный участник; именно
# type 2 попадает в фильтр responsible_ids). POST /cards/{id}/members создаёт членство и
# ИГНОРИРУЕТ переданный type — роль поднимает только PATCH /cards/{id}/members/{user_id}.
# Значит assign обязан вызвать И POST (создать членство), И PATCH с type:2. Раньше он слал
# лишь POST с "type":1 и молча оставлял пользователя участником.
#
# Тест стабит kaiten.sh (логирует вызовы, отдаёт валидный JSON) и проверяет последовательность.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CARDS_SH="$SCRIPT_DIR/../integrations/kaiten/scripts/kaiten-cards.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/calls.log"
FAILS=0

# Копия kaiten-cards.sh рядом со стаб-kaiten.sh: kaiten-cards.sh зовёт "$SCRIPT_DIR/kaiten.sh",
# поэтому стаб должен лежать в той же директории, что и копия.
cp "$CARDS_SH" "$TMP/kaiten-cards.sh"
cat > "$TMP/kaiten.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LOG"
printf '{"id":1,"type":2}\n'
STUB
chmod +x "$TMP/kaiten.sh" "$TMP/kaiten-cards.sh"

check() { # <desc> <extended-regex>: лог обязан содержать
  if grep -Eq "$2" "$LOG"; then
    echo "ok   $1"
  else
    echo "FAIL $1"; echo "     ожидали вызов: $2"; echo "     фактические вызовы:"; sed 's/^/       /' "$LOG"
    FAILS=$((FAILS + 1))
  fi
}

: > "$LOG"
"$TMP/kaiten-cards.sh" assign 111 222 >/dev/null 2>&1

check "assign создаёт членство (POST /cards/111/members)" '^POST /cards/111/members'
check "assign поднимает роль до ответственного (PATCH .../members/222 type:2)" \
      '^PATCH /cards/111/members/222 .*"type": *2'

echo "-----"
if [ "$FAILS" -eq 0 ]; then echo "PASS"; else echo "$FAILS fail(s)"; exit 1; fi
