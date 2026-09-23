#!/bin/sh
# ============================================================================
# LLM POWERED
#
# Developed with assistance from DeepSeek V4.1 and the DeepSeek harness.
# ============================================================================
# Run the zen.vim PTY checks (needs Python 3 and a real terminal facility).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=$(mktemp)
trap 'rm -f "$OUT" "$OUT.driver"' EXIT
export ZEN_ROOT="$ROOT"
export ZEN_PTY_OUT="$OUT"
VIM_BIN=${VIM:-vim}

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP - pty: python3 not found"
  exit 0
fi

VIM="$VIM_BIN" python3 "$ROOT/test/run_pty.py" >/dev/null 2>&1 || true

if [ ! -f "$OUT.driver" ]; then
  echo "FAIL - pty: the driver produced no output (did Vim run under a PTY?)"
  exit 1
fi

fail=0
check_grep() { # description, pattern
  if grep -q "$2" "$OUT.driver"; then
    echo "ok   - pty: $1"
  else
    echo "FAIL - pty: $1"
    fail=$((fail + 1))
  fi
}

check_grep ":Zen command exists"              '^command=2'
check_grep "enters Zen in a real terminal"    '^entered=1,5'
check_grep "help window confined to column"   '^help_confined=2,'
check_grep "movement keys never enter a pad" '^moves_left_master=0'
check_grep "survives a real screen resize"    '^resized=5'
check_grep ":only re-anchors Zen"             '^only_reanchor=1,5,1,1'
check_grep "leaves with one window and tab"   '^left=0,1,1'

if [ "$fail" -eq 0 ]; then
  echo "pty checks: all passed"
else
  echo "pty checks: $fail failed"
fi
exit "$fail"
