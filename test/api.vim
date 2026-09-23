vim9script
# ============================================================================
# LLM POWERED
#
# Developed with assistance from DeepSeek V4.1 and the DeepSeek harness.
# ============================================================================
# zen.vim dependency contract tests
#
# The plugin leans on a number of Vim built-ins and events.  Vim does not
# remove functions, but it does change the *shape* of some return values and
# the set of available events/options.  These tests pin the contract the
# plugin relies on, so that a change in Vim surfaces in CI instead of at
# runtime.
#
# Run with:  sh test/api.sh   (or make api)
# ============================================================================

var passed = 0
var failed = 0
var report: list<string> = []

def Ok(msg: string)
  report->add('ok   - ' .. msg)
enddef

def Fail(msg: string)
  report->add('FAIL - ' .. msg)
enddef

def Check(desc: string, cond: bool)
  if cond
    passed += 1
    Ok(desc)
  else
    failed += 1
    Fail(desc)
  endif
enddef

# --- functions the plugin calls -------------------------------------------
const FUNCTIONS: list<string> = [
  'append', 'bindtextdomain', 'bufexists', 'bufwinnr', 'bufnr', 'cursor',
  'deepcopy', 'deletebufline', 'empty', 'escape', 'exists', 'expand',
  'extend', 'filter', 'fnamemodify', 'get', 'getbufline', 'getbufvar',
  'getcurpos', 'gettext', 'getwininfo', 'has', 'hlget', 'hlset', 'index',
  'keys', 'len', 'line', 'maparg', 'mapnew', 'matchlist', 'max', 'min',
  'printf', 'rand', 'range', 'repeat', 'setbufvar', 'str2nr', 'string',
  'tabpagenr', 'type', 'winbufnr', 'winheight', 'winlayout', 'winnr',
  'winrestview', 'winsaveview', 'winwidth',
]
const EVENTS: list<string> = [
  'BufWinEnter', 'ColorScheme', 'TabLeave', 'VimResized', 'WinEnter',
  'WinLeave', 'WinResized',
]
const OPTIONS: list<string> = [
  'buftype', 'bufhidden', 'colorcolumn', 'fillchars', 'laststatus',
  'numberwidth', 'relativenumber', 'ruler', 'showtabline', 'sidescroll',
  'sidescrolloff', 'statusline', 'winfixheight', 'winfixwidth',
  'winheight', 'winminheight', 'winminwidth', 'winwidth',
]

# --- availability ----------------------------------------------------------
for f in FUNCTIONS
  Check('function exists: ' .. f .. '()', exists('*' .. f) == 1)
endfor
for e in EVENTS
  Check('event exists: ' .. e, exists('##' .. e) == 1)
endfor
for o in OPTIONS
  Check('option exists: ' .. o, exists('&' .. o) == 1)
endfor

# 'winfixbuf' was added in Vim 9.1.0147, which is later than the plugin's
# minimum of 9.1.0000.  The plugin probes it, so it must exist on newer builds
# and may be absent on the earliest supported ones.
if has('patch-9.1.0147')
  Check("option exists: winfixbuf (>= 9.1.0147)", exists('&winfixbuf') == 1)
else
  Ok("winfixbuf not required before 9.1.0147 (probed by the plugin)")
endif

# --- return-value contracts the plugin depends on --------------------------
# getcurpos(): [bufnum, lnum, col, off, curswant]
var cp = getcurpos()
Check('getcurpos() returns 5 items', len(cp) == 5)
Check('getcurpos()[1] is the line number (Number)', type(cp[1]) == v:t_number)
Check('getcurpos()[2] is the column (Number)', type(cp[2]) == v:t_number)

# getwininfo(): list of dicts with the keys the plugin reads
var wi = getwininfo()
Check('getwininfo() returns a List', type(wi) == v:t_list)
Check('getwininfo() is non-empty in a normal session', len(wi) > 0)
if len(wi) > 0
  var d: dict<any> = wi[0]
  for k in ['bufnr', 'winnr', 'wincol', 'winrow', 'width', 'height', 'winid', 'tabnr']
    Check('getwininfo() entry has "' .. k .. '"', has_key(d, k))
  endfor
endif

# winlayout(): ['leaf', winid] / ['row', [...]] / ['col', [...]]
var wl = winlayout()
Check('winlayout() returns a List', type(wl) == v:t_list)
Check('winlayout() starts with a known kind', wl[0] == 'leaf' || wl[0] == 'row' || wl[0] == 'col')
if wl[0] == 'leaf'
  Check('winlayout() leaf is ["leaf", winid]', len(wl) == 2 && type(wl[1]) == v:t_number)
else
  Check('winlayout() container is [kind, List]', len(wl) == 2 && type(wl[1]) == v:t_list)
endif

# winsaveview()/winrestview(): the dictionary round-trips
var view = winsaveview()
Check('winsaveview() returns a Dict', type(view) == v:t_dict)
for k in ['lnum', 'col', 'topline', 'leftcol']
  Check('winsaveview() has "' .. k .. '"', has_key(view, k))
endfor
winrestview(view)

# maparg() with dict=1 returns a Dict (used to test whether a key is free)
var d2: dict<any> = maparg('zzz_no_such_map_zzz', 'n', false, true)
Check('maparg(..., 1) returns a Dict', type(d2) == v:t_dict)

# mapnew() must not modify its input
var src: list<number> = [1, 2, 3]
var dst = mapnew(src, (_: number, v: number): number => v * 2)
Check('mapnew() leaves the source intact', src == [1, 2, 3])
Check('mapnew() returns the mapped list', dst == [2, 4, 6])

# hlget()/hlset() accept a bare group name and a list of dicts
var hl: list<dict<any>> = hlget('Normal', true)
Check('hlget() returns a List', type(hl) == v:t_list)
if len(hl) > 0
  Check('hlget() entry has "name"', has_key(hl[0], 'name'))
endif
Check('hlset() accepts a list', hlset([]) == 0)

# timer_start() returns a Number id (zero-delay deferral)
var tid: number = timer_start(0, (_: number) => 0)
Check('timer_start() returns a Number', type(tid) == v:t_number)

# --------------------------------------------------------------------------
var out = getenv('ZEN_API_OUT')
if empty(out)
  out = '/tmp/zen-api.txt'
endif
report->add(printf('api tests: %d passed, %d failed', passed, failed))
writefile(report, out)
if failed > 0
  execute 'cquit ' .. failed
endif
qall!
