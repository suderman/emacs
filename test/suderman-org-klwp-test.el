;;; suderman-org-klwp-test.el --- KLWP agenda export checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'json)
(require 'suderman-org-klwp)

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

;;; suderman-org-klwp-test.el ends here
