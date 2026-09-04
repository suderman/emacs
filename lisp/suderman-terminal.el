;;; suderman-terminal.el --- Ghostel terminal integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Ghostel owns terminal emulation while Meow follows its live and copy states.

;;; Code:

(require 'use-package)
(require 'meow)
(require 'suderman-windows)

(defvar ghostel--input-mode)
(declare-function ghostel-readonly-exit "ghostel")

(defun suderman/ghostel-sync-meow-state (&rest _)
  "Match Meow to Ghostel's current input mode."
  (when (bound-and-true-p meow-mode)
    (pcase ghostel--input-mode
      ('copy
       (unless (meow-normal-mode-p)
         (meow-normal-mode 1)))
      ((or 'semi-char 'char)
       (unless (meow-insert-mode-p)
         (meow-insert-mode 1))))))

(defun suderman/ghostel-resume-on-meow-insert ()
  "Resume terminal input when leaving Meow normal state."
  (when (eq ghostel--input-mode 'copy)
    (ghostel-readonly-exit)))

(defun suderman/ghostel-setup ()
  "Connect Meow insert state to Ghostel's live terminal state."
  (add-hook 'meow-insert-enter-hook
            #'suderman/ghostel-resume-on-meow-insert nil t))

(use-package ghostel
  :ensure nil
  :if (not (eq system-type 'android))
  :demand t
  :hook (ghostel-mode . suderman/ghostel-setup)
  :config
  (setopt ghostel-initial-input-mode 'semi-char
          ghostel-readonly-fast-exit nil
          ghostel-keymap-exceptions
          (delete-dups
           (append ghostel-keymap-exceptions
                   '("M-h" "M-j" "M-k" "M-l"
                     "M-H" "M-J" "M-K" "M-L"))))

  ;; These keys are Meow-state bindings elsewhere, so semi-char mode needs
  ;; local commands after exempting them from terminal forwarding.
  (dolist (binding '(("M-h" . suderman/window-left)
                     ("M-j" . windmove-down)
                     ("M-k" . windmove-up)
                     ("M-l" . windmove-right)
                     ("M-H" . suderman/resize-window-left)
                     ("M-J" . suderman/resize-window-down)
                     ("M-K" . suderman/resize-window-up)
                     ("M-L" . suderman/resize-window-right)))
    (keymap-set ghostel-semi-char-mode-map (car binding) (cdr binding)))

  (dolist (command '(ghostel-copy-mode
                     ghostel-semi-char-mode
                     ghostel-char-mode))
    (advice-remove command #'suderman/ghostel-sync-meow-state)
    (advice-add command :after #'suderman/ghostel-sync-meow-state)))

(provide 'suderman-terminal)
;;; suderman-terminal.el ends here
