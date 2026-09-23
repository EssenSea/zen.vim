# Changelog

All notable changes to this project are documented here.  The format is based
on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed

- Reorganised the project as a standard Vim package, following
  `:help package-create` and the layout used by Vim's bundled plugins.
- `plugin/goyo.vim` is now Vim9script and loads the implementation with
  `import autoload '../autoload/goyo.vim'`; `autoload/goyo.vim` exposes a
  typed `export def` API.
- The help file follows `:help help-writing`: tagged first line, numbered
  sections, 78-column formatting and a standard modeline.
- User messages can be translated with `gettext()`; a catalogue template and
  an English catalogue are provided under `lang/`.

### Fixed

- `:Goyo` is now defined (the previous single-file layout never defined it).
- User command bodies use `:call` so Vim loads the autoload function.
- Dimension expressions support `{width}{±xoff}x{height}{±yoff}`.
- Option restoration no longer raises E591/E592.
- `Blank()` no longer calls a non-existent function.
- `Decorate()` guards against empty elements and zero width.
- Windows opened by `:help` and friends are confined to the content column.

### Added

- `test/test_goyo.vim` and `test/run.sh`: a dependency-free test suite.
- `Makefile`, `.editorconfig`, `CONTRIBUTING.md`, `README.md`, `LICENSE`.
