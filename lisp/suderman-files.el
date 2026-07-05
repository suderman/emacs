;;; suderman-files.el --- File tree and directory browsing -*- lexical-binding: t; -*-

;;; Commentary:
;; Explorer-style tools and their helper commands.  Project/file picker logic is
;; elsewhere; this module is about moving around directory trees once opened.

;;; Code:

(require 'use-package)
(require 'suderman-evil)
(require 'suderman-windows)

(defun suderman/treemacs-root-for-file (file)
  "Return a Treemacs project root for FILE, preferring the nearest Git root."
  (file-name-as-directory
   (expand-file-name
    (or (locate-dominating-file file ".git")
        (file-name-directory file)))))

(defun suderman/treemacs-project-name-candidates (root)
  "Return unique Treemacs project name candidates for ROOT."
  (let* ((dir (directory-file-name root))
         (base (file-name-nondirectory dir))
         (parent-dir (file-name-directory dir))
         (parent (when parent-dir
                   (file-name-nondirectory
                    (directory-file-name parent-dir))))
         (candidates (list base
                           (when (and parent (not (string= parent "")))
                             (format "%s (%s)" base parent))
                           (abbreviate-file-name root)
                           root))
         names)
    (dolist (name candidates (nreverse names))
      (when (and name (not (member name names)))
        (push name names)))))

(defun suderman/treemacs-add-project-root (root)
  "Add ROOT to the current Treemacs workspace if possible."
  (let (result)
    (catch 'done
      (dolist (name (suderman/treemacs-project-name-candidates root))
        (let ((attempt (treemacs-do-add-project-to-workspace root name)))
          (setq result attempt)
          (cond
           ((memq (car-safe attempt) '(success duplicate-project includes-project))
            (throw 'done attempt))
           ((memq (car-safe attempt) '(duplicate-name invalid-name))
            nil)
           ((eq (car-safe attempt) 'invalid-path)
            (user-error "Cannot add Treemacs project %s: %s" root (cadr attempt)))))))
    (unless result
      (user-error "Cannot add Treemacs project %s" root))
    result))

(defun suderman/treemacs-toggle ()
  "Toggle/focus Treemacs, adding the current project before revealing the file."
  (interactive)
  (cond
   ((derived-mode-p 'treemacs-mode)
    (treemacs))
   ((not buffer-file-name)
    (treemacs-select-window))
   (t
    (require 'treemacs)
    (let ((file (treemacs-canonical-path (expand-file-name buffer-file-name))))
      (unless (treemacs-is-path file :in-workspace)
        (suderman/treemacs-add-project-root
         (suderman/treemacs-root-for-file buffer-file-name)))
      (unless (treemacs-is-path file :in-workspace)
        (user-error "%s does not fall under any Treemacs project" file))
      (treemacs-find-file)
      (treemacs-select-window)))))

(use-package treemacs
  :after evil
  :commands (treemacs treemacs-find-file treemacs-select-window)
  :init
  ;; Set this before any Treemacs buffer is created.
  (evil-set-initial-state 'treemacs-mode 'emacs)
  (setq treemacs-width 32
        treemacs-follow-after-init t
        treemacs-is-never-other-window t)
  :config
  ;; Do not enable treemacs-evil here: Treemacs' own keymap handles mouse input
  ;; correctly in emacs state, including double-click open/toggle.
  (add-hook 'treemacs-mode-hook #'evil-emacs-state)
  (define-key treemacs-mode-map (kbd "j") #'treemacs-next-line)
  (define-key treemacs-mode-map (kbd "k") #'treemacs-previous-line)
  (define-key treemacs-mode-map (kbd "M-h") #'suderman/window-left-or-treemacs)
  (define-key treemacs-mode-map (kbd "M-j") #'windmove-down)
  (define-key treemacs-mode-map (kbd "M-k") #'windmove-up)
  (define-key treemacs-mode-map (kbd "M-l") #'windmove-right)
  (treemacs-follow-mode 1)
  (treemacs-filewatch-mode 1))

(use-package dirvish
  :commands (dirvish dirvish-side)
  :init
  (setq dirvish-use-mode-line t)
  :config
  (dirvish-override-dired-mode 1))

(provide 'suderman-files)
;;; suderman-files.el ends here
