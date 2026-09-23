vim9script
# ---------------------------------------------------------------------------
# autoload/goyo.vim 的 Vim9script 移植版本
# Vim9script port of autoload/goyo.vim
#
# 原版使用了一些在 Vim9script 中不可用（或行为不同）的写法，下面按要点说明，
# 文件中每处改动也都有行内注释。
# The original legacy-script implementation used a handful of idioms that are
# not available (or work differently) under Vim9script.  The notable changes
# are documented inline.  In short:
#
#   * 函数用 `def` 声明并带类型，不再有 `s:` 和 `a:` 前缀。
#     Functions are declared with `def` and use typed arguments.  The `s:`
#     and `a:` prefixes no longer exist.
#   * 用 `<ScriptCmd>` 取代 `<sid>`，让映射和命令可以直接调用脚本内函数。
#     `<sid>` is replaced with `<ScriptCmd>` so mappings and commands can
#     invoke the script-local functions directly.
#   * Vim9script 的 `execute` 上下文中不允许 `:let &opt = ...`，因此还原选
#     项改用 `:set` / 辅助函数。
#     Dynamic `:let &opt = ...` is not allowed in a Vim9script `execute`
#     context, so option restoration goes through `:set` / helper functions.
#   * 字符串形式的 `filter()`/`map()` 回调换成 lambda。
#     String-based `filter()`/`map()` callbacks are replaced with lambdas.
#
# 同时修复了 Goyo 激活期间打开新窗口（help/tag 跳转、quickfix 等）时的几个
# 长期问题：
# It also fixes several long-standing goyo issues around windows that are
# opened while Goyo is active (help/tag jumps, quickfix, ...):
#
#   * `:help` 等命令使用 `:topleft split`，会让新窗口横跨整个 tab，左右页边
#     距随之消失。`ConfineWindows()`（由 `BufWinEnter` 自动命令触发）会把这类
#     窗口移回内容列。
#     `:help` and friends use `:topleft split`, so the new window spans the
#     whole tab and the left/right margins disappear.  `ConfineWindows()` (run
#     from a `BufWinEnter` autocmd) moves such windows back into the content
#     column.
#   * `GoyoOff()` 过去记录的是「当前窗口」的光标，所以从 help 窗口退出时会
#     把 master 缓冲区重置到 help 窗口的位置。现在改为显式读取 master 窗口
#     的光标。
#     `GoyoOff()` used to remember the cursor of whichever window happened to
#     be current, so leaving Goyo from a help window reset the master buffer
#     to the help window's position.  It now reads the master window's cursor
#     explicitly.
#   * `GoyoOff()` 现在会保留退出时 master 窗口实际显示的缓冲区，因此中途
#     `:edit` 别的文件，退出后仍停留在那个文件。
#     `GoyoOff()` now preserves the buffer the master window actually shows,
#     so `:edit`-ing another file survives leaving Goyo.
# ---------------------------------------------------------------------------

# Goyo 打开时所在的 tab 号。其余会话状态放在 `t:goyo_*` 变量里，与原版一致。
# Tab number that was active when Goyo was turned on.  All other per-session
# state lives in `t:goyo_*` variables, exactly like the original.
var orig_tab: number

def Const(val: number, min: number, max: number): number
  return min([max([val, min]), max])
enddef

def GetColor(group: string, attr: string): any
  return synIDattr(synIDtrans(hlID(group)), attr)
enddef

def SetColor(group: string, attr: string, color: any)
  var gui = has('gui_running') || (has('termguicolors') && &termguicolors)
  execute printf('hi %s %s%s=%s', group, gui ? 'gui' : 'cterm', attr, color)
enddef

def Blank(repel: string)
  if bufwinnr(t:goyo_pads.r) <= bufwinnr(t:goyo_pads.l) + 1
      || bufwinnr(t:goyo_pads.b) <= bufwinnr(t:goyo_pads.t) + 3
    call feedkeys("\<Plug>(goyo-off)")
  endif
  execute 'noautocmd wincmd ' .. repel
enddef

def Decorate()
  var save_scroll = getcurpos()[1]

  setlocal nowrap

  var win_width = winwidth(0)
  var win_height = winheight(0)

  var elements: list<string> = get(g:, 'goyo_decoration_elements', ['~'])
  # 把网格宽度统一为最长元素的长度
  # Normalise our grid to the length of the longest element
  elements = map(copy(elements), (_: number, element: string): string => printf('%1s', element))
  var grid_width = max(map(copy(elements), (_: number, element: string): number => len(element)))
  var elements_count = len(elements)
  var blank = ''
  for i in range(0, grid_width - 1)
    blank ..= ' '
  endfor
  var density = get(g:, 'goyo_decoration_density', 0.0)

  for line_num in range(win_height)
    var random_line = ''
    for i in range(win_width / grid_width + 1)
      if (rand() % 10000) < (density * 10000)
        var element = elements[rand() % elements_count]
        # 用空格补齐元素宽度，让它在单元格内随机落位
        # Normalise the element width by padding it with spaces to place it
        # somewhere random in the cell
        var length_diff = grid_width - len(element)
        if length_diff > 0
          var left = (rand() % length_diff)
          var right = length_diff - left
          element = repeat(' ', left) .. element .. repeat(' ', right)
        endif
        random_line ..= element
      else
        random_line ..= blank
      endif
    endfor
    random_line = random_line[0 : win_width - 3]
    append(line_num, random_line)
  endfor

  execute ':' .. save_scroll .. 'normal! zz'
enddef

def InitPad(command: string): number
  execute command

  setlocal buftype=nofile bufhidden=wipe nomodifiable nobuflisted noswapfile
      \ nonu nocursorline nocursorcolumn winfixwidth winfixheight statusline=\
  if exists('&rnu')
    setlocal nornu
  endif
  if exists('&colorcolumn')
    setlocal colorcolumn=
  endif
  var bufnr = winbufnr(0)

  execute ':' .. winnr('#') .. 'wincmd w'
  return bufnr
enddef

def SetupPad(bufnr: number, vert: bool, size: number, repel: string)
  var win = bufwinnr(bufnr)
  execute ':' .. win .. 'wincmd w'
  execute (vert ? 'vertical ' : '') .. 'resize ' .. max([0, size])
  augroup goyop
    execute 'autocmd WinEnter,CursorMoved <buffer> ++nested Blank("' .. repel .. '")'
    autocmd WinLeave <buffer> HideStatusline()
  augroup END

  # 用于隐藏 GVim 中 pad 窗口的滚动条
  # To hide scrollbars of pad windows in GVim
  var diff = winheight(0) - line('$') - (has('gui_running') ? 2 : 0)
  if diff > 0
    setlocal modifiable
    append(0, map(range(1, diff), (_: number, _: number): string => ''))
    normal! gg
    setlocal nomodifiable
  endif

  if get(g:, 'goyo_decoration_density', 0.0) > 0.0
    setlocal modifiable
    Decorate()
    normal! gg
    setlocal nomodifiable
  endif

  execute ':' .. winnr('#') .. 'wincmd w'
enddef

def ResizePads()
  augroup goyop
    autocmd!
  augroup END

  t:goyo_dim.width = Const(t:goyo_dim.width, 2, &columns)
  t:goyo_dim.height = Const(t:goyo_dim.height, 2, &lines)

  var vmargin = max([0, (&lines - t:goyo_dim.height) / 2 - 1])
  var yoff = Const(t:goyo_dim.yoff, -vmargin, vmargin)
  var top = vmargin + yoff
  var bot = vmargin - yoff - 1
  SetupPad(t:goyo_pads.t, false, top, 'j')
  SetupPad(t:goyo_pads.b, false, bot, 'k')

  var nwidth = max([len(string(line('$'))) + 1, &numberwidth])
  var width = t:goyo_dim.width + (&number ? nwidth : 0)
  var hmargin = max([0, (&columns - width) / 2 - 1])
  var xoff = Const(t:goyo_dim.xoff, -hmargin, hmargin)
  SetupPad(t:goyo_pads.l, true, hmargin + xoff, 'l')
  SetupPad(t:goyo_pads.r, true, hmargin - xoff, 'h')
enddef

def Tranquilize()
  var bg = GetColor('Normal', 'bg#')
  for grp in ['NonText', 'FoldColumn', 'ColorColumn', 'VertSplit',
              'StatusLine', 'StatusLineNC', 'SignColumn']
    # 没有可用的背景色：数字（Vim 下为 -1）或空字符串（GVim 下为 ''）。
    # 其余（例如 "#14161b"）都是需要镜像的真实颜色。
    # No usable background: a Number (-1 on Vim) or an empty String ('' on
    # GVim).  Anything else (e.g. "#14161b") is a real colour to mirror.
    if empty(bg) || (type(bg) == v:t_number && bg == -1)
      SetColor(grp, 'fg', get(g:, 'goyo_bg', 'black'))
      SetColor(grp, 'bg', 'NONE')
    else
      SetColor(grp, 'fg', bg)
      SetColor(grp, 'bg', bg)
    endif
    SetColor(grp, '', 'NONE')
  endfor
enddef

def HideStatusline()
  setlocal statusline=\
enddef

def HideLinenr()
  if !get(g:, 'goyo_linenr', 0)
    setlocal nonu
    if exists('&rnu')
      setlocal nornu
    endif
  endif
  if exists('&colorcolumn')
    setlocal colorcolumn=
  endif
enddef

def MapsNop(): list<string>
  var mapped = filter(
    ['R', 'H', 'J', 'K', 'L', '|', '_'],
    (_: number, v: string): bool => empty(maparg("\<c-w>" .. v, 'n')))
  for c in mapped
    execute 'nnoremap <c-w>' .. escape(c, '|') .. ' <nop>'
  endfor
  return mapped
enddef

def MapsResize(): list<string>
  var commands = {
    '=': '<ScriptCmd>ResizeFromExpr()<cr>',
    '>': '<ScriptCmd>ResizeWidth(v:count1)<cr>',
    '<': '<ScriptCmd>ResizeWidth(-v:count1)<cr>',
    '+': '<ScriptCmd>ResizeHeight(v:count1)<cr>',
    '-': '<ScriptCmd>ResizeHeight(-v:count1)<cr>',
  }
  var mapped = filter(keys(commands),
    (_: number, v: string): bool => empty(maparg("\<c-w>" .. v, 'n')))
  for c in mapped
    execute 'nnoremap <silent> <c-w>' .. c .. ' ' .. commands[c]
  endfor
  return mapped
enddef

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

# `:help`、`:tag`、`:copen` 等命令使用 `:topleft split` / `:botright split`，
# `:vertical help` 使用 `:vertical topleft split`。它们会把新窗口挂到整个 tab
# 上（或抢占页边距列），而不是在 master 的列组内打开，从而破坏左右页边距。
# 只要发现内容窗口落在了 master 列之外，就关掉它，并从 master 窗口用普通
# `:split` 重新打开其缓冲区，使其回到内容列内。
# Commands such as `:help`, `:tag`, `:copen`, ... use `:topleft split` /
# `:botright split`, and `:vertical help` uses `:vertical topleft split`.
# Those attach the new window to the whole tab (or steal a margin column)
# instead of opening inside the master's column group, which destroys the
# left/right margins.  Whenever a content window shows up outside the master
# column we close it and re-open its buffer as an ordinary `:split` from the
# master window, so it lands back inside the content column.
def ConfineWindows()
  if !exists('#goyo') || !exists('t:goyo_pads')
    return
  endif

  # 用窗口 ID 定位 master，因为 master 窗口里的缓冲区可能已经变了。
  # Locate the master by window id: its buffer may have changed.
  var master_win = win_id2win(t:goyo_winid)
  if master_win <= 0
    master_win = bufwinnr(t:goyo_master)
  endif
  if master_win <= 0
    return
  endif
  var master_buf = winbufnr(master_win)
  # 内容列的左右边界应由两侧 pad 决定，而不是由 master 窗口本身决定——因为
  # master 一旦 :vsplit，它自己的宽度就会变化，不再代表整个内容列。
  # The content column's bounds come from the side pads, not from the master
  # window itself: once the master is `:vsplit`, its own width changes and no
  # longer represents the whole content column.
  var lpad_win = bufwinnr(t:goyo_pads.l)
  var rpad_win = bufwinnr(t:goyo_pads.r)
  var content_left = lpad_win > 0 ? win_screenpos(lpad_win)[1] + winwidth(lpad_win) : 1
  var content_right = rpad_win > 0 ? win_screenpos(rpad_win)[1] - 1 : &columns

  for win in range(1, winnr('$'))
    var buf = winbufnr(win)
    # pad 窗口和 master 窗口是预期存在的，绝不动它们。
    # Pads and the master window are expected; never touch them.
    if buf == t:goyo_pads.t || buf == t:goyo_pads.b
        || buf == t:goyo_pads.l || buf == t:goyo_pads.r
        || win == master_win || buf == master_buf
      continue
    endif

    # 只要窗口**完全落在内容列内**就正常（例如 master 自己 :vsplit 出来的较窄
    # 子窗口）；越出内容列（如 :topleft split 的整屏窗口）才需要修。
    # A window is fine as long as it lies fully inside the content column
    # (e.g. a narrower `:vsplit` child).  Only a window that sticks out of
    # that column (like a full-tab `:topleft split`) needs fixing.
    var win_col = win_screenpos(win)[1]
    if win_col >= content_left && win_col + winwidth(win) - 1 <= content_right
      continue
    endif

    var target = buf
    var view = winsaveview()
    execute ':' .. master_win .. 'wincmd w'
    # 按编号关闭是安全的：此时 `win` 指向的是我们刚离开的那个窗口。
    # Closing by number is safe: `win` refers to the window we just left.
    execute ':' .. win .. 'wincmd c'
    execute 'sbuffer ' .. target
    winrestview(view)
    # 窗口布局已改变，从头重新扫描一次。
    # The window layout changed; re-scan from the start.
    return
  endfor
enddef

def GoyoOn(dim_arg: string)
  var dim = ParseArg(dim_arg)
  if empty(dim)
    return
  endif

  orig_tab = tabpagenr()
  var settings = {
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

  # 记录原 tab 里「即将成为 master」的那个窗口的 ID（tab split 之前）。
  # Remember the id of the window that is about to become the master, before
  # `tab split` duplicates it into the Goyo tab.
  var orig_winid = win_getid()

  # 新建 tab
  # New tab
  tab split

  # 存进 goyo tab 的 t: 命名空间（必须在 tab split 之后赋值）。
  # Store it in the Goyo tab's t: namespace (must be after `tab split`).
  t:goyo_orig_winid = orig_winid
  t:goyo_master = winbufnr(0)
  # 记录 master 窗口的 ID，这样即使用户在 goyo 中 :edit 了别的文件
  # （窗口缓冲区变了）也仍然能定位到它。
  # Remember the master window id so we can still find it after the user
  # :edits another buffer in it (the buffer number alone would be stale).
  t:goyo_winid = win_getid()
  t:goyo_dim = dim
  t:goyo_dim_expr = dim_arg
  t:goyo_pads = {}
  t:goyo_revert = settings
  t:goyo_maps = extend(MapsNop(), MapsResize())
  if has('gui_running')
    t:goyo_revert.guioptions = &guioptions
  endif

  # vim-gitgutter：暂时禁用以避免插件干扰
  # vim-gitgutter: temporarily disable it
  t:goyo_disabled_gitgutter = get(g:, 'gitgutter_enabled', 0)
  if t:goyo_disabled_gitgutter
    execute 'silent! GitGutterDisable'
  endif

  # vim-signify：暂时关闭 signs
  # vim-signify: toggle it off
  t:goyo_disabled_signify = !empty(getbufvar(bufnr(''), 'sy'))
  if t:goyo_disabled_signify
    execute 'silent! SignifyToggle'
  endif

  # vim-airline：暂时关闭状态栏
  # vim-airline: toggle it off
  t:goyo_disabled_airline = exists('#airline')
  if t:goyo_disabled_airline
    execute 'silent! AirlineToggle'
  endif

  # vim-powerline：移除其 augroup
  # vim-powerline: remove its augroup
  t:goyo_disabled_powerline = exists('#PowerlineMain')
  if t:goyo_disabled_powerline
    augroup PowerlineMain
      autocmd!
    augroup END
    augroup! PowerlineMain
  endif

  # lightline.vim：暂时禁用
  # lightline.vim: disable it
  t:goyo_disabled_lightline = exists('#lightline')
  if t:goyo_disabled_lightline
    silent! call lightline#disable()
  endif

  HideLinenr()
  # 全局选项
  # Global options
  &winheight = max([&winminheight, 1])
  set winminheight=1
  set winheight=1
  set winminwidth=1 winwidth=1
  set laststatus=0
  set showtabline=0
  set noruler
  set fillchars+=vert:\
  set fillchars+=stl:\
  set fillchars+=stlnc:\
  set sidescroll=1
  set sidescrolloff=0

  # 隐藏左侧滚动条
  # Hide left-hand scrollbars
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
    autocmd TabLeave    * ++nested GoyoOff()
    autocmd VimResized  *      ResizePads()
    autocmd ColorScheme *      Tranquilize()
    autocmd BufWinEnter *      HideLinenr() | HideStatusline()
    # 让 `:help`、tag 跳转、`:copen` 等打开的窗口留在内容列内，避免丢失页边距。
    # Keep windows opened by `:help`, tag jumps, `:copen`, ... inside the
    # content column so the margins are not lost.
    autocmd BufWinEnter *      ConfineWindows()
    autocmd WinEnter,WinLeave * HideStatusline()
    if has('nvim')
      autocmd TermClose * call feedkeys("\<plug>(goyo-resize)")
    endif
  augroup END

  HideStatusline()
  if exists('g:goyo_callbacks[0]')
    g:goyo_callbacks[0]()
  endif
  if exists('#User#GoyoEnter')
    doautocmd User GoyoEnter
  endif
enddef

def GoyoOff()
  if !exists('#goyo')
    return
  endif

  # 不是这个 tab，直接返回
  # Oops, not this tab
  if !exists('t:goyo_revert')
    return
  endif

  # 清除自动命令
  # Clear auto commands
  augroup goyo
    autocmd!
  augroup END
  augroup! goyo
  augroup goyop
    autocmd!
  augroup END
  augroup! goyop

  for c in t:goyo_maps
    execute 'nunmap <c-w>' .. escape(c, '|')
  endfor

  var goyo_revert             = t:goyo_revert
  var goyo_disabled_gitgutter = t:goyo_disabled_gitgutter
  var goyo_disabled_signify   = t:goyo_disabled_signify
  var goyo_disabled_airline   = t:goyo_disabled_airline
  var goyo_disabled_powerline = t:goyo_disabled_powerline
  var goyo_disabled_lightline = t:goyo_disabled_lightline
  # 记录原 tab 的 master 窗口（进入 goyo 前那个），退出后要把 goyo 里的
  # 内容窗口布局搬回它所在的位置。
  # Remember the original tab's master window; on exit the Goyo content-window
  # layout is transplanted back onto it.
  var orig_winid = t:goyo_orig_winid

  # 采集 goyo tab 中所有「内容窗口」（非 pad）：缓冲区、光标、屏幕位置。
  # Collect every content window (non-pad) in the Goyo tab.
  var content: list<dict<any>> = []
  for win in range(1, winnr('$'))
    var buf = winbufnr(win)
    if buf == t:goyo_pads.t || buf == t:goyo_pads.b
        || buf == t:goyo_pads.l || buf == t:goyo_pads.r
      continue
    endif
    var wid = win_getid(win)
    var pos = win_screenpos(win)
    content->add({
      'buf':    buf,
      'lnum':   getcurpos(wid)[1],
      'col':    getcurpos(wid)[2],
      'row':    pos[0],
      'col_pos': pos[1],
    })
  endfor
  # 按屏幕位置（先上下后左右）排序，保证重建时的相对顺序。
  # Sort by screen position so the rebuilt layout keeps the same order.
  content->sort((a, b) => a.row != b.row ? a.row - b.row : a.col_pos - b.col_pos)

  var goyo_tab = tabpagenr()

  # 先把 goyo tab 的每个内容窗口记好，再回到原 tab 重建。
  # Go back to the original tab and transplant the layout.
  execute ':' .. orig_tab .. 'normal! gt'
  if orig_winid > 0 && win_id2win(orig_winid) > 0
    win_gotoid(orig_winid)
  endif

  if !empty(content)
    # 第一个内容窗口直接占用原 tab 的 master 窗口。
    # The first content window takes over the original master window.
    if winbufnr(0) != content[0].buf && bufexists(content[0].buf)
      execute 'buffer ' .. content[0].buf
    endif
    execute ':' .. printf('normal! %dG%d|', content[0].lnum, content[0].col)

    # 其余内容窗口依次重建为分屏：上下方向用水平分割，左右方向用垂直分割。
    # Re-create the remaining content windows as splits.
    var base_row = content[0].row
    var base_col_pos = content[0].col_pos
    for i in range(1, len(content) - 1)
      var item = content[i]
      var cmd = ''
      if item.col_pos > base_col_pos
        cmd = 'rightbelow vertical split'
      elseif item.col_pos < base_col_pos
        cmd = 'leftabove vertical split'
      elseif item.row >= base_row
        cmd = 'belowright split'
      else
        cmd = 'aboveleft split'
      endif
      execute cmd
      if bufexists(item.buf)
        execute 'buffer ' .. item.buf
      endif
      execute ':' .. printf('normal! %dG%d|', item.lnum, item.col)
    endfor
  endif

  # 关闭 goyo tab（按当时记录的编号）。
  # Close the Goyo tab (by the number recorded before switching away).
  if goyo_tab != tabpagenr() && goyo_tab <= tabpagenr('$')
    execute ':' .. goyo_tab .. 'tabclose'
  elseif tabpagenr() == 1 && tabpagenr('$') == 1 && goyo_tab == tabpagenr()
    # 兜底：goyo tab 就是当前 tab（理论上不会发生）。
    # Fallback: should not normally happen.
    tabclose
  endif

  var wmw = remove(goyo_revert, 'winminwidth')
  var ww  = remove(goyo_revert, 'winwidth')
  &winwidth    = ww
  &winminwidth = wmw
  var wmh = remove(goyo_revert, 'winminheight')
  var wh  = remove(goyo_revert, 'winheight')
  &winheight    = max([wmh, 1])
  &winminheight = wmh
  &winheight    = wh

  for [k, v] in items(goyo_revert)
    RestoreOption(k, v)
  endfor
  execute 'colo ' .. get(g:, 'colors_name', 'default')

  if goyo_disabled_gitgutter
    execute 'silent! GitGutterEnable'
  endif

  if goyo_disabled_signify
    if !get(b:, 'sy', {}).get('active', 0)
      execute 'silent! SignifyToggle'
    endif
  endif

  if goyo_disabled_airline && !exists('#airline')
    execute 'silent! AirlineToggle'
    # 不知为何，Airline 需要刷新两次才能避免显示残影。
    # For some reason, Airline requires two refreshes to avoid display
    # artifacts
    silent! execute 'AirlineRefresh'
    silent! execute 'AirlineRefresh'
  endif

  if goyo_disabled_powerline && !exists('#PowerlineMain')
    doautocmd PowerlineStartup VimEnter
    silent! execute 'PowerlineReloadColorscheme'
  endif

  if goyo_disabled_lightline
    silent! call lightline#enable()
  endif

  if exists('#Powerline')
    doautocmd Powerline ColorScheme
  endif

  if exists('g:goyo_callbacks[1]')
    g:goyo_callbacks[1]()
  endif
  if exists('#User#GoyoLeave')
    doautocmd User GoyoLeave
  endif
enddef

# Vim9script 禁止 `:let &opt = value`，因此通过 `:set` 还原选项。
# Vim9script forbids `:let &opt = value`, so restore options through `:set`.
def RestoreOption(name: string, value: any)
  execute RawOptionCmd(name, value)
enddef

def RawOptionCmd(name: string, value: any): string
  if type(value) == v:t_bool
    return 'set ' .. (value ? '' : 'no') .. name
  elseif type(value) == v:t_string
    # 转义会截断或改变 `:set` 参数含义的字符。
    # Escape characters that terminate or alter a `:set` argument.
    return 'set ' .. name .. '=' .. escape(value, " \t|\\\"")
  endif
  return 'set ' .. name .. '=' .. string(value)
enddef

# 既接受字符串（可以以 '%' 结尾）也接受数字，与原版无类型时的行为一致
# （那时 `str2nr()` 会愉快地接受数字）。
# Accepts either a string (possibly ending in '%') or a number, mirroring the
# untyped original where `str2nr()` was happy to coerce numbers.
def Relsz(expr: any, limit: number): number
  # 注意：`string()` 会给参数加引号，因此只对真正的数字做转换。
  # NB: `string()` quotes its argument, so only convert actual numbers.
  var e = type(expr) == v:t_string ? expr : string(expr)
  if e !~ '%$'
    return str2nr(e)
  endif
  return limit * str2nr(e[: -2]) / 100
enddef

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

  var dim = {
    'width':  Relsz(get(g:, 'goyo_width', 80), &columns),
    'height': height,
    'xoff':   0,
    'yoff':   yoff,
  }
  if empty(arg)
    return dim
  endif
  var parts = matchlist(arg, '^\s*\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\%(x\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\)\?\s*$')
  if empty(parts)
    echohl WarningMsg
    echo 'Invalid dimension expression: ' .. arg
    echohl None
    return {}
  endif
  if !empty(parts[1]) | dim.width  = Relsz(parts[1], &columns) | endif
  if !empty(parts[2]) | dim.xoff   = Relsz(parts[2], &columns) | endif
  if !empty(parts[3]) | dim.height = Relsz(parts[3], &lines)   | endif
  if !empty(parts[4]) | dim.yoff   = Relsz(parts[4], &lines)   | endif
  return dim
enddef

# 公开入口。放在 `autoload/zen/goyo.vim` 时名字是 `zen#goyo#Execute`；如果安
# 装为 `autoload/goyo.vim`，导出名会是 `goyo#Execute`，可直接替代上游插件。
# Public entry point.  In an `autoload/zen/goyo.vim` file this becomes
# `zen#goyo#Execute`.  If you install it as `autoload/goyo.vim`, the exported
# name resolves to `goyo#Execute` and is a drop-in for the upstream plugin.
export def Execute(bang: bool, dim: string)
  if bang
    if exists('#goyo')
      GoyoOff()
    endif
  else
    if exists('#goyo') == 0
      GoyoOn(dim)
    elseif !empty(dim)
      if winnr('$') < 5
        GoyoOff()
        Execute(bang, dim)
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
  endif
enddef

# ---------------------------------------------------------------------------
# <Plug> 映射。原版用 `:call <sid>fn()`；Vim9script 下改用 `<ScriptCmd>`
# 直接调用脚本内函数。
# <Plug> mappings.  The original used `:call <sid>fn()`; under Vim9script
# `<ScriptCmd>` invokes the script-local functions directly.
# ---------------------------------------------------------------------------
nnoremap <silent> <Plug>(goyo-off) <ScriptCmd>GoyoOff()<cr>
nnoremap <silent> <plug>(goyo-resize) <ScriptCmd>ResizePads()<cr>
