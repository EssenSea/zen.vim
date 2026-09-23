# zen.vim

Distraction-free writing mode for Vim — 无干扰写作模式。

This repository is a fork of
[goyo.vim](https://github.com/junegunn/goyo.vim) that rewrites the
implementation in **Vim9script** and organises the project
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
set runtimepath+=/path/to/zen.vim

" option B: as a package (recommended for :packadd)
"   ~/.vim/pack/zen/start/zen/  <- clone here
packadd zen
```

`plugin/zen.vim` defines the `:Zen` command at startup.

## Usage

```vim
:Zen            " enter; run again to leave
:Zen 80x20      " 80 columns by 20 lines
:Zen 50%x70%    " percentages
:Zen!           " force leave
```

See `:help zen` for the full manual.

## Layout

```
plugin/zen.vim           loads the plugin, defines :Zen and <Plug> mappings
autoload/zen.vim         the implementation (Vim9script, exported API)
doc/zen.txt              help file
doc/zen-internals.txt    notes on the built-in mechanisms used
doc/tags                 help tags (regenerate with :helptags doc)
lang/                    gettext catalogues (zen.pot, <lang>/LC_MESSAGES/zen.mo)
test/test_zen.vim        test suite
test/conformance.sh      package-convention checks
test/run.sh              test runner
test/bench.sh            micro-benchmark runner
Makefile                 common tasks
```

## Development

```sh
make test        # run the suite with Vim
make test-nvim   # run with Neovim (skipped if it lacks Vim9script)
make check       # lint + conformance + tests
make bench       # micro-benchmarks (median/min/max per operation)
make tags        # regenerate doc/tags
make lint        # load the plugin to catch compile errors
```

The tests use Vim's built-in `assert_*()` functions and report the number of
failures as the exit status.  See `CONTRIBUTING.md`.

## Translation

The catalogue template is `lang/zen.pot`.  To add a language, create
`lang/<lang_id>/LC_MESSAGES/zen.po`, translate it and compile it with
`msgfmt -o zen.mo zen.po`.  See `:help package-translation`.

## License

MIT — see [LICENSE](LICENSE).  Upstream copyright belongs to Junegunn Choi.
