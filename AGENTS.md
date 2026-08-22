# Working on this Emacs config

## What this repository is

This is Jon Suderman's personal Emacs configuration. It is used every day, but
it is still under active construction. Some parts are polished. Some parts are
experiments that solved a real problem and have not had much time to settle.

Do not mistake "work in progress" for permission to redesign it from scratch.
The general feel is right. The customized Meow editing model, project-oriented
buffer workflow, completion stack, modeline, explorers, icons, and most chosen
packages are taking shape deliberately.

Prefer a small repair that preserves this direction. Broad rewrites need a
clear reason and explicit approval.

## The NixOS half of the setup

This repository is only the Emacs half of the system. The matching NixOS flake
lives at `/etc/nixos` and <https://github.com/suderman/nixos>.

Read `/etc/nixos/modules/home/desktop/default/options/emacs.nix` before changing
package ownership, daemon behavior, fonts, tree-sitter grammars, language
servers, or external tools.

The current division is intentional.

- Nix supplies Emacs 31 PGTK, the Emacs daemon and client, native or awkward
  packages, tree-sitter grammars, language modes that are better managed by
  Nix, language servers, formatters, `fd`, `ripgrep`, Pandoc, and fonts.
- Stylix supplies the active Emacs theme and system typography.
- This repository owns mutable Elisp packages, commands, keymaps, and daily
  editing behavior.
- `package.el` data lives under `~/.local/share/emacs/elpa`, not in this repo.
- Emacs state, history, backups, auto-saves, Custom data, and caches follow XDG
  paths configured in `lisp/suderman-paths.el`.

Use `:ensure nil` for packages supplied by Nix. Before adding a package to Nix,
ask whether it really needs native dependencies, grammar data, or system-level
integration. Pure Elisp normally belongs in the mutable `package.el` setup.

Do not hardcode a replacement palette in this repo. Stylix theme changes must
continue to affect Emacs. When a derived color is needed, calculate it from
active semantic faces as `lisp/suderman-appearance.el` does for selections.

The expected icon fonts are `JetBrainsMono Nerd Font Mono` and `Symbols Nerd
Font Mono`. Nix installs them.

## Repository shape

Keep `init.el` boring. It loads modules in dependency order. New behavior
belongs in the narrowest existing `lisp/suderman-*.el` module, or in a new
module when a concern has genuinely outgrown its old home.

The current modules have clear jobs.

- `suderman-paths.el` owns XDG paths and mutable state locations.
- `suderman-packages.el` owns `package.el` and `use-package` defaults.
- `suderman-defaults.el` contains small built-in behavior changes.
- `suderman-appearance.el` owns fonts, Stylix-derived faces, Doom Modeline,
  current-line highlighting, line numbers, and the 100-column guide.
- `suderman-windows.el` owns window helpers and smooth jump animation.
- `suderman-projects.el` wraps built-in `project.el` behavior.
- `suderman-buffers.el` owns project-grouped IBuffer.
- `suderman-completion.el` owns Vertico, Orderless, Consult, Marginalia, and
  Embark.
- `suderman-pickers.el` owns commands built from the completion stack.
- `suderman-meow.el` owns modal editing, selections, editing commands, and the
  normal and motion maps.
- `suderman-files.el` owns Dired and Dirvish.
- `suderman-treemacs.el` owns the project-focused Treemacs tree and its links to
  IBuffer.
- `suderman-markdown.el` owns Markdown mode behavior and Pandoc preview.
- `suderman-languages.el` owns broad language associations and tree-sitter
  setup.
- `suderman-keys.el` owns global keys and the Meow `SPC` leader maps.
- `suderman-reload.el` owns hot reload behavior.

Do not put generated files, package trees, caches, or compiled Elisp in the
repository. The existing `.gitignore` describes those boundaries.

## Editing model

Meow is the modal editor, but this is not Meow's sample QWERTY layout. The map
has been shaped around Jon's habits and borrows some Vim and Neovim ideas
without trying to emulate either editor exactly.

Read `suderman/meow-setup-qwerty` in `lisp/suderman-meow.el` before changing a
normal-state key. Read `lisp/suderman-keys.el` before changing `SPC`, Meta
window keys, or global shortcuts.

Important parts of the current grammar follow.

- `hjkl` moves. Active Meow selections expand with movement.
- `m`, `mm`, and `mmm` select a word, symbol, and enclosing block.
- `M`, `MM`, and `MMM` select a rectangle, line, and whole buffer.
- `s` is the full Surround prefix. `s s` inserts a surround.
- `'` repeats the last Repeat-FU edit, except immediately after `t` or `T`,
  when it repeats that till motion.
- `,` opens project-grouped IBuffer and selects the invoking buffer.
- `.` opens full-frame Dirvish for the current file or directory.
- In normal state, `S`, double quote, backtick, and `~` are
  intentionally inert. Motion buffers let these keys fall through to their
  major-mode maps.
- Image buffers use Motion state. Their native `n` and `p` browse files in
  cyclic alphabetical order while `SPC` remains Meow's keypad, `,` opens
  IBuffer, `.` opens Dirvish, and `h` focuses Treemacs. `=`/`+` and `-` zoom,
  `r` and `R` rotate, and `0` resets the image transformations. Animated images
  autoplay and loop.
- `c` copies, `v` pastes, `d` deletes without filling the kill ring, and `x`
  cuts a real multi-character selection before entering insert state.
- `X` cuts the current line and enters insert state.
- `n` and `p` search forward and backward.
- `t` and `T` move till a character forward and backward.
- `y` is redo. `u` is one-way Meow undo. `U` is one-way undo in selection.
- `C` and `V` page up and down through Meow. Vanilla `C-u`, `C-d`, and `C-v`
  are deliberately not shadowed by Meow normal bindings.
- `SPC` is both Meow's keypad and the owned leader map. `SPC h` focuses
  Treemacs and `SPC H` toggles its visibility. Numeric arguments are useful,
  for example `SPC 3 f`.

The full map is the source of truth. Do not duplicate every binding here.

IBuffer and Treemacs disable Meow locally. Their major-mode maps own `hjkl` and
related keys. Meow's emulation maps outrank ordinary major-mode maps, so
forgetting this causes keys to appear correct in a keymap inspection while
doing something else in a live buffer.

Dirvish also disables Meow locally so Dired's map can own `hjkl`, marking, and
file operations. `SPC` invokes Meow's keypad directly without enabling a Meow
state. Its full-frame layout follows Yazi's parent/current/preview proportions,
but its commands remain Dired commands rather than a second Yazi emulation.
Comma closes the full-frame layout before opening IBuffer, period closes
Dirvish, and dotfiles start hidden in the parent and current panes while `i`
toggles them together without messages. The preview remains unfiltered. `c`,
`x`, and `v` stage copy, stage cut, and paste operations through Dirvish's
transfer engine. Deleting a file automatically kills its unmodified visiting
buffer; modified buffers remain protected by a confirmation. Slash searches
below the current directory. Question mark shows a compact Which-Key view
generated from the effective bindings; the upstream Dirvish dispatcher remains
available through `M-x`.

## Buffer and explorer workflow

The buffer list and project tree overlap on purpose, but each has a different
job.

### IBuffer

IBuffer is the project-oriented overview. It uses built-in `project.el`,
`ibuffer-project`, and Nerd Icon columns. Non-project image buffers get their
own group; other non-project buffers remain visible in the default group. There
is no broad hidden-buffer blacklist.

- Normal-state `,` opens it and highlights the invoking buffer.
- IBuffer `,` closes it and restores the prior buffer and window.
- `j` and `k` move by row.
- `l` visits the selected buffer and updates a visible Treemacs, or toggles a
  group heading.
- `h` visits the selected buffer, then focuses Treemacs on that file.
- `SPC` and `H` toggle a contextual Treemacs view without leaving IBuffer.
- `.` opens Dirvish for the selected buffer or project heading.
- `m` toggles the current buffer mark without moving. `M` marks every visible
  buffer and `t` inverts the marks, so `M t` clears them all.

IBuffer relies on native `quit-window` restoration. Do not add a custom window
stack unless native restoration has been shown to fail.

### Treemacs

Treemacs is the project tree. It reveals the current file, supports Git and
file watching, and uses Nerd Icons. It keeps a private, non-persisted Treemacs
workspace object per frame. This is necessary because upstream Treemacs
otherwise shares one workspace object across frame-local buffers, which caused
stale trees, blank trees, and root-navigation crashes.

The module contains repair code for stale or blank frame trees. It also uses
some Treemacs internals. Preserve this behavior unless the installed Treemacs
version has fixed the underlying shared-workspace assumptions and the old
failures have been retested.

Treemacs and IBuffer have contextual transitions. Period opens Dirvish for the
selected buffer, project heading, or tree node. A selected file, project
heading, current editor window, and current frame all matter. Test those flows
with real windows instead of calling commands in an arbitrary temporary buffer.

## Package choices that already have a reason

These choices are not immutable, but replacing one needs a concrete benefit.

- Built-in `project.el` is the project API. Do not add Projectile alongside it.
- Vertico, Orderless, Consult, Marginalia, and Embark form the minibuffer stack.
- Meow owns modal editing.
- Repeat-FU owns edit repeat on apostrophe. Its Meow preset records edits across
  insert-state transitions and keeps history across buffers.
- `surround` owns pair insertion, deletion, change, and pair selection.
- `scroll-on-jump` animates keyboard pages and selected jumps. Built-in
  pixel-scroll precision mode remains off because it is a different feature
  and interfered with cursor-preserving keyboard paging.
- Doom Modeline supplies the modeline and native Meow state segment.
- Nerd Icons packages decorate Doom Modeline, IBuffer, and Treemacs.
- Dirvish improves Dired, while Treemacs provides the persistent project tree.
- Tree-sitter modes are preferred where the NixOS flake supplies grammars.
- Markdown preview uses Pandoc and a small local HTTP server. It refreshes only
  after save and preserves browser scroll position.

Avoid adding a package when an existing package or Emacs itself already covers
the request. This config has enough moving pieces.

## Hot reload is useful and imperfect

`suderman/reload-config` unloads and reloads the ordered modules from `init.el`.
It is intended for command, keymap, face, and ordinary module edits.

Several real bugs have come from reload behavior.

- Removing a binding from source does not necessarily clear a stale binding
  from a live keymap. Explicit cleanup may be needed.
- Re-enabling global Meow unnecessarily can leak a Meow state into buffers
  where Meow was disabled locally.
- `unload-feature` can demote live buffers to `fundamental-mode`. The reload
  code snapshots and restores major modes to prevent this.
- Advice, hooks, global minor modes, and frame callbacks must remain
  idempotent. Reloading twice should not duplicate or toggle them.

`suderman-reload.el` excludes itself from hot unloading. When changing the
reload implementation, load that file explicitly before testing the full
reload command.

Restart Emacs for changes to `early-init.el`, package initialization, native
modules, daemon options, or process-level state. A restart is also the right
escape hatch when a live keymap or package has accumulated stale state.

## How to investigate bugs

Reproduce before editing. This config combines package internals, global minor
modes, emulation maps, side windows, daemon frames, and hot reload. The obvious
caller is often not the cause.

Use this order when it applies.

1. Inspect the effective command with `key-binding`, not only the declared
   major-mode map.
2. Reproduce in a fresh batch load when possible.
3. Reproduce in the running graphical daemon when frames, fonts, faces, side
   windows, or selected-window history matter.
4. Read the installed package source. The locally installed version is more
   useful than an old snippet from the web.
5. Change the smallest shared point that explains every failing path.

Actual keyboard sequences matter for Meow, Repeat-FU, command repetition,
physical Return versus `RET`, and commands that inspect `last-command` or
`this-command`. Separate calls to `execute-kbd-macro` can break consecutive-key
state. Use one macro for one sequence.

Batch Emacs differs from an interactive session. `transient-mark-mode`, the
selected window, active regions, graphical face resolution, and daemon frame
state have all produced misleading test results. Treat a failing harness as
evidence to inspect, not automatic proof that the implementation is wrong.

When a command should follow the user's visible editor context, prefer the
selected window's buffer over ambient `current-buffer`. Sidebars and package
callbacks can leave `current-buffer` somewhere surprising.

## Verification

There is no standalone test suite yet. Leave a focused runnable check for new
branching behavior, then run the checks that match the change.

At minimum:

- Load the full config with `emacs --batch -l init.el`.
- Byte-compile every changed module, sending `.elc` output to `/tmp/opencode`
  rather than the repository.
- Run `git diff --check`.
- Inspect the relevant diff and keep it limited to the task.

For interactive behavior, also reload or restart the daemon and exercise the
real key sequence. Check GUI and terminal frames when frame handling or Nerd
Font rendering changes. Check two frames when changing Treemacs.

Known warnings are not a reason to ignore new warnings. Existing warnings have
included obsolete `when-let`, upstream package compatibility helpers, and Org
movement functions that are unknown at compile time. Confirm that a warning is
pre-existing before calling it harmless.

## Git and generated state

The ignored `projects` file is mutable Emacs project history. The running
editor rewrites it. Treat it as user-owned runtime state. Do not delete,
reformat, or add it back to Git unless Jon explicitly asks.

Other agents or the user may change the worktree while work is in progress.
Do not undo unrelated changes. If a concurrent change conflicts with the same
code, stop and ask.

Do not commit or push unless asked. Before a requested commit, inspect status,
unstaged and staged diffs, and recent history. Stage only the intended files.

## Taste and maintenance rules

Use lexical binding. Follow the existing `suderman/` namespace for functions
and variables that are not private file constants. Keep comments short and
explain only behavior that the code cannot make obvious.

Prefer built-in Emacs behavior, then an installed package, then a small custom
command. Delete obsolete code when the reason for it is gone. Do not add
compatibility branches for versions this setup does not run.

This config values direct keyboard workflows, stable cursor and window
behavior, project context, and a clean interface. It does not value framework
construction or an abstract configuration system. Make the smallest change
that works, verify it in the path Jon actually uses, and leave the code easier
to understand than you found it.
