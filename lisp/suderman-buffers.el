;;; suderman-buffers.el --- Project-oriented buffer list -*- lexical-binding: t; -*-

;;; Commentary:
;; IBuffer presentation and project grouping live here.

;;; Code:

(require 'use-package)
(require 'ibuffer)
(require 'suderman-appearance)
(require 'suderman-projects)
(require 'suderman-windows)

(declare-function suderman/dashboard "suderman-dashboard")
(declare-function suderman/ibuffer-dirvish "suderman-files")
(declare-function suderman/ibuffer-dirvish-side "suderman-files")
(declare-function ibuffer-project-root "ibuffer-project")
(declare-function ibuffer-project-generate-filter-groups "ibuffer-project")

(defvar suderman/ibuffer-grouped nil
  "Non-nil groups IBuffer by project; nil lists recent buffers.")

(defvar suderman/ibuffer-show-hidden nil
  "Non-nil shows the buffers that IBuffer hides by default.")

(defvar suderman/ibuffer-starred-keep '("*scratch*" "*Messages*")
  "Starred buffer names that IBuffer always shows.")

(defun suderman/alternate-buffer ()
  "Switch to the most recent alternate buffer."
  (interactive)
  (let ((buffer (other-buffer (current-buffer) t)))
    (if buffer
        (switch-to-buffer buffer)
      (user-error "No alternate buffer"))))

(define-ibuffer-column suderman-name
  (:name "Name"
         :header-mouse-map ibuffer-name-header-map
         :props
         ('mouse-face 'highlight 'keymap ibuffer-name-map
                      'ibuffer-name-column t
                      'help-echo
                      '(if tooltip-mode
                           "mouse-1: visit this buffer\nmouse-2: toggle its mark\nmouse-3: operate on this buffer"
                         "mouse-1: visit buffer   mouse-2: toggle mark   mouse-3: operate")))
  (let ((string (propertize (buffer-name)
                            'font-lock-face
                            (ibuffer-buffer-name-face buffer mark))))
    (if (not (seq-position string ?\n))
        string
      (string-replace
       "\n" (propertize "^J" 'font-lock-face 'escape-glyph) string))))

(define-ibuffer-column suderman-project
  (:name "Project" :props ('font-lock-face 'shadow))
  (let ((root (car (ibuffer-project-root buffer))))
    (if root (file-name-nondirectory (directory-file-name root)) "")))

(defun suderman/ibuffer-hidden-p (buffer)
  "Return non-nil when IBuffer hides BUFFER by default.
That is a starred buffer, or a file never shown in a window, such as
the files Org Agenda loads."
  (let ((name (buffer-name buffer)))
    (or (and (string-suffix-p "*" name)
             (not (member name suderman/ibuffer-starred-keep)))
        (and (buffer-file-name buffer)
             (not (buffer-local-value 'buffer-display-time buffer))))))

(defun suderman/ibuffer-toggle ()
  "Open IBuffer, or restore the previous buffer when already there.
The recent list starts on the previous buffer, like Alt-Tab."
  (interactive)
  (if (derived-mode-p 'ibuffer-mode)
      (quit-window)
    (let ((buffer (current-buffer)))
      (ibuffer)
      (if suderman/ibuffer-grouped
          (ibuffer-jump-to-buffer (buffer-name buffer))
        (goto-char (point-min))
        (ibuffer-forward-line 0 t)
        (when (eq (ibuffer-current-buffer) buffer)
          (ibuffer-forward-line 1))))))

(defun suderman/ibuffer-toggle-grouped ()
  "Switch IBuffer between the recent list and project groups."
  (interactive)
  (setq suderman/ibuffer-grouped (not suderman/ibuffer-grouped))
  (suderman/ibuffer-setup)
  (unless suderman/ibuffer-grouped
    ;; Android touch scrolls only the grouped view sideways.
    (kill-local-variable 'auto-hscroll-mode)
    (set-window-hscroll nil 0))
  (goto-char (point-min))
  (ibuffer-forward-line 0 t))

(defun suderman/ibuffer-toggle-hidden ()
  "Show or hide the buffers IBuffer hides by default."
  (interactive)
  (setq suderman/ibuffer-show-hidden (not suderman/ibuffer-show-hidden))
  (suderman/ibuffer-setup))

(defun suderman/ibuffer-disable-visual-line-mode ()
  "Keep visual line wrapping disabled in the current IBuffer."
  (when visual-line-mode
    (visual-line-mode -1)))

(defun suderman/ibuffer-disable-meow ()
  "Disable Meow in the current IBuffer."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/ibuffer-open ()
  "Visit the buffer at point, or toggle the current project group."
  (interactive)
  (if (ibuffer-current-buffer)
      (ibuffer-visit-buffer)
    (ibuffer-toggle-filter-group)))

(defun suderman/ibuffer-toggle-mark ()
  "Toggle the ordinary mark at point without moving to another row."
  (interactive)
  (let ((group (get-text-property (point) 'ibuffer-filter-group-name)))
    (cond
     (group
      (ibuffer-toggle-marks group))
     ((ibuffer-current-buffer)
      (ibuffer-set-mark
       (if (eq (ibuffer-current-mark) ibuffer-marked-char)
           ?\s
         ibuffer-marked-char)))
     (t
      (user-error "No buffer at point")))))

(defun suderman/ibuffer-mark-all ()
  "Mark every visible buffer row."
  (interactive)
  (ibuffer-mark-on-buffer #'identity))

(defun suderman/ibuffer-unmark ()
  "Unmark at point without moving to another row."
  (interactive)
  (save-excursion
    (call-interactively #'ibuffer-unmark-forward)))

(defun suderman/ibuffer-group-at-point ()
  "Return the group name when point is on an IBuffer group header."
  (get-text-property (line-beginning-position) 'ibuffer-filter-group-name))

(defun suderman/ibuffer-next-sibling (&optional n)
  "Move to the Nth next row of the same kind, or previous if N < 0.
Buffers stop at the edge of their group; group headers move among groups."
  (interactive "p")
  (let ((n (or n 1))
        (header (suderman/ibuffer-group-at-point))
        target)
    (save-excursion
      (dotimes (_ (abs n))
        (setq target nil)
        (catch 'done
          (while (zerop (forward-line (if (> n 0) 1 -1)))
            (cond ((suderman/ibuffer-group-at-point)
                   (when header (setq target (point)))
                   (throw 'done nil))
                  ((and (not header) (ibuffer-current-buffer))
                   (setq target (point))
                   (throw 'done nil)))))
        (unless target
          (user-error (if (> n 0) "No next entry here" "No previous entry here")))))
    (goto-char target)))

(defun suderman/ibuffer-previous-sibling (&optional n)
  "Move to the Nth previous row of the same kind."
  (interactive "p")
  (suderman/ibuffer-next-sibling (- (or n 1))))

(defun suderman/ibuffer-parent ()
  "Move to the group header that holds the buffer at point."
  (interactive)
  (when (suderman/ibuffer-group-at-point)
    (user-error "Already at the top"))
  (while (and (zerop (forward-line -1))
              (not (suderman/ibuffer-group-at-point))))
  (beginning-of-line))

(defun suderman/ibuffer-child ()
  "Expand the group at point if needed and move to its first buffer."
  (interactive)
  (let ((group (suderman/ibuffer-group-at-point)))
    (unless group
      (user-error "Not a group"))
    (when (member group ibuffer-hidden-filter-groups)
      (ibuffer-toggle-filter-group)
      (goto-char (point-min))
      (while (and (not (equal (suderman/ibuffer-group-at-point) group))
                  (zerop (forward-line 1)))))
    (forward-line 1)
    (unless (ibuffer-current-buffer)
      (forward-line -1)
      (user-error "Empty group"))
    (beginning-of-line)))

(defun suderman/ibuffer-setup ()
  "Apply project grouping and display defaults to IBuffer."
  (add-hook 'meow-mode-hook #'suderman/ibuffer-disable-meow nil t)
  (add-hook 'visual-line-mode-hook
            #'suderman/ibuffer-disable-visual-line-mode nil t)
  (suderman/ibuffer-disable-meow)
  (suderman/ibuffer-disable-visual-line-mode)
  (if suderman/ibuffer-grouped
      (setq ibuffer-filter-groups
            (append (ibuffer-project-generate-filter-groups)
                    '(("Images" (derived-mode . image-mode))))
            ibuffer-sorting-mode 'project-file-relative
            ibuffer-current-format 1)
    (setq ibuffer-filter-groups '(("Recent"))
          ibuffer-sorting-mode 'recency
          ibuffer-current-format 0))
  (setq-local ibuffer-maybe-show-predicates
              (append (unless suderman/ibuffer-show-hidden
                        '(suderman/ibuffer-hidden-p))
                      (default-value 'ibuffer-maybe-show-predicates)))
  (ibuffer-update nil t))

(use-package ibuffer
  :ensure nil
  :demand t
  :init
  (setq ibuffer-use-other-window nil
        ibuffer-never-show-predicates
        '("\\` ?\\*dirvish-\\(?:parent-[0-9]+\\|preview\\|shell\\|header\\|footer\\)@"
          "\\`PREVIEW :: ")
        ibuffer-expert t
        ibuffer-display-summary nil
        ibuffer-show-empty-filter-groups nil
        ibuffer-use-header-line 'title
        ibuffer-formats
        `((mark modified read-only " "
                ,@(when (suderman/nerd-fonts-available-p) '((icon 2 2)))
                (suderman-name 40 40 :left :elide) " "
                suderman-project)
          (mark modified read-only " "
                ,@(when (suderman/nerd-fonts-available-p) '((icon 2 2)))
                (suderman-name 32 32 :left :elide) " "
                (mode+ 16 16 :left :elide) " "
                (size-h 7 -1 :right) " "
                suderman-project-file-relative)))
  :config
  (keymap-set ibuffer-name-map "<mouse-1>" #'ibuffer-mouse-visit-buffer)
  (keymap-set ibuffer-name-map "<mouse-2>" #'ibuffer-mouse-toggle-mark)
  (keymap-set ibuffer-mode-map "`" #'suderman/dashboard)
  (keymap-set ibuffer-mode-map "," #'suderman/ibuffer-toggle)
  (keymap-set ibuffer-mode-map "h" #'suderman/ibuffer-toggle)
  (keymap-set ibuffer-mode-map "<left>" #'suderman/ibuffer-toggle)
  (keymap-set ibuffer-mode-map "j" #'ibuffer-forward-line)
  (keymap-set ibuffer-mode-map "n" #'ibuffer-forward-line)
  (keymap-set ibuffer-mode-map "<down>" #'ibuffer-forward-line)
  (keymap-set ibuffer-mode-map "k" #'ibuffer-backward-line)
  (keymap-set ibuffer-mode-map "p" #'ibuffer-backward-line)
  (keymap-set ibuffer-mode-map "<up>" #'ibuffer-backward-line)
  (keymap-set ibuffer-mode-map "l" #'suderman/ibuffer-open)
  (keymap-set ibuffer-mode-map "<right>" #'suderman/ibuffer-open)
  (keymap-set ibuffer-mode-map "m" #'suderman/ibuffer-toggle-mark)
  (keymap-set ibuffer-mode-map ";" #'suderman/ibuffer-toggle-grouped)
  (keymap-set ibuffer-mode-map "[" #'suderman/ibuffer-previous-sibling)
  (keymap-set ibuffer-mode-map "]" #'suderman/ibuffer-next-sibling)
  (keymap-set ibuffer-mode-map "{" #'suderman/ibuffer-parent)
  (keymap-set ibuffer-mode-map "}" #'suderman/ibuffer-child)
  (keymap-set ibuffer-mode-map "i" #'suderman/ibuffer-toggle-hidden)
  (keymap-set ibuffer-mode-map "d" #'ibuffer-do-delete)
  (keymap-set ibuffer-mode-map "M" #'suderman/ibuffer-mark-all)
  (keymap-set ibuffer-mode-map "u" #'suderman/ibuffer-unmark)
  (keymap-set ibuffer-mode-map "U" #'ibuffer-unmark-all-marks)
  (keymap-set ibuffer-mode-map "B" #'ibuffer-copy-buffername-as-kill)
  (keymap-set ibuffer-mode-map "<" #'previous-buffer)
  (keymap-set ibuffer-mode-map ">" #'next-buffer)
  (keymap-set ibuffer-mode-map "." #'suderman/ibuffer-dirvish)
  (keymap-set ibuffer-mode-map "\\" #'suderman/ibuffer-dirvish-side)
  (keymap-set ibuffer-mode-map "SPC" #'meow-keypad)
  (keymap-unset ibuffer-mode-map "S" t)
  (keymap-unset ibuffer-mode-map "H" t)
  (suderman/install-keys ibuffer-mode-map suderman/window-keys))

(use-package ibuffer-project
  :after ibuffer
  :demand t
  :init
  (setq ibuffer-project-root-functions
        '(((lambda (dir)
              (let ((root (ibuffer-project-project-root dir)))
                (and root (abbreviate-file-name root)))) . ""))
        ibuffer-project-use-cache nil)
  :config
  (define-ibuffer-column suderman-project-file-relative
    (:name "Filename"
           :props ('font-lock-face 'nerd-icons-ibuffer-file-face)
           :header-mouse-map ibuffer-project-file-relative-header-map)
    (let* ((file (buffer-local-value 'buffer-file-name buffer))
           (project (and file (project-current nil (file-name-directory file)))))
      (if (suderman/project-p project)
          (let ((source (suderman/project--directory
                         suderman/project-source-root project))
                (data (suderman/project--directory
                       suderman/project-data-root project)))
            (cond
             ((string-prefix-p source file)
              (concat "src/" (file-relative-name file source)))
             ((string-prefix-p data file)
              (concat "data/" (file-relative-name file data)))
             (t (ibuffer-make-column-project-file-relative buffer mark))))
        (ibuffer-make-column-project-file-relative buffer mark))))
  (add-hook 'ibuffer-hook #'suderman/ibuffer-setup)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'ibuffer-mode)
        (suderman/ibuffer-setup)))))

(use-package nerd-icons-ibuffer
  :after (ibuffer ibuffer-project)
  :demand t)

(provide 'suderman-buffers)
;;; suderman-buffers.el ends here
