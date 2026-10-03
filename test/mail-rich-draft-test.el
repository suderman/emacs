;;; mail-rich-draft-test.el --- Safe Org and native rich-draft checks -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'suderman-mail-drafts)

(ert-deftest suderman/mail-org-input-rejects-code-headers-and-unsafe-files ()
  (let ((org-inhibit-startup t)
        (root (make-temp-file "mail-org-input-" t))
        (outside (make-temp-file "mail-outside-")))
    (unwind-protect
        (progn
          (make-symbolic-link outside (expand-file-name "escape.txt" root))
          (dolist (body '("#+INCLUDE: /etc/passwd" "#+SETUPFILE: /etc/passwd"
                          "#+BIND: org-export-use-babel t"
                          "#+MACRO: hack (eval (error \"executed\"))\n{{{hack}}}"
                          "#+LINK: hack %(shell-command)\n[[hack:test]]"
                          "#+HTML: <img src=\"https://example.invalid/tracker\">"
                          "#+ATTR_HTML: :onclick bad()\n[[file:escape.txt]]"
                          "#+begin_export html\n<script>bad()</script>\n#+end_export"
                          "@@html:<img src=\"https://example.invalid/tracker\">@@"
                          "#+CALL: run()" "call_run()"
                          "<#part filename=\"/etc/passwd\">"
                          "[[elisp:(error \"executed\")]]"
                          "[[https://example.invalid/tracker.png]]"
                          "[[file:/etc/passwd]]" "[[file:escape.txt]]"
                          "[[file:/ssh:example.invalid:/etc/passwd]]"
                          "[[file:missing.txt]]" "[[file:escape.txt::unsafe-search]]"
                          "#+PROPERTY: MAIL_SUBJECT duplicate"
                          "#+PROPERTY: MAIL_FCC bad"))
            (with-temp-buffer
              (insert "#+PROPERTY: MAIL_FROM jon@suderman.net\n"
                      "#+PROPERTY: MAIL_TO reader@example.invalid\n"
                      "#+PROPERTY: MAIL_SUBJECT Safe draft\n\n" body "\n")
              (delay-mode-hooks (org-mode))
              (should-error (suderman/mail-draft-input root) :type 'user-error)))
          (dolist (header '("hello\nBcc: injected@example.invalid" "hello\rbad" "bad\0value"))
            (should-error (suderman/mail-draft-header header) :type 'user-error))
          (dolist (from '("unknown@example.invalid" "jon@suderman.net, jon@nonfiction.ca"))
            (with-temp-buffer
              (insert "#+PROPERTY: MAIL_FROM " from "\n"
                      "#+PROPERTY: MAIL_TO reader@example.invalid\n"
                      "#+PROPERTY: MAIL_SUBJECT Draft\n\nBody\n")
              (delay-mode-hooks (org-mode))
              (should-error (suderman/mail-draft-input root) :type 'user-error))))
      (delete-directory root t)
      (delete-file outside))))

(ert-deftest suderman/mail-org-file-is-rejected-before-external-reads ()
  (skip-unless (and (executable-find "notmuch") (locate-library "notmuch")
                    (locate-library "org-mime")))
  (require 'notmuch)
  (require 'org-mime)
  (let ((source (make-temp-file "mail-unsafe-source-" nil ".org"))
        (reader (symbol-function 'insert-file-contents)))
    (unwind-protect
        (dolist (body '("#+SETUPFILE: /ssh:example.invalid:/etc/passwd"
                        "#+INCLUDE: /etc/passwd"
                        "#+STARTUP: inlineimages\n[[file:/ssh:example.invalid:/tmp/test.png]]"))
          (with-temp-file source
            (insert "#+PROPERTY: MAIL_FROM jon@suderman.net\n"
                    "#+PROPERTY: MAIL_TO reader@example.invalid\n"
                    "#+PROPERTY: MAIL_SUBJECT Unsafe input\n\n" body "\n"))
          (cl-letf (((symbol-function 'insert-file-contents)
                     (lambda (file &rest args)
                       (unless (equal file source)
                         (ert-fail "Unvalidated source caused an external read"))
                       (apply reader file args)))
                    ((symbol-function 'org-link-preview)
                     (lambda (&rest _) (ert-fail "Unvalidated source caused a preview"))))
            (should-error (suderman/mail-draft-from-org source) :type 'user-error)))
      (delete-file source))))

(ert-deftest suderman/mail-org-rich-draft-embeds-images-and-survives-resume ()
  (skip-unless (and (executable-find "notmuch") (executable-find "python3")
                    (locate-library "notmuch") (locate-library "org-mime")))
  (require 'notmuch)
  (require 'org-mime)
  (let* ((root (make-temp-file "mail-rich-draft-" t))
         (mail (expand-file-name "mail" root))
         (config (expand-file-name "notmuch-config" root))
         (source (expand-file-name "draft.org" root))
         (png (expand-file-name "screenshot.png" root))
         (notes (expand-file-name "notes.txt" root))
         (raw (expand-file-name "draft.eml" root))
         (process-environment (copy-sequence process-environment))
         (notmuch--cli-sane-p nil)
         (notmuch-address-use-company nil)
         buffers)
    (unwind-protect
        (save-window-excursion
          (setenv "NOTMUCH_CONFIG" config)
          (setenv "NOTMUCH_DATABASE" nil)
          (setenv "NOTMUCH_PROFILE" nil)
          (make-directory mail)
          (with-temp-file config
            (insert "[database]\npath=" mail
                    "\n[user]\nname=Test\nprimary_email=test@example.invalid\n"
                    "[new]\ntags=unread\n[search]\nexclude_tags=deleted;spam\n"
                    "[maildir]\nsynchronize_flags=true\n"))
          (should (= 0 (call-process "notmuch" nil nil nil "new")))
          (with-temp-file png
            (set-buffer-multibyte nil)
            (insert (base64-decode-string
                     "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=")))
          (with-temp-file notes (insert "Attached notes.\n"))
          (with-temp-file source
            (insert "#+STARTUP: inlineimages\n"
                    "#+PROPERTY: MAIL_FROM Jon Suderman <jon@suderman.net>\n"
                    "#+PROPERTY: MAIL_TO reader@example.invalid\n"
                    "#+PROPERTY: MAIL_CC copy@example.invalid\n"
                    "#+PROPERTY: MAIL_BCC private@example.invalid\n"
                    "#+PROPERTY: MAIL_SUBJECT Rich draft test\n"
                    "#+PROPERTY: MAIL_IN_REPLY_TO <original@example.invalid>\n"
                    "#+PROPERTY: MAIL_REFERENCES <older@example.invalid> <original@example.invalid>\n\n"
                    "* Update\nA *bold* change and [[https://example.invalid][link]].\n\n"
                    "- First item\n- Second item\n\n"
                    "[[file:screenshot.png]]\n\n[[file:notes.txt][Notes]]\n\n"
                    "#+begin_src emacs-lisp\n(error \"Never execute this\")\n#+end_src\n"
                    "\n# Local Variables:\n# eval: (error \"Never apply file locals\")\n# End:\n"))
          (cl-letf (((symbol-function 'org-link-preview)
                     (lambda (&rest _) (ert-fail "Untrusted source triggered a preview")))
                    ((symbol-function 'message-send-mail)
                     (lambda (&rest _) (ert-fail "Transport called by draft creation")))
                    ((symbol-function 'org-babel-execute-src-block)
                     (lambda (&rest _) (ert-fail "Babel executed during draft creation"))))
            (let* ((result (suderman/mail-draft-from-org source))
                   (id (plist-get result :id)))
              (push (current-buffer) buffers)
              (should (equal (plist-get result :source) source))
              (should message-confirm-send)
              (should (equal "1\n" (notmuch-command-to-string "count" id)))
              (should (equal "1\n" (notmuch-command-to-string
                                    "count" (concat id " and folder:drafts and tag:draft and not tag:unread"))))
              (should (= #o600 (file-modes (string-trim (notmuch-command-to-string "search" "--output=files" id)))))
              (when (display-graphic-p)
                (let ((compose (current-buffer))
                      (notmuch-show-all-multipart/alternative-parts t)
                      (mm-text-html-renderer 'shr))
                  (cl-letf (((symbol-function 'url-queue-retrieve)
                             (lambda (&rest _) (ert-fail "Remote image fetched"))))
                    (notmuch-show id))
                  (push (current-buffer) buffers)
                  (goto-char (point-min))
                  (let ((image (text-property-search-forward
                                'image-url nil (lambda (_ value)
                                                 (and (stringp value)
                                                      (string-prefix-p "cid:" value))))))
                    (should image)
                    (should (eq (car-safe (get-text-property
                                          (prop-match-beginning image) 'display))
                                'image)))
                  (pop-to-buffer compose)))
              (set-buffer-modified-p nil)
              (kill-buffer (current-buffer))
              ;; The source remains caller-owned; a saved draft doesn't depend on it.
              (delete-file source)
              (delete-file png)
              (delete-file notes)
              (notmuch-draft-resume id)
              (push (current-buffer) buffers)
              (should (equal (message-fetch-field "In-Reply-To") "<original@example.invalid>"))
              (should (string-match-p "<older@example.invalid>" (message-fetch-field "References")))
              (should (string-match-p "type=\"?text/html" (buffer-string)))
              (message-replace-header "Subject" "Reviewed rich draft")
              (notmuch-draft-save)
              (should (equal "0\n" (notmuch-command-to-string "count" id)))
              (let ((mime (notmuch-command-to-string "show" "--format=raw" notmuch-draft-id)))
                (with-temp-file raw (insert mime)))
              (with-temp-buffer
                (should (= 0 (call-process
                              "python3" nil t nil "-c"
                              (concat
                               "import email,sys\nfrom email.policy import default\n"
                               "m=email.message_from_binary_file(open(sys.argv[1],'rb'),policy=default)\n"
                               "assert m['Subject']=='Reviewed rich draft'\n"
                               "assert m['Bcc']=='private@example.invalid'\n"
                               "assert m['X-Notmuch-Emacs-Draft']=='True'\n"
                               "types=[p.get_content_type() for p in m.walk()]\n"
                               "assert types.count('multipart/alternative')==1,types\n"
                               "assert 'multipart/related' in types,types\n"
                               "html=m.get_body(preferencelist=('html',)).get_content()\n"
                               "assert '<h2' in html and '<ul' in html and '<b>bold</b>' in html,html\n"
                               "assert 'https://example.invalid' in html\n"
                               "assert 'MAIL_BCC' not in html\n"
                               "img=next(p for p in m.walk() if p.get_content_type()=='image/png')\n"
                               "assert img.get_payload(decode=True).startswith(b'\\x89PNG\\r\\n\\x1a\\n')\n"
                               "assert 'cid:'+img['Content-ID'].strip('<>') in html\n"
                               "plain=m.get_body(preferencelist=('plain',)).get_content()\n"
                               "assert 'First item' in plain and '<#' not in plain\n"
                               "assert 'MAIL_BCC' not in plain\n"
                               "assert plain.count('https://suderman.net')==1,plain\n"
                               "assert any(p.get_filename()=='notes.txt' and p.get_payload(decode=True)==b'Attached notes.\\n' for p in m.walk())\n")
                              raw)))
                (should (string-empty-p (buffer-string)))))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory root t))))

(provide 'mail-rich-draft-test)
;;; mail-rich-draft-test.el ends here
