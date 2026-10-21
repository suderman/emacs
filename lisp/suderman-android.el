;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android-only input: volume keys for the software keyboard, pinch zoom,
;; touch scrolling, the Emacs server, and Termux executables.  The toolbar
;; shared with desktop lives in `suderman-toolbar'.

;;; Code:

(require 'subr-x)

(defvar global-text-scale-adjust-limits)
(defvar meow-keypad-describe-delay)
(defvar touch-screen-enable-hscroll)
(defvar touch-screen-extend-selection)
(defvar touch-screen-delay)
(defvar touch-screen-precision-scroll)
(defvar touch-screen-word-select)

(declare-function server-running-p "server" (&optional name))
(declare-function suderman/sync-fixed-pitch-height "suderman-appearance")

(defconst suderman/android-termux-bin
  "/data/data/com.termux/files/usr/bin")

(defun suderman/android-show-keyboard ()
  "Show the Android software keyboard for the selected frame."
  (interactive)
  (frame-toggle-on-screen-keyboard (selected-frame) nil))

(defun suderman/android-hide-keyboard ()
  "Hide the Android software keyboard for the selected frame."
  (interactive)
  (frame-toggle-on-screen-keyboard (selected-frame) t))

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

(defvar suderman/android-blank-tap nil
  "Time and window of the last tap below a listing's final line, or nil.")

(defun suderman/android-below-last-line-p (posn)
  "Return non-nil when POSN lies below the last line of its buffer's text."
  (when-let* ((window (posn-window posn))
              ((windowp window))
              (pos (posn-point posn)))
    (with-current-buffer (window-buffer window)
      (> pos (save-excursion
               (goto-char (point-max))
               (skip-chars-backward " \t\n")
               (line-end-position))))))

(defun suderman/mouse-set-point-or-toggle-keyboard (event)
  "Set point at EVENT, or toggle the Android keyboard on a double tap.
Listings such as Dired and IBuffer are read-only, so a tap never shows the
keyboard.  A double tap in the blank space below the last entry toggles it.
A tap elsewhere hides it, as Emacs does after other taps in read-only text."
  (interactive "e")
  (let ((posn (event-start event)))
    (if (not (and (featurep 'android)
                  (suderman/android-below-last-line-p posn)))
        (progn
          (setq suderman/android-blank-tap nil)
          (mouse-set-point event)
          (when (featurep 'android)
            (suderman/android-hide-keyboard)))
      (let ((previous suderman/android-blank-tap))
        (setq suderman/android-blank-tap (cons (float-time) (posn-window posn)))
        (when (and previous
                   (eq (cdr previous) (posn-window posn))
                   (< (- (float-time) (car previous))
                      (/ (if (numberp double-click-time) double-click-time 500)
                         1000.0)))
          (setq suderman/android-blank-tap nil)
          (if (suderman/android-keyboard-visible-p (selected-frame))
              (suderman/android-hide-keyboard)
            (suderman/android-show-keyboard)))))))

(defvar-local suderman/tap-selected-line nil
  "Start of the row selected when the last command finished.
A tap moves point before its command runs, so point cannot tell.")

(defun suderman/remember-tap-selected-line ()
  "Record the selected row for `suderman/tap-on-selected-row-p'."
  (setq suderman/tap-selected-line (line-beginning-position)))

(defun suderman/track-tap-selection ()
  "Let taps in this Android list buffer select a row before opening it."
  (when (featurep 'android)
    (suderman/remember-tap-selected-line)
    (add-hook 'post-command-hook #'suderman/remember-tap-selected-line nil t)))

(defun suderman/tap-on-selected-row-p (event)
  "Move point to EVENT and return non-nil when its row was already selected."
  (mouse-set-point event)
  (eql (line-beginning-position) suderman/tap-selected-line))

(defun suderman/android-volume-up ()
  "Show the software keyboard, or with it showing, open the Meow keypad."
  (interactive)
  (if (not (suderman/android-keyboard-visible-p (selected-frame)))
      (suderman/android-show-keyboard)
    (let ((meow-keypad-describe-delay 0))
      (meow-keypad))))

;; The open Meow keypad reads keys itself, so decode its volume keys.
(defun suderman/android-keypad-volume-up (_prompt)
  "Show the hidden software keyboard without leaving the Meow keypad."
  (when (bound-and-true-p meow-keypad-mode)
    (unless (suderman/android-keyboard-visible-p (selected-frame))
      (suderman/android-show-keyboard))
    []))

(defun suderman/android-keypad-volume-down (_prompt)
  "Quit the Meow keypad and keep the software keyboard."
  (when (bound-and-true-p meow-keypad-mode)
    [suderman-keypad-quit]))

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
IBuffer's recent list, which stay vertical-only."
  (if suderman/sideways-scroll
      (car suderman/sideways-scroll)
    (and truncate-lines
         (if (derived-mode-p 'ibuffer-mode)
             (bound-and-true-p suderman/ibuffer-grouped)
           (not (derived-mode-p 'dired-mode
                                'dirvish-directory-view-mode
                                'dirvish-special-preview-mode))))))

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
  (global-set-key [volume-up] #'suderman/android-volume-up)
  (global-set-key [volume-down] #'suderman/android-hide-keyboard)
  (define-key input-decode-map [volume-up] #'suderman/android-keypad-volume-up)
  (define-key input-decode-map [volume-down]
              #'suderman/android-keypad-volume-down))

(provide 'suderman-android)
;;; suderman-android.el ends here
