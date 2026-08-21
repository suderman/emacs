;;; suderman-files.el --- Dired and file utilities -*- lexical-binding: t; -*-

;;; Commentary:
;; Generic file commands and Dired/Dirvish navigation live here.

;;; Code:

(require 'dired)
(require 'use-package)
(require 'suderman-windows)

(defun suderman/revert-buffer-no-confirm ()
  "Revert the current buffer without confirmation or auto-save recovery."
  (interactive)
  (revert-buffer t t))

(use-package dirvish
  :commands (dirvish dirvish-side)
  :init
  (setq dirvish-use-mode-line t)
  :config
  (dirvish-override-dired-mode 1)
  (dolist (map (list dired-mode-map dirvish-mode-map))
    (define-key map (kbd "h") #'dired-up-directory)
    (define-key map (kbd "j") #'dired-next-line)
    (define-key map (kbd "k") #'dired-previous-line)
    (define-key map (kbd "l") #'dired-find-file)
    (define-key map (kbd "M-h") #'suderman/window-left)
    (define-key map (kbd "M-j") #'windmove-down)
    (define-key map (kbd "M-k") #'windmove-up)
    (define-key map (kbd "M-l") #'windmove-right))
  (define-key dired-mode-map (kbd "q") #'quit-window))

(provide 'suderman-files)
;;; suderman-files.el ends here
