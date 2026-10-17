;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android-only input: volume-key modifiers, pinch zoom, touch scrolling, the
;; software keyboard, the Emacs server, and Termux executables.  The toolbar
;; shared with desktop lives in `suderman-toolbar'.

;;; Code:

(require 'subr-x)

(defvar global-text-scale-adjust-limits)
(defvar touch-screen-enable-hscroll)
(defvar touch-screen-extend-selection)
(defvar touch-screen-delay)
(defvar touch-screen-precision-scroll)
(defvar touch-screen-word-select)

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

(defvar-local suderman/sideways-scroll nil
  "How `suderman/toggle-sideways-scroll' overrode this buffer, or nil.
The value is (ON VISUAL-LINE TRUNCATE): whether sideways scrolling is
on, and the `visual-line-mode' and `truncate-lines' to restore.")

(defun suderman/sideways-scroll-p ()
  "Return non-nil when touch may scroll the current buffer sideways.
By default that is where lines are truncated, except Dired, Dirvish, and
IBuffer, which stay vertical-only."
  (if suderman/sideways-scroll
      (car suderman/sideways-scroll)
    (and truncate-lines
         (not (derived-mode-p 'dired-mode 'ibuffer-mode
                              'dirvish-directory-view-mode
                              'dirvish-special-preview-mode)))))

(defun suderman/toggle-sideways-scroll ()
  "Toggle wrapping and sideways scrolling in the current buffer.
The first toggle reverses the buffer's default; the next restores it."
  (interactive)
  (if-let* ((saved suderman/sideways-scroll))
      (progn
        (setq suderman/sideways-scroll nil)
        (visual-line-mode (if (nth 1 saved) 1 -1))
        (setq truncate-lines (nth 2 saved)))
    (let ((on (not (suderman/sideways-scroll-p))))
      (setq suderman/sideways-scroll (list on visual-line-mode truncate-lines))
      (when on (visual-line-mode -1))
      (setq truncate-lines on)))
  (unless (suderman/sideways-scroll-p)
    (kill-local-variable 'auto-hscroll-mode)
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-hscroll window 0)))
  (message "Sideways scrolling %s" (if (suderman/sideways-scroll-p) "on" "off")))

(defun suderman/android-touch-hscroll (scroll dx dy)
  "Call SCROLL with DX and DY, swiping sideways where `suderman/sideways-scroll-p'.
Those buffers stop following point sideways, so a vertical swipe keeps
the horizontal position, and scroll both ways at once: touch-screen.el
otherwise ignores sideways movement once a swipe has scrolled vertically.
Hide the beginning or end of buffer message SCROLL shows on each drag."
  (let ((touch-screen-enable-hscroll (suderman/sideways-scroll-p))
        (inhibit-message t)
        (message-log-max nil))
    (when touch-screen-enable-hscroll
      (setq-local auto-hscroll-mode nil)
      ;; A nonzero count of sideways steps lifts the lock.
      (let ((hscrolled (nthcdr 8 touch-screen-current-tool)))
        (when (and hscrolled (memq (car hscrolled) '(nil 0)))
          (setcar hscrolled 1))))
    (funcall scroll dx dy)))

(defun suderman/android-touch-lift-point (&rest _)
  "Move point up from a bottom line that hangs below the window.
`pixel-scroll-precision-scroll-up-page' leaves point on such a line, as
on a large Org heading, and redisplay then recenters the window."
  (when-let* ((pos (pos-visible-in-window-p (point) nil t))
              ((> (+ (cadr pos) (line-pixel-height))
                  (window-body-height nil t))))
    (vertical-motion -1)))

(defun suderman/android-setup-touch-scrolling ()
  "Configure Android touch input idempotently.
The `fling' package continues swipes; see `suderman-windows'."
  (require 'pixel-scroll)
  (require 'touch-screen)
  ;; Swipe sideways only where lines are truncated, such as Org Agenda, or
  ;; where `SPC t t' turned it on; it would defeat visual wrapping elsewhere.
  ;; Keep vertical swipes pixel-precise, and let touch adjust either end of a
  ;; word selection.  Shorten long press and hide drag events in the echo area.
  (advice-add 'touch-screen-handle-scroll :around
              #'suderman/android-touch-hscroll)
  (advice-add 'pixel-scroll-precision-scroll-up-page :after
              #'suderman/android-touch-lift-point)
  (setq touch-screen-enable-hscroll nil
        touch-screen-precision-scroll t
        touch-screen-word-select t
        touch-screen-extend-selection t
        touch-screen-delay 0.5
        echo-keystrokes 0)
  (setq-default make-cursor-line-fully-visible nil))

(defun suderman/android-mark-main-frame ()
  "Mark the startup frame, which owns the launcher's Android window."
  (set-frame-parameter nil 'suderman/android-main t))

(defun suderman/android-delete-frame (delete &optional frame force)
  "Call DELETE on FRAME and FORCE, but keep the launcher's Android window.
Once the startup frame is gone, the launcher icon cannot reopen Emacs.
Instead that frame takes another frame's windows, and the other closes."
  (let* ((frame (window-normalize-frame frame))
         (other (and (frame-parameter frame 'suderman/android-main)
                     (seq-find (lambda (f)
                                 (and (not (eq f frame))
                                      (not (frame-parent f))
                                      (eq (frame-terminal f) (frame-terminal frame))))
                               (frame-list)))))
    (if (not other)
        (funcall delete frame force)
      (window-state-put (window-state-get (frame-root-window other) t)
                        (frame-root-window frame) 'safe)
      (funcall delete other force)
      (select-frame-set-input-focus frame))))

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
  (add-hook 'window-setup-hook #'suderman/android-mark-main-frame)
  (advice-add 'delete-frame :around #'suderman/android-delete-frame)
  (define-key function-key-map [volume-down] #'suderman/android-volume-control)
  (define-key function-key-map [volume-up] #'suderman/android-volume-meta))

(provide 'suderman-android)
;;; suderman-android.el ends here
