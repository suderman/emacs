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

(ert-deftest suderman/reload-clears-config-function-keys ()
  (dolist (key '("<f5>" "<f6>" "<f9>"))
    (should (member key suderman/reload-modal-keys))))

(ert-deftest suderman/pull-config-runs-git-in-user-emacs-directory ()
  (let ((user-emacs-directory "/tmp/emacs-config/")
        call)
    (cl-letf (((symbol-function 'async-shell-command)
               (lambda (command output-buffer)
                 (setq call (list command output-buffer default-directory)))))
      (suderman/pull-config)
      (should (equal call
                     '("git pull" "*Emacs config pull*"
                       "/tmp/emacs-config/"))))))

(provide 'suderman-reload-test)
;;; suderman-reload-test.el ends here
