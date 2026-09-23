vim9script noclear

# goyo.vim: Distraction-free writing mode
#
# Maintainer:   goyo.vim fork contributors
# Last Change:  2026 Sep 23
# License:      MIT (see LICENSE)
#
# The implementation lives in autoload/goyo.vim; this file only defines the
# user-facing command and mappings, following the conventions used by Vim's
# bundled plugins (see :help package-create and plugin/helpcurwin.vim).

# Vim 9.1.0000 is the first version with the Vim9script features used here
# (import autoload, typed export def, <ScriptCmd>).  See :help vim9-mix.
if !has('patch-9.1.0000')
  echohl ErrorMsg
  echomsg 'goyo: this plugin requires Vim 9.1.0000 or newer (Vim9script)'
  echohl None
  finish
endif

import autoload '../autoload/goyo.vim'

# :Goyo [dimensions]
#   :Goyo           Enter Goyo; run again to leave.
#   :Goyo 80x20     Enter with a content area of 80 columns by 20 lines.
#   :Goyo 50%x70%   Percentages are also accepted.
#   :Goyo!          Force leaving.
#
# The completion function must be referenced as goyo#Complete: the
# -complete=customlist option only accepts the legacy autoload name, not the
# imported namespace (goyo.Complete).
command! -nargs=* -bang -bar -complete=customlist,goyo#Complete Goyo
      \ goyo.Execute(<bang>0, <q-args>)

# <Plug> mappings so users can bind keys without this plugin doing it.
nnoremap <silent> <Plug>(goyo-off) <ScriptCmd>goyo.Close()<CR>
nnoremap <silent> <Plug>(goyo-resize) <ScriptCmd>goyo.Resize()<CR>

# vim: ts=8 sts=2 sw=2 et:
