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
(defvar touch-screen-precision-scroll)

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

;; GTK reloads toolbar :file images itself, bypassing Emacs image scaling,
;; theme colors, and masks.  Its natural button padding is also the minimum,
;; so render desktop glyphs directly at their final size as SVG :data.
(defun suderman/tool-bar-desktop-svg-data (name foreground background)
  "Return a final-size desktop toolbar SVG for NAME using theme colors."
  (let* ((active (string-suffix-p "-active" name))
         (name (string-remove-suffix "-active" name))
         (spec
          (pcase name
            ("control" '("Ctrl" 28 11 14 "JetBrainsMono Nerd Font Mono"))
            ("meta" '("Meta" 28 11 14 "JetBrainsMono Nerd Font Mono"))
            ("tab" '("Tab" 22 11 14 "JetBrainsMono Nerd Font Mono"))
            ("escape" '("Esc" 22 11 14 "JetBrainsMono Nerd Font Mono"))
            ("buffers" '("&#xF018F;" 22 18 18 "Symbols Nerd Font Mono"))
            ("keyboard" '("&#xF097B;" 22 18 18 "Symbols Nerd Font Mono"))
            ("files" '("&#xF0256;" 22 18 18 "Symbols Nerd Font Mono"))
            (_ (error "Unknown toolbar image %s" name))))
         (text (nth 0 spec))
         (width (nth 1 spec))
         (height 22)
         (font-size (nth 2 spec))
         (baseline (nth 3 spec))
         (family (nth 4 spec)))
    (format
     (concat "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" "
             "height=\"%d\" viewBox=\"0 0 %d %d\" "
             "text-rendering=\"geometricPrecision\">%s"
             "<text x=\"50%%\" y=\"%d\" text-anchor=\"middle\" "
             "font-family=\"%s\" font-size=\"%d\" font-weight=\"600\" "
             "fill=\"%s\">%s</text></svg>")
     width height width height
     (if active
         (format "<rect width=\"%d\" height=\"%d\" rx=\"2\" fill=\"%s\"/>"
                 width height foreground)
       "")
     baseline family font-size (if active background foreground) text)))

(defun suderman/android-tool-bar-image (name)
  "Return a theme-aware tool-bar image expression for NAME."
  (let* ((file (expand-file-name (format "assets/android-toolbar/%s.pbm" name)
                                 user-emacs-directory))
         (android (eq system-type 'android))
         (foreground (face-foreground 'tool-bar nil t))
         (background (face-background 'tool-bar nil t)))
    (if android
        `(create-image ,file 'pbm nil :scale 1
                       :foreground ,foreground :background ,background
                       :mask ',(unless (string-suffix-p "-active" name)
                                 'heuristic))
      `(create-image
        ,(suderman/tool-bar-desktop-svg-data name foreground background)
        'svg t :scale 1))))

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
  "Enable pixel-precise touch scrolling with momentum idempotently."
  (require 'pixel-scroll)
  (require 'touch-screen)
  (setq touch-screen-precision-scroll t
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
        tool-bar-style 'image
        tool-bar-always-show-default t)
  (let ((map (make-sparse-keymap)))
    (define-key-after map [control]
      `(menu-item "CTRL" ignore
                  :image ,(suderman/android-tool-bar-state-images "control")
                  :button (:toggle . (memq 'control
                                            modifier-bar-modifier-list))
                  :help "Apply Control to the next key"))
    (define-key-after map [meta]
      `(menu-item "META" ignore
                  :image ,(suderman/android-tool-bar-state-images "meta")
                  :button (:toggle . (memq 'meta
                                            modifier-bar-modifier-list))
                  :help "Apply Meta to the next key")
      'control)
    (define-key-after map [suderman-buffers]
      `(menu-item "BUFFERS" suderman/ibuffer-toggle
                  :image ,(suderman/android-tool-bar-image "buffers")
                  :help "Open IBuffer")
      'meta)
    (define-key-after map [suderman-keyboard]
      `(menu-item "KEYBOARD" suderman/android-toggle-keyboard
                  :image ,(suderman/android-tool-bar-image "keyboard")
                  :help "Show or hide the software keyboard")
      'suderman-buffers)
    (define-key-after map [suderman-files]
      `(menu-item "FILES" suderman/dirvish
                  :image ,(suderman/android-tool-bar-image "files")
                  :help "Open Dirvish")
      'suderman-keyboard)
    (define-key-after map [suderman-tab]
      `(menu-item "TAB" ignore
                  :image ,(suderman/android-tool-bar-image "tab")
                  :help "Send Tab")
      'suderman-files)
    (define-key-after map [suderman-escape]
      `(menu-item "ESC" suderman/meow-escape
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
