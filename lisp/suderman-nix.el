;;; suderman-nix.el --- Embedded languages in Nix strings -*- lexical-binding: t; -*-

;;; Commentary:
;; Fontify Nix indented strings according to their preceding language comment.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'use-package)

(defconst suderman/nix-embedded-languages '(bash elisp html lua python))

;; Tree-sitter capture names cannot contain the usual `suderman/' separator.
(defun suderman--nix-fontify-included-ranges
    (node face override start end)
  "Fontify NODE with FACE only inside its parser's included ranges."
  (dolist (range (treesit-parser-included-ranges
                  (treesit-node-parser node)))
    (let ((range-start (max (treesit-node-start node) (car range)))
          (range-end (min (treesit-node-end node) (cdr range))))
      (when (< range-start range-end)
        (treesit-fontify-with-override
         range-start range-end face override start end)))))

(defun suderman--nix-fontify-embedded-default
    (node override start end &rest _)
  "Remove the host string face from embedded parser NODE."
  (when (null (treesit-node-parent node))
    (suderman--nix-fontify-included-ranges
     node 'default override start end)))

(defun suderman--nix-fontify-embedded-string
    (node override start end &rest _)
  "Fontify embedded string NODE without covering Nix interpolation."
  (suderman--nix-fontify-included-ranges
   node 'font-lock-string-face override start end))

(defun suderman--nix-fontify-elisp-symbol (node override start end &rest _)
  "Fontify Elisp symbol NODE like `emacs-lisp-mode'."
  (let* ((symbol (intern-soft (treesit-node-text node t)))
         (parent (treesit-node-parent node))
         (function-position
          (and parent
               (equal (treesit-node-type parent) "list")
               (treesit-node-eq node (treesit-node-child parent 0 t))))
         (face
          (cond
           ((and function-position
                 (memq symbol '(cl-assert cl-check-type error signal
                                         user-error warn)))
            'font-lock-warning-face)
           ((and function-position
                 symbol
                 (or (special-form-p symbol) (macrop symbol))
                 (not (get symbol 'no-font-lock-keyword)))
            'font-lock-keyword-face)
           (t 'default))))
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     face override start end)))

(defun suderman/nix-embedded-language (node)
  "Return the supported language named by Nix comment NODE."
  (let ((language
         (intern-soft
          (string-trim
           (string-remove-prefix "#" (treesit-node-text node t))))))
    (when (eq language 'sh)
      (setq language 'bash))
    (and (memq language suderman/nix-embedded-languages)
         (treesit-language-available-p language)
         language)))

(defun suderman--nix-embedded-ranges (node offset)
  "Return all string fragments in NODE as one range group using OFFSET."
  (treesit-query-range
   node '((string_fragment) @content) nil nil offset))

(defun suderman--nix-embedded-query-source (query)
  "Make string captures in compiled QUERY respect included ranges."
  (let ((source (treesit-query-source query)))
    (cl-labels ((replace-capture
                 (form)
                 (cond
                  ((eq form '@font-lock-string-face)
                   '@suderman--nix-fontify-embedded-string)
                  ((consp form)
                   (cons (replace-capture (car form))
                         (replace-capture (cdr form))))
                  ((vectorp form)
                   (apply #'vector (mapcar #'replace-capture form)))
                  ((stringp form)
                   (string-replace
                    "@font-lock-string-face"
                    "@suderman--nix-fontify-embedded-string"
                    form))
                  (t form))))
      (replace-capture source))))

(defun suderman/nix-language-at-point (position)
  "Return the Tree-sitter language at POSITION in a Nix buffer."
  (let ((node (treesit-node-at position 'nix)))
    (while (and node (not (equal (treesit-node-type node) "interpolation")))
      (setq node (treesit-node-parent node)))
    (if node
        'nix
      (treesit-language-at-point-default position))))

(defun suderman/nix-embedded-font-lock-settings ()
  "Return font-lock settings for supported languages in Nix strings."
  (require 'html-ts-mode)
  (require 'lua-ts-mode)
  (require 'python)
  (require 'sh-script)
  (let* ((elisp-query
          (with-temp-buffer
            (insert-file-contents
             (expand-file-name "assets/elisp-highlights.scm"
                               user-emacs-directory))
            (buffer-string)))
         (settings
          `((bash . ,(symbol-value 'sh-mode--treesit-settings))
            (elisp . ,(treesit-font-lock-rules
                       :language 'elisp
                       :feature 'embedded
                       :override t
                       elisp-query))
            (html . ,(symbol-value 'html-ts-mode--font-lock-settings))
            (lua . ,(symbol-value 'lua-ts--font-lock-settings))
            (python . ,(symbol-value 'python--treesit-settings)))))
    (cl-mapcan
     (lambda (entry)
       (append
        (treesit-font-lock-rules
         :language (car entry)
         :feature 'embedded
         :override t
         '((_) @suderman--nix-fontify-embedded-default))
        (cl-mapcan
         (lambda (setting)
           (treesit-font-lock-rules
            :language (car entry)
            :feature 'embedded
            :override t
            (suderman--nix-embedded-query-source
             (treesit-font-lock-setting-query setting))))
         (cdr entry))))
     settings)))

(defun suderman/nix-embedded-languages-setup ()
  "Fontify Nix indented strings according to the preceding comment."
  (setq-local treesit-font-lock-level 4)
  (unless (memq 'embedded (apply #'append treesit-font-lock-feature-list))
    (setq-local treesit-primary-parser
                (or treesit-primary-parser (car (treesit-parser-list))))
    (setq-local treesit-range-settings
                (treesit-range-rules
                 :embed #'suderman/nix-embedded-language
                 :host 'nix
                 :local t
                 :range-fn #'suderman--nix-embedded-ranges
                 "((comment) @language
                    .
                    (indented_string_expression) @content)"))
    (setq-local treesit-language-at-point-function
                #'suderman/nix-language-at-point)
    (setq-local treesit-font-lock-settings
                (append treesit-font-lock-settings
                        (suderman/nix-embedded-font-lock-settings)))
    (setq-local treesit-font-lock-feature-list
                (treesit-merge-font-lock-feature-list
                 treesit-font-lock-feature-list '((embedded))))
    (treesit-update-ranges)
    (treesit-font-lock-recompute-features)
    (font-lock-flush)))

(unless (eq system-type 'android)
  (use-package nix-ts-mode
    :mode "\\.nix\\'"
    :hook (nix-ts-mode . suderman/nix-embedded-languages-setup)))

(provide 'suderman-nix)
;;; suderman-nix.el ends here
