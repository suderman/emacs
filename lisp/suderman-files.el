;;; suderman-files.el --- Dired and file utilities -*- lexical-binding: t; -*-

;;; Commentary:
;; Dired and Dirvish: layouts, the sidebar, previews, navigation, marks, and
;; their keys.  Copy, paste, and drag transfers live in `suderman-transfer'.

;;; Code:

(require 'dired)
(require 'dired-x)
(require 'dired-aux)
(require 'dnd)
;; Its use-package form is below, after code that needs it loaded.
(unless (package-installed-p 'dirvish)
  (package-refresh-contents)
  (package-install 'dirvish))
(require 'dirvish)
(require 'seq)
(require 'use-package)
(require 'suderman-appearance)
(require 'suderman-buffers)
(require 'suderman-windows)
(require 'suderman-transfer)

(defvar dirvish-quick-access-entries)
(defvar dirvish-archive-exts)
(defvar dirvish-binary-exts)
(defvar dirvish-preview-setup-hook)
(defvar dirvish-preview-dispatchers)
(defvar dirvish-peek-key)
(defvar dirvish-peek-candidate-fetcher)
(defvar consult--completion-refresh-hook)
(defvar vertico--index)
(defvar dirvish-path-separators)
(defvar dirvish-yank-sources)
(defvar dirvish-side-attributes)
(defvar dirvish-side-mode-line-format)
(defvar dirvish-subtree--state-icons)
(defvar global-hl-line-mode)
(defvar dirvish-directory-view-mode-map)
(defvar dirvish-misc-mode-map)
(defvar dirvish-mode-map)
(declare-function xterm-paste "term/xterm")
(declare-function suderman/dashboard "suderman-dashboard")
(declare-function dirvish--build-layout "dirvish")
(declare-function dirvish--create-parent-buffer "dirvish")
(declare-function dirvish--find-entry "dirvish")
(declare-function dirvish--find-file-temporarily "dirvish")
(declare-function dirvish--render-attrs "dirvish")
(declare-function dirvish--run-with-delay "dirvish")
(declare-function dirvish--preview-update "dirvish")
(declare-function vertico--candidate "vertico")
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
(declare-function pdf-loader-install "pdf-loader")
(declare-function android-browse-url "android-win")
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
  "Toggle Dirvish for PATH, selecting it when it is a file.
With no PATH, select a visible sidebar in this frame instead of opening Dirvish."
  (interactive)
  (let ((sidebar (and (null path) (dirvish-side--session-visible-p))))
    (cond
     ((and (fboundp 'dirvish-curr) (dirvish-curr))
      (dirvish-quit))
     (sidebar
      (suderman/dirvish-side-make-resizable sidebar)
      (select-window sidebar))
     (t
      (let* ((target (expand-file-name (or path buffer-file-name
                                           default-directory)))
             (directory (if (file-directory-p target)
                            target
                          (file-name-directory target))))
        (dirvish directory)
        (when-let* ((session
                     (seq-some
                      (lambda (window)
                        (with-current-buffer (window-buffer window)
                          (when-let* ((session (dirvish-curr)))
                            (and (eq (dv-type session) 'default) session))))
                      (window-list)))
                     ((dv-curr-layout session)))
          (with-selected-window (dv-root-window session)
            (dirvish-layout-toggle)))
        (unless (file-directory-p target)
          (dired-goto-file target)))))))

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

(defun suderman/dirvish-side-find-file (file find-function)
  "Open sidebar FILE in an existing editor before loading it.
Return non-nil when handling a normal FIND-FUNCTION file visit."
  (when-let* (((eq find-function 'find-file))
              ((not (file-directory-p file)))
              (session (dirvish-curr))
              ((eq (dv-type session) 'side)))
    ;; Loading in the sidebar lets layout refreshes restore its dedication.
    (select-window
     (or (get-mru-window (selected-frame) nil t t)
         (user-error "No editor window available")))
    (find-file file)
    t))

(defun suderman/dirvish-side-hide-truncation ()
  "Clip sidebar filenames without a terminal truncation indicator."
  (when-let* ((session (dirvish-curr))
              ((eq (dv-type session) 'side)))
    (let ((table (if buffer-display-table
                     (copy-sequence buffer-display-table)
                   (make-display-table))))
      ;; Hide terminal Emacs's $ marker so filenames clip like GUI sidebars.
      (set-display-table-slot table 'truncation ?\s)
      (setq-local buffer-display-table table))))

(defun suderman/dirvish-side-make-resizable (window)
  "Allow ordinary resizing of the Dirvish sidebar WINDOW."
  (with-current-buffer (window-buffer window)
    ;; Dirvish reapplies the session's fixed width when rebuilding its layout.
    (when-let* ((session (dirvish-curr)))
      (setf (dv-size-fixed session) nil))
    (setq-local window-size-fixed nil)))

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
        (when-let* ((sidebar (dirvish-side--session-visible-p)))
          (suderman/dirvish-side-make-resizable sidebar))
        (when (window-live-p editor)
          (select-window editor)))))))

(defvar suderman/dirvish-subtree-mouse-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'dirvish-subtree-toggle-or-open)
    map)
  "Mouse bindings used by Dirvish subtree state arrows.")

(defvar-keymap suderman/dirvish-keys
  :doc "Keys shared by Dired and Dirvish.  `?' shows them with their labels."
  "h" '("Parent directory" . dired-up-directory)
  "j" '("Next entry" . dired-next-line)
  "k" '("Previous entry" . dired-previous-line)
  "l" '("Open entry" . suderman/dired-open)
  "f" '("Toggle fullscreen" . dirvish-layout-toggle)
  "G" '("Open image gallery" . suderman/image-dired-gallery)
  "b" '("Drag files with Ripdrag" . suderman/dired-ripdrag)
  "TAB" '("Toggle subtree" . suderman/dirvish-toggle-subtree)
  "o" '("Toggle subtree" . suderman/dirvish-toggle-subtree)
  "M-o" '("Open in other window" . dired-find-file-other-window)
  "\\" '("Toggle file sidebar" . suderman/dirvish-side-toggle)
  "<" '("Previous buffer" . previous-buffer)
  ">" '("Next buffer" . next-buffer)
  "B" '("Byte-compile files" . dired-do-byte-compile)
  "C-c B" '("Byte-compile files" . dired-do-byte-compile)
  "H" '("History backward" . dirvish-history-go-backward)
  "L" '("History forward" . dirvish-history-go-forward)
  "N" '("Narrow entries" . dirvish-narrow)
  "E" '("Manage file groups" . dirvish-emerge-menu)
  "R" '("Rsync marked files" . dirvish-rsync)
  "m" '("Toggle mark" . suderman/dired-toggle-mark)
  "M" '("Mark all" . suderman/dired-mark-all)
  "t" '("Invert marks" . dired-toggle-marks)
  "u" '("Unmark" . suderman/dired-unmark)
  "U" '("Unmark all" . dired-unmark-all-marks)
  "c" '("Stage copy" . suderman/dired-copy-files)
  "x" '("Stage cut" . suderman/dired-cut-files)
  "v" '("Paste files or clipboard image" . suderman/dired-paste)
  "V" '("Receive files with Kitty" . suderman/dired-kitty-receive)
  "C" '("Copy immediately" . dired-do-copy)
  "D" '("Delete without confirmation" . suderman/dired-delete-without-confirmation)
  "d" '("Delete with confirmation" . dired-do-delete)
  "Z" '("Compress" . dired-do-compress)
  "a" '("Create file or directory" . suderman/dired-create-item)
  "r" '("Rename or move" . dired-do-rename)
  "g" '("Refresh" . revert-buffer)
  "I" '("File information" . dirvish-file-info-menu)
  "i" '("Toggle dotfiles" . suderman/dirvish-toggle-dotfiles)
  "s" '("Sort" . dirvish-quicksort)
  "z" '("Quick access" . dirvish-quick-access)
  "/" '("Search here" . suderman/dirvish-search)
  "'" '("Change view attributes" . dirvish-setup-menu)
  ";" '("Dirvish menu" . dirvish-dispatch)
  "," '("Open IBuffer" . suderman/dirvish-ibuffer)
  "." '("Toggle Dirvish" . suderman/dirvish)
  "`" '("Dashboard" . suderman/dashboard)
  "SPC" '("Meow keypad" . meow-keypad)
  "?" '("Show these bindings" . suderman/dirvish-help))

(defvar suderman/dirvish-help-map nil
  "Keymap displayed by `suderman/dirvish-help'.")

(defun suderman/dirvish-help ()
  "Show Dired, Dirvish, and window keys with Which-Key."
  (interactive)
  (require 'which-key)
  (setq suderman/dirvish-help-map
        (make-composed-keymap (list suderman/dirvish-keys suderman/window-keys)))
  (which-key-show-keymap 'suderman/dirvish-help-map))

(defun suderman/dirvish-toggle-subtree ()
  "Toggle the subtree at point only when the entry is a directory."
  (interactive)
  (when-let* ((entry (dired-get-filename nil t))
              ((file-directory-p entry)))
    (dirvish-subtree-toggle)))

(defun suderman/dirvish-search (pattern)
  "Search below the current directory for comma-separated PATTERNs."
  (interactive (list (read-string "Search current directory: ")))
  (dirvish-fd nil pattern))

(defun suderman/dired-open ()
  "Open the entry at point, delegating EPUB, audio, and video to the system."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (dired-find-file)
      (require 'mailcap)
      (let ((mime-type (mailcap-file-name-to-mime-type file)))
        (if (and mime-type
                 (or (equal mime-type "application/epub+zip")
                     (string-match-p "\\`\\(?:audio\\|video\\)/" mime-type)))
            (if (featurep 'android)
                (progn
                  (require 'browse-url)
                  (android-browse-url (browse-url-file-url file)))
              (unless (executable-find "xdg-open")
                (user-error "xdg-open is not installed"))
              (start-process "open-media" nil "xdg-open" file))
          (dired-find-file))))))

(defun suderman/dirvish-quick-access-entries ()
  "Return configured Dirvish destinations that exist on this device."
  (seq-filter
   (lambda (entry)
     (file-directory-p (expand-file-name (nth 1 entry))))
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
     ("x" "/mnt/main/scratch/" "Scratch"))))

(defun suderman/dired-mouse-open (event)
  "Open the Dired entry clicked in EVENT."
  (interactive "e")
  (mouse-set-point event)
  (suderman/dired-open))

(defun suderman/dired-mouse-secondary-open (event)
  "Open the Dired entry in place on Android, or in another window elsewhere."
  (interactive "e")
  (if (featurep 'android)
      (suderman/dired-mouse-open event)
    (dired-mouse-find-file-other-window event)))

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

(defun suderman/dirvish-peek-candidate ()
  "Return a selected Vertico file, not raw Consult search input."
  (when (and (boundp 'vertico--index) (>= vertico--index 0))
    (vertico--candidate)))

(defun suderman/dirvish-peek-consult-refresh ()
  "Preview Consult file results that arrive after the last keypress."
  (when-let* ((dv (dirvish-curr))
              ((eq (dv-type dv) 'peek))
              ((eq (dirvish-prop :peek-category) 'file))
              (fetcher (dirvish-prop :peek-fetcher))
              (candidate (funcall fetcher))
              (file (expand-file-name candidate)))
    (dirvish-prop :index file)
    (dirvish--preview-update dv file)))

(defun suderman/dirvish-preview-disable-line-numbers ()
  "Configure the current Dirvish preview."
  (add-hook 'display-line-numbers-mode-hook
            #'suderman/dired-disable-line-numbers nil t)
  ;; Preview buffers use real major-mode maps.  Do not change editor bindings.
  (use-local-map (if (current-local-map)
                     (copy-keymap (current-local-map))
                   (make-sparse-keymap)))
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

(defun suderman/dired-delete-without-confirmation ()
  "Delete marked files, or the current file, without confirmation.
Delete nonempty directories recursively.  Keep visiting buffers alive so
unsaved edits are not discarded or interrupted by buffer-killing prompts."
  (interactive)
  (let ((dired-deletion-confirmer (lambda (&rest _) t))
        (dired-no-confirm t)
        (dired-recursive-deletes 'always)
        (dired-clean-up-buffers-too nil))
    (dired-do-delete)))

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

(defun suderman/dired-archive ()
  "Move marked items, or the item at point, into sibling archive directories.
Skip archive.org files and archive directories.  Timestamp names on collisions."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "This command requires a Dired buffer"))
  (dired-create-files
   (lambda (from to _overwrite)
     (make-directory (file-name-directory to) t)
     ;; Never overwrite, even if another entry appears after choosing the name.
     (let ((dired-backup-overwrite nil))
       (dired-rename-file from to nil)))
   "Archive" (dired-get-marked-files)
   (lambda (file)
     (let* ((file (directory-file-name file))
            (name (file-name-nondirectory file)))
       (unless (or (member name '("." ".." "archive.org"))
                   (and (equal name "archive") (file-directory-p file)))
         (let ((destination (expand-file-name
                             name (expand-file-name "archive/"
                                                    (file-name-directory file)))))
           (when (or (file-exists-p destination) (file-symlink-p destination))
             (let* ((extension (unless (file-directory-p file)
                                 (file-name-extension name t)))
                    (base (concat (if extension
                                      (file-name-sans-extension destination)
                                    destination)
                                  "-" (format-time-string "%Y%m%d-%H%M%S")))
                    (number 1))
               (setq destination (concat base extension))
               (while (or (file-exists-p destination) (file-symlink-p destination))
                 (setq number (1+ number)
                       destination (concat base "-" (number-to-string number)
                                           extension)))))
           destination))))))

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

(advice-add 'dired-clean-up-after-deletion :around
            #'suderman/dired-clean-up-after-deletion)

(add-hook 'dired-mode-hook #'suderman/dired-setup)
(add-hook 'dired-mode-hook #'suderman/dired-hide-dotfiles t)
(keymap-set ibuffer-mode-map "." #'suderman/ibuffer-dirvish)
(keymap-unset ibuffer-mode-map "S" t)
(keymap-set ibuffer-mode-map "B" #'ibuffer-copy-buffername-as-kill)
(keymap-set ibuffer-mode-map "\\" #'suderman/ibuffer-dirvish-side)
(keymap-set ibuffer-mode-map "<" #'previous-buffer)
(keymap-set ibuffer-mode-map ">" #'next-buffer)
(keymap-set ibuffer-mode-map "l" #'suderman/ibuffer-open)
(keymap-unset ibuffer-mode-map "i" t)
(keymap-unset ibuffer-mode-map "H" t)
(keymap-set ibuffer-mode-map "SPC" #'meow-keypad)
(keymap-set dired-mode-map "`" #'suderman/dashboard)

(use-package pdf-loader
  :ensure nil
  :demand t
  :config
  (pdf-loader-install))

(use-package dirvish
  :demand t
  :init
  (setq dired-mouse-drag-files nil
        dired-listing-switches
        (if (featurep 'android) "-al" "-al --group-directories-first")
        dirvish-attributes
        (append '(vc-state suderman-vc-state subtree-state)
                (when (suderman/nerd-fonts-available-p) '(nerd-icons))
                '(collapse file-size))
        dirvish-default-layout '(1 0.125 0.5)
        dirvish-mode-line-format
        '(:left (sort vc-info symlink yank)
          :right (file-size file-modes index))
        dirvish-path-separators '("  ⌂" "  /" " ⋗ ")
        dirvish-preview-dired-sync-omit nil
        dirvish-preview-dispatchers
        '(video image gif audio epub archive font pdf)
        dirvish-peek-key '(:debounce 0.2 any)
        dirvish-peek-candidate-fetcher #'suderman/dirvish-peek-candidate
        dirvish-quick-access-entries (suderman/dirvish-quick-access-entries)
        dirvish-side-attributes
        (append '(suderman-vc-state subtree-state)
                (when (suderman/nerd-fonts-available-p) '(nerd-icons))
                '(collapse))
        dirvish-side-mode-line-format
        '(:left (path) :right (index))
        dirvish-use-mode-line 'global)
  :config
  (require 'dirvish-vc)
  (dirvish-define-attribute suderman-vc-state
    "Color changed filenames in Dirvish."
    :when (and (dirvish-prop :vc-backend)
               (not (dirvish-prop :remote)))
    (when-let* ((state (dirvish-attribute-cache f-name :vc-state))
                (face (alist-get state '((edited . warning)
                                         (added . success)
                                         (removed . error)
                                         (missing . error)
                                         (needs-merge . error)
                                         (conflict . error)
                                         (unlocked-changes . warning)
                                         (needs-update . warning)
                                         (unregistered . font-lock-constant-face)))))
      (let ((ov (make-overlay f-beg f-end)))
        (overlay-put ov 'face face)
        (overlay-put ov 'priority 1)
        `(ov . ,ov))))
  (dirvish-override-dired-mode 1)
  (require 'dirvish-yank)
  (require 'dirvish-rsync)
  (require 'dirvish-side)
  (add-hook 'dirvish-find-entry-hook #'suderman/dirvish-side-find-file)
  (add-hook 'dirvish-setup-hook #'suderman/dirvish-side-hide-truncation)
  (require 'dirvish-peek)
  (require 'dirvish-subtree)
  (add-to-list 'dirvish-archive-exts "gz")
  (add-to-list 'dirvish-binary-exts "gz")
  (suderman/dirvish-enable-subtree-mouse)
  (dolist (frame (frame-list))
    (with-selected-frame frame
      (when-let* ((sidebar (dirvish-side--session-visible-p)))
        (suderman/dirvish-side-make-resizable sidebar))))
  (dirvish-side-follow-mode 1)
  (dirvish-peek-mode 1)
  (with-eval-after-load 'consult
    ;; Consult refreshes async candidates without another minibuffer command.
    (add-hook 'consult--completion-refresh-hook
              #'suderman/dirvish-peek-consult-refresh 90))
  (add-hook 'dirvish-preview-setup-hook
            #'suderman/dirvish-preview-disable-line-numbers)
  (advice-add 'dirvish--create-parent-buffer :around
               #'suderman/dirvish-create-parent-buffer)
  (advice-add 'dirvish--find-entry :around
              #'suderman/dirvish-find-entry-at-root)
  (advice-add 'windmove-find-other-window :around
              #'suderman/dirvish-ignore-misc-window)
  (advice-add 'dirvish--run-with-delay :around
              #'suderman/dirvish-render-after-narrow)
  (add-hook 'dirvish-directory-view-mode-hook #'suderman/dired-setup)
  (dolist (map (list dired-mode-map dirvish-mode-map))
    (suderman/install-keys map suderman/dirvish-keys)
    (suderman/install-keys map suderman/window-keys)
    (keymap-unset map "S" t)
    (keymap-unset map "X" t)
    (keymap-set map "<tab>" #'suderman/dirvish-toggle-subtree)
    (keymap-set map "<left>" #'dired-up-directory)
    (keymap-set map "<down>" #'dired-next-line)
    (keymap-set map "<up>" #'dired-previous-line)
    (keymap-set map "<right>" #'suderman/dired-open)
    (keymap-set map "<xterm-paste>" #'suderman/dired-xterm-paste)
    (keymap-set map "<mouse-1>" #'mouse-set-point)
    (keymap-set map "<mouse-2>" #'suderman/dired-mouse-secondary-open)
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
    (keymap-set map "\\" #'suderman/dirvish-side-toggle)
    (keymap-set map "<" #'previous-buffer)
    (keymap-set map ">" #'next-buffer)
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

(defun suderman/kitty-graphics-probe-with-redraw (function &rest arguments)
  "Call FUNCTION with ARGUMENTS and repaint after a fresh terminal probe."
  (let ((frame (selected-frame))
        (cached (terminal-parameter nil 'kitty-graphics-text-sizing)))
    (unwind-protect
        (apply function arguments)
      ;; The probe erases a row and its scaled test space touches the next row.
      (unless cached
        (redraw-frame frame)))))

(use-package kitty-graphics
  :ensure nil
  :after dirvish
  :demand t
  :init
  (setq kitty-graphics-enable-video t
        kitty-graphics-dirvish-video-inline-preview t)
  :config
  (advice-add 'kitty-graphics--query-text-sizing-support :around
              #'suderman/kitty-graphics-probe-with-redraw)
  (kitty-graphics-setup))

(provide 'suderman-files)
;;; suderman-files.el ends here
