;;; suderman-reload-test.el --- Focused reload checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-reload-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'seq)
(require 'suderman-reload)

(ert-deftest suderman/reload-loads-keys-after-command-modules ()
  (let ((modules (suderman/reload--config-modules)))
    (should (eq (car (last modules)) 'suderman-keys))
    (should (< (seq-position modules 'suderman-formatting)
               (seq-position modules 'suderman-keys)))
    (should-not (memq 'suderman-reload modules))))

(ert-deftest suderman/reload-no-longer-clears-retired-modal-keys ()
  (should-not (member "M-g" suderman/reload-modal-keys))
  (should-not (member "M-;" suderman/reload-modal-keys)))

(provide 'suderman-reload-test)
;;; suderman-reload-test.el ends here
