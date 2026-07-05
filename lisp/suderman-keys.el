;;; suderman-keys.el --- Global Evil and leader bindings -*- lexical-binding: t; -*-

;;; Commentary:
;; Load keybindings after commands exist.  This keeps each feature module focused
;; on behavior while one final file describes how Suderman drives Emacs day to day.

;;; Code:

(require 'use-package)
(require 'suderman-evil)
(require 'suderman-files)
(require 'suderman-pickers)
(require 'suderman-projects)
(require 'suderman-windows)

(defvar suderman/local-leader-map
  (make-sparse-keymap)
  "Fallback keymap for the local leader key `,'.")

(dolist (map (list evil-normal-state-map evil-motion-state-map))
  (define-key map (kbd ";") #'evil-ex)
  (define-key map (kbd "j") #'evil-next-visual-line)
  (define-key map (kbd "k") #'evil-previous-visual-line)
  (define-key map (kbd "Y") (kbd "y$"))
  (define-key map (kbd "K") #'suderman/switch-buffer)
  (define-key map (kbd "M-p") #'consult-recent-file)
  (define-key map (kbd "M-g") #'suderman/search-project)
  (define-key map (kbd "-") #'dirvish)
  (define-key map (kbd "M-h") #'suderman/window-left-or-treemacs)
  (define-key map (kbd "M-j") #'windmove-down)
  (define-key map (kbd "M-k") #'windmove-up)
  (define-key map (kbd "M-l") #'windmove-right)
  (define-key map (kbd "M-;") #'suderman/window-previous)
  (define-key map (kbd "M-H") #'suderman/shrink-window-width)
  (define-key map (kbd "M-J") #'suderman/enlarge-window-height)
  (define-key map (kbd "M-K") #'suderman/shrink-window-height)
  (define-key map (kbd "M-L") #'suderman/enlarge-window-width)
  (define-key map (kbd "M-u") #'suderman/split-window-below-and-focus)
  (define-key map (kbd "M-i") #'suderman/split-window-right-and-focus)
  (define-key map (kbd "M-U") #'suderman/split-window-below-and-focus)
  (define-key map (kbd "M-I") #'suderman/split-window-right-and-focus)
  (define-key map (kbd "g u") #'suderman/split-window-below-and-focus)
  (define-key map (kbd "g i") #'suderman/split-window-right-and-focus)
  (define-key map (kbd "M-q") #'delete-window)
  (define-key map (kbd ",") suderman/local-leader-map)
  (define-key map (kbd "[b") #'previous-buffer)
  (define-key map (kbd "]b") #'next-buffer)
  (define-key map (kbd "[c") #'previous-error)
  (define-key map (kbd "]c") #'next-error))

(define-key evil-visual-state-map (kbd "j") #'evil-next-visual-line)
(define-key evil-visual-state-map (kbd "k") #'evil-previous-visual-line)
(define-key evil-visual-state-map (kbd "<") #'suderman/evil-shift-left-visual)
(define-key evil-visual-state-map (kbd ">") #'suderman/evil-shift-right-visual)
(define-key evil-visual-state-map (kbd "M-h") #'suderman/shrink-window-width)
(define-key evil-visual-state-map (kbd "M-j") #'suderman/enlarge-window-height)
(define-key evil-visual-state-map (kbd "M-k") #'suderman/shrink-window-height)
(define-key evil-visual-state-map (kbd "M-l") #'suderman/enlarge-window-width)

(use-package which-key
  :demand t
  :init
  (setq which-key-idle-delay 0.35)
  :config
  (which-key-mode 1))

(use-package general
  :after evil
  :config
  (general-create-definer suderman/leader
    :states '(normal visual motion)
    :keymaps 'override
    :prefix "SPC")

  (suderman/leader
    "SPC" '(suderman/find-file :which-key "find file/project file")
    "."   '(find-file :which-key "find file")
    "/"   '(suderman/search-project :which-key "grep project")
    ","   '(suderman/switch-buffer :which-key "switch buffer")
    ":"   '(execute-extended-command :which-key "M-x")
    "\\" '(suderman/alternate-buffer :which-key "last buffer")
    "="   '(suderman/treemacs-toggle :which-key "toggle explorer")
    "u"   '(suderman/split-window-below-and-focus :which-key "split below")
    "i"   '(suderman/split-window-right-and-focus :which-key "split right")
    "q"   '(delete-window :which-key "quit split")

    ;; Files
    "f"   '(:ignore t :which-key "files")
    "f f" '(suderman/find-file :which-key "find file/project file")
    "f r" '(consult-recent-file :which-key "recent files")
    "f s" '(save-buffer :which-key "save file")

    ;; Buffers
    "b"   '(:ignore t :which-key "buffers")
    "b b" '(suderman/switch-buffer :which-key "switch buffer")
    "b k" '(kill-current-buffer :which-key "kill buffer")
    "b n" '(next-buffer :which-key "next buffer")
    "b p" '(previous-buffer :which-key "previous buffer")

    ;; Search
    "s"   '(:ignore t :which-key "search")
    "s c" '(suderman/clear-search :which-key "clear search")
    "s g" '(suderman/search-project :which-key "grep project")
    "s l" '(consult-line :which-key "search line")
    "s i" '(consult-imenu :which-key "imenu symbols")

    ;; Pickers
    "t"   '(:ignore t :which-key "pickers")
    "t t" '(suderman/smart-picker :which-key "smart picker")
    "t b" '(suderman/switch-buffer :which-key "buffers")
    "t f" '(suderman/find-file :which-key "files")
    "t g" '(suderman/search-project :which-key "grep")
    "t r" '(consult-recent-file :which-key "recent")
    "t q" '(consult-complex-command :which-key "command history")
    "t l" '(consult-line :which-key "line")
    "t i" '(consult-imenu :which-key "symbols")
    "t k" '(describe-bindings :which-key "keymaps")

    ;; Windows
    "w"   '(:ignore t :which-key "windows")
    "w v" '(suderman/split-window-right-and-focus :which-key "split right")
    "w s" '(suderman/split-window-below-and-focus :which-key "split below")
    "w d" '(delete-window :which-key "delete window")
    "w o" '(delete-other-windows :which-key "only window")
    "w h" '(suderman/window-left-or-treemacs :which-key "window left")
    "w j" '(windmove-down :which-key "window down")
    "w k" '(windmove-up :which-key "window up")
    "w l" '(windmove-right :which-key "window right")
    "w +" '(suderman/enlarge-window-width :which-key "wider")
    "w -" '(suderman/shrink-window-width :which-key "narrower")
    "w =" '(balance-windows :which-key "balance")

    ;; Projects
    "p"   '(:ignore t :which-key "projects")
    "p p" '(project-switch-project :which-key "switch project")
    "p f" '(project-find-file :which-key "project file")
    "p b" '(project-switch-to-buffer :which-key "project buffer")
    "p k" '(project-kill-buffers :which-key "kill project buffers")

    ;; Explorer / files
    "e"   '(suderman/treemacs-toggle :which-key "explorer")
    "d"   '(dirvish :which-key "dirvish")

    ;; Help
    "h"   '(:ignore t :which-key "help")
    "h k" '(describe-key :which-key "describe key")
    "h f" '(describe-function :which-key "describe function")
    "h v" '(describe-variable :which-key "describe variable")
    "h m" '(describe-mode :which-key "describe mode")))

(provide 'suderman-keys)
;;; suderman-keys.el ends here
