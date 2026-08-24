;;; suderman-org.el --- Org agenda and capture workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep daily Org work centered on the inbox and todo files.

;;; Code:

(require 'use-package)

(use-package org
  :ensure nil
  :init
  (setq org-directory (expand-file-name "~/org")
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
