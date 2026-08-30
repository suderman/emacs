;;; run.el --- Run all Suderman ERT checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Run with: emacs --batch -l init.el -l test/run.el

;;; Code:

(require 'ert)

(let ((test-directory (file-name-directory load-file-name)))
  (dolist (file (directory-files test-directory t "-test\\.el\\'"))
    (load file nil 'nomessage)))

(ert-run-tests-batch-and-exit)

;;; run.el ends here
