;;; suderman-toolbar.el --- Touch-friendly toolbar -*- lexical-binding: t; -*-

;;; Commentary:
;; A bottom toolbar with sticky Ctrl and Meta, IBuffer, the software keyboard,
;; Dirvish, Tab, and Escape.  Android shows images; desktop shows Nerd Font
;; labels.  F9 toggles it.

;;; Code:

(require 'subr-x)

(defvar modifier-bar-modifier-list)
(defvar overriding-text-conversion-style)
(defvar text-conversion-style)

(declare-function set-text-conversion-style "textconv.c"
                  (style &optional keep-selection))
(declare-function tool-bar-apply-modifiers "tool-bar" (event modifiers))

(defun suderman/tool-bar-image (name)
  "Return a theme-aware tool-bar image expression for NAME."
  (let* ((file (expand-file-name (format "assets/toolbar/%s.pbm" name)
                                 user-emacs-directory))
         (foreground (face-foreground 'tool-bar nil t))
         (background (face-background 'tool-bar nil t)))
    `(create-image ,file 'pbm nil :scale 1
                   :foreground ,foreground :background ,background
                   :mask ',(unless (string-suffix-p "-active" name)
                             'heuristic))))

(defun suderman/tool-bar-state-images (name)
  "Return platform-appropriate state images for toolbar item NAME."
  ;; GTK rejects the four-image state vectors supported by Android, so select
  ;; one image dynamically before GTK validates it.
  (if (not (featurep 'android))
      `(if (memq ',(intern name) modifier-bar-modifier-list)
           ,(suderman/tool-bar-image (concat name "-active"))
         ,(suderman/tool-bar-image name))
    (let ((active (eval (suderman/tool-bar-image
                         (concat name "-active")) t))
          (normal (eval (suderman/tool-bar-image name) t)))
      (vector active normal active normal))))

(defun suderman/tool-bar-refresh ()
  "Rebuild the toolbar after its dynamic modifier state changes."
  (let ((tool-bar-map (default-value 'tool-bar-map)))
    (unless (featurep 'android)
      (dolist (button '((control "Ctrl") (meta "Meta")))
        (when-let* ((binding (assq (car button) (cdr tool-bar-map))))
          (setcar (nthcdr 2 binding)
                  (if (memq (car button) modifier-bar-modifier-list)
                      (upcase (cadr button))
                    (cadr button))))))
    (tool-bar--flush-cache))
  (force-mode-line-update t))

(defun suderman/tool-bar-modifier-button (modifier)
  "Toggle MODIFIER while decoding the next non-toolbar event."
  (let ((old-text-conversion-style text-conversion-style)
        result)
    (when (fboundp 'set-text-conversion-style)
      (set-text-conversion-style nil))
    (unwind-protect
        (setq result
              (let ((modifier-bar-modifier-list (list modifier)))
                (frame-toggle-on-screen-keyboard nil nil)
                (suderman/tool-bar-refresh)
                (redisplay)
                (let ((modifiers (list modifier))
                      (overriding-text-conversion-style nil)
                      event modifier-event)
                  (setq event (read-event))
                  (while (and modifiers (eq event 'tool-bar))
                    (setq modifier-event (event-basic-type (read-event)))
                    (unless (memq modifier-event
                                  '(alt super hyper shift control meta))
                      (user-error "Unknown tool-bar event %s" modifier-event))
                    (if (memq modifier-event modifiers)
                        (setq modifiers (delq modifier-event modifiers)
                              modifier-bar-modifier-list
                              (delq modifier-event modifier-bar-modifier-list))
                      (push modifier-event modifiers)
                      (push modifier-event modifier-bar-modifier-list))
                    (suderman/tool-bar-refresh)
                    (redisplay)
                    (when modifiers
                      (setq event (read-event))))
                  (if modifiers
                      (vector (tool-bar-apply-modifiers event modifiers))
                    []))))
      (unless (or (not (fboundp 'set-text-conversion-style))
                  (eq old-text-conversion-style text-conversion-style))
        (set-text-conversion-style old-text-conversion-style t))
      (suderman/tool-bar-refresh))
    result))

(defun suderman/tool-bar-toggle-control (_prompt)
  "Toggle Control while decoding the next event."
  (suderman/tool-bar-modifier-button 'control))

(defun suderman/tool-bar-toggle-meta (_prompt)
  "Toggle Meta while decoding the next event."
  (suderman/tool-bar-modifier-button 'meta))

(defun suderman/setup-tool-bar (&optional theme)
  "Configure the touch-friendly input toolbar idempotently.
THEME is non-nil when refreshing the toolbar after a theme change."
  (require 'tool-bar)
  (modifier-bar-mode -1)
  (customize-set-variable 'tool-bar-position 'bottom)
  (set-face-attribute 'tool-bar nil
                      :foreground (face-foreground 'default nil t)
                      :background (face-background 'default nil t))
  (setq secondary-tool-bar-map nil
        tool-bar-button-margin (if (featurep 'android) '(48 . 20) 4)
        tool-bar-style (if (featurep 'android) 'image 'text)
        tool-bar-always-show-default t)
  (let ((map (make-sparse-keymap)))
    (define-key-after map [control]
      `(menu-item "Ctrl" ignore
                  :image ,(suderman/tool-bar-state-images "control")
                  :button (:toggle . (memq 'control
                                            modifier-bar-modifier-list))
                  :help "Apply Control to the next key"))
    (define-key-after map [meta]
      `(menu-item "Meta" ignore
                  :image ,(suderman/tool-bar-state-images "meta")
                  :button (:toggle . (memq 'meta
                                            modifier-bar-modifier-list))
                  :help "Apply Meta to the next key")
      'control)
    (define-key-after map [suderman-buffers]
      `(menu-item ,(if (featurep 'android)
                       "BUFFERS"
                     (string #xF018F))
                  suderman/ibuffer-toggle
                  :image ,(suderman/tool-bar-image "buffers")
                  :help "Open IBuffer")
      'meta)
    (define-key-after map [suderman-keyboard]
      `(menu-item ,(if (featurep 'android)
                       "KEYBOARD"
                     (string #xF097B))
                  suderman/android-toggle-keyboard
                  :image ,(suderman/tool-bar-image "keyboard")
                  :help "Show or hide the software keyboard")
      'suderman-buffers)
    (define-key-after map [suderman-files]
      `(menu-item ,(if (featurep 'android)
                       "FILES"
                     (string #xF0256))
                  suderman/dirvish
                  :image ,(suderman/tool-bar-image "files")
                  :help "Open Dirvish")
      'suderman-keyboard)
    (define-key-after map [suderman-tab]
      `(menu-item "Tab" ignore
                  :image ,(suderman/tool-bar-image "tab")
                  :help "Send Tab")
      'suderman-files)
    (define-key-after map [suderman-escape]
      `(menu-item "Esc" suderman/meow-escape
                  :image ,(suderman/tool-bar-image "escape")
                  :help "Leave Insert state or cancel")
      'suderman-tab)
    (set-default 'tool-bar-map map))
  (define-key input-decode-map [tool-bar suderman-escape] nil)
  (define-key input-decode-map [tool-bar suderman-tab] [tab])
  (define-key input-decode-map [tool-bar control]
              #'suderman/tool-bar-toggle-control)
  (define-key input-decode-map [tool-bar meta]
              #'suderman/tool-bar-toggle-meta)
  (tool-bar--flush-cache)
  (unless theme
    (tool-bar-mode 1))
  (force-mode-line-update t))

;; Terminal-only builds such as Termux have no tool bar or images.
(when (fboundp 'tool-bar-mode)
  (add-hook 'enable-theme-functions #'suderman/setup-tool-bar t)
  (suderman/setup-tool-bar))

(provide 'suderman-toolbar)
;;; suderman-toolbar.el ends here
