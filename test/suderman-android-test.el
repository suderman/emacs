;;; suderman-android-test.el --- Focused Android checks -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'suderman-android)

(ert-deftest suderman/android-font-install-verifies-before-committing ()
  (let* ((directory (make-temp-file "suderman-android-fonts-" t))
         (suderman/android-font-directory directory)
         (content "verified font")
         (checksum (secure-hash 'sha256 content))
         (suderman/android-fonts
          `(("font.ttf" . ("https://example.test/font.ttf" ,checksum)))))
    (unwind-protect
        (cl-letf (((symbol-function 'url-copy-file)
                   (lambda (_url destination &optional _ok-if-exists)
                     (with-temp-file destination (insert content)))))
          (suderman/android-install-fonts)
          (should (equal
                   (with-temp-buffer
                     (insert-file-contents (expand-file-name "font.ttf" directory))
                     (buffer-string))
                   content)))
      (delete-directory directory t))))

(ert-deftest suderman/android-font-install-rejects-a-bad-download ()
  (let* ((directory (make-temp-file "suderman-android-fonts-" t))
         (suderman/android-font-directory directory)
         (suderman/android-fonts
          '(("font.ttf" . ("https://example.test/font.ttf" "wrong")))))
    (unwind-protect
        (cl-letf (((symbol-function 'url-copy-file)
                   (lambda (_url destination &optional _ok-if-exists)
                     (with-temp-file destination (insert "corrupt")))))
          (suderman/android-install-fonts)
          (should-not (file-exists-p (expand-file-name "font.ttf" directory)))
          (should (null (directory-files directory nil "\\`\\.font" t))))
      (delete-directory directory t))))

(ert-deftest suderman/android-volume-buttons-support-modifiers-and-chords ()
  (cl-letf (((symbol-function 'read-event) (lambda (&rest _) 'volume-up)))
    (should (equal (suderman/android-volume-control nil) [escape])))
  (cl-letf (((symbol-function 'read-event) (lambda (&rest _) 'volume-down)))
    (should (equal (suderman/android-volume-meta nil) [tab])))
  (cl-letf (((symbol-function 'read-event) (lambda (&rest _) ?x))
            ((symbol-function 'event-apply-modifier)
             (lambda (event modifier bit prefix)
               (list event modifier bit prefix))))
    (should (equal (suderman/android-volume-control nil)
                   [(120 control 26 "C-")]))
    (should (equal (suderman/android-volume-meta nil)
                   [(120 meta 27 "M-")]))))

(provide 'suderman-android-test)
;;; suderman-android-test.el ends here
