#!/bin/sh
# Run the zen.vim dependency contract tests (see test/api.vim).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
export ZEN_API_OUT="$OUT"
VIM_BIN=${VIM:-vim}
"$VIM_BIN" -u NONE -i NONE -N -es --not-a-term \
    -S "$ROOT/test/api.vim" </dev/null >/dev/null 2>&1 || status=$?
status=${status:-0}
[ -f "$OUT" ] && cat "$OUT"
exit "$status"
