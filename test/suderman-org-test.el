;;; suderman-org-test.el --- Org workflow and export checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for custom behavior with enough moving parts to merit a safety net.

;;; Code:

(require 'ert)
(require 'org-agenda)
(require 'org-archive)
(require 'suderman-org)

;; Agenda discovery

(ert-deftest suderman/org-discovers-work-agenda-files-by-convention ()
  (let* ((work (make-temp-file "suderman-org-work-" t))
         (nonfiction (expand-file-name "nonfiction" work))
         (project (expand-file-name "beefresearch" nonfiction))
         (task (expand-file-name "2026-09-14-economic-value-of-feeds" project))
         (archive (expand-file-name "archive" nonfiction))
         (suderman (expand-file-name "suderman" work)))
    (unwind-protect
        (progn
          (dolist (directory (list task
                                   (expand-file-name "gta" archive)
                                   (expand-file-name "upick" nonfiction)
                                   (expand-file-name "not-a-file.org" nonfiction)
                                   (expand-file-name ".secret" nonfiction)
                                   (expand-file-name ".hidden" work)
                                   (expand-file-name "emacs" suderman)))
            (make-directory directory t))
          (dolist (file (list (expand-file-name "bcrc.org" nonfiction)
                              (expand-file-name "archive.org" nonfiction)
                              (expand-file-name "gta/gta.org" archive)
                              (expand-file-name ".private.org" nonfiction)
                              (expand-file-name "beefresearch.org" project)
                              (expand-file-name "quote-review.org" task)
                              (expand-file-name "notes.org"
                                                (expand-file-name "upick" nonfiction))
                              (expand-file-name ".secret.org"
                                                (expand-file-name ".secret" nonfiction))
                              (expand-file-name "client.org"
                                                (expand-file-name ".hidden" work))
                              (expand-file-name "davy.org" suderman)
                              (expand-file-name "emacs.org"
                                                (expand-file-name "emacs" suderman))))
            (with-temp-file file))
          (should
           (equal (suderman/org-work-agenda-files work)
                  (list (expand-file-name "bcrc.org" nonfiction)
                        (expand-file-name "beefresearch.org" project)
                        (expand-file-name "davy.org" suderman)
                        (expand-file-name "emacs/emacs.org" suderman))))
          (should-not
           (suderman/org-work-agenda-files
            (expand-file-name "missing" work))))
      (delete-directory work t))))

(ert-deftest suderman/org-builds-context-and-refile-file-lists ()
  (let* ((org-directory (make-temp-file "suderman-org-contexts-" t))
         (life (expand-file-name "life/kids.org" org-directory))
         (notes (expand-file-name "notes/reference.org" org-directory))
         (calendar (expand-file-name "calendar/import.org" org-directory))
         (client (expand-file-name "work/acme/acme.org" org-directory))
         (project (expand-file-name "work/acme/widget/widget.org" org-directory))
         (inbox (expand-file-name "inbox.org" org-directory))
         (todo (expand-file-name "todo.org" org-directory))
         (routines (expand-file-name "routines.org" org-directory))
         (draft (expand-file-name "draft.org" org-directory))
         (archive (expand-file-name "notes/archive.org" org-directory))
         (contexts (list life notes client project))
         (destinations (append (list todo routines) contexts)))
    (unwind-protect
        (progn
          (dolist (directory (list (file-name-directory life)
                                   (file-name-directory notes)
                                   (file-name-directory calendar)
                                   (file-name-directory project)))
            (make-directory directory t))
          (dolist (file (append (list inbox todo routines draft calendar archive)
                                contexts))
            (with-temp-file file))
          (should (equal (suderman/org-context-files) contexts))
          (with-temp-buffer
            (setq buffer-file-name inbox)
            (should (equal (suderman/org-refile-files) destinations)))
          (with-temp-buffer
            (setq buffer-file-name draft)
            (should (equal (suderman/org-refile-files)
                           (cons draft destinations))))
          (dolist (excluded (list inbox calendar archive))
            (with-temp-buffer
              (setq buffer-file-name excluded)
              (should-not (member excluded (suderman/org-refile-files)))))
          (should (cl-every #'file-regular-p destinations)))
      (delete-directory org-directory t))))

(ert-deftest suderman/org-excludes-archive-files-and-directories ()
  (let* ((directory (make-temp-file "suderman-org-files-" t))
         (active (expand-file-name "active.org" directory))
         (archive-file (expand-file-name "archive.org" directory))
         (archive-directory (expand-file-name "archive" directory))
         (archived (expand-file-name "client.org" archive-directory)))
    (unwind-protect
        (progn
          (make-directory archive-directory)
          (dolist (file (list active archive-file archived))
            (with-temp-file file))
          (should (equal (suderman/org--direct-org-files directory)
                         (list active)))
          (should-not (suderman/org--direct-org-files archive-directory)))
      (delete-directory directory t))))


;; Archiving and synced files

(ert-deftest suderman/org-archive-cuts-only-the-current-subtree ()
  (dolist (case '(("* TODO Parent\nBody\n** Notes\n*** Details\nChild body\n"
                   "Body" "Parent" nil)
                  ("* PROG Parent\n** Notes\n*** Details\nChild body\n"
                   "Child body" "Details" t)
                  ("* TODO Parent\n** TODO Child\nChild body\n"
                   "Child body" "Child" nil)
                  ("* DONE Parent\n** Notes\nChild body\n"
                   "Child body" "Notes" nil)
                  ("* TODO Parent\nBody\n"
                   "Parent" "Parent" nil)
                  ("* TODO Parent\nBody\n"
                   "Body" "Parent" nil t)))
    (let* ((directory (make-temp-file "suderman-org-archive-task-" t))
           (source (expand-file-name "tasks.org" directory))
           (archive (expand-file-name "archive.org" directory))
           (org-archive-location "archive.org::")
           (transient-mark-mode t)
           (org-loop-over-headlines-in-active-region t))
      (unwind-protect
          (progn
            (with-temp-file source
              (insert (nth 0 case) "* TODO Keep\nKeep body\n"))
            (with-current-buffer (find-file-noselect source)
              (goto-char (point-min))
              (search-forward (nth 1 case))
              (when (nth 3 case)
                ;; The enclosing task can be outside the accessible text.
                (narrow-to-region (line-beginning-position) (line-end-position)))
              (when (nth 4 case)
                (set-mark (point-max))
                (setq mark-active t))
              (call-interactively #'suderman/org-archive)
              (widen)
              (goto-char (point-min))
              (should-not (search-forward (nth 2 case) nil t))
              (goto-char (point-min))
              (should (search-forward "TODO Keep" nil t))
              (when (member (nth 2 case) '("Child" "Details" "Notes"))
                (goto-char (point-min))
                (should (search-forward "Parent" nil t))))
            (with-current-buffer (find-buffer-visiting archive)
              (goto-char (point-min))
              (should (search-forward (nth 2 case) nil t))
              (should (search-forward "ARCHIVE_FILE" nil t))
              (should-not (search-forward "TODO Keep" nil t))))
        (dolist (file (list source archive))
          (when-let* ((buffer (find-buffer-visiting file)))
            (with-current-buffer buffer (set-buffer-modified-p nil))
            (kill-buffer buffer)))
        (delete-directory directory t)))))

(ert-deftest suderman/org-archive-refuses-to-archive-before-first-heading ()
  (dolist (text '("Before first heading\n* TODO Later\n"))
    (with-temp-buffer
      (insert text)
      (org-mode)
      (goto-char (if (string-prefix-p "Before" text) (point-min) (point-max)))
      (let ((position (point)))
        (should-error (suderman/org-archive) :type 'user-error)
        (should (= (point) position))
        (should (equal (buffer-string) text))))))

(ert-deftest suderman/org-agenda-archive-removes-only-the-selected-subtree ()
  (let* ((directory (make-temp-file "suderman-agenda-archive-task-" t))
         (source (expand-file-name "tasks.org" directory))
         (archive (expand-file-name "archive.org" directory))
         (org-agenda-files (list source))
         (org-agenda-buffer-name "*Agenda archive task test*")
         (org-agenda-start-day "2026-09-29")
         (org-archive-location "archive.org::"))
    (unwind-protect
        (save-window-excursion
          (with-temp-file source
            (insert "* TODO Parent\n** Note\n<2026-09-29 Tue>\nBody\n"
                    "* TODO Keep\n* Plain\n<2026-09-29 Tue>\n"))
          (suderman/org-dashboard)
          (goto-char (point-min))
          (search-forward "Plain")
          (suderman/org-archive)
          (should-not (string-match-p "Plain" (buffer-string)))
          (goto-char (point-min))
          (search-forward "Note")
          (suderman/org-archive)
          (should-not (string-match-p "Note" (buffer-string)))
          (should (string-match-p "Parent" (buffer-string)))
          (should (string-match-p "Keep" (buffer-string)))
          (with-current-buffer (find-file-noselect source)
            (should-not (string-match-p "Note" (buffer-string)))
            (should (string-match-p "Parent" (buffer-string)))
            (should (string-match-p "TODO Keep" (buffer-string)))))
      (when-let* ((buffer (get-buffer org-agenda-buffer-name)))
        (kill-buffer buffer))
      (dolist (file (list source archive))
        (when-let* ((buffer (find-buffer-visiting file)))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest suderman/org-bulk-archive-saves-only-current-buffer-completed-trees ()
  (let* ((directory (make-temp-file "suderman-org-bulk-" t))
         (first (expand-file-name "first.org" directory))
         (second (expand-file-name "second.org" directory))
         (archive (expand-file-name "archive.org" directory))
         (override (expand-file-name "special.org" directory))
         (org-agenda-files (list first second))
         (org-archive-location "archive.org::")
         (org-archive-file-header-format nil)
         refreshed)
    (unwind-protect
        (progn
          (with-temp-file first
            (insert "#+TODO: TODO | DONE CLOSED\n"
                    "* DONE Finished parent\n** DONE Finished child\n"
                    "* DONE Mixed parent\n** TODO Still open\n"
                    "** DONE Finished under mixed parent\n"
                    "* TODO Keep working\n"
                    "* CLOSED Special\n:PROPERTIES:\n"
                    ":ARCHIVE: special.org::\n:END:\n"))
          (with-temp-file second
            (insert "* DONE Special\n:PROPERTIES:\n"
                    ":ARCHIVE: special.org::\n:END:\n"))
          (with-current-buffer (find-file-noselect first)
            (goto-char (point-min))
            (re-search-forward "^\\* DONE")
            (org-narrow-to-subtree)
            (cl-letf (((symbol-function 'yes-or-no-p)
                       (lambda (&rest _) (error "Batch archiving prompted")))
                      ((symbol-function 'org-agenda-maybe-redo)
                       (lambda () (setq refreshed t))))
              (should (= (suderman/org-archive-done) 3))))
          (should refreshed)
          (should (string-match-p "Still open"
                                  (with-temp-buffer
                                    (insert-file-contents first)
                                    (buffer-string))))
          (should-not (string-match-p "Finished parent"
                                      (with-temp-buffer
                                        (insert-file-contents first)
                                        (buffer-string))))
          (with-temp-buffer
            (insert-file-contents archive)
            (should (search-forward "Finished parent" nil t))
            (should (search-forward "Finished child" nil t))
            (should (search-forward "Finished under mixed parent" nil t)))
          (with-temp-buffer
            (insert-file-contents override)
            (should (search-forward "Special" nil t))
            (should (search-forward "ARCHIVE_FILE" nil t)))
          (with-temp-buffer
            (insert-file-contents second)
            (should (equal (buffer-string)
                           "* DONE Special\n:PROPERTIES:\n:ARCHIVE: special.org::\n:END:\n")))
          (with-current-buffer (find-file-noselect first)
            (should (= (suderman/org-archive-done) 0))))
      (dolist (file (list first second archive override))
        (when-let* ((buffer (find-buffer-visiting file)))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest suderman/org-bulk-archive-confirms-or-accepts-prefix ()
  (let* ((directory (make-temp-file "suderman-org-confirm-" t))
         (source (expand-file-name "tasks.org" directory))
         (org-agenda-files (list source))
         (org-archive-location "archive.org::")
         (org-archive-file-header-format nil)
         (noninteractive nil)
         asked)
    (unwind-protect
        (progn
          (with-temp-file source (insert "* DONE Finished\n"))
          (with-current-buffer (find-file-noselect source)
            (cl-letf (((symbol-function 'yes-or-no-p)
                       (lambda (_prompt) (setq asked t) nil)))
              (should (= (call-interactively #'suderman/org-archive-done) 0))
              (should asked)
              (should (= (let ((current-prefix-arg '(4)))
                           (call-interactively #'suderman/org-archive-done))
                         1))))
          (should (file-exists-p (expand-file-name "archive.org" directory))))
      (dolist (file (list source (expand-file-name "archive.org" directory)))
        (when-let* ((buffer (find-buffer-visiting file)))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest suderman/org-auto-saves-only-safe-files-under-org-directory ()
  (let* ((org-directory (make-temp-file "suderman-org-" t))
         (inside (expand-file-name "todo.org" org-directory))
         (outside (make-temp-file "suderman-org-outside-" nil ".org"))
         (current t))
    (unwind-protect
        (cl-letf (((symbol-function 'verify-visited-file-modtime)
                   (lambda (&optional _buffer) current)))
          (with-temp-buffer
            (setq buffer-file-name inside)
            (org-mode)
            (should (suderman/org-auto-save-visited-p))
            (setq current nil)
            (should-not (suderman/org-auto-save-visited-p))
            (setq current t)
            (text-mode)
            (should-not (suderman/org-auto-save-visited-p)))
          (with-temp-buffer
            (setq buffer-file-name outside)
            (org-mode)
            (should-not (suderman/org-auto-save-visited-p))))
      (delete-directory org-directory t)
      (delete-file outside))))

;; Context-sensitive commands

(ert-deftest suderman/org-delete-cuts-one-complete-subtree-to-kill-ring ()
  (let ((kill-ring nil)
        (kill-ring-yank-pointer nil))
    (with-temp-buffer
      (insert "* TODO Discard\nBody\n** Child\nChild body\n* TODO Keep\n")
      (org-mode)
      (goto-char (point-min))
      (search-forward "Body")
      (narrow-to-region (line-beginning-position) (line-end-position))
      (call-interactively #'suderman/org-delete-subtree)
      (widen)
      (should (equal (buffer-string) "* TODO Keep\n"))
      (should (equal (current-kill 0 t)
                     "* TODO Discard\nBody\n** Child\nChild body\n")))
    (with-temp-buffer
      (should-error (suderman/org-delete-subtree) :type 'user-error)
      (should-error (suderman/org-archive-done) :type 'user-error))))

(ert-deftest suderman/org-item-commands-follow-buffer-context ()
  (let (called)
    (cl-letf (((symbol-function 'consult-org-agenda)
               (lambda () (interactive) (setq called 'consult-org-agenda)))
              ((symbol-function 'suderman/org--agenda-archive-task)
               (lambda () (interactive) (setq called 'agenda-archive-task)))
              ((symbol-function 'consult-org-heading)
               (lambda () (interactive) (setq called 'consult-org-heading)))
              ((symbol-function 'org-agenda-deadline)
               (lambda () (interactive) (setq called 'org-agenda-deadline)))
              ((symbol-function 'org-agenda-refile)
               (lambda () (interactive) (setq called 'org-agenda-refile)))
              ((symbol-function 'org-agenda-schedule)
               (lambda () (interactive) (setq called 'org-agenda-schedule)))
              ((symbol-function 'org-agenda-todo)
               (lambda () (interactive) (setq called 'org-agenda-todo)))
              ((symbol-function 'org-agenda-write)
               (lambda () (interactive) (setq called 'org-agenda-write)))
              ((symbol-function 'org-deadline)
               (lambda () (interactive) (setq called 'org-deadline)))
              ((symbol-function 'org-export-dispatch)
               (lambda () (interactive) (setq called 'org-export-dispatch)))
              ((symbol-function 'suderman/org--archive-task)
               (lambda () (interactive) (setq called 'archive-task)))
              ((symbol-function 'org-insert-link)
               (lambda () (interactive) (setq called 'org-insert-link)))
              ((symbol-function 'org-refile)
               (lambda () (interactive) (setq called 'org-refile)))
              ((symbol-function 'org-schedule)
               (lambda () (interactive) (setq called 'org-schedule)))
              ((symbol-function 'org-todo)
               (lambda () (interactive) (setq called 'org-todo)))
              ((symbol-function 'org-todo-list)
               (lambda () (interactive) (setq called 'org-todo-list)))
              ((symbol-function 'org-toggle-checkbox)
               (lambda () (interactive) (setq called 'org-toggle-checkbox))))
      (dolist (case '((org-mode suderman/org-archive archive-task)
                      (org-mode suderman/org-deadline org-deadline)
                      (org-mode suderman/org-export org-export-dispatch)
                      (org-mode suderman/org-heading consult-org-heading)
                      (org-mode suderman/org-insert-link org-insert-link)
                      (org-mode suderman/org-refile org-refile)
                      (org-mode suderman/org-schedule org-schedule)
                      (org-mode suderman/org-todo org-todo)
                      (org-mode suderman/org-toggle-checkbox org-toggle-checkbox)
                      (org-agenda-mode suderman/org-archive agenda-archive-task)
                      (org-agenda-mode suderman/org-deadline org-agenda-deadline)
                      (org-agenda-mode suderman/org-export org-agenda-write)
                      (org-agenda-mode suderman/org-heading consult-org-agenda)
                      (org-agenda-mode suderman/org-refile org-agenda-refile)
                      (org-agenda-mode suderman/org-schedule org-agenda-schedule)
                      (org-agenda-mode suderman/org-todo org-agenda-todo)
                      (markdown-ts-mode suderman/org-deadline org-todo-list)
                      (markdown-ts-mode suderman/org-heading consult-org-agenda)
                      (markdown-ts-mode suderman/org-refile org-todo-list)
                      (markdown-ts-mode suderman/org-schedule org-todo-list)
                      (markdown-ts-mode suderman/org-todo org-todo-list)))
        (setq called nil)
        (with-temp-buffer
          (funcall (nth 0 case))
          (call-interactively (nth 1 case)))
        (should (eq called (nth 2 case))))
      (dolist (case '((org-agenda-mode suderman/org-insert-link)
                      (org-agenda-mode suderman/org-toggle-checkbox)
                      (markdown-ts-mode suderman/org-archive)
                      (markdown-ts-mode suderman/org-export)
                      (markdown-ts-mode suderman/org-insert-link)
                      (markdown-ts-mode suderman/org-toggle-checkbox)))
        (with-temp-buffer
          (funcall (nth 0 case))
          (should-error (call-interactively (nth 1 case))
                        :type 'user-error))))))

;; Font-lock regressions

(ert-deftest suderman/org-drawer-blocks-preserve-content-and-folding ()
  (with-temp-buffer
    (insert "* Task\n:PROPERTIES:\n:CREATED: [2026-09-17 Thu]\n:END:\n"
            ":LOGBOOK:\n- Note taken on [2026-09-17 Thu] \\\\\n  Prose with [[https://example.com][a link]].\n:END:\n\nOutside\n")
    (let ((text (buffer-string)))
      (org-mode)
      (org-fold-show-all)
      (set-buffer-modified-p nil)
      (font-lock-ensure)
      (should (equal text (buffer-substring-no-properties (point-min) (point-max))))
      (should-not (buffer-modified-p))
      (dolist (drawer '((":PROPERTIES:" "CREATED")
                       (":LOGBOOK:" "Prose")))
        (goto-char (point-min))
        (search-forward (car drawer))
        (let ((faces (ensure-list (get-text-property (1- (point)) 'face))))
          (should (eq (car faces) 'suderman/org-drawer-label))
          (should-not (memq 'suderman/org-drawer-block faces)))
        (should (memq 'suderman/org-drawer-block
                      (ensure-list (get-text-property (point) 'face))))
        (org-fold-hide-drawer-toggle t)
        (search-forward (cadr drawer))
        (should (org-invisible-p (1- (point))))
        (goto-char (point-min))
        (search-forward (car drawer))
        (org-fold-hide-drawer-toggle nil)
        (search-forward (cadr drawer))
        (should-not (org-invisible-p (1- (point))))
        (should (memq 'suderman/org-drawer-block
                      (ensure-list (get-text-property (1- (point)) 'face))))
        (search-forward ":END:")
        (let ((faces (ensure-list (get-text-property (1- (point)) 'face))))
          (should (eq (car faces) 'org-block-end-line))
          (should (memq 'suderman/org-drawer-block faces))))
      (goto-char (point-min))
      (search-forward ":CREATED:")
      (should (memq 'org-special-keyword
                    (ensure-list (get-text-property (1- (point)) 'face))))
      (search-forward "2026-09-17")
      (should (memq 'org-date (ensure-list (get-text-property (1- (point)) 'face))))
      (search-forward "a link")
      (should (memq 'org-link (ensure-list (get-text-property (1- (point)) 'face))))
      (search-forward "Outside")
      (should-not (memq 'suderman/org-drawer-block
                        (ensure-list (get-text-property (1- (point)) 'face)))))))

(ert-deftest suderman/org-drawer-blocks-refontify-after-edits ()
  (with-temp-buffer
    (insert "* Task\n:LOGBOOK:\nFirst note\n:END:\nOutside\n")
    (org-mode)
    (org-fold-show-all)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "First")
    (insert " edited")
    (font-lock-ensure (line-beginning-position) (line-end-position))
    (should (memq 'suderman/org-drawer-block
                  (ensure-list (get-text-property (1- (point)) 'face))))
    (search-forward ":END:")
    (delete-region (match-beginning 0) (match-end 0))
    (font-lock-ensure (line-beginning-position) (line-beginning-position 2))
    (goto-char (point-min))
    (search-forward "First")
    (should-not (memq 'suderman/org-drawer-block
                      (ensure-list (get-text-property (1- (point)) 'face)))))
  (with-temp-buffer
    (insert "* Task\n:LOGBOOK:\nNew note\n")
    (org-mode)
    (font-lock-ensure)
    (goto-char (point-max))
    (insert ":END:")
    (font-lock-ensure (line-beginning-position) (point-max))
    (goto-char (point-min))
    (search-forward "New note")
    (should (memq 'suderman/org-drawer-block
                  (ensure-list (get-text-property (1- (point)) 'face))))))

(provide 'suderman-org-test)
;;; suderman-org-test.el ends here
