;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android input helpers and Termux executable discovery.

;;; Code:

(require 'subr-x)

(defvar global-text-scale-adjust-limits)
(defvar modifier-bar-modifier-list)
(defvar overriding-text-conversion-style)
(defvar pixel-scroll-precision-use-momentum)
(defvar text-conversion-style)
(defvar touch-screen-current-tool)
(defvar touch-screen-enable-hscroll)
(defvar touch-screen-extend-selection)
(defvar touch-screen-delay)
(defvar touch-screen-precision-scroll)
(defvar touch-screen-word-select)

(declare-function pixel-scroll-accumulate-velocity "pixel-scroll" (delta))
(declare-function pixel-scroll-start-momentum "pixel-scroll" (event))
(declare-function set-text-conversion-style "textconv.c"
                  (style &optional keep-selection))
(declare-function tool-bar-apply-modifiers "tool-bar" (event modifiers))

(defconst suderman/android-termux-bin
  "/data/data/com.termux/files/usr/bin")

(defun suderman/android-volume-control (_prompt)
  "Apply Control to the next event, or make Volume Up send Escape."
  (let ((event (read-event)))
    (if (eq event 'volume-up)
        [escape]
      (vector (event-apply-modifier event 'control 26 "C-")))))

(defun suderman/android-volume-meta (_prompt)
  "Apply Meta to the next event, or make Volume Down send Tab."
  (let ((event (read-event)))
    (if (eq event 'volume-down)
        [tab]
      (vector (event-apply-modifier event 'meta 27 "M-")))))

(defun suderman/android-tool-bar-image (name)
  "Return a theme-aware tool-bar image expression for NAME."
  (let* ((file (expand-file-name (format "assets/android-toolbar/%s.pbm" name)
                                 user-emacs-directory))
         (foreground (face-foreground 'tool-bar nil t))
         (background (face-background 'tool-bar nil t)))
    `(create-image ,file 'pbm nil :scale 1
                   :foreground ,foreground :background ,background
                   :mask ',(unless (string-suffix-p "-active" name)
                             'heuristic))))

(defun suderman/android-tool-bar-state-images (name)
  "Return platform-appropriate state images for toolbar item NAME."
  ;; GTK rejects the four-image state vectors supported by Android, so select
  ;; one image dynamically before GTK validates it.
  (if (not (eq system-type 'android))
      `(if (memq ',(intern name) modifier-bar-modifier-list)
           ,(suderman/android-tool-bar-image (concat name "-active"))
         ,(suderman/android-tool-bar-image name))
    (let ((active (eval (suderman/android-tool-bar-image
                         (concat name "-active")) t))
          (normal (eval (suderman/android-tool-bar-image name) t)))
      (vector active normal active normal))))

(defun suderman/tool-bar-refresh ()
  "Rebuild the toolbar after its dynamic modifier state changes."
  (let ((tool-bar-map (default-value 'tool-bar-map)))
    (unless (eq system-type 'android)
      (dolist (button '((control "Ctrl") (meta "Meta")))
        (when-let* ((binding (assq (car button) (cdr tool-bar-map))))
          (setcar (nthcdr 2 binding)
                  (if (memq (car button) modifier-bar-modifier-list)
                      (upcase (cadr button))
                    (cadr button))))))
    (tool-bar--flush-cache))
  (force-mode-line-update t))

(defun suderman/android-modifier-bar-button (modifier)
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

(defun suderman/android-toggle-control-modifier (_prompt)
  "Toggle Control while decoding the next event."
  (suderman/android-modifier-bar-button 'control))

(defun suderman/android-toggle-meta-modifier (_prompt)
  "Toggle Meta while decoding the next event."
  (suderman/android-modifier-bar-button 'meta))

(defun suderman/android-keyboard-visible-p (frame)
  "Return non-nil when FRAME appears shortened by the Android keyboard.
Android exposes no keyboard visibility query to Lisp, so remember the
largest frame height seen at the current width.  Another same-width frame
resize can therefore be mistaken for the keyboard."
  (let* ((size (cons (frame-pixel-width frame) (frame-pixel-height frame)))
         (full-size
          (frame-parameter frame 'suderman/android-keyboard-full-size)))
    (when (or (not (consp full-size))
              (/= (car size) (car full-size))
              (> (cdr size) (cdr full-size)))
      (setq full-size size)
      (set-frame-parameter frame 'suderman/android-keyboard-full-size size))
    (< (cdr size) (cdr full-size))))

(defun suderman/android-toggle-keyboard ()
  "Show or hide the Android software keyboard for the selected frame."
  (interactive)
  (let ((frame (selected-frame)))
    (frame-toggle-on-screen-keyboard
     frame (suderman/android-keyboard-visible-p frame))))

(defun suderman/android-global-pinch (event)
  "Use Android pinch EVENT to scale the default face globally."
  (interactive "e")
  (let* ((ratio (nth 2 event))
         (previous-ratio (- ratio (nth 5 event))))
    (when (> previous-ratio 0)
      (let* ((height (face-attribute 'default :height nil 'default))
             (new-height (round (* height (/ ratio previous-ratio)))))
        (setq new-height
              (max (car global-text-scale-adjust-limits)
                   (min (cdr global-text-scale-adjust-limits) new-height)))
        (set-face-attribute 'default nil :height new-height)))))

(defun suderman/android-record-touch-scroll (_dx dy)
  "Record vertical touch movement DY for kinetic scrolling."
  (pixel-scroll-accumulate-velocity (- dy)))

(defun suderman/android-start-touch-momentum (event &rest _)
  "Start momentum after a completed touch-scroll EVENT."
  (when (and (eq (car event) 'touchscreen-end)
             (eq (caadr event) (car touch-screen-current-tool))
             (eq (nth 3 touch-screen-current-tool) 'scroll)
             (not (caddr event)))
    (pixel-scroll-start-momentum event)))

(defun suderman/android-setup-touch-scrolling ()
  "Configure Android touch input and momentum idempotently."
  (require 'pixel-scroll)
  (require 'touch-screen)
  ;; Disable horizontal swipes; horizontal scrolling also defeats visual wrapping.
  ;; Keep vertical swipes pixel-precise, and let touch adjust either end of a
  ;; word selection.  Shorten long press and hide drag events in the echo area.
  (setq touch-screen-enable-hscroll nil
        touch-screen-precision-scroll t
        touch-screen-word-select t
        touch-screen-extend-selection t
        touch-screen-delay 0.5
        echo-keystrokes 0
        pixel-scroll-precision-use-momentum t)
  (setq-default make-cursor-line-fully-visible nil)
  (advice-remove 'touch-screen-handle-scroll
                 #'suderman/android-record-touch-scroll)
  (advice-add 'touch-screen-handle-scroll :before
              #'suderman/android-record-touch-scroll)
  (advice-remove 'touch-screen-handle-touch
                 #'suderman/android-start-touch-momentum)
  (advice-add 'touch-screen-handle-touch :before
              #'suderman/android-start-touch-momentum))

(defun suderman/android-setup-tool-bar (&optional theme)
  "Configure the touch-friendly input toolbar idempotently.
THEME is non-nil when refreshing the toolbar after a theme change."
  (require 'tool-bar)
  (modifier-bar-mode -1)
  (customize-set-variable 'tool-bar-position 'bottom)
  (set-face-attribute 'tool-bar nil
                      :foreground (face-foreground 'default nil t)
                      :background (face-background 'default nil t))
  (setq secondary-tool-bar-map nil
        tool-bar-button-margin (if (eq system-type 'android) '(48 . 20) 4)
        tool-bar-style (if (eq system-type 'android) 'image 'text)
        tool-bar-always-show-default t)
  (let ((map (make-sparse-keymap)))
    (define-key-after map [control]
      `(menu-item "Ctrl" ignore
                  :image ,(suderman/android-tool-bar-state-images "control")
                  :button (:toggle . (memq 'control
                                            modifier-bar-modifier-list))
                  :help "Apply Control to the next key"))
    (define-key-after map [meta]
      `(menu-item "Meta" ignore
                  :image ,(suderman/android-tool-bar-state-images "meta")
                  :button (:toggle . (memq 'meta
                                            modifier-bar-modifier-list))
                  :help "Apply Meta to the next key")
      'control)
    (define-key-after map [suderman-buffers]
      `(menu-item ,(if (eq system-type 'android)
                       "BUFFERS"
                     (string #xF018F))
                  suderman/ibuffer-toggle
                  :image ,(suderman/android-tool-bar-image "buffers")
                  :help "Open IBuffer")
      'meta)
    (define-key-after map [suderman-keyboard]
      `(menu-item ,(if (eq system-type 'android)
                       "KEYBOARD"
                     (string #xF097B))
                  suderman/android-toggle-keyboard
                  :image ,(suderman/android-tool-bar-image "keyboard")
                  :help "Show or hide the software keyboard")
      'suderman-buffers)
    (define-key-after map [suderman-files]
      `(menu-item ,(if (eq system-type 'android)
                       "FILES"
                     (string #xF0256))
                  suderman/dirvish
                  :image ,(suderman/android-tool-bar-image "files")
                  :help "Open Dirvish")
      'suderman-keyboard)
    (define-key-after map [suderman-tab]
      `(menu-item "Tab" ignore
                  :image ,(suderman/android-tool-bar-image "tab")
                  :help "Send Tab")
      'suderman-files)
    (define-key-after map [suderman-escape]
      `(menu-item "Esc" suderman/meow-escape
                  :image ,(suderman/android-tool-bar-image "escape")
                  :help "Leave Insert state or cancel")
      'suderman-tab)
    (set-default 'tool-bar-map map))
  (define-key input-decode-map [tool-bar suderman-escape] nil)
  (define-key input-decode-map [tool-bar suderman-tab] [tab])
  (define-key input-decode-map [tool-bar control]
              #'suderman/android-toggle-control-modifier)
  (define-key input-decode-map [tool-bar meta]
              #'suderman/android-toggle-meta-modifier)
  (tool-bar--flush-cache)
  (unless theme
    (tool-bar-mode 1))
  (force-mode-line-update t))

(add-hook 'enable-theme-functions #'suderman/android-setup-tool-bar t)
(suderman/android-setup-tool-bar)

(when (eq system-type 'android)
  (add-to-list 'exec-path suderman/android-termux-bin)
  (setenv "PATH"
          (string-join (delete-dups
                        (cons suderman/android-termux-bin
                              (parse-colon-path (getenv "PATH"))))
                       path-separator))
  (require 'face-remap)
  (global-set-key [touchscreen-pinch] #'suderman/android-global-pinch)
  (suderman/android-setup-touch-scrolling)
  (suderman/android-keyboard-visible-p (selected-frame))
  (define-key function-key-map [volume-down] #'suderman/android-volume-control)
  (define-key function-key-map [volume-up] #'suderman/android-volume-meta))

(provide 'suderman-android)
;;; suderman-android.el ends here
