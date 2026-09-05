;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android input helpers and Termux executable discovery.

;;; Code:

(require 'subr-x)

(defvar global-text-scale-adjust-limits)
(defvar pixel-scroll-precision-use-momentum)
(defvar touch-screen-current-tool)
(defvar touch-screen-precision-scroll)

(declare-function pixel-scroll-accumulate-velocity "pixel-scroll" (delta))
(declare-function pixel-scroll-start-momentum "pixel-scroll" (event))

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
  `(create-image
    ,(expand-file-name (format "assets/android-toolbar/%s.pbm" name)
                       user-emacs-directory)
    'pbm nil :scale 1
    :foreground ,(face-foreground 'tool-bar nil t)
    :background ,(face-background 'tool-bar nil t)))

(defun suderman/android-show-keyboard ()
  "Show the Android software keyboard for the selected frame."
  (interactive)
  (frame-toggle-on-screen-keyboard (selected-frame) nil))

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

(defun suderman/android-setup-tool-bar (&optional _theme)
  "Configure the touch-friendly Android input toolbar idempotently."
  (require 'tool-bar)
  (modifier-bar-mode -1)
  (customize-set-variable 'tool-bar-position 'bottom)
  (set-face-attribute 'tool-bar nil
                      :foreground (face-background 'default nil t)
                      :background (face-foreground 'default nil t))
  (setq secondary-tool-bar-map nil
        tool-bar-button-margin '(48 . 20)
        tool-bar-always-show-default t)
  (let ((map (make-sparse-keymap)))
    (define-key-after map [suderman-escape]
      `(menu-item "ESC" suderman/meow-escape
                  :image ,(suderman/android-tool-bar-image "escape")
                  :help "Leave Insert state or cancel"))
    (define-key-after map [suderman-tab]
      `(menu-item "TAB" ignore
                  :image ,(suderman/android-tool-bar-image "tab")
                  :help "Send Tab")
      'suderman-escape)
    (define-key-after map [suderman-files]
      `(menu-item "FILES" suderman/dirvish
                  :image ,(suderman/android-tool-bar-image "files")
                  :help "Open Dirvish")
      'suderman-tab)
    (define-key-after map [suderman-buffers]
      `(menu-item "BUFFERS" suderman/ibuffer-toggle
                  :image ,(suderman/android-tool-bar-image "buffers")
                  :help "Open IBuffer")
      'suderman-files)
    (define-key-after map [suderman-keyboard]
      `(menu-item "KEYBOARD" suderman/android-show-keyboard
                  :image ,(suderman/android-tool-bar-image "keyboard")
                  :help "Show the software keyboard")
      'suderman-buffers)
    (define-key-after map [control]
      `(menu-item "CTRL" ignore
                  :image ,(suderman/android-tool-bar-image "control")
                  :help "Apply Control to the next key")
      'suderman-keyboard)
    (define-key-after map [meta]
      `(menu-item "META" ignore
                  :image ,(suderman/android-tool-bar-image "meta")
                  :help "Apply Meta to the next key")
      'control)
    (set-default 'tool-bar-map map))
  (define-key input-decode-map [tool-bar suderman-escape] nil)
  (define-key input-decode-map [tool-bar suderman-tab] [tab])
  (define-key input-decode-map [tool-bar control]
              #'tool-bar-event-apply-control-modifier)
  (define-key input-decode-map [tool-bar meta]
              #'tool-bar-event-apply-meta-modifier)
  (tool-bar--flush-cache)
  (tool-bar-mode 1)
  (force-mode-line-update t))

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
  (add-hook 'enable-theme-functions #'suderman/android-setup-tool-bar t)
  (suderman/android-setup-tool-bar)
  (define-key function-key-map [volume-down] #'suderman/android-volume-control)
  (define-key function-key-map [volume-up] #'suderman/android-volume-meta))

(provide 'suderman-android)
;;; suderman-android.el ends here
