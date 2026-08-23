;;; suderman-windows-test.el --- Focused window resize checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-windows-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'suderman-windows)

(ert-deftest suderman/resize-window-follows-direction ()
  (save-window-excursion
    (delete-other-windows)
    (let ((left (selected-window))
          (right (split-window-right)))
      (select-window left)
      (let ((width (window-total-width left)))
        (suderman/resize-window-right)
        (should (> (window-total-width left) width)))
      (balance-windows)
      (select-window right)
      (let ((width (window-total-width right)))
        (suderman/resize-window-left)
        (should (> (window-total-width right) width))))
    (delete-other-windows)
    (let ((top (selected-window))
          (bottom (split-window-below)))
      (select-window top)
      (let ((height (window-total-height top)))
        (suderman/resize-window-down)
        (should (> (window-total-height top) height)))
      (balance-windows)
      (select-window bottom)
      (let ((height (window-total-height bottom)))
        (suderman/resize-window-up)
        (should (> (window-total-height bottom) height))))))

(provide 'suderman-windows-test)
;;; suderman-windows-test.el ends here
