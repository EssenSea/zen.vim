vim9script
# ===========================================================================
# goyo.vim — 分心/免打扰写作模式（Distraction-free writing）
#
# 本文件是 goyo.vim 的 Vim9script 实现，位于 autoload/goyo.vim：
#   * plugin/goyo.vim 负责定义 :Goyo 命令与文档入口；
#   * 本文件只导出 goyo#Execute()，由命令层调用。
#
# 本实现相对上游（legacy script）在以下方面遵循 Vim 自身代码规范：
#   * 使用 `def` + 类型标注；用 `<ScriptCmd>`/`:k` 替代 `<sid>`；
#   * 用 `set`/`&opt` 赋值，而非 `execute 'let &opt = ...'`；
#   * 用 `autocmd` 的 augroup 精确管理生命周期；
#   * 会话状态集中在 `t:goyo_*`，退出时严格还原。
#
# VIM9 说明 / Vim9 notes:
#   * `def` 函数内的 `:set` 通过辅助函数执行，避免动态 `execute` 里的选项
#     解析歧义；
#   * 字符串回调统一改为 lambda，避免 legacy `map()`/`filter()` 的字符串形式。
# ===========================================================================

# ---------------------------------------------------------------------------
# 会话状态（存放在 tab 局部变量中）
#   t:goyo_dict     会话总状态字典（见 NewSession()）
#   t:goyo_pads     四个填充窗口 {l,r,t,b} 的缓冲区号
#   t:goyo_dim      几何尺寸 {width,height,xoff,yoff}
# 其余兼容变量：t:goyo_master / t:goyo_winid / t:goyo_orig_winid 等。
# ---------------------------------------------------------------------------

const PAD_BUF_OPTS: string = 'buftype=nofile bufhidden=wipe nomodifiable '
  .. 'nobuflisted noswapfile nonumber nocursorline nocursorcolumn '
  .. 'winfixwidth winfixheight nowrap'

# ---------------------------------------------------------------------------
# 小工具 / Helpers
# ---------------------------------------------------------------------------

# 将 val 限制在 [min, max] 区间。
def Clamp(val: number, minv: number, maxv: number): number
  return min([max([val, minv]), maxv])
enddef

# 读取高亮组的属性。synIDattr() 在 Vim 下可能返回数字（-1），在 GVim 下返回
# 字符串（'' 或 '#rrggbb'），语义依属性而定。
def Highlight(group: string, attr: string): any
  return synIDattr(synIDtrans(hlID(group)), attr)
enddef

# 设置高亮。gui 与 cterm 自动选择。
def SetHighlight(group: string, attr: string, color: string)
  var use_gui = has('gui_running') || (has('termguicolors') && &termguicolors)
  execute printf('highlight %s %s%s=%s', group, use_gui ? 'gui' : 'cterm', attr, color)
enddef

# 通过 `:set` 还原选项，避免 Vim9 对 `:let &opt =` 的限制。
# 字符串需要转义会终止/改变 `:set` 语义的字符。
def RestoreOption(name: string, value: any)
  if type(value) == v:t_bool
    execute 'set ' .. (value ? '' : 'no') .. name
  elseif type(value) == v:t_number
    execute 'set ' .. name .. '=' .. value
  elseif type(value) == v:t_string
    execute 'set ' .. name .. '=' .. escape(value, " \t|\\\"")
  endif
enddef

# 解析尺寸表达式：接受数字（相对行/列数）或 'N%'（相对百分比）。
# 既接受字符串也接受数字，保持与上游一致的宽容度。
def Relsz(expr: any, limit: number): number
  var e = type(expr) == v:t_string ? expr : string(expr)
  if e !~ '%$'
    return str2nr(e)
  endif
  return limit * str2nr(e[: -2]) / 100
enddef

# 隐藏状态栏：既隐藏窗口 statusline，也清空自身。
def HideStatusline()
  setlocal statusline=\ 
enddef

# 隐藏行号/相对行号/colorcolumn。仅在用户未显式要求显示行号时。
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
# 映射管理：记录我们覆盖的 <C-w> 键，退出时精确还原。
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
  # 命令表：键 -> ScriptCmd 调用。
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
# 填充窗口（pad）
# ---------------------------------------------------------------------------

# 在当前窗口上创建一个填充缓冲区，并返回其缓冲区号。
# 调用后光标会回到进入前的窗口（winnr('#')）。
def InitPad(command: string): number
  execute command

  # 一次性设置所有本地选项，减少 :set 调用次数。
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

# 调整指定 pad 缓冲区所在窗口的尺寸，并绑定「越界即退出」的自动命令。
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

  # 清空缓冲区内容；必要时填充空行以隐藏滚动条。
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

# 光标越界时把焦点弹回内容窗口。
def Blank(repel: string)
  var pads = get(t:, 'goyo_pads', {})
  if bufwinnr(pads.r) <= bufwinnr(pads.l) + 1
      || bufwinnr(pads.b) <= bufwinnr(pads.t) + 3
    execute 'silent! call feedkeys("\<Plug>(goyo-off)")'
  endif
  execute 'noautocmd wincmd ' .. repel
enddef

# 在 pad 窗口内绘制 ASCII 装饰。
def Decorate()
  var save_scroll = getcurpos()[1]
  var win_width = winwidth(0)
  var win_height = winheight(0)
  if win_width <= 0 || win_height <= 0
    return
  endif

  var elements: list<string> = get(g:, 'goyo_decoration_elements', ['~'])
  # 过滤空元素，避免网格宽度为 0 导致除零。
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

  # 一次性构造所有行，减少 append() 调用。
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
# 尺寸计算
# ---------------------------------------------------------------------------

# 把 'N' / 'N%' / '+N' / '-N' 形式的表达式解析成会话尺寸字典。
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

  # 语法：{width}[{+/-xoff}]x{height}[{+/-yoff}]
  # 宽度/高度各自可为绝对值、百分比或（当省略时为）默认值。
  # 捕获组：1=width, 2=xoff, 3=height, 4=yoff
  var parts = matchlist(arg,
    '^\s*'
    .. '\([+-]\?[0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?'
    .. '\%(x'
    .. '\([+-]\?[0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?'
    .. '\)\?'
    .. '\s*$')
  if empty(parts)
    echohl WarningMsg
    echomsg 'goyo: invalid dimension expression: ' .. arg
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
# 布局
# ---------------------------------------------------------------------------

# 调整四个 pad 的尺寸，使内容窗口获得请求的几何尺寸。
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

# 按表达式重新计算尺寸（<C-w>=）。
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
# 颜色
# ---------------------------------------------------------------------------

# 让非内容元素融入背景色，营造「无干扰」效果。
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
# 内容窗口约束（keep :help / :copen / tag jumps inside the content column）
# ---------------------------------------------------------------------------

# 返回内容列的水平边界 [left, right]。
def ContentBounds(): list<number>
  var lpad = bufwinnr(t:goyo_pads.l)
  var rpad = bufwinnr(t:goyo_pads.r)
  var left = lpad > 0 ? win_screenpos(lpad)[1] + winwidth(lpad) : 1
  var right = rpad > 0 ? win_screenpos(rpad)[1] - 1 : &columns
  return [left, right]
enddef

# 定位 master 窗口号；优先用窗口 ID（缓冲区可能已变），失败则退回缓冲号。
def MasterWin(): number
  var win = win_id2win(t:goyo_winid)
  if win > 0
    return win
  endif
  return bufwinnr(t:goyo_master)
enddef

# 若某个内容窗口整块越出内容列（如 :topleft split），把它收回到 master
# 所在列组。每次只处理一个窗口，由 BufWinEnter 再次触发以处理其余窗口，
# 避免在遍历中改变窗口布局导致索引失效。
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

    # 越界：关闭并按普通 split 从 master 重新打开，回到内容列内。
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
# 打开 / 关闭
# ---------------------------------------------------------------------------

# 记录可能被 Goyo 干扰的插件状态，退出时恢复。
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
    # Airline 需要刷新两次才能避免残影（上游已知问题）。
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

# 收集进入前需要保存并恢复的全局选项。
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
  # winwidth 必须 >= winminwidth，winheight 必须 >= winminheight。
  # 因此还原顺序为：先把当前值放大到足以容纳目标 min，再设 min，最后设目标值，
  # 否则会出现 "E592/E591: cannot be smaller than ..."。
  var wmw = remove(revert, 'winminwidth')
  var ww  = remove(revert, 'winwidth')
  var wmh = remove(revert, 'winminheight')
  var wh  = remove(revert, 'winheight')

  # 1) 先把当前值放大到足以容纳目标下限。
  &winwidth = Clamp(max([wmw, ww, &winwidth]), 1, &columns)
  &winheight = Clamp(max([wmh, wh, &winheight]), 1, &lines)
  # 2) 设置下限；受当前 winwidth/winheight 约束，避免窗口数不足时
  #    被 Vim 自动 clamp 后触发 E591/E592。
  &winminwidth = Clamp(wmw, 1, &winwidth)
  &winminheight = Clamp(wmh, 1, &winheight)
  # 3) 设置目标值，并夹在 [min, 上限] 之间。
  &winwidth = Clamp(max([wmw, ww]), &winminwidth, &columns)
  &winheight = Clamp(max([wmh, wh]), &winminheight, &lines)

  for [k, v] in items(revert)
    RestoreOption(k, v)
  endfor
enddef

# 打开 Goyo。
# BufWinEnter / WinEnter 时刷新本会话窗口的界面并约束越界窗口。
# 只在当前 tab 属于 Goyo 会话时生效，避免影响其它 tab。
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

  # tab split：复制当前 tab，以便在独立 tab 中改造布局；退出时关闭它。
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

  # 全局选项：让所有窗口尽可能小，以便 pad 精确控制尺寸。
  # 顺序：必须先降低 *_minheight/*_minwidth，再把 winheight/winwidth 设为 1，
  # 否则原 min 较大且窗口数不足时，Vim 会拒绝或自动 clamp 并报 E591/E592。
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
    # 仅在本 tab 的窗口上生效；ConfineWindows() 负责把越界窗口收回内容列。
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

# 关闭 Goyo，并把 Goyo tab 的内容窗口布局恢复到原 tab。
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

  # 采集所有内容窗口的缓冲区/光标/屏幕位置。
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

  # 回到原 tab / 原窗口，并把布局搬过去。
  # 优先按原窗口 ID 定位其所在 tab（tab 编号可能已变）；否则回退到记录值。
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

  # 关闭 Goyo tab。
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

# 判断会话是否激活。
export def IsActive(): bool
  return exists('#goyo')
enddef

# 公开入口，由 plugin/goyo.vim 的 :Goyo 命令调用。
#   bang 为真：强制关闭。
#   dim 非空：以给定尺寸/表达式进入或调整尺寸。
export def Execute(bang: bool, dim: string)
  if bang
    GoyoOff()
    return
  endif
  if !IsActive()
    GoyoOn(dim)
  elseif !empty(dim)
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

# ---------------------------------------------------------------------------
# 命令补全
# ---------------------------------------------------------------------------

# :Goyo 的尺寸参数补全。
export def Complete(arglead: string, cmdline: string, _cursorpos: number): list<string>
  if cmdline =~ '\s\S*$'
    return ['80', '100', '120', '50%', '60%', '80x24', '50%x70%', '120x30']
  endif
  return []
enddef

# 供 Blank()/其他函数访问当前 tab 的 pads（缺失时回退到空 dict）。
export def GoyoPads(): dict<number>
  return get(t:, 'goyo_pads', {})
enddef

# ---------------------------------------------------------------------------
# <Plug> 映射（供用户映射，不直接绑键）。
# ---------------------------------------------------------------------------
nnoremap <silent> <Plug>(goyo-off) <ScriptCmd>GoyoOff()<CR>
nnoremap <silent> <Plug>(goyo-resize) <ScriptCmd>ResizePads()<CR>
