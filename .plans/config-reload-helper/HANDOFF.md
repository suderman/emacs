# Config reload helper

Hot-reload Emacs config from a running session so quick keybinding edits do not require `M-x restart-emacs`.

## Usage

1. Edit any file under `lisp/suderman-*.el`.
2. Press `<f5>` (in any Evil state) or run `M-x suderman/reload-config`.
3. Modules re-`require` in load order; keymaps rebuilt; bindings updated.

If something goes sideways, `M-x restart-emacs` still works.

## What gets reloaded

All modules currently loaded by `init.el`:

```
suderman-paths
suderman-packages
suderman-defaults
suderman-windows
suderman-projects
suderman-completion
suderman-pickers
suderman-evil
suderman-files
suderman-markdown
suderman-languages
suderman-keys
```

Order is parsed from `init.el` at reload time, so adding new modules only requires extending the `require` list there.

## What does NOT get reloaded

- `early-init.el` — handled at startup.
- `package.el` archives / installed packages — already cached.
- Session-local state: recentf, savehist, bookmarks, projectile cache, etc.
- Running processes: `markdown-preview-server`, dirvish, Treemacs buffers stay alive.

## Files changed

### NEW `lisp/suderman-reload.el`

Holds `suderman/reload-config`. Steps:

1. Read `init.el`.
2. Extract ordered `(require 'suderman-X)` calls.
3. For each module, in reverse order:
   - `unload-feature` the feature (force t).
   - `unload-feature` the `suderman-keys` feature last, after stripping the `<f5>` binding we are about to dispatch.
4. Re-`require` each module in the original forward order.
5. Re-enable `evil-mode` if it was active (use-package :demand modules can wipe it during unload).
6. Echo a summary line listing the modules reloaded.

Defensive keymap cleanup before unloading `suderman-keys`:

```elisp
(dolist (map (list evil-normal-state-map evil-motion-state-map evil-visual-state-map))
  (define-key map (kbd "SPC") nil)
  (define-key map (kbd "\\") nil)
  (define-key map (kbd ",") nil))
(setq suderman/local-leader-map (make-sparse-keymap))
```

This guarantees the next `suderman/leader` call rebuilds from a clean prefix.

### NEW `lisp/` + `init.el` wire-up

Add to `init.el`, immediately after the existing requires:

```elisp
(require 'suderman-reload)
```

### MOD `lisp/suderman-keys.el`

Add one binding to the existing `dolist` block that installs normal/motion keys:

```elisp
(define-key map (kbd "<f5>") #'suderman/reload-config)
```

That is the only key change. `<f5>` is otherwise unused in this config.

## Verification

Manual smoke test, after restart so we know the cold path works:

1. Restart Emacs: `M-x restart-emacs`.
2. Open any file: `C-x C-f`.
3. Confirm `<f5>` is bound. `M-x describe-key RET <f5>` shows `suderman/reload-config`.
4. Confirm new bindings active: `SPC SPC` finds a file.
5. Edit `lisp/suderman-keys.el`, add a dummy `5` binding under leader: `"5" '(other-window :which-key "other window")`.
6. Press `<f5>`. In `*Messages*` you should see `Reloaded N modules`.
7. `SPC 5` cycles windows. Original binding gone on next reload if you delete the line.
8. `M-x describe-key RET SPC` confirms only the new prefix map is active.

If any step fails, fall back to `M-x restart-emacs` and file a follow-up task.

## Notes / caveats

- Unloading `evil` and re-requiring it can briefly disable `evil-mode` mid-reload. Re-enabled at the end of the helper.
- The `(general-create-definer suderman/leader ...)` only registers a definer; calling `(suderman/leader ...)` mutates active keymaps. The `:keymaps 'override` flag means new bindings replace old ones for the same prefix, but old bindings under the previous prefix (e.g. `\`) survive unless explicitly nil'd. The helper handles this.
- `tornado.el` / file-watcher style reloads were rejected as overkill; this stays a one-shot command bound to one key.
