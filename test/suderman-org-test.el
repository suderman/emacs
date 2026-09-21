;;; suderman-org-test.el --- Org workflow and export checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for custom behavior with enough moving parts to merit a safety net.

;;; Code:

(require 'ert)
(require 'json)
(require 'org-agenda)
(require 'org-archive)
(require 'suderman-org)
(require 'suderman-org-klwp)

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

(ert-deftest suderman/org-bulk-archive-saves-done-trees-in-their-own-archives ()
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
            (insert "* DONE Finished parent\n** DONE Finished child\n"
                    "* DONE Mixed parent\n** TODO Still open\n"
                    "** DONE Finished under mixed parent\n"
                    "* TODO Keep working\n"))
          (with-temp-file second
            (insert "* DONE Special\n:PROPERTIES:\n"
                    ":ARCHIVE: special.org::\n:END:\n"))
          (cl-letf (((symbol-function 'yes-or-no-p)
                     (lambda (&rest _) (error "Batch archiving prompted")))
                    ((symbol-function 'org-agenda-maybe-redo)
                     (lambda () (setq refreshed t))))
            (should (= (suderman/org-archive-done) 3)))
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
          (should (= (suderman/org-archive-done) 0)))
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
          (cl-letf (((symbol-function 'yes-or-no-p)
                     (lambda (_prompt) (setq asked t) nil)))
            (should (= (call-interactively #'suderman/org-archive-done) 0))
            (should asked)
            (should (= (let ((current-prefix-arg '(4)))
                         (call-interactively #'suderman/org-archive-done))
                       1)))
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

(ert-deftest suderman/org-revert-refreshes-visible-agenda-only-for-synced-files ()
  (let* ((org-directory (make-temp-file "suderman-org-" t))
         (inside (expand-file-name "todo.org" org-directory))
         (outside (make-temp-file "suderman-org-outside-" nil ".org"))
         (agenda-buffer (generate-new-buffer " *suderman-org-agenda*"))
         refreshed)
    (unwind-protect
        (cl-letf (((symbol-function 'org-agenda-maybe-redo)
                   (lambda ()
                     (setq refreshed t)
                     (set-buffer agenda-buffer))))
          (with-temp-buffer
            (setq buffer-file-name inside)
            (org-mode)
            (should (local-variable-p 'after-revert-hook))
            (should (memq #'suderman/org-refresh-agenda-after-revert
                          after-revert-hook))
            (run-hooks 'after-revert-hook)
            (should refreshed)
            (should-not (eq (current-buffer) agenda-buffer)))
          (setq refreshed nil)
          (with-temp-buffer
            (setq buffer-file-name outside)
            (org-mode)
            (should-not
             (memq #'suderman/org-refresh-agenda-after-revert
                   after-revert-hook)))
          (should-not refreshed))
      (delete-directory org-directory t)
      (delete-file outside)
      (kill-buffer agenda-buffer))))


;; Context-sensitive commands

(ert-deftest suderman/org-agenda-dirvish-uses-selected-entry-file ()
  (let* ((source (generate-new-buffer " *agenda-source*"))
         (agenda (generate-new-buffer " *agenda-files*"))
         (file "/tmp/suderman-agenda-entry.org")
         (marker (with-current-buffer source
                   (setq buffer-file-name file)
                   (point-marker)))
         opened)
    (unwind-protect
        (cl-letf (((symbol-function 'suderman/dirvish)
                   (lambda (path) (setq opened path))))
          (with-current-buffer agenda
            (org-agenda-mode)
            (let ((inhibit-read-only t))
              (insert "Entry\n")
              (put-text-property (point-min) (point-max)
                                 'org-marker marker))
            (goto-char (point-min))
            (suderman/org-agenda-dirvish)
            (should (equal opened file))
            (remove-text-properties (point-min) (point-max)
                                    '(org-marker nil))
            (suderman/org-agenda-dirvish)
            (should (equal opened org-directory))))
      (set-marker marker nil)
      (kill-buffer source)
      (kill-buffer agenda))))

(ert-deftest suderman/org-item-commands-follow-buffer-context ()
  (dolist (binding '(("A" . suderman/org-archive)
                     ("d" . suderman/org-deadline)
                     ("e" . suderman/org-export)
                     ("g" . suderman/org-heading)
                     ("i" . suderman/org-insert-link)
                     ("r" . suderman/org-refile)
                     ("s" . suderman/org-schedule)
                     ("t" . suderman/org-todo)
                     ("x" . suderman/org-toggle-checkbox)))
    (should (eq (lookup-key suderman/leader-org-map (kbd (car binding)))
                (cdr binding))))
  (let (called)
    (cl-letf (((symbol-function 'consult-org-agenda)
               (lambda () (interactive) (setq called 'consult-org-agenda)))
              ((symbol-function 'org-agenda-archive)
               (lambda () (interactive) (setq called 'org-agenda-archive)))
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
              ((symbol-function 'org-archive-subtree)
               (lambda () (interactive) (setq called 'org-archive-subtree)))
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
      (dolist (case '((org-mode suderman/org-archive org-archive-subtree)
                      (org-mode suderman/org-deadline org-deadline)
                      (org-mode suderman/org-export org-export-dispatch)
                      (org-mode suderman/org-heading consult-org-heading)
                      (org-mode suderman/org-insert-link org-insert-link)
                      (org-mode suderman/org-refile org-refile)
                      (org-mode suderman/org-schedule org-schedule)
                      (org-mode suderman/org-todo org-todo)
                      (org-mode suderman/org-toggle-checkbox org-toggle-checkbox)
                      (org-agenda-mode suderman/org-archive org-agenda-archive)
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

(ert-deftest suderman/org-item-commands-pass-prefix-arguments ()
  (let (received)
    (cl-letf (((symbol-function 'org-schedule)
               (lambda (arg)
                 (interactive "P")
                 (setq received arg))))
      (with-temp-buffer
        (org-mode)
        (let ((current-prefix-arg '(4)))
          (call-interactively #'suderman/org-schedule))))
    (should (equal received '(4)))))


;; Font-lock regressions

(ert-deftest suderman/org-dates-respect-protected-text ()
  (let ((org-display-custom-times t)
        (org-time-stamp-custom-formats '("<%d/%m/%Y>" . "<%d/%m/%Y %H:%M>")))
    (with-temp-buffer
      (insert "# <2026-06-01> [2026-06-01]\n"
              "#+begin_example\n<2026-06-01> [2026-06-01]\n#+end_example\n"
              "#+begin_src emacs-lisp\n\"<2026-06-01> [2026-06-01]\"\n#+end_src\n")
      (org-mode)
      (font-lock-ensure)
      (goto-char (point-min))
      (while (search-forward "2026-06-01" nil t)
        (let ((faces (get-text-property (match-beginning 0) 'face)))
          (should-not (memq 'org-date (ensure-list faces)))
          ;; Org clears custom time display in blocks, but not comments.
          (unless (save-excursion (beginning-of-line) (looking-at-p "# "))
            (should-not (get-text-property (match-beginning 0) 'display))))))))

(ert-deftest suderman/org-drawer-blocks-preserve-content-and-folding ()
  (with-temp-buffer
    (insert "* Task\n:PROPERTIES:\n:CREATED: [2026-09-17 Thu]\n:END:\n"
            ":LOGBOOK:\n- Note taken on [2026-09-17 Thu] \\\\\n  Prose with [[https://example.com][a link]].\n:END:\n\nOutside\n")
    (let ((text (buffer-string)))
      (org-mode)
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

(ert-deftest suderman/org-drawer-blocks-ignore-protected-and-unclosed-text ()
  (with-temp-buffer
    (insert "* Task\n#+begin_src text\n:LOGBOOK:\nnot a drawer\n:END:\n#+end_src\n"
            "#+begin_example\n:PROPERTIES:\n:X: not a drawer\n:END:\n#+end_example\n"
            ":OTHER:\nOther drawer\n:END:\n"
            ":LOGBOOK:\nUnclosed drawer\n* Next\nOutside\n")
    (org-mode)
    (font-lock-ensure)
    (let ((position (point-min)))
      (while (< position (point-max))
        (should-not (memq 'suderman/org-drawer-block
                          (ensure-list (get-text-property position 'face))))
        (setq position (1+ position))))))

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

(ert-deftest suderman/org-drawer-blocks-handle-eof-and-affiliated-keywords ()
  (dolist (case '(("* Task\n:PROPERTIES:\n:ID: example\n:END:" "example")
                  ("* Task\n:LOGBOOK:\nA note\n:END:" "A note")
                  ("* Task\n#+name: history\n:LOGBOOK:\nA note\n:END:\n" "A note")))
    (with-temp-buffer
      (insert (car case))
      (org-mode)
      (font-lock-ensure)
      (goto-char (point-min))
      (search-forward (cadr case))
      (let ((faces (ensure-list (get-text-property (1- (point)) 'face))))
        (should (memq 'suderman/org-drawer-block faces))
        (should-not (memq 'suderman/org-drawer-label faces)))
      (search-forward ":END:")
      (let ((faces (ensure-list (get-text-property (1- (point)) 'face))))
        (should (eq (car faces) 'org-block-end-line))
        (should (memq 'suderman/org-drawer-block faces)))
      (goto-char (point-min))
      (when (search-forward "#+name:" nil t)
        (should-not (memq 'suderman/org-drawer-block
                          (ensure-list (get-text-property (1- (point)) 'face))))))))

(ert-deftest suderman/org-drawer-blocks-refresh-existing-buffers ()
  (with-temp-buffer
    (insert "#+begin_src text\ncontent\n#+end_src\n"
            "* Task\n:PROPERTIES:\n:ID: example\n:END:\n")
    (org-mode)
    (font-lock-ensure)
    ;; Simulate a buffer whose keywords predate source-opener styling.
    (font-lock-remove-keywords
     nil '((suderman/org-fontify-source-block-openers)))
    (font-lock-flush)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "#+begin_src text")
    (should-not (memq 'org-block
                      (ensure-list (get-text-property (point) 'face))))
    (search-forward "example")
    (add-face-text-property (1- (point)) (point) 'suderman/old-drawer-face)
    (suderman/org-refresh-drawer-blocks)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "#+begin_src text")
    (should (memq 'org-block
                  (ensure-list (get-text-property (point) 'face))))
    (search-forward "example")
    (let ((faces (ensure-list (get-text-property (1- (point)) 'face))))
      (should (memq 'suderman/org-drawer-block faces))
      (should-not (memq 'suderman/old-drawer-face faces)))
    (let ((keywords (copy-tree font-lock-keywords)))
      (suderman/org-refresh-drawer-blocks)
      (should (equal font-lock-keywords keywords)))))


;; Mouse behavior

(ert-deftest suderman/org-mouse-cycles-todo-on-left-click ()
  (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
    (with-temp-buffer
      (insert "* TODO item\n")
      (org-mode)
      (font-lock-ensure)
      (goto-char (+ (point-min) 2))
      (let ((map (get-text-property (point) 'keymap)))
        (should (eq (lookup-key map [mouse-1])
                    #'suderman/org-mouse-cycle-todo)))
      (cl-letf (((symbol-function 'mouse-set-point)
                 (lambda (_event) (goto-char (+ (point-min) 2)))))
        (suderman/org-mouse-cycle-todo nil))
      (should (equal (org-get-todo-state) "NEXT"))
      (cl-letf (((symbol-function 'mouse-set-point)
                 (lambda (_event) (goto-char (+ (point-min) 2)))))
        (suderman/org-mouse-cycle-todo nil)
        (should (equal (org-get-todo-state) "DONE"))
        (suderman/org-mouse-cycle-todo nil)
        (should (equal (org-get-todo-state) "TODO"))))))

(ert-deftest suderman/org-mouse-todo-menu-clears-state ()
  (let ((org-todo-keywords '((sequence "TODO" "NEXT" "|" "DONE"))))
    (with-temp-buffer
      (insert "* DONE item\n")
      (org-mode)
      (goto-char (+ (point-min) 2))
      (let ((clear
             (cl-find-if
              (lambda (item)
                (and (vectorp item)
                     (equal (aref item 0) "Clear")))
              (org-mouse-todo-menu "DONE"))))
        (should clear)
        (should (equal (aref clear 1) '(org-todo "")))
        (should (aref clear 2))
        (eval (aref clear 1))
        (should-not (org-get-todo-state))))))


;; KLWP agenda export

(ert-deftest suderman/org-klwp-counts-unique-dated-items-and-overdue-headings ()
  (let* ((directory (make-temp-file "org-klwp-fixture-" t))
         (file (expand-file-name "agenda.org" directory))
         (org-agenda-files (list file)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* TODO Late\nSCHEDULED: <2026-09-17 Thu>\n"
                    "* TODO Both overdue dates\n"
                    "SCHEDULED: <2026-09-17 Thu> DEADLINE: <2026-09-16 Wed>\n"
                    "* HOLD Paused\nSCHEDULED: <2026-09-17 Thu>\n"
                    "* DONE Finished\nSCHEDULED: <2026-09-17 Thu>\n"
                    "* TODO Today\nSCHEDULED: <2026-09-18 Fri>\n"
                    "* Event today\n<2026-09-18 Fri 12:00-13:30>\n"
                    "* Event tomorrow\n<2026-09-19 Sat 16:00-17:00>\n"
                    "* TODO Duplicated date\n"
                    "SCHEDULED: <2026-09-19 Sat>\n<2026-09-19 Sat>\n"
                    "* TODO Due in fourteen days\nDEADLINE: <2026-10-02 Fri>\n"
                    "* TODO Too far away\nSCHEDULED: <2026-10-03 Sat>\n"))
          (let ((today (calendar-absolute-from-gregorian '(9 18 2026))))
            (cl-letf (((symbol-function 'org-today) (lambda () today)))
              (let* ((tomorrow (suderman/org-klwp--day-entries
                                (1+ today) (list file)))
                     (snapshot (suderman/org-klwp-snapshot '(9 18 2026) 1400))
                     (current (suderman/org-klwp-snapshot '(9 18 2026) 1230))
                     (counts (alist-get 'counts snapshot)))
                (should (= 2 (alist-get 'overdue counts)))
                (should (= 2 (alist-get 'today counts)))
                (should (= 3 (alist-get 'next14 counts)))
                (should (= 2 (length tomorrow)))
                (should (equal "Event tomorrow"
                               (alist-get 'title (alist-get 'next snapshot))))
                (should (equal "Sat, Sep 19"
                               (alist-get 'when (alist-get 'next snapshot))))
                (should (equal "16:00"
                               (alist-get 'start (alist-get 'next snapshot))))
                (should (equal "17:00"
                               (alist-get 'end (alist-get 'next snapshot))))
                (should (equal "16:00 – 17:00"
                               (alist-get 'time (alist-get 'next snapshot))))
                (should (equal "Event today"
                               (alist-get 'title (alist-get 'next current))))
                (should (equal "Today"
                               (alist-get 'when (alist-get 'next current))))
                (should (equal "12:00 – 13:30"
                               (alist-get 'time (alist-get 'next current))))
                (should (string-prefix-p "2026-09-18T13:30:00"
                                         (alist-get 'refresh current)))))))
      (when-let* ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest suderman/org-klwp-expands-repeating-timestamps ()
  (let* ((directory (make-temp-file "org-klwp-repeat-" t))
         (file (expand-file-name "agenda.org" directory))
         (org-agenda-files (list file)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Daily appointment\n<2026-09-18 Fri 08:00-09:00 +1d>\n"))
          (let* ((snapshot (suderman/org-klwp-snapshot '(9 18 2026) 1200))
                 (next (alist-get 'next snapshot))
                 (counts (alist-get 'counts snapshot)))
            (should (= 1 (alist-get 'today counts)))
            (should (= 14 (alist-get 'next14 counts)))
            (should (equal "Daily appointment" (alist-get 'title next)))
            (should (equal "Sat, Sep 19" (alist-get 'when next)))))
      (when-let* ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest suderman/org-klwp-keeps-later-occurrence-on-the-same-heading ()
  (let* ((directory (make-temp-file "org-klwp-occurrences-" t))
         (file (expand-file-name "agenda.org" directory))
         (org-agenda-files (list file)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Two appointments\n"
                    "<2026-09-18 Fri 09:00-10:00>\n"
                    "<2026-09-18 Fri 17:00-18:00>\n"))
          (let* ((snapshot (suderman/org-klwp-snapshot '(9 18 2026) 1200))
                 (next (alist-get 'next snapshot)))
            (should (= 1 (alist-get 'today (alist-get 'counts snapshot))))
            (should (equal "Two appointments" (alist-get 'title next)))
            (should (equal "17:00 – 18:00" (alist-get 'time next)))))
      (when-let* ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest suderman/org-klwp-broadcasts-snapshot-with-freshness-last ()
  (let ((system-type 'android)
        calls)
    (cl-letf (((symbol-function 'call-process)
               (lambda (_program _infile _destination _display &rest args)
                 (push (cons (nth 8 args) (nth 11 args)) calls)
                 0)))
      (suderman/org-klwp--broadcast-snapshot
       '((generated . "2026-09-19T07:00:00-06:00")
         (refresh . "2026-09-20T00:00:00-06:00")
         (next . nil)
         (counts . ((overdue . 2) (today . 0) (next14 . 19))))))
    (setq calls (nreverse calls))
    (should (equal '("title" "when" "ntime" "overdue" "today" "next14"
                     "generated")
                   (mapcar #'car calls)))
    (should (equal '("null" "null" "null" "2" "0" "19"
                     "2026-09-19T07:00:00-06:00")
                   (mapcar #'cdr calls)))))

(ert-deftest suderman/org-klwp-export-preserves-snapshot-on-failure ()
  (let* ((directory (make-temp-file "org-klwp-output-" t))
         (file (expand-file-name "org-agenda.json" directory)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "old snapshot\n"))
          (cl-letf (((symbol-function 'suderman/org-klwp-snapshot)
                     (lambda (&rest _) (error "Agenda unavailable"))))
            (should-error (suderman/org-export-klwp-agenda file)))
          (should (equal "old snapshot\n"
                         (with-temp-buffer
                           (insert-file-contents file)
                           (buffer-string))))
          (should (= 1 (length (directory-files directory nil "^[^.].*")))))
      (delete-directory directory t))))

(ert-deftest suderman/org-klwp-export-writes-valid-json ()
  (let* ((directory (make-temp-file "org-klwp-output-" t))
         (file (expand-file-name "org-agenda.json" directory)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'suderman/org-klwp-snapshot)
                     (lambda (&rest _)
                       '((generated . "2026-09-18T12:00:00-06:00")
                         (next . nil)
                         (counts . ((overdue . 0) (today . 0) (next14 . 0)))))))
            (should (equal file (suderman/org-export-klwp-agenda file))))
          (let ((data (json-read-file file)))
            (should (equal "2026-09-18T12:00:00-06:00"
                           (alist-get 'generated data)))
            (should (equal 0 (alist-get 'today (alist-get 'counts data))))
            (should-not (alist-get 'next data))))
      (delete-directory directory t))))

(ert-deftest suderman/org-klwp-reloads-externally-changed-unmodified-files ()
  (let* ((directory (make-temp-file "org-klwp-sync-" t))
         (file (expand-file-name "agenda.org" directory))
         (org-agenda-files (list file)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Old event\n<2026-09-18 Fri>\n"))
          (let ((buffer (find-file-noselect file)))
            (with-temp-file file
              (insert "* New event\n<2026-09-18 Fri>\n"))
            (set-file-times file (time-add (current-time) 5))
            (should (equal "New event"
                           (alist-get 'title
                                      (alist-get 'next
                                                 (suderman/org-klwp-snapshot
                                                  '(9 18 2026))))))
            (with-current-buffer buffer
              (should (search-forward "New event" nil t)))))
      (when-let* ((buffer (find-buffer-visiting file))) (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest suderman/org-klwp-refreshes-only-when-state-changes ()
  (let* ((directory (make-temp-file "org-klwp-state-" t))
         (suderman/org-klwp-file (expand-file-name "agenda.json" directory))
         (suderman/org-klwp--last-state nil)
         (state '("2026-09-18" ("agenda.org" 1 20)))
         (exports 0))
    (unwind-protect
        (cl-letf (((symbol-function 'suderman/org-klwp--state)
                   (lambda () state))
                  ((symbol-function 'suderman/org-export-klwp-agenda)
                   (lambda (&rest _)
                     (cl-incf exports)
                     (with-temp-file suderman/org-klwp-file (insert "{}")))))
          (suderman/org-klwp--refresh-if-needed)
          (suderman/org-klwp--refresh-if-needed)
          (should (= exports 1))
          (setq suderman/org-klwp--next-refresh (time-subtract (current-time) 1))
          (suderman/org-klwp--refresh-if-needed)
          (should (= exports 2))
          (setq suderman/org-klwp--next-refresh (time-add (current-time) 3600)
                state '("2026-09-19" ("agenda.org" 1 20)))
          (suderman/org-klwp--refresh-if-needed)
          (should (= exports 3))
          (setq state '("2026-09-19" ("agenda.org" 2 20)))
          (suderman/org-klwp--refresh-if-needed)
          (should (= exports 4)))
      (delete-directory directory t))))

(ert-deftest suderman/org-klwp-debounces-only-saved-agenda-files ()
  (let* ((directory (make-temp-file "org-klwp-save-" t))
         (inside (expand-file-name "todo.org" directory))
         (outside (expand-file-name "other.org" directory))
         (org-agenda-files (list inside))
         (suderman/org-klwp--refresh-timer nil)
         calls)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (&rest args) (push args calls) nil)))
            (dolist (file (list inside outside))
              (with-temp-buffer
                (setq buffer-file-name file)
                (org-mode)
                (suderman/org-klwp--queue-refresh)))
            (should (= 1 (length calls)))
            (should (equal 5 (caar calls)))))
      (delete-directory directory t))))

(provide 'suderman-org-test)
;;; suderman-org-test.el ends here
