;;; suderman-files.el --- File and directory browsing -*- lexical-binding: t; -*-

;;; Commentary:
;; Directory browsing lives here.  Project/file picker logic is elsewhere; this
;; module is about moving around directory trees once opened.

;;; Code:

(require 'dired)
(require 'use-package)
(require 'suderman-windows)

(defun suderman/revert-buffer-no-confirm ()
  "Revert the current buffer without confirmation or auto-save recovery."
  (interactive)
  (revert-buffer t t))

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

  ;; Inherit semantic faces so Speedbar follows the active Stylix theme.
  (face-spec-set 'speedbar-button-face
                 '((t (:inherit shadow))) 'face-defface-spec)
  (face-spec-set 'speedbar-file-face
                 '((t (:inherit default))) 'face-defface-spec)
  (face-spec-set 'speedbar-directory-face
                 '((t (:inherit dired-directory :weight bold)))
                 'face-defface-spec)
  (face-spec-set 'speedbar-tag-face
                 '((t (:inherit font-lock-function-name-face)))
                 'face-defface-spec)
  (face-spec-set 'speedbar-selected-face
                 '((t (:inherit (highlight default)
                       :weight bold :underline nil)))
                 'face-defface-spec)
  (face-spec-set 'speedbar-highlight-face
                 '((t (:inherit highlight))) 'face-defface-spec)
  (face-spec-set 'speedbar-separator-face
                 '((t (:inherit header-line))) 'face-defface-spec)
  
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
