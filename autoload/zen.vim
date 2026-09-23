vim9script

# zen.vim: Distraction-free writing mode (implementation)
#
# Maintainer:   zen.vim fork contributors
# Last Change:  2026 Sep 23
# License:      MIT (see LICENSE)
#
# This file is the Vim9script implementation of the plugin.  plugin/zen.vim
# defines the user-facing command and imports this file as `zen`; only the
# exported items below are part of the public API.
#
# Design notes:
#   * Session state lives in tab-local variables (t:zen_*) so that multiple
#     tabs never interfere with each other.
#   * Options and mappings touched while Zen is active are saved on entry and
#     restored exactly on exit.
#   * Autocommands are confined to the `zen` augroup and removed on exit.
#
# See doc/zen.txt for user documentation.

# ---------------------------------------------------------------------------
# Message translation.  The package identifier is "zen" (see
# :help package-translation).  The lang/ directory is optional; when it
# is absent gettext() simply returns the untranslated string.
# ---------------------------------------------------------------------------
try
  bindtextdomain('zen',
    fnamemodify(expand('<sfile>'), ':p:h') .. '/../lang/')
catch
  # bindtextdomain() is only available with the +multi_lang feature; ignore.
endtry

# Highlight groups whose attributes are blended into the background while
# Zen is active.  They are saved before Tranquilize() and restored on exit.
const TRANQUILIZED_GROUPS: list<string> = [
  'NonText', 'FoldColumn', 'ColorColumn', 'VertSplit',
  'StatusLine', 'StatusLineNC', 'SignColumn',
]

# ---------------------------------------------------------------------------
# Session state (stored in tab-local variables).
#   t:zen_pads         buffer numbers of the four pads {l,r,t,b}
#   t:zen_dim          geometry {width,height,xoff,yoff}
#   t:zen_dim_expr     the expression the geometry was parsed from
#   t:zen_master       buffer number of the master window
#   t:zen_winid        window id of the master window
#   t:zen_orig_winid   window id of the window Zen started from
#   t:zen_orig_tab     tab number Zen started from
#   t:zen_revert       saved global options
#   t:zen_maps         temporary mappings to remove on exit
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

# Clamp val into the [minv, maxv] range.
def Clamp(val: number, minv: number, maxv: number): number
  return min([max([val, minv]), maxv])
enddef

# Whether GUI colours are in effect.
def UseGui(): bool
  return has('gui_running') || (has('termguicolors') && &termguicolors)
enddef

# Return the background colour of a highlight group using the built-in
# highlight API (|hlget()|).  The group link is resolved recursively so that
# the effective value is used.  Returns an empty string when no colour is
# defined.
def GroupBg(group: string): string
  var info = hlget(group, true)
  if empty(info)
    return ''
  endif
  var entry = info[0]
  if get(entry, 'cleared', false)
    return ''
  endif
  # Prefer the GUI colour with 'termguicolors', otherwise the cterm colour.
  if UseGui()
    return get(entry, 'guibg', '')
  endif
  return get(entry, 'ctermbg', '')
enddef

# Apply a foreground and background colour to a list of highlight groups in a
# single hlset() call.  A colour of 'NONE' clears the corresponding attribute.
def SetGroupColors(groups: list<string>, fg: string, bg: string)
  var use_gui = UseGui()
  var items: list<dict<any>> = []
  for group in groups
    if use_gui
      # gui: {} clears the attribute flags (bold, ...), as in the original
      # `:highlight Group guifg=.. guibg=.. gui=NONE`.
      items->add({name: group, guifg: fg, guibg: bg, gui: {}})
    else
      items->add({name: group, ctermfg: fg, ctermbg: bg, cterm: {}})
    endif
  endfor
  hlset(items)
enddef

# Parse a size expression: a Number (rows/columns), or a 'N%' String
# (percentage).  Both Numbers and Strings are accepted for compatibility
# with the upstream plugin.
def Relsz(expr: any, limit: number): number
  var e = type(expr) == v:t_string ? expr : string(expr)
  if e !~ '%$'
    return str2nr(e)
  endif
  return limit * str2nr(e[: -2]) / 100
enddef

# Hide the status line, both for the window and for itself.
def HideStatusline()
  setlocal statusline=\ 
enddef

# Hide 'number', 'relativenumber' and 'colorcolumn' unless the user asked
# to keep line numbers.
def HideLinenr()
  if !get(g:, 'zen_linenr', 0)
    setlocal nonumber norelativenumber
  endif
  setlocal colorcolumn=
enddef

# ---------------------------------------------------------------------------
# Mapping management: remember the <C-w> keys we override so they can be
# restored exactly on exit.
# ---------------------------------------------------------------------------
# Keys disabled while Zen is active, and the resize bindings installed in
# their place (key -> <ScriptCmd> body).
# The four padding windows.  key is the name used in t:zen_pads, cmd creates
# the window horizontally or vertically, and repel is the |wincmd| argument
# used to bounce the cursor back into the content column.
const PAD_DEFS: list<dict<string>> = [
  {key: 'l', cmd: 'vertical topleft new',  repel: 'l'},
  {key: 'r', cmd: 'vertical botright new', repel: 'h'},
  {key: 't', cmd: 'topleft new',           repel: 'j'},
  {key: 'b', cmd: 'botright new',          repel: 'k'},
]

const NOP_KEYS: list<string> = ['R', 'H', 'J', 'K', 'L', '|', '_']
const RESIZE_KEYS: dict<string> = {
  '=': 'ResizeFromExpr()',
  '>': 'ResizeWidth(v:count1)',
  '<': 'ResizeWidth(-v:count1)',
  '+': 'ResizeHeight(v:count1)',
  '-': 'ResizeHeight(-v:count1)',
}

# Install the temporary <C-w> mappings.  A key is only mapped when it is
# currently free, so user mappings are never clobbered; the keys that were
# actually installed are returned so they can be removed on exit.
def InstallMaps(): list<string>
  var mapped: list<string> = []
  for k in NOP_KEYS
    if empty(maparg("\<C-w>" .. k, 'n'))
      execute 'nnoremap <silent> <C-w>' .. escape(k, '|') .. ' <Nop>'
      mapped->add(k)
    endif
  endfor
  for k in keys(RESIZE_KEYS)
    if empty(maparg("\<C-w>" .. k, 'n'))
      execute 'nnoremap <silent> <C-w>' .. escape(k, '|')
        .. ' <ScriptCmd>' .. RESIZE_KEYS[k] .. '<CR>'
      mapped->add(k)
    endif
  endfor
  return mapped
enddef

def UnmapWindowKeys(keys: list<string>)
  for k in keys
    execute 'silent! nunmap <C-w>' .. escape(k, '|')
  endfor
enddef

# ---------------------------------------------------------------------------
# Padding windows (pads)
# ---------------------------------------------------------------------------

# Create a padding buffer in the current window and return its buffer
# number.  On return the cursor is back in the previously active window
# (winnr('#')).
def InitPad(command: string): number
  execute command

  # Set all window-local options in one go.
  setlocal buftype=nofile bufhidden=wipe nomodifiable nobuflisted
    \ noswapfile nonumber norelativenumber nocursorline nocursorcolumn
    \ colorcolumn= winfixwidth winfixheight nowrap statusline=\ 
  var bufnr = winbufnr(0)

  if winnr('#') > 0
    execute ':' .. winnr('#') .. 'wincmd w'
  endif
  return bufnr
enddef

# Bind the autocommands that bounce the cursor out of a pad.  Called once per
# pad when the session is created; resizing must not touch them.
def BindPadAutocmd(bufnr: number, repel: string)
  augroup zen_pad
    execute 'autocmd WinEnter,CursorMoved <buffer=' .. bufnr .. '> ++nested'
      .. ' Blank("' .. repel .. '")'
    execute 'autocmd WinLeave <buffer=' .. bufnr .. '> HideStatusline()'
  augroup END
enddef

# Resize the window showing a pad buffer and refill its contents.
# Everything is done with win_execute()/setbufvar()/deletebufline()/append()
# so the current window is never left, avoiding spurious WinEnter/WinLeave.
def SetupPad(bufnr: number, vert: bool, size: number)
  var win = bufwinnr(bufnr)
  if win <= 0
    return
  endif
  var winid = win_getid(win)
  win_execute(winid, (vert ? 'vertical resize ' : 'resize ') .. max([0, size]))

  # Clear the buffer; append blank lines to hide scroll bars if needed.
  setbufvar(bufnr, '&modifiable', true)
  deletebufline(bufnr, 1, '$')
  var diff = winheight(winid) - len(getbufline(bufnr, 1, '$'))
    - (has('gui_running') ? 2 : 0)
  if diff > 0
    append(bufnr, repeat([''], diff))
  endif

  if get(g:, 'zen_decoration_density', 0.0) > 0.0
    win_execute(winid, 'Decorate()')
  endif
  setbufvar(bufnr, '&modifiable', false)
  win_execute(winid, 'normal! gg')
enddef

# Run a callback out of the current autocommand context.  A zero-delay timer
# is used when available; otherwise the callback runs immediately (the
# fallback is only hit on builds without |+timers|).
def Defer(Fn: func)
  if has('timers')
    timer_start(0, (_: number) => Fn())
  else
    Fn()
  endif
enddef

# Bounce the cursor back into the content window.
def Blank(repel: string)
  var pads = get(t:, 'zen_pads', {})
  if bufwinnr(pads.r) <= bufwinnr(pads.l) + 1
      || bufwinnr(pads.b) <= bufwinnr(pads.t) + 3
    # The content column is too small to be useful; leave Zen.  Closing
    # windows from inside CursorMoved/WinEnter is unsafe, so defer it via a
    # zero-delay timer rather than feeding a <Plug> key (which would depend
    # on the user's mappings).
    Defer(() => ZenOff())
  endif
  execute 'noautocmd wincmd ' .. repel
enddef

# Draw ASCII decoration in a pad window.
def Decorate()
  var save_scroll = getcurpos()[1]
  var win_width = winwidth(0)
  var win_height = winheight(0)
  if win_width <= 0 || win_height <= 0
    return
  endif

  # mapnew() leaves g:zen_decoration_elements untouched.
  var elements: list<string> = mapnew(
    get(g:, 'zen_decoration_elements', ['~']),
    (_: number, e: string): string => printf('%1s', e))
  # Drop empty elements so the grid width cannot become zero.
  elements = filter(elements, (_: number, e: string): bool => !empty(e))
  if empty(elements)
    return
  endif
  var grid_width = max(mapnew(elements, (_: number, e: string): number => len(e)))
  var elements_count = len(elements)
  var blank = repeat(' ', grid_width)
  var density = get(g:, 'zen_decoration_density', 0.0)

  # Build all lines at once to avoid repeated append() calls.
  var lines: list<string> = []
  for _ in range(win_height)
    var line = ''
    for _ in range(win_width / grid_width + 1)
      if (rand() % 10000) < (density * 10000)
        var element = elements[rand() % elements_count]
        var length_diff = grid_width - len(element)
        if length_diff > 0
          var left = rand() % length_diff
          element = repeat(' ', left) .. element .. repeat(' ', length_diff - left)
        endif
        line ..= element
      else
        line ..= blank
      endif
    endfor
    lines->add(line[: win_width - 1])
  endfor
  append(0, lines)

  if save_scroll > 0
    cursor(save_scroll, 1)
  endif
  normal! zz
enddef

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

# Parse an expression such as 'N', 'N%', '+N' or '-N' into a geometry
# dictionary.
def ParseArg(arg: string): dict<number>
  var height: number
  var yoff: number
  if exists('g:zen_height') || (!exists('g:zen_margin_top') && !exists('g:zen_margin_bottom'))
    height = Relsz(get(g:, 'zen_height', '85%'), &lines)
    yoff = 0
  else
    var top = max([0, Relsz(get(g:, 'zen_margin_top', 4), &lines)])
    var bot = max([0, Relsz(get(g:, 'zen_margin_bottom', 4), &lines)])
    height = &lines - top - bot
    yoff = top - bot
  endif

  var dim: dict<number> = {
    'width':  Relsz(get(g:, 'zen_width', 80), &columns),
    'height': height,
    'xoff':   0,
    'yoff':   yoff,
  }
  if empty(arg)
    return dim
  endif

  # Syntax: {width}[{+/-xoff}]x{height}[{+/-yoff}]
  # Each of width/height may be an absolute value, a percentage, or be
  # omitted to use the default.  Capture groups: 1=width 2=xoff 3=height
  # 4=yoff.
  var parts = matchlist(arg,
    '^\s*'
    .. '\([+-]\?[0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?'
    .. '\%(x'
    .. '\([+-]\?[0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?'
    .. '\)\?'
    .. '\s*$')
  if empty(parts)
    echohl WarningMsg
    echomsg gettext('zen: invalid dimension expression: ') .. arg
    echohl None
    return {}
  endif
  if !empty(parts[1]) | dim.width = Relsz(parts[1], &columns) | endif
  if !empty(parts[2]) | dim.xoff = Relsz(parts[2], &columns) | endif
  if !empty(parts[3]) | dim.height = Relsz(parts[3], &lines) | endif
  if !empty(parts[4]) | dim.yoff = Relsz(parts[4], &lines) | endif
  return dim
enddef

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

# Resize the four pads so the content window gets the requested geometry.
# This is called from VimResized and WinResized, among others.  Because
# resizing changes window sizes it can trigger WinResized again, so a
# re-entrancy guard ignores those secondary events.  The t:zen_pads check
# makes the autocommand a no-op in other tabs.
var resizing = false

def ResizePads()
  if resizing || !exists('t:zen_pads')
    return
  endif
  resizing = true
  try
    var dim = t:zen_dim
    dim.width = Clamp(dim.width, 2, &columns)
    dim.height = Clamp(dim.height, 2, &lines)

    var vmargin = max([0, (&lines - dim.height) / 2 - 1])
    var yoff = Clamp(dim.yoff, -vmargin, vmargin)
    var top = vmargin + yoff
    var bot = vmargin - yoff - 1
    SetupPad(t:zen_pads.t, false, top)
    SetupPad(t:zen_pads.b, false, bot)

    var nwidth = max([len(string(line('$'))) + 1, &numberwidth])
    var width = dim.width + (&number ? nwidth : 0)
    var hmargin = max([0, (&columns - width) / 2 - 1])
    var xoff = Clamp(dim.xoff, -hmargin, hmargin)
    SetupPad(t:zen_pads.l, true, hmargin + xoff)
    SetupPad(t:zen_pads.r, true, hmargin - xoff)
  finally
    resizing = false
  endtry
enddef

# Re-parse the expression and re-apply the geometry (<C-w>=).
def ResizeFromExpr()
  t:zen_dim = ParseArg(t:zen_dim_expr)
  ResizePads()
enddef

def ResizeWidth(delta: number)
  t:zen_dim.width = winwidth(0) + 2 * delta
  ResizePads()
enddef

def ResizeHeight(delta: number)
  t:zen_dim.height += 2 * delta
  ResizePads()
enddef

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

# Save the highlight attributes we are about to change so they can be
# restored exactly, without reloading the whole color scheme.
def SaveHighlights(): list<dict<any>>
  # hlget() takes a single group name, so query them one by one.
  var saved: list<dict<any>> = []
  for group in TRANQUILIZED_GROUPS
    saved->extend(hlget(group, true))
  endfor
  return saved
enddef

def RestoreHighlights(saved: list<dict<any>>)
  if empty(saved)
    return
  endif
  # hlset() merges the given attributes; it does not remove attributes that
  # are absent from the dictionary.  Tranquilize() may have added an
  # attribute the group did not have before, so clear each group first and
  # then apply the saved attributes.
  var clears: list<dict<any>> = []
  var items: list<dict<any>> = []
  for entry in saved
    clears->add({name: entry.name, cleared: true})
    items->add(deepcopy(entry))
  endfor
  hlset(clears)
  hlset(items)
enddef

# Blend interface elements into the background for a distraction-free look.
# All groups are updated with a single hlset() call.
def Tranquilize()
  var bg = GroupBg('Normal')
  if empty(bg)
    # No usable background colour: fall back to g:zen_bg with no background.
    SetGroupColors(TRANQUILIZED_GROUPS, get(g:, 'zen_bg', 'black'), 'NONE')
  else
    SetGroupColors(TRANQUILIZED_GROUPS, bg, bg)
  endif
enddef

# ---------------------------------------------------------------------------
# Confining content windows (:help / :copen / tag jumps stay in the column)
# ---------------------------------------------------------------------------

# The pad buffer numbers of the current session.
def PadBufs(): list<number>
  var bufs: list<number> = []
  var pads = get(t:, 'zen_pads', {})
  for pad in PAD_DEFS
    if has_key(pads, pad.key)
      bufs->add(pads[pad.key])
    endif
  endfor
  return bufs
enddef

# Return the horizontal bounds of the content column as [left, right].
def ContentBounds(): list<number>
  var lpad = bufwinnr(t:zen_pads.l)
  var rpad = bufwinnr(t:zen_pads.r)
  var left = lpad > 0 ? win_screenpos(lpad)[1] + winwidth(lpad) : 1
  var right = rpad > 0 ? win_screenpos(rpad)[1] - 1 : &columns
  return [left, right]
enddef

# Locate the master window: prefer its window id (its buffer may have
# changed), fall back to its buffer number.
def MasterWin(): number
  var win = win_id2win(t:zen_winid)
  if win > 0
    return win
  endif
  return bufwinnr(t:zen_master)
enddef

# Layout capture and rebuild
# ---------------------------
# winlayout() returns the window tree of a tab page as nested lists:
#   ['leaf', {winid}]
#   ['row',  [child, ...]]   " horizontal row (left to right)
#   ['col',  [child, ...]]   " vertical column (top to bottom)
# The helpers below turn that tree into a form that can be replayed on another
# tab page, dropping the pad windows and remembering each window's buffer and
# view.  This reproduces nested layouts exactly, unlike inferring the
# direction from screen coordinates.

# Switch the current window to buffer {buf}.  'winfixbuf' (Vim 9.1) pins a
# window to its buffer and makes :buffer fail, so it is turned off for the
# switch and restored afterwards.
def SwitchBuffer(buf: number)
  if !bufexists(buf)
    return
  endif
  # 'winfixbuf' (Vim 9.1) pins a window to its buffer; lift it for the switch
  # and restore it afterwards.
  var fixed = &winfixbuf
  if fixed
    setlocal nowinfixbuf
  endif
  execute 'buffer ' .. buf
  if fixed
    setlocal winfixbuf
  endif
enddef

# Replace each leaf with {buf, lnum, col} and drop pad leaves; a node left
# with a single child is collapsed into that child.
def CaptureTree(node: any, padlist: list<number>): any
  if node[0] == 'leaf'
    var winid: number = node[1]
    if index(padlist, winbufnr(winid)) >= 0
      return []
    endif
    var cur = getcurpos(winid)
    return ['leaf', {buf: winbufnr(winid), lnum: cur[1], col: cur[2]}]
  endif
  var kids: list<any> = []
  for child in node[1]
    var pruned = CaptureTree(child, padlist)
    if !empty(pruned)
      kids->add(pruned)
    endif
  endfor
  if empty(kids)
    return []
  endif
  if len(kids) == 1
    return kids[0]
  endif
  return [node[0], kids]
enddef

# Rebuild the tree in the current window.  For a row the windows are split to
# the right, for a column downwards, matching winlayout()'s ordering.
def RebuildTree(node: any)
  if node[0] == 'leaf'
    var item: dict<any> = node[1]
    SwitchBuffer(item.buf)
    winrestview({lnum: item.lnum, col: item.col, topline: 1, leftcol: 0})
    return
  endif
  var children: list<any> = node[1]
  RebuildTree(children[0])
  for i in range(1, len(children) - 1)
    if node[0] == 'row'
      execute 'rightbelow vertical split'
    else
      execute 'belowright split'
    endif
    RebuildTree(children[i])
  endfor
enddef

# When a content window lies outside the content column (for example one
# opened with :topleft split), close it and re-open its buffer with an
# ordinary :split from the master window.  Only one window is handled per
# call; BufWinEnter fires again for the rest, which avoids invalidating the
# window iteration.
# Autocommands should not change the window layout directly, and opening one
# window often triggers several events.  ConfineWindows() is therefore
# scheduled through a zero-delay timer and de-duplicated, so it runs once the
# editor is back in the main loop and handles all stray windows in one pass.
var confine_pending = false

def ScheduleConfine()
  if confine_pending || !exists('t:zen_pads')
    return
  endif
  confine_pending = true
  Defer(() => ConfineWindows())
enddef

def ConfineWindows()
  confine_pending = false
  if !exists('#zen') || !exists('t:zen_pads')
    return
  endif
  var master_win = MasterWin()
  if master_win <= 0
    return
  endif
  var bounds = ContentBounds()
  var left = bounds[0]
  var right = bounds[1]
  var tabnr = tabpagenr()
  var padbufs = PadBufs()

  # Collect the buffers of every content window that sticks out of the
  # content column.  getwininfo() gives the geometry in one call.
  var stray: list<number> = []
  for info in getwininfo()
    if info.tabnr != tabnr
      continue
    endif
    var buf = info.bufnr
    if info.winnr == master_win || index(padbufs, buf) >= 0
      continue
    endif
    if info.wincol >= left && info.wincol + info.width - 1 <= right
      continue
    endif
    stray->add(buf)
  endfor

  # Re-open each stray buffer as an ordinary split from the master window.
  for buf in stray
    if !bufexists(buf)
      continue
    endif
    var master = MasterWin()
    if master <= 0
      break
    endif
    var v = winsaveview()
    # Locate the stray window again: earlier fixes may have renumbered windows.
    var w = bufwinnr(buf)
    if w <= 0 || w == master
      continue
    endif
    execute ':' .. master .. 'wincmd w'
    var was_fixed = &winfixbuf
    if was_fixed
      setlocal nowinfixbuf
    endif
    execute ':' .. w .. 'wincmd c'
    execute 'sbuffer ' .. buf
    if was_fixed
      setlocal winfixbuf
    endif
    winrestview(v)
  endfor
enddef

# ---------------------------------------------------------------------------
# Entering and leaving
# ---------------------------------------------------------------------------

# Remember the state of plugins that Zen interferes with, to restore it
# on exit.
def DisablePlugins(): dict<bool>
  var state: dict<bool> = {}

  state.gitgutter = get(g:, 'gitgutter_enabled', 0)
  if state.gitgutter | silent! execute 'GitGutterDisable' | endif

  state.signify = !empty(getbufvar(bufnr(''), 'sy'))
  if state.signify | silent! execute 'SignifyToggle' | endif

  state.airline = exists('#airline')
  if state.airline | silent! execute 'AirlineToggle' | endif

  state.powerline = exists('#PowerlineMain')
  if state.powerline
    augroup PowerlineMain
      autocmd!
    augroup END
    silent! augroup! PowerlineMain
  endif

  state.lightline = exists('#lightline')
  if state.lightline | silent! execute 'call lightline#disable()' | endif

  return state
enddef

def EnablePlugins(state: dict<bool>)
  if state.gitgutter | silent! execute 'GitGutterEnable' | endif

  if state.signify && !get(b:, 'sy', {}).get('active', 0)
    silent! execute 'SignifyToggle'
  endif

  if state.airline && !exists('#airline')
    silent! execute 'AirlineToggle'
    # Airline needs two refreshes to avoid display artifacts.
    silent! execute 'AirlineRefresh'
    silent! execute 'AirlineRefresh'
  endif

  if state.powerline && !exists('#PowerlineMain')
    doautocmd PowerlineStartup VimEnter
    silent! execute 'PowerlineReloadColorscheme'
  endif

  if state.lightline
    silent! execute 'call lightline#enable()'
  endif

  if exists('#Powerline')
    doautocmd Powerline ColorScheme
  endif
enddef

# Collect the global options that must be saved and restored.
def SaveOptions(): dict<any>
  var opts: dict<any> = {
    'laststatus':    &laststatus,
    'showtabline':   &showtabline,
    'fillchars':     &fillchars,
    'winminwidth':   &winminwidth,
    'winwidth':      &winwidth,
    'winminheight':  &winminheight,
    'winheight':     &winheight,
    'ruler':         &ruler,
    'sidescroll':    &sidescroll,
    'sidescrolloff': &sidescrolloff,
  }
  if has('gui_running')
    opts.guioptions = &guioptions
  endif
  return opts
enddef

def RestoreOptions(revert: dict<any>)
  # winwidth must be >= winminwidth and winheight must be >= winminheight.
  # The order therefore is: enlarge the current values enough to hold the
  # target minimum, set the minimum, then set the target value.  Otherwise
  # Vim raises "E592/E591: cannot be smaller than ...".
  var wmw: number = revert.winminwidth
  var ww: number = revert.winwidth
  var wmh: number = revert.winminheight
  var wh: number = revert.winheight

  # 1) Enlarge the current values enough to hold the target minimum.
  &winwidth = Clamp(max([wmw, ww, &winwidth]), 1, &columns)
  &winheight = Clamp(max([wmh, wh, &winheight]), 1, &lines)
  # 2) Set the minimum, bounded by the current winwidth/winheight so that
  #    Vim clamping on a small layout cannot raise E591/E592.
  &winminwidth = Clamp(wmw, 1, &winwidth)
  &winminheight = Clamp(wmh, 1, &winheight)
  # 3) Set the target value, clamped to [min, upper bound].
  &winwidth = Clamp(max([wmw, ww]), &winminwidth, &columns)
  &winheight = Clamp(max([wmh, wh]), &winminheight, &lines)

  # The remaining options are assigned directly (Vim9-typed), so no :set
  # string escaping is involved.
  &laststatus = revert.laststatus
  &showtabline = revert.showtabline
  &fillchars = revert.fillchars
  &ruler = revert.ruler
  &sidescroll = revert.sidescroll
  &sidescrolloff = revert.sidescrolloff
  if has_key(revert, 'guioptions')
    &guioptions = revert.guioptions
  endif
enddef

# Enter Zen.
# Refresh the session windows on BufWinEnter/WinEnter and confine
# out-of-column windows.  Only acts on the Zen tab so other tabs are
# unaffected.
def OnBufWinEnter()
  if !exists('t:zen_pads')
    return
  endif
  HideLinenr()
  HideStatusline()
  ScheduleConfine()
enddef

def OnWinEnter()
  if exists('t:zen_pads')
    HideStatusline()
  endif
enddef

def ZenOn(dim_arg: string)
  var dim = ParseArg(dim_arg)
  if empty(dim)
    return
  endif

  var orig_tab = tabpagenr()
  var orig_winid = win_getid()
  var revert = SaveOptions()

  # tab split: keep the original tab intact and build the layout in a copy
  # that is closed again on exit.
  tab split

  t:zen_orig_winid = orig_winid
  t:zen_orig_tab = orig_tab
  t:zen_master = winbufnr(0)
  t:zen_winid = win_getid()
  t:zen_dim = dim
  t:zen_dim_expr = dim_arg
  t:zen_pads = {}
  t:zen_revert = revert

  t:zen_disabled = DisablePlugins()
  t:zen_maps = InstallMaps()

  HideLinenr()

  # Global options: make all windows as small as possible so the pads can
  # set the geometry precisely.  Lower the minimum sizes before setting the
  # sizes to 1, or Vim raises E591/E592 on a small layout.
  set winminheight=1 winminwidth=1
  set winheight=1 winwidth=1
  set laststatus=0 showtabline=0 noruler
  set fillchars+=vert:\  fillchars+=stl:\  fillchars+=stlnc:\ 
  set sidescroll=1 sidescrolloff=0

  if has('gui_running')
    set guioptions-=l
    set guioptions-=L
  endif

  for pad in PAD_DEFS
    t:zen_pads[pad.key] = InitPad(pad.cmd)
  endfor

  ResizePads()

  # Bind the bounce-back autocommands once, after the pads are laid out;
  # ResizePads() itself only resizes them.
  for pad in PAD_DEFS
    BindPadAutocmd(t:zen_pads[pad.key], pad.repel)
  endfor

  # Remember the highlight attributes Tranquilize() is about to change.
  t:zen_highlights = SaveHighlights()
  Tranquilize()

  augroup zen
    autocmd!
    autocmd TabLeave    * ++nested call ZenOff()
    autocmd VimResized  * call ResizePads()
    # WinResized (Vim 9.0.0917) is more precise than VimResized.
    autocmd WinResized  * call ResizePads()
    autocmd ColorScheme * call Tranquilize()
    # Only act on this tab; ConfineWindows() pulls stray windows back.
    autocmd BufWinEnter * call OnBufWinEnter()
    autocmd WinEnter    * call OnWinEnter()
  augroup END

  HideStatusline()
  var callbacks = get(g:, 'zen_callbacks', [])
  if len(callbacks) > 0 && type(callbacks[0]) == v:t_func
    callbacks[0]()
  endif
  doautocmd <nomodeline> User ZenEnter
enddef

# Leave Zen and transplant the content-window layout back to the
# original tab.
def ZenOff()
  if !exists('#zen') || !exists('t:zen_revert')
    return
  endif

  augroup zen
    autocmd!
  augroup END
  augroup! zen
  augroup zen_pad
    autocmd!
  augroup END
  augroup! zen_pad

  UnmapWindowKeys(get(t:, 'zen_maps', []))

  var revert   = t:zen_revert
  var disabled = get(t:, 'zen_disabled', {})
  var orig_winid = get(t:, 'zen_orig_winid', 0)
  # Read the saved highlights while still in the Zen tab: t: variables are
  # tab-local and the original tab is restored before the end of this function.
  var saved_highlights = get(t:, 'zen_highlights', [])

  # Capture the content-window layout of the Zen tab as a winlayout() tree
  # with the pad windows removed.  This reproduces nested layouts exactly.
  var layout = CaptureTree(winlayout(), PadBufs())

  var zen_tab = tabpagenr()

  # Go back to the original tab/window and rebuild the layout there.
  # win_gotoid() also switches tab pages, so it is used first; it returns
  # false when the window no longer exists, in which case fall back to the
  # recorded tab number.
  var orig_tab = get(t:, 'zen_orig_tab', 0)
  if orig_winid > 0 && win_gotoid(orig_winid)
    # done
  elseif orig_tab > 0 && orig_tab <= tabpagenr('$')
    execute ':' .. orig_tab .. 'tabnext'
  endif

  if !empty(layout)
    RebuildTree(layout)
  endif

  # Close the Zen tab.
  if zen_tab != tabpagenr() && zen_tab <= tabpagenr('$')
    execute ':' .. zen_tab .. 'tabclose!'
  endif

  RestoreOptions(revert)
  # Restore the highlight groups we changed instead of reloading the color
  # scheme, which is much more expensive and would re-trigger ColorScheme.
  RestoreHighlights(saved_highlights)

  EnablePlugins(disabled)

  var callbacks = get(g:, 'zen_callbacks', [])
  if len(callbacks) > 1 && type(callbacks[1]) == v:t_func
    callbacks[1]()
  endif
  doautocmd <nomodeline> User ZenLeave
enddef

# ---------------------------------------------------------------------------
# Public API (imported by plugin/zen.vim as `zen`)
# ---------------------------------------------------------------------------

# Whether a Zen session is currently active in this tab.
# Public API
# ----------
# The following three functions are the supported interface for other plugins
# and for user mappings.  Everything else in this file is an implementation
# detail and may change without notice.

# Open a Zen session.  When one is already active the dimensions are updated
# instead of rebuilding the layout.  {dim} is an optional dimension
# expression, see |zen-command|.
export def Open(dim: string = '')
  if !IsActive()
    ZenOn(dim)
  elseif !empty(dim)
    # Changing dimensions on a live session: rebuild only when the layout is
    # too small for the pads, otherwise just resize.
    if winnr('$') < 5
      ZenOff()
      ZenOn(dim)
      return
    endif
    var d = ParseArg(dim)
    if !empty(d)
      t:zen_dim = d
      t:zen_dim_expr = dim
      ResizePads()
    endif
  endif
enddef

# Close the current Zen session.  Safe to call when it is not active.
export def Close()
  ZenOff()
enddef

# Toggle Zen: open it when inactive, close it when active.  {dim} has the same
# meaning as for Open().
export def Toggle(dim: string = '')
  if IsActive()
    ZenOff()
  else
    ZenOn(dim)
  endif
enddef

# Whether a Zen session is active in the current tab page.
def IsActive(): bool
  return exists('#zen')
enddef

# The pad buffers of the current session ({l,r,t,b} -> bufnr).
def Pads(): dict<number>
  return get(t:, 'zen_pads', {})
enddef

# Custom completion for :Zen ({ArgLead}, {CmdLine}, {CursorPos}; see
# :help command-completion-customlist).
export def Complete(arglead: string, cmdline: string, _cursorpos: number): list<string>
  if cmdline =~ '\s\S*$'
    return ['80', '100', '120', '50%', '60%', '80x24', '50%x70%', '120x30']
  endif
  return []
enddef

# vim: ts=8 sts=2 sw=2 et:
