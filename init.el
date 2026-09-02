;;; init.el --- Suderman's Emacs entrypoint -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep this file boring: it wires together the real configuration modules in
;; dependency order.  Personal sections live under lisp/suderman-*.el so new areas can
;; grow without turning init.el back into a monolith.

;;; Code:

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; Support mouse in emacs terminal
(xterm-mouse-mode 1)

;; Foundations: paths before packages, packages before use-package forms.
(require 'suderman-paths)
(require 'suderman-packages)
(require 'suderman-defaults)
(require 'suderman-appearance)
(require 'suderman-windows)

;; Editing building blocks.
(require 'suderman-buffers)
(require 'suderman-completion)
(require 'suderman-meow)
(require 'suderman-terminal)
(require 'suderman-files)
(require 'suderman-images)
(require 'suderman-dashboard)
(require 'suderman-markdown)
(require 'suderman-org)
(require 'suderman-languages)
(require 'suderman-nix)
(require 'suderman-git)
(require 'suderman-formatting)
(require 'suderman-pi)
(require 'suderman-reload)

;; Bind keys only after every command they invoke exists.
(require 'suderman-keys)

;; Keep Custom out of the hand-written config.
(when (file-exists-p custom-file)
  (load custom-file))

(message "Loaded Suderman's modular Emacs config")

(provide 'init)
;;; init.el ends here
