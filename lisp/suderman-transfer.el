;;; suderman-transfer.el --- Move files in and out of Dired -*- lexical-binding: t; -*-

;;; Commentary:
;; Staged copy, cut, and paste through Dirvish; clipboard and terminal paste of
;; files and images; Ripdrag drag-out; and Kitty transfers over SSH.  Commands
;; here are bound in `suderman/dirvish-keys'.

;;; Code:

(require 'dired)
(require 'dired-aux)
(require 'seq)
(require 'subr-x)

(defvar dirvish-yank-sources)
(declare-function xterm-paste "term/xterm")
(declare-function dirvish-move "dirvish-yank")
(declare-function dirvish-yank "dirvish-yank")

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

(provide 'suderman-transfer)
;;; suderman-transfer.el ends here
