;;; suderman-images.el --- Image viewing -*- lexical-binding: t; -*-

;;; Commentary:
;; Image mode: zoom, pan, and flip by touch, touchpad, mouse, and keys;
;; directory or gallery paging; animation; and clipboard copy.
;;
;; Emacs scales an image when it loads it, so each new zoom level costs a
;; full decode plus a scaling pass: on the Android APK about 0.2 to 1 s for
;; a camera photo.  While fingers move, zooming therefore draws a small
;; proxy without smoothing, and draws the real image once they stop.
;; Panning only moves an image slice, which costs nothing.  An overlay in
;; the image's window draws the slice, centred, over Image mode's own display
;; property, which its commands keep reading.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'image-mode)
(require 'exif)
(require 'suderman-paths)
(require 'suderman-files)
(require 'suderman-meow)
(eval-when-compile (require 'doc-view))

(defvar image-animate-loop)
(defvar meow-cursor-type-motion)
(defvar doom-modeline-buffer-file-name-style)
(defvar dired-movement-style)
(declare-function touch-screen-relative-xy "touch-screen" (posn window))
(declare-function doc-view-enlarge "doc-view" (factor))
(declare-function pdf-view-enlarge "pdf-view" (factor &optional window))
(declare-function pdf-view-redisplay "pdf-view" (&optional window))
(defvar doc-view-mode-map)
(defvar doc-view-image-width)
(defvar doc-view-resolution)
(defvar doc-view-continuous)
(defvar pdf-view-mode-map)
(declare-function doc-view-next-page "doc-view" (&optional arg))
(declare-function doc-view-previous-page "doc-view" (&optional arg))
(declare-function doc-view-goto-page "doc-view" (page))
(declare-function doc-view-last-page-number "doc-view")
(declare-function image-mode-window-get "image-mode" (prop &optional winprops))
(declare-function touch-screen-inhibit-drag "touch-screen")

;;;; Preferences

(defvar suderman/image-max-zoom 8.0
  "Largest zoom, relative to an image's fitted size.")

(defvar suderman/image-max-pixels 24000000
  "Largest zoomed image to hold in memory, in pixels.
Emacs keeps a zoomed image whole, about 8 bytes per pixel on Android.")

(defvar suderman/image-double-tap-zoom 2.5
  "Zoom a double tap or double click jumps to.")

(defvar suderman/image-proxy-size 1600
  "Longest edge, in pixels, of the rough copy drawn while zooming.")

(defvar suderman/image-proxy-min-bytes 1000000
  "Smallest image file worth a proxy; smaller files decode fast enough.")

(defvar suderman/image-proxy-limit 300
  "Number of proxies to keep in the cache.")

;;;; State

(defvar-local suderman/image-zoom 1.0
  "Zoom of this buffer's image relative to its fitted size.")

(defvar-local suderman/image-origin nil
  "Top-left corner of the window as (X . Y) pixels in the zoomed image.
Nil centres the image.")

(defvar-local suderman/image-shift 0
  "Pixels a sideways swipe has dragged the fitted image to the right.")

(defvar-local suderman/image-overlay nil
  "Overlay that draws this buffer's image in one window.")

(defvar-local suderman/image-shown nil
  "Zoomed image spec the overlay draws, as (KEY . SPEC), or nil at fit.")

(defvar-local suderman/image-geometry nil
  "Last drawn (X Y WIDTH HEIGHT): the window's corner in the image and its size.")

(defvar-local suderman/image-step-function nil
  "Function that visits the Nth next image, or nil for directory order.
A gallery sets it so that paging follows the gallery.")

(defvar-local suderman/image-quit-function nil
  "Function that leaves this image, or nil for `quit-window'.")

;;;; Drawing

(defun suderman/image--base ()
  "Return Image mode's own image spec in this buffer, or nil."
  (let ((spec (get-text-property (point-min) 'display)))
    (and (eq (car-safe spec) 'image) spec)))

(defun suderman/image--window ()
  "Return the window showing this buffer, preferring the selected one."
  (if (eq (window-buffer) (current-buffer))
      (selected-window)
    (get-buffer-window nil 'visible)))

(defun suderman/image--box (window)
  "Return WINDOW's text area as (WIDTH . HEIGHT) pixels."
  (let ((edges (window-inside-pixel-edges window)))
    (cons (- (nth 2 edges) (nth 0 edges))
          (- (nth 3 edges) (nth 1 edges)))))

(defun suderman/image--clamp (position size view)
  "Clamp POSITION of a VIEW-sized window over an image SIZE pixels long.
An image smaller than the window is centred, at a negative position."
  (if (<= size view)
      (- (/ (- view size) 2))
    (max 0 (min (round (or position 0)) (- size view)))))

(defun suderman/image--max-zoom (fit)
  "Return the largest zoom for an image whose fitted size is FIT."
  (max 1.0 (min suderman/image-max-zoom
                (sqrt (/ suderman/image-max-pixels
                         (float (max 1 (* (car fit) (cdr fit)))))))))

(defvar-local suderman/image--exif nil
  "(FILE . DEGREES): the rotation FILE's Exif orientation asks for.")

(defun suderman/image--exif-rotation (file)
  "Return the rotation that FILE's Exif orientation asks for, in degrees."
  (unless (equal file (car suderman/image--exif))
    (setq suderman/image--exif
          (cons file (or (ignore-errors (exif-orientation (exif-parse-file file)))
                         0))))
  (cdr suderman/image--exif))

(defun suderman/image--zoomed-spec (base fit zoom rough)
  "Return BASE resized to ZOOM times its FIT size.
ROUGH draws from a proxy without smoothing, for speed during a gesture."
  (let* ((props (copy-sequence (cdr base)))
         (file (plist-get props :file))
         (proxy (and rough file (suderman/image-proxy file)))
         (rotation (float (mod (- (or (plist-get props :rotation) 0)
                                  (if proxy (suderman/image--exif-rotation file) 0))
                               360)))
         ;; :width applies before rotation.
         (width (max 1 (round (* zoom (if (= 90 (mod (round rotation) 180))
                                         (cdr fit)
                                       (car fit)))))))
    (dolist (key '(:max-width :max-height :width :height :scale :rotation
                              :transform-smoothing))
      (cl-remf props key))
    (if proxy
        (create-image proxy nil nil :scale 1 :width width :rotation rotation
                      :transform-smoothing nil)
      `(image :scale 1 :width ,width :rotation ,rotation
              :transform-smoothing ,(not rough) ,@props))))

(defun suderman/image--spec (base fit rough)
  "Return the spec to draw BASE at the current zoom, given its FIT size.
Drop the zoomed image it replaces from the image cache."
  (if (= suderman/image-zoom 1.0)
      (progn (suderman/image--forget) base)
    (let ((key (list suderman/image-zoom rough fit)))
      (if (equal key (car suderman/image-shown))
          (cdr suderman/image-shown)
        (let ((spec (suderman/image--zoomed-spec base fit suderman/image-zoom rough)))
          (suderman/image--forget)
          (setq suderman/image-shown (cons key spec))
          spec)))))

(defun suderman/image--forget ()
  "Drop the zoomed image from the image cache."
  (when suderman/image-shown
    (image-flush (cdr suderman/image-shown) t)
    (setq suderman/image-shown nil)))

(defun suderman/image-redraw (&optional window rough)
  "Draw this buffer's image in WINDOW at its zoom and position.
ROUGH draws quickly from a proxy while a gesture is under way."
  (let ((window (or window (suderman/image--window)))
        (base (suderman/image--base)))
    (if (not (and base window (display-graphic-p (window-frame window))))
        (when (overlayp suderman/image-overlay)
          (delete-overlay suderman/image-overlay))
      (let* ((frame (window-frame window))
             (fit (image-display-size base t frame))
             (spec (suderman/image--spec base fit rough))
             (size (image-size spec t frame))
             (box (suderman/image--box window))
             (iw (round (car size)))
             (ih (round (cdr size)))
             (ww (car box))
             (wh (cdr box))
             (x (suderman/image--clamp (car suderman/image-origin) iw ww))
             (y (suderman/image--clamp (cdr suderman/image-origin) ih wh))
             (shown-x (- x suderman/image-shift))
             (x0 (max 0 shown-x))
             (y0 (max 0 y))
             (slice (list 'slice x0 y0
                          (max 1 (- (min iw (+ shown-x ww)) x0))
                          (max 1 (- (min ih (+ y wh)) y0))))
             (overlay (or (and (overlayp suderman/image-overlay)
                               (overlay-buffer suderman/image-overlay)
                               suderman/image-overlay)
                          (setq suderman/image-overlay
                                (make-overlay (point-min) (point-max))))))
        (when suderman/image-origin
          (setq suderman/image-origin (cons x y)))
        (setq suderman/image-geometry (list shown-x y iw ih))
        (move-overlay overlay (point-min) (point-max))
        (overlay-put overlay 'window window)
        ;; Default image ascent is 50%, so a stretch as tall as the window
        ;; with the same ascent centres the image vertically.
        (overlay-put overlay 'before-string
                     (propertize " " 'display
                                 `(space :width (,(max 0 (- shown-x)))
                                         :height (,wh) :ascent 50)
                                 'pointer 'arrow))
        (overlay-put overlay 'display (list slice spec))
        ;; Not the text I-beam: nothing here takes typing.
        (overlay-put overlay 'pointer 'arrow)
        (set-window-start window (point-min) t)
        (set-window-hscroll window 0)
        (set-window-vscroll window 0 t)))))

(defun suderman/image--anchor (point)
  "Return the image fraction (U . V) under window POINT (X . Y)."
  (pcase-let ((`(,x ,y ,iw ,ih) (or suderman/image-geometry '(0 0 1 1))))
    (cons (/ (+ x (car point)) (float (max 1 iw)))
          (/ (+ y (cdr point)) (float (max 1 ih))))))

(defun suderman/image--zoom-around (zoom anchor point &optional rough window)
  "Set ZOOM so image fraction ANCHOR (U . V) stays at window POINT (X . Y).
Draw ROUGH unless input is waiting.  Return the zoom used."
  (when-let* ((base (suderman/image--base))
              (window (or window (suderman/image--window))))
    (let* ((fit (image-display-size base t (window-frame window)))
           (zoom (max (if rough 0.85 1.0)
                      (min (suderman/image--max-zoom fit) zoom))))
      (setq suderman/image-zoom (if (< (abs (- zoom 1.0)) 0.01) 1.0 zoom)
            suderman/image-origin
            (cons (- (* (car anchor) (car fit) zoom) (car point))
                  (- (* (cdr anchor) (cdr fit) zoom) (cdr point))))
      (unless (and rough (input-pending-p))
        (suderman/image-redraw window rough))
      suderman/image-zoom)))

(defun suderman/image--centre (window)
  "Return the centre of WINDOW's text area as (X . Y)."
  (let ((box (suderman/image--box window)))
    (cons (/ (car box) 2) (/ (cdr box) 2))))

(defun suderman/image-zoom-by (factor &optional point rough)
  "Multiply the zoom by FACTOR around window POINT, by default the centre."
  (let* ((window (suderman/image--window))
         (point (or point (suderman/image--centre window))))
    (suderman/image--zoom-around (* suderman/image-zoom factor)
                                 (suderman/image--anchor point) point rough window)))

(defun suderman/image-settle (&optional window)
  "Draw the image sharply after a gesture, back at fit if it shrank below it."
  (when (< suderman/image-zoom 1.0)
    (setq suderman/image-zoom 1.0
          suderman/image-origin nil))
  (suderman/image-redraw window))

(defun suderman/image-reset (&rest _)
  "Show the image fitted and centred again."
  (when (derived-mode-p 'image-mode)
    (setq suderman/image-zoom 1.0
          suderman/image-origin nil
          suderman/image-shift 0)
    (suderman/image--forget)
    (suderman/image-redraw)))

(defun suderman/image--refresh (window)
  "Redraw the image in WINDOW after its size or buffer changed."
  (with-current-buffer (window-buffer window)
    (when (derived-mode-p 'image-mode)
      (suderman/image-redraw window))))

(defun suderman/image--cleanup ()
  "Remove the zoom overlay and drop the zoomed image."
  (suderman/image--forget)
  (when (overlayp suderman/image-overlay)
    (delete-overlay suderman/image-overlay))
  (setq suderman/image-overlay nil))

;;;; Proxies

(defvar suderman/image--worker nil
  "Shell that runs image jobs in the background.")

(defun suderman/image-run-shell (command)
  "Run shell COMMAND in the background and forget it.
Starting a process takes about 0.35 s on the Android APK, which also never
notices one exit, so one long-lived shell runs every job.  Callers watch
for the files COMMAND writes instead of waiting for it."
  (let ((line (format "( %s ) >/dev/null 2>&1 &\n" command)))
    (unless (and (processp suderman/image--worker)
                 (ignore-errors
                   (process-send-string suderman/image--worker line)
                   t))
      (setq suderman/image--worker
            (make-process :name "image-worker" :noquery t :connection-type 'pipe
                          :command (list (or (executable-find "sh") shell-file-name))))
      (process-send-string suderman/image--worker line))))

(defvar suderman/image--proxy-job nil
  "(PROXY . START) of the proxy being made, or nil.")

(defun suderman/image--proxy-name (file)
  "Return the cache file for FILE's proxy."
  (let ((attributes (file-attributes file)))
    (expand-file-name
     (concat (md5 (format "%s %s %s" file
                          (file-attribute-size attributes)
                          (file-attribute-modification-time attributes)))
             ".jpg")
     (expand-file-name "image-proxy" suderman/cache-dir))))

(defun suderman/image-proxy (file)
  "Return a proxy of image FILE, or start making one and return nil.
Small files, animations, vector images, and remote files get none."
  (when (and (not (file-remote-p file))
             (string-match-p "\\.\\(?:jpe?g\\|png\\|webp\\|tiff?\\|bmp\\)\\'"
                             (downcase file))
             (> (or (file-attribute-size (file-attributes file)) 0)
                suderman/image-proxy-min-bytes))
    (let ((proxy (suderman/image--proxy-name file)))
      (if (file-exists-p proxy)
          proxy
        (suderman/image--make-proxy file proxy)
        nil))))

(defun suderman/image--make-proxy (file proxy)
  "Start writing FILE's PROXY in the background, one at a time."
  (when (and suderman/image--proxy-job
             (or (file-exists-p (car suderman/image--proxy-job))
                 (> (- (float-time) (cdr suderman/image--proxy-job)) 30)))
    (setq suderman/image--proxy-job nil))
  (when-let* (((not suderman/image--proxy-job))
              (program (or (executable-find "magick")
                           (executable-find "convert"))))
    (let ((partial (concat proxy ".part"))
          (size suderman/image-proxy-size))
      (make-directory (file-name-directory proxy) t)
      (suderman/image--prune-proxies)
      (setq suderman/image--proxy-job (cons proxy (float-time)))
      (suderman/image-run-shell
       (format "%s && mv -f %s %s"
               (mapconcat #'shell-quote-argument
                          (list program
                                "-define" (format "jpeg:size=%dx%d" (* 2 size) (* 2 size))
                                (concat file "[0]")
                                "-auto-orient"
                                "-thumbnail" (format "%dx%d>" size size)
                                "-quality" "85"
                                (concat "jpeg:" partial))
                          " ")
               (shell-quote-argument partial)
               (shell-quote-argument proxy))))))

(defun suderman/image--prune-proxies ()
  "Delete the oldest proxies beyond `suderman/image-proxy-limit'."
  (let* ((directory (expand-file-name "image-proxy" suderman/cache-dir))
         (files (and (file-directory-p directory)
                     (directory-files-and-attributes directory t "\\.jpg\\(?:\\.part\\)?\\'" t))))
    (when (> (length files) suderman/image-proxy-limit)
      (dolist (entry (nthcdr suderman/image-proxy-limit
                             (sort files
                                   (lambda (a b)
                                     (time-less-p
                                      (file-attribute-modification-time (cdr b))
                                      (file-attribute-modification-time (cdr a)))))))
        (ignore-errors (delete-file (car entry)))))))

;;;; Paging

(defun suderman/image-next-file (n)
  "Visit the Nth next image, in gallery order or cyclic directory order."
  (interactive "p")
  (if suderman/image-step-function
      (funcall suderman/image-step-function n)
    (let ((dired-movement-style 'cycle-files))
      (image-next-file n))))

(defun suderman/image-previous-file (n)
  "Visit the Nth previous image, in gallery order or cyclic directory order."
  (interactive "p")
  (suderman/image-next-file (- n)))

(defun suderman/image-quit ()
  "Leave the image, back to the gallery it came from if any."
  (interactive)
  (if suderman/image-quit-function
      (funcall suderman/image-quit-function)
    (quit-window)))

;;;; Keys and mouse

(defun suderman/image-zoom-in ()
  "Zoom in around the centre of the window."
  (interactive)
  (suderman/image-zoom-by 1.25))

(defun suderman/image-zoom-out ()
  "Zoom out around the centre of the window."
  (interactive)
  (suderman/image-zoom-by 0.8))

(defun suderman/image--pan (dx dy &optional window)
  "Move the view DX and DY pixels across the zoomed image.
Return non-nil if it moved."
  (let ((before (car suderman/image-geometry))
        (before-y (cadr suderman/image-geometry)))
    (pcase-let ((`(,x ,y . ,_) suderman/image-geometry))
      (setq suderman/image-origin (cons (+ x dx) (+ y dy))))
    (suderman/image-redraw window)
    (not (and (equal before (car suderman/image-geometry))
              (equal before-y (cadr suderman/image-geometry))))))

(defun suderman/image--pan-step (dx dy)
  "Pan by fractions DX and DY of the window."
  (let ((box (suderman/image--box (suderman/image--window))))
    (suderman/image--pan (round (* dx (car box))) (round (* dy (cdr box))))))

(defun suderman/image-left ()
  "Pan left when zoomed, otherwise show the previous image."
  (interactive)
  (if (> suderman/image-zoom 1.0)
      (suderman/image--pan-step -0.2 0)
    (suderman/image-previous-file 1)))

(defun suderman/image-right ()
  "Pan right when zoomed, otherwise show the next image."
  (interactive)
  (if (> suderman/image-zoom 1.0)
      (suderman/image--pan-step 0.2 0)
    (suderman/image-next-file 1)))

(defun suderman/image-up ()
  "Pan up when zoomed."
  (interactive)
  (suderman/image--pan-step 0 -0.2))

(defun suderman/image-down ()
  "Pan down when zoomed."
  (interactive)
  (suderman/image--pan-step 0 0.2))

(defun suderman/image-toggle-zoom (point &optional window)
  "Zoom in on window POINT (X . Y), or back to fit when zoomed."
  (if (> suderman/image-zoom 1.0)
      (progn (setq suderman/image-zoom 1.0
                   suderman/image-origin nil)
             (suderman/image-redraw window))
    (suderman/image--zoom-around suderman/image-double-tap-zoom
                                 (suderman/image--anchor point) point nil window)))

(defun suderman/image-mouse-toggle-zoom (event)
  "Zoom in where EVENT clicked, or back to fit when zoomed."
  (interactive "e")
  (let ((posn (event-start event)))
    (with-selected-window (posn-window posn)
      (suderman/image-toggle-zoom (posn-x-y posn)))))

(defun suderman/image-mouse-drag (event)
  "Drag a zoomed image with the mouse from EVENT.
A press that does not move hands its click back, so a double click on a
zoomed image still reaches `suderman/image-mouse-toggle-zoom'."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn))
         (last (posn-x-y posn)))
    (when (and (windowp window)
               (> (buffer-local-value 'suderman/image-zoom (window-buffer window)) 1.0))
      (with-selected-window window
        (let (next moved)
          (track-mouse
            (while (mouse-movement-p (setq next (read-event)))
              (let ((posn (event-start next)))
                (when (eq (posn-window posn) window)
                  (let ((xy (posn-x-y posn)))
                    (unless (equal xy last)
                      (setq moved t)
                      (suderman/image--pan (- (car last) (car xy))
                                           (- (cdr last) (cdr xy)) window)
                      (setq last xy)
                      (redisplay)))))))
          (unless moved
            (push next unread-command-events)))))))

(defvar suderman/image--wheel-flip nil
  "(TOTAL . TIME) of touchpad scrolling toward a flip at fit.
TOTAL is `flipped' once this scroll has flipped.")

(defun suderman/image--wheel-flip (type delta)
  "Flip to the next or previous image for wheel TYPE at fit.
A mouse flips once per notch.  A touchpad, whose events carry pixel
DELTA, flips once per scroll after 120 pixels."
  (let ((forward (memq type '(wheel-down wheel-right))))
    (if (not (consp delta))
        (suderman/image-next-file (if forward 1 -1))
      (let* ((now (float-time))
             (state suderman/image--wheel-flip)
             (total (if (and state (< (- now (cdr state)) 0.3)) (car state) 0)))
        (if (eq total 'flipped)
            (setq suderman/image--wheel-flip (cons 'flipped now))
          (setq total (+ total (* (if forward 1 -1)
                                  (abs (if (memq type '(wheel-left wheel-right))
                                           (car delta)
                                         (cdr delta))))))
          (if (< (abs total) 120)
              (setq suderman/image--wheel-flip (cons total now))
            (setq suderman/image--wheel-flip (cons 'flipped now))
            (suderman/image-next-file (if (> total 0) 1 -1))))))))

(defun suderman/image-wheel (event)
  "Pan a zoomed image with wheel EVENT, or flip images at fit.
Control zooms at the pointer."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn))
         (type (event-basic-type event))
         (delta (nth 4 event))
         (clicks (or (nth 2 event) 1)))
    (when (windowp window)
      (with-selected-window window
        (cond
         ((memq 'control (event-modifiers event))
          (suderman/image-zoom-by (if (eq type 'wheel-up) 1.15 (/ 1 1.15))
                                  (posn-x-y posn) t)
          (suderman/image--settle-later window))
         ((<= suderman/image-zoom 1.0)
          (suderman/image--wheel-flip type delta))
         (t
          (let ((pixels (if (consp delta)
                            (max (abs (car delta)) (abs (cdr delta)))
                          (* 80 clicks))))
            (pcase type
              ('wheel-down (suderman/image--pan 0 pixels))
              ('wheel-up (suderman/image--pan 0 (- pixels)))
              ('wheel-right (suderman/image--pan pixels 0))
              ('wheel-left (suderman/image--pan (- pixels) 0))))))))))

(defvar suderman/image--settle-timer nil
  "Timer that draws the image sharply once a gesture pauses.")

(defun suderman/image--settle-later (window &optional delay)
  "Draw WINDOW's image sharply after DELAY idle seconds."
  (when (timerp suderman/image--settle-timer)
    (cancel-timer suderman/image--settle-timer))
  (setq suderman/image--settle-timer
        (run-with-idle-timer
         (or delay 0.2) nil
         (lambda ()
           (when (window-live-p window)
             (with-current-buffer (window-buffer window)
               (when (derived-mode-p 'image-mode)
                 (suderman/image-settle window))))))))

(defvar suderman/image--pinch-start nil
  "(ZOOM ANCHOR X Y) when the current touchpad pinch began.")

(defun suderman/image-pinch (event)
  "Zoom with touchpad pinch EVENT around the pointer."
  (interactive "e")
  (pcase-let* ((`(,_ ,posn ,dx ,dy ,scale ,angle) event)
               (window (posn-window posn)))
    (when (windowp window)
      (with-selected-window window
        (when (or (null suderman/image--pinch-start)
                  (and (zerop dx) (zerop dy) (zerop angle)))
          (let ((xy (posn-x-y posn)))
            (setq suderman/image--pinch-start
                  (list suderman/image-zoom (suderman/image--anchor xy)
                        (car xy) (cdr xy)))))
        (pcase-let ((`(,zoom ,anchor ,x ,y) suderman/image--pinch-start))
          (setf (nth 2 suderman/image--pinch-start) (+ x dx)
                (nth 3 suderman/image--pinch-start) (+ y dy))
          (suderman/image--zoom-around (* zoom scale) anchor
                                       (cons (+ x dx) (+ y dy)) t window))
        (suderman/image--settle-later window)))))

;;;; Touch

(defvar suderman/image--touch nil
  "The touch gesture on an image, a plist.
:window is the image's window, :points the fingers as ((ID X . Y) ...),
:mode nil until they move, then `pan', `swipe', `still', or `pinch'.
:start is (X Y TIME) of the first finger, :pinch is (DISTANCE ZOOM
ANCHOR) when the second finger landed, and :trail holds recent (TIME X
. Y) of a moving finger, newest first.")

(defvar suderman/image--last-tap nil
  "(TIME X . Y) of the last tap on an image, to spot a double tap.")

(defconst suderman/image--slop 16
  "Pixels a finger moves before a touch stops being a tap.")

(defun suderman/image--distance (a b)
  "Return the distance between points A and B."
  (max 1.0 (sqrt (+ (expt (- (car a) (car b)) 2)
                    (expt (- (cdr a) (cdr b)) 2)))))

(defun suderman/image--midpoint (a b)
  "Return the midpoint of A and B."
  (cons (/ (+ (car a) (car b)) 2.0) (/ (+ (cdr a) (cdr b)) 2.0)))

(defun suderman/image--velocity (trail)
  "Return the (VX . VY) pixels per second of the last 0.1 s of TRAIL."
  (let* ((newest (car trail))
         (oldest (car (last (seq-take-while
                             (lambda (sample) (<= (- (car newest) (car sample)) 100))
                             trail))))
         (dt (and oldest (/ (- (car newest) (car oldest)) 1000.0))))
    (if (and dt (> dt 0))
        (cons (/ (- (cadr newest) (cadr oldest)) dt)
              (/ (- (cddr newest) (cddr oldest)) dt))
      (cons 0 0))))

(defun suderman/image-touch (event)
  "Zoom, pan, flip, or double-tap an image with touch EVENT."
  (interactive "e")
  (require 'touch-screen)
  (pcase (car event)
    ('touchscreen-begin (suderman/image--touch-begin (cadr event)))
    ('touchscreen-update (suderman/image--touch-update (cadr event)))
    ('touchscreen-end (suderman/image--touch-end (cadr event) (caddr event)))))

(defun suderman/image--touch-begin (point)
  "Start tracking finger POINT, an (ID . POSN)."
  (let* ((posn (cdr point))
         (window (posn-window posn)))
    (when (windowp window)
      (when (timerp suderman/image--settle-timer)
        (cancel-timer suderman/image--settle-timer))
      ;; A second finger joins the gesture; anything else starts a new one,
      ;; even if an earlier finger's end event went missing.
      (unless (and (= 1 (length (plist-get suderman/image--touch :points)))
                   (eq window (plist-get suderman/image--touch :window)))
        (select-window window)
        (let ((xy (posn-x-y posn)))
          (setq suderman/image--touch
                (list :window window :points nil :mode nil
                      :start (list (car xy) (cdr xy) (posn-timestamp posn))))))
      (let* ((touch suderman/image--touch)
             (points (cons (cons (car point)
                                 (touch-screen-relative-xy
                                  posn (plist-get touch :window)))
                           (plist-get touch :points))))
        (setq suderman/image--touch (plist-put touch :points points))
        (when (= (length points) 2)
          (let ((a (cdar points))
                (b (cdadr points)))
            (with-selected-window (plist-get touch :window)
              (setq suderman/image--touch
                    (plist-put (plist-put suderman/image--touch :mode 'pinch)
                               :pinch (list (suderman/image--distance a b)
                                            suderman/image-zoom
                                            (suderman/image--anchor
                                             (suderman/image--midpoint a b))))))))))))

(defun suderman/image--touch-update (moved)
  "Follow MOVED fingers, a list of (ID . POSN)."
  (let* ((touch suderman/image--touch)
         (window (plist-get touch :window))
         (points (plist-get touch :points))
         delta)
    (when (and (window-live-p window) points)
      (dolist (finger moved)
        (when-let* ((cell (assq (car finger) points)))
          (let ((xy (touch-screen-relative-xy (cdr finger) window)))
            (when (eq cell (car (last points)))
              ;; The first finger down drives a pan or a swipe.
              (setq delta (list (posn-timestamp (cdr finger))
                                (- (car xy) (cadr cell))
                                (- (cdr xy) (cddr cell))
                                xy)))
            (setcdr cell xy))))
      (with-selected-window window
        (if (eq (plist-get touch :mode) 'pinch)
            (when (>= (length points) 2)
              (pcase-let ((`(,distance ,zoom ,anchor) (plist-get touch :pinch))
                          (a (cdar points))
                          (b (cdadr points)))
                (suderman/image--zoom-around
                 (* zoom (/ (suderman/image--distance a b) distance))
                 anchor (suderman/image--midpoint a b) t window)))
          (when delta
            (pcase-let ((`(,time ,dx ,dy ,xy) delta)
                        (`(,x0 ,y0 . ,_) (plist-get touch :start)))
              (let ((mode (plist-get touch :mode))
                    (tx (- (car xy) x0))
                    (ty (- (cdr xy) y0)))
                (unless (or mode (< (max (abs tx) (abs ty)) suderman/image--slop))
                  (setq mode (cond ((> suderman/image-zoom 1.0) 'pan)
                                   ((> (abs tx) (abs ty)) 'swipe)
                                   (t 'still))))
                (setq touch (plist-put touch :mode mode))
                (setq touch (plist-put touch :trail
                                       (seq-take (cons (cons time xy)
                                                       (plist-get touch :trail))
                                                 20)))
                (pcase mode
                  ('pan (suderman/image--pan (- dx) (- dy) window))
                  ('swipe (setq suderman/image-shift tx)
                          (suderman/image-redraw window)))
                (setq suderman/image--touch touch)))))))))

(defun suderman/image--touch-end (point canceled)
  "Finish finger POINT, an (ID . POSN); CANCELED means the system took it."
  (let* ((touch suderman/image--touch)
         (window (plist-get touch :window))
         (points (assq-delete-all (car point) (plist-get touch :points)))
         (mode (plist-get touch :mode)))
    (setq suderman/image--touch (plist-put touch :points points))
    (when (window-live-p window)
      (with-selected-window window
        (cond
         (canceled
          (setq suderman/image-shift 0)
          (suderman/image-settle window))
         ((eq mode 'pinch)
          (if points
              ;; Keep panning with the finger still down.
              (setq suderman/image--touch
                    (plist-put (plist-put suderman/image--touch :mode 'pan)
                               :trail nil))
            (suderman/image-settle window)))
         (points nil)
         ((eq mode 'pan)
          (let ((velocity (suderman/image--velocity (plist-get touch :trail))))
            (suderman/image--glide window (- (car velocity)) (- (cdr velocity))))
          ;; A pinch that ended one finger at a time is still rough.
          (when (cadr (car suderman/image-shown))
            (suderman/image-settle window)))
         ((eq mode 'swipe)
          (suderman/image--finish-swipe
           window (car (suderman/image--velocity (plist-get touch :trail)))))
         ((null mode)
          (suderman/image--tap window (cdr point))))))))

(defun suderman/image--tap (window posn)
  "Handle a tap at POSN in WINDOW, zooming on a double tap."
  (let ((time (posn-timestamp posn))
        (xy (touch-screen-relative-xy posn window))
        (last suderman/image--last-tap))
    (if (and last
             (< (- time (car last)) 350)
             (< (suderman/image--distance xy (cdr last)) 60))
        (progn (setq suderman/image--last-tap nil)
               (suderman/image-toggle-zoom xy window))
      (setq suderman/image--last-tap (cons time xy)))))

(defun suderman/image--glide (window vx vy)
  "Keep panning WINDOW at VX and VY pixels per second, slowing down.
Any input stops it, as a touch-screen fling does."
  (let ((last (float-time))
        (carry-x 0.0)
        (carry-y 0.0))
    (while (and (> (sqrt (+ (* vx vx) (* vy vy))) 30)
                (sit-for 0.001))
      (let* ((now (float-time))
             (dt (- now last))
             (decay (exp (- (/ dt 0.35))))
             (tx (+ carry-x (* vx dt)))
             (ty (+ carry-y (* vy dt)))
             (px (truncate tx))
             (py (truncate ty)))
        (setq last now
              carry-x (- tx px)
              carry-y (- ty py)
              vx (* vx decay)
              vy (* vy decay))
        (unless (and (zerop px) (zerop py))
          (unless (suderman/image--pan px py window)
            (setq vx 0 vy 0)))))))

(defun suderman/image--slide (window target)
  "Slide the fitted image in WINDOW sideways to TARGET pixels."
  (let ((start suderman/image-shift)
        (began (float-time)))
    (while (and (/= suderman/image-shift target)
                (sit-for 0.001))
      (let ((progress (min 1.0 (/ (- (float-time) began) 0.15))))
        (setq suderman/image-shift
              (round (+ start (* progress (- target start)))))
        (suderman/image-redraw window)))))

(defun suderman/image--finish-swipe (window velocity)
  "Flip to the next or previous image, or slide back, after a swipe.
VELOCITY is the finger's sideways speed when it lifted."
  (let* ((width (car (suderman/image--box window)))
         (shift suderman/image-shift)
         (flip (or (> (abs shift) (* 0.25 width))
                   (and (> (abs shift) 40) (> (abs velocity) 800)
                        (eq (> shift 0) (> velocity 0))))))
    (if (not flip)
        (suderman/image--slide window 0)
      (suderman/image--slide window (if (> shift 0) width (- width)))
      (setq suderman/image-shift 0)
      (condition-case err
          (if (> shift 0)
              (suderman/image-previous-file 1)
            (suderman/image-next-file 1))
        (error (suderman/image-redraw window)
               (message "%s" (error-message-string err)))))))

;;;; Image mode

(defun suderman/image-rotate (&optional degrees)
  "Rotate the image DEGREES clockwise, by default 90."
  (interactive)
  (image-transform-set-rotation (+ image-transform-rotation (or degrees 90))))

(defun suderman/image-rotate-counterclockwise ()
  "Rotate the image 90 degrees counterclockwise."
  (interactive)
  (suderman/image-rotate -90))

(defun suderman/image-own-display (get)
  "Return Image mode's own image from GET, not the zoom overlay's slice."
  (or (and (derived-mode-p 'image-mode) (suderman/image--base))
      (funcall get)))

(defun suderman/image-copy-to-clipboard ()
  "Copy the current image file to the Wayland clipboard."
  (interactive)
  (unless (and buffer-file-name
               (not (file-remote-p buffer-file-name))
               (file-readable-p buffer-file-name))
    (user-error "This image is not a readable local file"))
  (require 'mailcap)
  (let ((mime-type (mailcap-file-name-to-mime-type buffer-file-name)))
    (unless (and mime-type (string-prefix-p "image/" mime-type))
      (user-error "Cannot determine an image MIME type for this file"))
    (unless (executable-find "wl-copy")
      (user-error "wl-copy is not installed"))
    (unless (eq 0
                (if (equal mime-type "image/gif")
                    (progn
                      (require 'url-util)
                      (call-process
                       "wl-copy" nil nil nil "--type" "text/uri-list"
                       (url-encode-url (concat "file://" buffer-file-name))))
                  (call-process "wl-copy" buffer-file-name nil nil
                                "--type" mime-type)))
      (user-error "wl-copy failed"))
    (message "Copied %s to the clipboard"
             (file-name-nondirectory buffer-file-name))))

(defun suderman/image-mode-setup ()
  "Prepare Image mode for Meow Motion state, zooming, and animation."
  (when (derived-mode-p 'image-mode)
    (goto-char (point-min))
    (when-let* ((image (image-get-display-property))
                ((image-multi-frame-p image))
                ((not (image-animate-timer image))))
      (image-toggle-animation))
    (when (and (bound-and-true-p meow-global-mode)
               (not (and (bound-and-true-p meow-mode)
                         (bound-and-true-p meow-motion-mode)
                         (eq meow--current-state 'motion))))
      (meow-mode 1))
    ;; Meow's Motion cursor would frame the whole image.  Doom Modeline's
    ;; usual style looks for a project, which lists the whole directory:
    ;; 1.2 s per photo in a phone's camera folder.
    (setq-local meow-cursor-type-motion nil
                cursor-type nil
                doom-modeline-buffer-file-name-style 'file-name)
    (suderman/image-view-mode 1)
    ;; The drawn row ends at the window edge; no truncation arrow.
    (setq-local fringe-indicator-alist
                (cons '(truncation nil nil) fringe-indicator-alist))
    (add-hook 'window-buffer-change-functions #'suderman/image--refresh nil t)
    (add-hook 'window-size-change-functions #'suderman/image--refresh nil t)
    (add-hook 'change-major-mode-hook #'suderman/image--cleanup nil t)
    (add-hook 'kill-buffer-hook #'suderman/image--cleanup nil t)
    (when (and buffer-file-name (display-graphic-p))
      (suderman/image-proxy buffer-file-name))
    (suderman/image-redraw)))

(defun suderman/image-metadata-graphic-frame (arguments)
  "Measure images on a GUI frame while a terminal frame is selected.
Animation timers call `image-metadata' with ARGUMENTS lacking a frame, which
fails and kills a GUI animation whenever a daemon's terminal frame is in use."
  (if (or (cadr arguments) (display-graphic-p))
      arguments
    (list (car arguments) (seq-find #'display-graphic-p (frame-list)))))

(advice-add 'image-metadata :filter-args #'suderman/image-metadata-graphic-frame)
;; Image mode rebuilds its image after a revert, rotation, or refit.
(advice-add 'image-toggle-display-image :after #'suderman/image-reset)
(advice-add 'image-toggle-display-text :after #'suderman/image-reset)
(advice-add 'image-get-display-property :around #'suderman/image-own-display)

(setq image-animate-loop t)

(dolist (binding '(("," . suderman/ibuffer-toggle)
                   ("." . suderman/dirvish)
                   ("c" . suderman/image-copy-to-clipboard)
                   ("n" . suderman/image-next-file)
                   ("p" . suderman/image-previous-file)
                   ("r" . suderman/image-rotate)
                   ("R" . suderman/image-rotate-counterclockwise)
                   ("0" . image-transform-reset-to-initial)))
  (keymap-set image-mode-map (car binding) (cdr binding)))

;; DocView's map inherits Image mode's, so gestures live in a minor mode
;; that only real image buffers enable.
(defvar-keymap suderman/image-view-mode-map
  :doc "Zoom, pan, and paging keys in Image mode."
  "q" #'suderman/image-quit
  "=" #'suderman/image-zoom-in
  "+" #'suderman/image-zoom-in
  "-" #'suderman/image-zoom-out
  "<left>" #'suderman/image-left
  "<right>" #'suderman/image-right
  "<up>" #'suderman/image-up
  "<down>" #'suderman/image-down
  "<remap> <meow-left>" #'suderman/image-left
  "<remap> <meow-right>" #'suderman/image-right
  "<remap> <meow-prev>" #'suderman/image-up
  "<remap> <meow-next>" #'suderman/image-down
  "<down-mouse-1>" #'suderman/image-mouse-drag
  "<double-mouse-1>" #'suderman/image-mouse-toggle-zoom
  "<wheel-up>" #'suderman/image-wheel
  "<wheel-down>" #'suderman/image-wheel
  "<wheel-left>" #'suderman/image-wheel
  "<wheel-right>" #'suderman/image-wheel
  "C-<wheel-up>" #'suderman/image-wheel
  "C-<wheel-down>" #'suderman/image-wheel
  "<pinch>" #'suderman/image-pinch
  ;; Raw touch events bypass touch-screen.el's scrolling and text-scale
  ;; pinch, so gestures reach the image directly.
  "<touchscreen-begin>" #'suderman/image-touch
  "<touchscreen-update>" #'suderman/image-touch
  "<touchscreen-end>" #'suderman/image-touch)

(define-minor-mode suderman/image-view-mode
  "Zoom, pan, and flip through images by touch, touchpad, mouse, and keys."
  :keymap suderman/image-view-mode-map)

;;;; Documents

;; DocView and PDF Tools show one page image at a time, scrolled with the
;; window's vscroll and hscroll.  Touch drives those directly, as
;; touch-screen.el's line-based scrolling cannot move through a single tall
;; image.  A zoom first draws the page roughly at the new size, then once
;; the gesture ends asks the viewer to render it.

(defvar suderman/document--touch nil
  "The touch gesture on a document page, a plist like `suderman/image--touch'.
:pinch is (DISTANCE WIDTH ANCHOR SPEC) when the second finger landed.")

(defvar suderman/document--live nil
  "Rough page spec drawn during a zoom gesture, or nil.")

(defun suderman/document--geometry ()
  "Return (WIDTH HEIGHT WINDOW-WIDTH WINDOW-HEIGHT LEFT) of the shown page.
LEFT is the page's offset when it is narrower than the window."
  (when-let* ((image (overlay-get (image-mode-window-get 'overlay) 'display))
              ((eq (car-safe image) 'image)))
    (let ((size (image-size image t))
          (box (suderman/image--box (selected-window))))
      (list (round (car size)) (round (cdr size)) (car box) (cdr box)
            (max 0 (/ (- (car box) (round (car size))) 2))))))

(defun suderman/document--anchor (point)
  "Return the page fraction (U . V) under window POINT (X . Y)."
  (pcase-let ((`(,iw ,ih ,_ ,_ ,left) (suderman/document--geometry)))
    (cons (/ (+ (car point) (- left) (* (window-hscroll) (frame-char-width)))
             (float (max 1 iw)))
          (/ (+ (cdr point) (window-vscroll nil t)) (float (max 1 ih))))))

(defun suderman/document--scroll-to (anchor point)
  "Scroll so page fraction ANCHOR (U . V) sits at window POINT (X . Y)."
  (pcase-let ((`(,iw ,ih ,ww ,wh ,left) (suderman/document--geometry)))
    (image-set-window-vscroll
     (max 0 (min (max 0 (- ih wh)) (round (- (* (cdr anchor) ih) (cdr point))))))
    (image-set-window-hscroll
     (if (<= iw ww)
         0
       (max 0 (min (ceiling (- iw ww) (frame-char-width))
                   (round (- (+ (* (car anchor) iw) left) (car point))
                          (frame-char-width))))))))

(defun suderman/document--edges ()
  "Return which edges of the page show: (TOP . BOTTOM)."
  (pcase-let ((`(,_ ,ih ,_ ,wh ,_) (suderman/document--geometry)))
    (cons (<= (window-vscroll nil t) 0)
          (>= (window-vscroll nil t) (max 0 (- (or ih 0) (or wh 0)))))))

(defun suderman/document--pan (dx dy &optional turn)
  "Scroll the page DX and DY pixels; return non-nil if anything moved.
With TURN, a drag that began at an edge of the page and goes a quarter of
the window past it turns the page."
  (pcase-let* ((`(,iw ,ih ,ww ,wh ,_) (suderman/document--geometry))
               (vscroll (window-vscroll nil t))
               (target (+ vscroll dy))
               (limit (max 0 (- ih wh)))
               (page (doc-view-current-page))
               (hscroll (window-hscroll))
               (edges (plist-get suderman/document--touch :edges))
               (moved nil))
    (image-set-window-vscroll (max 0 (min limit target)))
    (setq moved (/= vscroll (window-vscroll nil t)))
    (when turn
      (let ((over (+ (or (plist-get suderman/document--touch :overscroll) 0)
                     (cond ((and (> target limit) (cdr edges)) (- target limit))
                           ((and (< target 0) (car edges)) target)
                           (t 0))))
            (half (* 0.25 wh)))
        (cond
         ((and (>= over half) (< page (doc-view-last-page-number)))
          (doc-view-next-page)
          (image-set-window-vscroll 0)
          (setq over 0 edges nil moved 'turned))
         ((and (<= over (- half)) (> page 1))
          (doc-view-previous-page)
          (pcase-let ((`(,_ ,ih ,_ ,wh ,_) (suderman/document--geometry)))
            (image-set-window-vscroll (max 0 (- ih wh))))
          (setq over 0 edges nil moved 'turned)))
        (setq suderman/document--touch
              (plist-put (plist-put suderman/document--touch :overscroll over)
                         :edges edges))
        ;; A turn ends the drag, so the new page shows from its edge.
        (when (eq moved 'turned)
          (setq suderman/document--touch
                (plist-put suderman/document--touch :mode 'turned)))))
    (when (> iw ww)
      (let* ((pixels (+ (plist-get suderman/document--touch :hpixels) dx))
             (columns (truncate pixels (frame-char-width))))
        (setq suderman/document--touch
              (plist-put suderman/document--touch :hpixels
                         (- pixels (* columns (frame-char-width)))))
        (image-set-window-hscroll
         (max 0 (min (ceiling (- iw ww) (frame-char-width)) (+ hscroll columns))))
        (setq moved (or moved (/= hscroll (window-hscroll))))))
    moved))

(defun suderman/document--clamp (factor width)
  "Limit FACTOR so a page WIDTH pixels wide stays within 0.5 to 4 windows."
  (let ((window-width (car (suderman/image--box (selected-window)))))
    (max (/ (* 0.5 window-width) width)
         (min (/ (* 4.0 window-width) width) factor))))

(defun suderman/document--resize (factor anchor point)
  "Render the page FACTOR times larger, keeping fraction ANCHOR at POINT."
  (let ((factor (suderman/document--clamp
                 factor (max 1 (car (suderman/document--geometry))))))
    (cond ((> (abs (- factor 1.0)) 0.02)
           (if (derived-mode-p 'pdf-view-mode)
               (pdf-view-enlarge factor)
             (doc-view-enlarge factor)))
          ((derived-mode-p 'pdf-view-mode) (pdf-view-redisplay))
          (t (doc-view-goto-page (doc-view-current-page))))
    (suderman/document--scroll-to anchor point)))

(defun suderman/document--forget-live ()
  "Drop the rough page drawn during a zoom from the image cache."
  (when suderman/document--live
    (image-flush suderman/document--live t)
    (setq suderman/document--live nil)))

(defun suderman/document--draw-live (spec width ratio anchor point)
  "Draw page SPEC, WIDTH pixels wide as drawn, roughly RATIO times larger.
Keep page fraction ANCHOR at window POINT."
  (let ((props (copy-sequence (cdr spec))))
    (dolist (key '(:width :height :max-width :max-height :scale
                          :transform-smoothing))
      (cl-remf props key))
    (let* ((window-width (car (suderman/image--box (selected-window))))
           (new (max 1 (round (* width (suderman/document--clamp ratio width)))))
           (live `(image :width ,new :scale 1 :transform-smoothing nil ,@props))
           (overlay (image-mode-window-get 'overlay)))
      (suderman/document--forget-live)
      (setq suderman/document--live live)
      (overlay-put overlay 'display live)
      (overlay-put overlay 'before-string
                   (when (> window-width new)
                     (propertize " " 'display
                                 `(space :align-to (+ center (-0.5 . (,new)))))))
      (suderman/document--scroll-to anchor point))))

(defun suderman/document--settle (spec width anchor point)
  "Render the page sharply at the live zoom of SPEC, drawn WIDTH pixels wide.
Put SPEC back first: PDF Tools measures the page from what is drawn."
  (when-let* ((live suderman/document--live))
    (let ((new (plist-get (cdr live) :width)))
      (suderman/document--forget-live)
      (overlay-put (image-mode-window-get 'overlay) 'display spec)
      (suderman/document--resize (/ new (float width)) anchor point))))

;;;;; Touchpad and wheel

(defvar suderman/document--pinch nil
  "(WINDOW ANCHOR POINT SPEC WIDTH) of the touchpad pinch under way.")

(defvar suderman/document--pinch-timer nil
  "Timer that renders the page sharply once a touchpad pinch pauses.")

(defun suderman/document-pinch (event)
  "Zoom the page around the pointer with touchpad pinch EVENT."
  (interactive "e")
  (pcase-let* ((`(,_ ,posn ,dx ,dy ,scale ,angle) event)
               (window (posn-window posn)))
    (when (windowp window)
      (with-selected-window window
        (when (or (not (eq (car suderman/document--pinch) window))
                  (and (zerop dx) (zerop dy) (zerop angle)))
          (setq suderman/document--pinch
                (when-let* ((spec (overlay-get (image-mode-window-get 'overlay)
                                               'display))
                            ((eq (car-safe spec) 'image))
                            (point (posn-x-y posn)))
                  (list window (suderman/document--anchor point) point spec
                        (car (suderman/document--geometry))))))
        (pcase-let ((`(,_ ,anchor ,point ,spec ,width) suderman/document--pinch))
          (when spec
            (unless (input-pending-p)
              (suderman/document--draw-live spec width scale anchor point))
            (when (timerp suderman/document--pinch-timer)
              (cancel-timer suderman/document--pinch-timer))
            (setq suderman/document--pinch-timer
                  (run-with-idle-timer
                   0.25 nil
                   (lambda ()
                     (when (window-live-p window)
                       (with-selected-window window
                         (setq suderman/document--pinch nil)
                         (suderman/document--settle spec width anchor point))))))))))))

(defun suderman/document-wheel-zoom (event)
  "Zoom the page around the pointer by one step of Control-wheel EVENT."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn)))
    (when (windowp window)
      (with-selected-window window
        (let ((point (posn-x-y posn)))
          (suderman/document--resize
           (if (eq (event-basic-type event) 'wheel-up) 1.15 (/ 1 1.15))
           (suderman/document--anchor point) point))))))

(defun suderman/document-touch (event)
  "Scroll, zoom, or double-tap a document page with touch EVENT."
  (interactive "e")
  (require 'touch-screen)
  (pcase (car event)
    ('touchscreen-begin (suderman/document--touch-begin (cadr event)))
    ('touchscreen-update (suderman/document--touch-update (cadr event)))
    ('touchscreen-end (suderman/document--touch-end (cadr event) (caddr event)))))

(defun suderman/document--touch-begin (point)
  "Start tracking finger POINT, an (ID . POSN)."
  (let* ((posn (cdr point))
         (window (posn-window posn)))
    (when (windowp window)
      (unless (and (= 1 (length (plist-get suderman/document--touch :points)))
                   (eq window (plist-get suderman/document--touch :window)))
        (select-window window)
        (let ((xy (posn-x-y posn)))
          (setq suderman/document--touch
                (list :window window :points nil :mode nil :hpixels 0
                      :edges (with-selected-window window
                               (suderman/document--edges))
                      :start (list (car xy) (cdr xy) (posn-timestamp posn))))))
      (let ((points (cons (cons (car point) (touch-screen-relative-xy posn window))
                          (plist-get suderman/document--touch :points))))
        (setq suderman/document--touch
              (plist-put suderman/document--touch :points points))
        (when (= (length points) 2)
          (with-selected-window window
            (when-let* ((geometry (suderman/document--geometry))
                        (spec (overlay-get (image-mode-window-get 'overlay) 'display)))
              (let ((middle (suderman/image--midpoint (cdar points) (cdadr points))))
                (setq suderman/document--touch
                      (plist-put (plist-put suderman/document--touch :mode 'pinch)
                                 :pinch (list (suderman/image--distance
                                               (cdar points) (cdadr points))
                                              (car geometry)
                                              (suderman/document--anchor middle)
                                              spec)))))))))))

(defun suderman/document--touch-update (moved)
  "Follow MOVED fingers, a list of (ID . POSN)."
  (let* ((touch suderman/document--touch)
         (window (plist-get touch :window))
         (points (plist-get touch :points))
         delta)
    (when (and (window-live-p window) points)
      (dolist (finger moved)
        (when-let* ((cell (assq (car finger) points)))
          (let ((xy (touch-screen-relative-xy (cdr finger) window)))
            (when (eq cell (car (last points)))
              (setq delta (list (posn-timestamp (cdr finger))
                                (- (car xy) (cadr cell))
                                (- (cdr xy) (cddr cell))
                                xy)))
            (setcdr cell xy))))
      (with-selected-window window
        (if (eq (plist-get touch :mode) 'pinch)
            (when (and (>= (length points) 2) (plist-get touch :pinch)
                       (not (input-pending-p)))
              (let ((a (cdar points)) (b (cdadr points)))
                (pcase-let ((`(,distance ,width ,anchor ,spec) (plist-get touch :pinch)))
                  (suderman/document--draw-live
                   spec width (/ (suderman/image--distance a b) distance)
                   anchor (suderman/image--midpoint a b)))))
          (when delta
            (pcase-let ((`(,time ,dx ,dy ,xy) delta)
                        (`(,x0 ,y0 . ,_) (plist-get touch :start)))
              (let ((mode (plist-get touch :mode)))
                (unless (or mode (< (max (abs (- (car xy) x0)) (abs (- (cdr xy) y0)))
                                    suderman/image--slop))
                  (setq mode 'pan))
                (setq touch (plist-put touch :mode mode))
                (setq touch (plist-put touch :trail
                                       (seq-take (cons (cons time xy)
                                                       (plist-get touch :trail))
                                                 20)))
                (setq suderman/document--touch touch)
                (when (eq mode 'pan)
                  (suderman/document--pan (- dx) (- dy) t))))))))))

(defun suderman/document--touch-end (point canceled)
  "Finish finger POINT, an (ID . POSN); CANCELED means the system took it."
  (let* ((touch suderman/document--touch)
         (window (plist-get touch :window))
         (points (assq-delete-all (car point) (plist-get touch :points)))
         (mode (plist-get touch :mode)))
    (setq suderman/document--touch (plist-put touch :points points))
    (when (window-live-p window)
      (with-selected-window window
        (cond
         ((eq mode 'pinch)
          (when-let* ((pinch (plist-get touch :pinch)))
            ;; Render sharply at the size the fingers chose, once.
            (let* ((middle (if points
                               (cdar points)
                             (touch-screen-relative-xy (cdr point) window))))
              (setq suderman/document--touch
                    (plist-put suderman/document--touch :pinch nil))
              (suderman/document--settle (nth 3 pinch) (nth 1 pinch)
                                         (suderman/document--anchor middle)
                                         middle)))
          (setq suderman/document--touch
                (plist-put (plist-put suderman/document--touch :mode (and points 'pan))
                           :trail nil)))
         ((or points canceled) nil)
         ((eq mode 'pan)
          (let ((velocity (suderman/image--velocity (plist-get touch :trail))))
            (suderman/document--glide (- (car velocity)) (- (cdr velocity)))))
         ((null mode)
          (suderman/document--tap (cdr point) window)))))))

(defun suderman/document--glide (vx vy)
  "Keep scrolling at VX and VY pixels per second, slowing down."
  (let ((last (float-time))
        (carry-x 0.0)
        (carry-y 0.0))
    (while (and (> (sqrt (+ (* vx vx) (* vy vy))) 30)
                (sit-for 0.001))
      (let* ((now (float-time))
             (dt (- now last))
             (decay (exp (- (/ dt 0.35))))
             (tx (+ carry-x (* vx dt)))
             (ty (+ carry-y (* vy dt)))
             (px (truncate tx))
             (py (truncate ty)))
        (setq last now
              carry-x (- tx px)
              carry-y (- ty py)
              vx (* vx decay)
              vy (* vy decay))
        (unless (and (zerop px) (zerop py))
          (unless (suderman/document--pan px py)
            (setq vx 0 vy 0)))))))

(defun suderman/document--tap (posn window)
  "Zoom in on a double tap at POSN in WINDOW, or back to the window width."
  (let ((time (posn-timestamp posn))
        (xy (touch-screen-relative-xy posn window))
        (last suderman/image--last-tap))
    (if (not (and last
                  (< (- time (car last)) 350)
                  (< (suderman/image--distance xy (cdr last)) 60)))
        (setq suderman/image--last-tap (cons time xy))
      (setq suderman/image--last-tap nil)
      (when-let* ((geometry (suderman/document--geometry)))
        (let ((anchor (suderman/document--anchor xy))
              (width (car geometry))
              (window-width (nth 2 geometry)))
          (suderman/document--resize
           (if (> width (* 1.05 window-width))
               (/ window-width (float width))
             2.0)
           anchor xy))))))

(defvar-keymap suderman/document-view-mode-map
  :doc "Touch gestures on DocView pages."
  "<touchscreen-begin>" #'suderman/document-touch
  "<touchscreen-update>" #'suderman/document-touch
  "<touchscreen-end>" #'suderman/document-touch)

(define-minor-mode suderman/document-view-mode
  "Scroll, zoom, and double-tap DocView pages by touch."
  :keymap suderman/document-view-mode-map)

(defun suderman/doc-view-setup ()
  "Fit pages to the window width and take touch gestures."
  ;; DocView passes no :scale, so a high-density screen would multiply
  ;; every page by `image-scaling-factor' (about 2.8 on the phone).
  (setq-local image-scaling-factor 1.0
              doc-view-image-width
              (window-body-width (or (get-buffer-window) (selected-window)) t))
  (suderman/document-view-mode 1))

(with-eval-after-load 'doc-view
  ;; Android renders PDFs with Termux's Ghostscript; render sharp enough
  ;; to zoom, and keep pages flowing under a swipe.
  (setq doc-view-resolution 200
        doc-view-continuous t)
  (keymap-set doc-view-mode-map "<pinch>" #'suderman/document-pinch)
  (keymap-set doc-view-mode-map "C-<wheel-up>" #'suderman/document-wheel-zoom)
  (keymap-set doc-view-mode-map "C-<wheel-down>" #'suderman/document-wheel-zoom)
  (add-hook 'doc-view-mode-hook #'suderman/doc-view-setup))

(with-eval-after-load 'pdf-view
  (keymap-set pdf-view-mode-map "<pinch>" #'suderman/document-pinch)
  (keymap-set pdf-view-mode-map "C-<wheel-up>" #'suderman/document-wheel-zoom)
  (keymap-set pdf-view-mode-map "C-<wheel-down>" #'suderman/document-wheel-zoom))

(add-hook 'image-mode-hook #'suderman/image-mode-setup)
(add-hook 'find-file-hook #'suderman/image-mode-setup t)

(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'image-mode)
      (suderman/image-mode-setup))))

(provide 'suderman-images)
;;; suderman-images.el ends here
