;;; suderman-reload.el --- Hot reload modular config -*- lexical-binding: t; -*-

;;; Commentary:
;; Reload the Suderman config modules from a running Emacs session.  This is
;; aimed at quick keybinding and command edits; restart-emacs remains the escape
;; hatch for package, early-init, and process-level changes.

;;; Code:

(require 'subr-x)

(defvar meow-global-mode)
(defvar meow-motion-state-keymap)
(defvar meow-normal-state-keymap)
(defvar suderman/meow-leader-map)
(declare-function meow-global-mode "meow-core" (&optional arg))
(declare-function suderman/meow-reset-leader-map "suderman-meow" ())

(defconst suderman/reload-excluded-features '(suderman-reload)
  "Suderman features that `suderman/reload-config' should not unload.")

(defconst suderman/reload-modal-keys
  '("<f5>"
    "M-p" "M-g"
    "M-h" "M-j" "M-k" "M-l" "M-;"
    "M-H" "M-J" "M-K" "M-L"
    "M-u" "M-i" "M-U" "M-I" "M-w")
  "Meow modal keys rebuilt by `suderman-keys'.")

(defun suderman/reload--quoted-symbol (form)
  "Return the quoted symbol in FORM, or nil."
  (when (and (consp form)
             (eq (car form) 'quote)
             (symbolp (cadr form)))
    (cadr form)))

(defun suderman/reload--user-init-file ()
  "Return the init file path used by `suderman/reload-config'."
  (or user-init-file
      (expand-file-name "init.el" user-emacs-directory)))

(defun suderman/reload--config-modules ()
  "Return ordered `suderman-*' modules required by the user init file."
  (let ((init-file (suderman/reload--user-init-file))
        features)
    (with-temp-buffer
      (insert-file-contents init-file)
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
  "Remove rebuilt modal bindings from MAP."
  (when (keymapp map)
    (dolist (key suderman/reload-modal-keys)
      (define-key map (kbd key) nil))))

(defun suderman/reload--clear-keymap-symbol (map-symbol)
  "Remove rebuilt modal bindings from MAP-SYMBOL."
  (when (boundp map-symbol)
    (suderman/reload--clear-keymap (symbol-value map-symbol))))

(defun suderman/reload--clear-keys ()
  "Remove rebuilt key prefixes before unloading `suderman-keys'."
  (dolist (map-symbol '(meow-normal-state-keymap meow-motion-state-keymap))
    (suderman/reload--clear-keymap-symbol map-symbol))
  (global-set-key (kbd "<f5>") nil)
  (when (fboundp 'suderman/meow-reset-leader-map)
    (suderman/meow-reset-leader-map)))

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
         (meow-was-enabled (bound-and-true-p meow-global-mode)))
    (unless modules
      (user-error "No suderman modules found in %s"
                  (suderman/reload--user-init-file)))
    (dolist (feature (reverse modules))
      (suderman/reload--unload-feature feature))
    (dolist (feature modules)
      (require feature))
    (when (and meow-was-enabled
               (not (bound-and-true-p meow-global-mode))
               (fboundp 'meow-global-mode))
      (meow-global-mode 1))
    (message "Reloaded %d modules: %s"
             (length modules)
             (mapconcat #'symbol-name modules ", "))))

(provide 'suderman-reload)
;;; suderman-reload.el ends here
