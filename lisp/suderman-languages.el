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

;; Keep routine hover text from resizing the echo area.
(setq eldoc-echo-area-use-multiline-p nil)

(use-package eglot
  :ensure nil
  :custom
  (eglot-code-action-indications '(left-fringe margin))
  :config
  ;; Emacs 31 maps nix-mode to nil but lacks a nix-ts-mode entry.
  (add-to-list 'eglot-server-programs '((nix-mode nix-ts-mode) "nil"))
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) "basedpyright-langserver" "--stdio"))
  (add-to-list 'eglot-server-programs
               '((web-mode :language-id "twig") "twiggy-language-server" "--stdio")))

(defun suderman/eglot-ensure-if-available ()
  "Start Eglot when the current language server is installed."
  (let ((program (pcase major-mode
                   ((or 'php-mode 'php-ts-mode) "phpactor")
                   ((or 'nix-mode 'nix-ts-mode) "nil")
                   ((or 'lua-mode 'lua-ts-mode) "lua-language-server")
                   ((or 'json-mode 'json-ts-mode 'jsonc-mode 'js-json-mode)
                    "vscode-json-language-server")
                   ((or 'yaml-mode 'yaml-ts-mode) "yaml-language-server")
                   ((or 'python-mode 'python-ts-mode) "basedpyright-langserver")
                   ('web-mode (when (and buffer-file-name
                                         (string-match-p "\\.twig\\'" buffer-file-name))
                                "twiggy-language-server"))
                   ((or 'html-mode 'html-ts-mode 'mhtml-mode)
                    "vscode-html-language-server")
                   ((or 'css-mode 'css-ts-mode) "vscode-css-language-server")
                   ((or 'js-mode 'js-ts-mode 'typescript-mode
                        'typescript-ts-mode 'tsx-ts-mode)
                    "typescript-language-server"))))
    (when (and program (executable-find program))
      (eglot-ensure))))

;; Envrc updates the buffer's PATH after its major-mode hook runs.
(add-hook 'after-change-major-mode-hook #'suderman/eglot-ensure-if-available t)

(add-to-list 'auto-mode-alist '("\\.zsh\\'" . sh-mode))

(provide 'suderman-languages)
;;; suderman-languages.el ends here
