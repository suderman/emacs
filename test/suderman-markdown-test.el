;;; suderman-markdown-test.el --- Focused Markdown preview checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-markdown-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'ert)
(require 'suderman-markdown)

(ert-deftest suderman/markdown-preview-render-owns-its-target ()
  (let ((root (make-temp-file "markdown-preview-test-" t)))
    (unwind-protect
        (with-temp-buffer
          (insert "| A |\n|---|\n| B |\n")
          (let ((suderman/markdown-preview-server-root root)
                (suderman/markdown-preview-css "<style>table { width: 100%; }</style>"))
            (cl-letf (((symbol-function 'executable-find) (lambda (_) "/bin/pandoc"))
                      ((symbol-function 'suderman/markdown-preview-server-start)
                       (lambda ()
                         (setq suderman/markdown-preview-server-port 4321)))
                      ((symbol-function 'call-process-region)
                       (lambda (&rest arguments)
                         (with-temp-file (car (last arguments))
                           (insert "<colgroup><col></colgroup>\n<table><tr><td>A</td></tr></table>"))
                         0)))
              (should (equal (suderman/markdown-preview-render)
                             suderman/markdown-preview-file)))
            (should (file-exists-p suderman/markdown-preview-version-file))
            (should (string-prefix-p "http://127.0.0.1:4321/"
                                     suderman/markdown-preview-url))
            (let ((html-file suderman/markdown-preview-file))
              (with-temp-buffer
                (insert-file-contents html-file)
                (should-not (search-forward "<colgroup" nil t))
                (goto-char (point-min))
                (should (search-forward "<div class=\"table-wrapper\">" nil t))))))
      (delete-directory root t))))

(ert-deftest suderman/markdown-preview-buffer-installs-local-lifecycle-hooks ()
  (with-temp-buffer
    (let (browsed)
      (cl-letf (((symbol-function 'suderman/markdown-preview-render)
                 (lambda ()
                   (setq suderman/markdown-preview-url "http://127.0.0.1/preview.html")))
                ((symbol-function 'browse-url)
                 (lambda (url &rest _)
                   (setq browsed url))))
        (suderman/markdown-preview-buffer))
      (should (equal browsed suderman/markdown-preview-url))
      (should (memq #'suderman/markdown-preview-after-save after-save-hook))
      (should (memq #'suderman/markdown-preview-cleanup kill-buffer-hook)))))

(ert-deftest suderman/markdown-preview-cleanup-removes-buffer-files ()
  (with-temp-buffer
    (setq-local suderman/markdown-preview-file (make-temp-file "markdown-preview-"))
    (setq-local suderman/markdown-preview-version-file (make-temp-file "markdown-preview-version-"))
    (setq-local suderman/markdown-preview-url "http://127.0.0.1/preview.html")
    (let ((html-file suderman/markdown-preview-file)
          (version-file suderman/markdown-preview-version-file))
      (suderman/markdown-preview-cleanup)
      (should-not (file-exists-p html-file))
      (should-not (file-exists-p version-file))
      (should-not suderman/markdown-preview-file)
      (should-not suderman/markdown-preview-version-file)
      (should-not suderman/markdown-preview-url))))

(provide 'suderman-markdown-test)
;;; suderman-markdown-test.el ends here
