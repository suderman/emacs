;;; suderman-keys.el --- Global keys and the SPC leader -*- lexical-binding: t; -*-

;;; Commentary:
;; Load after every command module.  Meow's Normal and Motion maps live in
;; `suderman-meow'; window keys live in `suderman-windows'.  This file owns
;; global shortcuts and the SPC leader.
;;
;; A ("label" . command) binding shows that label in Which-Key.  After an
;; edit, evaluate the changed form with C-M-x or reload everything with F5.

;;; Code:

(require 'use-package)
(require 'suderman-appearance)
(require 'suderman-buffers)
(require 'suderman-completion)
(require 'suderman-meow)
(require 'suderman-files)
(require 'suderman-git)
(require 'suderman-help)
(require 'suderman-mail)
(require 'suderman-org)
(require 'suderman-reload)
(require 'suderman-terminal)
(require 'suderman-windows)

(use-package which-key
  :ensure nil
  :demand t
  :init
  (setq which-key-idle-delay 0.35)
  :config
  (which-key-mode 1))

;;;; Global keys

(define-keymap :keymap global-map
  "<escape>" #'suderman/meow-escape
  "C-<escape>" #'top-level
  "C-c C-g" #'top-level
  "C-c h" #'suderman/cheatsheet
  "C-c m" #'suderman/mail
  "<f5>" #'suderman/reload-config
  "<f6>" #'suderman/pull-config
  "<f9>" #'tool-bar-mode
  "s-+" #'suderman/frame-text-scale-increase
  "s-=" #'suderman/frame-text-scale-increase
  "s--" #'suderman/frame-text-scale-decrease
  "s-_" #'suderman/frame-text-scale-decrease
  "s-t" #'tab-new
  "s-[" #'tab-previous
  "s-]" #'tab-next
  "s-w" #'tab-close
  "M-z" #'suderman/zoom-window-toggle
  "C-x 0" #'suderman/delete-window-or-tab)

(setq tab-bar-close-last-tab-choice 'delete-frame)

;; Meow's state maps outrank major-mode maps, so window keys go there too.
(dolist (map (list global-map meow-normal-state-keymap meow-motion-state-keymap))
  (suderman/install-keys map suderman/window-keys))

(dolist (map (list meow-normal-state-keymap meow-motion-state-keymap))
  (define-keymap :keymap map
    "M-p" #'consult-recent-file
    "M-U" #'suderman/split-window-below-and-focus
    "M-I" #'suderman/split-window-right-and-focus))

;;;; SPC leader

;; One form builds the whole leader, so C-M-x anywhere inside applies it.
(setf
 (alist-get 'leader meow-keymap-alist)
 (define-keymap
   "SPC" #'execute-extended-command
   "?" #'suderman/cheatsheet
   "e" '("mail" . suderman/mail)
   "0" #'meow-digit-argument
   "1" #'meow-digit-argument
   "2" #'meow-digit-argument
   "3" #'meow-digit-argument
   "4" #'meow-digit-argument
   "5" #'meow-digit-argument
   "6" #'meow-digit-argument
   "7" #'meow-digit-argument
   "8" #'meow-digit-argument
   "9" #'meow-digit-argument

   "," (cons "buffers"
             (define-keymap
               "/" #'consult-buffer
               "b" #'ibuffer
               "k" #'kill-current-buffer
               "," #'suderman/alternate-buffer
               "n" #'next-buffer
               "p" #'previous-buffer
               "r" #'suderman/revert-buffer-no-confirm
               "s" #'save-buffer))

   "." (cons "files"
             (define-keymap
               "." #'consult-fd
               "/" #'consult-ripgrep
               "f" #'suderman/dirvish
               "b" #'consult-bookmark
               "m" #'bookmark-set
               "M" #'bookmark-delete
               "," #'consult-recent-file
               "s" #'save-buffer
               "S" #'write-file
               "R" #'tramp-cleanup-this-connection))

   "g" (cons "git"
             (define-keymap
               "B" #'magit-blame-addition
               "C" #'magit-branch-checkout
               "b" #'magit-blame-echo
               "d" #'magit-diff-buffer-file
               "f" #'magit-file-dispatch
               "g" #'magit-status
               "l" #'magit-log-buffer-file
               "L" #'magit-log-current
               "m" #'magit-dispatch
               "s" #'magit-stage-files
               "u" #'magit-unstage-files
               "c" (cons "conflicts"
                         (define-keymap
                           "0" #'smerge-kill-current
                           "a" #'smerge-keep-all
                           "b" #'smerge-keep-base
                           "e" #'smerge-ediff
                           "l" #'smerge-keep-lower
                           "n" #'smerge-next
                           "p" #'smerge-prev
                           "r" #'smerge-refine
                           "u" #'smerge-keep-upper))
               "h" (cons "hunks"
                         (define-keymap
                           "d" #'diff-hl-diff-goto-hunk
                           "n" #'diff-hl-next-hunk
                           "p" #'diff-hl-previous-hunk
                           "r" #'diff-hl-revert-hunk
                           "s" #'diff-hl-stage-current-hunk
                           "u" #'diff-hl-unstage-file
                           "v" #'diff-hl-show-hunk))))

   "o" (cons "org"
             (define-keymap
               "TAB" '("collapse all" . org-overview)
               "a" '("archive" . suderman/org-archive)
               "A" '("archive completed in buffer" . suderman/org-archive-done)
               "c" #'org-capture
               "d" '("DONE" . suderman/org-todo-done)
               "D" '("delete subtree" . suderman/org-delete-subtree)
               "e" '("EVAL" . suderman/org-todo-eval)
               "E" '("export" . suderman/org-export)
               "g" #'suderman/org-heading
               "h" '("HOLD" . suderman/org-todo-hold)
               "i" #'suderman/org-insert-link
               "l" #'org-store-link
               "n" #'org-toggle-narrow-to-subtree
               "o" '("dashboard" . suderman/org-dashboard)
               "p" '("PROG" . suderman/org-todo-prog)
               "r" #'suderman/org-refile
               "t" '("TODO" . suderman/org-todo-todo)
               "x" #'suderman/org-toggle-checkbox
               "s" (cons "planning"
                         (define-keymap
                           "s" '("schedule" . suderman/org-schedule)
                           "d" '("deadline" . suderman/org-deadline)))
               "v" (cons "views"
                         (define-keymap
                           "a" '("agenda" . org-agenda)
                           "t" '("TODO list" . org-todo-list)
                           "d" '("daily" . suderman/org-daily)
                           "i" '("inbox" . suderman/org-inbox)))))

   "q" (cons "quit/config"
             (define-keymap
               "p" #'suderman/pull-config
               "q" #'kill-emacs
               "r" #'suderman/reload-config
               "u" #'suderman/package-upgrade-all))

   "/" (cons "search"
             (define-keymap
               "/" #'consult-ripgrep
               "g" #'consult-git-grep
               "l" #'consult-line
               "L" #'consult-line-multi
               "i" #'consult-imenu
               "I" #'consult-imenu-multi
               "o" #'consult-outline
               "m" #'consult-mark
               "M" #'consult-global-mark
               "r" #'consult-register
               "y" #'consult-yank-pop
               "e" #'consult-compile-error
               "f" #'consult-flymake
               "s" #'consult-isearch-history
               "c" #'suderman/clear-search))

   "t" (cons "toggles"
             (define-keymap
               "c" '("column indicator" . display-fill-column-indicator-mode)
               "d" '("dirvish sidebar" . suderman/dirvish-side-toggle)
               "h" '("current line" . hl-line-mode)
               "m" '("menu bar" . menu-bar-mode)
               "n" '("line numbers" . suderman/toggle-line-numbers)
               "o" '("org indentation" . org-indent-mode)
               "r" '("read only" . read-only-mode)
               "s" (and (fboundp 'jinx-mode) '("spelling" . jinx-mode))
               "v" '("visual lines" . visual-line-mode)
               "w" '("whitespace" . whitespace-mode)))

   "w" (cons "windows"
             (define-keymap
               "=" #'balance-windows
               "h" #'edger-left
               "j" #'edger-down
               "k" #'edger-up
               "l" #'edger-right
               "H" #'edger-resize-left
               "J" #'edger-resize-down
               "K" #'edger-resize-up
               "L" #'edger-resize-right
               "u" #'edger-horizontal
               "i" #'edger-vertical
               "o" #'delete-other-windows
               "w" #'edger-close))

   "RET" (and (fboundp 'ghostel-project) #'ghostel-project)))

(provide 'suderman-keys)
;;; suderman-keys.el ends here
