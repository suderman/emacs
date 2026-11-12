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
  ;; Labelled digits would no longer collapse into one 0..9 entry.
  (add-to-list 'which-key-replacement-alist
               '((nil . "\\`meow-digit-argument\\'") . (nil . "digit argument")))
  (when (featurep 'android)
    ;; Fit two columns in the phone's narrow frame: each column holds a key
    ;; up to three characters wide, the separator, and the description.
    (setq which-key-max-description-length
          (lambda (width)
            (- (/ (1- width) 2) 3 (string-width which-key-separator)))))
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

(setq tab-bar-close-last-tab-choice 'delete-frame
      tab-bar-show 1)

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
   "SPC" '("command" . execute-extended-command)
   "?" '("cheatsheet" . suderman/cheatsheet)
   "TAB" '("fold/open all" . suderman/meow-fold-all)
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
               "/" '("switch buffer" . consult-buffer)
               "b" '("ibuffer" . suderman/ibuffer-toggle)
               "k" '("kill" . kill-current-buffer)
               "," '("alternate" . suderman/alternate-buffer)
               "n" '("next" . next-buffer)
               "p" '("previous" . previous-buffer)
               "r" '("revert" . suderman/revert-buffer-no-confirm)
               "s" '("save" . save-buffer)))

   "." (cons "files"
             (define-keymap
               "." '("find file" . consult-fd)
               "/" '("ripgrep" . consult-ripgrep)
               "f" '("dirvish" . suderman/dirvish)
               "b" '("bookmark" . consult-bookmark)
               "m" '("set bookmark" . bookmark-set)
               "M" '("delete bookmark" . bookmark-delete)
               "," '("recent files" . consult-recent-file)
               "s" '("save" . save-buffer)
               "S" '("save as" . write-file)
               "R" '("tramp cleanup" . tramp-cleanup-this-connection)))

   "g" (cons "git"
             (define-keymap
               "B" '("blame addition" . magit-blame-addition)
               "C" '("checkout" . magit-branch-checkout)
               "b" '("blame echo" . magit-blame-echo)
               "d" '("diff file" . magit-diff-buffer-file)
               "f" '("file dispatch" . magit-file-dispatch)
               "g" '("status" . magit-status)
               "l" '("log file" . magit-log-buffer-file)
               "L" '("log current" . magit-log-current)
               "m" '("dispatch" . magit-dispatch)
               "s" '("stage files" . magit-stage-files)
               "u" '("unstage files" . magit-unstage-files)
               "c" (cons "conflicts"
                         (define-keymap
                           "0" '("kill current" . smerge-kill-current)
                           "a" '("keep all" . smerge-keep-all)
                           "b" '("keep base" . smerge-keep-base)
                           "e" '("ediff" . smerge-ediff)
                           "l" '("keep lower" . smerge-keep-lower)
                           "n" '("next" . smerge-next)
                           "p" '("previous" . smerge-prev)
                           "r" '("refine" . smerge-refine)
                           "u" '("keep upper" . smerge-keep-upper)))
               "h" (cons "hunks"
                         (define-keymap
                           "d" '("diff" . diff-hl-diff-goto-hunk)
                           "n" '("next" . diff-hl-next-hunk)
                           "p" '("previous" . diff-hl-previous-hunk)
                           "r" '("revert" . diff-hl-revert-hunk)
                           "s" '("stage" . diff-hl-stage-current-hunk)
                           "u" '("unstage file" . diff-hl-unstage-file)
                           "v" '("show" . diff-hl-show-hunk)))))

   "o" (cons "org"
             (define-keymap
               "a" '("archive" . suderman/org-archive)
               "A" '("archive done" . suderman/org-archive-done)
               "c" '("capture" . org-capture)
               "d" '("DONE" . suderman/org-todo-done)
               "D" '("delete subtree" . suderman/org-delete-subtree)
               "e" '("EVAL" . suderman/org-todo-eval)
               "E" '("export" . suderman/org-export)
               "g" '("go to heading" . suderman/org-heading)
               "h" '("HOLD" . suderman/org-todo-hold)
               "l" '("insert link" . suderman/org-insert-link)
               "L" '("store link" . org-store-link)
               "n" '("narrow" . org-toggle-narrow-to-subtree)
               "o" '("dashboard" . suderman/org-dashboard)
               "p" '("PROG" . suderman/org-todo-prog)
               "q" '("tags" . org-set-tags-command)
               "r" '("refile" . suderman/org-refile)
               "t" '("TODO" . suderman/org-todo-todo)
               "T" '("AUTO" . suderman/org-todo-auto)
               "w" '("track Asana" . suderman/org-asana-track)
               "W" '("add agent step" . suderman/org-asana-delegate)
               "x" '("checkbox" . suderman/org-toggle-checkbox)
               "TAB" '("fold task" . suderman/org-fold-task)
               "[" '("go to task" . suderman/org-goto-task)
               "s" (cons "planning"
                         (define-keymap
                           "s" '("schedule" . suderman/org-schedule)
                           "d" '("deadline" . suderman/org-deadline)))
               "v" (cons "views"
                         (define-keymap
                           "a" '("agenda" . org-agenda)
                           "t" '("TODO list" . org-todo-list)
                           "c" '("closed" . suderman/org-closed)
                           "d" '("daily" . suderman/org-daily)
                           "i" '("inbox" . suderman/org-inbox)))))

   "q" (cons "quit/config"
             (define-keymap
               "p" '("pull config" . suderman/pull-config)
               "q" '("close client" . save-buffers-kill-terminal)
               "Q" '("stop server" . save-buffers-kill-emacs)
               "s" '("save all, close" . suderman/save-and-quit)
               "d" '("discard, close" . suderman/quit-without-saving)
               "r" '("reload config" . suderman/reload-config)
               "u" '("upgrade all" . suderman/package-upgrade-all)))

   "/" (cons "search"
             (define-keymap
               "/" '("ripgrep" . consult-ripgrep)
               "g" '("git grep" . consult-git-grep)
               "l" '("line" . consult-line)
               "L" '("line, buffers" . consult-line-multi)
               "i" '("imenu" . consult-imenu)
               "I" '("imenu, buffers" . consult-imenu-multi)
               "o" '("outline" . consult-outline)
               "m" '("mark" . consult-mark)
               "M" '("global mark" . consult-global-mark)
               "r" '("register" . consult-register)
               "y" '("yank ring" . consult-yank-pop)
               "e" '("compile error" . consult-compile-error)
               "f" '("flymake" . consult-flymake)
               "s" '("isearch history" . consult-isearch-history)
               "c" '("clear search" . suderman/clear-search)))

   "t" (cons "toggles"
             (define-keymap
               "c" '("fill column" . display-fill-column-indicator-mode)
               "d" '("dirvish sidebar" . suderman/dirvish-side-toggle)
               "f" '("formatting" . suderman/toggle-formatting)
               "h" '("current line" . hl-line-mode)
               "m" '("menu bar" . menu-bar-mode)
               "n" '("line numbers" . suderman/toggle-line-numbers)
               "r" '("read only" . read-only-mode)
               "s" (and (fboundp 'jinx-mode) '("spelling" . jinx-mode))
               "t" '("sideways scroll" . suderman/toggle-sideways-scroll)
               "v" '("visual lines" . visual-line-mode)
               "w" '("whitespace" . whitespace-mode)))

   "w" (cons "windows"
             (define-keymap
               "=" '("balance" . balance-windows)
               "h" '("left" . edger-left)
               "j" '("down" . edger-down)
               "k" '("up" . edger-up)
               "l" '("right" . edger-right)
               "H" '("resize left" . edger-resize-left)
               "J" '("resize down" . edger-resize-down)
               "K" '("resize up" . edger-resize-up)
               "L" '("resize right" . edger-resize-right)
               "u" '("split below" . edger-horizontal)
               "i" '("split right" . edger-vertical)
               "n" '("new frame" . suderman/new-frame)
               "N" '("new tab" . tab-bar-new-tab)
               "o" '("close others" . delete-other-windows)
               "s" '("save" . save-buffer)
               "w" '("close" . edger-close)))

   "RET" (and (fboundp 'ghostel-project) #'ghostel-project)))

(provide 'suderman-keys)
;;; suderman-keys.el ends here
