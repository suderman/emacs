;;; suderman-mail-drafts.el --- Org-authored local mail drafts -*- lexical-binding: t; -*-

;;; Commentary:
;; Agents provide an Org file, not Elisp or MIME.  This command saves a native
;; Notmuch draft for review and never sends.  Source files remain with the caller.

;;; Code:

(require 'suderman-mail)
(require 'org)
(require 'ox-html)
(eval-when-compile (require 'org-mime nil t))

(declare-function org-mime-htmlize "org-mime")
(declare-function notmuch-mua-mail "notmuch-mua")
(declare-function notmuch-draft-save "notmuch-draft")
(defvar notmuch-draft-id)

(use-package org-mime
  :if (executable-find "notmuch")
  :commands org-mime-htmlize
  :init
  (setq org-mime-export-options '(:with-toc nil :section-numbers nil
                                 :with-author nil :with-latex verbatim)
        org-mime-export-ascii 'utf-8))

(defun suderman/mail-draft-header (value)
  "Reject control characters in a supplied header VALUE."
  (when (string-match-p "[[:cntrl:]]" value)
    (user-error "Mail headers must be single lines without control characters"))
  value)

(defun suderman/mail-draft-input (directory)
  "Validate the current Org buffer for mail export relative to DIRECTORY.
Return (HEADERS ATTACHMENTS).  Local file links must stay inside DIRECTORY,
including after resolving symlinks.  Export code and raw MIME are not input."
  (when (string-match-p "<#" (buffer-string))
    (user-error "Raw MML is not allowed in Org draft input"))
  (let ((tree (org-element-parse-buffer)) headers attachments)
    (org-element-map tree '(keyword export-block export-snippet macro
                           babel-call inline-babel-call link)
      (lambda (element)
        (pcase (org-element-type element)
          ('keyword
           (let ((key (org-element-property :key element))
                 (value (org-element-property :value element)))
             (when (member key '("INCLUDE" "SETUPFILE" "BIND" "MACRO"
                                 "CALL" "LINK" "HTML" "ATTR_HTML"
                                 "HTML_HEAD" "HTML_HEAD_EXTRA"))
               (user-error "%s is not allowed in mail source" key))
             (when (and (equal key "PROPERTY")
                        (string-match "\\`MAIL_\\([A-Z_]+\\)[ \t]+\\(.*\\)\\'" value))
               (let ((name (match-string 1 value))
                     (text (suderman/mail-draft-header (match-string 2 value))))
                 (unless (member name '("FROM" "TO" "SUBJECT" "CC" "BCC"
                                        "IN_REPLY_TO" "REFERENCES"))
                   (user-error "Unknown mail property: MAIL_%s" name))
                 (when (assoc name headers)
                   (user-error "Duplicate mail property: MAIL_%s" name))
                 (push (cons name text) headers)))))
          ('link
           (let ((type (org-element-property :type element))
                 (path (org-element-property :path element)))
             (unless (member type '("file" "http" "https" "mailto"))
               (user-error "Link type %s is not allowed in mail source" type))
             (when (and (equal type "file")
                        (org-element-property :search-option element))
               (user-error "File links must name whole attachments without search options"))
             (if (equal type "file")
                 (let ((path (expand-file-name (org-link-unescape path) directory)))
                   ;; Check before file-truename, which would contact TRAMP hosts.
                   (when (or (file-remote-p path)
                             (string-match-p "[[:cntrl:]<>\"\\\\]" path))
                     (user-error "Unsafe or remote attachment filename"))
                   (let ((real (file-truename path)))
                     ;; org-mime puts image paths into quoted MML attributes.
                     (when (string-match-p "[[:cntrl:]<>\"\\\\]" real)
                       (user-error "Unsafe attachment filename"))
                     (unless (and (not (file-remote-p real))
                                  (file-in-directory-p real directory)
                                  (file-regular-p real) (file-readable-p real))
                       (user-error "Attachments must be readable local files inside the source directory"))
                     (unless (org-export-inline-image-p element org-html-inline-image-rules)
                       (cl-pushnew real attachments :test #'equal))))
               (when (org-export-inline-image-p element org-html-inline-image-rules)
                 (user-error "Use a local screenshot, not a remote inline image")))))
          (_ (user-error "Executable or raw export constructs are not allowed in mail source")))))
    (dolist (name '("FROM" "TO" "SUBJECT"))
      (unless (and (assoc name headers)
                   (not (string-empty-p (cdr (assoc name headers)))))
        (user-error "MAIL_%s is required" name)))
    (let ((from (mail-header-parse-addresses (cdr (assoc "FROM" headers)))))
      (unless (and (= (length from) 1)
                   (assoc-string (caar from) suderman/mail-accounts t))
        (user-error "MAIL_FROM must be one configured sender")))
    (dolist (name '("TO" "CC" "BCC"))
      (when-let* ((text (cdr (assoc name headers))))
        (let ((addresses (mail-header-parse-addresses text)))
          (unless (and addresses
                       (cl-every (lambda (address)
                                   (string-match-p "\\`[^[:space:]<>@]+@[^[:space:]<>@]+\\'"
                                                   (car address)))
                                 addresses))
            (user-error "MAIL_%s must contain email addresses" name)))))
    (dolist (name '("IN_REPLY_TO" "REFERENCES"))
      (when-let* ((text (cdr (assoc name headers))))
        (unless (string-match-p "\\`<[^[:space:]<>]+>\\(?: +<[^[:space:]<>]+>\\)*\\'" text)
          (user-error "MAIL_%s must contain bracketed message IDs" name))))
    (list headers attachments)))

(defun suderman/mail-draft-from-org (file)
  "Create and save a local Notmuch draft from Org FILE.  Never send.
Use #+PROPERTY: MAIL_FROM, MAIL_TO, and MAIL_SUBJECT.  Optional properties
are MAIL_CC, MAIL_BCC, MAIL_IN_REPLY_TO, and MAIL_REFERENCES.  File links
embed images or attach files, which must be inside FILE's directory.
Return a plist with :id, :source, and :buffer for human review.
Each call creates a new candidate; it does not replace earlier drafts.
Keep FILE and linked files to edit and regenerate.  Saved drafts embed bytes
and can also be resumed and edited directly with native Notmuch commands."
  (interactive "fOrg mail source: ")
  (unless (executable-find "notmuch")
    (user-error "Notmuch CLI and local mail store are required on this host"))
  (when (file-remote-p file)
    (user-error "Mail source must be a local file"))
  (setq file (file-truename file))
  (unless (and (file-regular-p file) (file-readable-p file))
    (user-error "Mail source must be a readable file"))
  (require 'notmuch)
  (require 'org-mime)
  (let* ((default-directory (file-name-directory file))
         ;; Startup previews run inside org-mode itself, even with delayed hooks.
         (org-inhibit-startup t)
         (input (with-temp-buffer
                  ;; Enter an empty mode before reading untrusted setup keywords.
                  ;; Do not visit FILE or apply its file-local variables.
                  (delay-mode-hooks (org-mode))
                  (insert-file-contents file)
                  (cons (buffer-string)
                        (suderman/mail-draft-input default-directory))))
         (headers (cadr input))
         (attachments (caddr input))
         (other-headers
          (cl-loop for (key . value) in headers
                   unless (member key '("TO" "SUBJECT" "REFERENCES"))
                   collect (cons (pcase key
                                   ("IN_REPLY_TO" "In-Reply-To")
                                   (_ (capitalize key))) value)))
         (org-export-use-babel nil)
         (org-export-allow-bind-keywords nil)
         (org-html-htmlize-output-type nil)
         ;; Render the complete body, including the sender's signature, once.
         (org-mime-mail-signature-separator "\\`\\'")
         (transient-mark-mode nil))
    (notmuch-mua-mail (cdr (assoc "TO" headers))
                      (cdr (assoc "SUBJECT" headers)) other-headers)
    ;; Message's References formatter omits its newline during initial setup.
    (when-let* ((references (cdr (assoc "REFERENCES" headers))))
      (message-replace-header "References" references))
    (message-goto-body)
    (insert (car input) "\n")
    (org-mime-htmlize)
    (dolist (attachment attachments)
      (goto-char (point-max))
      (mml-attach-file attachment))
    (notmuch-draft-save)
    (let ((result (list :id notmuch-draft-id :source file :buffer (buffer-name))))
      (message "Saved local draft %s; review before sending" notmuch-draft-id)
      result)))

(provide 'suderman-mail-drafts)
;;; suderman-mail-drafts.el ends here
