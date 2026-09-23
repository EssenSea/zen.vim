" zen.vim: Distraction-free writing mode
"
" Maintainer:   zen.vim fork contributors
" Last Change:  2026 Sep 23
" License:      MIT (see LICENSE)
"
" ===========================================================================
" LLM POWERED
"
" This plugin was developed with assistance from DeepSeek V4.1 and the
" DeepSeek harness.  Parts of the code, tests and documentation were
" produced or reviewed by that large language model; review them with the
" usual care before relying on them.
" ===========================================================================
"
" The implementation lives in autoload/zen.vim; this file only defines the
" user-facing commands and <Plug> mappings, following the conventions used by
" Vim's bundled plugins (see :help package-create and plugin/helpcurwin.vim).
"
" This file uses the vim9-mix layout (see :help vim9-mix): the version check
" below is legacy Vim script so that an older Vim, which does not understand
" :vim9script, exits cleanly instead of reporting an error.  Everything after
" the :vim9script command is Vim9 script.

" zen.vim needs Vim 9.1.1652: import autoload, typed export def, <ScriptCmd>,
" Vim9script in general, and the features used by the implementation such as
" gettext()/bindtextdomain() (9.1.0509) and 'winfixbuf' (9.1.0147).  See
" doc/zen.txt (Requirements).
if !has('patch-9.1.1652')
  if !get(g:, 'zen_disable_legacy_warning', 0)
    echohl WarningMsg
    echomsg 'zen.vim needs Vim 9.1.1652 or newer; the plugin is not loaded'
    echohl None
  endif
  finish
endif

vim9script noclear

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
