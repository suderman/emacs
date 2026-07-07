;;; init.el --- Suderman's Emacs entrypoint -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep this file boring: it wires together the real configuration modules in
;; dependency order.  Personal sections live under lisp/suderman-*.el so new areas can
;; grow without turning init.el back into a monolith.

;;; Code:

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; Foundations: paths before packages, packages before use-package forms.
(require 'suderman-paths)
(require 'suderman-packages)
(require 'suderman-defaults)
(require 'suderman-appearance)
(require 'suderman-windows)

;; Editing building blocks.
(require 'suderman-projects)
(require 'suderman-completion)
(require 'suderman-pickers)
(require 'suderman-meow)
(require 'suderman-files)
(require 'suderman-markdown)
(require 'suderman-languages)
(require 'suderman-keys)
(require 'suderman-reload)

;; Keep Custom out of the hand-written config.
(when (file-exists-p custom-file)
  (load custom-file))

(message "Loaded Suderman's modular Emacs config")

(provide 'init)
;;; init.el ends here
