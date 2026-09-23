# goyo.vim — 顶层 Makefile
#
# 目标：
#   make test      使用默认 Vim 运行测试
#   make test-vim  使用 vim 运行测试
#   make test-nvim 使用 nvim 运行测试
#   make tags      重新生成 doc/tags
#   make lint      对 Vim9 源码做基本静态检查
#   make clean     清理生成物

VIM ?= vim
NVIM ?= nvim

.PHONY: all test test-vim test-nvim tags lint clean

all: test

test: test-vim

test-vim:
	@sh test/run.sh vim

test-nvim:
	@sh test/run.sh nvim

tags:
	@$(VIM) -u NONE -i NONE -N -es --not-a-term \
	--cmd 'helptags doc' -c 'qa!' < /dev/null
	@echo "doc/tags updated"

# 基本静态检查：确保源文件可被 Vim 成功加载（编译 Vim9script）。
lint:
	@$(VIM) -u NONE -i NONE -N -es --not-a-term \
	--cmd 'set runtimepath^=.' \
	--cmd 'runtime plugin/goyo.vim' \
	--cmd 'call writefile(["lint-ok"], "/tmp/goyo-lint.txt")' \
	-c 'qa!' < /dev/null
	@echo "lint OK"

clean:
	@rm -f /tmp/goyo-lint.txt
	@echo "clean done"
