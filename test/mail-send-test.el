;;; mail-send-test.el --- Offline transport and sender checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Use a private Notmuch store and a dummy sendmail executable, never SMTP.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'suderman-mail)

(ert-deftest suderman/mail-rejects-unknown-missing-and-multiple-senders ()
  (dolist (from '("" "unknown@example.invalid"
                  "jon@suderman.net, jon@nonfiction.ca"
                  "jon@suderman.net\nFrom: jon@nonfiction.ca"))
    (with-temp-buffer
      (insert "From: " from "\n" mail-header-separator "\nBody\n")
      (should-error (suderman/mail-account) :type 'user-error))))

(ert-deftest suderman/mail-recomputes-routing-after-changing-from ()
  (skip-unless (locate-library "notmuch"))
  (require 'notmuch)
  (with-temp-buffer
    (insert "From: Jon Suderman <jon@suderman.net>\n"
            "Fcc: stale-folder\nX-Message-SMTP-Method: smtp smtp.invalid\n"
            mail-header-separator "\nBody\n")
    (suderman/mail-prepare-send)
    (should (equal message-sendmail-extra-arguments '("--account=suderman")))
    (should (equal (message-sendmail-envelope-from) "jon@suderman.net"))
    (should (equal (message-fetch-field "Fcc") "suderman/Sent -inbox -unread -draft"))
    (should-not (message-fetch-field "X-Message-SMTP-Method"))
    (message-replace-header "From" "Jon Suderman <jon@nonfiction.ca>")
    (suderman/mail-prepare-send)
    (should (equal message-sendmail-extra-arguments '("--account=nonfiction")))
    (should (equal (message-sendmail-envelope-from) "jon@nonfiction.ca"))
    (should-not (message-fetch-field "Fcc"))))

(ert-deftest suderman/mail-routes-sends-and-keeps-failed-drafts ()
  (skip-unless (and (executable-find "notmuch") (locate-library "notmuch")))
  (require 'notmuch)
  (let* ((root (make-temp-file "suderman-send-test-" t))
         (mail (expand-file-name "mail" root))
         (config (expand-file-name "notmuch-config" root))
         (sendmail-program (expand-file-name "dummy-sendmail" root))
         (args-file (expand-file-name "args" root))
         (input-file (expand-file-name "input" root))
         (process-environment (copy-sequence process-environment))
         (notmuch--cli-sane-p nil)
         (notmuch-address-use-company nil)
         (message-sendmail-extra-arguments nil)
         ;; Message normally warns about .invalid recipients.
         (message-bogus-addresses nil)
         (buffers nil))
    (unwind-protect
        (save-window-excursion
          (setenv "NOTMUCH_CONFIG" config)
          (setenv "NOTMUCH_DATABASE" nil)
          (setenv "NOTMUCH_PROFILE" nil)
          (setenv "MAIL_TEST_ROOT" root)
          (make-directory mail)
          (dolist (part '("cur" "new" "tmp"))
            (make-directory (expand-file-name (concat "suderman/Sent/" part) mail) t))
          (with-temp-file config
            (insert "[database]\npath=" mail
                    "\n[user]\nname=Send Test\nprimary_email=test@example.invalid\n"
                    "[new]\ntags=unread\n[search]\nexclude_tags=deleted;spam\n"
                    "[maildir]\nsynchronize_flags=true\n"))
          (should (= 0 (call-process "notmuch" nil nil nil "new")))
          (with-temp-file sendmail-program
            (insert "#!/bin/sh\numask 077\n"
                    "printf '%s\\n' \"$@\" > \"$MAIL_TEST_ROOT/args\"\n"
                    "cat > \"$MAIL_TEST_ROOT/input\"\n"
                    "printf x >> \"$MAIL_TEST_ROOT/calls\"\n"
                    "if [ -f \"$MAIL_TEST_ROOT/fail\" ]; then\n"
                    "  echo 'Synthetic transport failure' >&2\n  exit 75\nfi\n"))
          (set-file-modes sendmail-program #o700)
          (dolist (address '("jon@suderman.net" "jon@nonfiction.ca"))
            (notmuch-mua-mail
             "recipient@example.invalid" "Offline send test"
             `((From . ,(concat "Jon Suderman <" address ">"))
               (Bcc . "private@example.invalid")))
            (push (current-buffer) buffers)
            (setq-local message-confirm-send nil)
            (message-goto-body)
            (insert "Synthetic transport test.\n")
            (should (string-match-p
                     (if (equal address "jon@suderman.net")
                         "https://suderman.net" "https://www.nonfiction.ca")
                     (buffer-string)))
            (notmuch-draft-save)
            (let ((compose (current-buffer))
                  (draft-id notmuch-draft-id)
                  (sent-before (notmuch-command-to-string "count" "folder:suderman/Sent")))
              ;; Refresh routing after resume or a user edit, ignoring stale Fcc.
              (message-replace-header "Fcc" "wrong-folder +unread")
              (message-replace-header "X-Message-SMTP-Method" "smtp smtp.invalid")
              (with-temp-file (expand-file-name "fail" root) (insert "fail\n"))
              (let ((before (buffer-list)))
                (should (string-match-p
                         "75" (cadr (should-error (notmuch-mua-send) :type 'error))))
                ;; Message keeps failed-transport diagnostics for human review.
                (dolist (buffer (buffer-list))
                  (when (and (not (memq buffer before))
                             (string-prefix-p " sendmail errors" (buffer-name buffer)))
                    (push buffer buffers))))
              (set-buffer compose)
              (should (equal "1\n" (notmuch-command-to-string "count" draft-id)))
              (should (equal sent-before (notmuch-command-to-string
                                         "count" "folder:suderman/Sent")))
              (should-not message-sent-message-via)
              (should-not (message-fetch-field "X-Message-SMTP-Method"))
              (should (equal (message-fetch-field "Fcc")
                             (and (equal address "jon@suderman.net")
                                  "suderman/Sent -inbox -unread -draft")))
              (with-temp-buffer
                (insert-file-contents args-file)
                (should (equal (split-string (buffer-string) "\n" t)
                               (list "-oi" (if (equal address "jon@suderman.net")
                                               "--account=suderman" "--account=nonfiction")
                                     "-f" address "-t"))))
              (with-temp-buffer
                (insert-file-contents input-file)
                ;; msmtp needs the Bcc header with -t to find blind recipients.
                (should (string-match-p "^Bcc: private@example.invalid$" (buffer-string)))
                (should-not (string-match-p "^Fcc:" (buffer-string)))
                (should-not (string-match-p "^X-Notmuch-Emacs-Draft:" (buffer-string))))
              ;; The failed draft can be reopened and retried without reconstruction.
              (set-buffer-modified-p nil)
              (kill-buffer compose)
              (notmuch-draft-resume draft-id)
              (push (current-buffer) buffers)
              (setq-local message-confirm-send nil)
              (delete-file (expand-file-name "fail" root))
              (should (notmuch-mua-send))
              (should (equal "0\n" (notmuch-command-to-string "count" draft-id)))
              (should (equal "1\n" (notmuch-command-to-string
                                    "count" "--exclude=false" draft-id)))
              (should (equal "1\n" (notmuch-command-to-string
                                    "count" "folder:suderman/Sent")))
              (should (equal "0\n" (notmuch-command-to-string
                                    "count" "folder:nonfiction/Sent"))))
            (set-buffer-modified-p nil)
            (kill-buffer (current-buffer)))
          ;; Delivery can succeed before Sent storage fails.  Retire the draft
          ;; and preserve Message's sent marker so a retry cannot silently resend.
          (notmuch-mua-mail "recipient@example.invalid" "Offline Fcc failure"
                            '((From . "Jon Suderman <jon@suderman.net>")))
          (push (current-buffer) buffers)
          (setq-local message-confirm-send nil)
          (message-goto-body)
          (insert "Synthetic Sent storage failure.\n")
          (notmuch-draft-save)
          (let ((draft-id notmuch-draft-id))
            (cl-letf (((symbol-function 'notmuch-maildir-message-do-fcc)
                       (lambda () (error "Synthetic Fcc failure"))))
              (should (equal '(error "Synthetic Fcc failure")
                             (should-error (notmuch-mua-send)))))
            (should (equal '(mail) message-sent-message-via))
            (should (equal "0\n" (notmuch-command-to-string "count" draft-id)))
            (should (equal "1\n" (notmuch-command-to-string
                                  "count" "--exclude=false" draft-id)))
            (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
              (should-error (notmuch-mua-send)))
            (with-temp-buffer
              (insert-file-contents (expand-file-name "calls" root))
              (should (equal "xxxxx" (buffer-string)))))
          (let* ((query "folder:suderman/Sent")
                 (tags (notmuch--process-lines "notmuch" "search" "--output=tags" query))
                 (file (car (notmuch--process-lines "notmuch" "search" "--output=files" query))))
            (should-not (member "draft" tags))
            (should-not (member "unread" tags))
            (should-not (member "inbox" tags))
            (should (string-match-p ":2,.*S" file))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory root t))))

;;; mail-send-test.el ends here
