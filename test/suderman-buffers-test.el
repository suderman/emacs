;;; suderman-buffers-test.el --- Focused IBuffer checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'suderman-buffers)

(ert-deftest suderman/ibuffer-hides-dirvish-support-buffers ()
  (let ((support-predicate (car ibuffer-never-show-predicates))
        (file-preview-predicate (cadr ibuffer-never-show-predicates)))
    (dolist (name '("*dirvish-parent-1@example*"
                    "*dirvish-preview@example*"
                    "*dirvish-shell@example*"
                    " *dirvish-header@example*"
                    " *dirvish-footer@example*"))
      (should (string-match-p support-predicate name)))
    (should (string-match-p file-preview-predicate
                            "PREVIEW :: 09/03/26|15:36:15 :: ideas.org"))
    (should-not (string-match-p support-predicate "*dirvish-dired@example*"))))

;;; suderman-buffers-test.el ends here
