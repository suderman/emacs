;;; suderman-projects.el --- Org work projects in project.el -*- lexical-binding: t; -*-

;;; Commentary:
;; An Org work directory defines the project; matching local source and data
;; directories extend it when present on this machine.

;;; Code:

(require 'cl-lib)
(require 'project)

(defvar suderman/project-org-root (expand-file-name "~/org/work/")
  "Directory containing canonical Org work projects.")
(defvar suderman/project-source-root (expand-file-name "~/src/")
  "Directory containing optional project source directories.")
(defvar suderman/project-data-root (expand-file-name "~/data/work/")
  "Directory containing optional project data directories.")

(cl-defstruct (suderman/project (:constructor suderman/project-create (domain name)))
  domain name)

(defun suderman/project--directory (base project)
  "Return PROJECT's directory below BASE."
  (file-name-as-directory
   (expand-file-name
    (concat (suderman/project-domain project) "/"
            (suderman/project-name project)) base)))

(defun suderman/project-try-work (directory)
  "Find an Org work project containing DIRECTORY, or return nil."
  (let ((directory (file-name-as-directory (expand-file-name directory)))
        result)
    (dolist (base (list suderman/project-org-root
                        suderman/project-source-root
                        suderman/project-data-root))
      (let ((base (file-name-as-directory (expand-file-name base))))
        (when (and (not result) (string-prefix-p base directory))
          (let* ((parts (split-string (substring directory (length base)) "/" t))
                 (project (and (>= (length parts) 2)
                               (suderman/project-create (car parts) (cadr parts)))))
            (when (and project
                       (file-directory-p (suderman/project--directory
                                          suderman/project-org-root project))
                       (file-directory-p (suderman/project--directory base project)))
              (setq result project))))))
    result))

(cl-defmethod project-root ((project suderman/project))
  (suderman/project--directory suderman/project-org-root project))

(cl-defmethod project-name ((project suderman/project))
  (concat (suderman/project-domain project) "/"
          (suderman/project-name project)))

(cl-defmethod project-external-roots ((project suderman/project))
  (cl-remove-if-not #'file-directory-p
                    (mapcar (lambda (base) (suderman/project--directory base project))
                            (list suderman/project-source-root
                                  suderman/project-data-root))))

(cl-defmethod project-buffers ((project suderman/project))
  (let ((roots (cons (project-root project) (project-external-roots project))))
    (cl-remove-if-not
     (lambda (buffer)
       (let ((path (buffer-local-value 'buffer-file-name buffer)))
         (setq path (or path (buffer-local-value 'default-directory buffer)))
         (and path
              (cl-some (lambda (root)
                         (string-prefix-p root (expand-file-name path)))
                       roots))))
     (buffer-list))))

(cl-defmethod project-files ((project suderman/project) &optional dirs)
  ;; Normal file commands include Org and source, but never scan heavy data
  ;; unless the caller explicitly asks for that directory.
  (let* ((root (project-root project))
         (source (suderman/project--directory suderman/project-source-root project))
         (dirs (if (or (null dirs) (equal dirs (list root)))
                   (append (list root) (and (file-directory-p source) (list source)))
                 dirs))
         (project-files-relative-names (and project-files-relative-names
                                            (= (length dirs) 1))))
    (cl-call-next-method project dirs)))

(defun suderman/project--existing-companion (base)
  "Return current project's directory under BASE, or report its absence."
  (let* ((project (project-current t))
         (directory (and (suderman/project-p project)
                         (suderman/project--directory base project))))
    (unless (and directory (file-directory-p directory))
      (user-error "No local project directory under %s" base))
    directory))

(defun suderman/project-source-dired ()
  "Open the current project's local source directory in Dired."
  (interactive)
  (dired (suderman/project--existing-companion suderman/project-source-root)))

(defun suderman/project-data-dired ()
  "Open the current project's local data directory in Dired."
  (interactive)
  (dired (suderman/project--existing-companion suderman/project-data-root)))

(defun suderman/project-source-shell ()
  "Open a shell in the current project's local source directory."
  (interactive)
  (let* ((project (project-current t))
         (default-directory (suderman/project--existing-companion
                             suderman/project-source-root)))
    (shell (format "*%s-source-shell*" (project-name project)))))

(add-hook 'project-find-functions #'suderman/project-try-work)

(provide 'suderman-projects)
;;; suderman-projects.el ends here
