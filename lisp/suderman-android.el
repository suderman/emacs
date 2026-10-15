;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android-only input: volume-key modifiers, pinch zoom, touch scrolling, the
;; software keyboard, the Emacs server, and Termux executables.  The toolbar
;; shared with desktop lives in `suderman-toolbar'.

;;; Code:

(require 'subr-x)

(defvar global-text-scale-adjust-limits)
(defvar touch-screen-current-tool)
(defvar touch-screen-enable-hscroll)
(defvar touch-screen-extend-selection)
(defvar touch-screen-delay)
(defvar touch-screen-precision-scroll)
(defvar touch-screen-word-select)

(declare-function pixel-scroll-precision-scroll-down-page "pixel-scroll" (delta))
(declare-function pixel-scroll-precision-scroll-up-page "pixel-scroll" (delta))
(declare-function server-running-p "server" (&optional name))
(declare-function suderman/sync-fixed-pitch-height "suderman-appearance")

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
        (set-face-attribute 'default nil :height new-height)
        (suderman/sync-fixed-pitch-height)))))

(defvar suderman/android-fling-time-constant 0.35
  "Seconds for a touch fling to lose about two thirds of its speed.")

(defvar suderman/android-fling-min-velocity 300
  "Release speed in pixels per second below which a swipe does not fling.")

(defvar suderman/android-touch-samples nil
  "Recent vertical touch-scroll movements as (TIME . DY), newest first.")

(defun suderman/android-recent-touch-samples (now)
  "Return touch samples from the 0.1 seconds before NOW."
  (seq-take-while (lambda (sample) (< (- now (car sample)) 0.1))
                  suderman/android-touch-samples))

(defun suderman/android-record-touch-scroll (_dx dy)
  "Record vertical touch movement DY for flinging."
  (let ((now (float-time)))
    (push (cons now dy) suderman/android-touch-samples)
    (setq suderman/android-touch-samples
          (suderman/android-recent-touch-samples now))))

(defun suderman/android-touch-velocity ()
  "Return the vertical swipe speed at release in pixels per second.
Only the last 0.1 seconds count, so a pause before lifting stops the fling."
  (let* ((now (float-time))
         (samples (suderman/android-recent-touch-samples now)))
    (if (cdr samples)
        ;; The oldest sample's movement happened before its own timestamp.
        (/ (apply #'+ (mapcar #'cdr (butlast samples)))
           (- now (car (car (last samples)))))
      0)))

(defun suderman/android-fling (window velocity)
  "Keep scrolling WINDOW at VELOCITY pixels per second, slowing with friction.
Steps use real elapsed time, so slow redisplay never slows the motion.  Any
input stops the fling."
  (let ((last (float-time))
        (carry 0.0)
        ;; A collection takes about 0.1 seconds on the phone, long enough to
        ;; make the fling jump.  Defer it until the fling stops.
        (gc-cons-threshold most-positive-fixnum))
    (with-selected-window window
      (condition-case nil
          (while (and (> (abs velocity) 30)
                      (sit-for 0.001))
            (let* ((now (float-time))
                   (dt (- now last))
                   (distance (+ carry (* velocity dt)))
                   (pixels (truncate distance)))
              (setq last now
                    carry (- distance pixels)
                    velocity (* velocity
                                (exp (- (/ dt suderman/android-fling-time-constant)))))
              (cond ((> pixels 0) (pixel-scroll-precision-scroll-down-page pixels))
                    ((< pixels 0) (pixel-scroll-precision-scroll-up-page
                                   (- pixels))))))
        ((beginning-of-buffer end-of-buffer) nil)))))

(defun suderman/android-start-touch-momentum (event &rest _)
  "Fling after a completed touch-scroll EVENT released at speed."
  (when (and (eq (car event) 'touchscreen-end)
             (eq (caadr event) (car touch-screen-current-tool))
             (eq (nth 3 touch-screen-current-tool) 'scroll)
             (not (caddr event)))
    (let ((velocity (suderman/android-touch-velocity)))
      (setq suderman/android-touch-samples nil)
      (when (> (abs velocity) suderman/android-fling-min-velocity)
        (suderman/android-fling (cadr touch-screen-current-tool) velocity)))))

(defun suderman/android-setup-touch-scrolling ()
  "Configure Android touch input and flinging idempotently."
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
        echo-keystrokes 0)
  (setq-default make-cursor-line-fully-visible nil)
  (advice-add 'touch-screen-handle-scroll :before
              #'suderman/android-record-touch-scroll)
  (advice-add 'touch-screen-handle-touch :before
              #'suderman/android-start-touch-momentum))

(when (featurep 'android)
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
