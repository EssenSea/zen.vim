#!/bin/sh
# ============================================================================
# goyo.vim test runner
#
# Usage:
#   sh test/run.sh [vim|nvim]       (default: vim)
#
# Exit status:
#   0        all tests passed
#   1..N     number of failing tests
#   2        the chosen editor cannot run Vim9script tests
#
# The plugin is written in Vim9script and needs Vim 9.1.0000+.  If the chosen
# editor cannot execute Vim9script, the runner reports this and exits.
# ============================================================================
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENGINE=${1:-vim}
OUT=$(mktemp)
PROBE=$OUT.probe.$$
trap 'rm -f "$OUT" "$PROBE" "$OUT.probe"' EXIT INT HUP TERM

export GOYO_TEST_OUT="$OUT"

# Vim9script capability probe: the script writes its result and quits.
cat > "$PROBE" <<PEOF
vim9script
def Probe(): number
  return 42
enddef
writefile([string(Probe())], '$OUT.probe')
qall!
PEOF

# probe_engine <editor> [flags...]
probe_engine() {
  _bin=$1
  shift
  rm -f "$OUT.probe"
  "$_bin" "$@" -u NONE -i NONE -N -es --not-a-term \
      -S "$PROBE" </dev/null >/dev/null 2>&1 || true
  if [ "$(cat "$OUT.probe" 2>/dev/null)" = "42" ]; then
    rm -f "$OUT.probe"
    return 0
  fi
  rm -f "$OUT.probe"
  return 1
}

status=0
case "$ENGINE" in
  vim)
    VIM_BIN=${VIM:-vim}
    if ! probe_engine "$VIM_BIN"; then
      echo "vim: this build does not support Vim9script; cannot run tests." >&2
      exit 2
    fi
    "$VIM_BIN" -u NONE -i NONE -N -es --not-a-term \
        --cmd "set runtimepath^=$ROOT" \
        -S "$ROOT/test/test_goyo.vim" </dev/null || status=$?
    ;;
  nvim)
    NVIM_BIN=${NVIM:-nvim}
    if ! probe_engine "$NVIM_BIN" --headless; then
      echo "SKIP - nvim: this Neovim build does not fully support Vim9script"
      echo "       Run 'make test-vim' with Vim 9 instead." >&2
      exit 0
    fi
    "$NVIM_BIN" --headless -u NONE -i NONE \
        --cmd "set runtimepath^=$ROOT" \
        -S "$ROOT/test/test_goyo.vim" </dev/null || status=$?
    ;;
  *)
    echo "usage: $0 [vim|nvim]" >&2
    exit 2
    ;;
esac

[ -f "$OUT" ] && cat "$OUT"
exit "$status"
