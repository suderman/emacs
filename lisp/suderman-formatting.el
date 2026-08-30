;;; suderman-formatting.el --- Automatic code formatting -*- lexical-binding: t; -*-

;;; Commentary:
;; Format saved buffers with project treefmt configuration when available,
;; falling back to Apheleia's language-specific formatters elsewhere.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'use-package)

(defvar apheleia-formatter)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)
(declare-function apheleia--get-formatters "apheleia-formatters")
(declare-function apheleia-format-buffer "apheleia")

(defun suderman/formatting--treefmt-root (file)
  "Return FILE's enclosing treefmt project root, or nil."
  (when file
    (locate-dominating-file file "treefmt.nix")))

(cl-defun suderman/formatting-treefmt
    (&key buffer scratch callback &allow-other-keys)
  "Format BUFFER through treefmt, writing the result into SCRATCH.
CALLBACK follows the formatter function protocol used by Apheleia."
  (let ((file (buffer-local-value 'buffer-file-name buffer))
        temp-file)
    (unwind-protect
        (condition-case err
            (let ((root (suderman/formatting--treefmt-root file)))
              (unless root
                (error "No enclosing treefmt.nix for %s" file))
              (setq temp-file
                    (make-nearby-temp-file
                     (expand-file-name ".apheleia-" (file-name-directory file))
                     nil
                     (concat "." (file-name-nondirectory file))))
              (with-current-buffer scratch
                (let ((coding-system-for-write buffer-file-coding-system))
                  (write-region nil nil temp-file nil 'silent)))
              (let ((default-directory root)
                    (exec-path (buffer-local-value 'exec-path buffer))
                    (process-environment
                     (buffer-local-value 'process-environment buffer)))
                (with-temp-buffer
                  (let ((status
                         (process-file
                          "treefmt" nil t nil
                          (file-relative-name temp-file root))))
                    (unless (zerop status)
                      (error "treefmt failed: %s"
                             (string-trim (buffer-string)))))))
              (with-current-buffer scratch
                (let ((coding-system-for-read buffer-file-coding-system))
                  (erase-buffer)
                  (insert-file-contents temp-file)))
              (funcall callback))
          (error (funcall callback err)))
      (when temp-file
        (ignore-errors (delete-file temp-file))))))

(defun suderman/formatting-select-formatter ()
  "Prefer treefmt for the current buffer when its project configures it."
  (if (suderman/formatting--treefmt-root buffer-file-name)
      (setq-local apheleia-formatter 'suderman/treefmt)
    (when (eq apheleia-formatter 'suderman/treefmt)
      (kill-local-variable 'apheleia-formatter))))

(defun suderman/format-buffer ()
  "Format the current buffer using its project-aware formatter."
  (interactive)
  (suderman/formatting-select-formatter)
  (let ((formatters (apheleia--get-formatters)))
    (if formatters
        (apheleia-format-buffer formatters)
      (user-error "No formatter configured for %s" major-mode))))

(use-package apheleia
  :demand t
  :custom
  (apheleia-formatters-respect-indent-level nil)
  :config
  (setf (alist-get 'suderman/treefmt apheleia-formatters)
        #'suderman/formatting-treefmt)
  (setf (alist-get 'alejandra apheleia-formatters)
        '("alejandra" "-q"))
  (setf (alist-get 'nix-ts-mode apheleia-mode-alist) 'alejandra)
  (dolist (mode '(python-mode python-ts-mode))
    (setf (alist-get mode apheleia-mode-alist) 'ruff))
  (setf (alist-get 'markdown-ts-mode apheleia-mode-alist) 'prettier-markdown)
  (setf (alist-get 'sql-mode apheleia-mode-alist) 'sqlfluff)
  (add-hook 'before-save-hook #'suderman/formatting-select-formatter)
  (apheleia-global-mode 1))

;; Enable this last so its buffer setup precedes other global minor modes.
(use-package envrc
  :demand t
  :custom
  (envrc-show-summary-in-minibuffer nil)
  :config
  (envrc-global-mode 1))

(provide 'suderman-formatting)
;;; suderman-formatting.el ends here
