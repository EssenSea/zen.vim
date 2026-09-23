# zen.vim — Makefile
#
# LLM POWERED: developed with assistance from DeepSeek V4.1 and the DeepSeek
# harness.
#
# Common tasks.  The test suite uses Vim's built-in assert_*() functions and
# needs Vim 9.1.1652+ with +vim9script.  See CONTRIBUTING.md.

VIM    ?= vim
NVIM   ?= nvim
PREFIX ?= $(HOME)/.vim

.PHONY: all test test-vim test-nvim lint tags conformance api pty check clean install bench ci

all: check

test: test-vim

test-vim:
	@sh test/run.sh vim

test-nvim:
	@sh test/run.sh nvim

# Regenerate the help tags.  Run this after changing doc/zen.txt.
tags:
	@$(VIM) -u NONE -i NONE -N -es --not-a-term \
	--cmd 'helptags doc' -c 'qa!' < /dev/null
	@echo "doc/tags updated"

# Load the plugin in a clean Vim to catch Vim9script compile errors.
lint:
	@$(VIM) -u NONE -i NONE -N -es --not-a-term \
	--cmd 'set runtimepath^=.' \
	--cmd 'runtime plugin/zen.vim' \
	--cmd 'call writefile(["lint-ok"], "/tmp/zen-lint.txt")' \
	-c 'qa!' < /dev/null
	@test "$$(cat /tmp/zen-lint.txt)" = "lint-ok" && echo "lint OK"

# Verify the package structure and style conventions.
conformance:
	@sh test/conformance.sh

# Verify the Vim built-ins and events the plugin depends on, so a change
# in Vim surfaces here instead of at runtime.
api:
	@sh test/api.sh

# PTY checks: run Vim under a real pseudo terminal for the parts that
# need a screen (layout, WinResized, the pad bounce, typed commands).
pty:
	@sh test/pty.sh

check: lint conformance api test-vim pty

# Install into a pack directory (see :help package-create).
install:
	@mkdir -p "$(PREFIX)/pack/zen/start/zen"
	@cp -R autoload doc lang plugin "$(PREFIX)/pack/zen/start/zen/"
	@echo "installed to $(PREFIX)/pack/zen/start/zen"

# Run the micro-benchmarks (reports median/min/max per operation).
bench:
	@sh test/bench.sh

# Run the same checks as CI (requires Vim 9.1.1652+ in $PATH).
ci:
	@sh ci.sh

clean:
	@rm -f /tmp/zen-lint.txt
	@echo "clean done"
