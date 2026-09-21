;;; run.el --- Run Suderman's focused ERT checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Run ERT only with: emacs --batch -l init.el -l test/run.el
;; Run the complete safety suite with: ./test/run.sh

;;; Code:

(require 'ert)

(let ((test-directory (file-name-directory load-file-name)))
  (dolist (file (directory-files test-directory t "-test\\.el\\'"))
    (load file nil 'nomessage)))

(ert-run-tests-batch-and-exit)

;;; run.el ends here
