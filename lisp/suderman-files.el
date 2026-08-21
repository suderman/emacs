;;; suderman-files.el --- File and directory browsing -*- lexical-binding: t; -*-

;;; Commentary:
;; Directory browsing lives here.  Project/file picker logic is elsewhere; this
;; module is about moving around directory trees once opened.

;;; Code:

(require 'dired)
(require 'use-package)
(require 'suderman-windows)

(defvar speedbar-buffer)
(defvar speedbar-full-text-cache)
(defvar speedbar-initial-expansion-list-name)
(defvar speedbar-initial-expansion-mode-alist)
(defvar speedbar-previously-used-expansion-list-name)
(defvar speedbar-shown-directories)

(defun suderman/revert-buffer-no-confirm ()
  "Revert the current buffer without confirmation or auto-save recovery."
  (interactive)
  (revert-buffer t t))

(defun suderman/speedbar-select-editor-window ()
  "Select the most recently used normal editor window."
  (let ((window (get-mru-window nil nil t t)))
    (when window
      (select-window window))))

(defun suderman/speedbar-disable-meow ()
  "Disable Meow in the current Speedbar buffer."
  (when (bound-and-true-p meow-mode)
    (meow-mode -1)))

(defun suderman/speedbar-setup ()
  "Use Speedbar's native navigation without visual line wrapping."
  (visual-line-mode -1)
  (add-hook 'meow-mode-hook #'suderman/speedbar-disable-meow nil t)
  (suderman/speedbar-disable-meow))

(defun suderman/speedbar-toggle ()
  "Toggle Speedbar, revealing the current file when opened."
  (interactive)
  (let ((file (buffer-local-value 'buffer-file-name
                                  (window-buffer (selected-window))))
         (visible (and (boundp 'speedbar-buffer)
                       (buffer-live-p speedbar-buffer)
                       (get-buffer-window speedbar-buffer (selected-frame)))))
    (when (and visible
               (equal speedbar-initial-expansion-list-name "files"))
      (with-current-buffer speedbar-buffer
        (speedbar-clear-current-file)
        (setq speedbar-full-text-cache
              (cons (copy-sequence speedbar-shown-directories)
                    (buffer-string))
              speedbar-shown-directories nil)))
    (speedbar)
    (unless visible
      (when-let* ((window (get-buffer-window speedbar-buffer
                                              (selected-frame))))
        (select-window window)
        (when file
          (unless (equal speedbar-initial-expansion-list-name "files")
            (suderman/speedbar-show-files))
          (unless (suderman/speedbar--goto-file file)
            (setq default-directory (file-name-directory file)
                  speedbar-shown-directories (list default-directory))
            (speedbar-update-contents)
            (suderman/speedbar--goto-file file)))))))

(defun suderman/speedbar-up-directory ()
  "Move to the parent directory without collapsing the current tree."
  (interactive)
  (let* ((directory (file-name-as-directory
                     (expand-file-name default-directory)))
         (parent (file-name-directory (directory-file-name directory)))
         (shown-directories
          (or (copy-sequence speedbar-shown-directories)
              (list directory))))
    (unless (equal directory parent)
      (speedbar-up-directory)
      (setq speedbar-shown-directories
            (append shown-directories
                    (list (expand-file-name default-directory))))
      (speedbar-update-contents)
      (speedbar-directory-line directory))))

(defun suderman/speedbar--line-marker ()
  "Return the current Speedbar row's Org source marker, when present."
  (let ((position (line-beginning-position))
        (end (line-end-position))
        marker)
    (while (and (< position end) (not marker))
      (setq marker (get-text-property position 'org-imenu-marker)
            position (1+ position)))
    (and (markerp marker) (marker-buffer marker) marker)))

(defun suderman/speedbar-edit-line ()
  "Edit the current item, preserving expansions when entering a directory."
  (interactive)
  (let* ((item (speedbar-line-file))
         (directory (and item
                         (file-directory-p item)
                         (file-name-as-directory (expand-file-name item))))
         (shown-directories (copy-sequence speedbar-shown-directories))
         (marker (suderman/speedbar--line-marker)))
    (if marker
        (speedbar-tag-find nil marker (speedbar--get-line-indent-level))
      (speedbar-edit-line))
    (when (and directory
               (equal directory
                      (file-name-as-directory
                       (expand-file-name default-directory))))
      (setq speedbar-shown-directories
            (seq-filter (lambda (shown-directory)
                          (file-in-directory-p shown-directory directory))
                        shown-directories))
      (unless (member directory speedbar-shown-directories)
        (setq speedbar-shown-directories
              (append speedbar-shown-directories (list directory))))
      (speedbar-update-contents))))

(defun suderman/speedbar--line-has-children-p ()
  "Return non-nil when the current Speedbar row has visible children."
  (let ((depth (speedbar--get-line-indent-level)))
    (save-excursion
      (forward-line 1)
      (and (not (eobp))
           (> (speedbar--get-line-indent-level) depth)))))

(defun suderman/speedbar-smart-open (&optional arg)
  "Expand the current node, or open it when already expanded or a leaf.
With universal argument ARG, flush cached data while expanding."
  (interactive "P")
  (if (suderman/speedbar--line-has-children-p)
      (suderman/speedbar-edit-line)
    (speedbar-expand-line arg)
    (unless (suderman/speedbar--line-has-children-p)
      (suderman/speedbar-edit-line))))

(defun suderman/speedbar-smart-close ()
  "Collapse the current node, or move to the parent when already closed."
  (interactive)
  (if (suderman/speedbar--line-has-children-p)
      (speedbar-contract-line)
    (suderman/speedbar-up-directory)))

(defun suderman/speedbar--goto-file (file)
  "Move to FILE's visible Speedbar row and return non-nil when found."
  (goto-char (point-min))
  (catch 'found
    (while (not (eobp))
      (let ((line-file (speedbar-line-file)))
        (when (and line-file (file-equal-p line-file file))
          (speedbar-position-cursor-on-line)
          (throw 'found t)))
      (forward-line 1))))

(defun suderman/speedbar-create-item ()
  "Create a file, or a directory when its name ends in a slash."
  (interactive)
  (let* ((item (speedbar-line-file))
         (base-directory
          (file-name-as-directory
           (cond
            ((and item (file-directory-p item)) item)
            (item (file-name-directory item))
            (t default-directory))))
         (input (read-file-name "Create file or directory: "
                                base-directory))
         (directoryp (directory-name-p input))
         (path (expand-file-name input)))
    (when (file-exists-p path)
      (user-error "%s already exists" path))
    (if directoryp
        (make-directory path t)
      (make-empty-file path t))
    (let ((directory
           (file-name-as-directory
            (file-name-directory
             (if directoryp (directory-file-name path) path))))
          (root (file-name-as-directory
                 (expand-file-name default-directory)))
          directories)
      (while (and (file-in-directory-p directory root)
                  (not (equal directory root)))
        (push directory directories)
        (setq directory
              (file-name-directory (directory-file-name directory))))
      (dolist (shown-directory directories)
        (setq speedbar-shown-directories
              (delete shown-directory speedbar-shown-directories))
        (push shown-directory speedbar-shown-directories)))
    (speedbar-refresh)
    (suderman/speedbar--goto-file path)))

(defun suderman/speedbar-show-buffers ()
  "Show buffers in Speedbar."
  (interactive)
  (speedbar-change-initial-expansion-list "buffers"))

(defun suderman/speedbar-show-files ()
  "Show files in Speedbar."
  (interactive)
  (speedbar-change-initial-expansion-list "files"))

(defun suderman/speedbar-previous-view ()
  "Return to Speedbar's previous view."
  (interactive)
  (speedbar-change-initial-expansion-list
   speedbar-previously-used-expansion-list-name))

(defun suderman/speedbar-show-keybindings ()
  "Show the current Speedbar view's bindings in a Which-Key popup."
  (interactive)
  (let ((keymap
         (nth 2 (assoc speedbar-initial-expansion-list-name
                       speedbar-initial-expansion-mode-alist))))
    (which-key-show-full-keymap (or keymap 'speedbar-mode-map))))

(use-package speedbar
  :ensure nil
  :if (> emacs-major-version 30)
  :commands (speedbar)
  :config
  (add-hook 'speedbar-before-visiting-file-hook
            #'suderman/speedbar-select-editor-window)
  (add-hook 'speedbar-mode-hook #'suderman/speedbar-setup)
  
  (setq speedbar-prefer-window t)
  (setq speedbar-window-default-width 50)

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
  
  ;; Lowercase-first tree controls
  (dolist (key '("n" "p" "r" "Q" "M-n" "M-p" "C-M-n" "C-M-p"))
    (keymap-unset speedbar-mode-map key t))
  (dolist (key '("e" "SPC" "+" "=" "-" "[" "]"
                  "U" "I" "B" "L" "C" "D" "O" "R" "M" "?"))
    (keymap-unset speedbar-file-key-map key t))
  (dolist (key '("e" "SPC" "+" "=" "-" "k"))
    (keymap-unset speedbar-buffers-key-map key t))

  (keymap-set speedbar-mode-map "h" #'suderman/speedbar-smart-close)
  (keymap-set speedbar-mode-map "l" #'suderman/speedbar-smart-open)
  (keymap-set speedbar-mode-map "H" #'speedbar-contract-line-descendants)
  (keymap-set speedbar-mode-map "L" #'speedbar-expand-line-descendants)
  (keymap-set speedbar-mode-map "j" #'speedbar-next)
  (keymap-set speedbar-mode-map "k" #'speedbar-prev)
  (keymap-set speedbar-mode-map "b" #'suderman/speedbar-show-buffers)
  (keymap-set speedbar-mode-map "f" #'suderman/speedbar-show-files)
  (keymap-set speedbar-mode-map "v" #'suderman/speedbar-previous-view)
  (keymap-set speedbar-mode-map "?" #'suderman/speedbar-show-keybindings)
  (keymap-set speedbar-mode-map "S" #'suderman/speedbar-toggle)
  (keymap-set speedbar-mode-map "`" #'suderman/speedbar-toggle)
  (keymap-set speedbar-mode-map "q" #'suderman/speedbar-toggle)
  (keymap-set speedbar-mode-map "M-h" #'suderman/window-left)
  (keymap-set speedbar-mode-map "M-j" #'windmove-down)
  (keymap-set speedbar-mode-map "M-k" #'windmove-up)
  (keymap-set speedbar-mode-map "M-l" #'windmove-right)
  (keymap-set speedbar-mode-map "M-H" #'suderman/shrink-window-width)
  (keymap-set speedbar-mode-map "M-J" #'suderman/enlarge-window-height)
  (keymap-set speedbar-mode-map "M-K" #'suderman/shrink-window-height)
  (keymap-set speedbar-mode-map "M-L" #'suderman/enlarge-window-width)

  (keymap-set speedbar-file-key-map "RET" #'suderman/speedbar-edit-line)
  (keymap-set speedbar-file-key-map "o" #'suderman/speedbar-edit-line)
  (keymap-set speedbar-file-key-map "u" #'suderman/speedbar-up-directory)
  (keymap-set speedbar-file-key-map "n" #'suderman/speedbar-create-item)
  (keymap-set speedbar-file-key-map "i" #'speedbar-item-info)
  (keymap-set speedbar-file-key-map "c" #'speedbar-item-copy)
  (keymap-set speedbar-file-key-map "d" #'speedbar-item-delete)
  (keymap-set speedbar-file-key-map "r" #'speedbar-item-rename)

  (keymap-set speedbar-buffers-key-map "RET" #'speedbar-edit-line)
  (keymap-set speedbar-buffers-key-map "o" #'speedbar-edit-line)
  (keymap-set speedbar-buffers-key-map "d" #'speedbar-buffer-kill-buffer)
  (keymap-set speedbar-buffers-key-map "r" #'speedbar-buffer-revert-buffer))

(use-package nerd-icons-speedbar
  :vc (:url "https://github.com/Akane-6730/nerd-icons-speedbar.git")
  :after speedbar
  :demand t
  :config
  (unless nerd-icons-speedbar-mode
    (nerd-icons-speedbar-mode 1)))
 
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
