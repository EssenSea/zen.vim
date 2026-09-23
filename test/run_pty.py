#!/usr/bin/env python3
# ============================================================================
# LLM POWERED
#
# Developed with assistance from DeepSeek V4.1 and the DeepSeek harness.
# ============================================================================
# zen.vim PTY check
#
# Runs Vim under a real pseudo terminal so the parts that need a screen are
# actually exercised: window layout, WinResized, the pad bounce, and the
# :Zen command typed as a user would.  `vim -es` cannot cover these because
# it has no terminal.
#
# It writes one "key=value" line per check to $ZEN_PTY_OUT and exits 0.
# test/pty.sh turns those into pass/fail.
# ============================================================================
import os
import pty
import select
import struct
import sys
import time
import fcntl
import termios
import tempfile

VIM = os.environ.get('VIM', 'vim')
ROOT = os.environ['ZEN_ROOT']
OUT = os.environ['ZEN_PTY_OUT']
COLS, ROWS = 100, 30
LOG = OUT + '.driver'

DRIVER = r'''
set nocompatible
set nomore noswapfile
let s:log = []
runtime plugin/zen.vim
call add(s:log, 'command=' . exists(':Zen'))

" Enter Zen in a real terminal.
call zen#Open('60x16')
call add(s:log, 'entered=' . exists('#zen') . ',' . winnr('$'))
redraw

" A full-width help window must be pulled back into the content column, so
" only the top/bottom pads remain full width.
silent! help
sleep 200m
redraw
let s:wide = 0
for i in range(1, winnr('$'))
  if winwidth(i) > 70
    let s:wide += 1
  endif
endfor
call add(s:log, 'help_confined=' . s:wide . ',' . winnr('$'))

" Movement keys must not move the cursor into a pad.
let s:master = winnr()
let s:entered = 0
for s:k in ['h', 'j', 'k', 'l', 't', 'b']
  execute 'normal ' . "\<C-w>" . s:k
  if winnr() != s:master
    let s:entered += 1
  endif
endfor
call add(s:log, 'moves_left_master=' . s:entered)

" A real screen resize exercises WinResized/VimResized.
set columns=90
call add(s:log, 'resized=' . winnr('$'))

" :only must re-anchor rather than leave Zen.
split
let s:target = winbufnr('%')
wincmd o
sleep 200m
let s:allpads = 1
for s:b in values(get(t:, 'zen_pads', {}))
  if bufwinnr(s:b) <= 0
    let s:allpads = 0
  endif
endfor
call add(s:log, 'only_reanchor=' . exists('#zen') . ',' . winnr('$') . ',' . s:allpads . ',' . (s:target == winbufnr('%')))

call zen#Close()
call add(s:log, 'left=' . exists('#zen') . ',' . winnr('$') . ',' . tabpagenr('$'))

call writefile(s:log, %LOG%)
qall!
'''
# --- below: the log path is substituted in main() ---


def set_winsize(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))


def drain(fd, seconds):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                os.read(fd, 4096)
            except OSError:
                break


def main():
    script = tempfile.NamedTemporaryFile('w', suffix='.vim', delete=False)
    script.write(DRIVER.replace('%LOG%', "'" + LOG + "'"))
    script.close()

    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        os.execvp(VIM, [VIM, '-u', 'NONE', '-i', 'NONE', '-N',
                        '--cmd', 'set runtimepath^=' + ROOT,
                        '--cmd', 'set termguicolors',
                        '-S', script.name])
        os._exit(127)

    set_winsize(fd, ROWS, COLS)
    drain(fd, 2.5)

    # Drive a second session purely by keystrokes, like a user.
    os.write(fd, b':Zen 60x16\r')
    drain(fd, 1.0)
    os.write(fd, b':Zen!\r')
    drain(fd, 1.0)
    os.write(fd, b':qa!\r')
    drain(fd, 0.6)

    try:
        os.close(fd)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    os.unlink(script.name)
    return 0


if __name__ == '__main__':
    sys.exit(main())
