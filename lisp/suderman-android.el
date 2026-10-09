;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android-only input: volume-key modifiers, pinch zoom, touch scrolling, the
;; software keyboard, the Emacs server, and Termux executables.  The toolbar
;; shared with desktop lives in `suderman-toolbar'.

;;; Code:

(require 'subr-x)

(defvar global-text-scale-adjust-limits)
(defvar pixel-scroll-precision-use-momentum)
(defvar touch-screen-current-tool)
(defvar touch-screen-enable-hscroll)
(defvar touch-screen-extend-selection)
(defvar touch-screen-delay)
(defvar touch-screen-precision-scroll)
(defvar touch-screen-word-select)

(declare-function pixel-scroll-accumulate-velocity "pixel-scroll" (delta))
(declare-function pixel-scroll-start-momentum "pixel-scroll" (event))
(declare-function server-running-p "server" (&optional name))

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
  (advice-add 'touch-screen-handle-scroll :before
              #'suderman/android-record-touch-scroll)
  (advice-add 'touch-screen-handle-touch :before
              #'suderman/android-start-touch-momentum))

(when (eq system-type 'android)
  (require 'server)
  (unless (server-running-p)
    (server-start))
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
