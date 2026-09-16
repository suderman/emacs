;;; suderman-org.el --- Org agenda and capture workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep daily Org work centered on a few phone-friendly files.

;;; Code:

(require 'use-package)

(defvar org-done-keywords)

(declare-function consult-org-agenda "consult-org" (&optional match))
(declare-function consult-org-heading "consult-org" (&optional match scope))
(declare-function org-agenda-deadline "org-agenda" (arg &optional time))
(declare-function org-agenda-maybe-redo "org-agenda" ())
(declare-function org-agenda-refile "org-agenda" (&optional goto rfloc no-update))
(declare-function org-agenda-schedule "org-agenda" (arg &optional time))
(declare-function org-agenda-todo "org-agenda" (&optional arg))
(declare-function org-agenda-write "org-agenda" (file &optional open nosettings _))
(declare-function org-todo-list "org-agenda" (&optional arg))
(declare-function org-get-todo-state "org" ())
(declare-function org-todo "org" (&optional arg))
(declare-function org-mouse-todo-menu "org-mouse" (state))

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

(defun suderman/org-auto-save-visited-p ()
  "Return non-nil when the current Org file is safe to save automatically."
  (and (derived-mode-p 'org-mode)
       buffer-file-name
       (file-in-directory-p buffer-file-name org-directory)
       (verify-visited-file-modtime (current-buffer))))

(defun suderman/org-refresh-agenda-after-revert ()
  "Refresh a visible Org Agenda after reverting a synced Org file."
  (when (fboundp 'org-agenda-maybe-redo)
    (save-current-buffer
      (save-selected-window
        (org-agenda-maybe-redo)))))

(defun suderman/org-enable-synced-file-behavior ()
  "Refresh Agenda when the current file under `org-directory' is reverted."
  (when (and buffer-file-name
             (file-in-directory-p buffer-file-name org-directory))
    (add-hook 'after-revert-hook
              #'suderman/org-refresh-agenda-after-revert nil t)))

(add-hook 'org-mode-hook #'suderman/org-enable-synced-file-behavior)

(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'org-mode)
      (suderman/org-enable-synced-file-behavior))))

(defun suderman/org-mouse-cycle-todo (event)
  "Cycle the TODO keyword clicked by EVENT."
  (interactive "e")
  (mouse-set-point event)
  (if (member (org-get-todo-state) org-done-keywords)
      (org-todo "TODO")
    (org-todo)))

(defvar suderman/org-mouse-todo-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'suderman/org-mouse-cycle-todo)
    map))

(defun suderman/org-enable-mouse-todo-cycling ()
  "Make TODO keywords in headlines cycle on mouse-1."
  (font-lock-add-keywords
   nil
   `((,(concat org-outline-regexp-bol
              "\\(" org-todo-regexp "\\)\\(?:[ \t]\\|$\\)")
      1 `(face nil keymap ,suderman/org-mouse-todo-map mouse-face highlight)
      'prepend))
   t))

(add-hook 'org-mode-hook #'suderman/org-enable-mouse-todo-cycling)

(defun suderman/org-inhibit-electric-angle-pairing ()
  "Keep Org structure-template shortcuts from gaining a closing angle bracket."
  (let ((inhibit-predicate electric-pair-inhibit-predicate))
    (setq-local electric-pair-inhibit-predicate
                (lambda (char)
                  (or (eq char ?<)
                      (funcall inhibit-predicate char))))))

(add-hook 'org-mode-hook #'suderman/org-inhibit-electric-angle-pairing)

(defun suderman/org--archived-path-p (file)
  "Return non-nil when FILE is archived by name or directory."
  (or (string-equal (file-name-nondirectory file) "archive.org")
      (member "archive"
              (file-name-split
               (directory-file-name (file-name-directory file))))))

(defun suderman/org--direct-org-files (directory)
  "Return sorted active, non-hidden Org files directly inside DIRECTORY."
  (when (file-directory-p directory)
    (delq nil
          (mapcar (lambda (file)
                    (and (file-regular-p file)
                         (not (suderman/org--archived-path-p file))
                         file))
                  (directory-files directory t "\\`[^.].*\\.org\\'")))))

(defun suderman/org-work-agenda-files (directory)
  "Return agenda files selected by the work hierarchy under DIRECTORY."
  (let (files)
    (dolist (domain (when (file-directory-p directory)
                      (directory-files directory t "\\`[^.]")))
      (when (file-directory-p domain)
        (setq files (append (suderman/org--direct-org-files domain) files))
        (dolist (project (directory-files domain t "\\`[^.]"))
          (when (file-directory-p project)
            (let ((file (expand-file-name
                         (concat (file-name-nondirectory
                                  (directory-file-name project))
                                 ".org")
                         project)))
              (when (and (file-regular-p file)
                         (not (suderman/org--archived-path-p file)))
                (push file files)))))))
    (sort files #'string<)))

(defun suderman/org--call-contextually
    (org-command &optional agenda-command fallback-command)
  "Call the command appropriate for the current Org context."
  (cond
   ((derived-mode-p 'org-agenda-mode)
    (if agenda-command
        (call-interactively agenda-command)
      (user-error "This command requires an Org buffer")))
   ((derived-mode-p 'org-mode)
    (call-interactively org-command))
   (fallback-command
    (call-interactively fallback-command))
   (t
    (user-error "This command requires an Org buffer"))))

(defun suderman/org-deadline ()
  "Set an Org item's deadline, or open the TODO list."
  (interactive)
  (suderman/org--call-contextually
   #'org-deadline #'org-agenda-deadline #'org-todo-list))

(defun suderman/org-export ()
  "Export the current Org buffer or Agenda view."
  (interactive)
  (suderman/org--call-contextually
   #'org-export-dispatch #'org-agenda-write))

(defun suderman/org-heading ()
  "Jump to an Org heading in the current buffer or agenda files."
  (interactive)
  (suderman/org--call-contextually
   #'consult-org-heading #'consult-org-agenda #'consult-org-agenda))

(defun suderman/org-insert-link ()
  "Insert a link in an Org buffer."
  (interactive)
  (suderman/org--call-contextually #'org-insert-link))

(defun suderman/org-refile ()
  "Refile an Org item, or open the TODO list."
  (interactive)
  (suderman/org--call-contextually
   #'org-refile #'org-agenda-refile #'org-todo-list))

(defun suderman/org-schedule ()
  "Schedule an Org item, or open the TODO list."
  (interactive)
  (suderman/org--call-contextually
   #'org-schedule #'org-agenda-schedule #'org-todo-list))

(defun suderman/org-todo ()
  "Change an Org item's TODO state, or open the TODO list."
  (interactive)
  (suderman/org--call-contextually
   #'org-todo #'org-agenda-todo #'org-todo-list))

(defun suderman/org-toggle-checkbox ()
  "Toggle a checkbox in an Org buffer."
  (interactive)
  (suderman/org--call-contextually #'org-toggle-checkbox))

(defun suderman/org-mouse-todo-menu-with-clear (original state)
  "Add a menu item that clears the current TODO state."
  (append (funcall original state)
          (list "--"
                (vector "Clear" '(org-todo "") (and state t)))))

(defun suderman/org-enable-mouse-todo-clearing ()
  "Add the clear action to Org Mouse TODO menus."
  (unless (advice-member-p #'suderman/org-mouse-todo-menu-with-clear
                           #'org-mouse-todo-menu)
    (advice-add 'org-mouse-todo-menu :around
                #'suderman/org-mouse-todo-menu-with-clear)))

(use-package org
  :ensure nil
  :init
  (setq auto-save-visited-interval 3
        auto-save-visited-predicate #'suderman/org-auto-save-visited-p
        org-M-RET-may-split-line '((default . nil))
        org-insert-heading-respect-content t
        org-log-done 'time
        org-log-into-drawer t
        org-startup-indented t
        org-startup-with-link-previews t
        org-tags-column 0
        org-auto-align-tags nil
        org-todo-keywords
        '((sequence "TODO" "PROG" "EVAL" "HOLD" "|" "DONE"))
        org-directory (expand-file-name "~/org")
        org-attach-id-dir (expand-file-name ".attach/" org-directory)
        org-attach-use-inheritance t
        org-agenda-files
        (append
         (mapcar (lambda (file) (expand-file-name file org-directory))
                 '("inbox.org" "todo.org" "routines.org"))
         (suderman/org--direct-org-files
          (expand-file-name "calendar" org-directory))
         (suderman/org--direct-org-files
          (expand-file-name "family" org-directory))
         (suderman/org-work-agenda-files
          (expand-file-name "work" org-directory)))
        org-default-notes-file (expand-file-name "inbox.org" org-directory)
        org-capture-templates
        `(("t" "Task" entry (file ,org-default-notes-file)
            "* TODO %?\n  %U\n  %a")
          ("n" "Note" entry (file ,org-default-notes-file)
            "* %?\n  %U\n  %a")
          ("i" "Idea" entry (file ,(expand-file-name "ideas.org" org-directory))
            "* %?\n  %U\n  %a"))
        org-refile-targets
        (mapcar (lambda (file)
                  (cons (expand-file-name file org-directory) '(:maxlevel . 3)))
                '("todo.org" "routines.org" "ideas.org"))
        org-archive-location "archive.org::"
        org-archive-file-header-format nil
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-deadline-if-done t
        org-agenda-custom-commands
        '(("d" "Dashboard"
           ((agenda "" ((org-agenda-span 7)))
            (todo "PROG|EVAL|HOLD")
            (todo "TODO")))))
  (auto-save-visited-mode 1))

(use-package org-tempo
  :ensure nil
  :after org
  :demand t
  :config
  (dolist (template '(("el" . "src emacs-lisp")
                      ("sh" . "src shell")
                      ("py" . "src python")
                      ("js" . "src js")
                      ("ts" . "src typescript")
                      ("php" . "src php")
                      ("html" . "src html")
                      ("twig" . "src twig")
                      ("css" . "src css")
                      ("scss" . "src scss")
                      ("nix" . "src nix")
                      ("lua" . "src lua")
                      ("sql" . "src sql")
                      ("json" . "src json")
                      ("yaml" . "src yaml")
                      ("xml" . "src xml")
                      ("md" . "src markdown")
                      ("conf" . "src conf")
                      ("docker" . "src dockerfile")))
    (add-to-list 'org-structure-template-alist template))
  (add-to-list 'org-src-lang-modes '("nix" . nix-ts)))

(use-package ob
  :ensure nil
  :after org
  :demand t
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (shell . t)
     (python . t)
     (js . t)
     (sqlite . t))))

(use-package org-superstar
  :after org
  :hook (org-mode . org-superstar-mode))

(use-package org-mouse
  :ensure nil
  :demand t
  :config
  (suderman/org-enable-mouse-todo-clearing))

(provide 'suderman-org)
;;; suderman-org.el ends here
