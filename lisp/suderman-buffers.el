;;; suderman-buffers.el --- Project-oriented buffer list -*- lexical-binding: t; -*-

;;; Commentary:
;; IBuffer presentation and project grouping live here.

;;; Code:

(require 'use-package)
(require 'ibuffer)
(require 'suderman-windows)

(declare-function suderman/dashboard "suderman-dashboard")

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

(defun suderman/ibuffer-toggle ()
  "Open IBuffer, or restore the previous buffer when already there."
  (interactive)
  (if (derived-mode-p 'ibuffer-mode)
      (quit-window)
    (let ((buffer-name (buffer-name)))
      (ibuffer)
      (ibuffer-jump-to-buffer buffer-name))))

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

(defun suderman/ibuffer-setup ()
  "Apply project grouping and display defaults to IBuffer."
  (add-hook 'meow-mode-hook #'suderman/ibuffer-disable-meow nil t)
  (add-hook 'visual-line-mode-hook
            #'suderman/ibuffer-disable-visual-line-mode nil t)
  (suderman/ibuffer-disable-meow)
  (suderman/ibuffer-disable-visual-line-mode)
  (setq ibuffer-filter-groups
        (append (ibuffer-project-generate-filter-groups)
                '(("Images" (derived-mode . image-mode)))))
  (unless (eq ibuffer-sorting-mode 'project-file-relative)
    (ibuffer-do-sort-by-project-file-relative)))

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
        '((mark modified read-only " "
                (icon 2 2)
                (suderman-name 24 32 :left :elide) " "
                (mode+ 16 20 :left :elide) " "
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
  (keymap-set ibuffer-mode-map "<down>" #'ibuffer-forward-line)
  (keymap-set ibuffer-mode-map "k" #'ibuffer-backward-line)
  (keymap-set ibuffer-mode-map "<up>" #'ibuffer-backward-line)
  (keymap-set ibuffer-mode-map "l" #'suderman/ibuffer-open)
  (keymap-set ibuffer-mode-map "<right>" #'suderman/ibuffer-open)
  (keymap-set ibuffer-mode-map "m" #'suderman/ibuffer-toggle-mark)
  (keymap-set ibuffer-mode-map "M" #'suderman/ibuffer-mark-all)
  (keymap-set ibuffer-mode-map "u" #'suderman/ibuffer-unmark)
  (keymap-set ibuffer-mode-map "U" #'ibuffer-unmark-all-marks)
  (keymap-set ibuffer-mode-map "M-h" #'suderman/window-left)
  (keymap-set ibuffer-mode-map "M-j" #'windmove-down)
  (keymap-set ibuffer-mode-map "M-k" #'windmove-up)
  (keymap-set ibuffer-mode-map "M-l" #'windmove-right)
  (keymap-set ibuffer-mode-map "M-H" #'suderman/resize-window-left)
  (keymap-set ibuffer-mode-map "M-J" #'suderman/resize-window-down)
  (keymap-set ibuffer-mode-map "M-K" #'suderman/resize-window-up)
  (keymap-set ibuffer-mode-map "M-L" #'suderman/resize-window-right)
  (keymap-set ibuffer-mode-map "M-u" #'suderman/split-window-below-and-focus)
  (keymap-set ibuffer-mode-map "M-i" #'suderman/split-window-right-and-focus)
  (keymap-set ibuffer-mode-map "M-w" #'suderman/delete-window-or-tab))

(use-package ibuffer-project
  :after ibuffer
  :demand t
  :init
  (setq ibuffer-project-root-functions
        '((ibuffer-project-project-root . ""))
        ibuffer-project-use-cache nil)
  :config
  (add-hook 'ibuffer-hook #'suderman/ibuffer-setup)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'ibuffer-mode)
        (suderman/ibuffer-setup)))))

(use-package nerd-icons-ibuffer
  :after (ibuffer ibuffer-project)
  :demand t
  :config
  (define-ibuffer-column suderman-project-file-relative
    (:name "Filename"
           :props ('font-lock-face 'nerd-icons-ibuffer-file-face)
           :header-mouse-map ibuffer-project-file-relative-header-map)
    (ibuffer-make-column-project-file-relative buffer mark)))

(provide 'suderman-buffers)
;;; suderman-buffers.el ends here
