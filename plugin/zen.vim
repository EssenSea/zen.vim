vim9script noclear

# zen.vim: Distraction-free writing mode
#
# Maintainer:   zen.vim fork contributors
# Last Change:  2026 Sep 23
# License:      MIT (see LICENSE)
#
# The implementation lives in autoload/zen.vim; this file only defines the
# user-facing command and mappings, following the conventions used by Vim's
# bundled plugins (see :help package-create and plugin/helpcurwin.vim).

# Vim 9.1.0000 is the first version with the Vim9script features used here
# (import autoload, typed export def, <ScriptCmd>).  See :help vim9-mix.
if !has('patch-9.1.0000')
  echohl ErrorMsg
  echomsg 'zen: this plugin requires Vim 9.1.0000 or newer (Vim9script)'
  echohl None
  finish
endif

import autoload '../autoload/zen.vim'

# :Zen [dimensions]
#   :Zen           Enter Zen; run again to leave.
#   :Zen 80x20     Enter with a content area of 80 columns by 20 lines.
#   :Zen 50%x70%   Percentages are also accepted.
#   :Zen!          Force leaving.
#
# The completion function must be referenced as zen#Complete: the
# -complete=customlist option only accepts the legacy autoload name, not the
# imported namespace (zen.Complete).
command! -nargs=* -bang -bar -complete=customlist,zen#Complete Zen
      \ zen.Execute(<bang>0, <q-args>)

# <Plug> mappings so users can bind keys without this plugin doing it.
nnoremap <silent> <Plug>(zen-off) <ScriptCmd>zen.Close()<CR>
nnoremap <silent> <Plug>(zen-resize) <ScriptCmd>zen.Resize()<CR>

# vim: ts=8 sts=2 sw=2 et:
