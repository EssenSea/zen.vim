" ============================================================================
" goyo.vim — 无干扰写作模式
" 插件加载层：定义 :Goyo 命令并做版本守卫。实际实现在 autoload/goyo.vim。
"
" Maintainer:  see doc/goyo.txt
" License:     see doc/goyo.txt
" ============================================================================

if exists('g:loaded_goyo')
  finish
endif
let g:loaded_goyo = 1

" autoload/goyo.vim 使用 Vim9script，要求 Vim 支持 +vim9script。
if !has('vim9script')
  echohl ErrorMsg
  echomsg 'goyo: this plugin requires Vim with +vim9script (Vim 9.1.0000 or newer)'
  echohl None
  finish
endif

" :Goyo [dimensions]
"   :Goyo           进入 Goyo；再次执行则退出。
"   :Goyo 80x20     以 80 列、20 行进入。
"   :Goyo 50%x70%   以百分比进入。
"   :Goyo!          强制退出。
"
" 注意：命令体必须使用 :call，否则 Vim 不会自动加载 autoload 函数。
command! -nargs=* -bang -bar -complete=customlist,goyo#Complete Goyo
      \ call goyo#Execute(<bang>0, <q-args>)
