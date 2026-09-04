;;; suderman-dashboard.el --- Minimal startup dashboard -*- lexical-binding: t; -*-

;;; Commentary:
;; Dashboard startup, common destinations, and spatial navigation live here.

;;; Code:

(require 'use-package)
(require 'nerd-icons)
(require 'subr-x)
(require 'suderman-appearance)
(require 'suderman-files)

(declare-function dashboard-open "dashboard")
(declare-function dirvish-curr "dirvish")
(declare-function dirvish-quit "dirvish")
(declare-function dv-curr-layout "dirvish")
(declare-function meow--disable "meow")
(declare-function meow-keypad "meow-keypad")
(declare-function meow-mode "meow")
(declare-function widget-get "wid-edit")

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

(defun suderman/dashboard-disable-meow ()
  "Disable Meow in the current Dashboard buffer."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/dashboard-setup ()
  "Prepare Dashboard navigation in the current buffer."
  (add-hook 'meow-mode-hook #'suderman/dashboard-disable-meow nil t)
  (suderman/dashboard-disable-meow)
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
  "Return pinned Dashboard destinations that exist on this device."
  (let ((entries
         `((nerd-icons-mdicon "nf-md-home" "Home"
            "Open home directory" "~/")
           (nerd-icons-sucicon "nf-custom-orgmode" "Org"
            "Open Org directory" "~/org/")
           (nerd-icons-mdicon "nf-md-account" "Personal"
            "Open personal source" "~/src/suderman/")
           (nerd-icons-mdicon "nf-md-briefcase" "Work"
            "Open work source" "~/src/nonfiction/")
           (nerd-icons-sucicon "nf-custom-emacs" "Emacs"
            "Open Emacs configuration" ,user-emacs-directory)
           (nerd-icons-mdicon "nf-md-nix" "NixOS"
            "Open NixOS configuration" "/etc/nixos/")
           (nerd-icons-mdicon "nf-md-folder_cog" "Config"
            "Open config directory" "~/.config/")
           (nerd-icons-mdicon "nf-md-note_edit" "Scratch"
            "Open scratch buffer" scratch)))
        (index 0))
    (delq
     nil
     (mapcar
      (lambda (entry)
        (let ((target (nth 4 entry)))
          (when (or (eq target 'scratch)
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
  (setq dashboard-items '((projects . 5) (recents . 5))
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
  (setq initial-buffer-choice #'dashboard-open)
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
  (keymap-set dashboard-mode-map "s" #'scratch-buffer))

(provide 'suderman-dashboard)
;;; suderman-dashboard.el ends here
