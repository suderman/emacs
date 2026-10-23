;;; suderman-org.el --- Org agenda and capture workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep daily Org work centered on a few phone-friendly files.

;;; Code:

(require 'use-package)
(require 'cl-lib)
(require 'face-remap)
(require 'org-macs)
(require 'suderman-treesit)
(eval-when-compile (require 'org-agenda))

(defvar org-done-keywords)
(defvar org-not-done-keywords)
(defvar org-archive-subtree-save-file-p)
(defvar org-archive-from-agenda)
(defvar org-tag-line-re)
(defvar org-indent-indentation-per-level)
(defvar markdown-ts-unordered-list-marker)
(defvar org-state)
(defvar org-file-tags)
(defvar org-highlight-links)
(defvar org-font-lock-extra-keywords)
(defvar font-lock-beg)
(defvar jit-lock-start)

(declare-function suderman/dired-archive "suderman-files" ())
(declare-function suderman/theme-blend "suderman-appearance" (face alpha))
(declare-function suderman/meow-off "suderman-windows" ())
(declare-function suderman/meow-insert "suderman-meow" ())
(declare-function meow--selection-type "meow-util" ())
(declare-function meow-purrsist-adopt-region "meow-purrsist" (&optional line))
(declare-function suderman/meow-delete-line "suderman-meow" ())
(declare-function suderman/meow-kill-line "suderman-meow" ())
(declare-function suderman/meow-paste "suderman-meow" ())
(declare-function suderman/meow-save "suderman-meow" ())
(declare-function suderman/meow--cancel-active-selection "suderman-meow" ())
(declare-function suderman/meow--fold-move "suderman-meow" (bounce start fold))
(defvar meow-use-clipboard)
(defvar org-mouse-map)
(declare-function suderman/enable-fold-taps "suderman-android" (line-p toggle))
(declare-function suderman/tap-repeats-p "suderman-android" (beg end))
(declare-function suderman/mouse-set-point-or-fold "suderman-android"
                  (event &optional promote-to-region))
(declare-function org-open-at-mouse "org" (ev))
(declare-function org-indent-mode "org-indent" (&optional arg))
(declare-function org-restart-font-lock "org" ())
(declare-function org-link-preview-region "ol" (&optional include-linked refresh beg end))
(declare-function org-link-preview-clear "ol" (&optional beg end))
(declare-function consult-org-agenda "consult-org" (&optional match))
(declare-function consult-org-heading "consult-org" (&optional match scope))
(declare-function org-agenda "org-agenda" (&optional arg keys restriction))
(declare-function org-agenda-redo "org-agenda" (&optional all))
(declare-function org-agenda-redo-all "org-agenda" (&optional exhaustive))
(declare-function org-remove-subtree-entries-from-agenda "org-agenda"
                  (&optional buf beg end))
(declare-function meow-keypad "meow-keypad")
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
(declare-function org-get-tags "org" (&optional epom local))
(declare-function org-set-tags "org" (tags))
(declare-function org-schedule "org" (arg &optional time))

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
  (remove-hook 'enable-theme-functions #'suderman/org-apply-log-entry-faces)
  (remove-hook 'enable-theme-functions #'suderman/org-apply-date-faces)
  (when (timerp suderman/org-date-timer)
    (cancel-timer suderman/org-date-timer))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (suderman/org-remove-fold-arrows))))
  nil)

(defun suderman/org-enable-tag-face ()
  "Keep heading tags distinct even when a completed heading gets its own face."
  (font-lock-add-keywords
   nil `((,org-tag-line-re (1 'font-lock-doc-face prepend))) t))

(add-hook 'org-mode-hook #'suderman/org-enable-tag-face)

(defface suderman/org-date '((t :inherit org-date :underline nil))
  "Active timestamp more than a week away, shown as a shaded chip."
  :group 'org-faces)

(defface suderman/org-date-soon '((t :inherit org-date :underline nil))
  "Active timestamp from today through six days ahead."
  :group 'org-faces)

(defface suderman/org-date-past '((t :inherit shadow :underline nil))
  "Active timestamp that has passed and does not repeat."
  :group 'org-faces)

(defface suderman/org-date-inactive '((t :inherit font-lock-doc-face :underline nil))
  "Inactive timestamp, a record rather than a plan."
  :group 'org-faces)

(defun suderman/org-apply-date-faces (&rest _)
  "Shade timestamp chips with their own color blended into the background."
  (pcase-dolist (`(,face ,color ,alpha)
                 '((suderman/org-date org-date 0.12)
                   (suderman/org-date-soon org-date 0.28)
                   (suderman/org-date-past shadow 0.06)
                   (suderman/org-date-inactive font-lock-doc-face 0.08)))
    (set-face-background face (or (suderman/theme-blend color alpha) 'unspecified))))

(add-hook 'org-mode-hook #'suderman/org-apply-date-faces)
(add-hook 'enable-theme-functions #'suderman/org-apply-date-faces)
(suderman/org-apply-date-faces)

(defun suderman/org-date-face ()
  "Return the chip face for the timestamp or range Org just matched."
  (save-match-data
    (let ((text (match-string 0)))
      (if (eq (aref text 0) ?\[)
          'suderman/org-date-inactive
        (let* ((last (and (string-match ".*\\([0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]\\)" text)
                          (match-string 1 text)))
               (days (and last (- (org-time-string-to-absolute last) (org-today)))))
          (cond ((null days) 'suderman/org-date)
                ;; A repeating timestamp comes around again.
                ((and (< days 0) (not (string-match-p "[.+]?\\+[0-9]+[hdwmy]" text)))
                 'suderman/org-date-past)
                ((= days 0) '((:weight bold) suderman/org-date-soon))
                ((<= 0 days 6) 'suderman/org-date-soon)
                (t 'suderman/org-date)))))))

(defun suderman/org-enable-date-faces ()
  "Show timestamps as chips: muted when inactive or past, stronger when soon."
  ;; Keep Org's matcher, after heading states but before code and comments.
  (setq org-font-lock-extra-keywords
        (cl-loop for rule in (assq-delete-all 'org-activate-dates
                                             org-font-lock-extra-keywords)
                 when (and (memq 'date org-highlight-links)
                           (eq (car-safe rule) 'org-font-lock-add-priority-faces))
                 collect '(org-activate-dates
                           (0 (or (ignore-errors (suderman/org-date-face)) 'org-date)
                              prepend))
                 collect rule)))

(add-hook 'org-font-lock-set-keywords-hook #'suderman/org-enable-date-faces)

(defun suderman/org-repeater-label (count unit)
  "Describe a repeater of COUNT UNITs, such as \"↻ weekly\"."
  (let ((name (cdr (assoc unit '(("h" . "hour") ("d" . "day") ("w" . "week")
                                 ("m" . "month") ("y" . "year"))))))
    (concat "↻ " (if (equal count "1")
                     (if (equal unit "d") "daily" (concat name "ly"))
                   (format "every %s %ss" count name)))))

(defun suderman/org-fontify-repeaters (limit)
  "Show timestamp repeaters from point to LIMIT in words."
  (remove-overlays (point) limit 'suderman/org-repeater t)
  (unless suderman/org-literal
    (while (re-search-forward
            (concat "[[<][0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9] [^]>\n]*?"
                    ;; +, ++, and .+ differ only in how Org catches up.
                    "\\([.+]?\\+\\([0-9]+\\)\\([hdwmy]\\)\\(?:/[0-9]+[hdwmy]\\)?\\)")
            limit t)
      (let ((overlay (make-overlay (match-beginning 1) (match-end 1) nil t nil)))
        (overlay-put overlay 'suderman/org-repeater t)
        (overlay-put overlay 'evaporate t)
        (overlay-put overlay 'display (suderman/org-repeater-label
                                       (match-string-no-properties 2)
                                       (match-string-no-properties 3))))))
  nil)

(defun suderman/org-fontify-date-brackets (limit)
  "Hide the angle brackets of active timestamps from point to LIMIT.
They hide like link brackets, so literal view shows them again."
  (remove-overlays (point) limit 'suderman/org-date-bracket t)
  (unless suderman/org-literal
    (while (re-search-forward org-ts-regexp limit t)
      (dolist (position (list (match-beginning 0) (1- (match-end 0))))
        (let ((overlay (make-overlay position (1+ position) nil t nil)))
          (overlay-put overlay 'suderman/org-date-bracket t)
          (overlay-put overlay 'evaporate t)
          (overlay-put overlay 'invisible 'org-link)))))
  nil)

(defun suderman/org-list-bullets ()
  "Return Markdown's unordered list glyphs by depth, so Org lists match."
  (require 'markdown-ts-mode)
  (mapcar (lambda (marker)
            (if (stringp (car marker)) (string-trim (car marker)) "•"))
          markdown-ts-unordered-list-marker))

(defun suderman/org-fontify-list-bullets (limit)
  "Show unordered list bullets from point to LIMIT as Markdown does, by depth."
  (unless suderman/org-literal
    (let ((bullets (suderman/org-list-bullets))
          struct parents)
      (while (re-search-forward "^\\(?:[ \t]*\\([-+]\\)\\|[ \t]+\\(\\*\\)\\)[ \t]+" limit t)
        (let ((bullet (or (match-beginning 1) (match-beginning 2)))
              (end (match-end 0)))
          (save-excursion
            (goto-char bullet)
            (when (org-at-item-p)
              (let ((item (line-beginning-position))
                    (depth 0))
                ;; One structure serves every item of the same list.
                (unless (assq item struct)
                  (setq struct (org-list-struct)
                        parents (org-list-parents-alist struct)))
                (while (setq item (cdr (assq item parents)))
                  (setq depth (1+ depth)))
                (compose-region bullet (1+ bullet)
                                (nth (mod depth (length bullets)) bullets)))))
          (goto-char end)))))
  nil)

(defvar suderman/org-date-timer nil
  "Timer that refreshes past and soon timestamps after midnight.")

(defun suderman/org-refresh-dates ()
  "Refontify Org buffers so timestamp chips follow the new day."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (font-lock-flush)))))

(when (timerp suderman/org-date-timer)
  (cancel-timer suderman/org-date-timer))
(setq suderman/org-date-timer
      (run-at-time "00:01" (* 24 60 60) #'suderman/org-refresh-dates))

(defface suderman/org-drawer-block
  '((t (:extend t)))
  "Source-block background for the contents of property and logbook drawers."
  :group 'org-faces)

(defface suderman/org-drawer-label
  '((t (:inherit shadow :extend nil)))
  "Muted face, without a background, for drawer labels and their :END:."
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
              ;; Only the contents get a background; the label and :END: lines
              ;; stay plain, open or folded.
              (add-face-text-property (min (1+ body-begin) end-begin) end-begin
                                      'suderman/org-drawer-block)
              (add-face-text-property begin body-begin
                                      'suderman/org-drawer-label)
              ;; A prose-font newline would make the label line taller only
              ;; while the drawer is open.
              (add-face-text-property body-begin (min (1+ body-begin) end)
                                      'suderman/fixed-pitch-text t)
              (add-face-text-property end-begin end 'suderman/org-drawer-label)
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

(defconst suderman/org-log-state-re
  (concat "^\\([ \t]*\\)- State \"\\([^\"\n]+\\)\"[ \t]+from"
          "\\(?:[ \t]+\"\\([^\"\n]*\\)\"\\)?[ \t]+\\[\\([^]\n]+\\)\\]"
          "\\(?:[ \t]*\\\\\\\\\\)?[ \t]*$")
  "A LOGBOOK state change: indentation, new state, old state, timestamp.")

(defface suderman/org-log-odd '((t :extend t))
  "Background for the first and every other LOGBOOK entry."
  :group 'org-faces)

(defface suderman/org-drawer-entry '((t :height 0.9))
  "Text size of PROPERTIES and LOGBOOK entries, relative to their usual size."
  :group 'org-faces)

(defface suderman/org-log-even '((t :extend t))
  "Background for the second and every other LOGBOOK entry."
  :group 'org-faces)

(defun suderman/org-apply-log-entry-faces (&rest _)
  "Shade LOGBOOK entries 5% and 10% from the drawer toward the foreground.
Both differ from the drawer's own label and :END: lines."
  (let ((background (face-background 'suderman/org-drawer-block nil t))
        (foreground (face-foreground 'default nil t)))
    (when-let* (((and (stringp background) (stringp foreground)))
                (background-rgb (color-name-to-rgb background))
                (foreground-rgb (color-name-to-rgb foreground)))
      (pcase-dolist (`(,face . ,alpha) '((suderman/org-log-odd . 0.05)
                                         (suderman/org-log-even . 0.10)))
        (set-face-background face (apply #'color-rgb-to-hex
                                         (append (color-blend foreground-rgb
                                                              background-rgb alpha)
                                                 '(2))))))))

(add-hook 'org-mode-hook #'suderman/org-apply-log-entry-faces)
(add-hook 'enable-theme-functions #'suderman/org-apply-log-entry-faces)
(suderman/org-apply-log-entry-faces)

(defun suderman/org-log-overlay (begin end &rest properties)
  "Add a LOGBOOK display overlay from BEGIN to END with PROPERTIES."
  (let ((overlay (make-overlay begin end nil t nil)))
    (overlay-put overlay 'suderman/org-log t)
    (overlay-put overlay 'evaporate t)
    (while properties
      (overlay-put overlay (pop properties) (pop properties)))))

(defun suderman/org-log-state-display (to from stamp quiet background)
  "Return the compact LOGBOOK line for TO from FROM at STAMP.
QUIET mutes the whole line.  BACKGROUND is the entry's background face,
which overlay faces would not otherwise give a display string."
  (let ((state (lambda (keyword)
                 (propertize keyword 'face
                             ;; State faces carry their own heading background.
                             ;; The relative size must precede the absolute one.
                             (list background 'suderman/org-drawer-entry
                                   (if quiet 'shadow (or (org-get-todo-face keyword) 'org-todo))
                                   'suderman/fixed-pitch-text))))
        (muted (lambda (text)
                 (propertize text 'face (list background 'suderman/org-drawer-entry
                                              'shadow 'suderman/fixed-pitch-text)))))
    (concat (if (string-empty-p from) "" (concat (funcall state from) (funcall muted " → ")))
            (funcall state to) (funcall muted (concat "  " stamp)))))

(defun suderman/org-decorate-log-entry (end prefix background)
  "Decorate the LOGBOOK entry whose state line was just matched, up to END.
PREFIX is the org-indent width in columns.  BACKGROUND shades the entry."
  (let* ((line (match-beginning 0))
         (to (match-string 2))
         (from (or (match-string 3) ""))
         (stamp (match-string 4))
         (bullet (match-end 1))
         (state-end (match-end 0))
         (notes (progn (forward-line 1) (point))))
    (while (and (< (point) end)
                (not (looking-at-p "^[ \t]*\\(?:- \\|CLOCK:\\|:END:\\)")))
      (forward-line 1))
    (let* ((notes-end (point))
           (text (replace-regexp-in-string
                  org-link-bracket-re ""
                  (buffer-substring-no-properties notes notes-end)))
           (quiet (string-match-p "\\`[ \t\n]*no changes?\\.?[ \t\n]*\\'"
                                  (downcase text))))
      ;; Above the per-line overlays, so its relative size scales their text.
      (suderman/org-log-overlay line notes-end
                                'face (list background 'suderman/org-drawer-entry)
                                'priority 1)
      (suderman/org-log-overlay
       bullet state-end
       'display (suderman/org-log-state-display to from stamp quiet background))
      (goto-char notes)
      (while (< (point) notes-end)
        ;; Monospace up to the note text, so its column is predictable.
        (let ((lead (point))
              (column (+ prefix (skip-chars-forward " \t"))))
          (when (looking-at org-link-bracket-re)
            ;; Link markup is hidden, so only its label takes columns.
            (setq column (+ column (length (or (match-string 2) (match-string 1)))))
            (goto-char (match-end 0))
            (setq column (+ column (skip-chars-forward " \t"))))
          (suderman/org-log-overlay lead (point) 'face 'suderman/fixed-pitch-text)
          ;; Keep org-indent's margin, then the entry's background to the text.
          ;; Monospace spaces, since a prefix string ignores :align-to.
          (suderman/org-log-overlay
           lead (line-end-position)
           'wrap-prefix (concat (propertize (make-string prefix ?\s)
                                            'face '(org-indent suderman/fixed-pitch-text))
                                (propertize (make-string (- column prefix) ?\s)
                                            'face (list background 'suderman/org-drawer-entry
                                                        'suderman/fixed-pitch-text)))
           'face (and quiet 'shadow)))
        (forward-line 1))
      (goto-char notes-end))))

(defun suderman/org-decorate-logbook (begin end)
  "Show state changes in the LOGBOOK body from BEGIN to END compactly.
Notes of \"No change.\" runs are muted, entries alternate two shades, and
wrapped notes hang under their text.  Literal view shows the raw text."
  (remove-overlays begin end 'suderman/org-log t)
  (unless suderman/org-literal
    (save-excursion
      (goto-char begin)
      (let ((prefix (if (bound-and-true-p org-indent-mode)
                        (* (or (org-current-level) 0) org-indent-indentation-per-level)
                      0))
            (odd t))
        (while (re-search-forward suderman/org-log-state-re end t)
          (suderman/org-decorate-log-entry
           end prefix (if odd 'suderman/org-log-odd 'suderman/org-log-even))
          (setq odd (not odd)))))))

(defun suderman/org-stripe-properties (begin end)
  "Shade property lines from BEGIN to END like LOGBOOK entries."
  (remove-overlays begin end 'suderman/org-log t)
  (unless suderman/org-literal
    (save-excursion
      (goto-char begin)
      (let ((odd t))
        (while (< (point) end)
          (suderman/org-log-overlay
           (point) (min (line-beginning-position 2) end)
           'face (list (if odd 'suderman/org-log-odd 'suderman/org-log-even)
                       'suderman/org-drawer-entry))
          (setq odd (not odd))
          (forward-line 1))))))

(defun suderman/org-fontify-drawer-entries (limit)
  "Decorate each LOGBOOK and PROPERTIES drawer from point to LIMIT."
  (let ((case-fold-search t))
    (while (re-search-forward "^[ \t]*:\\(LOGBOOK\\|PROPERTIES\\):[ \t]*$" limit t)
      (let* ((begin (match-beginning 0))
             (element (save-excursion (goto-char begin) (org-element-at-point)))
             (type (org-element-type element))
             (contents-begin (org-element-property :contents-begin element)))
        (when (and (memq type '(drawer property-drawer))
                   (= begin (org-element-property :post-affiliated element))
                   ;; An empty drawer has no contents to decorate.
                   contents-begin)
          (funcall (if (eq type 'drawer)
                       #'suderman/org-decorate-logbook
                     #'suderman/org-stripe-properties)
                   contents-begin (org-element-property :contents-end element)))
        (goto-char (max (point) (org-element-property :end element))))))
  nil)

(defconst suderman/org-block-font-lock-keywords
  '((suderman/org-fontify-source-block-openers)
    (suderman/org-fontify-drawer-blocks)
    (suderman/org-fontify-drawer-entries)
    (suderman/org-fontify-repeaters)
    (suderman/org-fontify-date-brackets)
    (suderman/org-fontify-list-bullets)))

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
(defvar-local suderman/org-literal nil
  "Non-nil when `suderman/org-toggle-formatting' shows raw Org syntax.")

(defun suderman/org-enable-mixed-pitch ()
  "Use proportional prose with fixed-width structural text in GUI Org buffers."
  (when (and (display-graphic-p)
             (not suderman/org-literal)
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

(defun suderman/org-toggle-formatting ()
  "Switch this Org buffer between formatted and literal views.
Literal shows link targets, emphasis markers, entities, stars, and images
as raw text, flush left and in monospace."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not an Org buffer"))
  (setq suderman/org-literal (not suderman/org-literal))
  (let ((formatted (not suderman/org-literal)))
    (setq-local org-link-descriptive formatted
                org-hide-emphasis-markers formatted
                org-pretty-entities formatted)
    (unless formatted
      (decompose-region (point-min) (point-max)))
    (org-indent-mode (if formatted 1 -1))
    (when (fboundp 'org-superstar-mode)
      (org-superstar-mode (if formatted 1 -1)))
    (if formatted
        (suderman/org-enable-mixed-pitch)
      (variable-pitch-mode -1))
    (org-restart-font-lock)
    (if formatted
        (org-link-preview-region)
      (org-link-preview-clear))
    (message "Org %s" (if formatted "formatted" "literal"))))

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

(defun suderman/org-open-below-heading ()
  "Open a line directly below the heading at point, showing its entry.
Planning lines or drawers can be added there by hand."
  (org-fold-show-entry)
  (end-of-line)
  (insert "\n"))

(defun suderman/org-return ()
  "Continue a heading or list item, or use Org Return, then enter Insert.
Anywhere on a folded heading, or at the end of an open one, show the
subtree and open a line directly below its planning lines and drawers.
Only an open heading splits at point.  With a prefix argument, open a
line directly below the heading instead.  Return on an empty item
removes it and ends the list.  Elsewhere a prefix argument keeps Org's
normal newline behavior."
  (interactive)
  (suderman/org-goto-adjacent-heading)
  (cond
   ((and (org-at-heading-p)
         (or (eolp) (org-fold-folded-p (line-end-position) 'outline)))
    (cond
     (current-prefix-arg (suderman/org-open-below-heading))
     ;; Org's skip also passes blank lines; open directly below the metadata.
     (t (suderman/org-show-children)
        (org-end-of-meta-data t)
        (skip-chars-backward " \t\n")
        (end-of-line)
        (insert "\n"))))
   ((and (not current-prefix-arg) (eolp) (org-at-item-p)
         (org-match-line org-list-full-item-re))
    (if (= (point) (match-end 0))
        (progn
          (delete-region (line-beginning-position) (point))
          ;; Electric indentation would put point back inside the list.
          (insert "\n")
          (org-update-checkbox-count-maybe))
      (org-insert-item (match-beginning 3))))
   (t (call-interactively #'org-return)))
  (when (bound-and-true-p meow-normal-mode)
    (suderman/meow-insert)))

(defun suderman/org-meta-return ()
  "Insert a heading or list item using Org, then enter Insert from Normal.
On a heading with content, add the sibling after its subtree.  Org
would give the new heading the body instead."
  (interactive)
  (if (and (not current-prefix-arg) (suderman/org-heading-has-content-p))
      (org-insert-heading-respect-content)
    (call-interactively #'org-meta-return))
  (when (bound-and-true-p meow-normal-mode)
    (suderman/meow-insert)))

(defun suderman/org-insert-heading-after-subtree ()
  "Insert a heading after the subtree, then enter Insert from Normal.
On a heading, open a line directly below it instead."
  (interactive)
  (if (org-at-heading-p)
      (suderman/org-open-below-heading)
    (call-interactively #'org-insert-heading-respect-content))
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
           '("inbox.org" "todo.org" "asana.org"))
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
              '("todo.org"))
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

(defun suderman/org-agenda-setup ()
  "Keep Meow off locally while retaining direct keypad access."
  (suderman/meow-off))

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

(defun suderman/org-collapse-all ()
  "Collapse all headings, keeping a lone top-level heading open as a title."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "This command requires an Org buffer"))
  (org-overview)
  (let ((top (org-map-entries #'point "LEVEL=1")))
    (when (length= top 1)
      (save-excursion
        (goto-char (car top))
        (org-fold-show-entry)
        (org-fold-show-children)))))

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

(defvar suderman/org-dispatch-hosts '(("kit" . ?k) ("cog" . ?c) ("lux" . ?l))
  "Host tags org-dispatch recognizes, with their fast-selection keys.
Keep the names in step with the dispatcher's `org-dispatch-hosts'.")

(defun suderman/org-auto-setup ()
  "Offer a dispatch host and a schedule when a heading enters AUTO.
Hosts resolve as org-dispatch does: local tags, then #+FILETAGS, never
parent headings.  Only user commands prompt; Lisp, timers, emacsclient
and batch state changes pass through untouched."
  (when (and (equal org-state "AUTO") this-command (not noninteractive))
    (condition-case nil
        (let* ((hosts (mapcar #'car suderman/org-dispatch-hosts))
               (local (org-get-tags nil t))
               (found (or (seq-intersection local hosts)
                          (seq-intersection org-file-tags hosts))))
          (unless (= (length found) 1)
            (let* ((prompt (concat "AUTO host: "
                                   (mapconcat (lambda (h)
                                                (format "[%c]%s" (cdr h) (substring (car h) 1)))
                                              suderman/org-dispatch-hosts " ")
                                   " [RET] skip: "))
                   (key (read-char-choice
                         prompt (cons ?\r (mapcar #'cdr suderman/org-dispatch-hosts))))
                   (host (car (rassq key suderman/org-dispatch-hosts))))
              (when host
                (org-set-tags (append (seq-difference local hosts) (list host))))))
          (unless (org-entry-get nil "SCHEDULED")
            (when (eq (read-char-choice
                       "AUTO schedule: [RET] next dispatch, [s] schedule: " '(?\r ?s))
                      ?s)
              (org-schedule nil))))
      ;; Let org-todo finish, so an Agenda line still refreshes.
      (quit (message "AUTO setup quit")))))

(add-hook 'org-after-todo-state-change-hook #'suderman/org-auto-setup)

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
  "Toggle a checkbox in an Org buffer, adding one where it is missing.
A list item without a box gains one, and any other line becomes a
checkbox item; on a blank line, enter Insert from Normal.  A prefix
argument, active region, or heading uses Org's toggle unchanged."
  (interactive)
  (if (or current-prefix-arg (use-region-p)
          (not (derived-mode-p 'org-mode)) (org-at-heading-p))
      (suderman/org--call-contextually #'org-toggle-checkbox)
    ;; A blank line inside a list still belongs to the item above it.
    (let ((item (and (not (org-match-line "[ \t]*$")) (org-in-item-p))))
      (if item
          (save-excursion
            (goto-char item)
            (org-toggle-checkbox (unless (org-at-item-checkbox-p) '(4))))
        (back-to-indentation)
        (insert "- [ ] ")
        (org-update-checkbox-count-maybe)
        (when (and (eolp) (bound-and-true-p meow-normal-mode))
          (suderman/meow-insert))))))

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
                        ;; The final newline stays visible; test the one before.
                        (org-fold-folded-p
                         (max (point-min) (- (point) (if (eobp) 2 1)))
                         'outline)))))
    ;; At EOF the visible newline can belong to a hidden, nonblank body line.
    ;; Skip hidden child headings to find the visible parent.
    (org-back-to-heading)))

(defun suderman/org-fold-keep-final-newline (args)
  "Leave the buffer's final newline outside a fold described by ARGS.
Otherwise a folded last subtree hides the empty line below it."
  (pcase-let ((`(,from ,to ,flag . ,rest) args))
    (if (and flag
             (> to (1+ from))
             (= to (save-restriction (widen) (point-max)))
             (eq (char-before to) ?\n))
        `(,from ,(1- to) ,flag . ,rest)
      args)))

(defun suderman/org-keep-planning-folded (add &rest args)
  "Call ADD with ARGS, keeping new planning text hidden under a folded heading.
Org inserts CLOSED, SCHEDULED, and DEADLINE where the heading's fold
starts, so the line would show.  An empty heading counts as folded."
  (let ((folded (save-excursion
                  (org-back-to-heading t)
                  (or (org-fold-folded-p (line-end-position) 'outline)
                      (not (suderman/org-heading-has-content-p))))))
    (prog1 (apply add args)
      (when folded
        (save-excursion
          (org-back-to-heading t)
          (org-fold-hide-entry))))))

(defvar-local suderman/org--final-line-edit nil
  "Start of this command's edits on the line below a folded last subtree.")

(defun suderman/org--below-folded-end-p (pos)
  "Return non-nil when POS is on the line below a folded last subtree.
`suderman/org-fold-keep-final-newline' leaves that line visible, but it
belongs to the subtree, so typing there would hide its context."
  (save-restriction
    (widen)
    (let ((bol (save-excursion (goto-char (point-max)) (pos-bol))))
      (and (>= pos (1- bol))
           (> bol (1+ (point-min)))
           (org-fold-folded-p (- bol 2) 'outline)))))

(defun suderman/org--show-subtree-at (pos)
  "Show the visible subtree whose hidden body contains POS."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char pos)
      (org-back-to-heading t)
      (while (and (org-invisible-p) (org-up-heading-safe)))
      (org-fold-show-subtree))))

(defun suderman/org-reveal-final-line-insert ()
  "Show a folded last subtree when Insert starts on the line below it."
  (when (and (suderman/org--below-folded-end-p (point))
             (not (org-at-heading-p)))
    (suderman/org--show-subtree-at (1- (pos-bol)))))

(defun suderman/org-reveal-final-line-edit (beg _end)
  "Note an interactive edit at BEG on the line below a folded last subtree."
  (when (and this-command (suderman/org--below-folded-end-p beg))
    (setq suderman/org--final-line-edit
          (min beg (or suderman/org--final-line-edit beg)))))

(defun suderman/org-reveal-after-final-line-edit ()
  "Show a folded last subtree after a command edited body text below it.
Org builds a new heading in several changes, so decide once the command
ends.  An edit that starts a heading leaves the subtree folded."
  (when-let* ((beg suderman/org--final-line-edit))
    (setq suderman/org--final-line-edit nil)
    (unless (save-excursion
              (goto-char (min beg (point-max)))
              (skip-chars-forward "\n")
              (and (bolp) (org-at-heading-p)))
      (suderman/org--show-subtree-at (max (point-min) (1- beg))))))

(defun suderman/org-enable-final-line-reveal ()
  "Show a folded last subtree before body edits on the line below it."
  (add-hook 'before-change-functions #'suderman/org-reveal-final-line-edit nil t)
  (add-hook 'post-command-hook #'suderman/org-reveal-after-final-line-edit nil t)
  (add-hook 'meow-insert-enter-hook #'suderman/org-reveal-final-line-insert nil t))

(add-hook 'org-mode-hook #'suderman/org-enable-final-line-reveal)

(defun suderman/org-mouse-toggle-fold (event)
  "Toggle the heading or drawer whose trailing arrow received EVENT."
  (interactive "e")
  (mouse-set-point event)
  (suderman/org-toggle-fold))

(defun suderman/org--drawer-start-p ()
  "Return non-nil when point is on the opening line of a drawer."
  (let ((element (org-element-at-point)))
    (and (memq (org-element-type element) '(drawer property-drawer))
         (= (line-beginning-position)
            (org-element-property :post-affiliated element)))))

(defun suderman/org--block-delimiter-p ()
  "Return non-nil when point is on a #+begin_ or #+end_ line."
  (org-match-line "[ \t]*#\\+\\(?:begin\\|end\\)_"))

(defun suderman/org--foldable-line-p ()
  "Return non-nil on a heading, a drawer's first line, or a block delimiter."
  (or (org-at-heading-p)
      (suderman/org--drawer-start-p)
      (suderman/org--block-delimiter-p)))

(defun suderman/org-enable-fold-taps ()
  "Let a second Android tap on a foldable line toggle it."
  (suderman/enable-fold-taps #'suderman/org--foldable-line-p
                             #'suderman/org-toggle-fold))

(defun suderman/org-mouse-open (event)
  "Open the link or timestamp clicked in EVENT.
On Android the first tap only moves point onto it; a second tap opens it."
  (interactive "e")
  (let ((pos (posn-point (event-start event))))
    (if (or (not (featurep 'android))
            (and (get-char-property pos 'mouse-face)
                 (suderman/tap-repeats-p
                  (previous-single-char-property-change (1+ pos) 'mouse-face)
                  (next-single-char-property-change pos 'mouse-face))))
        (org-open-at-mouse event)
      (mouse-set-point event))))

(defun suderman/org-fold-arrow-press ()
  "Ignore a press on a fold arrow; the click toggles it."
  (interactive))

;; A touch that starts on an arrow still scrolls instead of dragging a region.
(put 'suderman/org-fold-arrow-press 'ignored-mouse-command t)

(defvar suderman/org-fold-arrow-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'suderman/org-fold-arrow-press)
    (define-key map [mouse-1] #'suderman/org-mouse-toggle-fold)
    (define-key map [mouse-2] #'suderman/org-mouse-toggle-fold)
    map)
  "Mouse bindings on trailing heading and drawer arrows.")

(defun suderman/org-heading-has-content-p ()
  "Return non-nil when the heading at point has body text or child headings."
  (and (org-at-heading-p)
       (< (line-end-position) (save-excursion (org-end-of-subtree t)))))

(defun suderman/org-fontify-fold-arrows (beg end)
  "Refresh heading and drawer arrow displays between BEG and END."
  (save-excursion
    (goto-char end)
    (setq end (min (point-max) (1+ (line-end-position))))
    (goto-char beg)
    (setq beg (line-beginning-position))
    (goto-char beg)
    (remove-overlays beg end 'suderman/org-fold-arrow t)
    (while (re-search-forward (concat org-outline-regexp-bol "\\|" org-drawer-regexp)
                             end t)
      (let* ((eol (line-end-position))
             (pos (1- eol))
             (kind (cond ((suderman/org-heading-has-content-p) 'outline)
                         ((suderman/org--drawer-start-p) 'drawer))))
        (when kind
          ;; Put the display on visible label text, not the folded newline or
          ;; hidden link brackets.  After-strings at the newline disappear folded.
          (while (and (> pos (line-beginning-position))
                      (invisible-p (get-text-property pos 'invisible)))
            (setq pos (1- pos)))
          ;; Inherit the face; copying it applies relative heading height twice.
          (let* ((char (buffer-substring-no-properties pos (1+ pos)))
                 (overlay (make-overlay pos (1+ pos)))
                 (folded `(with-current-buffer object
                            (save-excursion
                              (goto-char buffer-position)
                              (org-fold-folded-p (line-end-position) ',kind)))))
            (overlay-put overlay 'suderman/org-fold-arrow t)
            (overlay-put overlay 'evaporate t)
            (overlay-put
             overlay 'display
             (mapcar
              (lambda (state)
                `(when ,(if (car state) folded `(not ,folded))
                   . ,(concat char
                              (propertize (cdr state)
                                          ;; Default height, so tags and heading
                                          ;; scale do not resize the arrow.
                                          'face '(org-ellipsis
                                                  suderman/fixed-pitch-text)
                                          'mouse-face 'highlight
                                          'pointer 'hand
                                          'help-echo (if (eq kind 'drawer)
                                                         "Toggle drawer"
                                                       "Toggle subtree")
                                          'keymap suderman/org-fold-arrow-map))))
              '((t . " ▸") (nil . " ▾"))))))
        (goto-char eol)))))

(defun suderman/org-extend-fold-arrow-region (beg _end _old-len)
  "Refontify the preceding heading or drawer when its contents change at BEG."
  ;; Runs inside `replace-match', which still needs the caller's match data.
  (save-match-data
    (save-excursion
      (goto-char beg)
      (beginning-of-line)
      (while (and (re-search-backward
                   (concat org-outline-regexp-bol "\\|" org-drawer-regexp) nil t)
                  (equal (upcase (or (match-string 1) "")) "END")))
      (setq jit-lock-start (min jit-lock-start (point))))))

(defun suderman/org-remove-fold-arrows ()
  "Remove heading and drawer displays when leaving Org mode."
  (remove-hook 'jit-lock-after-change-extend-region-functions
               #'suderman/org-extend-fold-arrow-region t)
  (jit-lock-unregister #'suderman/org-fontify-fold-arrows)
  (save-restriction
    (widen)
    (remove-overlays (point-min) (point-max) 'suderman/org-fold-arrow t)))

(defun suderman/org-enable-fold-arrows ()
  "Show clickable heading and drawer arrows independently of hidden text."
  (dolist (kind '(outline drawer))
    (org-fold-core-set-folding-spec-property
     (org-fold-core-get-folding-spec-from-alias kind) :ellipsis nil))
  (jit-lock-register #'suderman/org-fontify-fold-arrows)
  (add-hook 'jit-lock-after-change-extend-region-functions
            #'suderman/org-extend-fold-arrow-region nil t)
  (jit-lock-refontify)
  (add-hook 'change-major-mode-hook #'suderman/org-remove-fold-arrows nil t))

(add-hook 'org-mode-hook #'suderman/org-enable-fold-arrows)

(defun suderman/org-show-children ()
  "Show the heading's body and its direct child headings, like Org's
children cycling state.  Deeper levels stay folded."
  (org-fold-show-entry)
  (org-fold-show-children))

(defun suderman/org-toggle-fold (&optional bounce)
  "Toggle a heading, drawer, or block, then move to the line end.
A folded heading opens to its body and direct children.  Empty headings
and lines that cannot fold only move to the line end.  With BOUNCE, as
from a key, a fold that closes moves to the line start instead, and on a
line that cannot fold a press at the end moves to the start."
  (interactive (list t))
  (let ((start (point)))
    (suderman/org-goto-adjacent-heading)
    (let* ((moved (/= start (point)))
           (foldable
            (cond
             ((org-fold-hide-drawer-toggle nil t))
             ((org-at-heading-p)
              (when (suderman/org-heading-has-content-p)
                (if (org-fold-folded-p (line-end-position) 'outline)
                    (suderman/org-show-children)
                  (org-fold-hide-subtree))
                t))
             ;; Only the delimiter lines toggle; a line inside the block just moves.
             ((suderman/org--block-delimiter-p)
              (org-fold-hide-block-toggle nil t)
              t))))
      (suderman/meow--fold-move
       bounce (if moved -1 start)
       (and foldable
            (if (org-fold-folded-p (line-end-position)) 'folded 'open))))))

(defun suderman/org--folded-subtree-bounds ()
  "Return the bounds of a folded subtree, or nil.
Point must be on its heading with no selection, or the selection must
cover exactly the heading line.  Acting on only a folded heading line
would leave its hidden body under the previous heading."
  (when-let* ((line (if (use-region-p)
                        (let ((end (region-end)))
                          (save-excursion
                            (goto-char (region-beginning))
                            (and (bolp)
                                 (<= (line-end-position) end
                                     (1+ (line-end-position)))
                                 (point))))
                      (line-beginning-position))))
    (save-excursion
      (goto-char line)
      (when (and (org-at-heading-p)
                 (org-fold-folded-p (line-end-position) 'outline))
        (cons (point) (org-end-of-subtree t t))))))

(defun suderman/org-delete-line ()
  "Delete the current line, or the whole subtree of a folded heading."
  (interactive)
  (if-let* ((bounds (suderman/org--folded-subtree-bounds)))
      (progn
        (suderman/meow--cancel-active-selection)
        (delete-region (car bounds) (cdr bounds)))
    (call-interactively #'suderman/meow-delete-line)))

(defun suderman/org-kill-line ()
  "Cut the current line, or the whole subtree of a folded heading.
Stay in Normal, like `suderman/meow-kill-line'."
  (interactive)
  (if-let* ((bounds (suderman/org--folded-subtree-bounds)))
      (progn
        (suderman/meow--cancel-active-selection)
        (let ((select-enable-clipboard meow-use-clipboard))
          (kill-region (car bounds) (cdr bounds))))
    (call-interactively #'suderman/meow-kill-line)))

(defun suderman/org-save ()
  "Copy the selection, or a folded heading's whole subtree.
The subtree is copied when the selection covers exactly that heading line."
  (interactive)
  (if-let* ((bounds (and (use-region-p) (suderman/org--folded-subtree-bounds))))
      (let ((select-enable-clipboard meow-use-clipboard))
        (kill-ring-save (car bounds) (cdr bounds))
        (suderman/meow--cancel-active-selection))
    (call-interactively #'suderman/meow-save)))

(defun suderman/org-paste ()
  "Paste the current kill, after the whole subtree of a folded heading.
Linewise text would otherwise land inside the heading's hidden body.
On the empty line below a folded last subtree, paste onto that line
rather than below it.  Fold pasted subtrees, as `org-yank' does."
  (interactive)
  (let* ((text (and kill-ring (current-kill 0 t)))
         (linewise (and text (not (use-region-p)) (string-suffix-p "\n" text)))
         (bounds (and linewise (suderman/org--folded-subtree-bounds)))
         (start (cond (bounds (cdr bounds))
                      ((and linewise
                            (suderman/org--below-folded-end-p (point))
                            (org-match-line "[ \t]*$"))
                       (pos-bol)))))
    (if (not start)
        (call-interactively #'suderman/meow-paste)
      (goto-char start)
      (unless (bolp) (insert "\n"))
      (setq start (point))
      (insert-for-yank text)
      (when (and org-yank-folded-subtrees (org-kill-is-subtree-p text))
        (let ((end (point)))
          (goto-char start)
          (while (< (point) end)
            (org-fold-hide-subtree)
            (org-end-of-subtree t t))))
      (goto-char start))))

(defun suderman/org--keep-selection (command)
  "Call COMMAND, then restore an active selection so it can be repeated.
Org's structure commands deactivate the region."
  (if (not (use-region-p))
      (call-interactively command)
    (let ((anchor (copy-marker (mark)))
          (active (copy-marker (point)))
          (line (equal (meow--selection-type) '(expand . line))))
      (unwind-protect
          (progn
            (call-interactively command)
            (set-mark anchor)
            (goto-char active)
            (activate-mark)
            (meow-purrsist-adopt-region line)
            (setq deactivate-mark nil
                  disable-point-adjustment t))
        (set-marker anchor nil)
        (set-marker active nil)))))

(defun suderman/org-promote ()
  "Promote with Org, keeping the selection for repeated use."
  (interactive)
  (let ((org-metaleft-final-hook
         (list (lambda () (suderman/meow--shift-lines -2) t))))
    (suderman/org--keep-selection #'org-metaleft)))

(defun suderman/org-demote ()
  "Demote with Org, then open a folded new parent to its children.
Otherwise the demoted headings show under a parent that looks folded
and hides its own body.  Keep the selection for repeated use."
  (interactive)
  (let ((start (copy-marker (if (use-region-p) (region-beginning) (point)))))
    ;; Shift plain lines, where Org would only move by a word.
    (let ((org-metaright-final-hook
           (list (lambda () (suderman/meow--shift-lines 2) t))))
      (suderman/org--keep-selection #'org-metaright))
    (save-excursion
      (goto-char start)
      (when (and (org-at-heading-p)
                 (org-up-heading-safe)
                 (org-fold-folded-p (pos-eol) 'outline))
        (suderman/org-show-children)))
    (set-marker start nil)))

(defun suderman/org-move-selected-subtrees (down)
  "Move the subtrees the selection covers past a sibling, DOWN or up.
Org's region move reopens folds, so swap the sibling's text instead,
refold it, and keep the selection for repeated moves."
  (let* ((beg (save-excursion (goto-char (region-beginning)) (pos-bol)))
         (end (save-excursion
                (goto-char (max beg (1- (region-end))))
                (org-back-to-heading t)
                (org-end-of-subtree t t)
                (point)))
         (level (save-excursion (goto-char beg) (org-current-level)))
         (other-beg (save-excursion
                      (if down
                          (progn (goto-char end)
                                 (and (org-at-heading-p) (point)))
                        (goto-char beg)
                        (and (org-get-previous-sibling) (point)))))
         (other-end (and other-beg
                         (save-excursion
                           (goto-char other-beg)
                           (org-end-of-subtree t t)
                           (point)))))
    (unless (and other-beg
                 (= level (save-excursion (goto-char other-beg) (org-current-level))))
      (user-error "Cannot move past superior level or buffer limit"))
    (let* ((folded (save-excursion
                     (goto-char other-beg)
                     (org-fold-folded-p (pos-eol) 'outline)))
           (text (buffer-substring other-beg other-end))
           (text (if (string-suffix-p "\n" text) text (concat text "\n")))
           (shift (if down (length text) (- (length text))))
           (new-mark (+ (mark) shift))
           (new-point (+ (point) shift)))
      (delete-region other-beg other-end)
      (goto-char (if down beg (+ end shift)))
      (unless (bolp) (insert "\n"))
      (let ((start (point)))
        (insert text)
        (org-fold-core--process-delayed)
        (when folded
          (goto-char start)
          (org-fold-subtree t)))
      (set-mark new-mark)
      (goto-char new-point)
      (setq deactivate-mark nil
            disable-point-adjustment t))))

(defun suderman/org-move (command)
  "Move the Org element at point with COMMAND, keeping a folded heading folded.
Point just past a folded heading's line moves to that heading first.
Org's delayed fold repair reopens some moved subtrees, such as the last
one in the buffer, so run it now and fold again.  A selection starting
on a heading moves its subtrees together."
  (if (and (use-region-p)
           (save-excursion (goto-char (region-beginning)) (beginning-of-line)
                           (org-at-heading-p)))
      (suderman/org-move-selected-subtrees (eq command #'org-metadown))
    (suderman/org-move-heading command)))

(defun suderman/org-move-heading (command)
  "Move the Org element at point with COMMAND; see `suderman/org-move'."
  (suderman/org-goto-adjacent-heading)
  (if (not (and (org-at-heading-p)
                (org-fold-folded-p (line-end-position) 'outline)))
      (call-interactively command)
    ;; Org restores the column with `move-to-column', which can pass the
    ;; line end into the hidden body.
    (let ((offset (- (point) (line-beginning-position))))
      (beginning-of-line)
      (call-interactively command)
      (org-fold-core--process-delayed)
      (org-fold-subtree t)
      (goto-char (min (+ (line-beginning-position) offset)
                      (line-end-position))))))

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

(defun suderman/org-herdr-follow-android (path)
  "Open a Termux session attached to the Herdr pane for herdr: link PATH.
The link's host is an ssh host in Termux, and Termux must set
allow-external-apps = true in ~/.termux/termux.properties.  Termux's
ssh-unlock adds the ssh key with a fingerprint before ssh runs."
  (let ((host (car (split-string path "/"))))
    (with-temp-buffer
      (unless (zerop (call-process
                      "am" nil t nil "startservice"
                      "-n" "com.termux/com.termux.app.RunCommandService"
                      "-a" "com.termux.RUN_COMMAND"
                      "--es" "com.termux.RUN_COMMAND_PATH"
                      "/data/data/com.termux/files/home/bin/ssh-unlock"
                      "--esa" "com.termux.RUN_COMMAND_ARGUMENTS"
                      (string-join
                       (list "ssh" "-t" host "herdr-link" "attach" path) ",")
                      "--ez" "com.termux.RUN_COMMAND_BACKGROUND" "false"
                      ;; 0 switches to the new session and shows Termux.
                      "--es" "com.termux.RUN_COMMAND_SESSION_ACTION" "0"))
        (message "%s" (string-trim (buffer-string)))))))

(defun suderman/org-herdr-follow (path _arg)
  "Jump to the Herdr pane for the agent session in herdr: link PATH."
  (if (featurep 'android)
      (suderman/org-herdr-follow-android path)
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
                     (kill-buffer buffer)))))))

(use-package org
  :ensure nil
  :init
  (setq auto-save-visited-interval (if (featurep 'android) 10 3)
        auto-save-visited-predicate #'suderman/org-auto-save-visited-p
        org-M-RET-may-split-line '((default . nil))
        org-insert-heading-respect-content nil
        org-blank-before-new-entry '((heading . nil) (plain-list-item . auto))
        ;; Keep a folded subtree's trailing blank lines folded with it.
        org-cycle-separator-lines 0
        org-log-done 'time
        org-log-into-drawer t
        org-fontify-whole-block-delimiter-line nil
        org-startup-indented t
        org-startup-folded 'fold
        org-ellipsis " ▾"
        org-hide-emphasis-markers t
        org-pretty-entities t
        ;; Only a_{b} and a^{b} raise or lower text, not snake_case names.
        org-use-sub-superscripts '{}
        org-hide-drawer-startup t
        org-startup-with-link-previews t
        org-tags-column 0
        org-auto-align-tags nil
        ;; Host tags exclude each other; one key toggles one and closes.
        org-tag-persistent-alist
        `((:startgroup) ,@suderman/org-dispatch-hosts (:endgroup))
        org-fast-tag-selection-single-key t
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
  (org-link-set-parameters "herdr" :follow #'suderman/org-herdr-follow
                           :face '(org-link suderman/fixed-pitch-text))
  (keymap-set org-mode-map "RET" #'suderman/org-return)
  (keymap-set org-mode-map "<remap> <org-meta-return>" #'suderman/org-meta-return)
  (keymap-set org-mode-map "<remap> <org-insert-heading-respect-content>"
              #'suderman/org-insert-heading-after-subtree)
  ;; `keymap-set' rejects the slash in these command names.
  (define-key org-mode-map [remap suderman/meow-toggle-fold]
              #'suderman/org-toggle-fold)
  (define-key org-mode-map [remap suderman/meow-delete-line]
              #'suderman/org-delete-line)
  (define-key org-mode-map [remap suderman/meow-kill-line]
              #'suderman/org-kill-line)
  (define-key org-mode-map [remap suderman/meow-save] #'suderman/org-save)
  (define-key org-mode-map [remap suderman/meow-paste] #'suderman/org-paste)
  (define-key org-mode-map [remap suderman/meow-indent] #'suderman/org-demote)
  (define-key org-mode-map [remap suderman/meow-outdent] #'suderman/org-promote)
  (keymap-set org-mode-map "<mouse-1>" #'suderman/mouse-set-point-or-fold)
  ;; Android taps on links arrive as mouse-2.
  (keymap-set org-mouse-map "<mouse-2>" #'suderman/org-mouse-open)
  (add-hook 'org-mode-hook #'suderman/org-enable-fold-taps)
  (add-hook 'org-cycle-tab-first-hook #'suderman/org-cycle-adjacent-heading)
  (advice-add 'org-fold-core-region :filter-args
              #'suderman/org-fold-keep-final-newline)
  (advice-add 'org-add-planning-info :around
              #'suderman/org-keep-planning-folded)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (suderman/org-enable-fold-arrows)
        (suderman/org-enable-final-line-reveal)))))

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
  (suderman/treesit-map-org-src))

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
     (sqlite . t)))
  ;; J and K move blocks with M-up and M-down, not load or pop to sessions.
  (remove-hook 'org-metaup-hook #'org-babel-load-in-session-maybe)
  (remove-hook 'org-metadown-hook #'org-babel-pop-to-session-maybe))

(use-package org-superstar
  :after org
  :hook (org-mode . org-superstar-mode)
  :custom
  ;; `suderman/org-fontify-list-bullets' draws list bullets like Markdown's.
  (org-superstar-prettify-item-bullets nil))

;; Scroll wide tables sideways while the surrounding text keeps wrapping.
(use-package phscroll
  :vc (:url "https://github.com/misohena/phscroll" :rev :newest)
  :ensure nil
  :if t
  :after org
  :demand t
  :config
  (require 'org-phscroll))

(use-package org-mouse
  :ensure nil
  :demand t
  :config
  (suderman/org-enable-mouse-todo-clearing))

(provide 'suderman-org)
;;; suderman-org.el ends here
