#!/bin/sh
# Run the zen.vim micro-benchmarks with a Vim that supports Vim9script.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
export ZEN_BENCH_OUT="$OUT"
VIM_BIN=${VIM:-vim}
"$VIM_BIN" -u NONE -i NONE -N -es --not-a-term \
    --cmd "set runtimepath^=$ROOT" \
    --cmd 'runtime plugin/zen.vim' \
    --cmd "source $ROOT/test/bench.vim" \
    -c 'qa!' </dev/null >/dev/null 2>&1 || true
[ -f "$OUT" ] && cat "$OUT"
