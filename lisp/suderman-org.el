;;; suderman-org.el --- Org agenda and capture workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep daily Org work centered on a few phone-friendly files.

;;; Code:

(require 'use-package)
(require 'cl-lib)
(require 'face-remap)
(require 'org-macs)
(eval-when-compile (require 'org-agenda))

(defvar org-done-keywords)
(defvar org-not-done-keywords)
(defvar org-archive-subtree-save-file-p)
(defvar org-archive-from-agenda)
(defvar org-tag-line-re)
(defvar org-highlight-links)
(defvar org-font-lock-extra-keywords)
(defvar font-lock-beg)
(defvar jit-lock-start)

(declare-function suderman/dired-archive "suderman-files" ())
(declare-function suderman/meow-insert "suderman-meow" ())
(declare-function consult-org-agenda "consult-org" (&optional match))
(declare-function consult-org-heading "consult-org" (&optional match scope))
(declare-function org-agenda "org-agenda" (&optional arg keys restriction))
(declare-function org-agenda-redo "org-agenda" (&optional all))
(declare-function org-agenda-redo-all "org-agenda" (&optional exhaustive))
(declare-function org-remove-subtree-entries-from-agenda "org-agenda"
                  (&optional buf beg end))
(declare-function meow--disable "meow")
(declare-function meow-mode "meow")
(declare-function meow-keypad "meow-keypad")
(declare-function meow-open-below "meow-command" ())
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
(declare-function org-link-set-parameters "ol" (type &rest parameters))
(declare-function org-agenda-files "org" (&optional unrestricted archives))
(declare-function org-entry-get "org" (epom property &optional inherit literal-nil))
(declare-function org-get-heading "org" (&optional no-tags no-todo no-priority no-comment))
(declare-function org-time-string-to-time "org" (s))

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
                      :inherit '(font-lock-type-face bold))
  (set-face-attribute 'org-ellipsis nil :foreground 'unspecified
                      :inherit 'font-lock-keyword-face :underline nil))

(add-hook 'org-mode-hook #'suderman/org-apply-heading-faces)
(add-hook 'enable-theme-functions #'suderman/org-apply-heading-faces)

(defun suderman-org-unload-function ()
  "Remove display callbacks before `suderman-org' functions are unloaded."
  ;; These callback lists are not ordinary hooks known to `unload-feature'.
  (remove-hook 'enable-theme-functions #'suderman/org-apply-heading-faces)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (suderman/org-remove-heading-arrows))))
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
    ;; Org gives cells starting with = the formula face.  Tags are not
    ;; column-aligned here.  Links and TODO colors stay theme-owned.
    (setq suderman/org-fixed-pitch-cookies
          (mapcar (lambda (face)
                    (face-remap-add-relative face 'suderman/fixed-pitch-text))
                  '(org-block org-block-begin-line suderman/org-drawer-label
                    org-code org-verbatim org-table org-formula org-meta-line
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

(defun suderman/org-return ()
  "Continue a list item or use Org Return, then enter Insert from Normal.
Return on an empty item removes it and ends the list.  A prefix
argument keeps Org's normal newline behavior."
  (interactive)
  (if (and (not current-prefix-arg) (eolp) (org-at-item-p)
           (org-match-line org-list-full-item-re))
      (if (= (point) (match-end 0))
          (progn
            (delete-region (line-beginning-position) (point))
            ;; Electric indentation would put point back inside the list.
            (insert "\n")
            (org-update-checkbox-count-maybe))
        (org-insert-item (match-beginning 3)))
    (call-interactively #'org-return))
  (when (bound-and-true-p meow-normal-mode)
    (suderman/meow-insert)))

(defun suderman/org-meta-return ()
  "Insert a heading or list item using Org, then enter Insert from Normal."
  (interactive)
  (call-interactively #'org-meta-return)
  (when (bound-and-true-p meow-normal-mode)
    (suderman/meow-insert)))

(defun suderman/org-insert-heading-after-subtree ()
  "Insert a heading after the subtree, then enter Insert from Normal."
  (interactive)
  (call-interactively #'org-insert-heading-respect-content)
  (when (bound-and-true-p meow-normal-mode)
    (suderman/meow-insert)))

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

(defun suderman/org-agenda-files ()
  "Return the current Agenda file set without scanning task directories."
  (append
   (mapcar (lambda (file) (expand-file-name file org-directory))
           '("inbox.org" "todo.org" "routines.org" "asana.org"))
   (suderman/org--direct-org-files (expand-file-name "calendar" org-directory))
   (suderman/org-context-files)))

(defun suderman/org-agenda-refresh (&optional all)
  "Rediscover Agenda files and rebuild the current view, or ALL views."
  (interactive "P")
  (setq org-agenda-files (suderman/org-agenda-files))
  (org-agenda-redo all))

(defun suderman/org-agenda-refresh-all (&optional exhaustive)
  "Rediscover files and rebuild all views, or all buffers with EXHAUSTIVE."
  (interactive "P")
  (setq org-agenda-files (suderman/org-agenda-files))
  (org-agenda-redo-all exhaustive))

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

(defun suderman/org--archive-task (&optional agenda-buffer)
  "Archive the current subtree, updating AGENDA-BUFFER if given."
  (interactive)
  (org-with-wide-buffer
    (org-back-to-heading t)
    (when agenda-buffer
      (let ((org-agenda-buffer-name agenda-buffer))
        (org-remove-subtree-entries-from-agenda)))
    ;; Archive one subtree, even when a region spans other headings.
    (let ((org-loop-over-headlines-in-active-region nil))
      (org-archive-subtree))))

(defun suderman/org--agenda-archive-task ()
  "Archive the current Agenda entry's subtree."
  (interactive)
  (let ((marker (or (org-get-at-bol 'org-hd-marker)
                    (org-get-at-bol 'org-marker)))
        (agenda-buffer (buffer-name))
        (org-archive-from-agenda t))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "No Org entry at point"))
    (org-with-remote-undo (marker-buffer marker)
      (org-with-point-at marker
        (suderman/org--archive-task agenda-buffer)))))

(defun suderman/org-archive ()
  "Archive a subtree in Org or Agenda, or selected files in Dired."
  (interactive)
  (if (derived-mode-p 'dired-mode)
      (call-interactively #'suderman/dired-archive)
    (suderman/org--call-contextually
     #'suderman/org--archive-task #'suderman/org--agenda-archive-task)))

(defun suderman/org--closed-days-ago (days)
  "Return non-nil when the heading at point was closed at least DAYS ago.
Headings without a CLOSED timestamp never qualify."
  (let ((closed (org-entry-get nil "CLOSED")))
    (and closed
         (>= (float-time (time-subtract nil (org-time-string-to-time closed)))
             (* days 86400)))))

(defun suderman/org-archive-done (&optional no-confirm min-days dry-run)
  "Archive completed headings in this buffer, keeping unfinished descendants.
Ask for confirmation in Emacs, unless given a prefix argument or NO-CONFIRM.
Batch calls do not prompt.  Save changed files before returning.
With MIN-DAYS, archive only headings closed at least that many days ago; a
more recent completed heading keeps its whole subtree.  With DRY-RUN, print
the headings that would be archived and return their count."
  (interactive "P")
  (unless (derived-mode-p 'org-mode)
    (user-error "This command requires an Org buffer"))
  (unless buffer-file-name
    (user-error "Save this Org buffer before archiving"))
  (org-with-wide-buffer
    (let (headings)
      (unwind-protect
          (progn
            (org-map-entries
             (lambda ()
               (let ((parent (point)))
                 (when (and (member (org-get-todo-state) org-done-keywords)
                            (not (memq t
                                       (org-map-entries
                                        (lambda ()
                                          (and (> (point) parent)
                                               (member (org-get-todo-state)
                                                       org-not-done-keywords)
                                               t))
                                        nil 'tree))))
                   (when (or (null min-days)
                             (suderman/org--closed-days-ago min-days))
                     (push (point-marker) headings))
                   (setq org-map-continue-from
                         (save-excursion (org-end-of-subtree t t))))))
             nil nil 'archive 'comment)
            (setq headings (nreverse headings))
            (when dry-run
              (dolist (heading headings)
                (goto-char heading)
                (princ (format "%s: %s\n" (abbreviate-file-name buffer-file-name)
                               (org-get-heading t t t t)))))
            (let ((count (length headings))
                  (archive-p (and headings (not dry-run)
                                  (or no-confirm noninteractive
                                      (yes-or-no-p
                                       (format "Archive %d completed Org headings? "
                                               (length headings)))))))
              (when archive-p
                (let ((org-archive-subtree-save-file-p t)
                      (org-loop-over-headlines-in-active-region nil))
                  (dolist (heading headings)
                    (goto-char heading)
                    (org-archive-subtree))
                  (save-buffer))
                (suderman/org-refresh-agenda-after-revert)
                (message "Archived %d completed Org headings" count))
              (unless headings
                (when (called-interactively-p 'interactive)
                  (message "No completed Org headings to archive")))
              (cond (archive-p count)
                    (dry-run count)
                    (t 0))))
        (dolist (heading headings)
          (set-marker heading nil))))))

(defun suderman/org-archive-old-done (days &optional dry-run)
  "Archive headings closed at least DAYS ago in every Agenda file.
With DRY-RUN, only print what would be archived.  Meant for batch runs, such
as the nightly archive timer; return the number of headings."
  (let ((total 0))
    (dolist (file (org-agenda-files))
      (with-current-buffer (find-file-noselect file)
        (setq total (+ total (suderman/org-archive-done t days dry-run)))))
    (princ (format "%s %d completed Org headings closed %d+ days ago\n"
                   (if dry-run "Would archive" "Archived") total days))
    total))

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

(defun suderman/org-daily ()
  "Show today's calendar and tasks in progress."
  (interactive)
  (org-agenda nil "D"))

(defun suderman/org-inbox ()
  "Open the Inbox for processing tasks, notes, and ideas."
  (interactive)
  (find-file (expand-file-name "inbox.org" org-directory)))

(defun suderman/org-agenda-goto-other-window (original &rest args)
  "Keep Agenda visible when ORIGINAL displays an entry with ARGS."
  ;; Follow and preview must not fall back to replacing the Agenda pane.
  (let ((display-buffer-overriding-action '(nil (inhibit-same-window . t))))
    (apply original args)))

(defun suderman/org-agenda-disable-meow ()
  "Let Agenda's own map take precedence over Meow."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/org-agenda-setup ()
  "Keep Meow off locally while retaining direct keypad access."
  (add-hook 'meow-mode-hook #'suderman/org-agenda-disable-meow nil t)
  (suderman/org-agenda-disable-meow))

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

(defvar suderman/org-asana-project-history nil
  "Project files chosen by `suderman/org-asana-track'.")

(defun suderman/org--asana-entry ()
  "Return (GID TITLE) for the Asana heading at point or Agenda line."
  (let ((marker (and (derived-mode-p 'org-agenda-mode)
                     (or (org-get-at-bol 'org-hd-marker)
                         (user-error "No Org entry on this line")))))
    (org-with-point-at (or marker (point))
      (org-back-to-heading t)
      (let ((gid (or (org-entry-get nil "ASANA_ID")
                     (user-error "Not an asana.org task")))
            (title (org-get-heading t t t t))
            (project (save-excursion
                       (and (re-search-forward
                             "^Project: \\(.+\\)$"
                             (save-excursion (outline-next-heading) (point)) t)
                            (match-string-no-properties 1)))))
        (when (and project (string-prefix-p (concat project " > ") title))
          (setq title (substring title (+ (length project) 3))))
        (list gid title)))))

(defun suderman/org-asana-track ()
  "Open the project heading that tracks the Asana task at point.
Create a heading without a TODO keyword in a chosen project file when none
links to the task yet, so the Agenda lists the Asana task once."
  (interactive)
  (pcase-let* ((`(,gid ,title) (suderman/org--asana-entry))
               (link (format "[[id:asana-%s]" gid))
               (work (expand-file-name "work" org-directory))
               ;; Project files sit at DOMAIN/PROJECT/PROJECT.org; client
               ;; files sit directly in DOMAIN.
               (projects (seq-filter
                          (lambda (file)
                            (= 3 (length (file-name-split
                                          (file-relative-name file work)))))
                          (suderman/org-work-agenda-files work)))
               (existing (seq-find
                          (lambda (file)
                            (if-let* ((buffer (find-buffer-visiting file)))
                                (with-current-buffer buffer
                                  (org-with-wide-buffer
                                   (goto-char (point-min))
                                   (search-forward link nil t)))
                              (with-temp-buffer
                                (insert-file-contents file)
                                (search-forward link nil t))))
                          projects)))
    (if existing
        (progn
          (pop-to-buffer-same-window (find-file-noselect existing))
          (widen)
          (goto-char (point-min))
          (search-forward link)
          (org-back-to-heading t))
      (let* ((names (mapcar (lambda (file)
                              (cons (file-name-directory
                                     (file-relative-name file work))
                                    file))
                            projects))
             (file (cdr (assoc (completing-read
                                (format "Track \"%s\" in project: " title)
                                names nil t nil
                                'suderman/org-asana-project-history)
                               names))))
        (pop-to-buffer-same-window (find-file-noselect file))
        (widen)
        (goto-char (point-min))
        (if (re-search-forward org-outline-regexp-bol nil t)
            (goto-char (match-beginning 0))
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (unless (or (bobp) (looking-back "\n\n" nil)) (insert "\n")))
        (save-excursion
          (insert (format "* %s :asana:\n%s[Asana task]]\n\n" title link)))))))

(defun suderman/org-asana-delegate ()
  "Add an agent step under the project heading for the Asana task at point.
The step starts as TODO so org-dispatch cannot launch it while its
instructions are being written; set AUTO when they are ready."
  (interactive)
  (suderman/org-asana-track)
  (let ((title (org-get-heading t t t t)))
    (org-end-of-subtree t t)
    (unless (bolp) (insert "\n"))
    (unless (looking-back "\n\n" nil) (insert "\n"))
    (insert (format "** TODO %s :kit:\n" title))
    (save-excursion (insert "\n\n"))))

(defun suderman/org-schedule ()
  "Schedule an Org item, or open the TODO list."
  (interactive)
  (suderman/org--call-contextually
   #'org-schedule #'org-agenda-schedule #'org-todo-list))

(defun suderman/org-todo (&optional state)
  "Change an Org item's TODO state, or set it directly to STATE.
Without STATE, open the TODO list outside Org or Agenda."
  (interactive)
  (if state
      (suderman/org--call-contextually
       (lambda () (interactive) (org-todo state))
       (lambda () (interactive) (org-agenda-todo state)))
    (suderman/org--call-contextually
     #'org-todo #'org-agenda-todo #'org-todo-list)))

(defun suderman/org-todo-todo ()
  "Set the current Org heading or Agenda entry to TODO."
  (interactive)
  (suderman/org-todo "TODO"))

(defun suderman/org-todo-prog ()
  "Set the current Org heading or Agenda entry to PROG."
  (interactive)
  (suderman/org-todo "PROG"))

(defun suderman/org-todo-eval ()
  "Set the current Org heading or Agenda entry to EVAL."
  (interactive)
  (suderman/org-todo "EVAL"))

(defun suderman/org-todo-hold ()
  "Set the current Org heading or Agenda entry to HOLD."
  (interactive)
  (suderman/org-todo "HOLD"))

(defun suderman/org-todo-auto ()
  "Set the current Org heading or Agenda entry to AUTO for org-dispatch."
  (interactive)
  (suderman/org-todo "AUTO"))

(defun suderman/org-todo-done ()
  "Set the current Org heading or Agenda entry to DONE."
  (interactive)
  (suderman/org-todo "DONE"))

(defun suderman/org-delete-subtree ()
  "Discard the current Org subtree, keeping it in the kill ring."
  (interactive)
  (suderman/org--call-contextually
   (lambda ()
     (interactive)
     (org-with-wide-buffer
       (org-back-to-heading t)
       (org-cut-subtree)))))

(defun suderman/org-toggle-checkbox ()
  "Toggle a checkbox in an Org buffer."
  (interactive)
  (suderman/org--call-contextually #'org-toggle-checkbox))

(defun suderman/org-goto-adjacent-heading ()
  "Move to the visible heading when point borders its folded subtree."
  (when (and (not (org-invisible-p))
             (or (and (eolp)
                      (not (bobp))
                      (org-fold-folded-p (1- (point)) 'outline))
                 (save-excursion
                   (beginning-of-line)
                   (and (not (bobp))
                        (looking-at-p "[ \t]*$")
                        (org-fold-folded-p (1- (point)) 'outline)))))
    ;; At EOF the visible newline can belong to a hidden, nonblank body line.
    ;; Skip hidden child headings to find the visible parent.
    (org-back-to-heading)))

(defun suderman/org-mouse-toggle-heading (event)
  "Toggle the subtree whose trailing arrow received EVENT."
  (interactive "e")
  (mouse-set-point event)
  (org-back-to-heading t)
  (suderman/org-open-below))

(defvar suderman/org-heading-arrow-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'ignore)
    (define-key map [mouse-1] #'suderman/org-mouse-toggle-heading)
    (define-key map [mouse-2] #'suderman/org-mouse-toggle-heading)
    map)
  "Mouse bindings on trailing heading arrows.")

(defun suderman/org-heading-has-content-p ()
  "Return non-nil when the heading at point has body text or child headings."
  (and (org-at-heading-p)
       (< (line-end-position) (save-excursion (org-end-of-subtree t)))))

(defun suderman/org-fontify-heading-arrows (beg end)
  "Refresh heading arrow displays between BEG and END."
  (save-excursion
    (goto-char end)
    (setq end (min (point-max) (1+ (line-end-position))))
    (goto-char beg)
    (setq beg (line-beginning-position))
    (goto-char beg)
    (remove-overlays beg end 'suderman/org-heading-arrow t)
    (while (re-search-forward org-outline-regexp-bol end t)
      (let* ((eol (line-end-position))
             (pos (1- eol)))
        (when (suderman/org-heading-has-content-p)
          ;; Put the display on visible title text, not the folded newline or
          ;; hidden link brackets.  After-strings at the newline disappear folded.
          (while (and (> pos (line-beginning-position))
                      (invisible-p (get-text-property pos 'invisible)))
            (setq pos (1- pos)))
          ;; Inherit the face; copying it applies relative heading height twice.
          (let* ((char (buffer-substring-no-properties pos (1+ pos)))
                 (overlay (make-overlay pos (1+ pos)))
                 (folded '(with-current-buffer object
                            (save-excursion
                              (goto-char buffer-position)
                              (org-fold-folded-p (line-end-position) 'outline)))))
            (overlay-put overlay 'suderman/org-heading-arrow t)
            (overlay-put overlay 'evaporate t)
            (overlay-put
             overlay 'display
             (mapcar
              (lambda (state)
                `(when ,(if (car state) folded `(not ,folded))
                   . ,(concat char
                              (propertize (cdr state)
                                          'face 'org-ellipsis
                                          'mouse-face 'highlight
                                          'pointer 'hand
                                          'help-echo "Toggle subtree"
                                          'keymap suderman/org-heading-arrow-map))))
              '((t . " ▸") (nil . " ▾"))))))
        (goto-char eol)))))

(defun suderman/org-extend-heading-arrow-region (beg _end _old-len)
  "Refontify the preceding heading when its contents change at BEG."
  (save-excursion
    (goto-char beg)
    (beginning-of-line)
    (when (re-search-backward org-outline-regexp-bol nil t)
      (setq jit-lock-start (min jit-lock-start (point))))))

(defun suderman/org-remove-heading-arrows ()
  "Remove heading displays when leaving Org mode."
  (remove-hook 'jit-lock-after-change-extend-region-functions
               #'suderman/org-extend-heading-arrow-region t)
  (jit-lock-unregister #'suderman/org-fontify-heading-arrows)
  (save-restriction
    (widen)
    (remove-overlays (point-min) (point-max) 'suderman/org-heading-arrow t)))

(defun suderman/org-enable-heading-arrows ()
  "Show clickable heading arrows independently of Org's hidden-text markers."
  (org-fold-core-set-folding-spec-property
   (org-fold-core-get-folding-spec-from-alias 'outline) :ellipsis nil)
  (jit-lock-register #'suderman/org-fontify-heading-arrows)
  (add-hook 'jit-lock-after-change-extend-region-functions
            #'suderman/org-extend-heading-arrow-region nil t)
  (jit-lock-refontify)
  (add-hook 'change-major-mode-hook #'suderman/org-remove-heading-arrows nil t))

(add-hook 'org-mode-hook #'suderman/org-enable-heading-arrows)

(defun suderman/org-open-below ()
  "Toggle a heading with content, or open a line below with Meow."
  (interactive)
  (suderman/org-goto-adjacent-heading)
  (if (suderman/org-heading-has-content-p)
      (if (org-fold-folded-p (line-end-position) 'outline)
          (org-fold-show-subtree)
        (org-fold-hide-subtree))
    (call-interactively #'meow-open-below)))

(defun suderman/org-cycle-adjacent-heading ()
  "Move from a folded subtree's boundary to its visible heading.
Return nil so Org continues its normal TAB action."
  (unless current-prefix-arg
    (suderman/org-goto-adjacent-heading))
  nil)

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

(defun suderman/org-herdr-follow (path _arg)
  "Jump to the Herdr pane for the agent session in herdr: link PATH."
  (unless (executable-find "herdr-link")
    (user-error "herdr-link is not available here"))
  (let ((buffer (generate-new-buffer " *herdr-link*")))
    (make-process
     :name "herdr-link"
     :buffer buffer
     :command (list "herdr-link" "jump" path)
     :sentinel (lambda (process _event)
                 (unless (process-live-p process)
                   (unless (zerop (process-exit-status process))
                     (message "%s" (with-current-buffer buffer
                                     (string-trim (buffer-string)))))
                   (kill-buffer buffer))))))

(use-package org
  :ensure nil
  :init
  (setq auto-save-visited-interval (if (featurep 'android) 10 3)
        auto-save-visited-predicate #'suderman/org-auto-save-visited-p
        org-M-RET-may-split-line '((default . nil))
        org-insert-heading-respect-content nil
        org-log-done 'time
        org-log-into-drawer t
        org-fontify-whole-block-delimiter-line nil
        org-startup-indented t
        org-startup-folded 'fold
        org-ellipsis " ▾"
        org-hide-drawer-startup t
        org-startup-with-link-previews t
        org-tags-column 0
        org-auto-align-tags nil
        org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id
        org-todo-keywords
        '((sequence "TODO" "PROG" "EVAL" "HOLD" "|" "DONE")
          ;; Agent work for org-dispatch; its own sequence keeps it out of cycling.
          (sequence "AUTO" "|"))
        org-directory (expand-file-name "~/org")
        org-attach-id-dir (expand-file-name ".attach/" org-directory)
        org-attach-use-inheritance t
        org-agenda-files (suderman/org-agenda-files)
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
        org-agenda-window-setup 'current-window
        org-agenda-restore-windows-after-quit t
        org-agenda-span 7
        org-agenda-start-on-weekday nil
        org-agenda-custom-commands
        '(("d" "Dashboard"
           ((agenda "" ((org-agenda-span 7)))
            (todo "PROG" ((org-agenda-overriding-header "In progress")))
            (todo "EVAL" ((org-agenda-overriding-header "In review")))
            (todo "HOLD" ((org-agenda-overriding-header "On hold")))
            (todo "AUTO" ((org-agenda-overriding-header "Agents")))
            (todo "TODO" ((org-agenda-overriding-header "Todo")))))
          ("D" "Daily"
           ((agenda "" ((org-agenda-span 1)))
            (todo "PROG" ((org-agenda-overriding-header "In progress")))))
          ("w" "Monday-based week" agenda ""
           ((org-agenda-span 7) (org-agenda-start-on-weekday 1)))))
  (auto-save-visited-mode 1)
  :config
  (org-link-set-parameters "herdr" :follow #'suderman/org-herdr-follow)
  (keymap-set org-mode-map "RET" #'suderman/org-return)
  (keymap-set org-mode-map "<remap> <org-meta-return>" #'suderman/org-meta-return)
  (keymap-set org-mode-map "<remap> <org-insert-heading-respect-content>"
              #'suderman/org-insert-heading-after-subtree)
  (keymap-set org-mode-map "<remap> <meow-open-below>" #'suderman/org-open-below)
  (keymap-set org-mode-map "<mouse-1>" #'mouse-set-point)
  (add-hook 'org-cycle-tab-first-hook #'suderman/org-cycle-adjacent-heading)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (suderman/org-enable-heading-arrows)))))

(use-package org-agenda
  :ensure nil
  :after org
  :hook (org-agenda-mode . suderman/org-agenda-setup)
  :config
  (advice-add 'org-agenda-goto :around #'suderman/org-agenda-goto-other-window)
  (keymap-set org-agenda-mode-map "SPC" #'meow-keypad)
  (keymap-set org-agenda-mode-map "j" #'org-agenda-next-line)
  (keymap-set org-agenda-mode-map "k" #'org-agenda-previous-line)
  (keymap-set org-agenda-mode-map "n" #'org-agenda-later)
  (keymap-set org-agenda-mode-map "p" #'org-agenda-earlier)
  (keymap-set org-agenda-mode-map "l" #'org-agenda-switch-to)
  (keymap-set org-agenda-mode-map "h" #'org-agenda-quit)
  (keymap-set org-agenda-mode-map "m" #'org-agenda-bulk-toggle)
  (keymap-set org-agenda-mode-map "M" #'org-agenda-bulk-unmark-all)
  (keymap-set org-agenda-mode-map "B" #'org-agenda-bulk-action)
  (keymap-set org-agenda-mode-map "C-SPC" #'org-agenda-show-and-scroll-up)
  (keymap-set org-agenda-mode-map "r" #'suderman/org-agenda-refresh)
  (keymap-set org-agenda-mode-map "g" #'suderman/org-agenda-refresh-all)
  (keymap-set org-agenda-mode-map "M-p" #'consult-recent-file)
  (keymap-set org-agenda-mode-map "M-U" #'suderman/split-window-below-and-focus)
  (keymap-set org-agenda-mode-map "M-I" #'suderman/split-window-right-and-focus)
  (keymap-set org-agenda-mode-map "," #'suderman/ibuffer-toggle)
  (keymap-set org-agenda-mode-map "." #'suderman/org-agenda-dirvish)
  (keymap-set org-agenda-mode-map "`" #'suderman/dashboard)
  (keymap-set org-agenda-mode-map "\\" #'suderman/dirvish-side-toggle)
  (keymap-set org-agenda-mode-map "<" #'previous-buffer)
  (keymap-set org-agenda-mode-map ">" #'next-buffer)
  (keymap-set org-agenda-mode-map "C-c ." #'org-agenda-goto-today)
  ;; Keep displaced native actions reachable without giving up navigation.
  (keymap-set org-agenda-mode-map "C-c j" #'org-agenda-goto-date)
  (keymap-set org-agenda-mode-map "C-c k" #'org-agenda-capture)
  (keymap-set org-agenda-mode-map "C-c l" #'org-agenda-log-mode)
  (keymap-set org-agenda-mode-map "C-c M" #'org-agenda-phases-of-moon)
  (keymap-set org-agenda-mode-map "C-c >" #'org-agenda-date-prompt)
  (keymap-set org-agenda-mode-map "C-c <" #'org-agenda-filter-by-category)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-agenda-mode)
        (suderman/org-agenda-setup)))))

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
