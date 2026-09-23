# Changelog

All notable changes to this project are documented here.  The format is based
on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed

- Window layouts are now captured with |winlayout()| and replayed on leave,
  so nested or unequal splits are restored exactly.  The previous code
  inferred the split direction from screen coordinates.
- `ConfineWindows()` is deferred through a zero-delay timer and handles all
  stray windows in one pass, instead of changing the layout from inside the
  BufWinEnter autocommand one window at a time.

### Added

- Compatibility: buffer switches respect 'winfixbuf' (Vim 9.1) by temporarily
  clearing it, and the deferred actions fall back to direct calls when the
  build has no |+timers| support.
- Public API reduced to `zen#Open()`, `zen#Close()` and `zen#Toggle()`; other
  functions are no longer exported.  Documented in `doc/zen.txt` under
  |zen-api|.
- `<Plug>(zen-open)`, `<Plug>(zen-close)` and `<Plug>(zen-toggle)`; the
  previous `<Plug>(zen-off)` is kept as an alias of close.
- `:Zen` now toggles, `:Zen {dim}` opens and `:Zen!` closes.
- GitHub Actions workflow (`.github/workflows/ci.yml`) and a local `ci.sh` /
  `make ci`, testing Vim 9.1.0000 and later only.
- Use Vim 9.1's |WinResized| event, with a re-entrancy guard, so dragging a
  window separator re-lays out the layout.

### Changed

- **Renamed everything from goyo to zen.**  The command is now `:Zen`, the
  script is `plugin/zen.vim` / `autoload/zen.vim`, the user events are
  `ZenEnter` / `ZenLeave`, the options are `g:zen_*`, the autoload functions
  are `zen#Open()` / `zen#Close()` / `zen#Toggle()`, and the mappings are
  `<Plug>(zen-open)` / `<Plug>(zen-close)` / `<Plug>(zen-toggle)`.  There are
  no goyo compatibility aliases, so update any mappings and options.
- Reorganised the project as a standard Vim package, following
  `:help package-create` and the layout used by Vim's bundled plugins.
- `plugin/zen.vim` is now Vim9script and loads the implementation with
  `import autoload '../autoload/zen.vim'`; `autoload/zen.vim` exposes a
  typed `export def` API.
- The help file follows `:help help-writing`: tagged first line, numbered
  sections, 78-column formatting and a standard modeline.
- User messages can be translated with `gettext()`; a catalogue template and
  an English catalogue are provided under `lang/`.

### Fixed

- `:Zen` is now defined (the previous single-file layout never defined it).
- User command bodies use `:call` so Vim loads the autoload function.
- Dimension expressions support `{width}{±xoff}x{height}{±yoff}`.
- Option restoration no longer raises E591/E592.
- `Blank()` no longer calls a non-existent function.
- `Decorate()` guards against empty elements and zero width.
- Windows opened by `:help` and friends are confined to the content column.

### Changed (internals)

- Highlighting uses the built-in |hlget()| / |hlset()| API instead of
  `synIDattr()` and `:highlight` strings.
- Options are saved and restored with typed `&option` assignments; the
  dynamic `:set` helper has been removed.
- Window scanning uses |getwininfo()| instead of repeated `winbufnr()`,
  `win_screenpos()` and `winwidth()` calls.
- `Blank()` defers closing through |timer_start()| rather than feeding a
  `<Plug>` key.
- `mapnew()` is used in Decorate() so the user's option list is not copied
  and mutated.
- Returning to the original window uses |win_gotoid()|, which also switches
  tab pages.
- Pad autocommands are installed once, not rebuilt on every resize.
- New `doc/zen-internals.txt` documents the mechanisms used.

### Performance

- Leaving Zen no longer reloads the whole color scheme.  The highlight
  groups changed by Tranquilize() are saved with |hlget()| and restored with
  |hlset()|, which is both exact and considerably cheaper.
  Measured with `make bench` on the reference machine:
    ZenOn + ZenOff           0.98ms -> 0.77ms  (-22%)
    On + stray split + Off     1.23ms -> 1.03ms  (-17%)
- The pad layout no longer switches windows: sizes and buffer contents are
  updated with |win_execute()|, |setbufvar()|, |deletebufline()| and
  |append()|, which removes the WinEnter/WinLeave churn during a resize.
  Measured with `make bench`:
    Resize                     0.23ms -> 0.05ms  (-79%)
    ZenOn + ZenOff           0.98ms -> 0.73ms  (-26%)
- Added `test/bench.vim` / `test/bench.sh` and a `make bench` target.

### Added

- `test/test_zen.vim` and `test/run.sh`: a dependency-free test suite.
- `Makefile`, `.editorconfig`, `CONTRIBUTING.md`, `README.md`, `LICENSE`.
