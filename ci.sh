#!/bin/sh
# ============================================================================
# LLM POWERED
#
# Developed with assistance from DeepSeek V4.1 and the DeepSeek harness.
# ============================================================================
# zen.vim local CI
#
# Runs the same checks as .github/workflows/ci.yml against the Vim found in
# $PATH (which must be Vim 9.1.0000 or newer).
#
# Usage:  sh ci.sh
# ============================================================================
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

VIM_BIN=${VIM:-vim}
version=$("$VIM_BIN" --version | head -1)
case "$version" in
  *"Vi IMproved"*) ;;
  *) echo "not Vim: $version" >&2; exit 2 ;;
esac
echo "== $version =="

# Only Vim 9.1+ is supported.
if ! "$VIM_BIN" -u NONE -i NONE -N -es --not-a-term \
      --cmd 'if !has("patch-9.1.0000") | cquit 1 | endif' -c 'qa!' </dev/null >/dev/null 2>&1; then
  echo "zen.vim requires Vim 9.1.0000 or newer" >&2
  exit 2
fi

echo "== conformance =="
sh test/conformance.sh

echo "== lint =="
make VIM="$VIM_BIN" lint

echo "== api contract =="
sh test/api.sh

echo "== test =="
sh test/run.sh vim

echo "== pty =="
sh test/pty.sh

echo "== bench (informational) =="
sh test/bench.sh

echo "== all CI checks passed =="
