;;; suderman-keys.el --- Global Meow and leader bindings -*- lexical-binding: t; -*-

;;; Commentary:
;; Load keybindings after commands exist.  Meow owns modal editing; this file
;; owns personal global shortcuts and the SPC leader groups that do not collide
;; with Meow's vanilla keypad prefixes.

;;; Code:

(require 'use-package)
(require 'suderman-appearance)
(require 'suderman-meow)
(require 'suderman-files)
(require 'suderman-git)
(require 'suderman-org)
(require 'suderman-pickers)
(require 'suderman-reload)
(require 'suderman-treemacs)
(require 'suderman-windows)

(defun suderman/clear-search ()
  "Clear active isearch and lazy search highlighting."
  (interactive)
  (when (bound-and-true-p isearch-mode)
    (isearch-exit))
  (when (fboundp 'lazy-highlight-cleanup)
    (lazy-highlight-cleanup t))
  (when (fboundp 'isearch-dehighlight)
    (isearch-dehighlight)))

(defun suderman/frame-text-scale-adjust (delta)
  "Adjust the selected graphical frame's text size by DELTA points."
  (let ((frame (selected-frame)))
    (unless (display-graphic-p frame)
      (user-error "Text scaling requires a graphical frame"))
    ;; PGTK rounds rendered font sizes, so track the requested height instead.
    (let* ((state
            (or (frame-parameter frame 'suderman/frame-text-scale-state)
                (let ((height
                       (face-attribute 'default :height frame 'default)))
                  (list height (frame-parameter frame 'font) height))))
           (base-height (nth 0 state))
           (base-font (nth 1 state))
           (new-height (+ (nth 2 state) (* delta 10))))
      (when (< 10 new-height 500)
        (set-frame-parameter
         frame 'suderman/frame-text-scale-state
         (list base-height base-font new-height))
        (if (= new-height base-height)
            (set-frame-font base-font t nil t)
          (set-face-attribute 'default frame :height new-height))))))

(defun suderman/frame-text-scale-decrease ()
  "Decrease text size in the selected graphical frame by one point."
  (interactive)
  (suderman/frame-text-scale-adjust -1))

(defun suderman/frame-text-scale-increase ()
  "Increase text size in the selected graphical frame by one point."
  (interactive)
  (suderman/frame-text-scale-adjust 1))

(defun suderman/keys--define (map key command)
  "Bind KEY to COMMAND in MAP."
  (define-key map (kbd key) command))

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
(suderman/keys--define suderman/leader-buffer-map "b" #'consult-buffer)
(suderman/keys--define suderman/leader-buffer-map "i" #'ibuffer)
(suderman/keys--define suderman/leader-buffer-map "k" #'kill-current-buffer)
(suderman/keys--define suderman/leader-buffer-map "l" #'suderman/alternate-buffer)
(suderman/keys--define suderman/leader-buffer-map "n" #'next-buffer)
(suderman/keys--define suderman/leader-buffer-map "p" #'previous-buffer)
(suderman/keys--define suderman/leader-buffer-map "r" #'suderman/revert-buffer-no-confirm)
(suderman/keys--define suderman/leader-buffer-map "s" #'save-buffer)

;; Files
(suderman/keys--define suderman/leader-file-map "." #'suderman/dirvish)
(suderman/keys--define suderman/leader-file-map "f" #'consult-fd)
(suderman/keys--define suderman/leader-file-map "g" #'consult-ripgrep)
(suderman/keys--define suderman/leader-file-map "r" #'consult-recent-file)
(suderman/keys--define suderman/leader-file-map "s" #'save-buffer)
(suderman/keys--define suderman/leader-file-map "S" #'write-file)

;; Git
(suderman/keys--define suderman/leader-git-map "B" #'magit-blame-addition)
(suderman/keys--define suderman/leader-git-map "b" #'magit-blame-echo)
(suderman/keys--define suderman/leader-git-map "c" suderman/leader-git-conflict-map)
(suderman/keys--define suderman/leader-git-map "d" #'magit-diff-buffer-file)
(suderman/keys--define suderman/leader-git-map "f" #'magit-file-dispatch)
(suderman/keys--define suderman/leader-git-map "." #'magit-status)
(suderman/keys--define suderman/leader-git-map "h" suderman/leader-git-hunk-map)
(suderman/keys--define suderman/leader-git-map "l" #'magit-log-buffer-file)
(suderman/keys--define suderman/leader-git-map "m" #'magit-dispatch)

;; Git hunks
(suderman/keys--define suderman/leader-git-hunk-map "d" #'diff-hl-diff-goto-hunk)
(suderman/keys--define suderman/leader-git-hunk-map "n" #'diff-hl-next-hunk)
(suderman/keys--define suderman/leader-git-hunk-map "p" #'diff-hl-previous-hunk)
(suderman/keys--define suderman/leader-git-hunk-map "r" #'diff-hl-revert-hunk)
(suderman/keys--define suderman/leader-git-hunk-map "s" #'diff-hl-stage-current-hunk)
(suderman/keys--define suderman/leader-git-hunk-map "u" #'diff-hl-unstage-file)
(suderman/keys--define suderman/leader-git-hunk-map "v" #'diff-hl-show-hunk)

;; Git conflicts
(suderman/keys--define suderman/leader-git-conflict-map "0" #'smerge-kill-current)
(suderman/keys--define suderman/leader-git-conflict-map "a" #'smerge-keep-all)
(suderman/keys--define suderman/leader-git-conflict-map "b" #'smerge-keep-base)
(suderman/keys--define suderman/leader-git-conflict-map "e" #'smerge-ediff)
(suderman/keys--define suderman/leader-git-conflict-map "l" #'smerge-keep-lower)
(suderman/keys--define suderman/leader-git-conflict-map "n" #'smerge-next)
(suderman/keys--define suderman/leader-git-conflict-map "p" #'smerge-prev)
(suderman/keys--define suderman/leader-git-conflict-map "r" #'smerge-refine)
(suderman/keys--define suderman/leader-git-conflict-map "u" #'smerge-keep-upper)

;; Org
(suderman/keys--define suderman/leader-org-map "a" #'org-agenda)
(suderman/keys--define suderman/leader-org-map "c" #'org-capture)
(suderman/keys--define suderman/leader-org-map "d" #'org-deadline)
(suderman/keys--define suderman/leader-org-map "e" #'org-export-dispatch)
(suderman/keys--define suderman/leader-org-map "g" #'consult-org-heading)
(suderman/keys--define suderman/leader-org-map "i" #'org-insert-link)
(suderman/keys--define suderman/leader-org-map "l" #'org-store-link)
(suderman/keys--define suderman/leader-org-map "r" #'org-refile)
(suderman/keys--define suderman/leader-org-map "s" #'org-schedule)
(suderman/keys--define suderman/leader-org-map "t" #'org-todo)
(suderman/keys--define suderman/leader-org-map "T" #'org-todo-list)
(suderman/keys--define suderman/leader-org-map "x" #'org-toggle-checkbox)

;; Search
(suderman/keys--define suderman/leader-search-map "c" #'suderman/clear-search)
(suderman/keys--define suderman/leader-search-map "i" #'consult-imenu)
(suderman/keys--define suderman/leader-search-map "l" #'consult-line)

;; Toggles
(suderman/keys--define suderman/leader-toggle-map "c" #'display-fill-column-indicator-mode)
(suderman/keys--define suderman/leader-toggle-map "h" #'hl-line-mode)
(suderman/keys--define suderman/leader-toggle-map "l" #'suderman/toggle-line-numbers)
(suderman/keys--define suderman/leader-toggle-map "o" #'org-indent-mode)
(suderman/keys--define suderman/leader-toggle-map "r" #'read-only-mode)
(suderman/keys--define suderman/leader-toggle-map "s" #'jinx-mode)
(suderman/keys--define suderman/leader-toggle-map "t" #'suderman/treemacs-toggle)
(suderman/keys--define suderman/leader-toggle-map "v" #'visual-line-mode)
(suderman/keys--define suderman/leader-toggle-map "w" #'whitespace-mode)

;; Windows
(suderman/keys--define suderman/leader-window-map "=" #'balance-windows)
(suderman/keys--define suderman/leader-window-map "+" #'suderman/enlarge-window-width)
(suderman/keys--define suderman/leader-window-map "-" #'suderman/shrink-window-width)
(suderman/keys--define suderman/leader-window-map "d" #'delete-window)
(suderman/keys--define suderman/leader-window-map "h" #'suderman/window-left)
(suderman/keys--define suderman/leader-window-map "j" #'windmove-down)
(suderman/keys--define suderman/leader-window-map "k" #'windmove-up)
(suderman/keys--define suderman/leader-window-map "l" #'windmove-right)
(suderman/keys--define suderman/leader-window-map "o" #'delete-other-windows)
(suderman/keys--define suderman/leader-window-map "q" #'delete-window)
(suderman/keys--define suderman/leader-window-map "s" #'suderman/split-window-below-and-focus)
(suderman/keys--define suderman/leader-window-map "u" #'suderman/split-window-below-and-focus)
(suderman/keys--define suderman/leader-window-map "v" #'suderman/split-window-right-and-focus)
(suderman/keys--define suderman/leader-window-map "i" #'suderman/split-window-right-and-focus)
(suderman/keys--define suderman/leader-window-map "H" #'suderman/shrink-window-width)
(suderman/keys--define suderman/leader-window-map "J" #'suderman/enlarge-window-height)
(suderman/keys--define suderman/leader-window-map "K" #'suderman/shrink-window-height)
(suderman/keys--define suderman/leader-window-map "L" #'suderman/enlarge-window-width)

;; Quit/reload
(suderman/keys--define suderman/leader-quit-map "r" #'suderman/reload-config)

(setq tab-bar-close-last-tab-choice 'delete-frame)

(global-set-key (kbd "<f5>") #'suderman/reload-config)
(global-set-key (kbd "s-+") #'suderman/frame-text-scale-increase)
(global-set-key (kbd "s-=") #'suderman/frame-text-scale-increase)
(global-set-key (kbd "s--") #'suderman/frame-text-scale-decrease)
(global-set-key (kbd "s-_") #'suderman/frame-text-scale-decrease)
(global-set-key (kbd "s-t") #'tab-new)
(global-set-key (kbd "s-[") #'tab-previous)
(global-set-key (kbd "s-]") #'tab-next)
(global-set-key (kbd "s-w") #'tab-close)
(global-set-key (kbd "M-z") #'suderman/zoom-window-toggle)
(global-set-key (kbd "C-x 0") #'suderman/delete-window-or-tab)

(dolist (binding '(("<f5>" . suderman/reload-config)
                   ("M-p" . consult-recent-file)
                   ("M-h" . suderman/window-left)
                   ("M-j" . windmove-down)
                   ("M-k" . windmove-up)
                   ("M-l" . windmove-right)
                   ("M-H" . suderman/resize-window-left)
                   ("M-J" . suderman/resize-window-down)
                   ("M-K" . suderman/resize-window-up)
                   ("M-L" . suderman/resize-window-right)
                   ("M-u" . suderman/split-window-below-and-focus)
                   ("M-i" . suderman/split-window-right-and-focus)
                   ("M-U" . suderman/split-window-below-and-focus)
                   ("M-I" . suderman/split-window-right-and-focus)
                   ("M-w" . suderman/delete-window-or-tab)))
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
  "h" "current line"
  "l" "line numbers"
  "o" "org indentation"
  "r" "read only"
  "s" "spelling"
  "t" "treemacs"
  "v" "visual lines"
  "w" "whitespace")

(which-key-add-keymap-based-replacements
  suderman/leader-git-map
  "c" (cons "conflicts" suderman/leader-git-conflict-map)
  "h" (cons "hunks" suderman/leader-git-hunk-map))

(provide 'suderman-keys)
;;; suderman-keys.el ends here
