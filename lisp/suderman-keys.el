;;; suderman-keys.el --- Global Meow and leader bindings -*- lexical-binding: t; -*-

;;; Commentary:
;; Load keybindings after commands exist.  Meow owns modal editing; this file
;; owns personal global shortcuts and the SPC leader groups that do not collide
;; with Meow's vanilla keypad prefixes.

;;; Code:

(require 'use-package)
(require 'suderman-meow)
(require 'suderman-files)
(require 'suderman-markdown)
(require 'suderman-pickers)
(require 'suderman-projects)
(require 'suderman-reload)
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
(defvar suderman/leader-project-map nil
  "SPC p project command keymap.")
(defvar suderman/leader-search-map nil
  "SPC s search command keymap.")
(defvar suderman/leader-tool-map nil
  "SPC t tool command keymap.")
(defvar suderman/leader-window-map nil
  "SPC w window command keymap.")
(defvar suderman/leader-quit-map nil
  "SPC q quit/reload command keymap.")

(setq suderman/leader-buffer-map (make-sparse-keymap)
      suderman/leader-file-map (make-sparse-keymap)
      suderman/leader-project-map (make-sparse-keymap)
      suderman/leader-search-map (make-sparse-keymap)
      suderman/leader-tool-map (make-sparse-keymap)
      suderman/leader-window-map (make-sparse-keymap)
      suderman/leader-quit-map (make-sparse-keymap))

;; Buffers
(suderman/keys--define suderman/leader-buffer-map "b" #'suderman/switch-buffer)
(suderman/keys--define suderman/leader-buffer-map "i" #'ibuffer)
(suderman/keys--define suderman/leader-buffer-map "k" #'kill-current-buffer)
(suderman/keys--define suderman/leader-buffer-map "l" #'suderman/alternate-buffer)
(suderman/keys--define suderman/leader-buffer-map "n" #'next-buffer)
(suderman/keys--define suderman/leader-buffer-map "p" #'previous-buffer)
(suderman/keys--define suderman/leader-buffer-map "r" #'revert-buffer)
(suderman/keys--define suderman/leader-buffer-map "s" #'save-buffer)

;; Files
(suderman/keys--define suderman/leader-file-map "." #'find-file)
(suderman/keys--define suderman/leader-file-map "f" #'suderman/find-file)
(suderman/keys--define suderman/leader-file-map "r" #'consult-recent-file)
(suderman/keys--define suderman/leader-file-map "s" #'save-buffer)
(suderman/keys--define suderman/leader-file-map "S" #'write-file)

;; Projects
(suderman/keys--define suderman/leader-project-map "b" #'project-switch-to-buffer)
(suderman/keys--define suderman/leader-project-map "f" #'project-find-file)
(suderman/keys--define suderman/leader-project-map "k" #'project-kill-buffers)
(suderman/keys--define suderman/leader-project-map "p" #'project-switch-project)
(suderman/keys--define suderman/leader-project-map "s" #'consult-ripgrep)

;; Search
(suderman/keys--define suderman/leader-search-map "c" #'suderman/clear-search)
(suderman/keys--define suderman/leader-search-map "g" #'consult-ripgrep)
(suderman/keys--define suderman/leader-search-map "i" #'consult-imenu)
(suderman/keys--define suderman/leader-search-map "l" #'consult-line)

;; Tools and pickers
(suderman/keys--define suderman/leader-tool-map "?" #'meow-keypad-describe-key)
(suderman/keys--define suderman/leader-tool-map "b" #'suderman/switch-buffer)
(suderman/keys--define suderman/leader-tool-map "d" #'dirvish)
(suderman/keys--define suderman/leader-tool-map "e" #'dirvish-side)
(suderman/keys--define suderman/leader-tool-map "f" #'suderman/find-file)
(suderman/keys--define suderman/leader-tool-map "g" #'consult-ripgrep)
(suderman/keys--define suderman/leader-tool-map "i" #'consult-imenu)
(suderman/keys--define suderman/leader-tool-map "k" #'describe-bindings)
(suderman/keys--define suderman/leader-tool-map "l" #'consult-line)
(suderman/keys--define suderman/leader-tool-map "p" #'suderman/markdown-preview-buffer)
(suderman/keys--define suderman/leader-tool-map "q" #'consult-complex-command)
(suderman/keys--define suderman/leader-tool-map "r" #'consult-recent-file)
(suderman/keys--define suderman/leader-tool-map "t" #'suderman/smart-picker)

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

(dolist (binding '(("<f5>" . suderman/reload-config)
                   ("M-p" . consult-recent-file)
                   ("M-g" . consult-ripgrep)
                   ("M-h" . suderman/window-left)
                   ("M-j" . windmove-down)
                   ("M-k" . windmove-up)
                   ("M-l" . windmove-right)
                   ("M-;" . suderman/window-previous)
                   ("M-H" . suderman/shrink-window-width)
                   ("M-J" . suderman/enlarge-window-height)
                   ("M-K" . suderman/shrink-window-height)
                   ("M-L" . suderman/enlarge-window-width)
                   ("M-u" . suderman/split-window-below-and-focus)
                   ("M-i" . suderman/split-window-right-and-focus)
                   ("M-U" . suderman/split-window-below-and-focus)
                   ("M-I" . suderman/split-window-right-and-focus)
                   ("M-q" . delete-window)))
  (suderman/keys--define-modal (car binding) (cdr binding)))

(use-package which-key
  :demand t
  :init
  (setq which-key-idle-delay 0.35)
  :config
  (which-key-mode 1)
  (which-key-add-key-based-replacements
    "SPC b" "buffers"
    "SPC d" "dirvish"
    "SPC e" "explorer"
    "SPC f" "files"
    "SPC p" "projects"
    "SPC q" "quit/reload"
    "SPC s" "search"
    "SPC t" "tools"
    "SPC w" "windows"))

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
 '("/" . consult-ripgrep)
 '("SPC" . suderman/find-file)
 '("." . find-file)
 '("," . suderman/switch-buffer)
 '(":" . execute-extended-command)
 '("\\" . suderman/alternate-buffer)
 '("d" . dirvish)
 '("e" . dirvish-side)
 (cons "b" suderman/leader-buffer-map)
 (cons "f" suderman/leader-file-map)
 (cons "p" suderman/leader-project-map)
 (cons "q" suderman/leader-quit-map)
 (cons "s" suderman/leader-search-map)
 (cons "t" suderman/leader-tool-map)
 (cons "w" suderman/leader-window-map))

(provide 'suderman-keys)
;;; suderman-keys.el ends here
