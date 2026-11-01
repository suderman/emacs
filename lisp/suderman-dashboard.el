;;; suderman-dashboard.el --- On-demand dashboard -*- lexical-binding: t; -*-

;;; Commentary:
;; Dashboard destinations and spatial navigation live here.

;;; Code:

(require 'use-package)
(require 'nerd-icons)
(require 'recentf)
(require 'savehist)
(require 'subr-x)
(require 'suderman-appearance)
(require 'suderman-files)

(declare-function dashboard-open "dashboard")
(eval-when-compile (require 'dashboard-widgets nil t))
(defvar dashboard-buffer-name)
(defvar dashboard-items)
(defvar dashboard-item-generators)
(defvar dashboard-item-shortcuts)
(declare-function dirvish-curr "dirvish")
(declare-function dirvish-quit "dirvish")
(declare-function dv-curr-layout "dirvish")
(declare-function meow-keypad "meow-keypad")
(declare-function widget-get "wid-edit")

(defvar suderman/file-frecency-half-life (* 7 24 60 60)
  "Seconds for a file's visit score to halve.")

(defvar suderman/file-frecency-limit 200
  "Most files to keep visit scores for.")

;; Declared without a value so hot reload's `unload-feature' cannot unbind it.
(defvar suderman/file-frecency)
(unless (boundp 'suderman/file-frecency)
  (setq suderman/file-frecency nil))
(add-to-list 'savehist-additional-variables 'suderman/file-frecency)

(defvar suderman/file-frecency--last nil
  "File most recently counted as a visit.")

(defun suderman/file-frecency-score (entry now)
  "Return the score of ENTRY, a (FILE SCORE . TIME) list, decayed to NOW."
  (* (cadr entry)
     (expt 0.5 (/ (- now (cddr entry)) suderman/file-frecency-half-life))))

(defun suderman/file-frecency-ranked ()
  "Return `suderman/file-frecency' entries, highest current score first."
  (let ((now (float-time)))
    (sort (copy-sequence suderman/file-frecency)
          :key (lambda (entry) (suderman/file-frecency-score entry now))
          :reverse t)))

(defun suderman/file-frecency-track (&optional _frame)
  "Count a visit when the selected window starts showing another file."
  (when-let* ((file (buffer-file-name (window-buffer (selected-window))))
              ((not (equal file suderman/file-frecency--last)))
              ((not (file-remote-p file)))
              ((recentf-include-p file)))
    (setq suderman/file-frecency--last file)
    (let* ((file (abbreviate-file-name file))
           (now (float-time))
           (entry (assoc file suderman/file-frecency))
           (score (if entry (suderman/file-frecency-score entry now) 0)))
      (setq suderman/file-frecency
            (cons (cons file (cons (1+ score) now))
                  (delq entry suderman/file-frecency)))
      (when (> (length suderman/file-frecency) suderman/file-frecency-limit)
        (setq suderman/file-frecency
              (take suderman/file-frecency-limit
                    (suderman/file-frecency-ranked)))))))

(add-hook 'window-buffer-change-functions #'suderman/file-frecency-track)
(add-hook 'window-selection-change-functions #'suderman/file-frecency-track)

(defun suderman/dashboard-move (direction)
  "Move to the nearest Dashboard button in DIRECTION."
  (interactive
   (list (pcase last-command-event
           (?h 'left)
           (?j 'down)
           (?k 'up)
           (?l 'right)
           (_ (user-error "Not a Dashboard direction key")))))
  (let* ((current-widget (get-char-property (point) 'button))
         (current (and current-widget
                       (widget-get current-widget :button-overlay)))
         (origin (or (and current (overlay-start current)) (point)))
         (origin-line (line-number-at-pos origin))
         (origin-left (save-excursion
                        (goto-char origin)
                        (current-column)))
         (origin-right
          (if current
              (save-excursion
                (goto-char (overlay-end current))
                (current-column))
            origin-left))
         (buttons (delq nil
                        (mapcar (lambda (overlay)
                                  (and (overlay-get overlay 'button)
                                       overlay))
                                (overlays-in (point-min) (point-max)))))
         candidates)
    (dolist (button buttons)
      (let* ((start (overlay-start button))
             (end (overlay-end button))
             (line (line-number-at-pos start))
             (left (save-excursion
                     (goto-char start)
                     (current-column)))
             (right (save-excursion
                      (goto-char end)
                      (current-column)))
             (primary
              (pcase direction
                ('left (and (= line origin-line)
                            (<= right origin-left)
                            (- origin-left right)))
                ('right (and (= line origin-line)
                             (>= left origin-right)
                             (- left origin-right)))
                ('up (and (< line origin-line) (- origin-line line)))
                ('down (and (> line origin-line) (- line origin-line)))
                ('first start)))
             (secondary
              (cond
               ((< right origin-left) (- origin-left right))
               ((> left origin-right) (- left origin-right))
               (t 0))))
        (when primary
          (push (list button primary secondary) candidates))))
    (when candidates
      (goto-char
       (overlay-start
        (car (car (sort candidates
                        (lambda (a b)
                          (or (< (cadr a) (cadr b))
                              (and (= (cadr a) (cadr b))
                                   (< (caddr a) (caddr b)))))))))))))

(defun suderman/dashboard-setup ()
  "Prepare Dashboard navigation in the current buffer."
  (suderman/meow-off)
  (suderman/dashboard-move 'first))

(defun suderman/dashboard ()
  "Open Dashboard, replacing an active full-frame Dirvish layout."
  (interactive)
  (when-let* ((session (suderman/dirvish-session))
              ((dv-curr-layout session)))
    (suderman/dirvish-quit-full-frame session))
  (dashboard-open))

(defun suderman/dashboard-open-destination (index)
  "Open pinned Dashboard destination at zero-based INDEX."
  (interactive (list (- last-command-event ?1)))
  (funcall (nth 3 (nth index (car dashboard-navigator-buttons)))))

(defun suderman/dashboard-destinations ()
  "Return pinned Dashboard destinations available on this device."
  (let ((entries
         (append
          `((nerd-icons-mdicon "nf-md-home" "Home"
             "Open home directory" "~/")
            (nerd-icons-sucicon "nf-custom-orgmode" "Org"
             "Open Org directory" "~/org/"))
          (if (featurep 'android)
              '((nerd-icons-mdicon "nf-md-code_braces" "Source"
                 "Open source directory" "~/src/"))
            '((nerd-icons-mdicon "nf-md-account" "Personal"
               "Open personal source" "~/src/suderman/")
              (nerd-icons-mdicon "nf-md-briefcase" "Work"
               "Open work source" "~/src/nonfiction/")))
          `((nerd-icons-sucicon "nf-custom-emacs" "Emacs"
             "Open Emacs configuration" ,user-emacs-directory)
            (nerd-icons-mdicon "nf-md-nix" "NixOS"
             "Open NixOS configuration" "/etc/nixos/")
            (nerd-icons-mdicon "nf-md-note_edit" "Scratch"
             "Open scratch buffer" scratch))))
        (index 0))
    (delq
     nil
     (mapcar
      (lambda (entry)
        (let ((target (nth 4 entry)))
          (when (or (eq target 'scratch)
                    (and (featurep 'android)
                         (member target '("~/org/" "~/src/")))
                    (file-directory-p (expand-file-name target)))
            (setq index (1+ index))
            (list (if (suderman/nerd-fonts-available-p)
                      (funcall (nth 0 entry) (nth 1 entry))
                    (nth 2 entry))
                  (number-to-string index)
                  (nth 3 entry)
                  (if (eq target 'scratch)
                      (lambda (&rest _) (scratch-buffer))
                    (lambda (&rest _) (suderman/dirvish target)))))))
      entries))))

(use-package dashboard
  :demand t
  :init
  (setq dashboard-items '((recents . 5) (frequent . 10) (projects . 5))
        dashboard-startup-banner 'ascii
        dashboard-banner-ascii
        (with-temp-buffer
          (insert-file-contents
           (expand-file-name "assets/dashboard.txt" user-emacs-directory))
          (string-remove-suffix "\n" (buffer-string)))
        dashboard-projects-backend 'project-el
        dashboard-projects-switch-function #'suderman/dirvish
        dashboard-startupify-list '(dashboard-insert-banner
                                    dashboard-insert-newline
                                    dashboard-insert-navigator
                                    dashboard-insert-newline
                                    dashboard-insert-items)
        dashboard-navigator-buttons
        (list (suderman/dashboard-destinations)))
  :config
  ;; A plain `emacs FILE' would split to show this beside FILE.
  (when (daemonp)
    (setq initial-buffer-choice #'suderman/dashboard-initial-buffer))
  (add-to-list 'dashboard-item-generators
               '(frequent . suderman/dashboard-insert-frequent))
  (add-to-list 'dashboard-item-shortcuts '(frequent . "f"))
  (add-hook 'dashboard-mode-hook #'suderman/dashboard-setup)
  (dolist (key '("h" "j" "k" "l"))
    (keymap-set dashboard-mode-map key #'suderman/dashboard-move))
  (dotimes (index 9)
    (keymap-unset dashboard-mode-map (number-to-string (1+ index)) t))
  (dotimes (index (length (car dashboard-navigator-buttons)))
    (keymap-set dashboard-mode-map (number-to-string (1+ index))
                #'suderman/dashboard-open-destination))
  (keymap-set dashboard-mode-map "SPC" #'meow-keypad)
  (keymap-set dashboard-mode-map "," #'suderman/ibuffer-toggle)
  (keymap-set dashboard-mode-map "." #'suderman/dirvish)
  (keymap-set dashboard-mode-map "\\" #'suderman/dirvish-side-toggle)
  (keymap-set dashboard-mode-map "<" #'previous-buffer)
  (keymap-set dashboard-mode-map ">" #'next-buffer)
  (keymap-set dashboard-mode-map "s" #'scratch-buffer))

(defvar suderman/dashboard-frequent-alist nil
  "Shortened Frequent Files entries and their full paths.")

(defun suderman/dashboard-insert-frequent (list-size)
  "Insert LIST-SIZE high-scoring files that Recent Files does not show."
  (let* ((recent (take (alist-get 'recents dashboard-items 0) recentf-list))
         (files (seq-remove (lambda (file)
                              (or (member file recent)
                                  (not (file-exists-p file))))
                            (mapcar #'car (suderman/file-frecency-ranked)))))
    (dashboard-insert-section
     "Frequent Files:"
     (dashboard-shorten-paths files 'suderman/dashboard-frequent-alist 'recents)
     list-size
     'frequent
     (dashboard-get-shortcut 'frequent)
     `(lambda (&rest _)
        (find-file-existing
         (dashboard-expand-path-alist ,el suderman/dashboard-frequent-alist)))
     (propertize
      (dashboard-extract-key-path-alist el suderman/dashboard-frequent-alist)
      'dashboard-path
      (dashboard-expand-path-alist el suderman/dashboard-frequent-alist)))))

(defun suderman/dashboard-initial-buffer ()
  "Return Dashboard in a bare emacsclient frame, otherwise *scratch*."
  (if (frame-parameter nil 'client)
      (progn (dashboard-open)
             (get-buffer dashboard-buffer-name))
    (get-scratch-buffer-create)))

(provide 'suderman-dashboard)
;;; suderman-dashboard.el ends here
