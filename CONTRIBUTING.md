# Contributing

Thanks for improving goyo.vim.  Please read this before opening a pull
request.

## Requirements

- Vim 9.1.0000 or newer with `+vim9script`.
- Use the bundled test suite (`make test`) before submitting.

## Coding style

This project follows the conventions used by Vim's bundled plugins
(see `:help package-create` and the files under
`$VIMRUNTIME/pack/dist/opt/`).

- Vim9script only.  Every script starts with `vim9script`.
- `plugin/goyo.vim` loads the implementation with
  `import autoload '../autoload/goyo.vim'` and only defines commands and
  `<Plug>` mappings.  It must not contain logic.
- `autoload/goyo.vim` exposes `export def` functions.  Script-local helpers
  stay private (no `export`).
- Use typed variables and function arguments.
- Never use `:let &opt = ...` inside `execute`; use `:set` or direct `&opt`
  assignment.
- Wrap user-visible messages in `gettext()`.
- Keep lines at most 78 columns where practical; help files must use a
  'textwidth' of 78.
- End every script with `# vim: ts=8 sts=2 sw=2 et:`.

## Tests

Add a case to `test/test_goyo.vim` for every behavioural change.  Tests use
Vim's built-in `assert_*()` functions and run with:

```sh
make test        # Vim
make test-nvim   # Neovim, if it supports Vim9script
```

## Documentation

Update `doc/goyo.txt` when user-facing behaviour changes, then regenerate the
tags:

```sh
make tags
```

Follow `:help help-writing`: a tag on the first line, a right-aligned version
line, section numbers with tags, two spaces between sentences, and a modeline
`vim:tw=78:ts=8:noet:ft=help:norl:` at the end.
