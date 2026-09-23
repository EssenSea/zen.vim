vim9script

# goyo.vim: Distraction-free writing mode (implementation)
#
# Maintainer:   goyo.vim fork contributors
# Last Change:  2026 Sep 23
# License:      MIT (see LICENSE)
#
# This file is the Vim9script implementation of the plugin.  plugin/goyo.vim
# defines the user-facing command and imports this file as `goyo`; only the
# exported items below are part of the public API.
#
# Design notes:
#   * Session state lives in tab-local variables (t:goyo_*) so that multiple
#     tabs never interfere with each other.
#   * Options and mappings touched while Goyo is active are saved on entry and
#     restored exactly on exit.
#   * Autocommands are confined to the `goyo` augroup and removed on exit.
#
# See doc/goyo.txt for user documentation.

# ---------------------------------------------------------------------------
# Message translation.  The package identifier is "goyo" (see
# :help package-translation).  The lang/ directory is optional; when it
# is absent gettext() simply returns the untranslated string.
# ---------------------------------------------------------------------------
try
  bindtextdomain('goyo',
    fnamemodify(expand('<sfile>'), ':p:h') .. '/../lang/')
catch
  # bindtextdomain() is only available with the +multi_lang feature; ignore.
endtry

# ---------------------------------------------------------------------------
# Session state (stored in tab-local variables).
#   t:goyo_pads         buffer numbers of the four pads {l,r,t,b}
#   t:goyo_dim          geometry {width,height,xoff,yoff}
#   t:goyo_dim_expr     the expression the geometry was parsed from
#   t:goyo_master       buffer number of the master window
#   t:goyo_winid        window id of the master window
#   t:goyo_orig_winid   window id of the window Goyo started from
#   t:goyo_orig_tab     tab number Goyo started from
#   t:goyo_revert       saved global options
#   t:goyo_maps         temporary mappings to remove on exit
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

# Clamp val into the [minv, maxv] range.
def Clamp(val: number, minv: number, maxv: number): number
  return min([max([val, minv]), maxv])
enddef

# Read a highlight-group attribute.  synIDattr() returns a Number (-1) on
# Vim and a String ('' or '#rrggbb') on GVim depending on the attribute.
def Highlight(group: string, attr: string): any
  return synIDattr(synIDtrans(hlID(group)), attr)
enddef

# Set a highlight attribute, choosing gui or cterm automatically.
def SetHighlight(group: string, attr: string, color: string)
  var use_gui = has('gui_running') || (has('termguicolors') && &termguicolors)
  execute printf('highlight %s %s%s=%s', group, use_gui ? 'gui' : 'cterm', attr, color)
enddef

# Restore an option through :set, avoiding the Vim9 restriction on
# `:let &opt = ...`.  Strings have characters escaped that would end or
# change the meaning of the :set argument.
def RestoreOption(name: string, value: any)
  if type(value) == v:t_bool
    execute 'set ' .. (value ? '' : 'no') .. name
  elseif type(value) == v:t_number
    execute 'set ' .. name .. '=' .. value
  elseif type(value) == v:t_string
    execute 'set ' .. name .. '=' .. escape(value, " \t|\\\"")
  endif
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
  if !get(g:, 'goyo_linenr', 0)
    setlocal nonumber
    if exists('&relativenumber')
      setlocal norelativenumber
    endif
  endif
  if exists('&colorcolumn')
    setlocal colorcolumn=
  endif
enddef

# ---------------------------------------------------------------------------
# Mapping management: remember the <C-w> keys we override so they can be
# restored exactly on exit.
# ---------------------------------------------------------------------------
def MapNop(): list<string>
  var keys = ['R', 'H', 'J', 'K', 'L', '|', '_']
  var mapped: list<string> = []
  for k in keys
    if empty(maparg("\<C-w>" .. k, 'n'))
      execute 'nnoremap <silent> <C-w>' .. escape(k, '|') .. ' <Nop>'
      mapped->add(k)
    endif
  endfor
  return mapped
enddef

def MapResize(): list<string>
  # Command table: key -> <ScriptCmd> call.
  var commands: dict<string> = {
    '=': 'ResizeFromExpr()',
    '>': 'ResizeWidth(v:count1)',
    '<': 'ResizeWidth(-v:count1)',
    '+': 'ResizeHeight(v:count1)',
    '-': 'ResizeHeight(-v:count1)',
  }
  var mapped: list<string> = []
  for k in keys(commands)
    if empty(maparg("\<C-w>" .. k, 'n'))
      execute 'nnoremap <silent> <C-w>' .. escape(k, '|')
        .. ' <ScriptCmd>' .. commands[k] .. '<CR>'
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
    \ noswapfile nonumber nocursorline nocursorcolumn winfixwidth
    \ winfixheight nowrap statusline=\ 
  if exists('&relativenumber')
    setlocal norelativenumber
  endif
  if exists('&colorcolumn')
    setlocal colorcolumn=
  endif
  var bufnr = winbufnr(0)

  if winnr('#') > 0
    execute ':' .. winnr('#') .. 'wincmd w'
  endif
  return bufnr
enddef

# Resize the window showing a pad buffer and install the autocommands that
# make the cursor bounce back when it reaches the padding.
def SetupPad(bufnr: number, vert: bool, size: number, repel: string)
  var win = bufwinnr(bufnr)
  if win <= 0
    return
  endif
  execute ':' .. win .. 'wincmd w'
  execute (vert ? 'vertical ' : '') .. 'resize ' .. max([0, size])

  augroup goyo_pad
    execute 'autocmd WinEnter,CursorMoved <buffer> ++nested'
      .. ' Blank("' .. repel .. '")'
    execute 'autocmd WinLeave <buffer> HideStatusline()'
  augroup END

  # Clear the buffer; append blank lines to hide scroll bars if needed.
  setlocal modifiable
  deletebufline(bufnr(''), 1, '$')
  var diff = winheight(0) - line('$') - (has('gui_running') ? 2 : 0)
  if diff > 0
    append(0, repeat([''], diff))
  endif

  if get(g:, 'goyo_decoration_density', 0.0) > 0.0
    Decorate()
  endif
  setlocal nomodifiable
  normal! gg
  if winnr('#') > 0
    execute ':' .. winnr('#') .. 'wincmd w'
  endif
enddef

# Bounce the cursor back into the content window.
def Blank(repel: string)
  var pads = get(t:, 'goyo_pads', {})
  if bufwinnr(pads.r) <= bufwinnr(pads.l) + 1
      || bufwinnr(pads.b) <= bufwinnr(pads.t) + 3
    execute 'silent! call feedkeys("\<Plug>(goyo-off)")'
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

  var elements: list<string> = get(g:, 'goyo_decoration_elements', ['~'])
  # Drop empty elements so the grid width cannot become zero.
  elements = filter(map(copy(elements),
    (_: number, e: string): string => printf('%1s', e)),
    (_: number, e: string): bool => !empty(e))
  if empty(elements)
    return
  endif
  var grid_width = max(map(copy(elements), (_: number, e: string): number => len(e)))
  var elements_count = len(elements)
  var blank = repeat(' ', grid_width)
  var density = get(g:, 'goyo_decoration_density', 0.0)

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
  if exists('g:goyo_height') || (!exists('g:goyo_margin_top') && !exists('g:goyo_margin_bottom'))
    height = Relsz(get(g:, 'goyo_height', '85%'), &lines)
    yoff = 0
  else
    var top = max([0, Relsz(get(g:, 'goyo_margin_top', 4), &lines)])
    var bot = max([0, Relsz(get(g:, 'goyo_margin_bottom', 4), &lines)])
    height = &lines - top - bot
    yoff = top - bot
  endif

  var dim: dict<number> = {
    'width':  Relsz(get(g:, 'goyo_width', 80), &columns),
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
    echomsg gettext('goyo: invalid dimension expression: ') .. arg
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
def ResizePads()
  augroup goyo_pad
    autocmd!
  augroup END

  var dim = t:goyo_dim
  dim.width = Clamp(dim.width, 2, &columns)
  dim.height = Clamp(dim.height, 2, &lines)

  var vmargin = max([0, (&lines - dim.height) / 2 - 1])
  var yoff = Clamp(dim.yoff, -vmargin, vmargin)
  var top = vmargin + yoff
  var bot = vmargin - yoff - 1
  SetupPad(t:goyo_pads.t, false, top, 'j')
  SetupPad(t:goyo_pads.b, false, bot, 'k')

  var nwidth = max([len(string(line('$'))) + 1, &numberwidth])
  var width = dim.width + (&number ? nwidth : 0)
  var hmargin = max([0, (&columns - width) / 2 - 1])
  var xoff = Clamp(dim.xoff, -hmargin, hmargin)
  SetupPad(t:goyo_pads.l, true, hmargin + xoff, 'l')
  SetupPad(t:goyo_pads.r, true, hmargin - xoff, 'h')
enddef

# Re-parse the expression and re-apply the geometry (<C-w>=).
def ResizeFromExpr()
  t:goyo_dim = ParseArg(t:goyo_dim_expr)
  ResizePads()
enddef

def ResizeWidth(delta: number)
  t:goyo_dim.width = winwidth(0) + 2 * delta
  ResizePads()
enddef

def ResizeHeight(delta: number)
  t:goyo_dim.height += 2 * delta
  ResizePads()
enddef

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

# Blend interface elements into the background for a distraction-free look.
def Tranquilize()
  var bg = Highlight('Normal', 'bg#')
  for grp in ['NonText', 'FoldColumn', 'ColorColumn', 'VertSplit',
              'StatusLine', 'StatusLineNC', 'SignColumn']
    if empty(bg) || (type(bg) == v:t_number && bg == -1)
      SetHighlight(grp, 'fg', get(g:, 'goyo_bg', 'black'))
      SetHighlight(grp, 'bg', 'NONE')
    else
      SetHighlight(grp, 'fg', bg)
      SetHighlight(grp, 'bg', bg)
    endif
    SetHighlight(grp, '', 'NONE')
  endfor
enddef

# ---------------------------------------------------------------------------
# Confining content windows (:help / :copen / tag jumps stay in the column)
# ---------------------------------------------------------------------------

# Return the horizontal bounds of the content column as [left, right].
def ContentBounds(): list<number>
  var lpad = bufwinnr(t:goyo_pads.l)
  var rpad = bufwinnr(t:goyo_pads.r)
  var left = lpad > 0 ? win_screenpos(lpad)[1] + winwidth(lpad) : 1
  var right = rpad > 0 ? win_screenpos(rpad)[1] - 1 : &columns
  return [left, right]
enddef

# Locate the master window: prefer its window id (its buffer may have
# changed), fall back to its buffer number.
def MasterWin(): number
  var win = win_id2win(t:goyo_winid)
  if win > 0
    return win
  endif
  return bufwinnr(t:goyo_master)
enddef

# When a content window lies outside the content column (for example one
# opened with :topleft split), close it and re-open its buffer with an
# ordinary :split from the master window.  Only one window is handled per
# call; BufWinEnter fires again for the rest, which avoids invalidating the
# window iteration.
def ConfineWindows()
  if !exists('#goyo') || !exists('t:goyo_pads')
    return
  endif
  var master_win = MasterWin()
  if master_win <= 0
    return
  endif
  var bounds = ContentBounds()
  var left = bounds[0]
  var right = bounds[1]

  for win in range(1, winnr('$'))
    var buf = winbufnr(win)
    if buf == t:goyo_pads.t || buf == t:goyo_pads.b
        || buf == t:goyo_pads.l || buf == t:goyo_pads.r
        || win == master_win
      continue
    endif

    var wincol = win_screenpos(win)[1]
    if wincol >= left && wincol + winwidth(win) - 1 <= right
      continue
    endif

    # Outside the column: close and re-open from the master as a split.
    var v = winsaveview()
    var target = buf
    execute ':' .. master_win .. 'wincmd w'
    execute ':' .. win .. 'wincmd c'
    execute 'sbuffer ' .. target
    winrestview(v)
    return
  endfor
enddef

# ---------------------------------------------------------------------------
# Entering and leaving
# ---------------------------------------------------------------------------

# Remember the state of plugins that Goyo interferes with, to restore it
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
  var wmw = remove(revert, 'winminwidth')
  var ww  = remove(revert, 'winwidth')
  var wmh = remove(revert, 'winminheight')
  var wh  = remove(revert, 'winheight')

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

  for [k, v] in items(revert)
    RestoreOption(k, v)
  endfor
enddef

# Enter Goyo.
# Refresh the session windows on BufWinEnter/WinEnter and confine
# out-of-column windows.  Only acts on the Goyo tab so other tabs are
# unaffected.
def OnBufWinEnter()
  if !exists('t:goyo_pads')
    return
  endif
  HideLinenr()
  HideStatusline()
  ConfineWindows()
enddef

def OnWinEnter()
  if exists('t:goyo_pads')
    HideStatusline()
  endif
enddef

def GoyoOn(dim_arg: string)
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

  t:goyo_orig_winid = orig_winid
  t:goyo_orig_tab = orig_tab
  t:goyo_master = winbufnr(0)
  t:goyo_winid = win_getid()
  t:goyo_dim = dim
  t:goyo_dim_expr = dim_arg
  t:goyo_pads = {}
  t:goyo_revert = revert

  t:goyo_disabled = DisablePlugins()
  t:goyo_maps = MapNop() + MapResize()

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

  t:goyo_pads.l = InitPad('vertical topleft new')
  t:goyo_pads.r = InitPad('vertical botright new')
  t:goyo_pads.t = InitPad('topleft new')
  t:goyo_pads.b = InitPad('botright new')

  ResizePads()
  Tranquilize()

  augroup goyo
    autocmd!
    autocmd TabLeave    * ++nested call GoyoOff()
    autocmd VimResized  * call ResizePads()
    autocmd ColorScheme * call Tranquilize()
    # Only act on this tab; ConfineWindows() pulls stray windows back.
    autocmd BufWinEnter * call OnBufWinEnter()
    autocmd WinEnter    * call OnWinEnter()
    if has('nvim')
      autocmd TermClose * call feedkeys("\<Plug>(goyo-resize)")
    endif
  augroup END

  HideStatusline()
  if exists('g:goyo_callbacks') && len(g:goyo_callbacks) > 0
    g:goyo_callbacks[0]()
  endif
  doautocmd <nomodeline> User GoyoEnter
enddef

# Leave Goyo and transplant the content-window layout back to the
# original tab.
def GoyoOff()
  if !exists('#goyo') || !exists('t:goyo_revert')
    return
  endif

  augroup goyo
    autocmd!
  augroup END
  augroup! goyo
  augroup goyo_pad
    autocmd!
  augroup END
  augroup! goyo_pad

  UnmapWindowKeys(get(t:, 'goyo_maps', []))

  var revert   = t:goyo_revert
  var disabled = get(t:, 'goyo_disabled', {})
  var orig_winid = get(t:, 'goyo_orig_winid', 0)
  var pads = get(t:, 'goyo_pads', {})

  # Collect buffer, cursor and screen position of every content window.
  var content: list<dict<any>> = []
  for win in range(1, winnr('$'))
    var buf = winbufnr(win)
    if buf == get(pads, 't', -1) || buf == get(pads, 'b', -1)
        || buf == get(pads, 'l', -1) || buf == get(pads, 'r', -1)
      continue
    endif
    var wid = win_getid(win)
    var pos = win_screenpos(win)
    content->add({
      buf: buf,
      lnum: getcurpos(wid)[1],
      col: getcurpos(wid)[2],
      row: pos[0],
      col_pos: pos[1],
    })
  endfor
  content->sort((a, b) => a.row != b.row ? a.row - b.row : a.col_pos - b.col_pos)

  var goyo_tab = tabpagenr()

  # Go back to the original tab/window and rebuild the layout there.
  # Prefer the original window id (tab numbers may have changed), fall
  # back to the recorded tab number.
  var orig_tab = get(t:, 'goyo_orig_tab', 0)
  if orig_winid > 0 && win_id2win(orig_winid) > 0
    win_gotoid(orig_winid)
  elseif orig_tab > 0 && orig_tab <= tabpagenr('$')
    execute ':' .. orig_tab .. 'tabnext'
  endif

  if !empty(content)
    if winbufnr(0) != content[0].buf && bufexists(content[0].buf)
      execute 'buffer ' .. content[0].buf
    endif
    winrestview({lnum: content[0].lnum, col: content[0].col, topline: 1, leftcol: 0})

    var base = content[0]
    for i in range(1, len(content) - 1)
      var item = content[i]
      var cmd = ''
      if item.col_pos > base.col_pos
        cmd = 'rightbelow vertical split'
      elseif item.col_pos < base.col_pos
        cmd = 'leftabove vertical split'
      elseif item.row >= base.row
        cmd = 'belowright split'
      else
        cmd = 'aboveleft split'
      endif
      execute cmd
      if bufexists(item.buf)
        execute 'buffer ' .. item.buf
      endif
      winrestview({lnum: item.lnum, col: item.col, topline: 1, leftcol: 0})
    endfor
  endif

  # Close the Goyo tab.
  if goyo_tab != tabpagenr() && goyo_tab <= tabpagenr('$')
    execute ':' .. goyo_tab .. 'tabclose!'
  endif

  RestoreOptions(revert)
  silent! execute 'colorscheme ' .. get(g:, 'colors_name', 'default')

  EnablePlugins(disabled)

  if exists('g:goyo_callbacks') && len(g:goyo_callbacks) > 1
    g:goyo_callbacks[1]()
  endif
  doautocmd <nomodeline> User GoyoLeave
enddef

# ---------------------------------------------------------------------------
# Public API (imported by plugin/goyo.vim as `goyo`)
# ---------------------------------------------------------------------------

# Whether a Goyo session is currently active in this tab.
export def IsActive(): bool
  return exists('#goyo')
enddef

# Access the pad buffers of the current session ({l,r,t,b} -> bufnr).
# Returns an empty dict when Goyo is not active.
export def Pads(): dict<number>
  return get(t:, 'goyo_pads', {})
enddef

# Close the current Goyo session.  Safe to call when it is not active.
export def Close()
  GoyoOff()
enddef

# Re-apply the current dimensions.
export def Resize()
  if IsActive()
    ResizePads()
  endif
enddef

# Main entry point, called by the :Goyo command in plugin/goyo.vim.
#   bang: when true, force leaving regardless of state.
#   dim:  optional dimension expression (see doc/goyo.txt).
export def Execute(bang: bool, dim: string)
  if bang
    GoyoOff()
    return
  endif
  if !IsActive()
    GoyoOn(dim)
  elseif !empty(dim)
    # Changing dimensions on a live session: rebuild only when the layout is
    # too small for the pads, otherwise just resize.
    if winnr('$') < 5
      GoyoOff()
      GoyoOn(dim)
      return
    endif
    var d = ParseArg(dim)
    if !empty(d)
      t:goyo_dim = d
      t:goyo_dim_expr = dim
      ResizePads()
    endif
  else
    GoyoOff()
  endif
enddef

# Custom completion for :Goyo ({ArgLead}, {CmdLine}, {CursorPos}; see
# :help command-completion-customlist).
export def Complete(arglead: string, cmdline: string, _cursorpos: number): list<string>
  if cmdline =~ '\s\S*$'
    return ['80', '100', '120', '50%', '60%', '80x24', '50%x70%', '120x30']
  endif
  return []
enddef

# vim: ts=8 sts=2 sw=2 et:
