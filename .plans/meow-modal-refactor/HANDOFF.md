# Meow modal refactor handoff

## Goal

Replace Evil + evil-collection with Meow, using upstream Meow QWERTY modal bindings, vanilla Emacs keypad behavior, and a Doom-ish SPC leader where Meow leaves keys available.

## User decisions

- Preserve Meow vanilla keypad prefixes. Do **not** bind leader groups on `SPC x`, `SPC c`, `SPC h`, `SPC m`, or `SPC g`; those remain Meow keypad translations for vanilla Emacs (`C-x`, `C-c`, `C-h`, `M-`, `C-M-`).
- `SPC /` should search project.
- No local leader for now; Meow does not support it.
- Use upstream `KEYBINDING_QWERTY.org` normal/motion layout as baseline.
- ESC exits insert; no `jk` chord.
- Use system clipboard behavior plus studium-style paste below/above.
- Keep Meow default indent keys.
- Add Vim-style redo on `C-r` in normal state.
- Move window commands under `SPC w`, but keep direct `M-h/j/k/l`, `M-H/J/K/L`, `M-u`, `M-i` bindings.
- Drop Treemacs now; use Dirvish/Dired.
- Reserve git/code concepts for later, but do not bind `SPC g`/`SPC c` now because they are Meow keypad prefixes.
- `SPC t` means tools.
- Keep vim nav in minibuffer.
- Drop insert-state `C-l` space hack.
- Special/read-only modes start in motion; shells/terminals start in insert.
- Dirvish/Dired should have vim-ish `h/j/k/l` navigation.
- Delete old Evil module; git is rollback.
- Remove General use from config.

## Important caveat

`[b`/`]b` and `[c`/`]c` conflict with exact Meow QWERTY because `[` and `]` are occupied by `meow-beginning-of-thing`/`meow-end-of-thing`. Exact Meow wins unless user later chooses to trade those keys away.

## Expected implementation shape

- Create `lisp/suderman-meow.el` for Meow setup, owned leader map helper, paste helpers, mode state defaults, and QWERTY bindings.
- Remove `lisp/suderman-evil.el`.
- Update `init.el` load order to require `suderman-meow` instead of `suderman-evil`.
- Rewrite `lisp/suderman-keys.el` around `meow-leader-define-key`, which-key, and Meow normal/motion additions; remove `general`.
- Simplify `lisp/suderman-files.el` to Dirvish/Dired only and add vim-ish file-browser keys.
- Replace Evil-specific markdown binding with vanilla/mode binding.
- Update `lisp/suderman-reload.el` to reset Meow leader maps instead of clearing Evil/general state.

## Verification

Run:

```sh
rg -n "evil|evil-collection|general|suderman-evil|treemacs" init.el lisp
emacs --batch -l init.el --eval '(message "loaded")'
emacs --batch -l init.el --eval '(batch-byte-compile)' lisp/suderman-meow.el lisp/suderman-keys.el lisp/suderman-files.el lisp/suderman-markdown.el lisp/suderman-reload.el lisp/suderman-windows.el lisp/suderman-pickers.el init.el
rm -f init.elc lisp/*.elc
```

Expected:

- `rg` returns no active config references to removed Evil/General/Treemacs names.
- Batch load exits 0 and prints loaded message.
- Byte compile exits 0 with no config warnings.
- Generated `.elc` files are removed after compile.

Manual smoke after batch verification:

- `SPC ?` shows Meow cheatsheet.
- `SPC /` runs project search.
- `SPC SPC` finds project/smart file.
- `SPC .`, `SPC ,`, `SPC :`, `SPC \\` work.
- `SPC f`, `SPC b`, `SPC p`, `SPC s`, `SPC t`, `SPC w`, `SPC q` groups show in which-key/keypad.
- `SPC x`, `SPC c`, `SPC h`, `SPC m`, `SPC g` still behave as Meow keypad modifier/vanilla dispatch prefixes.
- `M-h/j/k/l`, `M-H/J/K/L`, `M-u`, `M-i` still work in normal/motion.
- Dirvish/Dired h/j/k/l works.
- Markdown preview is available from its new non-Evil binding.
- `<f5>` reloads config.