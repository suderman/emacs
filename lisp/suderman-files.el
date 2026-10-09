;;; suderman-files.el --- Dired and file utilities -*- lexical-binding: t; -*-

;;; Commentary:
;; Generic file commands and Dired/Dirvish navigation live here.

;;; Code:

(require 'dired)
(require 'dired-x)
(require 'dired-aux)
(require 'dnd)
(require 'dirvish)
(require 'seq)
(require 'use-package)
(require 'suderman-appearance)
(require 'suderman-buffers)
(require 'suderman-windows)

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

(defconst suderman/dirvish-help-keys
  '(("h" . "Parent directory")
    ("j" . "Next entry")
    ("k" . "Previous entry")
    ("l" . "Open entry")
    ("f" . "Toggle fullscreen")
    ("G" . "Open image gallery")
    ("b" . "Drag files with Ripdrag")
    ("TAB" . "Toggle subtree")
    ("o" . "Toggle subtree")
    ("M-o" . "Open in other window")
    ("\\" . "Toggle file sidebar")
    ("<" . "Previous buffer")
    (">" . "Next buffer")
    ("C-c B" . "Byte-compile files")
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
    ("v" . "Paste files or clipboard image")
    ("V" . "Receive files with Kitty")
    ("C" . "Copy immediately")
    ("D" . "Delete without confirmation")
    ("d" . "Delete with confirmation")
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

(defun suderman/dired-ripdrag ()
  "Drag marked files or the current entry with Ripdrag, when installed."
  (interactive)
  (when-let* ((program (executable-find "ripdrag")))
    (make-process
     :name "ripdrag"
     :command (append (list program "--and-exit" "--no-click" "--all"
                            "--basename" "--icon-size" "96" "--resizable")
                      (dired-get-marked-files))
     :noquery t)))

(defun suderman/dired--kitty-command (arguments finish &optional stderr)
  "Hand this terminal to kitten with ARGUMENTS in the displayed directory.
Call FINISH with the process and original buffer after restoring the tty.
When STDERR is supplied, capture kitten's diagnostics in that file."
  (unless (derived-mode-p 'dired-mode)
    (user-error "Open Dired or Dirvish first"))
  (when (display-graphic-p)
    (user-error "Kitty receive needs a terminal frame; GUI drops work directly"))
  (unless (equal (tty-type) "xterm-kitty")
    (user-error "Kitty receive needs a Kitty terminal frame"))
  (let* ((default-directory (dired-current-directory))
         (frame (selected-frame))
         (terminal (frame-terminal frame))
         (tty (terminal-name terminal))
         (buffer (current-buffer))
         process
         (close-frame
          (lambda (deleted-frame)
            (when (and (eq deleted-frame frame) process (process-live-p process))
              (signal-process (process-id process) 'SIGTERM))))
         (process-environment (copy-sequence process-environment)))
    (when (file-remote-p default-directory)
      (user-error "Kitty receive needs a local directory on the Emacs host"))
    ;; Standalone Emacs names its tty /dev/tty, which detached children cannot open.
    (when (equal tty "/dev/tty")
      (setq tty (file-truename "/proc/self/fd/0")))
    (setq tty (shell-quote-argument tty))
    (let* ((kitten (or (executable-find "kitten")
                       (user-error "kitten is not installed on the Emacs host")))
           (script (or (executable-find "script")
                       (user-error "util-linux script is not installed on the Emacs host")))
           (command (concat (mapconcat #'shell-quote-argument
                                       (cons kitten arguments) " ")
                            (when stderr
                              (concat " 2> " (shell-quote-argument stderr))))))
      (setenv "TERM" (tty-type terminal))
      (setenv "SHELL" shell-file-name)
      ;; Keep emacsclient running while this frame releases its tty.
      (let ((suspend-tty-functions
             (remq 'server-handle-suspend-tty suspend-tty-functions)))
        (suspend-tty terminal))
      (condition-case err
          (progn
            (setq process
                  (make-process
                   :name "kitten-dnd" :buffer nil :connection-type 'pipe :noquery t
                   ;; script supplies /dev/tty and passes Kitty's protocols unchanged.
                   :command (list shell-file-name "-c"
                                  (format "exec %s -q -e -c %s /dev/null < %s > %s 2>&1"
                                          (shell-quote-argument script)
                                          (shell-quote-argument command) tty tty))
                   :sentinel
                   (lambda (process _event)
                     (unless (process-live-p process)
                       (remove-hook 'delete-frame-functions close-frame)
                       (when (terminal-live-p terminal) (resume-tty terminal))
                       (when (frame-live-p frame) (redraw-frame frame))
                       (funcall finish process buffer)))))
            (add-hook 'delete-frame-functions close-frame)
            process)
        ((error quit)
         (remove-hook 'delete-frame-functions close-frame)
         (resume-tty terminal)
         (signal (car err) (cdr err)))))))

(defun suderman/dired-kitty-receive ()
  "Receive a Kitty file drop in the displayed directory, including over SSH.
Hand this terminal to kitten dnd until a drop finishes or Escape is pressed.
Requires kitten with dnd support and util-linux script on the Emacs host."
  (interactive)
  (suderman/dired--kitty-command
   '("dnd" "--drop-anywhere" "copy" "--copy-mode" "independent"
     "--confirm-drop-overwrite" "--exit-on" "drop-finish,esc-key")
   (lambda (process buffer)
     (when (buffer-live-p buffer)
       (with-current-buffer buffer
         (when (derived-mode-p 'dired-mode)
           (suderman/dired--refresh-import))))
     (unless (zerop (process-exit-status process))
       (message "Kitty receive exited with status %s; check kitten dnd and util-linux script"
                (process-exit-status process))))))

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
            (if (eq system-type 'android)
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
  (if (eq system-type 'android)
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

(defun suderman/dired--local-paths (paths)
  "Return quoted PATHS only when every entry is an existing absolute local path."
  ;; Quote names before probing so literal colons never invoke a file handler.
  (when (and paths
             (seq-every-p (lambda (path)
                            (and (stringp path)
                                 (file-name-absolute-p path)
                                 (not (string-search "\0" path))
                                 (file-exists-p (file-name-quote path))))
                          paths))
    (mapcar #'file-name-quote paths)))

(defun suderman/dired--paste-paths (text)
  "Recognize newline-separated paths in TEXT without shell parsing or trimming."
  (when (stringp text)
    (let ((lines (split-string text "\n")))
      (when (equal (car (last lines)) "")
        (setq lines (butlast lines)))
      (suderman/dired--local-paths lines))))

(defun suderman/dired--refresh-import (&optional file)
  "Refresh the directory listing and select imported FILE when supplied."
  (revert-buffer nil t)
  (when file (dired-goto-file file)))

(defun suderman/dired--copy-file (from to overwrite)
  "Copy FROM to TO using Dired, respecting declined OVERWRITE requests."
  (when (or (file-equal-p from to)
            (and (file-directory-p from)
                 (file-in-directory-p (file-name-directory to) from)))
    (signal 'file-error (list "Cannot copy into itself" from to)))
  ;; Dired's recursive copy ignores OK-FLAG for directories.  Guard it here.
  (when (and (or (file-exists-p to) (file-symlink-p to)) (not overwrite))
    (signal 'file-already-exists (list "Not overwriting" to)))
  (dired-copy-file from
                   (if (and (file-directory-p from) (file-directory-p to))
                       (file-name-directory to)
                     to)
                   overwrite))

(defun suderman/dired-import-files (files)
  "Copy FILES into the displayed directory with Dired collision/error handling."
  (let ((directory (file-name-as-directory (dired-current-directory))))
    (unwind-protect
        (dired-create-files
         #'suderman/dired--copy-file "Copy" files
         (lambda (from)
           (expand-file-name (file-name-nondirectory (directory-file-name from))
                             directory))
         dired-keep-marker-copy)
      (suderman/dired--refresh-import))))

(defun suderman/dired-xterm-paste (event)
  "Import an all-path terminal paste EVENT, otherwise use normal terminal paste."
  (interactive "e")
  (if-let* ((files (and (derived-mode-p 'dired-mode)
                       (suderman/dired--paste-paths (nth 1 event)))))
      (suderman/dired-import-files files)
    (xterm-paste event)))

(defconst suderman/dired--image-extensions
  '((image/png . "png") (image/jpeg . "jpg") (image/gif . "gif")
    (image/webp . "webp") (image/tiff . "tiff") (image/bmp . "bmp")
    (image/svg+xml . "svg"))
  "Clipboard image formats that can be saved without conversion.")

(defun suderman/dired--wl-paste (program &rest arguments)
  "Read clipboard bytes from PROGRAM with ARGUMENTS, or nil if unavailable."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((default-directory "/")
          (coding-system-for-read 'binary))
      (when (eq 0 (apply #'call-process program nil '(t nil) nil arguments))
        (buffer-string)))))

(defun suderman/dired--clipboard-reader ()
  "Return (TYPES . READER) for native selection or optional local wl-paste."
  (let ((types (ignore-errors (gui-get-selection 'CLIPBOARD 'TARGETS))))
    (if (seq-some (lambda (type)
                    (and (symbolp type) (string-search "/" (symbol-name type))))
                  types)
        (cons (append types nil)
              (lambda (type) (gui-get-selection 'CLIPBOARD type)))
      (let ((default-directory "/"))
        (when-let* (((getenv "WAYLAND_DISPLAY" (selected-frame)))
                    ((not (getenv "SSH_CONNECTION" (selected-frame))))
                    ((not (getenv "SSH_TTY" (selected-frame))))
                    (program (executable-find "wl-paste"))
                    (offered (suderman/dired--wl-paste program "--list-types")))
          (cons (mapcar #'intern (split-string offered "[\r\n]+" t))
                (lambda (type)
                  (or (suderman/dired--wl-paste
                       program "--type" (symbol-name type) "--no-newline")
                      (user-error "Could not read clipboard type %s" type)))))))))

(defun suderman/dired--clipboard-files (type data)
  "Decode local clipboard file DATA of MIME TYPE, rejecting mixed invalid lists."
  (when (stringp data)
    (let* ((text (if (multibyte-string-p data) data
                   (decode-coding-string data 'utf-8)))
           (lines (split-string text "\r?\n" t)))
      (when (memq type '(x-special/gnome-copied-files x-special/mate-copied-files))
        (setq lines (and (member (car lines) '("copy" "cut")) (cdr lines))))
      (setq lines (seq-remove (lambda (line) (string-prefix-p "#" line)) lines))
      (suderman/dired--local-paths
       (mapcar (lambda (uri)
                 (let ((local (or (dnd-get-local-file-uri uri) uri)))
                   (when (or (string-prefix-p "file:///" local)
                             (and (string-prefix-p "file:/" local)
                                  (not (string-prefix-p "file://" local))))
                     (dnd-get-local-file-name local))))
               lines)))))

(defun suderman/dired--write-image (type data)
  "Save clipboard image DATA of TYPE with a timestamp and exclusive creation."
  (unless (and (stringp data) (> (length data) 0))
    (user-error "Clipboard returned no %s image data" type))
  (let ((directory default-directory)
        (timestamp (format-time-string "%Y-%m-%d-%H%M%S"))
        (extension (alist-get type suderman/dired--image-extensions))
        (attempt 1)
        file)
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert (if (multibyte-string-p data) (encode-coding-string data 'utf-8) data))
      (let ((coding-system-for-write 'binary))
        (while (not file)
          (let ((candidate
                 (expand-file-name
                  (format "clipboard-%s%s.%s" timestamp
                          (if (= attempt 1) "" (format "-%d" attempt)) extension)
                  directory)))
            (condition-case nil
                (progn
                  (write-region nil nil candidate nil 'silent nil 'excl)
                  (setq file candidate))
              (file-already-exists (setq attempt (1+ attempt))))))))
    (suderman/dired--refresh-import file)
    (message "Saved clipboard image to %s" file)))

(defvar suderman/dired-transfer nil
  "Staged file operation as (METHOD . FILES).")

(declare-function xterm--read-string "term/xterm" (term1 &optional term2))

(defun suderman/dired--kitty-clipboard-types (finish)
  "Query Kitty's clipboard formats without releasing the terminal.
Call FINISH with the MIME types after the asynchronous reply completes."
  (let* ((terminal (frame-terminal))
         (map input-decode-map)
         (key "\e]5522;")
         (previous (lookup-key map key))
         timer types
         (cleanup
          (lambda ()
            (define-key map key previous)
            (when timer (cancel-timer timer))
            (when (terminal-live-p terminal)
              (set-terminal-parameter terminal 'suderman/kitty-clipboard-query nil)))))
    (when (terminal-parameter terminal 'suderman/kitty-clipboard-query)
      (user-error "A Kitty clipboard query is already running"))
    (define-key map key
      (lambda (&optional _prompt)
        (condition-case err
            (let* ((packet (xterm--read-string ?\e ?\\))
                   (status (and (string-match "status=\\([^:;]+\\)" packet)
                                (match-string 1 packet))))
              (pcase status
                ("OK")
                ("DATA"
                 (setq types
                       (append types (split-string
                                      (base64-decode-string
                                       (substring packet (1+ (string-search ";" packet))))))))
                ("DONE"
                 (funcall cleanup)
                 ;; Leave input decoding before a possible terminal handoff.
                 (run-at-time 0 nil finish types))
                (_ (funcall cleanup)
                   (message "Kitty clipboard format query failed: %s" status))))
          (error (funcall cleanup)
                 (message "Kitty clipboard format query failed: %s"
                          (error-message-string err))))
        []))
    (setq timer (run-at-time 5 nil
                             (lambda ()
                               (funcall cleanup)
                               (message "Kitty clipboard format query timed out"))))
    (set-terminal-parameter terminal 'suderman/kitty-clipboard-query timer)
    (condition-case err
        ;; Listing formats requires no permission prompt and transfers no clipboard data.
        (send-string-to-terminal "\e]5522;type=read;Lg==\e\\" terminal)
      ((error quit) (funcall cleanup) (signal (car err) (cdr err))))
    t))

(defun suderman/dired--kitty-paste ()
  "Read a PNG through Kitty only when its clipboard advertises image/png."
  (when (and (not (display-graphic-p)) (equal (tty-type) "xterm-kitty")
             (not (file-remote-p (dired-current-directory)))
             (executable-find "kitten") (executable-find "script"))
    (let ((frame (selected-frame)) (buffer (current-buffer)))
      (suderman/dired--kitty-clipboard-types
       (lambda (types)
         (when (and (frame-live-p frame) (buffer-live-p buffer))
           (with-selected-frame frame
             (with-current-buffer buffer
               (when (derived-mode-p 'dired-mode)
                 (if (member "image/png" types)
                     (suderman/dired--kitty-paste-image)
                   (message "Clipboard does not contain files or supported image data")))))))))))

(defun suderman/dired--kitty-paste-image ()
  "Read an advertised PNG through Kitty's permission-checked helper."
  (let* ((directory (dired-current-directory))
         (frame (selected-frame))
         (temporary (make-temp-file "emacs-kitty-clipboard-" t))
         (image (expand-file-name "image.png" temporary))
         (stderr (expand-file-name "error.log" temporary)))
    (condition-case err
        (suderman/dired--kitty-command
         (list "clipboard" "-g" "--mime" "image/png" image)
         (lambda (process buffer)
           (unwind-protect
               (when (and (frame-live-p frame) (buffer-live-p buffer))
                 (with-current-buffer buffer
                   (when (derived-mode-p 'dired-mode)
                     (let ((default-directory directory)
                           (diagnostic (with-temp-buffer
                                         (when (file-exists-p stderr)
                                           (insert-file-contents stderr))
                                         (string-trim (buffer-string)))))
                       (cond
                        ((and (zerop (process-exit-status process))
                              (file-exists-p image))
                         (suderman/dired--write-image
                          'image/png (with-temp-buffer
                                       (set-buffer-multibyte nil)
                                       (insert-file-contents-literally image)
                                       (buffer-string))))
                        ;; The clipboard can change after the format query.
                        ((string-match-p
                          "not available on the clipboard\\|The clipboard is empty\\|No data for .* with MIME type: image/png"
                          diagnostic)
                         (message "Clipboard does not contain files or supported image data"))
                        (t (message "Kitty clipboard read failed: %s"
                                    (if (string-empty-p diagnostic)
                                        (format "status %s" (process-exit-status process))
                                      diagnostic))))))))
             (delete-directory temporary t)))
         stderr)
      ((error quit)
       (delete-directory temporary t)
       (signal (car err) (cdr err))))))

(defun suderman/dired-paste (&optional clipboard-only)
  "Paste staged files first, otherwise import clipboard files or images.
With prefix argument CLIPBOARD-ONLY, skip the staged transfer."
  (interactive "P")
  (unless (derived-mode-p 'dired-mode)
    (user-error "This command requires a Dired buffer"))
  (if (and suderman/dired-transfer (not clipboard-only))
      (suderman/dired-paste-files)
    (pcase-let* ((`(,types . ,reader) (suderman/dired--clipboard-reader))
                 (files
                  (seq-some
                   (lambda (type)
                     (when (memq type types)
                       (suderman/dired--clipboard-files type (funcall reader type))))
                   '(text/uri-list x-special/gnome-copied-files
                                   x-special/mate-copied-files)))
                 (image-type (seq-find (lambda (type) (memq type types))
                                       (mapcar #'car suderman/dired--image-extensions))))
      (cond
       (files (suderman/dired-import-files files))
       (image-type (suderman/dired--write-image image-type (funcall reader image-type)))
       ((setq files
              (let* ((data (or (and reader
                                    (seq-some
                                     (lambda (type)
                                       (and (memq type types) (funcall reader type)))
                                     '(text/plain\;charset=utf-8 text/plain)))
                               (ignore-errors (gui-get-selection 'CLIPBOARD 'UTF8_STRING))
                               (ignore-errors (gui-get-selection 'CLIPBOARD 'STRING))))
                     (text (and (stringp data)
                                (if (multibyte-string-p data) data
                                  (decode-coding-string data 'utf-8)))))
                (or (suderman/dired--clipboard-files 'text/uri-list text)
                    (suderman/dired--paste-paths text))))
        (suderman/dired-import-files files))
       ((suderman/dired--kitty-paste))
       (t (message "Clipboard does not contain files or supported image data"))))))

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
  "Copy or move staged files here, consuming the stage once transfer starts."
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
     (setq suderman/dired-transfer nil))
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
  :if (not (eq system-type 'android))
  :demand t
  :config
  (pdf-loader-install))

(use-package dirvish
  :demand t
  :init
  (setq dired-mouse-drag-files nil
        dired-listing-switches
        (if (eq system-type 'android) "-al" "-al --group-directories-first")
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
    (keymap-set map "TAB" #'suderman/dirvish-toggle-subtree)
    (keymap-set map "<tab>" #'suderman/dirvish-toggle-subtree)
    (keymap-set map "o" #'suderman/dirvish-toggle-subtree)
    (keymap-set map "M-o" #'dired-find-file-other-window)
    (keymap-set map "E" #'dirvish-emerge-menu)
    (keymap-set map "H" #'dirvish-history-go-backward)
    (keymap-set map "I" #'dirvish-file-info-menu)
    (keymap-set map "L" #'dirvish-history-go-forward)
    (keymap-set map "M" #'suderman/dired-mark-all)
    (keymap-set map "N" #'dirvish-narrow)
    (keymap-set map "R" #'dirvish-rsync)
    (keymap-unset map "S" t)
    (keymap-set map "B" #'dired-do-byte-compile)
    (keymap-set map "b" #'suderman/dired-ripdrag)
    (keymap-set map "\\" #'suderman/dirvish-side-toggle)
    (keymap-set map "<" #'previous-buffer)
    (keymap-set map ">" #'next-buffer)
    (keymap-set map "C-c B" #'dired-do-byte-compile)
    (keymap-set map "U" #'dired-unmark-all-marks)
    (keymap-unset map "X" t)
    (keymap-set map "d" #'dired-do-delete)
    (keymap-set map "D" #'suderman/dired-delete-without-confirmation)
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
    (keymap-set map "v" #'suderman/dired-paste)
    (keymap-set map "V" #'suderman/dired-kitty-receive)
    (keymap-set map "<xterm-paste>" #'suderman/dired-xterm-paste)
    (keymap-set map "x" #'suderman/dired-cut-files)
    (keymap-set map "z" #'dirvish-quick-access)
    (keymap-set map "M-h" #'edger-left)
    (keymap-set map "M-j" #'edger-down)
    (keymap-set map "M-k" #'edger-up)
    (keymap-set map "M-l" #'edger-right)
    (keymap-set map "M-H" #'edger-resize-left)
    (keymap-set map "M-J" #'edger-resize-down)
    (keymap-set map "M-K" #'edger-resize-up)
    (keymap-set map "M-L" #'edger-resize-right)
    (keymap-set map "M-u" #'edger-horizontal)
    (keymap-set map "M-i" #'edger-vertical)
    (keymap-set map "M-w" #'edger-close)
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
  :if (not (eq system-type 'android))
  :after dirvish
  :demand t
  :init
  (setq kitty-graphics-enable-video t
        kitty-graphics-dirvish-video-inline-preview t)
  :config
  (advice-remove 'kitty-graphics--query-text-sizing-support
                 #'suderman/kitty-graphics-probe-with-redraw)
  (advice-add 'kitty-graphics--query-text-sizing-support :around
              #'suderman/kitty-graphics-probe-with-redraw)
  (kitty-graphics-setup))

(provide 'suderman-files)
;;; suderman-files.el ends here
