;;; suderman-appearance-test.el --- Focused appearance checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-appearance-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'ert)
(require 'suderman-appearance)

(ert-deftest suderman/selection-faces-wait-for-a-graphical-frame ()
  (let ((frames nil)
        (original-region (face-background 'region nil t)))
    (cl-letf (((symbol-function 'filtered-frame-list)
               (lambda (_predicate) frames))
              ((symbol-function 'suderman/theme-blend)
               (lambda (face _alpha)
                 (if (eq face 'font-lock-function-name-face)
                     "#112233"
                   "#445566"))))
      (suderman/apply-selection-faces)
      (should (equal (face-background 'region nil t) original-region))

      (setq frames (list (selected-frame)))
      (suderman/apply-selection-faces)
      (should (equal (face-background 'region nil t) "#112233"))
      (should (equal (face-background 'secondary-selection nil t) "#445566")))))

(provide 'suderman-appearance-test)
;;; suderman-appearance-test.el ends here
