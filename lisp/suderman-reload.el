;;; suderman-reload.el --- Hot reload modular config -*- lexical-binding: t; -*-

;;; Commentary:
;; Reload the Suderman config modules from a running Emacs session.  This is
;; aimed at quick keybinding and command edits; restart-emacs remains the escape
;; hatch for package, early-init, and process-level changes.  Meow's Normal and
;; Motion maps are rebuilt from a stock snapshot, so deleted bindings disappear.
;; Bindings deleted from other packages' maps stay until restart.

;;; Code:

(require 'subr-x)

(defvar meow-global-mode)
(declare-function meow-global-mode "meow-core" (&optional arg))

(defconst suderman/reload-excluded-features '(suderman-reload)
  "Suderman features that `suderman/reload-config' should not unload.")

(defun suderman/reload--quoted-symbol (form)
  "Return the quoted symbol in FORM, or nil."
  (when (and (consp form)
             (eq (car form) 'quote)
             (symbolp (cadr form)))
    (cadr form)))

(defun suderman/reload--user-init-file ()
  "Return the init file path used by `suderman/reload-config'."
  (let ((file (or user-init-file
                  (expand-file-name "init.el" user-emacs-directory))))
    (if (string-suffix-p ".elc" file)
        (string-remove-suffix "c" file)
      file)))

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

;;;###autoload
(defun suderman/pull-config ()
  "Run `git pull' asynchronously in `user-emacs-directory'."
  (interactive)
  (let ((default-directory user-emacs-directory))
    (async-shell-command "git pull" "*Emacs config pull*")))

(defun suderman/reload--unload-feature (feature)
  "Unload FEATURE when it is loaded."
  (when (featurep feature)
    (unload-feature feature t)))

(defun suderman/reload--restore-major-modes (buffer-modes)
  "Restore BUFFER-MODES changed while unloading configuration modules."
  (dolist (entry buffer-modes)
    (let ((buffer (car entry))
          (mode (cdr entry)))
      (when (and (buffer-live-p buffer)
                 (not (eq (buffer-local-value 'major-mode buffer) mode))
                 (fboundp mode))
        (with-current-buffer buffer
          (funcall mode))))))

;;;###autoload
(defun suderman/reload-config ()
  "Reload Suderman config modules without restarting Emacs."
  (interactive)
  (let* ((modules (suderman/reload--config-modules))
         (buffer-modes
          (mapcar (lambda (buffer)
                    (cons buffer (buffer-local-value 'major-mode buffer)))
                  (buffer-list)))
         (meow-was-enabled (bound-and-true-p meow-global-mode)))
    (unless modules
      (user-error "No suderman modules found in %s"
                  (suderman/reload--user-init-file)))
    (dolist (feature (reverse modules))
      (suderman/reload--unload-feature feature))
    (dolist (feature modules)
      (require feature))
    (suderman/reload--restore-major-modes buffer-modes)
    (when (and meow-was-enabled
               (not (bound-and-true-p meow-global-mode))
               (fboundp 'meow-global-mode))
      (meow-global-mode 1))
    (message "Reloaded %d modules: %s"
             (length modules)
             (mapconcat #'symbol-name modules ", "))))

(provide 'suderman-reload)
;;; suderman-reload.el ends here
