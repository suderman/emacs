;;; suderman-speedbar.el --- Frame-aware Speedbar browsing -*- lexical-binding: t; -*-

;;; Commentary:
;; Configure Speedbar as a frame-aware, keyboard-driven file and buffer tree.

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
(defvar suderman/speedbar-focus-timer nil)
(defvar suderman/speedbar-focused-frames nil)

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

(defun suderman/speedbar--save-frame-state (frame window)
  "Save FRAME's Speedbar tree state from WINDOW."
  (with-current-buffer speedbar-buffer
    (let ((shown-directories (copy-sequence speedbar-shown-directories))
          (cache speedbar-full-text-cache))
      (when (equal speedbar-initial-expansion-list-name "files")
        (speedbar-clear-current-file)
        (setq cache (cons shown-directories (buffer-string))))
      (set-frame-parameter
       frame 'suderman/speedbar-state
       (list :directory default-directory
             :shown-directories shown-directories
             :cache (and cache
                         (cons (copy-sequence (car cache))
                               (copy-sequence (cdr cache))))
             :view speedbar-initial-expansion-list-name
             :previous-view speedbar-previously-used-expansion-list-name
             :point (window-point window)
             :window-start (window-start window)))
      ;; A new Speedbar buffer must not mistake this tree for rendered state.
      (setq speedbar-full-text-cache cache
            speedbar-shown-directories nil))))

(defun suderman/speedbar--restore-frame-state (frame window)
  "Restore FRAME's saved Speedbar tree state in WINDOW."
  (when-let* ((state (frame-parameter frame 'suderman/speedbar-state)))
    (let ((cache (plist-get state :cache))
          (shown-directories (plist-get state :shown-directories))
          (view (plist-get state :view)))
      (with-current-buffer speedbar-buffer
        (setq default-directory (plist-get state :directory)
              speedbar-initial-expansion-list-name view
              speedbar-previously-used-expansion-list-name
              (plist-get state :previous-view)
              speedbar-shown-directories nil
              speedbar-full-text-cache
              (and (equal view "files") cache))
        (speedbar-update-contents)
        (unless (equal view "files")
          (setq speedbar-full-text-cache cache
                speedbar-shown-directories shown-directories))
        (set-window-point
         window (min (max (point-min) (plist-get state :point)) (point-max)))
        (set-window-start
         window
         (min (max (point-min) (plist-get state :window-start)) (point-max))
         t)))))

(defun suderman/speedbar--window ()
  "Return the live Speedbar window, wherever it is displayed."
  (and (boundp 'speedbar-buffer)
       (buffer-live-p speedbar-buffer)
       (get-buffer-window speedbar-buffer t)))

(defun suderman/speedbar--hide ()
  "Save and close the visible Speedbar without changing open intent."
  (when-let* ((window (suderman/speedbar--window)))
    (suderman/speedbar--save-frame-state (window-frame window) window)
    (speedbar -1)))

(defun suderman/speedbar--show (frame select)
  "Restore Speedbar in FRAME, selecting it when SELECT is non-nil."
  (when (frame-live-p frame)
    (with-selected-frame frame
      (let* ((editor-window (selected-window))
             (file (buffer-local-value 'buffer-file-name
                                       (window-buffer editor-window)))
             (state (frame-parameter frame 'suderman/speedbar-state)))
        (set-frame-parameter frame 'suderman/speedbar-open-p t)
        (setq speedbar-full-text-cache nil
              speedbar-shown-directories nil
              speedbar-initial-expansion-list-name
              (or (plist-get state :view) "files")
              speedbar-previously-used-expansion-list-name
              (or (plist-get state :previous-view) "files"))
        (speedbar 1)
        (when-let* ((window (get-buffer-window speedbar-buffer frame)))
          (suderman/speedbar--restore-frame-state frame window)
          (with-current-buffer speedbar-buffer
            (when file
              (unless (equal speedbar-initial-expansion-list-name "files")
                (suderman/speedbar-show-files))
              (unless (suderman/speedbar--goto-file file)
                (setq default-directory (file-name-directory file)
                      speedbar-shown-directories (list default-directory))
                (speedbar-update-contents)
                (suderman/speedbar--goto-file file))))
          (select-window (if select window editor-window)))))))

(defun suderman/speedbar-toggle ()
  "Toggle Speedbar in this frame, preserving each frame's tree state."
  (interactive)
  (let* ((frame (selected-frame))
         (speedbar-window (suderman/speedbar--window))
         (visible (and speedbar-window
                       (eq frame (window-frame speedbar-window)))))
    (if visible
        (progn
          (set-frame-parameter frame 'suderman/speedbar-open-p nil)
          (suderman/speedbar--hide))
      (when speedbar-window
        (set-frame-parameter
         (window-frame speedbar-window) 'suderman/speedbar-open-p t)
        (suderman/speedbar--hide))
      (suderman/speedbar--show frame t))))

(defun suderman/speedbar--focused-frames ()
  "Return focused top-level frames that can host Speedbar."
  (seq-filter
   (lambda (frame)
     (and (frame-live-p frame)
          (eq t (frame-focus-state frame))
          (not (frame-parameter frame 'parent-frame))
          (not (eq (frame-parameter frame 'minibuffer) 'only))))
   (frame-list)))

(defun suderman/speedbar--sync-focused-frame ()
  "Hide or restore Speedbar according to the newly focused frame."
  (setq suderman/speedbar-focus-timer nil)
  (let* ((focused-frames (suderman/speedbar--focused-frames))
         (newly-focused
          (seq-find (lambda (frame)
                      (not (memq frame suderman/speedbar-focused-frames)))
                    focused-frames))
         (target
          (or newly-focused
              (and (memq (selected-frame) focused-frames)
                   (selected-frame))
              (and (= (length focused-frames) 1)
                   (car focused-frames))))
         (speedbar-window (suderman/speedbar--window))
         (owner (and speedbar-window (window-frame speedbar-window))))
    (setq suderman/speedbar-focused-frames focused-frames)
    (when (and target (not (eq target owner)))
      (when owner
        (set-frame-parameter owner 'suderman/speedbar-open-p t)
        (suderman/speedbar--hide))
      (when (frame-parameter target 'suderman/speedbar-open-p)
        (suderman/speedbar--show target nil)))))

(defun suderman/speedbar--schedule-focus-sync ()
  "Debounce synchronization after frame focus changes."
  (when (timerp suderman/speedbar-focus-timer)
    (cancel-timer suderman/speedbar-focus-timer))
  (setq suderman/speedbar-focus-timer
        (run-with-idle-timer 0 nil #'suderman/speedbar--sync-focused-frame)))

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

  (when (timerp suderman/speedbar-focus-timer)
    (cancel-timer suderman/speedbar-focus-timer))
  (setq suderman/speedbar-focus-timer nil
        suderman/speedbar-focused-frames
        (suderman/speedbar--focused-frames))
  (remove-function after-focus-change-function
                   #'suderman/speedbar--schedule-focus-sync)
  (add-function :after after-focus-change-function
                #'suderman/speedbar--schedule-focus-sync)
  (when-let* ((window (suderman/speedbar--window)))
    (set-frame-parameter
     (window-frame window) 'suderman/speedbar-open-p t))

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

(provide 'suderman-speedbar)
;;; suderman-speedbar.el ends here
