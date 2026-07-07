# Meow modal refactor context

## Intent

- Replace Evil + evil-collection with Meow modal editing.
- Keep vanilla Emacs bindings as first-class. Meow supplies modal editing, not a Vim clone layer.
- Use Meow bundled QWERTY keybinding as baseline because it semi-resembles Vim.
- Keep SPC leader ergonomics, with categories inspired by Doom and studium-emacs, but not wholesale copied.
- Preserve current Suderman workflow where useful: project/file/buffer/search pickers, Treemacs/Dirvish, window movement/resizing, markdown preview, hot reload.

## Decisions

- Do not edit yet. Need user choices on leader taxonomy, exact vim-ish overrides, and special-mode policy first.
- Use upstream Meow `KEYBINDING_QWERTY.org` as canonical normal/motion baseline.
- Prefer `meow-leader-define-key` over `general.el` if abandoning Evil. General is only needed today for Evil state-aware SPC maps.
- Prefer a dedicated Suderman leader keymap installed into `(alist-get 'leader meow-keymap-alist)` instead of default `mode-specific-map`. Reason: keep vanilla/package `C-c` bindings intact and make hot reload safe by recreating one owned keymap.
- Replace `lisp/suderman-evil.el` with a Meow module rather than layer Meow into old Evil file. Likely filename: `lisp/suderman-meow.el`.
- Update hot reload helper because it currently knows about Evil auxiliary keymaps and re-enables `evil-mode`.

## Constraints

- Current config is modular; keep entrypoint boring and module names clear.
- Package management is package.el + use-package with MELPA available.
- Avoid copy-pasting studium-emacs. Steal broad vibe/categorization only.
- Meow leader defaults to `mode-specific-map` / `C-c`; SPC in normal/motion enters keypad. Need decide whether leader bindings should also live under `C-c` or in a dedicated keymap via `meow-keypad-leader-dispatch`.
- Meow keypad reserves `SPC x`, `SPC c`, `SPC h`, `SPC m`, and `SPC g` style prefixes for vanilla modifier translation by default (`C-x`, `C-c`, `C-h`, `M-`, `C-M-`). Doom-style categories want some same letters (`h` help, `g` git, `c` code, `m` localleader). Need choose preserve vanilla prefixes vs move keypad prefixes to uppercase to free category letters.
- Meow has no major-mode-specific local leader. Need implement local actions via plain mode maps or category prefixes, not pretend local leader exists.

## Open questions

Resolved by user:

- Preserve Meow vanilla keypad prefixes. Do not bind leader groups on `SPC x/c/h/m/g`; those remain Meow/vanilla dispatch prefixes.
- `SPC /` should search project.
- No local leader for now.
- Use upstream QWERTY normal/motion layout exactly, except explicit customizations below.
- ESC exits insert; no jk chord.
- Use system clipboard behavior and studium-style paste below/above.
- Keep Meow default indent keys.
- Add Vim-style redo on `C-r` in normal state.
- Move window commands under `SPC w`, but keep direct `M-h/j/k/l`, `M-H/J/K/L`, `M-u`, `M-i` bindings.
- Drop Treemacs now; use Dirvish/Dired.
- Reserve git/code concepts for later, but do not bind `SPC g`/`SPC c` because they are Meow keypad prefixes.
- `SPC t` means tools.
- Keep vim nav in minibuffer.
- Drop insert-state `C-l` space hack.
- Special/read-only modes start in motion; shells/terminals start in insert.
- Dirvish/Dired should have vim-ish h/j/k/l navigation.
- Delete old Evil module; git is rollback.
- Remove General use from config.

Implementation caveat:

- `[b`/`]b` and `[c`/`]c` conflict with exact Meow QWERTY because `[` and `]` are occupied by `meow-beginning-of-thing`/`meow-end-of-thing`. Exact Meow wins. Buffer/error navigation stays under leader/window/search groups unless user chooses to trade off later.

## Discarded options

- Keep Evil and add Meow alongside it: rejected by user intent; modal systems would fight over state maps.
- Copy studium-emacs meow setup wholesale: rejected by user; many commands/packages are unrelated.
- Keep `general.el` solely for leader definitions: probably unnecessary if using Meow leader; revisit only if which-key metadata/group labeling is much better with general.

## Blast radius

- Removing `suderman-evil`: must update every `(require 'suderman-evil)` and Evil API call.
- Current Evil references found by `rg -n "evil|general|suderman-evil|evil-collection" . --glob '!auto-save-list/**' --glob '!*~'`:
  - `init.el` requires `suderman-evil`.
  - `lisp/suderman-evil.el` owns Evil setup and helpers.
  - `lisp/suderman-keys.el` requires Evil, binds Evil state maps, uses general leader.
  - `lisp/suderman-files.el` requires Evil, uses `:after evil`, `evil-set-initial-state`, `evil-emacs-state`.
  - `lisp/suderman-markdown.el` requires Evil, uses `evil-define-key` for local preview binding.
  - `lisp/suderman-reload.el` declares/re-enables Evil and clears Evil/general keymaps.
