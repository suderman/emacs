# Config reload helper

## Intent
Add a low-friction hot-reload command so Suderman can tweak Emacs config without restarting per edit. Backup for Emacs' lack of config hot-reload. Must reset global/keymap side effects so old bindings don't linger.

## Decisions
- Single command: `suderman/reload-config` bound to `<f5>` as the entry point.
- Iterate modules in `init.el` load order: paths, packages, defaults, windows, projects, completion, pickers, evil, files, markdown, languages, keys.
- For each module: clear active keymaps we know pollute (the `general` `suderman/leader` definitions, the `evil-normal/motion-state-map` dolist block, `suderman/local-leader-map`), `unload-feature` the module, re-`require`.
- Re-extract load order from `init.el` itself with a regex so we don't drift.
- Keep helper under `lisp/` as a new module `suderman-reload.el`. Auto-require at end of `init.el`.
- Bind `<f5>` in `suderman-keys.el`. Add a one-line docstring at top of file.

## Constraints
- Must not break cold start (first load with no prior state).
- Idempotent: running twice leaves the same key state.
- Don't touch `package.el` cache or session-local state (recentf, savehist) — only re-eval config modules.
- `unload-feature` may fail on some use-package modules that have `:demand t` and side effects on `evil-mode`. Mitigation: explicit `(evil-mode 1)` after reload.

## Discarded options
- `tornado.el` / file-watchers: too much surface area; many packages don't re-init cleanly.
- Restart-emacs binding: too slow for the iteration loop we want.
- Auto-reload on save via `file-notify`: same problem, with extra moving parts and no undo if reload breaks current buffer state.

## Open questions
- None blocking. Future: surface a generic "eval this file" as well via `C-c C-l` after focusing the file.

## Blast radius
No deletions. One new file + one new require + one new key binding. Safe to ship incrementally.
