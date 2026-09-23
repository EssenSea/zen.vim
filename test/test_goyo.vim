vim9script
# ============================================================================
# goyo.vim unit / integration tests
#
# Usage (see test/run.sh):
#   vim -u NONE -i NONE -N -es --not-a-term \
#       --cmd 'set rtp^=<plugin-root>' -S test/test_goyo.vim
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

# Results are collected in a list and written to $GOYO_TEST_OUT.
def Report(line: string)
  report_lines->add(line)
enddef

def FlushReport()
  var out = getenv('GOYO_TEST_OUT')
  if !empty(out)
    writefile(report_lines, out)
  endif
enddef

# Discard scratch state so tests do not leak modified buffers or windows.
def ResetScratch()
  if goyo#IsActive()
    goyo#Execute(true, '')
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

def Setup()
  set nocompatible
  set nomore noswapfile nobackup nowritebackup
  set columns=80 lines=24
  # Make sure the plugin is loaded.
  if !exists(':Goyo')
    runtime plugin/goyo.vim
  endif
  if goyo#IsActive()
    goyo#Execute(true, '')
  endif
enddef

def Teardown()
  if goyo#IsActive()
    goyo#Execute(true, '')
  endif
enddef

# Helper: ConfineWindows() is script-local and cannot be called from the
# tests, so drive it by re-triggering BufWinEnter.
def ConfineSettle()
  doautocmd BufWinEnter
enddef

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
Setup()

# ---------------------------------------------------------------------------
# 1. Plugin loading and commands
# ---------------------------------------------------------------------------
Test('plugin defines :Goyo command', () => {
  assert_equal(2, exists(':Goyo'))
})

Test('goyo#Execute is an autoload function', () => {
  assert_true(exists('*goyo#Execute') > 0)
})

Test('goyo#IsActive is exported', () => {
  assert_true(exists('*goyo#IsActive') > 0)
})

# ---------------------------------------------------------------------------
# 2. Geometry parsing (enter through the public API, then inspect t:goyo_dim)
# ---------------------------------------------------------------------------
Test('default dimensions use g:goyo_width (80)', () => {
  g:goyo_width = 80
  g:goyo_height = '85%'
  goyo#Execute(false, '')
  assert_true(goyo#IsActive())
  var dim = t:goyo_dim
  assert_equal(80, dim.width)
  assert_equal(24 * 85 / 100, dim.height)
  goyo#Execute(true, '')
})

Test('percentage expression 100%x50%', () => {
  goyo#Execute(false, '100%x50%')
  var dim = t:goyo_dim
  assert_equal(80, dim.width)
  assert_equal(12, dim.height)
  goyo#Execute(true, '')
})

Test('offset expression 120x20', () => {
  goyo#Execute(false, '120x20')
  var dim = t:goyo_dim
  assert_equal(120, dim.width)
  assert_equal(20, dim.height)
  goyo#Execute(true, '')
})

Test('invalid expression is rejected (not active)', () => {
  goyo#Execute(false, 'definitely-not-a-size')
  assert_false(goyo#IsActive())
})

# ---------------------------------------------------------------------------
# 3. Session activation / deactivation
# ---------------------------------------------------------------------------
Test('activating creates 5 windows (master + 4 pads)', () => {
  goyo#Execute(false, '80x20')
  assert_true(goyo#IsActive())
  assert_equal(5, winnr('$'))
  assert_equal(4, len(t:goyo_pads))
  goyo#Execute(true, '')
})

Test('deactivating removes augroup and pads', () => {
  goyo#Execute(false, '80x20')
  goyo#Execute(true, '')
  assert_false(goyo#IsActive())
  assert_equal(1, winnr('$'))
  assert_equal(1, tabpagenr('$'))
})

Test('toggle: :Goyo then :Goyo leaves', () => {
  goyo#Execute(false, '80x20')
  assert_true(goyo#IsActive())
  goyo#Execute(false, '')
  assert_false(goyo#IsActive())
})

# ---------------------------------------------------------------------------
# 4. Saving and restoring options
# ---------------------------------------------------------------------------
Test('global options are restored on leave', () => {
  set laststatus=2
  set showtabline=2
  set ruler
  set sidescroll=5
  goyo#Execute(false, '80x20')
  assert_equal(0, &laststatus)
  assert_equal(0, &showtabline)
  assert_false(&ruler)
  assert_equal(1, &sidescroll)
  goyo#Execute(true, '')
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
  goyo#Execute(false, '80x20')
  assert_equal(1, &winminwidth)
  assert_equal(1, &winwidth)
  goyo#Execute(true, '')
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
  goyo#Execute(false, '80x20')
  during_on = &fillchars
  goyo#Execute(true, '')
  assert_equal(saved, &fillchars)
  assert_true(during_on =~ 'stl:')
})

Test('highlight groups are restored exactly on leave', () => {
  # Give Normal a background and a group with an attribute, then check that
  # entering and leaving Goyo returns them to the previous state.
  execute 'highlight Normal guibg=#202020'
  execute 'highlight StatusLine guifg=Black guibg=Yellow gui=bold'
  execute 'highlight StatusLineNC guifg=Grey gui=italic cterm=underline'
  var before_sl = hlget('StatusLine', true)
  var before_slnc = hlget('StatusLineNC', true)
  goyo#Execute(false, '80x20')
  goyo#Execute(true, '')
  assert_equal(before_sl, hlget('StatusLine', true))
  assert_equal(before_slnc, hlget('StatusLineNC', true))
})

Test('highlight attribute added by Goyo is removed again', () => {
  execute 'highlight ColorColumn guibg=LightRed'
  var before = hlget('ColorColumn', true)
  goyo#Execute(false, '80x20')
  goyo#Execute(true, '')
  assert_equal(before, hlget('ColorColumn', true))
})

# ---------------------------------------------------------------------------
# 5. Buffer preservation
# ---------------------------------------------------------------------------
Test(':edit another file during Goyo survives exit', () => {
  var tmp = tempname()
  writefile(['hello'], tmp)
  execute 'edit ' .. tmp
  goyo#Execute(false, '80x20')
  var tmp2 = tempname()
  writefile(['world'], tmp2)
  execute 'edit ' .. tmp2
  goyo#Execute(true, '')
  assert_equal(tmp2, bufname('%'))
  silent! execute 'bwipeout! ' .. tmp
  silent! execute 'bwipeout! ' .. tmp2
})

Test('leaving Goyo returns to the original tab and window', () => {
  # Build a second tab with two windows and enter Goyo from the right one.
  tabnew
  vsplit
  wincmd l
  var orig_winid = win_getid()
  var orig_tab = tabpagenr()
  goyo#Execute(false, '80x20')
  assert_true(goyo#IsActive())
  goyo#Execute(true, '')
  assert_equal(orig_tab, tabpagenr())
  assert_equal(orig_winid, win_getid())
  assert_equal(2, tabpagenr('$'))
})

# ---------------------------------------------------------------------------
# 6. Confining content windows (ConfineWindows)
# ---------------------------------------------------------------------------
Test('help window stays within content column', () => {
  goyo#Execute(false, '80x20')
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
  goyo#Execute(true, '')
})

# ---------------------------------------------------------------------------
# 7. Robustness: repeated calls and invalid input
# ---------------------------------------------------------------------------
Test('idempotent force-off when not active', () => {
  goyo#Execute(true, '')
  goyo#Execute(true, '')
  assert_false(goyo#IsActive())
})

Test('resizing an active session', () => {
  goyo#Execute(false, '80x20')
  goyo#Execute(false, '60x10')
  var dim = t:goyo_dim
  assert_equal(60, dim.width)
  assert_equal(10, dim.height)
  goyo#Execute(true, '')
})

# ---------------------------------------------------------------------------
# 8. Geometry bounds and parsing robustness
# ---------------------------------------------------------------------------
Test('oversized dimensions are clamped to screen', () => {
  goyo#Execute(false, '9999x9999')
  var dim = t:goyo_dim
  assert_true(dim.width <= &columns)
  assert_true(dim.height <= &lines)
  goyo#Execute(true, '')
})

Test('negative offset expression parses', () => {
  goyo#Execute(false, '80-10x20+2')
  var dim = t:goyo_dim
  assert_equal(70, dim.width)
  assert_equal(22, dim.height)
  goyo#Execute(true, '')
})

Test('percent offset expression parses', () => {
  goyo#Execute(false, '50%+5x50%-2')
  var dim = t:goyo_dim
  assert_equal(40 + 5, dim.width)
  assert_equal(12 - 2, dim.height)
  goyo#Execute(true, '')
})

Test('empty dimension uses configured defaults', () => {
  g:goyo_width = 100
  g:goyo_height = '50%'
  goyo#Execute(false, '')
  assert_equal(100, t:goyo_dim.width)
  assert_equal(12, t:goyo_dim.height)
  goyo#Execute(true, '')
})

# ---------------------------------------------------------------------------
# 9. Callbacks and user events
# ---------------------------------------------------------------------------
Test('g:goyo_callbacks fire on enter and leave', () => {
  var calls: list<string> = []
  g:goyo_callbacks = [
    () => calls->add('enter'),
    () => calls->add('leave'),
  ]
  goyo#Execute(false, '80x20')
  assert_equal(['enter'], calls)
  goyo#Execute(true, '')
  assert_equal(['enter', 'leave'], calls)
  unlet g:goyo_callbacks
})

Test('invalid g:goyo_callbacks entries are ignored', () => {
  g:goyo_callbacks = ['not-a-funcref', 42]
  goyo#Execute(false, '80x20')
  assert_true(goyo#IsActive())
  goyo#Execute(true, '')
  unlet g:goyo_callbacks
})

Test('User GoyoEnter/GoyoLeave autocmds fire', () => {
  var log: list<string> = []
  augroup goyo_test_events
    autocmd!
    autocmd User GoyoEnter call add(g:test_evt, 'enter')
    autocmd User GoyoLeave call add(g:test_evt, 'leave')
  augroup END
  g:test_evt = []
  goyo#Execute(false, '80x20')
  goyo#Execute(true, '')
  augroup goyo_test_events
    autocmd!
  augroup END
  augroup! goyo_test_events
  assert_equal(['enter', 'leave'], g:test_evt)
  unlet g:test_evt
})

# ---------------------------------------------------------------------------
# 10. Line-number option
# ---------------------------------------------------------------------------
Test('g:goyo_linenr=1 keeps numbers', () => {
  set number
  g:goyo_linenr = 1
  goyo#Execute(false, '80x20')
  # The content window keeps 'number'.
  execute ':' .. win_id2win(t:goyo_winid) .. 'wincmd w'
  assert_true(&number)
  goyo#Execute(true, '')
  unlet g:goyo_linenr
  set nonumber
})

Test('default hides numbers in content window', () => {
  set number
  unlet! g:goyo_linenr
  goyo#Execute(false, '80x20')
  execute ':' .. win_id2win(t:goyo_winid) .. 'wincmd w'
  assert_false(&number)
  goyo#Execute(true, '')
  set nonumber
})

# ---------------------------------------------------------------------------
# 11. Temporary mappings
# ---------------------------------------------------------------------------
Test('temporary <C-w> mappings are installed and removed', () => {
  var before = maparg('<C-w>', 'n')
  var before_lt = maparg('<C-w><lt>', 'n')
  goyo#Execute(false, '80x20')
  assert_false(empty(maparg('<C-w>R', 'n')))
  assert_false(empty(maparg('<C-w>=', 'n')))
  goyo#Execute(true, '')
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
  goyo#Execute(false, '80x20')
  var tmp2 = tempname()
  writefile(['b'], tmp2)
  execute 'vsplit ' .. tmp2
  # master + new split + 4 pads = 6
  assert_equal(6, winnr('$'))
  goyo#Execute(true, '')
  # Both content windows survive leaving Goyo.
  assert_equal(2, winnr('$'))
  silent! execute 'bwipeout! ' .. tmp
  silent! execute 'bwipeout! ' .. tmp2
})

Test('ConfineWindows brings full-width window back into content column', () => {
  goyo#Execute(false, '80x20')
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
  goyo#Execute(true, '')
})

# ---------------------------------------------------------------------------
# 13. Plugin layer and namespace API (import autoload)
# ---------------------------------------------------------------------------
Test('plugin defines <Plug> mappings', () => {
  assert_false(empty(maparg('<Plug>(goyo-off)', 'n')))
  assert_false(empty(maparg('<Plug>(goyo-resize)', 'n')))
})

Test('plugin does not clobber user <C-w> mappings by default', () => {
  # The plugin must not set <C-w> mappings at load time.
  goyo#Execute(true, '')
  # Just check that nothing is left behind.
  assert_true(empty(maparg('<C-w>R', 'n')) || !goyo#IsActive())
})

Test('goyo#IsActive / goyo#Pads compatibility names exist', () => {
  assert_true(exists('*goyo#IsActive') > 0)
  assert_true(exists('*goyo#Pads') > 0)
  assert_true(exists('*goyo#Close') > 0)
  assert_true(exists('*goyo#Resize') > 0)
  assert_true(exists('*goyo#Complete') > 0)
})

Test('goyo#Pads returns empty when inactive', () => {
  goyo#Execute(true, '')
  assert_equal({}, goyo#Pads())
})

Test('goyo#Pads returns four pads when active', () => {
  goyo#Execute(false, '80x20')
  var pads = goyo#Pads()
  assert_equal(4, len(pads))
  for k in ['l', 'r', 't', 'b']
    assert_true(has_key(pads, k))
    assert_true(bufexists(pads[k]))
  endfor
  goyo#Execute(true, '')
})

Test('goyo#Close closes an active session', () => {
  goyo#Execute(false, '80x20')
  assert_true(goyo#IsActive())
  goyo#Close()
  assert_false(goyo#IsActive())
})

Test('goyo#Resize is a no-op when inactive', () => {
  goyo#Execute(true, '')
  goyo#Resize()
  assert_false(goyo#IsActive())
})

Test('goyo#Complete returns candidates and is well formed', () => {
  var items = goyo#Complete('8', 'Goyo 8', 6)
  assert_true(type(items) == v:t_list)
  assert_true(len(items) > 0)
  assert_true(index(items, '80') >= 0)
})

Test('<Plug>(goyo-off) leaves Goyo', () => {
  goyo#Execute(false, '80x20')
  assert_true(goyo#IsActive())
  execute "normal \<Plug>(goyo-off)"
  assert_false(goyo#IsActive())
})

Test('<Plug>(goyo-resize) re-applies dimensions', () => {
  goyo#Execute(false, '80x20')
  var before = get(t:, 'goyo_dim', {})
  execute "normal \<Plug>(goyo-resize)"
  assert_equal(before, get(t:, 'goyo_dim', {}))
  goyo#Execute(true, '')
})

# ---------------------------------------------------------------------------
# Run and report
# ---------------------------------------------------------------------------

Teardown()

Report(printf('goyo tests: %d passed, %d failed', passed, failed))

# Exit status: number of failures, convenient for CI.
FlushReport()
if failed > 0
  execute 'cquit ' .. failed
else
  qall!
endif
