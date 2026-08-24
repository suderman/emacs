;;; suderman-org-test.el --- Focused Org workflow checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-org-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'suderman-keys)
(require 'suderman-org)

(ert-deftest suderman/org-uses-inbox-and-todo-files ()
  (let ((directory (expand-file-name "~/org")))
    (should (equal org-directory directory))
    (should (equal org-agenda-files
                   (mapcar (lambda (file) (expand-file-name file directory))
                           '("inbox.org" "todo.org"))))
    (should (equal org-default-notes-file
                   (expand-file-name "inbox.org" directory)))
    (should (equal org-capture-templates
                   `(("t" "Todo" entry (file ,org-default-notes-file)
                      "* TODO %?\n  %U\n  %a"))))
    (should (equal org-refile-targets
                   '((org-agenda-files :maxlevel . 3))))))

(ert-deftest suderman/org-prefix-enters-through-meow-keypad ()
  (should (eq (lookup-key suderman/meow-leader-map (kbd "o"))
              suderman/leader-org-map))
  (should (eq (lookup-key suderman/leader-org-map (kbd "g"))
              #'consult-org-heading))
  (let (called)
    (cl-letf (((symbol-function 'org-agenda)
               (lambda ()
                 (interactive)
                 (setq called t))))
      (with-temp-buffer
        (text-mode)
        (meow-normal-mode 1)
        (execute-kbd-macro (kbd "SPC o a"))
        (should called)))))

(provide 'suderman-org-test)
;;; suderman-org-test.el ends here
