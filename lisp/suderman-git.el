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
(declare-function meow-insert "meow")
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

(defun suderman/git-commit-start-insert ()
  "Enter Meow Insert state when the commit summary is blank."
  (when (and (bound-and-true-p meow-mode) (bobp) (eolp))
    (meow-insert)))

(use-package magit
  :commands (magit-branch-checkout
             magit-stage-files
             magit-unstage-files
             magit-log-current
             magit-blame-addition
             magit-blame-echo
             magit-diff-buffer-file
             magit-dispatch
             magit-file-dispatch
             magit-log-buffer-file
             magit-status)
  :init
  (setq magit-display-buffer-function
        #'magit-display-buffer-same-window-except-diff-v1
        magit-diff-refine-hunk t
        magit-revision-insert-related-refs nil)
  :config
  (add-hook 'after-save-hook #'magit-after-save-refresh-status)
  (add-hook 'magit-mode-hook #'suderman/magit-setup)
  (add-hook 'git-commit-setup-hook #'suderman/git-commit-start-insert)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
  (keymap-set magit-mode-map "." #'magit-mode-bury-buffer)
  (keymap-set magit-mode-map "C-SPC" #'meow-keypad)
  (keymap-set magit-mode-map "M-h" #'edger-left)
  (keymap-set magit-mode-map "M-j" #'edger-down)
  (keymap-set magit-mode-map "M-k" #'edger-up)
  (keymap-set magit-mode-map "M-l" #'edger-right)
  (keymap-set magit-mode-map "M-H" #'edger-resize-left)
  (keymap-set magit-mode-map "M-J" #'edger-resize-down)
  (keymap-set magit-mode-map "M-K" #'edger-resize-up)
  (keymap-set magit-mode-map "M-L" #'edger-resize-right)
  (keymap-set magit-mode-map "M-u" #'edger-horizontal)
  (keymap-set magit-mode-map "M-i" #'edger-vertical)
  (keymap-set magit-mode-map "M-w" #'edger-close)
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
