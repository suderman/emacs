;;; suderman-languages-test.el --- Language mode checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'suderman-languages)

(ert-deftest suderman/treesit-auto-uses-static-file-associations ()
  (should-not global-treesit-auto-mode)
  (should-not
   (advice-member-p #'treesit-auto--set-major-remap #'set-auto-mode-0)))

(ert-deftest suderman/treesit-auto-keeps-extension-based-modes ()
  (dolist (case '(("example.py" . python-ts-mode)
                  ("example.sh" . bash-ts-mode)
                  ("example.yaml" . yaml-ts-mode)))
    (should (eq (assoc-default (car case) auto-mode-alist #'string-match)
                (cdr case)))))

(provide 'suderman-languages-test)
;;; suderman-languages-test.el ends here
