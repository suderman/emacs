;;; suderman-languages.el --- Language mode associations -*- lexical-binding: t; -*-

;;; Commentary:
;; Broad language-mode wiring that does not need a dedicated module yet.
;; Promote sections out of here when they gain custom commands or larger setup.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'use-package)
(require 'suderman-markdown)

(defconst suderman/nix-embedded-languages '(bash elisp html lua python))

;; Tree-sitter capture names cannot contain the usual `suderman/' separator.
(defun suderman--nix-fontify-elisp-symbol (node override start end &rest _)
  "Fontify Elisp symbol NODE like `emacs-lisp-mode'."
  (let* ((symbol (intern-soft (treesit-node-text node t)))
         (parent (treesit-node-parent node))
         (function-position
          (and parent
               (equal (treesit-node-type parent) "list")
               (treesit-node-eq node (treesit-node-child parent 0 t))))
         (face
          (cond
           ((and function-position
                 (memq symbol '(cl-assert cl-check-type error signal
                                         user-error warn)))
            'font-lock-warning-face)
           ((and function-position
                 symbol
                 (or (special-form-p symbol) (macrop symbol))
                 (not (get symbol 'no-font-lock-keyword)))
            'font-lock-keyword-face)
           (t 'default))))
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     face override start end)))

(defun suderman/nix-embedded-language (node)
  "Return the supported language named by Nix comment NODE."
  (let ((language
         (intern-soft
          (string-trim
           (string-remove-prefix "#" (treesit-node-text node t))))))
    (when (eq language 'sh)
      (setq language 'bash))
    (and (memq language suderman/nix-embedded-languages)
         (treesit-language-available-p language)
         language)))

(defun suderman/nix-embedded-font-lock-settings ()
  "Return font-lock settings for supported languages in Nix strings."
  (require 'html-ts-mode)
  (require 'lua-ts-mode)
  (require 'python)
  (require 'sh-script)
  (let* ((elisp-query
         (with-temp-buffer
           (insert-file-contents
            (expand-file-name "assets/elisp-highlights.scm"
                              user-emacs-directory))
           (buffer-string)))
        (settings
         `((bash . ,(symbol-value 'sh-mode--treesit-settings))
           (elisp . ,(treesit-font-lock-rules
                       :language 'elisp
                       :feature 'embedded
                       :override t
                       elisp-query))
           (html . ,(symbol-value 'html-ts-mode--font-lock-settings))
           (lua . ,(symbol-value 'lua-ts--font-lock-settings))
           (python . ,(symbol-value 'python--treesit-settings)))))
    (cl-mapcan
     (lambda (entry)
       (cl-mapcan
        (lambda (setting)
          (treesit-font-lock-rules
           :language (car entry)
           :feature 'embedded
           :override t
           (treesit-font-lock-setting-query setting)))
        (cdr entry)))
     settings)))

(defun suderman/nix-embedded-languages-setup ()
  "Fontify Nix indented strings according to the preceding comment."
  (unless (memq 'embedded (apply #'append treesit-font-lock-feature-list))
    (setq-local treesit-primary-parser
                (or treesit-primary-parser (car (treesit-parser-list))))
    (setq-local treesit-range-settings
                (treesit-range-rules
                 :embed #'suderman/nix-embedded-language
                 :host 'nix
                 :local t
                 "((comment) @language
                   .
                   (indented_string_expression
                    (string_fragment) @content))"))
    (setq-local treesit-language-at-point-function
                #'treesit-language-at-point-default)
    (setq-local treesit-font-lock-settings
                (append treesit-font-lock-settings
                        (suderman/nix-embedded-font-lock-settings)))
    (setq-local treesit-font-lock-feature-list
                (treesit-merge-font-lock-feature-list
                 treesit-font-lock-feature-list '((embedded))))
    (treesit-update-ranges)
    (treesit-font-lock-recompute-features)
    (font-lock-flush)))

(use-package treesit-auto
  :demand t
  :when (and (fboundp 'treesit-available-p) (treesit-available-p))
  :custom
  (treesit-auto-install nil)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

(use-package nix-ts-mode
  :mode "\\.nix\\'"
  :hook (nix-ts-mode . suderman/nix-embedded-languages-setup))

(use-package web-mode
  :mode ("\\.twig\\'" . web-mode))

(use-package php-mode
  :mode "\\.php\\'")

(add-to-list 'auto-mode-alist '("\\.zsh\\'" . sh-mode))

(provide 'suderman-languages)
;;; suderman-languages.el ends here
