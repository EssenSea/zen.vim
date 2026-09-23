# Changelog

All notable changes to this project are documented here.  The format is based
on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed

- Opening a new tab no longer ends the session.  `:tabnew` / `:tabedit` keep
  the Zen tab (the new tab is an ordinary tab without a session), and
  switching back to the Zen tab finds it still active.  A plain `:tabnext` /
  `:tabprevious` still leaves Zen, and `:q` on the Zen tab still closes it.
- The pad windows now stay out of the cursor's way: `<C-w>h`, `<C-w>j`,
  `<C-w>k`, `<C-w>l`, `<C-w>t` and `<C-w>b` do nothing when they would move
  into a pad, so the cursor no longer flashes into the padding.  Movement
  between content windows is unchanged, and a fallback still bounces the
  cursor back if it reaches a pad another way.
- `:only` / `<C-w>o`, or closing a pad by hand, no longer leaves Zen.  The
  surviving window becomes the new master and the pads are rebuilt around it
  (Reanchor()).  Replaces the previous behaviour of leaving Zen.
- `<C-w>o` and `<C-w>c` are now temporary `<ScriptCmd>` mappings routed
  through ZenOnly()/ZenClose().  A plain `:only` / `:close` removes the
  window first and only then lets the deferred WinClosed handler rebuild the
  pads, which shows a one-window layout for a few frames (a visible "jump").
  The mapping closes and rebuilds in a single event-loop turn, so that frame
  is never drawn.  User bindings for these keys are still left untouched, and
  the `:only` / `:close` command forms keep working through the fallback.
- Pads are made more thoroughly background-like: the winbar is cleared
  when the option exists, and the WinBar/WinBarNC highlight groups are
  blended in when present.  The status line is hidden for every window
  (see the Fixed entry below), and the option is only rewritten when it
  actually differs, to avoid a redraw when the cursor bounces out.
- Raised the minimum supported Vim to **9.1.1652** (it was 9.1.0000).
  plugin/zen.vim, `ci.sh` and the CI matrix now require 9.1.1652, which
  covers the features used by the implementation: gettext()/bindtextdomain()
  (9.1.0509) and 'winfixbuf' (9.1.0147) are guaranteed present from this
  version on.  They are still probed, so unusual builds keep working.

### Added

- Prominent **LLM POWERED** notices: the plugin and its tests/docs were
  developed with assistance from DeepSeek V4.1 and the DeepSeek harness.
  Noted at the top of the source files, test scripts and documentation, plus
  `:help zen-llm`.
- `test/run_pty.py` / `test/pty.sh` / `make pty`: run Vim under a real pseudo
  terminal to exercise the parts `vim -es` cannot (window layout, WinResized,
  the pad bounce, and the `:Zen` command typed by the user).  Wired into
  `make check` and CI.
- plugin/zen.vim now uses the vim9-mix layout: the version check is legacy
  Vim script, so loading the plugin on a Vim older than 9.1.0000 exits
  cleanly with a warning instead of failing on the `:vim9script` command.
  Set `g:zen_disable_legacy_warning` to silence the warning.
- `test/api.vim` / `make api`: contract tests pinning every Vim built-in,
  event and option the plugin relies on, plus the shape of the return values
  it reads (getcurpos, getwininfo, winlayout, winsaveview, maparg, mapnew,
  hlget/hlset, timer_start).  CI runs them on 9.1.0000, 9.1.1000, 9.1.2000
  and master, and a weekly schedule re-runs them so a change in Vim itself is
  reported even when the plugin has not changed.

### Removed

- The unused `Pads()` helper in autoload/zen.vim.  It was dead code left
  over from the upstream API; the public API is Open/Close/Toggle only.

### Fixed

- Entering or leaving Zen printed `No matching autocommands: User
  ZenEnter` / `ZenLeave` when no user autocommand listened for those events.
  The `:doautocmd User ZenEnter/ZenLeave` calls are now guarded by
  `exists('#User#ZenEnter')` / `exists('#User#ZenLeave')`, so user handlers
  still fire but the message is gone when there is none.
- The separator rows reappeared after a config reload.  `:w` on a vimrc can
  source it (via a BufWritePost autocommand), and that source can both set
  `&laststatus = 2` (so every window draws a status line) and run a
  colorscheme whose ColorScheme autocommands re-set StatusLine/StatusLineNC
  after Tranquilize() blended them.  Zen now re-asserts 'laststatus' = 0 and
  re-runs Tranquilize() on BufWinEnter/WinEnter, and schedules the same from
  a zero-delay timer after a `:w`, so both are restored once the whole
  autocommand chain (including the nested :source) has finished.
- The status line above the content and between the left/right pads was
  visible again.  'laststatus' = 0 only removes the status line of the
  bottom-most window of a column; a window that has another window below it
  keeps a separator row (see |status-line|).  That row is filled from the
  window-local 'statusline', and an *empty* value makes Vim draw the
  built-in default text (buffer name, ruler, ...) there.  The value is now
  the non-empty BLANK_STATUSLINE (a single space) for the master and every
  pad, applied by HideAllStatuslines() on entry and after re-anchoring.
- The status line rows of the pads were still visible: tranquillizing the
  highlight groups cleared only `gui` (or only `cterm`), so a leftover
  `term`/reverse/bold survived and the row showed as a coloured bar.  All
  three attribute groups are now cleared (and the GUI colour is no longer
  passed to cterm, which raised E421).
- Hiding the status line leaked into other tab pages.  getwininfo() without
  an argument returns the windows of *all* tabs, so HideAllStatuslines()
  blanked the original tab's windows too and left them with a one-space
  'statusline' after leaving Zen.  It now restricts itself to the current
  tab page (tabnr check), matching the convention used elsewhere.
- The test suite could report success while assertions failed.  The
  `assert_*()` functions add failures to |v:errors| and return non-zero;
  they only throw for the `:assert_*` command forms, so the try/catch in
  the test runner never saw a failed `assert_equal()`.  Each test now
  clears |v:errors|, checks it afterwards, and reports the collected
  messages.  Several previously hidden failures (stale window lookup,
  type-strict boolean comparisons, offset expressions) were fixed with it.
- A failure while entering Zen reported `E608: Cannot :throw exceptions with
  'Vim' prefix` instead of the original error.  The rollback no longer does
  `throw v:exception`; it uses `echoerr` to keep the original message.
- Opening help (`<F1>` / `:help`) while Zen was active raised
  `E21: Cannot make changes, 'modifiable' is off`.  SetupPad() used
  `append(buf, ...)`, which treats the first argument as a line number and
  writes to the *current* buffer (the read-only help window); it now uses
  `appendbufline(buf, ...)`.
- `:only` / `<C-w>o` (or closing a pad by hand) removed the pad windows but
  left the session active with a broken layout and no margins.  A |WinClosed|
  handler now detects a missing pad and re-anchors Zen (see below).
- `'winfixbuf'` was added in Vim 9.1.0147, later than the 9.1.0000 minimum,
  but it was used unconditionally after an earlier clean-up.  It is probed
  again (HasWinFixBuf()) so the plugin works on the earliest supported
  builds; the contract test only requires it from 9.1.0147 on.

- A failure part way through opening Zen (for example a window that cannot be
  created, or a throwing BufWinEnter autocommand) used to leave a half-built
  session behind: an extra tab, stray `t:zen_*` variables and, most visibly,
  the temporary `<C-w>` mappings still installed.  The setup is now guarded
  and rolled back by `AbortOn()`; the original error is re-thrown.

### Internal

- Slimmed the implementation: the four pad windows are described once in a
  `PAD_DEFS` table used for creation, autocommands and exclusion; `MapNop()`
  and `MapResize()` were merged into `InstallMaps()`; `OnWinResized()` was
  removed because `ResizePads()` already guards itself; the `+timers`
  fallback moved into a single `Defer()` helper.
- Removed checks for options that always exist on Vim 9.1+ (`relativenumber`,
  `colorcolumn`, `winfixbuf`) and the unused nvim branch; `WinResized` no
  longer needs an `exists('##WinResized')` guard (it is present since
  9.0.0917).

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

- The four deferred handlers (ConfineWindows, ApplyRestore, ApplyZenOff and
  CheckPads) now share one de-duplicating scheduler (`Schedule()`, a keyed
  script-local dictionary) instead of one `<name>_pending` boolean each.
  ResetDeferred() clears them all on teardown, so AbortOn() can no longer
  leave a stale flag behind.  Behaviour is unchanged.
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
