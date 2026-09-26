;;; suderman-keys.el --- Global Meow and leader bindings -*- lexical-binding: t; -*-

;;; Commentary:
;; Load keybindings after commands exist.  Meow owns modal editing; this file
;; owns personal global shortcuts and the SPC leader groups that do not collide
;; with Meow's vanilla keypad prefixes.

;;; Code:

(require 'use-package)
(require 'suderman-appearance)
(require 'suderman-buffers)
(require 'suderman-completion)
(require 'suderman-meow)
(require 'suderman-files)
(require 'suderman-git)
(require 'suderman-org)
(require 'suderman-reload)
(require 'suderman-terminal)
(require 'suderman-windows)

(defun suderman/keys--define-modal (key command)
  "Bind KEY to COMMAND in Meow normal and motion states."
  (meow-normal-define-key (cons key command))
  (meow-motion-define-key (cons key command)))

(defvar suderman/leader-buffer-map nil
  "SPC b buffer command keymap.")
(defvar suderman/leader-file-map nil
  "SPC f file command keymap.")
(defvar suderman/leader-git-map nil
  "SPC . Git command keymap.")
(defvar suderman/leader-git-conflict-map nil
  "SPC . c conflict command keymap.")
(defvar suderman/leader-git-hunk-map nil
  "SPC . h hunk command keymap.")
(defvar suderman/leader-org-map nil
  "SPC o Org command keymap.")
(defvar suderman/leader-search-map nil
  "SPC s search command keymap.")
(defvar suderman/leader-toggle-map nil
  "SPC t toggle command keymap.")
(defvar suderman/leader-window-map nil
  "SPC w window command keymap.")
(defvar suderman/leader-quit-map nil
  "SPC q quit/reload command keymap.")

(setq suderman/leader-buffer-map (make-sparse-keymap)
      suderman/leader-file-map (make-sparse-keymap)
      suderman/leader-git-map (make-sparse-keymap)
      suderman/leader-git-conflict-map (make-sparse-keymap)
      suderman/leader-git-hunk-map (make-sparse-keymap)
      suderman/leader-org-map (make-sparse-keymap)
      suderman/leader-search-map (make-sparse-keymap)
      suderman/leader-toggle-map (make-sparse-keymap)
      suderman/leader-window-map (make-sparse-keymap)
      suderman/leader-quit-map (make-sparse-keymap))

;; Buffers
(keymap-set suderman/leader-buffer-map "b" #'consult-buffer)
(keymap-set suderman/leader-buffer-map "i" #'ibuffer)
(keymap-set suderman/leader-buffer-map "k" #'kill-current-buffer)
(keymap-set suderman/leader-buffer-map "l" #'suderman/alternate-buffer)
(keymap-set suderman/leader-buffer-map "n" #'next-buffer)
(keymap-set suderman/leader-buffer-map "p" #'previous-buffer)
(keymap-set suderman/leader-buffer-map "r" #'suderman/revert-buffer-no-confirm)
(keymap-set suderman/leader-buffer-map "s" #'save-buffer)

;; Files
(keymap-set suderman/leader-file-map "." #'suderman/dirvish)
(keymap-set suderman/leader-file-map "f" #'consult-fd)
(keymap-set suderman/leader-file-map "g" #'consult-ripgrep)
(keymap-set suderman/leader-file-map "r" #'consult-recent-file)
(keymap-set suderman/leader-file-map "s" #'save-buffer)
(keymap-set suderman/leader-file-map "S" #'write-file)

;; Git
(keymap-set suderman/leader-git-map "B" #'magit-blame-addition)
(keymap-set suderman/leader-git-map "b" #'magit-blame-echo)
(keymap-set suderman/leader-git-map "c" suderman/leader-git-conflict-map)
(keymap-set suderman/leader-git-map "d" #'magit-diff-buffer-file)
(keymap-set suderman/leader-git-map "f" #'magit-file-dispatch)
(keymap-set suderman/leader-git-map "." #'magit-status)
(keymap-set suderman/leader-git-map "h" suderman/leader-git-hunk-map)
(keymap-set suderman/leader-git-map "l" #'magit-log-buffer-file)
(keymap-set suderman/leader-git-map "m" #'magit-dispatch)

;; Git hunks
(keymap-set suderman/leader-git-hunk-map "d" #'diff-hl-diff-goto-hunk)
(keymap-set suderman/leader-git-hunk-map "n" #'diff-hl-next-hunk)
(keymap-set suderman/leader-git-hunk-map "p" #'diff-hl-previous-hunk)
(keymap-set suderman/leader-git-hunk-map "r" #'diff-hl-revert-hunk)
(keymap-set suderman/leader-git-hunk-map "s" #'diff-hl-stage-current-hunk)
(keymap-set suderman/leader-git-hunk-map "u" #'diff-hl-unstage-file)
(keymap-set suderman/leader-git-hunk-map "v" #'diff-hl-show-hunk)

;; Git conflicts
(keymap-set suderman/leader-git-conflict-map "0" #'smerge-kill-current)
(keymap-set suderman/leader-git-conflict-map "a" #'smerge-keep-all)
(keymap-set suderman/leader-git-conflict-map "b" #'smerge-keep-base)
(keymap-set suderman/leader-git-conflict-map "e" #'smerge-ediff)
(keymap-set suderman/leader-git-conflict-map "l" #'smerge-keep-lower)
(keymap-set suderman/leader-git-conflict-map "n" #'smerge-next)
(keymap-set suderman/leader-git-conflict-map "p" #'smerge-prev)
(keymap-set suderman/leader-git-conflict-map "r" #'smerge-refine)
(keymap-set suderman/leader-git-conflict-map "u" #'smerge-keep-upper)

;; Org
(keymap-set suderman/leader-org-map "a" #'org-agenda)
(keymap-set suderman/leader-org-map "A" #'suderman/org-archive)
(keymap-set suderman/leader-org-map "B" #'suderman/org-archive-done)
(keymap-set suderman/leader-org-map "c" #'org-capture)
(keymap-set suderman/leader-org-map "d" #'suderman/org-deadline)
(keymap-set suderman/leader-org-map "e" #'suderman/org-export)
(keymap-set suderman/leader-org-map "g" #'suderman/org-heading)
(keymap-set suderman/leader-org-map "i" #'suderman/org-insert-link)
(keymap-set suderman/leader-org-map "l" #'org-store-link)
(keymap-set suderman/leader-org-map "n" #'org-toggle-narrow-to-subtree)
(keymap-set suderman/leader-org-map "r" #'suderman/org-refile)
(keymap-set suderman/leader-org-map "s" #'suderman/org-schedule)
(keymap-set suderman/leader-org-map "t" #'suderman/org-todo)
(keymap-set suderman/leader-org-map "T" #'org-todo-list)
(keymap-set suderman/leader-org-map "o" #'suderman/org-dashboard)
(keymap-set suderman/leader-org-map "x" #'suderman/org-toggle-checkbox)

;; Search
(keymap-set suderman/leader-search-map "c" #'suderman/clear-search)
(keymap-set suderman/leader-search-map "i" #'consult-imenu)
(keymap-set suderman/leader-search-map "l" #'consult-line)

;; Toggles
(keymap-set suderman/leader-toggle-map "c" #'display-fill-column-indicator-mode)
(keymap-set suderman/leader-toggle-map "d" #'suderman/dirvish-side-toggle)
(keymap-set suderman/leader-toggle-map "h" #'hl-line-mode)
(keymap-set suderman/leader-toggle-map "n" #'suderman/toggle-line-numbers)
(keymap-set suderman/leader-toggle-map "o" #'org-indent-mode)
(keymap-set suderman/leader-toggle-map "r" #'read-only-mode)
(when (fboundp 'jinx-mode)
  (keymap-set suderman/leader-toggle-map "s" #'jinx-mode))
(keymap-set suderman/leader-toggle-map "v" #'visual-line-mode)
(keymap-set suderman/leader-toggle-map "w" #'whitespace-mode)

;; Windows
(keymap-set suderman/leader-window-map "=" #'balance-windows)
(keymap-set suderman/leader-window-map "h" #'edger-left)
(keymap-set suderman/leader-window-map "j" #'edger-down)
(keymap-set suderman/leader-window-map "k" #'edger-up)
(keymap-set suderman/leader-window-map "l" #'edger-right)
(keymap-set suderman/leader-window-map "H" #'edger-resize-left)
(keymap-set suderman/leader-window-map "J" #'edger-resize-down)
(keymap-set suderman/leader-window-map "K" #'edger-resize-up)
(keymap-set suderman/leader-window-map "L" #'edger-resize-right)
(keymap-set suderman/leader-window-map "u" #'edger-horizontal)
(keymap-set suderman/leader-window-map "i" #'edger-vertical)
(keymap-set suderman/leader-window-map "o" #'delete-other-windows)
(keymap-set suderman/leader-window-map "w" #'edger-close)

;; Quit/reload
(keymap-set suderman/leader-quit-map "r" #'suderman/reload-config)

(setq tab-bar-close-last-tab-choice 'delete-frame)

(global-set-key (kbd "<escape>") #'suderman/meow-escape)
(global-set-key (kbd "<f5>") #'suderman/reload-config)
(global-set-key (kbd "<f6>") #'suderman/pull-config)
(global-set-key (kbd "<f9>") #'tool-bar-mode)
(global-set-key (kbd "s-+") #'suderman/frame-text-scale-increase)
(global-set-key (kbd "s-=") #'suderman/frame-text-scale-increase)
(global-set-key (kbd "s--") #'suderman/frame-text-scale-decrease)
(global-set-key (kbd "s-_") #'suderman/frame-text-scale-decrease)
(global-set-key (kbd "s-t") #'tab-new)
(global-set-key (kbd "s-[") #'tab-previous)
(global-set-key (kbd "s-]") #'tab-next)
(global-set-key (kbd "s-w") #'tab-close)
(global-set-key (kbd "M-z") #'suderman/zoom-window-toggle)
(global-set-key (kbd "M-h") #'edger-left)
(global-set-key (kbd "M-j") #'edger-down)
(global-set-key (kbd "M-k") #'edger-up)
(global-set-key (kbd "M-l") #'edger-right)
(global-set-key (kbd "M-H") #'edger-resize-left)
(global-set-key (kbd "M-J") #'edger-resize-down)
(global-set-key (kbd "M-K") #'edger-resize-up)
(global-set-key (kbd "M-L") #'edger-resize-right)
(global-set-key (kbd "M-u") #'edger-horizontal)
(global-set-key (kbd "M-i") #'edger-vertical)
(global-set-key (kbd "M-w") #'edger-close)
(global-set-key (kbd "C-x 0") #'suderman/delete-window-or-tab)

(dolist (binding '(("<f5>" . suderman/reload-config)
                   ("<f6>" . suderman/pull-config)
                   ("<f9>" . tool-bar-mode)
                   ("M-p" . consult-recent-file)
                   ("M-h" . edger-left)
                   ("M-j" . edger-down)
                   ("M-k" . edger-up)
                   ("M-l" . edger-right)
                   ("M-H" . edger-resize-left)
                   ("M-J" . edger-resize-down)
                   ("M-K" . edger-resize-up)
                   ("M-L" . edger-resize-right)
                   ("M-u" . edger-horizontal)
                   ("M-i" . edger-vertical)
                   ("M-U" . suderman/split-window-below-and-focus)
                   ("M-I" . suderman/split-window-right-and-focus)
                   ("M-w" . edger-close)))
  (suderman/keys--define-modal (car binding) (cdr binding)))

(use-package which-key
  :demand t
  :init
  (setq which-key-idle-delay 0.35)
  :config
  (which-key-mode 1))

(suderman/meow-reset-leader-map)
(meow-leader-define-key
 '("1" . meow-digit-argument)
 '("2" . meow-digit-argument)
 '("3" . meow-digit-argument)
 '("4" . meow-digit-argument)
 '("5" . meow-digit-argument)
 '("6" . meow-digit-argument)
 '("7" . meow-digit-argument)
 '("8" . meow-digit-argument)
 '("9" . meow-digit-argument)
 '("0" . meow-digit-argument)
 '("?" . meow-cheatsheet)
 '("SPC" . execute-extended-command)
 (cons "." suderman/leader-git-map)
 (cons "b" suderman/leader-buffer-map)
 (cons "f" suderman/leader-file-map)
 (cons "o" suderman/leader-org-map)
 (cons "q" suderman/leader-quit-map)
 (cons "s" suderman/leader-search-map)
 (cons "t" suderman/leader-toggle-map)
 (cons "w" suderman/leader-window-map))
(when (fboundp 'ghostel-project)
  (meow-leader-define-key '("RET" . ghostel-project)))

(which-key-add-keymap-based-replacements
  suderman/meow-leader-map
  "." (cons "git" suderman/leader-git-map)
  "b" (cons "buffers" suderman/leader-buffer-map)
  "f" (cons "files" suderman/leader-file-map)
  "o" (cons "org" suderman/leader-org-map)
  "q" (cons "quit/reload" suderman/leader-quit-map)
  "s" (cons "search" suderman/leader-search-map)
  "t" (cons "toggles" suderman/leader-toggle-map)
  "w" (cons "windows" suderman/leader-window-map))

(which-key-add-keymap-based-replacements
  suderman/leader-toggle-map
  "c" "column indicator"
  "d" "dirvish sidebar"
  "h" "current line"
  "n" "line numbers"
  "o" "org indentation"
  "r" "read only"
  "s" "spelling"
  "v" "visual lines"
  "w" "whitespace")

(which-key-add-keymap-based-replacements
  suderman/leader-git-map
  "c" (cons "conflicts" suderman/leader-git-conflict-map)
  "h" (cons "hunks" suderman/leader-git-hunk-map))

(provide 'suderman-keys)
;;; suderman-keys.el ends here
