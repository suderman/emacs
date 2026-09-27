;;; suderman-languages.el --- Language mode associations -*- lexical-binding: t; -*-

;;; Commentary:
;; Broad language-mode wiring that does not need a dedicated module.

;;; Code:

(require 'use-package)

(use-package treesit-auto
  :demand t
  :when (and (fboundp 'treesit-available-p) (treesit-available-p))
  :custom
  (treesit-auto-install nil)
  :config
  ;; Keep mappings static.  The global mode rebuilds every remap at each mode
  ;; probe; opening 53 Agenda files triggered it 159 times and blocked Android
  ;; for 25-30 seconds.
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode -1))

(use-package web-mode
  :mode ("\\.twig\\'" . web-mode))

(use-package php-mode
  :mode "\\.php\\'")

(use-package csv-mode
  :mode "\\.csv\\'"
  :hook (csv-mode . (lambda () (visual-line-mode -1))))

;; The VS Code HTML/CSS servers require snippet support to offer completion.
(use-package yasnippet
  :demand t)

(use-package eglot
  :ensure nil
  :config
  ;; Emacs 31 maps nix-mode to nil but lacks a nix-ts-mode entry.
  (add-to-list 'eglot-server-programs '((nix-mode nix-ts-mode) "nil")))

(defun suderman/eglot-ensure-if-available ()
  "Start Eglot when the current language server is installed."
  (let ((program (pcase major-mode
                   ((or 'php-mode 'php-ts-mode) "phpactor")
                   ((or 'nix-mode 'nix-ts-mode) "nil")
                   ((or 'lua-mode 'lua-ts-mode) "lua-language-server")
                   ((or 'html-mode 'html-ts-mode 'mhtml-mode)
                    "vscode-html-language-server")
                   ((or 'css-mode 'css-ts-mode) "vscode-css-language-server")
                   ((or 'js-mode 'js-ts-mode 'typescript-mode
                        'typescript-ts-mode 'tsx-ts-mode)
                    "typescript-language-server"))))
    (when (and program (executable-find program))
      (eglot-ensure))))

(dolist (mode '(php-mode php-ts-mode nix-mode nix-ts-mode lua-mode lua-ts-mode
                html-mode html-ts-mode mhtml-mode css-mode css-ts-mode
                js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode))
  (add-hook (intern (format "%s-hook" mode))
            #'suderman/eglot-ensure-if-available))

(add-to-list 'auto-mode-alist '("\\.zsh\\'" . sh-mode))

(provide 'suderman-languages)
;;; suderman-languages.el ends here
