;;; suderman-git.el --- Git status, hunks, and conflicts -*- lexical-binding: t; -*-

;;; Commentary:
;; Magit owns repository operations, diff-hl shows live file changes, and
;; built-in smerge-mode handles conflict markers.

;;; Code:

(require 'smerge-mode)
(require 'use-package)
(require 'suderman-windows)

(declare-function magit-after-save-refresh-status "magit-mode")
(declare-function magit-display-buffer-same-window-except-diff-v1 "magit-mode")
(declare-function magit-mode-bury-buffer "magit-mode")
(declare-function magit-section-backward "magit-section")
(declare-function magit-section-forward "magit-section")
(declare-function meow--disable "meow")
(declare-function meow-mode "meow")
(declare-function transient-quit-one "transient")

(use-package transient
  :ensure nil
  :config
  (keymap-set transient-base-map "<escape>" #'transient-quit-one))

(defun suderman/magit-disable-meow ()
  "Disable Meow in the current Magit buffer."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/magit-setup ()
  "Let Magit's native keys own the current buffer."
  (add-hook 'meow-mode-hook #'suderman/magit-disable-meow nil t)
  (suderman/magit-disable-meow)
  (keymap-local-set "j" #'magit-section-forward)
  (keymap-local-set "k" #'magit-section-backward))

(use-package magit
  :commands (magit-blame-addition
             magit-blame-echo
             magit-diff-buffer-file
             magit-dispatch
             magit-file-dispatch
             magit-log-buffer-file
             magit-status)
  :init
  (setq magit-display-buffer-function
        #'magit-display-buffer-same-window-except-diff-v1)
  :config
  (add-hook 'after-save-hook #'magit-after-save-refresh-status)
  (add-hook 'magit-mode-hook #'suderman/magit-setup)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
  (keymap-set magit-mode-map "," #'magit-mode-bury-buffer)
  (keymap-set magit-mode-map "M-h" #'suderman/window-left)
  (keymap-set magit-mode-map "M-j" #'windmove-down)
  (keymap-set magit-mode-map "M-k" #'windmove-up)
  (keymap-set magit-mode-map "M-l" #'windmove-right)
  (keymap-set magit-mode-map "M-H" #'suderman/resize-window-left)
  (keymap-set magit-mode-map "M-J" #'suderman/resize-window-down)
  (keymap-set magit-mode-map "M-K" #'suderman/resize-window-up)
  (keymap-set magit-mode-map "M-L" #'suderman/resize-window-right)
  (keymap-set magit-mode-map "M-u" #'suderman/split-window-below-and-focus)
  (keymap-set magit-mode-map "M-i" #'suderman/split-window-right-and-focus)
  (keymap-set magit-mode-map "M-w" #'suderman/delete-window-or-tab)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'magit-mode)
        (suderman/magit-setup)))))

(use-package diff-hl
  :demand t
  :config
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1))

(provide 'suderman-git)
;;; suderman-git.el ends here
