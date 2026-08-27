;;; suderman-files.el --- Dired and file utilities -*- lexical-binding: t; -*-

;;; Commentary:
;; Generic file commands and Dired/Dirvish navigation live here.

;;; Code:

(require 'dired)
(require 'dired-x)
(require 'use-package)
(require 'suderman-buffers)
(require 'suderman-windows)

(defvar dirvish-quick-access-entries)
(defvar dirvish-preview-setup-hook)
(defvar dirvish-yank-sources)
(defvar global-hl-line-mode)
(declare-function suderman/dashboard "suderman-dashboard")
(declare-function dirvish--build-layout "dirvish")
(declare-function dirvish--create-parent-buffer "dirvish")
(declare-function dirvish "dirvish")
(declare-function dirvish-curr "dirvish")
(declare-function dirvish-dwim "dirvish")
(declare-function dirvish-fd "dirvish-fd")
(declare-function dirvish-layout-toggle "dirvish")
(declare-function dirvish-quit "dirvish")
(declare-function dirvish-move "dirvish-yank")
(declare-function dirvish-yank "dirvish-yank")
(declare-function dv-curr-layout "dirvish")
(declare-function dv-index "dirvish")
(declare-function global-hl-line-unhighlight "hl-line")
(declare-function meow--disable "meow")
(declare-function meow-keypad "meow-keypad")
(declare-function meow-mode "meow")
(declare-function which-key-show-keymap "which-key")

(defun suderman/revert-buffer-no-confirm ()
  "Revert the current buffer without confirmation or auto-save recovery."
  (interactive)
  (revert-buffer t t))

(defun suderman/dirvish (&optional path)
  "Toggle Dirvish for PATH, selecting it when it is a file."
  (interactive)
  (if (and (fboundp 'dirvish-curr) (dirvish-curr))
      (dirvish-quit)
    (let* ((target (expand-file-name (or path buffer-file-name
                                         default-directory)))
           (directory (if (file-directory-p target)
                          target
                        (file-name-directory target))))
      (dirvish-dwim directory)
      (unless (file-directory-p target)
        (dired-goto-file target)))))

(defun suderman/dirvish-ibuffer ()
  "Replace full-frame Dirvish with IBuffer."
  (interactive)
  (when-let* ((session (dirvish-curr))
              ((dv-curr-layout session)))
    (dirvish-quit))
  (set-buffer (window-buffer (selected-window)))
  (suderman/ibuffer-toggle))

(defconst suderman/dirvish-help-keys
  '(("h" . "Parent directory")
    ("j" . "Next entry")
    ("k" . "Previous entry")
    ("l" . "Open entry")
    ("f" . "Toggle fullscreen")
    ("H" . "History backward")
    ("L" . "History forward")
    ("m" . "Toggle mark")
    ("M" . "Mark all")
    ("t" . "Invert marks")
    ("u" . "Unmark")
    ("U" . "Unmark all")
    ("c" . "Stage copy")
    ("x" . "Stage cut")
    ("v" . "Paste staged files")
    ("C" . "Copy immediately")
    ("D" . "Delete immediately")
    ("d" . "Flag for deletion")
    ("X" . "Delete flagged files")
    ("Z" . "Compress")
    ("a" . "Create file or directory")
    ("r" . "Rename or move")
    ("g" . "Refresh")
    ("I" . "File information")
    ("i" . "Toggle dotfiles")
    ("s" . "Sort")
    ("z" . "Quick access")
    ("/" . "Search here")
    ("," . "Open IBuffer")
    ("." . "Toggle Dirvish")
    ("q" . "Close view")
    ("SPC" . "Meow keypad")
    ("M-h" . "Focus left window")
    ("M-j" . "Focus lower window")
    ("M-k" . "Focus upper window")
    ("M-l" . "Focus right window")
    ("M-H" . "Move divider left")
    ("M-J" . "Move divider down")
    ("M-K" . "Move divider up")
    ("M-L" . "Move divider right")
    ("M-u" . "Split below")
    ("M-i" . "Split right")
    ("M-w" . "Close window or tab")
    ("?" . "Show these bindings"))
  "Practical Dirvish keys and their help labels.")

(defvar suderman/dirvish-help-map (make-sparse-keymap)
  "Current effective bindings displayed by `suderman/dirvish-help'.")

(defun suderman/dirvish-help ()
  "Show practical current directory bindings with Which-Key."
  (interactive)
  (require 'which-key)
  (setq suderman/dirvish-help-map (make-sparse-keymap))
  (dolist (entry suderman/dirvish-help-keys)
    (when-let* ((command (key-binding (kbd (car entry))))
                ((commandp command)))
      (keymap-set suderman/dirvish-help-map (car entry)
                  (cons (cdr entry) command))))
  (which-key-show-keymap 'suderman/dirvish-help-map))

(defun suderman/dirvish-search (pattern)
  "Search below the current directory for comma-separated PATTERNs."
  (interactive (list (read-string "Search current directory: ")))
  (dirvish-fd nil pattern))

(defun suderman/dired-disable-meow ()
  "Disable Meow in the current Dired or Dirvish buffer."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/dired-disable-line-numbers ()
  "Keep line numbers disabled in the current buffer."
  (when display-line-numbers-mode
    (display-line-numbers-mode -1)))

(defun suderman/dirvish-preview-disable-line-numbers ()
  "Keep line numbers disabled in the current Dirvish preview."
  (add-hook 'display-line-numbers-mode-hook
            #'suderman/dired-disable-line-numbers nil t)
  (suderman/dired-disable-line-numbers))

(defun suderman/dired-disable-visual-line-mode ()
  "Keep directory entries on one display row."
  (when visual-line-mode
    (visual-line-mode -1))
  (setq-local truncate-lines t))

(defun suderman/dired-disable-column-indicator ()
  "Keep the fill-column indicator out of directory buffers."
  (when display-fill-column-indicator-mode
    (display-fill-column-indicator-mode -1)))

(defun suderman/dired-disable-hl-line ()
  "Let Dirvish own current-row highlighting."
  (setq-local global-hl-line-mode nil)
  (when (fboundp 'global-hl-line-unhighlight)
    (global-hl-line-unhighlight)))

(defun suderman/dired-setup ()
  "Prepare a Dired or Dirvish directory buffer."
  (setq-local dired-omit-files "\\`\\."
              dired-omit-extensions nil
              dired-omit-verbose nil)
  (add-hook 'meow-mode-hook #'suderman/dired-disable-meow nil t)
  (add-hook 'display-line-numbers-mode-hook
            #'suderman/dired-disable-line-numbers nil t)
  (add-hook 'visual-line-mode-hook
            #'suderman/dired-disable-visual-line-mode nil t)
  (add-hook 'display-fill-column-indicator-mode-hook
            #'suderman/dired-disable-column-indicator nil t)
  (suderman/dired-disable-meow)
  (suderman/dired-disable-line-numbers)
  (suderman/dired-disable-visual-line-mode)
  (suderman/dired-disable-column-indicator)
  (suderman/dired-disable-hl-line))

(defun suderman/dired-hide-dotfiles ()
  "Hide dotfiles when a directory buffer is first created."
  (dired-omit-mode 1))

(defun suderman/dirvish-create-parent-buffer
    (function session directory index level)
  "Call FUNCTION and match the parent pane to SESSION's dotfile visibility."
  (let ((buffer (funcall function session directory index level))
        (omit (with-current-buffer (cdr (dv-index session))
                (bound-and-true-p dired-omit-mode))))
    (with-current-buffer buffer
      (setq-local dired-directory directory
                  dired-omit-files "\\`\\."
                  dired-omit-extensions nil
                  dired-omit-mode omit)
      (when omit
        (let ((dired-omit-verbose nil))
          (dired-omit-expunge))))
    buffer))

(defun suderman/dirvish-toggle-dotfiles ()
  "Toggle dotfiles in the current Dirvish layout."
  (interactive)
  (dired-omit-mode (if dired-omit-mode -1 1))
  (when-let* ((session (dirvish-curr))
              ((dv-curr-layout session)))
    (dirvish--build-layout session)))

(defun suderman/dired-toggle-mark ()
  "Toggle the current file's ordinary mark without moving."
  (interactive)
  (unless (dired-get-filename nil t)
    (user-error "No file on this line"))
  (save-excursion
    (if (eq (char-after (line-beginning-position)) dired-marker-char)
        (dired-unmark 1)
      (dired-mark 1))))

(defun suderman/dired-mark-all ()
  "Mark every displayed file."
  (interactive)
  (dired-mark-files-regexp "."))

(defun suderman/dired-unmark ()
  "Unmark at point without moving to another row."
  (interactive)
  (save-excursion
    (call-interactively #'dired-unmark)))

(defun suderman/dired-create-item ()
  "Create a file, or a directory when its name ends in a slash."
  (interactive)
  (let* ((input (read-file-name "Create file or directory: "
                                default-directory))
         (directoryp (directory-name-p input))
         (path (expand-file-name input)))
    (when (file-exists-p path)
      (user-error "%s already exists" path))
    (if directoryp
        (make-directory path t)
      (make-empty-file path t))
    (revert-buffer)
    (dired-goto-file (if directoryp (directory-file-name path) path))))

(defvar suderman/dired-transfer nil
  "Staged file operation as (METHOD . FILES).")

(defun suderman/dired--stage-transfer (method)
  "Stage the marked files for transfer using METHOD."
  (let ((files (dired-get-marked-files)))
    (unless files
      (user-error "No files to stage"))
    (setq suderman/dired-transfer (cons method files))
    (message "Staged %d item%s to %s"
             (length files)
             (if (= (length files) 1) "" "s")
             (if (eq method 'copy) "copy" "cut"))))

(defun suderman/dired-copy-files ()
  "Stage the marked files, or the current file, for copying."
  (interactive)
  (suderman/dired--stage-transfer 'copy))

(defun suderman/dired-cut-files ()
  "Stage the marked files, or the current file, for moving."
  (interactive)
  (suderman/dired--stage-transfer 'move))

(defun suderman/dired-paste-files ()
  "Copy or move the staged files into the current directory."
  (interactive)
  (pcase suderman/dired-transfer
    (`(,method . ,files)
     (unless files
       (user-error "No files staged for copying or moving"))
     (dolist (file files)
       (unless (or (file-exists-p file) (file-symlink-p file))
         (user-error "%s no longer exists" file)))
     (let ((dirvish-yank-sources (lambda () files)))
       (pcase method
         ('copy (dirvish-yank))
         ('move (dirvish-move))))
     (when (eq method 'move)
       (setq suderman/dired-transfer nil)))
    (_ (user-error "No files staged for copying or moving"))))

(defun suderman/dired-clean-up-after-deletion (function file)
  "Call FUNCTION for FILE, prompting only for a modified visiting buffer."
  (let* ((buffer (get-file-buffer file))
         (dired-clean-confirm-killing-deleted-buffers
          (and buffer (buffer-modified-p buffer))))
    (funcall function file)))

(defun suderman/ibuffer-dirvish ()
  "Open Dirvish for the buffer or project group at point."
  (interactive)
  (let* ((buffer (ibuffer-current-buffer))
         (group (get-text-property (line-beginning-position)
                                   'ibuffer-filter-group-name))
         (target
          (cond
           ((buffer-live-p buffer)
            (with-current-buffer buffer
              (or buffer-file-name default-directory)))
           ((and (stringp group) (file-directory-p group))
            (file-name-as-directory (expand-file-name group)))
           (t default-directory))))
    (suderman/dirvish target)))

(advice-remove 'dired-clean-up-after-deletion
               #'suderman/dired-clean-up-after-deletion)
(advice-add 'dired-clean-up-after-deletion :around
            #'suderman/dired-clean-up-after-deletion)

(add-hook 'dired-mode-hook #'suderman/dired-setup)
(add-hook 'dired-mode-hook #'suderman/dired-hide-dotfiles t)
(keymap-set ibuffer-mode-map "." #'suderman/ibuffer-dirvish)
(keymap-set dired-mode-map "`" #'suderman/dashboard)

(use-package dirvish
  :commands (dirvish dirvish-dwim)
  :init
  (setq dired-listing-switches "-al --group-directories-first"
        dirvish-attributes '(vc-state nerd-icons file-modes)
        dirvish-default-layout '(1 0.125 0.5)
        dirvish-mode-line-format
        '(:left (sort vc-info symlink yank)
          :right (file-size file-modes index))
        dirvish-preview-dired-sync-omit nil
        dirvish-quick-access-entries
        '(("h" "~/" "Home")
          ("d" "~/Downloads/" "Downloads")
          ("k" "~/Desktop/" "Desktop")
          ("b" "~/Documents/" "Documents")
          ("i" "~/Pictures/" "Pictures")
          ("v" "~/Movies/" "Movies")
          ("m" "~/Music/" "Music")
          ("g" "~/games/" "Games")
          ("s" "~/src/" "Source")
          ("n" "~/notes/" "Notes")
          ("c" "/etc/nixos/" "NixOS")
          ("t" "/mnt/main/storage/" "Storage")
          ("x" "/mnt/main/scratch/" "Scratch"))
        dirvish-use-mode-line 'global)
  :config
  (dirvish-override-dired-mode 1)
  (require 'dirvish-yank)
  (add-hook 'dirvish-preview-setup-hook
            #'suderman/dirvish-preview-disable-line-numbers)
  (advice-remove 'dirvish--create-parent-buffer
                 #'suderman/dirvish-create-parent-buffer)
  (advice-add 'dirvish--create-parent-buffer :around
              #'suderman/dirvish-create-parent-buffer)
  (add-hook 'dirvish-directory-view-mode-hook #'suderman/dired-setup)
  (dolist (map (list dired-mode-map dirvish-mode-map))
    (keymap-set map "`" #'suderman/dashboard)
    (keymap-set map "SPC" #'meow-keypad)
    (keymap-set map "," #'suderman/dirvish-ibuffer)
    (keymap-set map "." #'suderman/dirvish)
    (keymap-set map "?" #'suderman/dirvish-help)
    (keymap-set map "/" #'suderman/dirvish-search)
    (keymap-set map "H" #'dirvish-history-go-backward)
    (keymap-set map "I" #'dirvish-file-info-menu)
    (keymap-set map "L" #'dirvish-history-go-forward)
    (keymap-set map "M" #'suderman/dired-mark-all)
    (keymap-set map "U" #'dired-unmark-all-marks)
    (keymap-set map "X" #'dired-do-flagged-delete)
    (keymap-set map "a" #'suderman/dired-create-item)
    (keymap-set map "c" #'suderman/dired-copy-files)
    (keymap-set map "f" #'dirvish-layout-toggle)
    (keymap-set map "h" #'dired-up-directory)
    (keymap-set map "g" #'revert-buffer)
    (keymap-set map "i" #'suderman/dirvish-toggle-dotfiles)
    (keymap-set map "j" #'dired-next-line)
    (keymap-set map "k" #'dired-previous-line)
    (keymap-set map "l" #'dired-find-file)
    (keymap-set map "m" #'suderman/dired-toggle-mark)
    (keymap-set map "r" #'dired-do-rename)
    (keymap-set map "s" #'dirvish-quicksort)
    (keymap-set map "u" #'suderman/dired-unmark)
    (keymap-set map "v" #'suderman/dired-paste-files)
    (keymap-set map "x" #'suderman/dired-cut-files)
    (keymap-set map "z" #'dirvish-quick-access)
    (keymap-set map "M-h" #'suderman/window-left)
    (keymap-set map "M-j" #'windmove-down)
    (keymap-set map "M-k" #'windmove-up)
    (keymap-set map "M-l" #'windmove-right)
    (keymap-set map "M-H" #'suderman/resize-window-left)
    (keymap-set map "M-J" #'suderman/resize-window-down)
    (keymap-set map "M-K" #'suderman/resize-window-up)
    (keymap-set map "M-L" #'suderman/resize-window-right)
    (keymap-set map "M-u" #'suderman/split-window-below-and-focus)
    (keymap-set map "M-i" #'suderman/split-window-right-and-focus)
    (keymap-set map "M-w" #'suderman/delete-window-or-tab))
  (keymap-set dired-mode-map "q" #'quit-window)
  (require 'dirvish-widgets)
  (set-face-attribute 'dirvish-file-modes nil
                      :inherit 'font-lock-keyword-face
                      :foreground 'unspecified)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (or (derived-mode-p 'dired-mode)
                (derived-mode-p 'dirvish-directory-view-mode))
        (suderman/dired-setup)))))

(provide 'suderman-files)
;;; suderman-files.el ends here
