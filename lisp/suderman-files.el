;;; suderman-files.el --- File and directory browsing -*- lexical-binding: t; -*-

;;; Commentary:
;; Directory browsing lives here.  Project/file picker logic is elsewhere; this
;; module is about moving around directory trees once opened.

;;; Code:

(require 'dired)
(require 'use-package)
(require 'suderman-windows)

(use-package speedbar
  :ensure nil
  :if (> emacs-major-version 30)
  :commands (speedbar)
  :config
  (setq speedbar-prefer-window t)
  (setq speedbar-window-default-width 50)
  (setq speedbar-use-images nil))

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
