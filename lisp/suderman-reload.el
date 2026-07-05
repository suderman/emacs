;;; suderman-reload.el --- Hot reload modular config -*- lexical-binding: t; -*-

;;; Commentary:
;; Reload the Suderman config modules from a running Emacs session.  This is
;; aimed at quick keybinding and command edits; restart-emacs remains the escape
;; hatch for package, early-init, and process-level changes.

;;; Code:

(require 'subr-x)

(defvar suderman/local-leader-map)
(defvar evil-mode)
(declare-function evil-mode "evil" (&optional arg))
(declare-function evil-get-auxiliary-keymap
                  "evil-core" (map state &optional create ignore-parent))

(defconst suderman/reload-excluded-features '(suderman-reload)
  "Suderman features that `suderman/reload-config' should not unload.")

(defun suderman/reload--quoted-symbol (form)
  "Return the quoted symbol in FORM, or nil."
  (when (and (consp form)
             (eq (car form) 'quote)
             (symbolp (cadr form)))
    (cadr form)))

(defun suderman/reload--config-modules ()
  "Return ordered `suderman-*' modules required by `user-init-file'."
  (let (features)
    (with-temp-buffer
      (insert-file-contents user-init-file)
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let* ((form (read (current-buffer)))
                   (feature (and (consp form)
                                 (eq (car form) 'require)
                                 (suderman/reload--quoted-symbol (cadr form)))))
              (when (and feature
                         (string-prefix-p "suderman-" (symbol-name feature))
                         (not (memq feature features))
                         (not (memq feature suderman/reload-excluded-features)))
                (push feature features))))
        (end-of-file nil)))
    (nreverse features)))

(defun suderman/reload--clear-keymap (map)
  "Remove leader bindings from MAP before rebuilding them."
  (when (keymapp map)
    (dolist (key '("SPC" "\\" "," "<f5>"))
      (define-key map (kbd key) nil))))

(defun suderman/reload--clear-evil-auxiliary-keymaps (map)
  "Remove leader bindings from Evil auxiliary keymaps under MAP."
  ;; `general' stores `:keymaps 'override' state bindings here, so direct
  ;; `define-key' cleanup on the parent map does not remove stale leaders.
  (when (and (keymapp map)
             (fboundp 'evil-get-auxiliary-keymap))
    (dolist (state '(normal motion visual))
      (when-let ((aux (evil-get-auxiliary-keymap map state nil t)))
        (suderman/reload--clear-keymap aux)))))

(defun suderman/reload--clear-keymap-symbol (map-symbol)
  "Remove leader bindings from MAP-SYMBOL and its Evil auxiliary maps."
  (when (boundp map-symbol)
    (let ((map (symbol-value map-symbol)))
      (suderman/reload--clear-keymap map)
      (suderman/reload--clear-evil-auxiliary-keymaps map))))

(defun suderman/reload--clear-keys ()
  "Remove rebuilt key prefixes before unloading `suderman-keys'."
  (dolist (map-symbol '(evil-normal-state-map
                        evil-motion-state-map
                        evil-visual-state-map
                        evil-normal-state-local-map
                        evil-motion-state-local-map
                        evil-visual-state-local-map
                        general-override-mode-map))
    (suderman/reload--clear-keymap-symbol map-symbol))
  (setq suderman/local-leader-map (make-sparse-keymap)))

(defun suderman/reload--unload-feature (feature)
  "Unload FEATURE, clearing keymaps first when needed."
  (when (eq feature 'suderman-keys)
    (suderman/reload--clear-keys))
  (when (featurep feature)
    (unload-feature feature t)))

;;;###autoload
(defun suderman/reload-config ()
  "Reload Suderman config modules without restarting Emacs."
  (interactive)
  (let* ((modules (suderman/reload--config-modules))
         (evil-was-enabled (bound-and-true-p evil-mode)))
    (unless modules
      (user-error "No suderman modules found in %s" user-init-file))
    (dolist (feature (reverse modules))
      (suderman/reload--unload-feature feature))
    (dolist (feature modules)
      (require feature))
    (when (and evil-was-enabled (fboundp 'evil-mode))
      (evil-mode 1))
    (message "Reloaded %d modules: %s"
             (length modules)
             (mapconcat #'symbol-name modules ", "))))

(provide 'suderman-reload)
;;; suderman-reload.el ends here
