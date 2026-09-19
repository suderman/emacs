;;; suderman-org-klwp.el --- Small Org agenda snapshot for KLWP -*- lexical-binding: t; -*-

;;; Commentary:
;; Org remains the authority for dated occurrences.  This module exports only
;; display data; the wallpaper never parses Org files.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'org-agenda)

(defvar suderman/org-klwp-file
  (if (eq system-type 'android)
      "/storage/emulated/0/Kustom/data/org-agenda/snapshot.json"
    (expand-file-name "~/.cache/org-agenda.json"))
  "Destination for the generated agenda snapshot.")

(defun suderman/org-klwp--actionable-p (state)
  "Return non-nil if STATE is an actionable TODO state."
  (member state '("TODO" "PROG" "EVAL")))

(defun suderman/org-klwp--entry-on-day-p (item day)
  "Return non-nil when agenda ITEM occurs on absolute DAY."
  (let ((entry-date (get-text-property 0 'date item)))
    (if (integerp entry-date)
        (= entry-date day)
      (equal entry-date (calendar-gregorian-from-absolute day)))))

(defun suderman/org-klwp--entry (item day)
  "Return a dated display record for Org agenda ITEM on absolute DAY.
Discard carry-forward schedules, deadline warnings, completed items, and
on-hold tasks.  Org provides occurrence dates and times as item properties."
  (when (and (stringp item)
             (suderman/org-klwp--entry-on-day-p item day)
             (not (member (get-text-property 0 'type item)
                          '("past-scheduled" "upcoming-deadline"))))
    (let ((marker (get-text-property 0 'org-hd-marker item)))
      (when (and (markerp marker) (marker-buffer marker))
        (with-current-buffer (marker-buffer marker)
          (save-excursion
            (goto-char marker)
            (org-back-to-heading t)
            (let ((state (org-get-todo-state))
                  (time (get-text-property 0 'time-of-day item))
                  (duration (get-text-property 0 'duration item)))
              (unless (and state (not (suderman/org-klwp--actionable-p state)))
                (list :key (cons (buffer-file-name) (point))
                      :title (org-get-heading t t t t)
                      :kind (if state "task" "event")
                      :day day
                      :time (and (numberp time) time)
                      :duration (and (numberp duration) duration))))))))))

(defun suderman/org-klwp--day-occurrences (day files)
  "Return every actionable occurrence on absolute DAY from FILES."
  (let ((date (calendar-gregorian-from-absolute day))
        entries)
    (dolist (file files)
      (dolist (item (org-agenda-get-day-entries
                     file date :deadline :scheduled :timestamp :sexp))
        (when-let* ((entry (suderman/org-klwp--entry item day)))
          (push entry entries))))
    (nreverse entries)))

(defun suderman/org-klwp--unique-entries (entries)
  "Return ENTRIES deduplicated by heading, preserving their first order."
  (let ((seen (make-hash-table :test 'equal))
        unique)
    (dolist (entry entries)
      (let ((key (plist-get entry :key)))
        (unless (gethash key seen)
          (puthash key t seen)
          (push entry unique))))
    (nreverse unique)))

(defun suderman/org-klwp--day-entries (day files)
  "Return headings with actionable occurrences on absolute DAY from FILES."
  (suderman/org-klwp--unique-entries
   (suderman/org-klwp--day-occurrences day files)))

(defun suderman/org-klwp--overdue-count (day files)
  "Count unfinished actionable headings overdue before absolute DAY in FILES."
  (let ((org-agenda-files files)
        (count 0))
    (org-map-entries
     (lambda ()
       (when (and (suderman/org-klwp--actionable-p (org-get-todo-state))
                  (cl-some (lambda (property)
                             (when-let* ((value (org-entry-get nil property)))
                               (< (org-time-string-to-absolute value) day)))
                           '("SCHEDULED" "DEADLINE")))
         (cl-incf count)))
     nil 'agenda 'archive 'comment)
    count))

(defun suderman/org-klwp--display-entry (entry reference-day)
  "Format ENTRY relative to absolute REFERENCE-DAY for the JSON schema."
  (let* ((absolute-day (plist-get entry :day))
         (day (calendar-gregorian-from-absolute absolute-day))
         (time (plist-get entry :time))
         (duration (plist-get entry :duration))
         (hour (and time (/ time 100)))
         (minute (and time (% time 100)))
         (minutes (and time (+ (* hour 60) minute)))
         (start (and minutes (format "%02d:%02d" hour minute)))
         (end (and minutes duration
                   (format "%02d:%02d" (% (/ (+ minutes (round duration)) 60) 24)
                           (% (+ minutes (round duration)) 60)))))
    `((title . ,(plist-get entry :title))
      (date . ,(format "%04d-%02d-%02d" (nth 2 day) (nth 0 day) (nth 1 day)))
      (when . ,(if (= absolute-day reference-day)
                   "Today"
                 (format-time-string "%a, %b %-d"
                                     (encode-time 0 0 12 (nth 1 day)
                                                  (nth 0 day) (nth 2 day)))))
      (kind . ,(plist-get entry :kind))
      (start . ,start)
      (end . ,end)
      (time . ,(if start
                   (if end (concat start " – " end) start)
                 "All day")))))

(defun suderman/org-klwp--time-on-day (day minutes)
  "Return a local Emacs time MINUTES after midnight on absolute DAY."
  (let ((date (calendar-gregorian-from-absolute day)))
    (encode-time 0 (% minutes 60) (/ minutes 60)
                 (nth 1 date) (nth 0 date) (nth 2 date))))

(defun suderman/org-klwp--next-refresh-time (day entry)
  "Return the next semantic-change time after DAY for selected ENTRY."
  (let ((midnight (suderman/org-klwp--time-on-day (1+ day) 0)))
    (if (and entry
             (= (plist-get entry :day) day)
             (numberp (plist-get entry :time)))
        (let* ((start (plist-get entry :time))
               (start-minutes (+ (* (/ start 100) 60) (% start 100)))
               (duration (plist-get entry :duration))
               (boundary (suderman/org-klwp--time-on-day
                          day (+ start-minutes (max 1 (round (or duration 1)))))))
          (if (time-less-p boundary midnight) boundary midnight))
      midnight)))

(defun suderman/org-klwp--sync-agenda-buffers (files)
  "Revert unmodified visiting FILES changed externally before reading Org."
  (dolist (file files)
    (when-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer
        (unless (verify-visited-file-modtime buffer)
          (when (buffer-modified-p buffer)
            (error "Agenda file changed on disk with unsaved edits: %s" file))
          (revert-buffer t t t))))))

(defun suderman/org-klwp-snapshot (&optional date current-time)
  "Return a JSON-ready agenda snapshot for calendar DATE, default today.
CURRENT-TIME is an HHMM integer used by tests; default to the current time.
TODAY counts unique actionable dated headings and events today, not carried
schedules or early deadline warnings.  NEXT14 counts unique occurrences on
tomorrow through the fourteenth day, allowing a repeat on each day.  OVERDUE
counts each actionable heading once if its schedule or deadline precedes DATE.
HOLD and DONE are not actionable.  NEXT prefers the earliest current or future
event; otherwise it uses the earliest task.  A missing event is JSON null."
  (let* ((day (calendar-absolute-from-gregorian (or date (calendar-current-date))))
         (files (org-agenda-files t))
         (_ (suderman/org-klwp--sync-agenda-buffers files))
         (today-occurrences (suderman/org-klwp--day-occurrences day files))
         (today (suderman/org-klwp--unique-entries today-occurrences))
         (future-occurrences
          (cl-loop for offset from 1 to 14
                   append (suderman/org-klwp--day-occurrences (+ day offset) files)))
         (future (cl-loop for offset from 1 to 14
                          append (suderman/org-klwp--day-entries
                                  (+ day offset) files)))
         (candidates (append today-occurrences future-occurrences))
         (now (or current-time
                  (+ (* (string-to-number (format-time-string "%H")) 100)
                     (string-to-number (format-time-string "%M")))))
         (upcoming (cl-remove-if
                    (lambda (entry)
                      (when (and (= (plist-get entry :day) day)
                                 (numberp (plist-get entry :time)))
                        (let* ((start (plist-get entry :time))
                               (start-minutes (+ (* (/ start 100) 60) (% start 100)))
                               (duration (plist-get entry :duration))
                               (end-minutes (and duration
                                                 (+ start-minutes duration)))
                               (now-minutes (+ (* (/ now 100) 60) (% now 100))))
                          (if end-minutes
                              (<= end-minutes now-minutes)
                            (< start now)))))
                    candidates))
         (sorted (sort upcoming
                       (lambda (a b)
                         (or (< (plist-get a :day) (plist-get b :day))
                             (and (= (plist-get a :day) (plist-get b :day))
                                  (< (or (plist-get a :time) 0)
                                     (or (plist-get b :time) 0)))))))
         (next (or (cl-find "event" sorted :key (lambda (e) (plist-get e :kind))
                            :test #'equal)
                   (car sorted))))
    `((generated . ,(format-time-string "%Y-%m-%dT%H:%M:%S%:z"))
      (refresh . ,(format-time-string "%Y-%m-%dT%H:%M:%S%:z"
                                     (suderman/org-klwp--next-refresh-time day next)))
      (next . ,(and next (suderman/org-klwp--display-entry next day)))
      (counts . ((overdue . ,(suderman/org-klwp--overdue-count day files))
                 (today . ,(length today))
                 (next14 . ,(length future)))))))

(defvar suderman/org-klwp--refresh-timer nil)
(defvar suderman/org-klwp--check-timer nil)
(defvar suderman/org-klwp--focus-timer nil)
(defvar suderman/org-klwp--boundary-timer nil)
(defvar suderman/org-klwp--next-refresh nil)
(defvar suderman/org-klwp--last-state nil)

(defun suderman/org-klwp--schedule-boundary-refresh (snapshot)
  "Schedule SNAPSHOT's next semantic-change export when running on Android."
  (when-let* ((refresh (alist-get 'refresh snapshot)))
    (setq suderman/org-klwp--next-refresh (date-to-time refresh))
    (when (timerp suderman/org-klwp--boundary-timer)
      (cancel-timer suderman/org-klwp--boundary-timer))
    (when (eq system-type 'android)
      (setq suderman/org-klwp--boundary-timer
            (run-at-time suderman/org-klwp--next-refresh nil
                         'suderman/org-klwp--refresh-if-needed t)))))

(defun suderman/org-klwp--broadcast-snapshot (snapshot)
  "Publish SNAPSHOT fields to Kustom on Android, with freshness sent last."
  (when (eq system-type 'android)
    (let* ((next (alist-get 'next snapshot))
           (counts (alist-get 'counts snapshot))
           (values `(("title" . ,(or (alist-get 'title next) "null"))
                     ("when" . ,(or (alist-get 'when next) "null"))
                     ("ntime" . ,(or (alist-get 'time next) "null"))
                     ("overdue" . ,(number-to-string (alist-get 'overdue counts)))
                     ("today" . ,(number-to-string (alist-get 'today counts)))
                     ("next14" . ,(number-to-string (alist-get 'next14 counts)))
                     ("generated" . ,(alist-get 'generated snapshot)))))
      (condition-case err
          (dolist (entry values)
            (unless (zerop
                     (call-process
                      "/system/bin/am" nil nil nil
                      "broadcast" "-a" "org.kustom.action.SEND_VAR"
                      "--es" "org.kustom.action.EXT_NAME" "org"
                      "--es" "org.kustom.action.VAR_NAME" (car entry)
                      "--es" "org.kustom.action.VAR_VALUE" (cdr entry)))
              (error "Kustom rejected agenda variable %s" (car entry))))
        (error (message "KLWP agenda JSON written; broadcast failed: %s"
                        (error-message-string err)))))))

(defun suderman/org-export-klwp-agenda (&optional file)
  "Write an atomic Org agenda snapshot to FILE or `suderman/org-klwp-file'.
Do not replace a good snapshot on failure.  A missing output directory is an
error rather than an implicit new directory in shared storage."
  (interactive)
  (let* ((target (or file suderman/org-klwp-file))
         (directory (file-name-directory target))
         (snapshot (suderman/org-klwp-snapshot))
         (temp nil))
    (unless (file-directory-p directory)
      (error "KLWP output directory does not exist: %s" directory))
    (unwind-protect
        (progn
          (setq temp (make-temp-file (expand-file-name ".org-agenda-" directory)))
          (with-temp-file temp
            (insert (json-encode snapshot) "\n"))
          (rename-file temp target t)
          (setq temp nil)
          (when (equal target suderman/org-klwp-file)
            (suderman/org-klwp--schedule-boundary-refresh snapshot)
            (suderman/org-klwp--broadcast-snapshot snapshot))
          target)
      (when (and temp (file-exists-p temp))
        (delete-file temp)))))

(defun suderman/org-klwp--state ()
  "Return agenda file timestamps/sizes and today's date for change checks."
  (cons (format-time-string "%Y-%m-%d")
        (mapcar (lambda (file)
                  (let ((attributes (file-attributes file)))
                    (list file (file-attribute-modification-time attributes)
                          (file-attribute-size attributes))))
                (org-agenda-files t))))

(defun suderman/org-klwp--refresh-if-needed (&optional force)
  "Regenerate after input, date, or event-boundary changes.
FORCE is non-nil for the exact boundary timer."
  (condition-case err
      (let ((state (suderman/org-klwp--state)))
        (unless (and (not force)
                     (equal state suderman/org-klwp--last-state)
                     (file-exists-p suderman/org-klwp-file)
                     (or (not suderman/org-klwp--next-refresh)
                         (time-less-p (current-time)
                                      suderman/org-klwp--next-refresh)))
          (suderman/org-export-klwp-agenda)
          (setq suderman/org-klwp--last-state state)))
    (error (message "KLWP agenda kept old snapshot: %s"
                    (error-message-string err)))))

(defun suderman/org-klwp--queue-refresh ()
  "Debounce a saved agenda file without delaying the save itself."
  (when (and buffer-file-name
             (derived-mode-p 'org-mode)
             (member (expand-file-name buffer-file-name) (org-agenda-files t)))
    (when (timerp suderman/org-klwp--refresh-timer)
      (cancel-timer suderman/org-klwp--refresh-timer))
    (setq suderman/org-klwp--refresh-timer
          (run-at-time 5 nil #'suderman/org-klwp--refresh-if-needed))))

(defun suderman/org-klwp--focus-check (&rest _)
  "Defer an agenda check when Emacs regains focus."
  (when (frame-focus-state)
    (when (timerp suderman/org-klwp--focus-timer)
      (cancel-timer suderman/org-klwp--focus-timer))
    (setq suderman/org-klwp--focus-timer
          (run-at-time 2 nil #'suderman/org-klwp--refresh-if-needed))))

(defun suderman/org-klwp-start ()
  "Track local saves, external sync, and date changes on Android."
  (add-hook 'after-save-hook #'suderman/org-klwp--queue-refresh)
  (remove-function after-focus-change-function #'suderman/org-klwp--focus-check)
  (add-function :after after-focus-change-function #'suderman/org-klwp--focus-check)
  (when (timerp suderman/org-klwp--check-timer)
    (cancel-timer suderman/org-klwp--check-timer))
  (setq suderman/org-klwp--check-timer
        (run-at-time 900 900 #'suderman/org-klwp--refresh-if-needed))
  (run-at-time 10 nil #'suderman/org-klwp--refresh-if-needed))

(when (eq system-type 'android)
  (suderman/org-klwp-start))

(provide 'suderman-org-klwp)
;;; suderman-org-klwp.el ends here
