#!/bin/sh
# ============================================================================
# goyo.vim 测试运行器
#
# 用法：
#   sh test/run.sh [vim|nvim]       默认 vim
#
# 退出码：0 = 全部通过；非 0 = 失败（值 = 失败用例数）。
#
# 本插件使用 Vim9script，需要支持 +vim9script 的 Vim（9.1.0000+）。
# 若所选编辑器不能正确执行 Vim9script，运行器会给出提示并以 2 退出。
# ============================================================================
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENGINE=${1:-vim}
OUT=$(mktemp)
PROBE=$(mktemp --suffix=.vim)
trap 'rm -f "$OUT" "$PROBE"' EXIT

export GOYO_TEST_OUT="$OUT"

# 生成 Vim9script 能力探测文件；文件自身写出结果后退出。
cat > "$PROBE" <<PEOF
vim9script
def Probe(): number
  return 42
enddef
writefile([string(Probe())], '$OUT.probe')
qall!
PEOF

probe_engine() { # $1 = editor binary ; $2... = extra flags
  local bin=$1; shift
  rm -f "$OUT.probe"
  "$bin" "$@" -u NONE -i NONE -N -es --not-a-term \
      -S "$PROBE" < /dev/null > /dev/null 2>&1 || true
  if [ "$(cat "$OUT.probe" 2>/dev/null)" = "42" ]; then
    rm -f "$OUT.probe"; return 0
  fi
  rm -f "$OUT.probe"; return 1
}

status=0
case "$ENGINE" in
  vim)
    VIM_BIN=${VIM:-vim}
    if ! probe_engine "$VIM_BIN" -es --not-a-term; then
      echo "vim: this build does not support Vim9script; cannot run tests." >&2
      exit 2
    fi
    "$VIM_BIN" -u NONE -i NONE -N -es --not-a-term \
        --cmd "set runtimepath^=$ROOT" \
        -S "$ROOT/test/test_goyo.vim" < /dev/null || status=$?
    ;;
  nvim)
    NVIM_BIN=${NVIM:-nvim}
    if ! probe_engine "$NVIM_BIN" --headless; then
      echo "SKIP - nvim: this Neovim build does not fully support Vim9script"
      echo "       Please run 'make test-vim' with Vim 9 instead." >&2
      exit 0
    fi
    "$NVIM_BIN" --headless -u NONE -i NONE \
        --cmd "set runtimepath^=$ROOT" \
        -S "$ROOT/test/test_goyo.vim" < /dev/null || status=$?
    ;;
  *)
    echo "usage: $0 [vim|nvim]" >&2
    exit 2
    ;;
esac

[ -f "$OUT" ] && cat "$OUT"
exit "$status"
