;;; suderman-org.el --- Org agenda and capture workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep daily Org work centered on the inbox and todo files.

;;; Code:

(require 'use-package)

(defun suderman/org-apply-heading-faces ()
  "Give Org headings a subtle descending size hierarchy."
  (dolist (face-height '((org-level-1 . 1.35)
                         (org-level-2 . 1.22)
                         (org-level-3 . 1.14)
                         (org-level-4 . 1.08)
                         (org-level-5 . 1.04)
                         (org-level-6 . 1.02)
                         (org-level-7 . 1.0)
                         (org-level-8 . 1.0)))
    (set-face-attribute (car face-height) nil :height (cdr face-height))))

(add-hook 'org-mode-hook #'suderman/org-apply-heading-faces)

(use-package org
  :ensure nil
  :init
  (setq org-startup-indented t
        org-directory (expand-file-name "~/org")
        org-agenda-files
        (mapcar (lambda (file) (expand-file-name file org-directory))
                '("inbox.org" "todo.org"))
        org-default-notes-file (expand-file-name "inbox.org" org-directory)
        org-capture-templates
        `(("t" "Todo" entry (file ,org-default-notes-file)
           "* TODO %?\n  %U\n  %a"))
        org-refile-targets '((org-agenda-files :maxlevel . 3))))

(provide 'suderman-org)
;;; suderman-org.el ends here
