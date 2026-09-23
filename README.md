# goyo.vim

Distraction-free writing mode for Vim — 无干扰写作模式。

This repository is a fork of [goyo.vim](https://github.com/junegunn/goyo.vim)
that rewrites the implementation in **Vim9script** and organises the project
as a standard Vim package, following the conventions used by Vim's bundled
plugins (`:help package-create`).

## Features

- The content window is centred; the surrounding space is filled with
  automatically sized padding windows.
- The status line, line numbers and color column are hidden while active.
- Content size can be given as columns, percentages or offsets.
- Windows opened by `:help`, `:tag`, `:copen`, … are kept inside the content
  column instead of destroying the margins.
- The buffer shown in the master window is preserved on exit.
- All touched options and mappings are restored exactly on exit.
- User messages are translatable through `gettext()`
  (`:help package-translation`).

## Requirements

- Vim **9.1.0000+** built with `+vim9script`.
- Optional translations need `+multi_lang`.

## Installation

Add the repository to `'runtimepath'`, or install it as a package:

```vim
" option A: plain runtimepath
set runtimepath+=/path/to/goyo.vim

" option B: as a package (recommended for :packadd)
"   ~/.vim/pack/goyo/start/goyo/  <- clone here
packadd goyo
```

`plugin/goyo.vim` defines the `:Goyo` command at startup.

## Usage

```vim
:Goyo            " enter; run again to leave
:Goyo 80x20      " 80 columns by 20 lines
:Goyo 50%x70%    " percentages
:Goyo!           " force leave
```

See `:help goyo` for the full manual.

## Layout

```
plugin/goyo.vim          loads the plugin, defines :Goyo and <Plug> mappings
autoload/goyo.vim        the implementation (Vim9script, exported API)
doc/goyo.txt             help file
doc/goyo-internals.txt   notes on the built-in mechanisms used
doc/tags                 help tags (regenerate with :helptags doc)
lang/                    gettext catalogues (goyo.pot, <lang>/LC_MESSAGES/goyo.mo)
test/test_goyo.vim       test suite
test/conformance.sh      package-convention checks
test/run.sh              test runner
Makefile                 common tasks
```

## Development

```sh
make test        # run the suite with Vim
make test-nvim   # run with Neovim (skipped if it lacks Vim9script)
make tags        # regenerate doc/tags
make lint        # load the plugin to catch compile errors
```

The tests use Vim's built-in `assert_*()` functions and report the number of
failures as the exit status.  See `CONTRIBUTING.md`.

## Translation

The catalogue template is `lang/goyo.pot`.  To add a language, create
`lang/<lang_id>/LC_MESSAGES/goyo.po`, translate it and compile it with
`msgfmt -o goyo.mo goyo.po`.  See `:help package-translation`.

## License

MIT — see [LICENSE](LICENSE).  Upstream copyright belongs to Junegunn Choi.
