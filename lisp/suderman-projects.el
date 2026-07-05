;;; suderman-projects.el --- Project-aware file and search commands -*- lexical-binding: t; -*-

;;; Commentary:
;; Thin wrappers around project.el and Consult.  Keeping them here lets pickers,
;; keys, and future project tooling share the same root-detection behavior.

;;; Code:

(require 'project)
(require 'subr-x)

(defun suderman/project-root ()
  "Return current project root, or nil outside a project."
  (when-let ((project (project-current nil)))
    (if (fboundp 'project-root)
        (project-root project)
      (car (project-roots project)))))

(defun suderman/find-file ()
  "Find a file, using recursive home search outside projects."
  (interactive)
  (if (suderman/project-root)
      (call-interactively #'project-find-file)
    (consult-fd (expand-file-name "~"))))

(defun suderman/search-project ()
  "Run ripgrep from the project root, or from default-directory outside a project."
  (interactive)
  (consult-ripgrep (or (suderman/project-root) default-directory)))

(provide 'suderman-projects)
;;; suderman-projects.el ends here
