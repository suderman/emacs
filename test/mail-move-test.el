;;; mail-move-test.el --- Private Maildir and mbsync round trips -*- lexical-binding: t; -*-

;;; Commentary:
;; Both mbsync sides are temporary Maildirs.  No providers, credentials, or SMTP.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'suderman-mail-moves)

(ert-deftest suderman/mail-move-preserves-bytes-flags-time-and-rejects-unsafe-paths ()
  (let* ((root (make-temp-file "mail-move-" t))
         (inbox (expand-file-name "suderman/Inbox/cur/" root))
         (source (expand-file-name "message,U=7:2,FS" inbox)))
    (unwind-protect
        (progn
          (make-directory inbox t)
          (with-temp-file source (insert "Message bytes.\n"))
          (set-file-modes source #o600)
          (set-file-times source (seconds-to-time 1000000000))
          (should-error (suderman/mail-move-file root source "Sent") :type 'user-error)
          (let ((target (suderman/mail-move-file root source "Archive")))
            (should-not (file-exists-p source))
            (should (string-suffix-p ":2,FS" target))
            (should-not (string-match-p ",U=" target))
            (should (= #o600 (file-modes target)))
            (should (= 1000000000 (float-time (file-attribute-modification-time (file-attributes target)))))
            (with-temp-buffer
              (insert-file-contents target)
              (should (equal "Message bytes.\n" (buffer-string))))
            (should-error (suderman/mail-move-file root target "Trash") :type 'user-error)
            (copy-file target source)
            (let ((other (expand-file-name "different:2,FS" (file-name-directory target))))
              (with-temp-file other (insert "Different bytes.\n"))
              (should-error (suderman/mail-move-file root source "Archive" other) :type 'user-error)
              (should (file-exists-p source)))
            (let ((link (expand-file-name "link:2,FS" inbox)))
              (make-symbolic-link source link)
              (should-error (suderman/mail-move-file root link "Trash") :type 'user-error))
            (let ((trashed (expand-file-name "marked:2,T" inbox)))
              (copy-file source trashed)
              (should-error (suderman/mail-move-file root trashed "Trash") :type 'user-error))
            (make-symbolic-link (expand-file-name "suderman/Archive" root)
                               (expand-file-name "suderman/Trash" root))
            (should-error (suderman/mail-move-file root source "Trash") :type 'user-error)
            (delete-file (expand-file-name "suderman/Trash" root))
            (with-temp-file (expand-file-name "suderman/Inbox/.isyncuidmap.db" root))
            (should-error (suderman/mail-move-file root source "Trash") :type 'user-error)
            (delete-file (expand-file-name "suderman/Inbox/.isyncuidmap.db" root))
            (should (equal target (suderman/mail-move-file root source "Archive" target)))
            (should-not (file-exists-p source))
            (should (file-exists-p target))))
      (delete-directory root t))))

(ert-deftest suderman/mail-move-reuses-local-tuid-differences-but-not-message-differences ()
  (let* ((root (make-temp-file "mail-move-tuid-" t))
         (source (expand-file-name "nonfiction/Inbox/cur/message,U=7:2,S" root))
         (existing (expand-file-name "nonfiction/Archive/cur/message,U=9:2,S" root))
         (headers "From: sender@example.invalid\nMessage-ID: <same@example.invalid>\n")
         (body "\nPreserved body.\nX-TUID: body text, not a header\n"))
    (unwind-protect
        (progn
          (make-directory (file-name-directory source) t)
          (make-directory (file-name-directory existing) t)
          (with-temp-file source (insert headers "X-TUID: InboxToken\n" body))
          (with-temp-file existing (insert headers "X-TUID: ArchiveToken\n" body))
          (let ((digest (suderman/mail-file-digest existing)))
            (should-not (equal digest (suderman/mail-file-digest source)))
            (should (equal existing (suderman/mail-move-file root source "Archive" existing)))
            (should-not (file-exists-p source))
            (should (equal digest (suderman/mail-file-digest existing))))
          (with-temp-file source
            (insert headers "X-TUID: InboxToken\n\nPreserved body.\nX-TUID: changed body\n"))
          (should-error (suderman/mail-move-file root source "Archive" existing) :type 'user-error)
          (should (file-exists-p source))
          (with-temp-file source (insert headers "Subject: Changed\nX-TUID: InboxToken\n" body))
          (should-error (suderman/mail-move-file root source "Archive" existing) :type 'user-error)
          (should (file-exists-p source)))
      (delete-directory root t))))

(ert-deftest suderman/mail-move-syncs-both-accounts-without-carrying-uids ()
  (skip-unless (cl-every #'executable-find '("notmuch" "mbsync" "flock")))
  (let* ((root (make-temp-file "mail-move-sync-" t))
         (mail (expand-file-name "near" root))
         (far (expand-file-name "far" root))
         (runtime (expand-file-name "runtime" root))
         (config (expand-file-name "notmuch-config" root))
         (sync-config (expand-file-name "mbsync-config" root))
         (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (make-directory runtime)
          (setenv "XDG_RUNTIME_DIR" runtime)
          (setenv "NOTMUCH_CONFIG" config)
          (setenv "NOTMUCH_DATABASE" nil)
          (setenv "NOTMUCH_PROFILE" nil)
          (with-temp-file config
            (insert "[database]\npath=" mail
                    "\n[user]\nname=Test\nprimary_email=test@example.invalid\n"
                    "[new]\ntags=unread\nignore=.uidvalidity;.mbsyncstate\n"
                    "[search]\nexclude_tags=deleted;spam\n[maildir]\nsynchronize_flags=true\n"))
          (with-temp-file sync-config
            (insert "Sync All\nCreate Near\nExpunge Both\nCopyArrivalDate yes\nSyncState *\n\n")
            (dolist (account '("suderman" "nonfiction"))
              (dolist (side '("near" "far"))
                (let ((path (expand-file-name (concat side "/" account "/") root)))
                  (make-directory path t)
                  (insert "MaildirStore " side "-" account "\nPath " path
                          "\nInbox " path "Inbox\nSubFolders Verbatim\n\n")))
              (dolist (folder '("Inbox" "Archive" "Trash"))
                (insert "Channel " account "-" folder "\nFar :far-" account ":" folder
                        "\nNear :near-" account ":" folder "\n\n"))
              (insert "Group " account "\nChannel " account "-Inbox\nChannel " account
                      "-Archive\nChannel " account "-Trash\n\n")))
          (cl-labels
              ((fixture (account folder name id flags)
                 (let ((dir (expand-file-name (concat account "/" folder "/") far)))
                   (dolist (part '("cur" "new" "tmp")) (make-directory (concat dir part) t))
                   (with-temp-file (concat dir "cur/" name ":2," flags)
                     (insert "From: sender@example.invalid\nTo: test@example.invalid\n"
                             "Subject: Offline folder move\nMessage-ID: <" id ">\n\n"
                             "Synthetic content for " id "\n"))))
               (sync (account)
                 (with-temp-buffer
                   (let ((status (call-process "mbsync" nil t nil "-c" sync-config account)))
                     (unless (eq status 0) (ert-fail (buffer-string))))))
               (files (account folder id)
                 (with-temp-buffer
                   (should (= 0 (call-process "notmuch" nil t nil "search" "--output=files" "--exclude=false"
                                             (format "id:%s and folder:%s/%s" id account folder))))
                   ;; Folder queries match message IDs, not individual filenames.
                   ;; Notmuch returns every account's copy of a matching ID.
                   (cl-remove-if-not
                    (lambda (file) (string-prefix-p
                                    (expand-file-name (concat account "/" folder "/") mail) file))
                    (split-string (buffer-string) "\n" t))))
               (far-files (account folder id)
                 (cl-remove-if-not
                  (lambda (file)
                    (with-temp-buffer (insert-file-contents file) (search-forward id nil t)))
                  (append (directory-files (expand-file-name (concat account "/" folder "/cur") far) t "^[^.]")
                          (directory-files (expand-file-name (concat account "/" folder "/new") far) t "^[^.]")))))
            (dolist (account '("suderman" "nonfiction"))
              ;; Existing UID 1 in Archive catches accidental reuse of Inbox UID 1.
              (fixture account "Archive" "filler" "filler@example.invalid" "S")
              (fixture account "Trash" "filler" "trash-filler@example.invalid" "S")
              (fixture account "Inbox" "1-archive" "archive@example.invalid" "FS")
              (fixture account "Inbox" "2-trash" "trash@example.invalid" "F")
              (fixture account "Inbox" "3-duplicate" "duplicate@example.invalid" "FS")
              (fixture account "Archive" "duplicate" "duplicate@example.invalid" "FS")
              (sync account))
            (should (= 0 (call-process "notmuch" nil nil nil "new" "--quiet")))
            (dolist (account '("suderman" "nonfiction"))
              (dolist (pair '(("archive@example.invalid" . "Archive")
                              ("trash@example.invalid" . "Trash")
                              ("duplicate@example.invalid" . "Archive")))
                (let* ((id (car pair)) (target (cdr pair))
                       (source (car (files account "Inbox" id)))
                       (existing (car (files account target id)))
                       ;; Reuse retains the destination's own local X-TUID.
                       (digest (suderman/mail-file-digest (or existing source)))
                       (flags (cadr (split-string source ":2,"))))
                  (should (string-match-p ",U=[0-9]+" source))
                  (let ((moved (suderman/mail-move-local mail source target existing)))
                    (should-not (file-exists-p source))
                    (should (equal digest (suderman/mail-file-digest moved)))
                    (should (string-suffix-p (concat ":2," flags) moved))
                    (unless existing (should-not (string-match-p ",U=" moved)))
                    (should (equal (list moved) (files account target id)))
                    (should-not (files account "Inbox" id)))
                  (sync account)
                  (should (= 0 (call-process "notmuch" nil nil nil "new" "--quiet")))
                  (should-not (far-files account "Inbox" id))
                  (should (= 1 (length (far-files account target id))))
                  (should (= 1 (length (files account target id))))
                  (should (string-suffix-p (concat ":2," flags) (car (files account target id))))
                  (should (equal digest (suderman/mail-file-digest (car (files account target id)))))
                  ;; A second sync must neither resurrect Inbox nor duplicate target.
                  (sync account)
                  (should-not (far-files account "Inbox" id))
                  (should (= 1 (length (far-files account target id))))))
              (should (= 1 (length (far-files account "Archive" "filler@example.invalid")))))))
      (delete-directory root t))))

(ert-deftest suderman/mail-move-busy-lock-leaves-source-untouched ()
  (skip-unless (cl-every #'executable-find '("notmuch" "flock")))
  (let* ((root (make-temp-file "mail-move-lock-" t))
         (runtime (expand-file-name "runtime" root))
         (inbox (expand-file-name "suderman/Inbox/cur/" root))
         (source (expand-file-name "message,U=7:2,S" inbox))
         (process-environment (copy-sequence process-environment))
         (output (generate-new-buffer " *mail move lock*"))
         holder)
    (unwind-protect
        (progn
          (make-directory runtime)
          (make-directory inbox t)
          (with-temp-file source (insert "Untouched.\n"))
          (setenv "XDG_RUNTIME_DIR" runtime)
          (setq holder (make-process :name "mail-move-lock" :buffer output :noquery t
                                     :command (list "flock" "--no-fork"
                                                    (expand-file-name "email-suderman.lock" runtime)
                                                    "sh" "-c" "printf READY; exec sleep 5")))
          (let ((deadline (+ (float-time) 2)))
            (while (and (< (float-time) deadline)
                        (not (with-current-buffer output (string-match-p "READY" (buffer-string)))))
              (accept-process-output holder 0.05)))
          (should (with-current-buffer output (string-match-p "READY" (buffer-string))))
          (should-error (suderman/mail-move-local root source "Archive") :type 'user-error)
          (should (file-exists-p source))
          (should-not (file-exists-p (expand-file-name "suderman/Archive" root))))
      (when (and holder (process-live-p holder)) (delete-process holder))
      (kill-buffer output)
      (delete-directory root t))))

(ert-deftest suderman/mail-move-index-failure-keeps-destination-and-reports-partial-change ()
  (let* ((root (make-temp-file "mail-move-index-failure-" t))
         (runtime (expand-file-name "runtime" root))
         (bin (expand-file-name "bin" root))
         (inbox (expand-file-name "suderman/Inbox/cur/" root))
         (source (expand-file-name "message,U=7:2,S" inbox))
         (process-environment (copy-sequence process-environment))
         (exec-path (cons bin exec-path)))
    (unwind-protect
        (progn
          (make-directory runtime)
          (make-directory bin)
          (make-directory inbox t)
          (with-temp-file source (insert "Preserved after indexing fails.\n"))
          (with-temp-file (expand-file-name "notmuch" bin)
            (insert "#!" (executable-find "sh") "\nexit 42\n"))
          (set-file-modes (expand-file-name "notmuch" bin) #o700)
          (setenv "XDG_RUNTIME_DIR" runtime)
          (setenv "PATH" (concat bin ":" (getenv "PATH")))
          (should (string-match-p "Moved to .* but indexing failed"
                                  (error-message-string
                                   (should-error (suderman/mail-move-local root source "Archive")))))
          (should-not (file-exists-p source))
          (let ((destinations (directory-files (expand-file-name "suderman/Archive/cur" root) t "^[^.]")))
            (should (= 1 (length destinations)))
            (with-temp-buffer
              (insert-file-contents (car destinations))
              (should (equal "Preserved after indexing fails.\n" (buffer-string)))))
          (should-error (suderman/mail-move-local root source "Archive") :type 'user-error))
      (delete-directory root t))))

(ert-deftest suderman/mail-move-selected-confirms-and-limits-copies-to-chosen-account ()
  (skip-unless (and (cl-every #'executable-find '("notmuch" "flock")) (locate-library "notmuch")))
  (require 'notmuch)
  (let* ((root (make-temp-file "mail-move-reader-" t))
         (mail (expand-file-name "mail" root))
         (config (expand-file-name "config" root))
         (runtime (expand-file-name "runtime" root))
         (process-environment (copy-sequence process-environment))
         (notmuch--cli-sane-p nil)
         (before (buffer-list))
         (id "id:shared-reader@example.invalid")
         (existing (expand-file-name "nonfiction/Archive/cur/existing,U=9:2,S" mail))
         (duplicate (expand-file-name "nonfiction/Archive/cur/duplicate,U=10:2,S" mail)))
    (unwind-protect
        (save-window-excursion
          (make-directory runtime)
          (setenv "XDG_RUNTIME_DIR" runtime)
          (setenv "NOTMUCH_CONFIG" config)
          (setenv "NOTMUCH_DATABASE" nil)
          (setenv "NOTMUCH_PROFILE" nil)
          (with-temp-file config
            (insert "[database]\npath=" mail
                    "\n[user]\nname=Test\nprimary_email=test@example.invalid\n"
                    "[new]\ntags=unread\n[search]\nexclude_tags=deleted;spam\n"
                    "[maildir]\nsynchronize_flags=true\n"))
          (dolist (account '("suderman" "nonfiction"))
            (let ((file (expand-file-name (concat account "/Inbox/cur/source,U=7:2,S") mail)))
              (make-directory (file-name-directory file) t)
              (with-temp-file file
                (insert "From: sender@example.invalid\nTo: test@example.invalid\n"
                        "Subject: Selected reader move\nMessage-ID: <shared-reader@example.invalid>\n"
                        "X-TUID: InboxToken\n\nShared message, distinct account copies.\n"))))
          (make-directory (file-name-directory existing) t)
          (with-temp-file existing
            (insert "From: sender@example.invalid\nTo: test@example.invalid\n"
                    "Subject: Selected reader move\nMessage-ID: <shared-reader@example.invalid>\n"
                    "X-TUID: ArchiveToken\n\nShared message, distinct account copies.\n"))
          (should (= 0 (call-process "notmuch" nil nil nil "new" "--quiet")))
          (with-temp-buffer
            (setq major-mode 'notmuch-search-mode)
            (should-error (suderman/mail-archive) :type 'user-error))
          (notmuch-unthreaded (concat id " and folder:nonfiction/Inbox"))
          (let ((deadline (+ (float-time) 3)))
            (while (and (< (float-time) deadline)
                        (or (get-buffer-process (current-buffer)) (not (notmuch-tree-get-message-id))))
              (accept-process-output nil 0.01)))
          (should (notmuch-tree-get-message-id))
          (cl-labels
              ((files (account folder)
                 (seq-filter (lambda (file) (string-prefix-p
                                            (expand-file-name (concat account "/" folder "/") mail) file))
                             (notmuch--process-lines "notmuch" "search" "--output=files" "--exclude=false" id))))
            (cl-letf (((symbol-function 'get-buffer-process) (lambda (&rest _) t)))
              (should (string-match-p "finish loading"
                                      (error-message-string (should-error (suderman/mail-archive) :type 'user-error)))))
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (_prompt collection &rest _)
                         (should (equal '("nonfiction" "suderman") (sort (copy-sequence collection) #'string<)))
                         "nonfiction"))
                      ((symbol-function 'yes-or-no-p)
                       (lambda (prompt)
                         (should (string-match-p "nonfiction/Inbox to Archive" prompt)) nil)))
              (should-error (suderman/mail-archive) :type 'user-error))
            (should (= 1 (length (files "nonfiction" "Inbox"))))
            (should (= 1 (length (files "suderman" "Inbox"))))
            (copy-file existing duplicate)
            (should (= 0 (call-process "notmuch" nil nil nil "new" "--quiet")))
            (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "nonfiction"))
                      ((symbol-function 'yes-or-no-p) (lambda (&rest _) (error "Must refuse before confirmation"))))
              (should (string-match-p "Multiple destination copies"
                                      (error-message-string (should-error (suderman/mail-archive) :type 'user-error)))))
            (should (= 1 (length (files "nonfiction" "Inbox"))))
            (delete-file duplicate)
            (should (= 0 (call-process "notmuch" nil nil nil "new" "--quiet")))
            (let ((digest (suderman/mail-file-digest existing)))
              (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "nonfiction"))
                        ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
                (should (equal existing (suderman/mail-archive))))
              (should (equal digest (suderman/mail-file-digest existing))))
            (should-not (files "nonfiction" "Inbox"))
            (should (= 1 (length (files "suderman" "Inbox"))))
            (notmuch-show id)
            (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (error "Only one Inbox account remains")))
                      ((symbol-function 'yes-or-no-p)
                       (lambda (prompt) (should (string-match-p "suderman/Inbox to Trash" prompt)) t)))
              (should (file-exists-p (suderman/mail-trash))))
            (should-not (files "suderman" "Inbox"))
            (should (= 1 (length (files "nonfiction" "Archive"))))
            (should (= 1 (length (files "suderman" "Trash"))))
            (should-not (files "suderman" "Archive"))
            (should-not (files "nonfiction" "Trash"))
            (should-error (suderman/mail-trash) :type 'user-error)))
      (dolist (buffer (seq-difference (buffer-list) before))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (set-buffer-modified-p nil)
            (let ((kill-buffer-query-functions nil)) (kill-buffer buffer)))))
      (delete-directory root t))))

;;; mail-move-test.el ends here
