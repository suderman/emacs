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

(ert-deftest suderman/line-number-toggle-preserves-special-buffer-exclusions ()
  (let ((original-state global-display-line-numbers-mode)
        (text-buffer (generate-new-buffer " *suderman-line-numbers-text*"))
        (special-buffer (generate-new-buffer " *suderman-line-numbers-special*")))
    (unwind-protect
        (progn
          (with-current-buffer text-buffer
            (text-mode))
          (with-current-buffer special-buffer
            (special-mode))
          (unless global-display-line-numbers-mode
            (global-display-line-numbers-mode 1)
            (suderman/disable-line-numbers-in-special-buffers))

          (suderman/toggle-line-numbers)
          (should-not global-display-line-numbers-mode)
          (should-not (buffer-local-value 'display-line-numbers-mode text-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode special-buffer))

          (suderman/toggle-line-numbers)
          (should global-display-line-numbers-mode)
          (should (buffer-local-value 'display-line-numbers-mode text-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode special-buffer)))
      (global-display-line-numbers-mode (if original-state 1 -1))
      (when original-state
        (suderman/disable-line-numbers-in-special-buffers))
      (kill-buffer text-buffer)
      (kill-buffer special-buffer))))

(provide 'suderman-appearance-test)
;;; suderman-appearance-test.el ends here
