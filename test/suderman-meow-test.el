;;; suderman-meow-test.el --- Focused Meow checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-meow-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'ert)
(require 'suderman-meow)

(ert-deftest suderman/meow-insert-dispatches-by-state ()
  (with-temp-buffer
    (let (calls)
      (cl-letf (((symbol-function 'meow-beacon-insert)
                 (lambda () (setq calls (append calls '(beacon)))))
                ((symbol-function 'meow-insert)
                 (lambda () (setq calls (append calls '(insert)))))
                ((symbol-function 'suderman/meow--cancel-active-selection)
                 (lambda () (setq calls (append calls '(cancel))))))
        (setq-local meow-beacon-mode t)
        (suderman/meow-insert)
        (should (equal calls '(beacon)))

        (setq calls nil)
        (setq-local meow-beacon-mode nil)
        (suderman/meow-insert)
        (should (equal calls '(cancel insert)))))))

(ert-deftest suderman/meow-keypad-runs-without-beacon-fanout ()
  (with-temp-buffer
    (let* ((overlay (make-overlay (point-min) (point-min)))
           (meow--beacon-overlays (list overlay))
           seen)
      (unwind-protect
          (cl-letf (((symbol-function 'meow-keypad)
                     (lambda () (setq seen meow--beacon-overlays))))
            (suderman/meow-keypad-once)
            (should-not seen)
            (should (equal meow--beacon-overlays (list overlay))))
        (delete-overlay overlay)))))

(ert-deftest suderman/meow-beacon-space-uses-one-shot-keypad ()
  (should (eq (lookup-key meow-beacon-state-keymap (kbd "SPC"))
              #'suderman/meow-keypad-once)))

(ert-deftest suderman/meow-parentheses-extend-selection ()
  (should (eq (lookup-key meow-normal-state-keymap (kbd "("))
              #'meow-left-expand))
  (should (eq (lookup-key meow-normal-state-keymap (kbd ")"))
              #'meow-right-expand))
  (should-not (lookup-key meow-normal-state-keymap (kbd "<")))
  (should-not (lookup-key meow-normal-state-keymap (kbd ">"))))

(ert-deftest suderman/treemacs-entrypoints-use-s-only ()
  (should (eq (lookup-key meow-normal-state-keymap (kbd "S"))
              #'suderman/treemacs-toggle))
  (should (eq (lookup-key meow-motion-state-keymap (kbd "S"))
              #'suderman/treemacs-toggle))
  (should (eq (lookup-key meow-motion-state-keymap (kbd "h"))
              #'meow-left))
  (should (eq (lookup-key ibuffer-mode-map (kbd "S"))
              #'suderman/ibuffer-toggle-treemacs))
  (should (eq (lookup-key ibuffer-mode-map (kbd "h"))
              #'suderman/ibuffer-toggle))
  (should (eq (lookup-key ibuffer-mode-map (kbd "l"))
              #'suderman/ibuffer-open-with-treemacs))
  (should-not (eq (lookup-key ibuffer-mode-map (kbd "H"))
                  #'suderman/ibuffer-toggle-treemacs))
  (should-not (eq (lookup-key ibuffer-mode-map (kbd "SPC"))
                  #'suderman/ibuffer-toggle-treemacs)))

(provide 'suderman-meow-test)
;;; suderman-meow-test.el ends here
