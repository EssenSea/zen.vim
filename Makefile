# goyo.vim — Makefile
#
# Common tasks.  The test suite uses Vim's built-in assert_*() functions and
# needs Vim 9.1.0000+ with +vim9script.  See CONTRIBUTING.md.

VIM    ?= vim
NVIM   ?= nvim
PREFIX ?= $(HOME)/.vim

.PHONY: all test test-vim test-nvim lint tags conformance check clean install

all: check

test: test-vim

test-vim:
	@sh test/run.sh vim

test-nvim:
	@sh test/run.sh nvim

# Regenerate the help tags.  Run this after changing doc/goyo.txt.
tags:
	@$(VIM) -u NONE -i NONE -N -es --not-a-term \
	--cmd 'helptags doc' -c 'qa!' < /dev/null
	@echo "doc/tags updated"

# Load the plugin in a clean Vim to catch Vim9script compile errors.
lint:
	@$(VIM) -u NONE -i NONE -N -es --not-a-term \
	--cmd 'set runtimepath^=.' \
	--cmd 'runtime plugin/goyo.vim' \
	--cmd 'call writefile(["lint-ok"], "/tmp/goyo-lint.txt")' \
	-c 'qa!' < /dev/null
	@test "$$(cat /tmp/goyo-lint.txt)" = "lint-ok" && echo "lint OK"

# Verify the package structure and style conventions.
conformance:
	@sh test/conformance.sh

check: lint conformance test-vim

# Install into a pack directory (see :help package-create).
install:
	@mkdir -p "$(PREFIX)/pack/goyo/start/goyo"
	@cp -R autoload doc lang plugin "$(PREFIX)/pack/goyo/start/goyo/"
	@echo "installed to $(PREFIX)/pack/goyo/start/goyo"

clean:
	@rm -f /tmp/goyo-lint.txt
	@echo "clean done"
