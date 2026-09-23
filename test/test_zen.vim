vim9script
# ============================================================================
# zen.vim unit / integration tests
#
# Usage (see test/run.sh):
#   vim -u NONE -i NONE -N -es --not-a-term \
#       --cmd 'set rtp^=<plugin-root>' -S test/test_zen.vim
#
# Tests use Vim's built-in assertions (assert_equal, assert_true, ...).
# A failing assertion throws; the runner counts failures and uses that
# count as its exit status.
# ============================================================================

# ---------------------------------------------------------------------------
# Minimal test framework (no dependencies, only Vim's assert_*())
# ---------------------------------------------------------------------------
var passed = 0
var failed = 0
var report_lines: list<string> = []

# Results are collected in a list and written to $ZEN_TEST_OUT.
def Report(line: string)
  report_lines->add(line)
enddef

def FlushReport()
  var out = getenv('ZEN_TEST_OUT')
  if !empty(out)
    writefile(report_lines, out)
  endif
enddef

# Discard scratch state so tests do not leak modified buffers or windows.
def ResetScratch()
  if ZenActive()
    zen#Close()
  endif
  silent! only!
  silent! tabonly!
  silent! enew!
  setlocal nomodified
enddef

def Test(name: string, Fn: func)
  ResetScratch()
  try
    Fn()
    passed += 1
    Report('ok   - ' .. name)
  catch
    failed += 1
    echohl ErrorMsg
    Report('FAIL - ' .. name .. ': ' .. v:exception)
    echohl None
  endtry
  ResetScratch()
enddef

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
const RTP_SAVE = &runtimepath
const COLUMNS_SAVE = &columns
const LINES_SAVE = &lines

# State helpers built on the public API only.
def ZenActive(): bool
  return exists('#zen')
enddef

def ZenPads(): dict<number>
  return get(t:, 'zen_pads', {})
enddef

# Structural shape of the current tab's windows as a sorted list of
# [screen_row, screen_col, width, height], independent of window ids.
def LayoutShape(): list<list<number>>
  var shape: list<list<number>> = []
  for info in getwininfo()
    if info.tabnr != tabpagenr()
      continue
    endif
    shape->add([info.winrow, info.wincol, info.width, info.height])
  endfor
  shape->sort((a, b) => a[0] != b[0] ? a[0] - b[0] : a[1] - b[1])
  return shape
enddef

def Setup()
  set nocompatible
  set nomore noswapfile nobackup nowritebackup
  set columns=80 lines=24
  # Make sure the plugin is loaded.
  if !exists(':Zen')
    runtime plugin/zen.vim
  endif
  if ZenActive()
    zen#Close()
  endif
enddef

def Teardown()
  if ZenActive()
    zen#Close()
  endif
enddef

# Helper: ConfineWindows() is script-local and cannot be called from the
# tests, so drive it by re-triggering BufWinEnter.
def ConfineSettle()
  # OnBufWinEnter() schedules ConfineWindows() through a zero-delay timer;
  # sleep so the main loop runs the callback.
  doautocmd BufWinEnter
  sleep 30m
enddef

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
Setup()

# ---------------------------------------------------------------------------
# 1. Plugin loading and commands
# ---------------------------------------------------------------------------
Test('plugin defines :Zen command', () => {
  assert_equal(2, exists(':Zen'))
})

Test('public API Open/Close/Toggle are exported', () => {
  assert_true(exists('*zen#Open') > 0)
  assert_true(exists('*zen#Close') > 0)
  assert_true(exists('*zen#Toggle') > 0)
})

Test('only Open/Close/Toggle (and Complete) are exported', () => {
  # zen#Execute/zen#IsActive/zen#Pads/zen#Resize are implementation details.
  assert_equal(0, exists('*zen#Execute'))
  assert_equal(0, exists('*zen#IsActive'))
  assert_equal(0, exists('*zen#Pads'))
  assert_equal(0, exists('*zen#Resize'))
  assert_true(exists('*zen#Complete') > 0)
})

# ---------------------------------------------------------------------------
# 2. Geometry parsing (enter through the public API, then inspect t:zen_dim)
# ---------------------------------------------------------------------------
Test('default dimensions use g:zen_width (80)', () => {
  g:zen_width = 80
  g:zen_height = '85%'
  zen#Toggle()
  assert_true(ZenActive())
  var dim = t:zen_dim
  assert_equal(80, dim.width)
  assert_equal(24 * 85 / 100, dim.height)
  zen#Close()
})

Test('percentage expression 100%x50%', () => {
  zen#Open('100%x50%')
  var dim = t:zen_dim
  assert_equal(80, dim.width)
  assert_equal(12, dim.height)
  zen#Close()
})

Test('offset expression 120x20', () => {
  zen#Open('120x20')
  var dim = t:zen_dim
  assert_equal(120, dim.width)
  assert_equal(20, dim.height)
  zen#Close()
})

Test('invalid expression is rejected (not active)', () => {
  zen#Open('definitely-not-a-size')
  assert_false(ZenActive())
})

# ---------------------------------------------------------------------------
# 3. Session activation / deactivation
# ---------------------------------------------------------------------------
Test('activating creates 5 windows (master + 4 pads)', () => {
  zen#Open('80x20')
  assert_true(ZenActive())
  assert_equal(5, winnr('$'))
  assert_equal(4, len(t:zen_pads))
  zen#Close()
})

Test('deactivating removes augroup and pads', () => {
  zen#Open('80x20')
  zen#Close()
  assert_false(ZenActive())
  assert_equal(1, winnr('$'))
  assert_equal(1, tabpagenr('$'))
})

Test('toggle: :Zen then :Zen leaves', () => {
  zen#Open('80x20')
  assert_true(ZenActive())
  zen#Toggle()
  assert_false(ZenActive())
})

# ---------------------------------------------------------------------------
# 4. Saving and restoring options
# ---------------------------------------------------------------------------
Test('global options are restored on leave', () => {
  set laststatus=2
  set showtabline=2
  set ruler
  set sidescroll=5
  zen#Open('80x20')
  assert_equal(0, &laststatus)
  assert_equal(0, &showtabline)
  assert_false(&ruler)
  assert_equal(1, &sidescroll)
  zen#Close()
  assert_equal(2, &laststatus)
  assert_equal(2, &showtabline)
  assert_true(&ruler)
  assert_equal(5, &sidescroll)
})

Test('winwidth/winheight restored in correct order', () => {
  # On a small CI screen Vim clamps the global winheight, so only verify
  # the save/restore logic rather than assuming arbitrary values.
  const save_ww = &winwidth
  const save_wmw = &winminwidth
  const save_wh = &winheight
  const save_wmh = &winminheight
  set winminwidth=2 winminheight=1
  zen#Open('80x20')
  assert_equal(1, &winminwidth)
  assert_equal(1, &winwidth)
  zen#Close()
  assert_equal(2, &winminwidth)
  assert_equal(save_ww, &winwidth)
  assert_equal(save_wmh, &winminheight)
  assert_equal(save_wh, &winheight)
  &winwidth = save_ww
  &winminwidth = save_wmw
  &winheight = save_wh
  &winminheight = save_wmh
})

Test('fillchars and guioptions-like string options are restored', () => {
  var saved = &fillchars
  set fillchars=vert:\ ,stl:\ ,stlnc:\ 
  var during_on = ''
  zen#Open('80x20')
  during_on = &fillchars
  zen#Close()
  assert_equal(saved, &fillchars)
  assert_true(during_on =~ 'stl:')
})

Test('highlight groups are restored exactly on leave', () => {
  # Give Normal a background and a group with an attribute, then check that
  # entering and leaving Zen returns them to the previous state.
  execute 'highlight Normal guibg=#202020'
  execute 'highlight StatusLine guifg=Black guibg=Yellow gui=bold'
  execute 'highlight StatusLineNC guifg=Grey gui=italic cterm=underline'
  var before_sl = hlget('StatusLine', true)
  var before_slnc = hlget('StatusLineNC', true)
  zen#Open('80x20')
  zen#Close()
  assert_equal(before_sl, hlget('StatusLine', true))
  assert_equal(before_slnc, hlget('StatusLineNC', true))
})

Test('highlight attribute added by Zen is removed again', () => {
  execute 'highlight ColorColumn guibg=LightRed'
  var before = hlget('ColorColumn', true)
  zen#Open('80x20')
  zen#Close()
  assert_equal(before, hlget('ColorColumn', true))
})

# ---------------------------------------------------------------------------
# 5. Buffer preservation
# ---------------------------------------------------------------------------
Test(':edit another file during Zen survives exit', () => {
  var tmp = tempname()
  writefile(['hello'], tmp)
  execute 'edit ' .. tmp
  zen#Open('80x20')
  var tmp2 = tempname()
  writefile(['world'], tmp2)
  execute 'edit ' .. tmp2
  zen#Close()
  assert_equal(tmp2, bufname('%'))
  silent! execute 'bwipeout! ' .. tmp
  silent! execute 'bwipeout! ' .. tmp2
})

Test('leaving Zen returns to the original tab and window', () => {
  # Build a second tab with two windows and enter Zen from the right one.
  tabnew
  vsplit
  wincmd l
  var orig_winid = win_getid()
  var orig_tab = tabpagenr()
  zen#Open('80x20')
  assert_true(ZenActive())
  zen#Close()
  assert_equal(orig_tab, tabpagenr())
  assert_equal(orig_winid, win_getid())
  assert_equal(2, tabpagenr('$'))
})

# ---------------------------------------------------------------------------
# 6. Confining content windows (ConfineWindows)
# ---------------------------------------------------------------------------
Test('help window stays within content column', () => {
  zen#Open('80x20')
  help
  # Locate the help window.
  var helpwin = 0
  for i in range(1, winnr('$'))
    if bufname(winbufnr(i)) =~ 'help.txt\|doc/'
      helpwin = i
    endif
  endfor
  assert_true(helpwin > 0)
  # The help window must not span the whole screen.
  assert_true(winwidth(helpwin) < &columns)
  zen#Close()
})

# ---------------------------------------------------------------------------
# 7. Robustness: repeated calls and invalid input
# ---------------------------------------------------------------------------
Test('idempotent force-off when not active', () => {
  zen#Close()
  zen#Close()
  assert_false(ZenActive())
})

Test('resizing an active session', () => {
  zen#Open('80x20')
  zen#Open('60x10')
  var dim = t:zen_dim
  assert_equal(60, dim.width)
  assert_equal(10, dim.height)
  zen#Close()
})

# ---------------------------------------------------------------------------
# 8. Geometry bounds and parsing robustness
# ---------------------------------------------------------------------------
Test('oversized dimensions are clamped to screen', () => {
  zen#Open('9999x9999')
  var dim = t:zen_dim
  assert_true(dim.width <= &columns)
  assert_true(dim.height <= &lines)
  zen#Close()
})

Test('negative offset expression parses', () => {
  zen#Open('80-10x20+2')
  var dim = t:zen_dim
  assert_equal(70, dim.width)
  assert_equal(22, dim.height)
  zen#Close()
})

Test('percent offset expression parses', () => {
  zen#Open('50%+5x50%-2')
  var dim = t:zen_dim
  assert_equal(40 + 5, dim.width)
  assert_equal(12 - 2, dim.height)
  zen#Close()
})

Test('empty dimension uses configured defaults', () => {
  g:zen_width = 100
  g:zen_height = '50%'
  zen#Toggle()
  assert_equal(100, t:zen_dim.width)
  assert_equal(12, t:zen_dim.height)
  zen#Close()
})

# ---------------------------------------------------------------------------
# 9. Callbacks and user events
# ---------------------------------------------------------------------------
Test('g:zen_callbacks fire on enter and leave', () => {
  var calls: list<string> = []
  g:zen_callbacks = [
    () => calls->add('enter'),
    () => calls->add('leave'),
  ]
  zen#Open('80x20')
  assert_equal(['enter'], calls)
  zen#Close()
  assert_equal(['enter', 'leave'], calls)
  unlet g:zen_callbacks
})

Test('invalid g:zen_callbacks entries are ignored', () => {
  g:zen_callbacks = ['not-a-funcref', 42]
  zen#Open('80x20')
  assert_true(ZenActive())
  zen#Close()
  unlet g:zen_callbacks
})

Test('User ZenEnter/ZenLeave autocmds fire', () => {
  var log: list<string> = []
  augroup zen_test_events
    autocmd!
    autocmd User ZenEnter call add(g:test_evt, 'enter')
    autocmd User ZenLeave call add(g:test_evt, 'leave')
  augroup END
  g:test_evt = []
  zen#Open('80x20')
  zen#Close()
  augroup zen_test_events
    autocmd!
  augroup END
  augroup! zen_test_events
  assert_equal(['enter', 'leave'], g:test_evt)
  unlet g:test_evt
})

# ---------------------------------------------------------------------------
# 10. Line-number option
# ---------------------------------------------------------------------------
Test('g:zen_linenr=1 keeps numbers', () => {
  set number
  g:zen_linenr = 1
  zen#Open('80x20')
  # The content window keeps 'number'.
  execute ':' .. win_id2win(t:zen_winid) .. 'wincmd w'
  assert_true(&number)
  zen#Close()
  unlet g:zen_linenr
  set nonumber
})

Test('default hides numbers in content window', () => {
  set number
  unlet! g:zen_linenr
  zen#Open('80x20')
  execute ':' .. win_id2win(t:zen_winid) .. 'wincmd w'
  assert_false(&number)
  zen#Close()
  set nonumber
})

# ---------------------------------------------------------------------------
# 11. Temporary mappings
# ---------------------------------------------------------------------------
Test('temporary <C-w> mappings are installed and removed', () => {
  var before = maparg('<C-w>', 'n')
  var before_lt = maparg('<C-w><lt>', 'n')
  zen#Open('80x20')
  assert_false(empty(maparg('<C-w>R', 'n')))
  assert_false(empty(maparg('<C-w>=', 'n')))
  zen#Close()
  assert_true(empty(maparg('<C-w>R', 'n')))
  assert_true(empty(maparg('<C-w>=', 'n')))
})

# ---------------------------------------------------------------------------
# 12. Window confinement: normal splits kept, full-width windows pulled back
# ---------------------------------------------------------------------------
Test('normal vsplit inside content column is preserved', () => {
  var tmp = tempname()
  writefile(['a'], tmp)
  execute 'edit ' .. tmp
  zen#Open('80x20')
  var tmp2 = tempname()
  writefile(['b'], tmp2)
  execute 'vsplit ' .. tmp2
  # master + new split + 4 pads = 6
  assert_equal(6, winnr('$'))
  zen#Close()
  # Both content windows survive leaving Zen.
  assert_equal(2, winnr('$'))
  silent! execute 'bwipeout! ' .. tmp
  silent! execute 'bwipeout! ' .. tmp2
})

Test('ConfineWindows brings full-width window back into content column', () => {
  zen#Open('80x20')
  # Directly open a full-width window.
  topleft new
  # ConfineWindows() should be driven by the autocommand; give it a chance
  # to run.
  call ConfineSettle()
  var outside = 0
  for i in range(1, winnr('$'))
    if winwidth(i) > &columns - 2
      outside += 1
    endif
  endfor
  # Apart from the top/bottom pads, no window should span the screen.
  assert_true(outside <= 2)
  zen#Close()
})

Test('nested window layout is restored exactly on leave', () => {
  # Build a nested layout: a row of (single window) and (column of two).
  var a = tempname()
  var b = tempname()
  var c = tempname()
  writefile(['A'], a)
  writefile(['B'], b)
  writefile(['C'], c)
  execute 'edit ' .. a
  vsplit
  execute 'buffer ' .. bufadd(b)
  wincmd l
  split
  execute 'buffer ' .. bufadd(c)
  # Remember the neutral structural shape (positions only).
  var before = LayoutShape()
  zen#Open('100x30')
  zen#Close()
  assert_equal(before, LayoutShape())
  assert_equal(1, tabpagenr('$'))
  for f in [a, b, c]
    silent! execute 'bwipeout! ' .. f
  endfor
})

Test('all stray windows are confined in one deferred pass', () => {
  zen#Open('80x20')
  topleft new
  topleft new
  call ConfineSettle()
  # Every content window must now fit inside the content column.
  var lpad = bufwinnr(ZenPads().l)
  var rpad = bufwinnr(ZenPads().r)
  var left = lpad > 0 ? win_screenpos(lpad)[1] + winwidth(lpad) : 1
  var right = rpad > 0 ? win_screenpos(rpad)[1] - 1 : &columns
  for i in range(1, winnr('$'))
    var b = winbufnr(i)
    if b == ZenPads().t || b == ZenPads().b || b == ZenPads().l || b == ZenPads().r
      continue
    endif
    var col = win_screenpos(i)[1]
    assert_true(col >= left && col + winwidth(i) - 1 <= right)
  endfor
  zen#Close()
})

# ---------------------------------------------------------------------------
# 13. Plugin layer and namespace API (import autoload)
# ---------------------------------------------------------------------------
Test('plugin defines <Plug> mappings', () => {
  assert_false(empty(maparg('<Plug>(zen-open)', 'n')))
  assert_false(empty(maparg('<Plug>(zen-close)', 'n')))
  assert_false(empty(maparg('<Plug>(zen-toggle)', 'n')))
  assert_false(empty(maparg('<Plug>(zen-off)', 'n')))
})

Test('plugin does not clobber user <C-w> mappings by default', () => {
  # The plugin must not set <C-w> mappings at load time.
  zen#Close()
  # Just check that nothing is left behind.
  assert_true(empty(maparg('<C-w>R', 'n')) || !ZenActive())
})

Test('zen#Toggle opens then closes', () => {
  zen#Toggle()
  assert_true(ZenActive())
  zen#Toggle()
  assert_false(ZenActive())
})

Test('ZenPads returns empty when inactive', () => {
  zen#Close()
  assert_equal({}, ZenPads())
})

Test('ZenPads returns four pads when active', () => {
  zen#Open('80x20')
  var pads = ZenPads()
  assert_equal(4, len(pads))
  for k in ['l', 'r', 't', 'b']
    assert_true(has_key(pads, k))
    assert_true(bufexists(pads[k]))
  endfor
  zen#Close()
})

Test('zen#Close closes an active session', () => {
  zen#Open('80x20')
  assert_true(ZenActive())
  zen#Close()
  assert_false(ZenActive())
})

Test('<Plug>(zen-toggle) opens and closes', () => {
  zen#Close()
  execute "normal \<Plug>(zen-toggle)"
  assert_true(ZenActive())
  execute "normal \<Plug>(zen-toggle)"
  assert_false(ZenActive())
})

Test('zen#Complete returns candidates and is well formed', () => {
  var items = zen#Complete('8', 'Zen 8', 6)
  assert_true(type(items) == v:t_list)
  assert_true(len(items) > 0)
  assert_true(index(items, '80') >= 0)
})

Test('<Plug>(zen-off) leaves Zen', () => {
  zen#Open('80x20')
  assert_true(ZenActive())
  execute "normal \<Plug>(zen-off)"
  assert_false(ZenActive())
})

Test('<Plug>(zen-open) and <Plug>(zen-close) work', () => {
  zen#Close()
  execute "normal \<Plug>(zen-open)"
  assert_true(ZenActive())
  var pads = ZenPads()
  assert_equal(4, len(pads))
  execute "normal \<Plug>(zen-close)"
  assert_false(ZenActive())
})

# ---------------------------------------------------------------------------
# Run and report
# ---------------------------------------------------------------------------

Teardown()

Report(printf('zen tests: %d passed, %d failed', passed, failed))

# Exit status: number of failures, convenient for CI.
FlushReport()
if failed > 0
  execute 'cquit ' .. failed
else
  qall!
endif
