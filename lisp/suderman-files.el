;;; suderman-files.el --- File and directory browsing -*- lexical-binding: t; -*-

;;; Commentary:
;; Directory browsing lives here.  Project/file picker logic is elsewhere; this
;; module is about moving around directory trees once opened.

;;; Code:

(require 'dired)
(require 'use-package)
(require 'suderman-windows)

(defun suderman/speedbar-select-editor-window ()
  "Select the most recently used normal editor window."
  (let ((window (get-mru-window nil nil t t)))
    (when window
      (select-window window))))

(use-package speedbar
  :ensure nil
  :if (> emacs-major-version 30)
  :commands (speedbar)
  :config
  (add-hook 'speedbar-before-visiting-file-hook
            #'suderman/speedbar-select-editor-window)
  
  (setq speedbar-prefer-window t)
  (setq speedbar-window-default-width 50)
  (setq speedbar-use-images nil)

  ;; Example colors
  (set-face-attribute 'speedbar-directory-face nil
		      :inherit 'font-lock-keyword-face
		      :weight 'bold)
  (set-face-attribute 'speedbar-file-face nil
		      :inherit 'default)
  (set-face-attribute 'speedbar-selected-face nil
		      :inherit 'highlight
		      :weight 'bold)
  
  ;; Tree appearance
  (setq speedbar-indentation-width 2)
  (setq speedbar-hide-button-brackets-flag t)

  ;; Behavior
  (setq speedbar-use-tool-tips-flag nil)
  (setq speedbar-show-unknown-files t)
  
  ;; Vim-ish tree controls
  (keymap-set speedbar-mode-map "j" #'speedbar-next)
  (keymap-set speedbar-mode-map "k" #'speedbar-prev)

  (keymap-set speedbar-file-key-map "l" #'speedbar-expand-line)
  (keymap-set speedbar-file-key-map "h" #'speedbar-contract-line)
  (keymap-set speedbar-file-key-map "RET" #'speedbar-edit-line))
 
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
