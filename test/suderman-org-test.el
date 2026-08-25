;;; suderman-org-test.el --- Focused Org workflow checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-org-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'suderman-keys)
(require 'suderman-org)

(ert-deftest suderman/org-uses-inbox-and-todo-files ()
  (should (equal org-M-RET-may-split-line '((default . nil))))
  (should org-insert-heading-respect-content)
  (should (eq org-log-done 'time))
  (should org-log-into-drawer)
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

(ert-deftest suderman/org-mouse-cycles-todo-on-left-click ()
  (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
    (with-temp-buffer
      (insert "* TODO item\n")
      (org-mode)
      (font-lock-ensure)
      (goto-char (+ (point-min) 2))
      (let ((map (get-text-property (point) 'keymap)))
        (should (eq (lookup-key map [mouse-1])
                    #'suderman/org-mouse-cycle-todo)))
      (cl-letf (((symbol-function 'mouse-set-point)
                 (lambda (_event) (goto-char (+ (point-min) 2)))))
        (suderman/org-mouse-cycle-todo nil))
      (should (equal (org-get-todo-state) "NEXT"))
      (cl-letf (((symbol-function 'mouse-set-point)
                 (lambda (_event) (goto-char (+ (point-min) 2)))))
        (suderman/org-mouse-cycle-todo nil)
        (should (equal (org-get-todo-state) "DONE"))
        (suderman/org-mouse-cycle-todo nil)
        (should (equal (org-get-todo-state) "TODO"))))))

(ert-deftest suderman/org-mouse-todo-menu-clears-state ()
  (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
    (with-temp-buffer
      (insert "* DONE item\n")
      (org-mode)
      (goto-char (+ (point-min) 2))
      (let ((clear
             (cl-find-if
              (lambda (item)
                (and (vectorp item)
                     (equal (aref item 0) "Clear")))
              (org-mouse-todo-menu "DONE"))))
        (should clear)
        (should (equal (aref clear 1) '(org-todo "")))
        (should (aref clear 2))
        (eval (aref clear 1))
        (should-not (org-get-todo-state))))))

(provide 'suderman-org-test)
;;; suderman-org-test.el ends here
