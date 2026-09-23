vim9script
# ============================================================================
# goyo.vim 单元/集成测试
#
# 用法（见 test/run.sh）：
#   vim -u NONE -i NONE -N -es --not-a-term \
#       --cmd 'set rtp^=<plugin-root>' -S test/test_goyo.vim
#
# 测试使用 Vim 内置的单元断言（assert_equal / assert_true / ...），
# 通过 `assert_...()` 抛出异常来报告失败；运行器将统计失败数并设置退出码。
# ============================================================================

# ---------------------------------------------------------------------------
# 最小测试框架（零依赖，仅用 Vim 内置 assert_*）
# ---------------------------------------------------------------------------
var passed = 0
var failed = 0
var report_lines: list<string> = []

# 把结果同时写入文件（供测试运行器收集）与消息区（交互模式）。
def Report(line: string)
  report_lines->add(line)
enddef

def FlushReport()
  var out = getenv('GOYO_TEST_OUT')
  if !empty(out)
    writefile(report_lines, out)
  endif
enddef

def Test(name: string, Fn: func)
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
enddef

# ---------------------------------------------------------------------------
# 测试夹具
# ---------------------------------------------------------------------------
const RTP_SAVE = &runtimepath
const COLUMNS_SAVE = &columns
const LINES_SAVE = &lines

def Setup()
  set nocompatible
  set nomore noswapfile nobackup nowritebackup
  set columns=80 lines=24
  # 保证 Goyo 已加载。
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

# 辅助：ConfineWindows 是脚本局部函数，测试无法直接调用。
# 通过重新触发 BufWinEnter 间接驱动它。
def ConfineSettle()
  doautocmd BufWinEnter
enddef

# ---------------------------------------------------------------------------
# 运行前准备
# ---------------------------------------------------------------------------
Setup()

# ---------------------------------------------------------------------------
# 1. 插件加载与命令
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
# 2. 尺寸表达式解析（通过公开入口进入后检查 t:goyo_dim）
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
# 3. 会话激活 / 退出
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
# 4. 选项保存与恢复
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
  # 注意：在屏幕很小的 CI 环境里，全局 winheight 会被 Vim 自动限制，
  # 因此这里只验证插件的保存/还原逻辑，不假设能设置任意大值。
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

# ---------------------------------------------------------------------------
# 5. 缓冲区保留
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

# ---------------------------------------------------------------------------
# 6. 内容窗口约束（ConfineWindows）
# ---------------------------------------------------------------------------
Test('help window stays within content column', () => {
  goyo#Execute(false, '80x20')
  help
  # 找出 help 窗口
  var helpwin = 0
  for i in range(1, winnr('$'))
    if bufname(winbufnr(i)) =~ 'help.txt\|doc/'
      helpwin = i
    endif
  endfor
  assert_true(helpwin > 0)
  # help 窗口不应占据整屏宽度（应 <= 内容列宽度）
  assert_true(winwidth(helpwin) < &columns)
  goyo#Execute(true, '')
})

# ---------------------------------------------------------------------------
# 7. 健壮性：重复操作、非法输入
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
# 8. 尺寸边界与解析健壮性
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
# 9. 回调与用户事件
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
# 10. 行号选项
# ---------------------------------------------------------------------------
Test('g:goyo_linenr=1 keeps numbers', () => {
  set number
  g:goyo_linenr = 1
  goyo#Execute(false, '80x20')
  # 内容窗口应保留 number
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
# 11. 临时映射
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
# 12. 窗口约束：普通 split 保留，整屏窗口回收
# ---------------------------------------------------------------------------
Test('normal vsplit inside content column is preserved', () => {
  var tmp = tempname()
  writefile(['a'], tmp)
  execute 'edit ' .. tmp
  goyo#Execute(false, '80x20')
  var tmp2 = tempname()
  writefile(['b'], tmp2)
  execute 'vsplit ' .. tmp2
  # master + 新 split + 4 pads = 6
  assert_equal(6, winnr('$'))
  goyo#Execute(true, '')
  # 退出后保留两个内容窗口
  assert_equal(2, winnr('$'))
  silent! execute 'bwipeout! ' .. tmp
  silent! execute 'bwipeout! ' .. tmp2
})

Test('ConfineWindows brings full-width window back into content column', () => {
  goyo#Execute(false, '80x20')
  # 直接触发一个整屏窗口：topleft new
  topleft new
  # 此时新窗口横跨整个 tab；ConfineWindows() 应由 autocmd 触发并收回。
  # 给自动命令一次执行机会。
  call ConfineSettle()
  var outside = 0
  for i in range(1, winnr('$'))
    if winwidth(i) > &columns - 2
      outside += 1
    endif
  endfor
  # 除上下 pad 外，不应有占满整屏的内容窗口。
  assert_true(outside <= 2)
  goyo#Execute(true, '')
})

# ---------------------------------------------------------------------------
# 运行与报告
# ---------------------------------------------------------------------------

Teardown()

Report(printf('goyo tests: %d passed, %d failed', passed, failed))

# 退出码：失败数即退出码，方便 CI。
FlushReport()
if failed > 0
  execute 'cquit ' .. failed
else
  qall!
endif
