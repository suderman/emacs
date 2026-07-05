;;; suderman-evil.el --- Evil modal editing setup -*- lexical-binding: t; -*-

;;; Commentary:
;; Core Evil behavior lives here.  Most user-facing keybindings are in suderman-keys
;; so package modules can load first and keymaps stay easy to scan.

;;; Code:

(require 'use-package)

(defun suderman/clear-search ()
  "Clear Evil search highlighting."
  (interactive)
  (evil-ex-nohighlight))

(defun suderman/evil-shift-left-visual (beg end)
  "Outdent the visual selection and keep it selected."
  (interactive "r")
  (evil-shift-left beg end)
  (evil-normal-state)
  (evil-visual-restore))

(defun suderman/evil-shift-right-visual (beg end)
  "Indent the visual selection and keep it selected."
  (interactive "r")
  (evil-shift-right beg end)
  (evil-normal-state)
  (evil-visual-restore))

(use-package evil
  :demand t
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil
        evil-want-C-u-scroll t
        evil-want-C-i-jump nil
        evil-respect-visual-line-mode t
        evil-undo-system 'undo-redo)
  :config
  (evil-mode 1)
  ;; Use jk as a low-friction escape hatch from insert state.
  (define-key evil-insert-state-map (kbd "j k") #'evil-normal-state)
  (define-key evil-insert-state-map (kbd "M-h") #'left-char)
  (define-key evil-insert-state-map (kbd "M-j") #'next-line)
  (define-key evil-insert-state-map (kbd "M-k") #'previous-line)
  (define-key evil-insert-state-map (kbd "M-l") #'right-char)
  (define-key evil-insert-state-map (kbd "C-l") (lambda () (interactive) (insert " "))))

(use-package evil-collection
  :after evil
  :demand t
  :config
  ;; Let Evil Collection handle special modes, but keep Treemacs on its own
  ;; keymap. Treemacs' mouse bindings work correctly in Evil's emacs state, and
  ;; evil-treemacs/normal-state mouse handling interferes with double-click.
  (setq evil-collection-mode-list
        (delq 'treemacs evil-collection-mode-list))
  (evil-collection-init))

(provide 'suderman-evil)
;;; suderman-evil.el ends here
