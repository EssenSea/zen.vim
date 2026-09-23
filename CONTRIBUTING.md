# Contributing

> **LLM POWERED** — this project is developed with assistance from
> **DeepSeek V4.1** and the **DeepSeek harness**.  Review AI-generated
> changes as carefully as any other contribution.

Thanks for improving zen.vim.  Please read this before opening a pull
request.

## Requirements

- Vim 9.1.1652 or newer with `+vim9script`.
- Use the bundled test suite (`make test`) before submitting.

## Coding style

This project follows the conventions used by Vim's bundled plugins
(see `:help package-create` and the files under
`$VIMRUNTIME/pack/dist/opt/`).

- Vim9script only.  Every script starts with `vim9script`.
- `plugin/zen.vim` loads the implementation with
  `import autoload '../autoload/zen.vim'` and only defines commands and
  `<Plug>` mappings.  It must not contain logic.
- `autoload/zen.vim` exposes `export def` functions.  Script-local helpers
  stay private (no `export`).
- Use typed variables and function arguments.
- Never use `:let &opt = ...` inside `execute`; use `:set` or direct `&opt`
  assignment.
- Wrap user-visible messages in `gettext()`.
- Keep lines at most 78 columns where practical; help files must use a
  'textwidth' of 78.
- End every script with `# vim: ts=8 sts=2 sw=2 et:`.

## Public API

Only `zen#Open()`, `zen#Close()` and `zen#Toggle()` are part of the supported
interface.  Keep their signatures stable and document any change in
`doc/zen.txt` and `doc/zen-internals.txt`.  Other functions in
`autoload/zen.vim` are implementation details and must not be exported.

## Continuous integration

Every change must pass the local CI entry point, which mirrors the GitHub
Actions workflow:

```sh
make ci        # or: sh ci.sh
```

It runs the conformance checks, the API contract tests, the test suite, the
PTY checks and the benchmarks against the Vim in `$PATH`, which must be Vim
9.1.1652 or newer.  The PTY checks need `python3` and a real terminal; they
exercise the screen-dependent paths.
Only Vim is supported; Neovim is out of scope.

When you start using a new Vim built-in, event or option, add it to
`test/api.vim` (see `make api`).  That test pins the contract the plugin
relies on, so a change in Vim is reported in CI instead of at runtime.  Vim
sometimes compiles without optional features (for example `+multi_lang`, or
the 'winfixbuf' option on builds before 9.1.0147); probe such features with
`exists()` rather than assuming them.

## Tests

Add a case to `test/test_zen.vim` for every behavioural change.  Tests use
Vim's built-in `assert_*()` functions and run with:

```sh
make test        # Vim
make test-nvim   # Neovim, if it supports Vim9script
```

## Documentation

Update `doc/zen.txt` when user-facing behaviour changes, then regenerate the
tags:

```sh
make tags
```

Follow `:help help-writing`: a tag on the first line, a right-aligned version
line, section numbers with tags, two spaces between sentences, and a modeline
`vim:tw=78:ts=8:noet:ft=help:norl:` at the end.
