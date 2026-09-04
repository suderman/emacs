;;; suderman-packages-test.el --- Focused package bootstrap checks -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'suderman-packages)

(ert-deftest suderman/android-package-keyring-is-materialized-for-gpg ()
  (let ((system-type 'android)
        imported-file
        imported-content)
    (cl-letf (((symbol-function 'copy-file)
               (lambda (source destination &rest _)
                 (should (equal source "/assets/etc/package-keyring.gpg"))
                 (with-temp-file destination
                   (set-buffer-multibyte nil)
                   (insert "keyring")))))
      (suderman/package-import-keyring-from-android-assets
       (lambda (file)
         (setq imported-file file)
         (should-not (string-prefix-p "/assets/" file))
         (setq imported-content
               (with-temp-buffer
                 (insert-file-contents-literally file)
                 (buffer-string))))
       "/assets/etc/package-keyring.gpg"))
    (should (equal imported-content "keyring"))
    (should-not (file-exists-p imported-file))))

(ert-deftest suderman/physical-package-keyring-passes-through-unchanged ()
  (let ((system-type 'android)
        imported-file)
    (suderman/package-import-keyring-from-android-assets
     (lambda (file) (setq imported-file file))
     "/tmp/package-keyring.gpg")
    (should (equal imported-file "/tmp/package-keyring.gpg"))))

(provide 'suderman-packages-test)
;;; suderman-packages-test.el ends here
