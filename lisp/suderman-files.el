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
(defvar dirvish-archive-exts)
(defvar dirvish-binary-exts)
(defvar dirvish-preview-setup-hook)
(defvar dirvish-preview-dispatchers)
(defvar dirvish-peek-key)
(defvar dirvish-yank-sources)
(defvar dirvish-side-attributes)
(defvar dirvish-side-mode-line-format)
(defvar dirvish-subtree--state-icons)
(defvar global-hl-line-mode)
(defvar dirvish-directory-view-mode-map)
(defvar dirvish-misc-mode-map)
(defvar dirvish-mode-map)
(declare-function suderman/dashboard "suderman-dashboard")
(declare-function suderman/dashboard-from-mode-line "suderman-appearance")
(declare-function suderman/dirvish-from-mode-line "suderman-appearance")
(declare-function doom-modeline-face "doom-modeline-core")
(declare-function doom-modeline-icon "doom-modeline-core")
(declare-function dirvish--build-layout "dirvish")
(declare-function dirvish--create-parent-buffer "dirvish")
(declare-function dirvish--find-entry "dirvish")
(declare-function dirvish--find-file-temporarily "dirvish")
(declare-function dirvish--render-attrs "dirvish")
(declare-function dirvish--run-with-delay "dirvish")
(declare-function dirvish "dirvish")
(declare-function dirvish-curr "dirvish")
(declare-function dirvish-dispatch "dirvish-extras")
(declare-function dirvish-dwim "dirvish")
(declare-function dirvish-emerge-menu "dirvish-emerge")
(declare-function dirvish-fd "dirvish-fd")
(declare-function dirvish-layout-toggle "dirvish")
(declare-function dirvish-narrow "dirvish-narrow")
(declare-function dirvish-quit "dirvish")
(declare-function dirvish-move "dirvish-yank")
(declare-function dirvish-rsync "dirvish-rsync")
(declare-function dirvish-setup-menu "dirvish-extras")
(declare-function dirvish-side "dirvish-side")
(declare-function dirvish-side--session-visible-p "dirvish-side")
(declare-function dirvish-side-follow-mode "dirvish-side")
(declare-function dirvish-subtree-toggle "dirvish-subtree")
(declare-function dirvish-subtree-toggle-or-open "dirvish-subtree")
(declare-function dirvish-yank "dirvish-yank")
(declare-function dv-curr-layout "dirvish")
(declare-function dv-index "dirvish")
(declare-function dv-root-window "dirvish")
(declare-function dv-type "dirvish")
(declare-function global-hl-line-unhighlight "hl-line")
(declare-function meow--disable "meow")
(declare-function meow-keypad "meow-keypad")
(declare-function meow-mode "meow")
(declare-function pdf-tools-install "pdf-tools")
(declare-function which-key-show-keymap "which-key")

(defun suderman/revert-buffer-no-confirm ()
  "Revert the current buffer without confirmation or auto-save recovery."
  (interactive)
  (revert-buffer t t))

(defun suderman/dirvish-session ()
  "Return current Dirvish session, including a full-frame preview's session."
  (or (and (fboundp 'dirvish-curr) (dirvish-curr))
      (and (fboundp 'dirvish--get-session) (dirvish--get-session))))

(defun suderman/dirvish-quit-full-frame (session)
  "Quit SESSION's full-frame layout from its root window."
  (with-selected-window (dv-root-window session)
    (dirvish-quit)))

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
      (dirvish directory)
      (unless (and (>= (frame-width) 80) (one-window-p t))
        (dirvish-layout-toggle))
      (unless (file-directory-p target)
        (dired-goto-file target)))))

(defun suderman/dirvish-ibuffer ()
  "Open IBuffer from Dirvish without replacing a visible sidebar."
  (interactive)
  (when-let* ((session (suderman/dirvish-session)))
    (cond
     ((dv-curr-layout session)
      (suderman/dirvish-quit-full-frame session))
     ((eq (dv-type session) 'side)
      (select-window
       (or (get-mru-window (selected-frame) nil t t)
           (user-error "No editor window available"))))))
  (set-buffer (window-buffer (selected-window)))
  (suderman/ibuffer-toggle))

(defun suderman/dirvish-ibuffer-from-mode-line (event)
  "Open IBuffer from the Dirvish mode line EVENT clicked."
  (interactive "e")
  (select-window (posn-window (event-start event)))
  (suderman/dirvish-ibuffer))

(defun suderman/dirvish-mode-line-button (icon fallback help command)
  "Return a clickable Dirvish mode line button using ICON and COMMAND."
  (propertize (concat " "
                     (doom-modeline-icon 'codicon icon fallback fallback
                                          :face (doom-modeline-face))
                     " ")
              'mouse-face 'doom-modeline-highlight
              'help-echo help
              'local-map (let ((map (make-sparse-keymap)))
                           (define-key map [mode-line mouse-1] command)
                           map)))

(defun suderman/dirvish-side-toggle (&optional path)
  "Toggle the Dirvish sidebar for PATH without stealing editor focus."
  (interactive)
  (let ((session (dirvish-curr))
        (visible (dirvish-side--session-visible-p)))
    (cond
     ((and session (eq (dv-type session) 'side))
      (dirvish-quit))
     (visible
      (with-selected-window visible
        (dirvish-quit)))
     ((and session (dv-curr-layout session))
      (user-error "Close the full-frame Dirvish view before opening the sidebar"))
     (t
      (let ((editor (selected-window)))
        (dirvish-side path)
        (when (window-live-p editor)
          (select-window editor)))))))

(defconst suderman/dirvish-help-keys
  '(("h" . "Parent directory")
    ("j" . "Next entry")
    ("k" . "Previous entry")
    ("l" . "Open entry")
    ("f" . "Toggle fullscreen")
    ("TAB" . "Toggle subtree")
    ("S" . "Toggle file sidebar")
    ("H" . "History backward")
    ("L" . "History forward")
    ("N" . "Narrow entries")
    ("E" . "Manage file groups")
    ("R" . "Rsync marked files")
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
    ("'" . "Change view attributes")
    (";" . "Dirvish menu")
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

(defvar suderman/dirvish-subtree-mouse-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'dirvish-subtree-toggle-or-open)
    map)
  "Mouse bindings used by Dirvish subtree state arrows.")

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

(defun suderman/dired-open ()
  "Open the entry at point, delegating EPUB, audio, and video to the desktop."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (dired-find-file)
      (require 'mailcap)
      (let ((mime-type (mailcap-file-name-to-mime-type file)))
        (if (and mime-type
                 (or (equal mime-type "application/epub+zip")
                     (string-match-p "\\`\\(?:audio\\|video\\)/" mime-type)))
            (progn
              (unless (executable-find "xdg-open")
                (user-error "xdg-open is not installed"))
              (start-process "open-media" nil "xdg-open" file))
          (dired-find-file))))))

(defun suderman/dired-mouse-open (event)
  "Open the Dired entry clicked in EVENT."
  (interactive "e")
  (mouse-set-point event)
  (suderman/dired-open))

(defun suderman/dirvish-enable-subtree-mouse ()
  "Make Dirvish subtree state arrows toggle their directory on click."
  (dolist (icon (list (car dirvish-subtree--state-icons)
                      (cdr dirvish-subtree--state-icons)))
    (add-text-properties
     0 (length icon)
     `(keymap ,suderman/dirvish-subtree-mouse-map
              mouse-face highlight
              help-echo "mouse-1: toggle subtree")
     icon)))

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
  "Configure the current Dirvish preview."
  (add-hook 'display-line-numbers-mode-hook
            #'suderman/dired-disable-line-numbers nil t)
  (keymap-local-set "`" #'suderman/dashboard)
  (keymap-local-set "," #'suderman/dirvish-ibuffer)
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
              dired-omit-verbose nil
              mouse-1-click-follows-link nil)
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
  (suderman/dired-disable-hl-line)
  (when (derived-mode-p 'dirvish-directory-view-mode)
    (setq-local context-menu-functions '(t dired-context-menu))))

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

(defun suderman/dirvish-focus-root ()
  "Return focus from a Dirvish auxiliary pane to its root window."
  (interactive)
  (let* ((session (dirvish-curr))
         (root (and session (dv-root-window session))))
    (unless (window-live-p root)
      (user-error "No Dirvish root window available"))
    (select-window root)))

(defun suderman/dirvish-ignore-misc-window (function &rest arguments)
  "Exclude Dirvish breadcrumb windows returned by FUNCTION with ARGUMENTS."
  (let ((window (apply function arguments)))
    (unless (and (window-live-p window)
                 (with-current-buffer (window-buffer window)
                   (derived-mode-p 'dirvish-misc-mode)))
      window)))

(defun suderman/dirvish-render-after-narrow
    (function action &optional record callback debounce throttle)
  "Call FUNCTION and repaint attributes after a delayed narrow CALLBACK."
  (if (and (eq record :narrow) callback)
      (let ((session (dirvish-curr)))
        (funcall function action record
                 (lambda (&rest arguments)
                   (prog1 (apply callback arguments)
                     (when-let* ((root (and session (dv-root-window session)))
                                 ((window-live-p root)))
                       (dirvish--render-attrs root root))))
                 debounce throttle))
    (funcall function action record callback debounce throttle)))

(defun suderman/dirvish-parent-navigate (directory)
  "Show DIRECTORY in the root while keeping focus in the parent pane."
  (let* ((session (dirvish-curr))
         (root (and session (dv-root-window session))))
    (unless (window-live-p root)
      (user-error "No Dirvish root window available"))
    (select-window root)
    (dirvish--find-entry 'find-alternate-file directory)
    (when-let* ((new-root (dv-root-window session))
                ((window-live-p new-root))
                (parent (window-in-direction 'left new-root t)))
      (select-window parent))))

(defun suderman/dirvish-parent-move (function)
  "Move to a parent directory with FUNCTION and display it in the root pane."
  (funcall function 1)
  (let ((directory (dired-get-filename nil t)))
    (unless (and directory (file-directory-p directory))
      (user-error "No directory on this line"))
    (suderman/dirvish-parent-navigate directory)))

(defun suderman/dirvish-parent-next-directory ()
  "Select the next directory in the parent pane."
  (interactive)
  (suderman/dirvish-parent-move #'dired-next-dirline))

(defun suderman/dirvish-parent-previous-directory ()
  "Select the previous directory in the parent pane."
  (interactive)
  (suderman/dirvish-parent-move #'dired-prev-dirline))

(defun suderman/dirvish-parent-up-directory ()
  "Move the root and parent panes up one directory."
  (interactive)
  (suderman/dirvish-parent-navigate (dired-current-directory)))

(defun suderman/dirvish-find-entry-at-root (function find-function entry)
  "Call FUNCTION for ENTRY from the root when a breadcrumb is selected."
  (if (derived-mode-p 'dirvish-misc-mode)
      (let* ((session (dirvish-curr))
             (root (and session (dv-root-window session))))
        (unless (window-live-p root)
          (user-error "No Dirvish root window available"))
        (select-window root)
        (funcall function find-function entry))
    (funcall function find-function entry)))

(defun suderman/dirvish-parent-mouse-select (event)
  "Navigate the root Dirvish pane to the parent entry clicked in EVENT."
  (interactive "e")
  (let* ((position (event-start event))
         (window (posn-window position))
         (point (posn-point position))
         file session)
    (unless (and (windowp window) (integer-or-marker-p point))
      (user-error "No file chosen"))
    (with-selected-window window
      (goto-char point)
      (setq file (dired-get-filename nil t)
            session (dirvish-curr)))
    (unless file
      (user-error "No file chosen"))
    (let ((root (and session (dv-root-window session))))
      (unless (window-live-p root)
        (user-error "No Dirvish root window available"))
      (select-window root)
      (if (file-directory-p file)
          (dirvish--find-entry 'find-alternate-file file)
        (dirvish--find-entry 'find-alternate-file
                             (file-name-directory file))
        (dired-goto-file file)))))

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

(defun suderman/ibuffer-dirvish-side ()
  "Toggle a sidebar for the buffer or project group at point."
  (interactive)
  (let ((buffer (ibuffer-current-buffer))
        (group (get-text-property (line-beginning-position)
                                  'ibuffer-filter-group-name)))
    (if (buffer-live-p buffer)
        (with-current-buffer buffer
          (suderman/dirvish-side-toggle))
      (suderman/dirvish-side-toggle
       (and (stringp group) (file-directory-p group)
            (file-name-as-directory (expand-file-name group)))))))

(advice-remove 'dired-clean-up-after-deletion
               #'suderman/dired-clean-up-after-deletion)
(advice-add 'dired-clean-up-after-deletion :around
            #'suderman/dired-clean-up-after-deletion)

(add-hook 'dired-mode-hook #'suderman/dired-setup)
(add-hook 'dired-mode-hook #'suderman/dired-hide-dotfiles t)
(keymap-set ibuffer-mode-map "." #'suderman/ibuffer-dirvish)
(keymap-set ibuffer-mode-map "S" #'suderman/ibuffer-dirvish-side)
(keymap-set ibuffer-mode-map "l" #'suderman/ibuffer-open)
(keymap-unset ibuffer-mode-map "i" t)
(keymap-unset ibuffer-mode-map "H" t)
(keymap-unset ibuffer-mode-map "SPC" t)
(keymap-set dired-mode-map "`" #'suderman/dashboard)

(use-package pdf-tools
  :ensure nil
  :demand t
  :config
  (pdf-tools-install))

(use-package dirvish
  :demand t
  :init
  (setq dired-listing-switches "-al --group-directories-first"
        dirvish-attributes
        '(vc-state subtree-state nerd-icons collapse file-size)
        dirvish-default-layout '(1 0.125 0.5)
        dirvish-mode-line-format
        '(:left (suderman-dashboard suderman-dirvish suderman-ibuffer
                 sort vc-info symlink yank)
          :right (file-size file-modes index))
        dirvish-preview-dired-sync-omit nil
        dirvish-preview-dispatchers
        '(video image gif audio epub archive font pdf)
        dirvish-peek-key '(:debounce 0.2 any)
        dirvish-quick-access-entries
        '(("h" "~/" "Home")
          ("d" "~/downloads/" "Downloads")
          ("k" "~/desktop/" "Desktop")
          ("b" "~/documents/" "Documents")
          ("i" "~/pictures/" "Pictures")
          ("v" "~/movies/" "Movies")
          ("m" "~/music/" "Music")
          ("g" "~/games/" "Games")
          ("s" "~/src/" "Source")
          ("n" "~/org/notes/markdown-vault/" "Notes")
          ("c" "/etc/nixos/" "NixOS")
          ("t" "/mnt/main/storage/" "Storage")
          ("x" "/mnt/main/scratch/" "Scratch"))
        dirvish-side-attributes
        '(vc-state subtree-state nerd-icons collapse)
        dirvish-side-mode-line-format
        '(:left (path) :right (index))
        dirvish-use-mode-line 'global)
  :config
  (dirvish-define-mode-line suderman-dashboard
    "Clickable Dashboard button."
    (suderman/dirvish-mode-line-button
     "nf-cod-dashboard" "D" "mouse-1: Open Dashboard"
     #'suderman/dashboard-from-mode-line))
  (dirvish-define-mode-line suderman-dirvish
    "Clickable Dirvish button."
    (suderman/dirvish-mode-line-button
     "nf-cod-folder" "D" "mouse-1: Toggle Dirvish"
     #'suderman/dirvish-from-mode-line))
  (dirvish-define-mode-line suderman-ibuffer
    "Clickable IBuffer button."
    (suderman/dirvish-mode-line-button
     "nf-cod-files" "B" "mouse-1: Toggle IBuffer"
     #'suderman/dirvish-ibuffer-from-mode-line))
  (dirvish-override-dired-mode 1)
  (require 'dirvish-yank)
  (require 'dirvish-rsync)
  (require 'dirvish-side)
  (require 'dirvish-peek)
  (require 'dirvish-subtree)
  (add-to-list 'dirvish-archive-exts "gz")
  (add-to-list 'dirvish-binary-exts "gz")
  (suderman/dirvish-enable-subtree-mouse)
  (dirvish-side-follow-mode 1)
  (dirvish-peek-mode 1)
  (add-hook 'dirvish-preview-setup-hook
            #'suderman/dirvish-preview-disable-line-numbers)
  (advice-remove 'dirvish--create-parent-buffer
                 #'suderman/dirvish-create-parent-buffer)
  (advice-add 'dirvish--create-parent-buffer :around
               #'suderman/dirvish-create-parent-buffer)
  (advice-remove 'dirvish--find-entry #'suderman/dirvish-find-entry-at-root)
  (advice-add 'dirvish--find-entry :around
              #'suderman/dirvish-find-entry-at-root)
  (advice-remove 'windmove-find-other-window
                 #'suderman/dirvish-ignore-misc-window)
  (advice-add 'windmove-find-other-window :around
              #'suderman/dirvish-ignore-misc-window)
  (advice-remove 'dirvish--run-with-delay
                 #'suderman/dirvish-render-after-narrow)
  (advice-add 'dirvish--run-with-delay :around
              #'suderman/dirvish-render-after-narrow)
  (add-hook 'dirvish-directory-view-mode-hook #'suderman/dired-setup)
  (dolist (map (list dired-mode-map dirvish-mode-map))
    (keymap-set map "`" #'suderman/dashboard)
    (keymap-set map "SPC" #'meow-keypad)
    (keymap-set map "," #'suderman/dirvish-ibuffer)
    (keymap-set map "." #'suderman/dirvish)
    (keymap-set map "?" #'suderman/dirvish-help)
    (keymap-set map "/" #'suderman/dirvish-search)
    (keymap-set map "'" #'dirvish-setup-menu)
    (keymap-set map ";" #'dirvish-dispatch)
    (keymap-set map "TAB" #'dirvish-subtree-toggle)
    (keymap-set map "<tab>" #'dirvish-subtree-toggle)
    (keymap-set map "E" #'dirvish-emerge-menu)
    (keymap-set map "H" #'dirvish-history-go-backward)
    (keymap-set map "I" #'dirvish-file-info-menu)
    (keymap-set map "L" #'dirvish-history-go-forward)
    (keymap-set map "M" #'suderman/dired-mark-all)
    (keymap-set map "N" #'dirvish-narrow)
    (keymap-set map "R" #'dirvish-rsync)
    (keymap-set map "S" #'suderman/dirvish-side-toggle)
    (keymap-set map "U" #'dired-unmark-all-marks)
    (keymap-set map "X" #'dired-do-flagged-delete)
    (keymap-set map "a" #'suderman/dired-create-item)
    (keymap-set map "c" #'suderman/dired-copy-files)
    (keymap-set map "f" #'dirvish-layout-toggle)
    (keymap-set map "h" #'dired-up-directory)
    (keymap-set map "<left>" #'dired-up-directory)
    (keymap-set map "g" #'revert-buffer)
    (keymap-set map "i" #'suderman/dirvish-toggle-dotfiles)
    (keymap-set map "j" #'dired-next-line)
    (keymap-set map "<down>" #'dired-next-line)
    (keymap-set map "k" #'dired-previous-line)
    (keymap-set map "<up>" #'dired-previous-line)
    (keymap-set map "l" #'suderman/dired-open)
    (keymap-set map "<right>" #'suderman/dired-open)
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
    (keymap-set map "M-w" #'suderman/delete-window-or-tab)
    (keymap-set map "<mouse-1>" #'mouse-set-point)
    (keymap-set map "<double-mouse-1>" #'suderman/dired-mouse-open)
    (keymap-set map "<mouse-3>" #'context-menu-open))
  (keymap-set dirvish-directory-view-mode-map
              "<mouse-1>" #'suderman/dirvish-parent-mouse-select)
  (keymap-set dirvish-directory-view-mode-map
              "<mouse-3>" #'context-menu-open)
  (keymap-set dirvish-directory-view-mode-map
              "h" #'suderman/dirvish-parent-up-directory)
  (keymap-set dirvish-directory-view-mode-map
              "<left>" #'suderman/dirvish-parent-up-directory)
  (keymap-set dirvish-directory-view-mode-map
              "j" #'suderman/dirvish-parent-next-directory)
  (keymap-set dirvish-directory-view-mode-map
              "<down>" #'suderman/dirvish-parent-next-directory)
  (keymap-set dirvish-directory-view-mode-map
              "k" #'suderman/dirvish-parent-previous-directory)
  (keymap-set dirvish-directory-view-mode-map
              "<up>" #'suderman/dirvish-parent-previous-directory)
  (keymap-set dirvish-directory-view-mode-map
              "l" #'suderman/dirvish-focus-root)
  (keymap-set dirvish-directory-view-mode-map
              "<right>" #'suderman/dirvish-focus-root)
  (dolist (map (list dirvish-directory-view-mode-map
                     dirvish-misc-mode-map
                     dirvish-special-preview-mode-map))
    (keymap-set map "`" #'suderman/dashboard)
    (keymap-set map "," #'suderman/dirvish-ibuffer)
    (dolist (key '("M-h" "M-j" "M-k" "M-l"))
      (keymap-set map key #'suderman/dirvish-focus-root)))
  (keymap-set dired-mode-map "q" #'quit-window)
  (require 'dirvish-widgets)
  (dirvish-define-preview gif (file ext)
    "Preview GIF images, looping while the preview remains visible."
    (when (equal ext "gif")
      (let ((gif (dirvish--find-file-temporarily file))
            (callback
             (lambda (recipe)
               (when-let* ((buffer (cdr recipe))
                           ((buffer-live-p buffer)))
                 (with-current-buffer buffer
                   (image-animate (get-char-property 1 'display)
                                  nil t 1))))))
        (run-with-idle-timer 1 nil callback gif)
        gif)))
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
