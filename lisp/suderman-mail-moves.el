;;; suderman-mail-moves.el --- Single-message Inbox folder moves -*- lexical-binding: t; -*-

;;; Commentary:
;; Move one account's Inbox copy, not whole threads or arbitrary tags.
;; Filesystem moves and reindexing share the NixOS account sync lock.

;;; Code:

(require 'subr-x)
(require 'seq)

(declare-function notmuch-tree-get-message-id "notmuch-tree" (&optional bare))
(declare-function notmuch-show-get-message-id "notmuch-show" (&optional bare))
(declare-function notmuch-config-get "notmuch-lib" (item))
(declare-function notmuch--process-lines "notmuch-lib" (&rest args))
(declare-function notmuch-refresh-this-buffer "notmuch-lib" ())

(defun suderman/mail-move-source (root source)
  "Validate SOURCE under mail ROOT and return (ACCOUNT FILE FLAGS).
Only native mbsync Maildirs are supported.  Expunge-marked files cannot move."
  (when (or (file-remote-p root) (file-remote-p source) (file-symlink-p source))
    (user-error "Mail moves require ordinary local files"))
  (setq root (file-name-as-directory (file-truename root))
        source (file-truename source))
  (let ((relative (file-relative-name source root)))
    (unless (and (file-regular-p source)
                 (string-match "\\`\\(suderman\\|nonfiction\\)/Inbox/\\(?:cur\\|new\\)/[^/]+\\'"
                               relative))
      (user-error "Only one configured account's Inbox file can move"))
    (let* ((account (match-string 1 relative))
           (name (file-name-nondirectory source))
           (flags (if (string-match ":2,\\([A-Za-z]*\\)\\'" name)
                      (match-string 1 name) "")))
      (when (string-match-p "T" flags)
        (user-error "An expunge-marked message cannot move"))
      (when (file-exists-p (expand-file-name (concat account "/Inbox/.isyncuidmap.db") root))
        (user-error "Alternative mbsync UID maps are not supported"))
      (list account source flags))))

(defun suderman/mail-file-digest (file &optional ignore-tuid)
  "Return a SHA-256 digest of local FILE.
With IGNORE-TUID, omit only mbsync's local X-TUID header, not body text."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (when ignore-tuid
      (goto-char (point-min))
      (when (re-search-forward "\r?\n\r?\n" nil t)
        (let ((end (copy-marker (match-end 0)))
              (case-fold-search t))
          (goto-char (point-min))
          (while (re-search-forward "^X-TUID:[^\r\n]*\r?\n" end t)
            (replace-match "" t t))
          (set-marker end nil))))
    (secure-hash 'sha256 (current-buffer))))

(defun suderman/mail-move-file (root source target &optional existing)
  "Move one Inbox SOURCE to TARGET, Archive or Trash, under mail ROOT.
Caller must hold the account's sync lock.  Return the destination file.
EXISTING may name an indexed destination copy.  Reuse it only when bytes and
flags and message bytes match, except the local X-TUID tracking header.
New filenames must not carry SOURCE's mailbox-specific mbsync ,U= UID."
  (unless (member target '("Archive" "Trash"))
    (user-error "Target must be Archive or Trash"))
  (pcase-let* ((`(,account ,source ,flags) (suderman/mail-move-source root source))
               (root (file-name-as-directory (file-truename root)))
               (folder (expand-file-name (concat account "/" target "/") root)))
    (when (or (not (file-in-directory-p folder root))
              (not (equal (file-name-as-directory (file-truename folder)) folder))
              (file-exists-p (expand-file-name ".isyncuidmap.db" folder)))
      (user-error "Destination must be a native Maildir inside this account"))
    (unless (equal (file-attribute-device-number (file-attributes source))
                   (file-attribute-device-number
                    (file-attributes (if (file-directory-p folder) folder
                                       (expand-file-name account root)))))
      (user-error "Source and destination must share a filesystem for atomic moves"))
    (if existing
        (progn
          (when (or (file-remote-p existing) (file-symlink-p existing))
            (user-error "Existing destination must be an ordinary local file"))
          (setq existing (file-truename existing))
          (unless (and (file-regular-p existing)
                       (member (file-name-directory existing)
                               (list (expand-file-name "cur/" folder)
                                     (expand-file-name "new/" folder)))
                       (string-suffix-p (concat ":2," flags) existing)
                       ;; Each mailbox pull assigns its own local tracking token.
                       (equal (suderman/mail-file-digest source t)
                              (suderman/mail-file-digest existing t)))
            (user-error "Existing destination differs; no Inbox file was removed"))
          ;; Gmail's All Mail often already has this exact indexed copy.
          (delete-file source)
          existing)
      (dolist (part '("cur" "new" "tmp"))
        (let ((directory (expand-file-name part folder)))
          (when (file-symlink-p directory)
            (user-error "Destination Maildir subdirectories cannot be symlinks"))
          (make-directory directory t)))
      (let ((destination
             (concat (make-temp-name (expand-file-name
                                     (format "cur/%s.%d." (format-time-string "%s")
                                             (emacs-pid)) folder))
                     ":2," flags)))
        ;; Atomic same-filesystem rename retains mode, bytes, and arrival time.
        ;; Never reuse a UID from the source mailbox or overwrite another file.
        (rename-file source destination nil)
        destination))))

(defun suderman/mail-move-local (root source target &optional existing)
  "Move and reindex one Inbox copy, serialized with the NixOS sync service.
Use the active NOTMUCH_CONFIG and database.  No IMAP sync runs here.
Return the destination path.  Index failure reports a completed filesystem move
rather than pretending it rolled back; run notmuch new before any retry."
  (let* ((account (car (suderman/mail-move-source root source)))
         (runtime (getenv "XDG_RUNTIME_DIR"))
         (library (locate-library "suderman-mail-moves")))
    (unless (and runtime (file-directory-p runtime) (not (file-remote-p runtime)))
      (user-error "A local XDG_RUNTIME_DIR is required for the sync lock"))
    (unless (and library (executable-find "flock") (executable-find "notmuch"))
      (user-error "Mail moves require this module, flock, and notmuch"))
    (with-temp-buffer
      (let ((status
             (call-process
              "flock" nil t nil "--nonblock" "--conflict-exit-code" "75"
              (expand-file-name (format "email-%s.lock" account) runtime)
              (expand-file-name invocation-name invocation-directory)
              "--batch" "-Q" "-l" library "--eval"
              (prin1-to-string
               `(condition-case failure
                    (let ((destination (suderman/mail-move-file ,root ,source ,target ,existing)))
                      (unless (zerop (call-process "notmuch" nil nil nil "new" "--quiet"))
                        (error "Moved to %s but indexing failed; run notmuch new before retrying"
                               destination))
                      (princ (prin1-to-string destination)))
                  (error (princ (error-message-string failure)) (kill-emacs 1)))))))
        (cond
         ((eq status 75) (user-error "Account sync is busy; refresh and retry"))
         ((not (eq status 0)) (error "Local mail move failed: %s" (string-trim (buffer-string))))
         (t (read (buffer-string))))))))

(defun suderman/mail-move-selected (target)
  "Confirm moving the selected message's Inbox copy to TARGET.
Only message rows and message views are supported, never thread-wide actions.
Choose an account when this message has Inbox copies in both accounts.
This is a local move; use G to sync it to the phone and g to refresh."
  (unless (member target '("Archive" "Trash"))
    (user-error "Target must be Archive or Trash"))
  ;; Tree refresh refuses while its query is still streaming.  Stop before moving.
  (when (and (eq major-mode 'notmuch-tree-mode) (get-buffer-process (current-buffer)))
    (user-error "Wait for the message list to finish loading"))
  (let ((query (pcase major-mode
                 ('notmuch-tree-mode (notmuch-tree-get-message-id))
                 ('notmuch-show-mode
                  (and (notmuch-show-get-message-id t)
                       (notmuch-show-get-message-id)))
                 (_ (user-error "Open a single-message row or message view first")))))
    (unless query (user-error "No message selected"))
    (let* ((root (file-name-as-directory (notmuch-config-get "database.mail_root")))
           (files (notmuch--process-lines "notmuch" "search" "--output=files" "--exclude=false" query))
           ;; Folder queries identify messages, not copies.  Filter every path.
           (sources (seq-filter
                     (lambda (file)
                       (string-match-p
                        "\\`\\(?:suderman\\|nonfiction\\)/Inbox/\\(?:cur\\|new\\)/[^/]+\\'"
                        (file-relative-name file root))) files))
           (accounts (delete-dups
                      (mapcar (lambda (file) (car (suderman/mail-move-source root file))) sources))))
      (unless sources (user-error "Selected message has no Inbox copy"))
      (let* ((account (if (= 1 (length accounts)) (car accounts)
                        (completing-read "Move which Inbox account: " accounts nil t)))
             (sources (seq-filter (lambda (file) (string-prefix-p
                                                 (expand-file-name (concat account "/Inbox/") root)
                                                 file)) sources))
             (existing (seq-filter (lambda (file) (string-prefix-p
                                                  (expand-file-name (concat account "/" target "/") root)
                                                  file)) files)))
        (unless (= 1 (length sources))
          (user-error "Multiple Inbox files in this account; no message moved"))
        (when (> (length existing) 1)
          (user-error "Multiple destination copies; no message moved"))
        (unless (yes-or-no-p (format "Move selected message from %s/Inbox to %s? " account target))
          (user-error "Mail move cancelled"))
        (let ((destination (suderman/mail-move-local root (car sources) target (car existing))))
          (notmuch-refresh-this-buffer)
          (message "Moved from %s/Inbox to %s locally; G syncs phone folders" account target)
          destination)))))

(defun suderman/mail-archive ()
  "Move the selected message's Inbox copy to its account's Archive folder."
  (interactive)
  (suderman/mail-move-selected "Archive"))

(defun suderman/mail-trash ()
  "Move the selected message's Inbox copy to Trash, not permanent deletion."
  (interactive)
  (suderman/mail-move-selected "Trash"))

(provide 'suderman-mail-moves)
;;; suderman-mail-moves.el ends here
