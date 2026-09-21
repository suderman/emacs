;;; suderman-org.el --- Org agenda and capture workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep daily Org work centered on a few phone-friendly files.

;;; Code:

(require 'use-package)
(require 'cl-lib)
(require 'face-remap)

(defvar org-done-keywords)
(defvar org-not-done-keywords)
(defvar org-archive-subtree-save-file-p)
(defvar org-tag-line-re)
(defvar org-highlight-links)
(defvar org-font-lock-extra-keywords)
(defvar font-lock-beg)

(declare-function consult-org-agenda "consult-org" (&optional match))
(declare-function consult-org-heading "consult-org" (&optional match scope))
(declare-function org-agenda "org-agenda" (&optional arg keys restriction))
(declare-function org-agenda-archive "org-agenda" (&optional arg))
(declare-function org-agenda-deadline "org-agenda" (arg &optional time))
(declare-function org-agenda-goto-today "org-agenda" ())
(declare-function org-agenda-maybe-redo "org-agenda" ())
(declare-function org-agenda-refile "org-agenda" (&optional goto rfloc no-update))
(declare-function org-agenda-schedule "org-agenda" (arg &optional time))
(declare-function org-agenda-todo "org-agenda" (&optional arg))
(declare-function org-agenda-write "org-agenda" (file &optional open nosettings _))
(declare-function org-todo-list "org-agenda" (&optional arg))
(declare-function org-get-todo-state "org" ())
(declare-function org-todo "org" (&optional arg))
(declare-function org-mouse-todo-menu "org-mouse" (state))

(defun suderman/org-apply-heading-faces (&optional _theme)
  "Scale Org headings and give tags a separate neutral color."
  (dolist (face-height '((org-level-1 . 1.35)
                         (org-level-2 . 1.22)
                         (org-level-3 . 1.14)
                         (org-level-4 . 1.08)
                         (org-level-5 . 1.04)
                         (org-level-6 . 1.02)
                         (org-level-7 . 1.0)
                         (org-level-8 . 1.0)))
    (set-face-attribute (car face-height) nil :height (cdr face-height)))
  (set-face-attribute 'org-tag nil :foreground 'unspecified
                      :inherit 'font-lock-doc-face)
  (set-face-attribute 'org-checkbox nil :foreground 'unspecified
                      :inherit '(font-lock-type-face bold)))

(add-hook 'org-mode-hook #'suderman/org-apply-heading-faces)
(add-hook 'enable-theme-functions #'suderman/org-apply-heading-faces)

(defun suderman-org-unload-function ()
  "Remove theme callbacks before `suderman-org' functions are unloaded."
  ;; `unload-feature' does not recognize `enable-theme-functions' as a hook.
  (remove-hook 'enable-theme-functions #'suderman/org-apply-heading-faces)
  nil)

(defun suderman/org-enable-tag-face ()
  "Keep heading tags distinct even when a completed heading gets its own face."
  (font-lock-add-keywords
   nil `((,org-tag-line-re (1 'font-lock-doc-face prepend))) t))

(add-hook 'org-mode-hook #'suderman/org-enable-tag-face)

(defun suderman/org-enable-date-faces ()
  "Keep timestamps distinct from headings and mute inactive timestamps."
  ;; Keep Org's matcher, after heading states but before code and comments.
  (setq org-font-lock-extra-keywords
        (cl-loop for rule in (assq-delete-all 'org-activate-dates
                                             org-font-lock-extra-keywords)
                 when (and (memq 'date org-highlight-links)
                           (eq (car-safe rule) 'org-font-lock-add-priority-faces))
                 collect '(org-activate-dates
                           (0 (if (eq (char-after (match-beginning 0)) ?\[)
                                  '(font-lock-doc-face org-date)
                                'org-date)
                              prepend))
                 collect rule)))

(add-hook 'org-font-lock-set-keywords-hook #'suderman/org-enable-date-faces)

(defface suderman/org-drawer-block
  '((t (:extend t)))
  "Source-block background for property and logbook drawers."
  :group 'org-faces)

(defface suderman/org-drawer-label
  '((t (:inherit org-block-begin-line :extend nil)))
  "Muted compact face for property and logbook drawer labels."
  :group 'org-faces)

;; Clean up the former theme-derived drawer faces after a hot reload.
(remove-hook 'org-mode-hook 'suderman/org-apply-drawer-faces)
(remove-hook 'enable-theme-functions 'suderman/org-apply-drawer-faces)

(defun suderman/org-apply-block-face-geometry ()
  "Keep folded block openers compact and expanded block endings full-width."
  (when (facep 'org-block-begin-line)
    (set-face-extend 'org-block-begin-line nil)
    (set-face-extend 'org-block-end-line t)))

(add-hook 'org-mode-hook #'suderman/org-apply-block-face-geometry)
(suderman/org-apply-block-face-geometry)

(defun suderman/org-fontify-source-block-openers (limit)
  "Extend expanded source-block openers, but not folded ones, to LIMIT."
  (let ((case-fold-search t))
    (catch 'found
      (while (re-search-forward
              "^[ \t]*#\\+begin_src\\(?:[ \t].*\\)?$" limit t)
        (let* ((begin (match-beginning 0))
               (element (save-excursion (goto-char begin) (org-element-at-point))))
          (when (and (eq (org-element-type element) 'src-block)
                     (= begin (org-element-property :post-affiliated element)))
            (let ((newline (line-end-position)))
              (when (< newline (point-max))
                ;; Folding hides the extending newline and leaves the compact
                ;; `org-block-begin-line' face visible.
                (add-face-text-property newline (1+ newline) 'org-block t))
              (goto-char (min (1+ newline) (point-max)))
              (throw 'found t)))))
      nil)))

(defun suderman/org-fontify-drawer-blocks (limit)
  "Style real PROPERTIES and LOGBOOK drawers like source blocks to LIMIT."
  (let ((case-fold-search t))
    (catch 'found
      (while (re-search-forward "^[ \t]*:\\(PROPERTIES\\|LOGBOOK\\):[ \t]*$" limit t)
        (let* ((begin (match-beginning 0))
               (element (save-excursion (goto-char begin) (org-element-at-point))))
          ;; Let Org reject drawer-like text inside source/example blocks.
          (when (and (memq (org-element-type element) '(property-drawer drawer))
                     (= begin (org-element-property :post-affiliated element)))
            (let* ((end-bounds
                    (save-excursion
                      (re-search-forward "^[ \t]*:END:[ \t]*$"
                                         (org-element-property :end element) t)
                      (let ((end-begin (match-beginning 0)))
                        ;; Include the delimiter even without a final newline.
                        (forward-line 1)
                        (cons end-begin (point)))))
                   (end-begin (car end-bounds))
                   (end (cdr end-bounds))
                   (body-begin (save-excursion
                                 (goto-char begin)
                                 (line-end-position))))
              ;; Folding hides the extending newline, leaving only the compact
              ;; label.  Expanded drawers show the full-width body underneath.
              (add-face-text-property body-begin end
                                      'suderman/org-drawer-block)
              (add-face-text-property begin body-begin
                                      'suderman/org-drawer-label)
              (add-face-text-property end-begin end 'org-block-end-line)
              (put-text-property begin end 'font-lock-multiline t)
              (goto-char end)
              (throw 'found t)))))
      nil)))

(defun suderman/org-extend-drawer-region ()
  "Start partial fontification at the enclosing drawer's opening line."
  ;; A newly typed :END: has no old font-lock-multiline range to extend.
  (save-excursion
    (goto-char font-lock-beg)
    (when-let* ((drawer (org-element-lineage (org-element-at-point)
                                           '(drawer property-drawer) t))
                (begin (org-element-property :post-affiliated drawer)))
      (when (< begin font-lock-beg)
        (setq font-lock-beg begin)
        t))))

(defconst suderman/org-block-font-lock-keywords
  '((suderman/org-fontify-source-block-openers)
    (suderman/org-fontify-drawer-blocks)))

(defun suderman/org-enable-drawer-blocks ()
  "Append collapsible block backgrounds after Org's fontification."
  (font-lock-remove-keywords nil suderman/org-block-font-lock-keywords)
  (font-lock-add-keywords nil suderman/org-block-font-lock-keywords t)
  (add-hook 'font-lock-extend-region-functions
            #'suderman/org-extend-drawer-region nil t))

(add-hook 'org-mode-hook #'suderman/org-enable-drawer-blocks)

(defun suderman/org-refresh-drawer-blocks ()
  "Install current block styling and refontify existing Org buffers."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (suderman/org-enable-drawer-blocks)
        (font-lock-flush)))))

(suderman/org-refresh-drawer-blocks)

(defvar suderman/system-style)
(defvar suderman/variable-font-scale)
(defvar-local suderman/org-fixed-pitch-cookies nil)

(defun suderman/org-enable-mixed-pitch ()
  "Use proportional prose with fixed-width structural text in GUI Org buffers."
  (when (and (display-graphic-p)
             (plist-get suderman/system-style :variable-font)
             (find-font (font-spec :family
                                  (plist-get suderman/system-style :variable-font))))
    (variable-pitch-mode 1)
    (mapc #'face-remap-remove-relative suderman/org-fixed-pitch-cookies)
    ;; Base16 gives block delimiters their own faces instead of org-meta-line.
    ;; Cancel the prose scale so structural text keeps the default font size.
    ;; Tags are not column-aligned here.  Links and TODO colors stay theme-owned.
    (setq suderman/org-fixed-pitch-cookies
          (mapcar (lambda (face)
                    (face-remap-add-relative
                     face 'fixed-pitch
                     :height (/ 1.0 suderman/variable-font-scale)))
                  '(org-block org-block-begin-line suderman/org-drawer-label
                    org-code org-verbatim org-table org-meta-line
                    org-special-keyword org-document-info-keyword
                    org-property-value org-drawer org-checkbox org-date
                    org-todo org-done org-tag org-indent)))))

(defun suderman/org-refresh-mixed-pitch (&optional frame)
  "Enable mixed typography in existing Org buffers when GUI FRAME is created."
  (when (display-graphic-p frame)
    (with-selected-frame (or frame (selected-frame))
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (derived-mode-p 'org-mode)
            (suderman/org-enable-mixed-pitch)))))))

(add-hook 'org-mode-hook #'suderman/org-enable-mixed-pitch)
(add-hook 'after-make-frame-functions #'suderman/org-refresh-mixed-pitch)
(suderman/org-refresh-mixed-pitch)

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

(defun suderman/org-context-files ()
  "Return active Org files from life, notes, and work contexts."
  (append
   (suderman/org--direct-org-files (expand-file-name "life" org-directory))
   (suderman/org--direct-org-files (expand-file-name "notes" org-directory))
   (suderman/org-work-agenda-files (expand-file-name "work" org-directory))))

(defun suderman/org-refile-files ()
  "Return valid refile destinations, including the current Org file."
  (let* ((current (and buffer-file-name (expand-file-name buffer-file-name)))
         (inbox (expand-file-name "inbox.org" org-directory))
         (calendar (expand-file-name "calendar" org-directory)))
    (delete-dups
     (append
      (and current
           (not (equal current inbox))
           (not (file-in-directory-p current calendar))
           (not (suderman/org--archived-path-p current))
           (list current))
      (mapcar (lambda (file) (expand-file-name file org-directory))
              '("todo.org" "routines.org"))
      (suderman/org-context-files)))))

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

(defun suderman/org-archive ()
  "Archive the current Org item or Agenda entry."
  (interactive)
  (suderman/org--call-contextually #'org-archive-subtree #'org-agenda-archive))

(defun suderman/org-archive-done (&optional no-confirm)
  "Archive completed Agenda headings without hiding unfinished descendants.
Ask for confirmation in Emacs, unless given a prefix argument or NO-CONFIRM.
Batch calls do not prompt.  Save changed files before returning."
  (interactive "P")
  (let (headings)
    (unwind-protect
        (progn
          (org-map-entries
           (lambda ()
             (let ((parent (point)))
               (unless (memq t (org-map-entries
                                (lambda ()
                                  (and (> (point) parent)
                                       (member (org-get-todo-state)
                                               org-not-done-keywords)
                                       t))
                                nil 'tree))
                 (push (point-marker) headings)
                 (setq org-map-continue-from
                       (save-excursion (org-end-of-subtree t t))))))
           "/DONE" (org-agenda-files t) 'archive 'comment)
          (setq headings (nreverse headings))
          (let ((count (length headings))
                (archive-p (and headings
                                (or no-confirm noninteractive
                                    (yes-or-no-p
                                     (format "Archive %d completed Org headings? "
                                             (length headings)))))))
            (when archive-p
              (let ((org-archive-subtree-save-file-p t))
                (dolist (heading headings)
                  (with-current-buffer (marker-buffer heading)
                    (save-excursion
                      (goto-char heading)
                      (org-archive-subtree))
                    (save-buffer))))
              (suderman/org-refresh-agenda-after-revert)
              (message "Archived %d completed Org headings" count))
            (unless headings
              (when (called-interactively-p 'interactive)
                (message "No completed Org headings to archive")))
            (if archive-p count 0)))
      (dolist (heading headings)
        (set-marker heading nil)))))

(defun suderman/org-agenda-dirvish ()
  "Open Dirvish at the file for the selected Agenda entry."
  (interactive)
  (let* ((marker (or (org-get-at-bol 'org-marker)
                     (org-get-at-bol 'org-hd-marker)))
         (file (and (markerp marker)
                    (buffer-live-p (marker-buffer marker))
                    (buffer-file-name (marker-buffer marker)))))
    (suderman/dirvish (or file org-directory))))

(defun suderman/org-dashboard ()
  "Open the custom Org Agenda dashboard."
  (interactive)
  (org-agenda nil "d"))

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
  (setq auto-save-visited-interval (if (eq system-type 'android) 10 3)
        auto-save-visited-predicate #'suderman/org-auto-save-visited-p
        org-M-RET-may-split-line '((default . nil))
        org-insert-heading-respect-content t
        org-log-done 'time
        org-log-into-drawer t
        org-fontify-whole-block-delimiter-line nil
        org-startup-indented t
        org-startup-folded 'nofold
        org-hide-drawer-startup t
        org-startup-with-link-previews t
        org-tags-column 0
        org-auto-align-tags nil
        org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id
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
         (suderman/org-context-files))
        org-default-notes-file (expand-file-name "inbox.org" org-directory)
        org-capture-templates
        `(("t" "Task" entry (file ,org-default-notes-file)
            "* TODO %?\n  %U\n  %a")
          ("n" "Note" entry (file ,org-default-notes-file)
            "* %?\n  %U\n  %a")
          ("i" "Idea" entry (file ,org-default-notes-file)
            "* %?\n  %U\n  %a"))
        org-refile-targets '((suderman/org-refile-files :maxlevel . 3))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm
        org-archive-location "archive.org::"
        org-archive-file-header-format nil
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-deadline-if-done t
        org-agenda-custom-commands
        '(("d" "Dashboard"
           ((agenda "" ((org-agenda-span 7)))
            (todo "PROG" ((org-agenda-overriding-header "In progress")))
            (todo "EVAL" ((org-agenda-overriding-header "In review")))
            (todo "HOLD" ((org-agenda-overriding-header "On hold")))
            (todo "TODO" ((org-agenda-overriding-header "Todo")))))))
  (auto-save-visited-mode 1))

(use-package org-agenda
  :ensure nil
  :after org
  :config
  (keymap-set org-agenda-mode-map "," #'suderman/ibuffer-toggle)
  (keymap-set org-agenda-mode-map "." #'suderman/org-agenda-dirvish)
  (keymap-set org-agenda-mode-map "C-c ." #'org-agenda-goto-today))

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
