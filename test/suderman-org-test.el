;;; suderman-org-test.el --- Focused Org workflow checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-org-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'suderman-keys)
(require 'suderman-org)

(ert-deftest suderman/org-uses-inbox-and-todo-files ()
  (should org-startup-indented)
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

(ert-deftest suderman/org-indent-toggle-is-under-toggles ()
  (should (eq (lookup-key suderman/leader-toggle-map (kbd "o"))
              #'org-indent-mode)))

(ert-deftest suderman/org-buffers-indent-and-scale-headings ()
  (require 'org)
  (with-temp-buffer
    (org-mode)
    (should (bound-and-true-p org-indent-mode))
    (should (= (face-attribute 'org-level-1 :height nil) 1.35))
    (should (= (face-attribute 'org-level-2 :height nil) 1.22))
    (org-indent-mode -1)
    (should-not (bound-and-true-p org-indent-mode))))

(ert-deftest suderman/org-superstar-prettifies-org-buffers ()
  (with-temp-buffer
    (insert "- item\n")
    (org-mode)
    (font-lock-ensure)
    (should (bound-and-true-p org-superstar-mode))
    (goto-char (point-min))
    (let ((bullet (get-text-property (point) 'display)))
      (should (stringp bullet))
      (should-not (equal bullet "-")))))

(provide 'suderman-org-test)
;;; suderman-org-test.el ends here
