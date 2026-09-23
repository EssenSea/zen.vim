vim9script noclear

# zen.vim: Distraction-free writing mode
#
# Maintainer:   zen.vim fork contributors
# Last Change:  2026 Sep 23
# License:      MIT (see LICENSE)
#
# The implementation lives in autoload/zen.vim; this file only defines the
# user-facing commands and <Plug> mappings, following the conventions used by
# Vim's bundled plugins (see :help package-create and plugin/helpcurwin.vim).

# Vim 9.1.0000 provides the Vim9script features used here (import autoload,
# typed export def, <ScriptCmd>, WinResized).  See :help vim9-mix.
if !has('patch-9.1.0000')
  echohl ErrorMsg
  echomsg 'zen: this plugin requires Vim 9.1.0000 or newer (Vim9script)'
  echohl None
  finish
endif

import autoload '../autoload/zen.vim'

# :Zen [dimensions]
#   :Zen           Toggle: enter Zen, or leave when it is already active.
#   :Zen 80x20     Open with a content area of 80 columns by 20 lines.
#   :Zen 50%x70%   Percentages are also accepted.
#   :Zen!          Leave unconditionally.
#
# The completion function must be referenced as zen#Complete: the
# -complete=customlist option only accepts the legacy autoload name, not the
# imported namespace (zen.Complete).
command! -nargs=* -bang -bar -complete=customlist,zen#Complete Zen
      \ expand('<bang>') ==# '!' ? zen.Close()
      \ : empty(<q-args>) ? zen.Toggle()
      \ : zen.Open(<q-args>)

# <Plug> mappings so users can bind keys without this plugin doing anything by
# itself.  They mirror the public API: open, close and toggle.
nnoremap <silent> <Plug>(zen-open) <ScriptCmd>zen.Open()<CR>
nnoremap <silent> <Plug>(zen-close) <ScriptCmd>zen.Close()<CR>
nnoremap <silent> <Plug>(zen-toggle) <ScriptCmd>zen.Toggle()<CR>
# <Plug>(zen-off) is kept as an alias of close for earlier configurations.
nnoremap <silent> <Plug>(zen-off) <ScriptCmd>zen.Close()<CR>

# vim: ts=8 sts=2 sw=2 et:
