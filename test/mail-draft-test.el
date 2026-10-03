;;; mail-draft-test.el --- Native drafts against an isolated mail store -*- lexical-binding: t; -*-

;;; Commentary:
;; Exercise real Notmuch insert/resume without touching Jon's mail or SMTP.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'suderman-mail)

(ert-deftest suderman/mail-drafts-survive-resave-resume-and-invalid-sender ()
  (skip-unless (and (executable-find "notmuch") (locate-library "notmuch")))
  (require 'notmuch)
  (let* ((root (make-temp-file "suderman-mail-test-" t))
         (mail (expand-file-name "mail" root))
         (config (expand-file-name "notmuch-config" root))
         (image (expand-file-name "screenshot.png" root))
         (process-environment (copy-sequence process-environment))
         (notmuch--cli-sane-p nil)
         (notmuch-address-use-company nil)
         (message-signature nil)
         (buffers nil)
         first-id second-id transport-called)
    (unwind-protect
        (save-window-excursion
          (setenv "NOTMUCH_CONFIG" config)
          (setenv "NOTMUCH_DATABASE" nil)
          (setenv "NOTMUCH_PROFILE" nil)
          (make-directory mail)
          (with-temp-file config
            (insert "[database]\npath=" mail
                    "\n[user]\nname=Draft Test\nprimary_email=test@example.invalid\n"
                    "[new]\ntags=unread\n[search]\nexclude_tags=deleted;spam\n"
                    "[maildir]\nsynchronize_flags=true\n"))
          (should (= 0 (call-process "notmuch" nil nil nil "new")))
          (with-temp-file image
            (set-buffer-multibyte nil)
            (insert (base64-decode-string
                     "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=")))
          (notmuch-mua-mail "recipient@example.invalid" "Synthetic draft"
                            '((From . "Jon Suderman <jon@suderman.net>")))
          (push (current-buffer) buffers)
          (message-goto-body)
          (insert "Editable draft body.\n")
          (mml-attach-file image "image/png" "Synthetic screenshot" "attachment")
          (notmuch-draft-save)
          (setq first-id notmuch-draft-id)
          (should (equal "1\n" (notmuch-command-to-string "count" "--output=messages"
                                                         first-id)))
          (let ((tags (notmuch--process-lines
                       "notmuch" "search" "--output=tags" first-id)))
            (should (member "draft" tags))
            (should-not (member "unread" tags))
            (should-not (member "deleted" tags)))
          (let ((file (car (notmuch--process-lines
                           "notmuch" "search" "--output=files" first-id))))
            (should (= #o600 (logand #o777 (file-modes file))))
            (should (string-match-p ":2,.*D" file)))
          ;; Read/unread and stars rename Maildir flags without moving folders.
          (notmuch-tag first-id '("+flagged" "+unread"))
          (let ((file (car (notmuch--process-lines
                           "notmuch" "search" "--output=files" first-id))))
            (should (string-match-p ":2,.*F" file))
            (should-not (string-match-p ":2,.*S" file))
            (should (string-prefix-p (expand-file-name "drafts/" mail) file)))
          (notmuch-tag first-id '("-flagged" "-unread"))
          ;; An unknown sender must stop before transport or hiding the draft.
          (message-replace-header "From" "unknown@example.invalid")
          (let ((message-send-mail-function
                 (lambda () (setq transport-called t))))
            (should-error (notmuch-mua-send) :type 'user-error)
            (should-error (run-hooks 'message-send-hook) :type 'user-error))
          (should-not transport-called)
          (message-replace-header "From" "Jon Suderman <jon@suderman.net>")
          (should (equal "1\n" (notmuch-command-to-string "count" first-id)))
          (message-goto-body)
          (insert "Revision kept.\n")
          (notmuch-draft-save)
          (setq second-id notmuch-draft-id)
          (should-not (equal first-id second-id))
          (should (equal "0\n" (notmuch-command-to-string "count" first-id)))
          (should (equal "1\n" (notmuch-command-to-string
                                "count" "--exclude=false" first-id)))
          (should (equal "1\n" (notmuch-command-to-string
                                "count" "folder:drafts and tag:draft and not tag:deleted")))
          (kill-buffer (current-buffer))
          (delete-file image)
          (notmuch-draft-resume second-id)
          (push (current-buffer) buffers)
          (should (derived-mode-p 'notmuch-message-mode))
          (should (equal second-id notmuch-draft-id))
          (should (equal "Jon Suderman <jon@suderman.net>" (message-fetch-field "From")))
          (should (string-match-p "Revision kept" (buffer-string)))
          (should (string-match-p "image/png" (buffer-string)))
          ;; Resave after the original attachment has been removed.
          (notmuch-draft-save)
          (should (equal "1\n" (notmuch-command-to-string
                                "count" "folder:drafts and tag:draft and not tag:deleted")))
          (should (string-match-p "image/png" (notmuch-command-to-string
                                              "show" "--format=raw" notmuch-draft-id))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory root t))))

;;; mail-draft-test.el ends here
