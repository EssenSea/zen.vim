#!/bin/sh
# ============================================================================
# goyo.vim package-convention conformance check
#
# Verifies the structural and stylistic rules described in
#   :help package-create
#   :help help-writing
#   :help vim9-namespace
# and the layout used by Vim's bundled plugins.
#
# Exit status: 0 when everything conforms, 1 otherwise.
# ============================================================================
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
fail=0

ok()   { printf 'PASS  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }

check() { # description, shell command
  if eval "$2"; then ok "$1"; else bad "$1"; fi
}

check "package layout (plugin/autoload/doc/tags)" \
  "[ -f plugin/goyo.vim ] && [ -f autoload/goyo.vim ] && [ -f doc/goyo.txt ] && [ -f doc/goyo-internals.txt ] && [ -s doc/tags ]"

check "plugin is Vim9script" \
  "head -1 plugin/goyo.vim | grep -q '^vim9script'"

check "autoload is Vim9script" \
  "head -1 autoload/goyo.vim | grep -q '^vim9script'"

check "plugin loads the implementation with import autoload" \
  "grep -q \"import autoload '\.\./autoload/goyo\.vim'\" plugin/goyo.vim"

check "plugin avoids legacy goyo# calls (completion excepted)" \
  "! grep -v '^[[:space:]]*#' plugin/goyo.vim | grep -v 'complete=customlist' | grep -q 'goyo#'"

check "autoload exposes a typed API" \
  "grep -q 'export def Execute(bang: bool, dim: string)' autoload/goyo.vim"

check "help first line follows help-writing" \
  "head -1 doc/goyo.txt | grep -qP '^\\*goyo\\.txt\\*\tFor Vim version'"

check "help has the standard modeline" \
  "tail -1 doc/goyo.txt | grep -q 'vim:tw=78:ts=8:noet:ft=help:norl:'"

check "scripts have the editor modeline" \
  "tail -1 autoload/goyo.vim | grep -q 'vim: ts=8 sts=2 sw=2 et:'"

check "messages are translatable and catalogues exist" \
  "grep -q gettext autoload/goyo.vim && [ -f lang/goyo.pot ] && [ -f lang/en/LC_MESSAGES/goyo.mo ]"

check "Makefile provides check, install and bench targets" \
  "grep -q '^check:' Makefile && grep -q '^install:' Makefile && grep -q '^bench:' Makefile"

check "project metadata present" \
  "[ -f README.md ] && [ -f CONTRIBUTING.md ] && [ -f CHANGELOG.md ] && [ -f LICENSE ] && [ -f .editorconfig ]"

check "benchmark tooling present" \
  "[ -f test/bench.vim ] && [ -f test/bench.sh ]"

check "all source comments are in English" \
  "! grep -rlP '[\x{4e00}-\x{9fff}]' plugin autoload test >/dev/null 2>&1"

check "help text fits in 78 columns" \
  "python3 -c \"
import glob
ok = True
for fn in glob.glob('doc/*.txt'):
  for line in open(fn):
    col = 0
    for ch in line.rstrip('\\n'):
        col = (col // 8 + 1) * 8 if ch == '\t' else col + 1
    if col > 78:
        ok = False
raise SystemExit(0 if ok else 1)\""

if [ "$fail" -eq 0 ]; then
  printf '\nconformance checks: all passed\n'
else
  printf '\nconformance checks: %d failed\n' "$fail"
fi
exit "$fail"
