;;; suderman-gallery.el --- Image gallery -*- lexical-binding: t; -*-

;;; Commentary:
;; A thumbnail grid of a directory's images, sized to the window.  Rows are
;; text, and each thumbnail loads only when redisplay first shows its row,
;; so a camera folder with thousands of photos opens at once and scrolls by
;; touch like any buffer.  Thumbnails share the freedesktop cache with
;; Image-Dired and desktop file managers.  Images open in Image mode, where
;; paging and swiping follow the gallery's order and `q' comes back.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'image-dired)
(require 'image-file)
(require 'jit-lock)
(require 'suderman-images)

(declare-function suderman/theme-blend "suderman-appearance" (face alpha))
(declare-function touch-screen-inhibit-drag "touch-screen")

;;;; Preferences

(defvar suderman/gallery-cell-width 260
  "Approximate thumbnail width; the window decides the number of columns.")

(defvar suderman/gallery-gap 8
  "Pixels between thumbnails.")

(setq image-dired-thumbnail-storage 'standard-large)


;;;; State

(defvar-local suderman/gallery-files []
  "Image files in gallery order.")

(defvar-local suderman/gallery-cells []
  "Buffer position of each file's thumbnail.")

(defvar-local suderman/gallery-cell nil
  "Thumbnail cell size in pixels.")

(defvar-local suderman/gallery-columns nil
  "Number of columns chosen with `+' and `-', or nil to fit the window.")

(defvar-local suderman/gallery-column-count 1
  "Number of columns in the current layout.")

(defvar-local suderman/gallery-layout-width nil
  "Window width the grid was laid out for.")

(defvar-local suderman/gallery-scan nil
  "Function returning the gallery's files in listing order.")

(defvar-local suderman/gallery-newest-first nil
  "Non-nil to show the newest images first.")

(defvar-local suderman/gallery-marks nil
  "Marked files, as a hash table.")

(defvar-local suderman/gallery-index 0
  "Index of the image last opened from the gallery.")

(defvar-local suderman/gallery-return nil
  "Window configuration to restore when the gallery closes.")

(defvar-local suderman/gallery-current-overlay nil
  "Overlay that frames the selected thumbnail.")

;;;; Files

(defun suderman/gallery--image-p (file)
  "Return non-nil if FILE is an image Emacs can show."
  (and (string-match-p (image-file-name-regexp) file)
       (file-regular-p file)))

(defun suderman/gallery--dired-files (buffer)
  "Return the top-level images listed in Dired BUFFER, in its order."
  (with-current-buffer buffer
    (let ((directory (file-name-as-directory (expand-file-name default-directory)))
          files)
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (when-let* ((file (dired-get-filename nil t))
                      ((equal (file-name-directory file) directory))
                      ((suderman/gallery--image-p file)))
            (push file files))
          (forward-line 1)))
      (nreverse files))))

(defun suderman/gallery--directory-files (directory)
  "Return the images in DIRECTORY, by name."
  (seq-filter #'file-regular-p
              (directory-files directory t (image-file-name-regexp))))

(defun suderman/gallery--order (files)
  "Return FILES in the gallery's current order."
  (if (not suderman/gallery-newest-first)
      files
    (mapcar #'car
            (sort (mapcar (lambda (file)
                            (cons file (file-attribute-modification-time
                                        (file-attributes file))))
                          files)
                  (lambda (a b) (time-less-p (cdr b) (cdr a)))))))

;;;; Layout

(defun suderman/gallery--tile-face ()
  "Return the face of an empty tile, a little off the background."
  (list :background (or (ignore-errors (suderman/theme-blend 'shadow 0.12))
                        "gray20")))

(defun suderman/gallery--show-selected ()
  "Scroll so the selected thumbnail's row is the first one shown."
  (when-let* ((window (get-buffer-window nil t)))
    (set-window-start window (line-beginning-position) t)))

(defun suderman/gallery--layout (&optional index)
  "Lay out the grid for the gallery's window, selecting INDEX."
  (let* ((window (or (get-buffer-window nil t) (selected-window)))
         (width (- (nth 2 (window-inside-pixel-edges window))
                   (nth 0 (window-inside-pixel-edges window))))
         (gap suderman/gallery-gap)
         (columns (max 1 (or suderman/gallery-columns
                             (round (- width gap)
                                    (+ suderman/gallery-cell-width gap)))))
         (cell (max 32 (/ (- width (* (1+ columns) gap)) columns)))
         (left (max 0 (/ (- width (* columns cell) (* (1- columns) gap)) 2)))
         (files suderman/gallery-files)
         (cells (make-vector (length files) nil))
         (index (or index (suderman/gallery--index) 0))
         (tile (suderman/gallery--tile-face))
         (inhibit-read-only t))
    ;; Thumbnails are cached at 256 or 512 pixels; use the smallest that fills a tile.
    (setq-local image-dired-thumbnail-storage
                (if (> cell 256) 'standard-x-large 'standard-large))
    (setq suderman/gallery-cell cell
          suderman/gallery-column-count columns
          suderman/gallery-layout-width width)
    (with-silent-modifications
      (erase-buffer)
      (dotimes (i (length files))
        (when (zerop (% i columns))
          (unless (zerop i) (insert (propertize "\n" 'pointer 'arrow)))
          ;; A gap taller than a tile, centred on the baseline like the
          ;; tiles, so every row has the same height and spacing.
          (insert (propertize " " 'display
                              `(space :width (,left) :height (,(+ cell gap))
                                      :ascent 50)
                              'pointer 'arrow)))
        (unless (zerop (% i columns))
          (insert (propertize " " 'display `(space :width (,gap)) 'pointer 'arrow)))
        (aset cells i (point))
        (insert (propertize " "
                            'suderman/gallery-index i
                            'display `(space :width (,cell) :height (,cell) :ascent 50)
                            'face tile
                            'pointer 'hand
                            'help-echo (abbreviate-file-name (aref files i)))))
      (insert (propertize "\n" 'pointer 'arrow)))
    (setq suderman/gallery-cells cells)
    (when (> (length cells) 0)
      (goto-char (aref cells (min index (1- (length cells))))))
    (suderman/gallery--show-marks)
    (suderman/gallery--select)))

(defun suderman/gallery--refit (window)
  "Lay out again when WINDOW's width changed."
  (with-current-buffer (window-buffer window)
    (when (and (derived-mode-p 'suderman/gallery-mode)
               (not (eql suderman/gallery-layout-width
                         (- (nth 2 (window-inside-pixel-edges window))
                            (nth 0 (window-inside-pixel-edges window))))))
      (suderman/gallery--layout))))

;;;; Thumbnails

(defvar suderman/gallery--queue nil
  "Thumbnails to make, most recently requested first, as (BUFFER INDEX).")

(defvar suderman/gallery--batches nil
  "Thumbnails being made, a list per process.
Each entry is (THUMBNAIL BUFFER INDEX FILE START).")

(defvar suderman/gallery--timer nil
  "Timer that watches for finished thumbnails.")

(defconst suderman/gallery--queue-limit 48
  "Most thumbnails to keep waiting; older requests have scrolled away.")

(defconst suderman/gallery--batch-size 6
  "Thumbnails one process makes.")

(defun suderman/gallery--thumbnail (file &optional storage)
  "Return FILE's current cached thumbnail, or nil.
STORAGE overrides `image-dired-thumbnail-storage'."
  (let ((thumbnail (let ((image-dired-thumbnail-storage
                          (or storage image-dired-thumbnail-storage)))
                     (image-dired-thumb-name file))))
    (and (file-exists-p thumbnail)
         (not (file-newer-than-file-p file thumbnail))
         thumbnail)))

(defun suderman/gallery--fontify (start end)
  "Load the thumbnails between START and END as redisplay reaches them."
  (let ((pos start))
    (while (and pos (< pos end))
      (when-let* ((index (get-text-property pos 'suderman/gallery-index))
                  ((not (get-text-property pos 'suderman/gallery-loading))))
        (if-let* ((thumbnail (suderman/gallery--thumbnail
                              (aref suderman/gallery-files index))))
            (suderman/gallery--place index thumbnail)
          ;; Show the other cached size until this one is made.
          (when-let* ((other (suderman/gallery--thumbnail
                              (aref suderman/gallery-files index)
                              (if (eq image-dired-thumbnail-storage 'standard-large)
                                  'standard-x-large
                                'standard-large))))
            (suderman/gallery--place index other))
          (put-text-property pos (1+ pos) 'suderman/gallery-loading t)
          (push (list (current-buffer) index) suderman/gallery--queue)
          (suderman/gallery--trim-queue)
          (run-at-time 0 nil #'suderman/gallery--run)))
      (setq pos (next-single-property-change pos 'suderman/gallery-index nil end)))))

(defun suderman/gallery--place (index thumbnail)
  "Show THUMBNAIL in cell INDEX, scaled to cover its square tile and cropped."
  (let* ((pos (aref suderman/gallery-cells index))
         (cell suderman/gallery-cell)
         (probe (create-image thumbnail nil nil :scale 1))
         (size (image-size probe t))
         (width (max 1 (round (car size))))
         (height (max 1 (round (cdr size))))
         (factor (/ cell (float (min width height))))
         (scaled-width (max cell (round (* width factor))))
         (scaled-height (max cell (round (* height factor))))
         (spec (create-image thumbnail nil nil :scale 1
                             :width scaled-width :height scaled-height)))
    (image-flush probe)
    (with-silent-modifications
      (add-text-properties
       pos (1+ pos)
       `(display ((slice ,(/ (- scaled-width cell) 2) ,(/ (- scaled-height cell) 2)
                         ,cell ,cell)
                  ,spec)
                 suderman/gallery-loading t)))))

(defun suderman/gallery--forget (buffer index)
  "Let cell INDEX of gallery BUFFER ask for its thumbnail again when shown."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (< index (length suderman/gallery-cells))
        (let ((pos (aref suderman/gallery-cells index)))
          (with-silent-modifications
            (remove-text-properties pos (1+ pos)
                                    '(suderman/gallery-loading nil fontified nil))))))))

(defun suderman/gallery--trim-queue ()
  "Forget the oldest requests beyond `suderman/gallery--queue-limit'.
Their rows have most likely scrolled away; redisplay asks again if they return."
  (when-let* ((tail (nthcdr (1- suderman/gallery--queue-limit) suderman/gallery--queue)))
    (pcase-dolist (`(,buffer ,index) (cdr tail))
      (suderman/gallery--forget buffer index))
    (setcdr tail nil)))

(defun suderman/gallery--converter-options (size)
  "Return Image-Dired's thumbnail options for SIZE, decoding faster.
Camera photos often keep their rotation in Exif only, so apply it too."
  (let ((options (copy-sequence image-dired-cmd-create-standard-thumbnail-options)))
    (unless (member "-auto-orient" options)
      (when-let* ((input (member "%f[0]" options)))
        (setcdr input (cons "-auto-orient" (cdr input)))))
    (if (equal (car options) "convert")
        ;; GraphicsMagick's subcommand must come first.
        options
      (append (list "-define" (format "jpeg:size=%dx%d" (* 2 size) (* 2 size)))
              options))))

(defun suderman/gallery--command (file thumbnail)
  "Return a shell command that writes FILE's THUMBNAIL whole or not at all."
  (let* ((partial (concat thumbnail ".part"))
         (size (if (eq image-dired-thumbnail-storage 'standard-x-large) 512 256))
         (spec `((?s . ,size) (?w . ,size) (?h . ,size)
                 (?m . ,(format-time-string
                         "%s" (file-attribute-modification-time (file-attributes file))))
                 (?f . ,file) (?u . ,file) (?t . ,partial))))
    (format "%s && mv -f %s %s"
            (mapconcat #'shell-quote-argument
                       (cons (if (executable-find "magick")
                                 "magick"
                               image-dired-cmd-create-thumbnail-program)
                             (mapcar (lambda (option) (format-spec option spec))
                                     (suderman/gallery--converter-options size)))
                       " ")
            (shell-quote-argument partial)
            (shell-quote-argument thumbnail))))

(defun suderman/gallery--run ()
  "Start making queued thumbnails, newest request first, a batch per process."
  (let ((limit (min 3 (max 1 (/ (num-processors) 2)))))
    (while (and suderman/gallery--queue
                (< (length suderman/gallery--batches) limit))
      (let (batch commands)
        (while (and suderman/gallery--queue
                    (< (length batch) suderman/gallery--batch-size))
          (pcase-let ((`(,buffer ,index) (pop suderman/gallery--queue)))
            (when (buffer-live-p buffer)
              (with-current-buffer buffer
                (when (< index (length suderman/gallery-files))
                  (let* ((file (aref suderman/gallery-files index))
                         (thumbnail (image-dired-thumb-name file)))
                    (make-directory (file-name-directory thumbnail) t)
                    (push (list thumbnail buffer index file (float-time)) batch)
                    (push (suderman/gallery--command file thumbnail) commands)))))))
        (when batch
          ;; The thumbnail standard wants files only their owner can read.
          (suderman/image-run-shell
           (concat "umask 077; " (string-join (nreverse commands) "; ")))
          (push batch suderman/gallery--batches)))))
  (when (and suderman/gallery--batches (not (timerp suderman/gallery--timer)))
    (setq suderman/gallery--timer
          (run-with-timer 0.3 0.3 #'suderman/gallery--poll))))

(defun suderman/gallery--poll ()
  "Show thumbnails that have appeared, and start more."
  (let ((now (float-time)))
    (setq suderman/gallery--batches
          (delq nil
                (mapcar
                 (lambda (batch)
                   (seq-remove
                    (pcase-lambda (`(,thumbnail ,buffer ,index ,file ,start))
                      (cond
                       ((file-exists-p thumbnail)
                        (when (buffer-live-p buffer)
                          (with-current-buffer buffer
                            (when (and (< index (length suderman/gallery-files))
                                       (equal file (aref suderman/gallery-files index)))
                              (suderman/gallery--place index thumbnail))))
                        t)
                       ;; A file the converter cannot read never appears.
                       ((> (- now start) 30) t)))
                    batch))
                 suderman/gallery--batches))))
  (suderman/gallery--run)
  (unless suderman/gallery--batches
    (cancel-timer suderman/gallery--timer)
    (setq suderman/gallery--timer nil)))

;;;; Selection and marks

(defun suderman/gallery--index (&optional pos)
  "Return the image index at POS, or the nearest one before it."
  (let ((pos (or pos (point))))
    (or (get-text-property pos 'suderman/gallery-index)
        (when-let* ((next (next-single-property-change
                           pos 'suderman/gallery-index nil (line-end-position))))
          (get-text-property next 'suderman/gallery-index))
        (when-let* ((previous (previous-single-property-change
                               pos 'suderman/gallery-index)))
          (get-text-property (max (point-min) (1- previous)) 'suderman/gallery-index)))))

(defun suderman/gallery--select ()
  "Snap point to a thumbnail and frame it; a marked one gets a thicker frame."
  (when-let* ((index (suderman/gallery--index)))
    (goto-char (aref suderman/gallery-cells index))
    (unless (overlayp suderman/gallery-current-overlay)
      (setq suderman/gallery-current-overlay (make-overlay 1 1))
      (overlay-put suderman/gallery-current-overlay 'priority 10))
    (let ((color (or (face-foreground 'cursor nil t)
                     (face-background 'cursor nil t)
                     "gray50"))
          (width (if (gethash (aref suderman/gallery-files index)
                              suderman/gallery-marks)
                     -10 -4)))
      (overlay-put suderman/gallery-current-overlay 'face
                   `(:box (:line-width (,width . ,width) :color ,color))))
    (move-overlay suderman/gallery-current-overlay (point) (1+ (point)))))

(defun suderman/gallery--show-marks ()
  "Frame every marked thumbnail."
  (remove-overlays (point-min) (point-max) 'suderman/gallery-mark t)
  (let ((color (or (face-foreground 'success nil t) "gray70")))
    (dotimes (index (length suderman/gallery-files))
      (when (gethash (aref suderman/gallery-files index) suderman/gallery-marks)
        (let* ((pos (aref suderman/gallery-cells index))
               (overlay (make-overlay pos (1+ pos))))
          (overlay-put overlay 'suderman/gallery-mark t)
          (overlay-put overlay 'face `(:box (:line-width (-10 . -10) :color ,color))))))))

(defun suderman/gallery--current-file ()
  "Return the selected image file."
  (when-let* ((index (suderman/gallery--index)))
    (aref suderman/gallery-files index)))

(defun suderman/gallery--targets ()
  "Return the marked files, or the selected one."
  (or (seq-filter (lambda (file) (gethash file suderman/gallery-marks))
                  suderman/gallery-files)
      (when-let* ((file (suderman/gallery--current-file)))
        (list file))))

;;;; Commands

(defun suderman/gallery (&optional directory)
  "Show the images of the current directory as a thumbnail gallery.
From Dired or Dirvish, use the images in the listing's order; from an image,
those in its DIRECTORY.  Start on the image at point or the one shown."
  (interactive)
  (unless (display-graphic-p)
    (user-error "The gallery needs a graphical frame"))
  (let* ((source (current-buffer))
         (dired (derived-mode-p 'dired-mode))
         (selected (cond (dired (dired-get-filename nil t))
                         ((derived-mode-p 'image-mode) buffer-file-name)))
         (directory (file-name-as-directory
                     (expand-file-name (or directory default-directory))))
         (scan (if dired
                   (lambda () (when (buffer-live-p source)
                                (with-current-buffer source (revert-buffer nil t))
                                (suderman/gallery--dired-files source)))
                 (lambda () (suderman/gallery--directory-files directory))))
         (files (funcall scan)))
    (unless files
      (user-error "No images in %s" (abbreviate-file-name directory)))
    (let ((configuration (current-window-configuration))
          (gallery (get-buffer-create
                    (format "*gallery %s*" (abbreviate-file-name directory)))))
      (with-current-buffer gallery
        (suderman/gallery-mode)
        (setq default-directory directory
              suderman/gallery-scan scan
              suderman/gallery-files (vconcat (suderman/gallery--order files))
              suderman/gallery-return configuration))
      ;; Dirvish's panes are dedicated; open over the whole frame.
      (let ((ignore-window-parameters t))
        (delete-other-windows))
      (set-window-dedicated-p nil nil)
      (switch-to-buffer gallery nil t)
      (suderman/gallery--layout (or (seq-position suderman/gallery-files selected) 0))
      (suderman/gallery--show-selected))))

(defun suderman/gallery-quit ()
  "Close the gallery and restore the windows it replaced."
  (interactive)
  (let ((gallery (current-buffer))
        (configuration suderman/gallery-return)
        (file (suderman/gallery--current-file)))
    (if configuration
        (set-window-configuration configuration)
      (quit-window))
    (let ((window (selected-window)))
      (with-current-buffer (window-buffer window)
        (when (and file (derived-mode-p 'dired-mode) (dired-goto-file file))
          (set-window-point window (point)))))
    (kill-buffer gallery)))

(defvar-local suderman/gallery--opened nil
  "Non-nil in an image buffer the gallery opened, and so may close.")

(defun suderman/gallery--close (buffer)
  "Kill image BUFFER if the gallery opened it."
  (when (and (buffer-live-p buffer)
             (buffer-local-value 'suderman/gallery--opened buffer))
    (kill-buffer buffer)))

(defun suderman/gallery--visit (gallery index)
  "Show image INDEX of GALLERY in the selected window.
Close the image it replaces if the gallery opened that one."
  (with-current-buffer gallery
    (setq suderman/gallery-index index))
  (let* ((previous (current-buffer))
         (file (aref (buffer-local-value 'suderman/gallery-files gallery) index))
         (existing (find-buffer-visiting file)))
    (switch-to-buffer (or existing (find-file-noselect file)))
    (unless existing
      (setq suderman/gallery--opened t))
    (setq-local suderman/image-step-function
                (lambda (n) (suderman/gallery--step gallery n))
                suderman/image-quit-function
                (lambda () (suderman/gallery--back gallery)))
    (unless (eq previous (current-buffer))
      (suderman/gallery--close previous))))

(defun suderman/gallery--step (gallery n)
  "Replace the shown image with the one N places after it in GALLERY."
  (unless (buffer-live-p gallery)
    (user-error "The gallery is closed"))
  (let* ((index (buffer-local-value 'suderman/gallery-index gallery))
         (count (length (buffer-local-value 'suderman/gallery-files gallery)))
         (next (+ index n)))
    (unless (< -1 next count)
      (user-error (if (< n 0) "First image" "Last image")))
    (suderman/gallery--visit gallery next)))

(defun suderman/gallery--back (gallery)
  "Return from an image to GALLERY."
  (let ((image (current-buffer)))
    (if (not (buffer-live-p gallery))
        (quit-window)
      (switch-to-buffer gallery)
      (goto-char (aref suderman/gallery-cells suderman/gallery-index))
      (suderman/gallery--select)
      (unless (pos-visible-in-window-p)
        (suderman/gallery--show-selected)))
    (suderman/gallery--close image)))

(defun suderman/gallery-open ()
  "Open the selected image."
  (interactive)
  (when-let* ((index (suderman/gallery--index)))
    (suderman/gallery--visit (current-buffer) index)))

(defun suderman/gallery-mouse-open (event)
  "Open the image clicked in EVENT."
  (interactive "e")
  (let ((posn (event-start event)))
    (with-selected-window (posn-window posn)
      (when-let* ((pos (posn-point posn))
                  ((get-text-property pos 'suderman/gallery-index)))
        (goto-char pos)
        (suderman/gallery-open)))))

(defun suderman/gallery-mouse-press ()
  "Ignore a press in the gallery; the click selects or opens."
  (interactive))

;; No region dragging, which would select every tile as whitespace, and a
;; touch on Android still scrolls.
(put 'suderman/gallery-mouse-press 'ignored-mouse-command t)

(defun suderman/gallery-mouse-select (event)
  "Select the image clicked in EVENT; on Android open it."
  (interactive "e")
  (if (featurep 'android)
      (suderman/gallery-mouse-open event)
    (mouse-set-point event)
    (suderman/gallery--select)))

(defun suderman/gallery-hold (event)
  "Mark or unmark the image held down in touch EVENT."
  (interactive "e")
  (let ((posn (cadr event)))
    (with-selected-window (posn-window posn)
      (when-let* ((pos (posn-point posn))
                  ((get-text-property pos 'suderman/gallery-index)))
        (when (fboundp 'touch-screen-inhibit-drag)
          (touch-screen-inhibit-drag))
        (goto-char pos)
        (suderman/gallery-toggle-mark t)))))

(defun suderman/gallery--move (n)
  "Select the image N places away, staying in range."
  (when-let* ((index (suderman/gallery--index)))
    (goto-char (aref suderman/gallery-cells
                     (max 0 (min (1- (length suderman/gallery-cells)) (+ index n)))))
    (suderman/gallery--select)))

(defun suderman/gallery-left () "Select the previous image." (interactive) (suderman/gallery--move -1))
(defun suderman/gallery-right () "Select the next image." (interactive) (suderman/gallery--move 1))
(defun suderman/gallery-up () "Select the image above." (interactive)
       (suderman/gallery--move (- suderman/gallery-column-count)))
(defun suderman/gallery-down () "Select the image below." (interactive)
       (suderman/gallery--move suderman/gallery-column-count))

(defun suderman/gallery-toggle-mark (&optional stay)
  "Mark or unmark the selected image, then select the next unless STAY."
  (interactive)
  (when-let* ((file (suderman/gallery--current-file)))
    (if (gethash file suderman/gallery-marks)
        (remhash file suderman/gallery-marks)
      (puthash file t suderman/gallery-marks))
    (suderman/gallery--show-marks)
    (unless stay (suderman/gallery--move 1))
    (force-mode-line-update)))

(defun suderman/gallery-unmark-all ()
  "Unmark every image."
  (interactive)
  (clrhash suderman/gallery-marks)
  (suderman/gallery--show-marks)
  (force-mode-line-update))

(defun suderman/gallery--reload (files)
  "Show FILES, keeping the selection near where it was."
  (let ((index (or (suderman/gallery--index) 0)))
    (setq suderman/gallery-files (vconcat (suderman/gallery--order files)))
    (maphash (lambda (file _)
               (unless (seq-contains-p suderman/gallery-files file)
                 (remhash file suderman/gallery-marks)))
             suderman/gallery-marks)
    (if (zerop (length suderman/gallery-files))
        (progn (suderman/gallery-quit)
               (message "No images remain"))
      (suderman/gallery--layout (min index (1- (length suderman/gallery-files)))))))

(defun suderman/gallery-refresh ()
  "Rescan the directory and rebuild the gallery."
  (interactive)
  (suderman/gallery--reload (funcall suderman/gallery-scan)))

(defun suderman/gallery-toggle-order ()
  "Switch between listing order and newest first."
  (interactive)
  (let ((file (suderman/gallery--current-file)))
    (setq suderman/gallery-newest-first (not suderman/gallery-newest-first))
    (setq suderman/gallery-files
          (vconcat (suderman/gallery--order (funcall suderman/gallery-scan))))
    (suderman/gallery--layout (or (seq-position suderman/gallery-files file) 0))
    (suderman/gallery--show-selected)
    (message (if suderman/gallery-newest-first "Newest first" "Listing order"))))

(defun suderman/gallery-delete ()
  "Delete the marked images, or the selected one, after confirmation."
  (interactive)
  (let ((files (suderman/gallery--targets)))
    (when (and files
               (yes-or-no-p (if (cdr files)
                                (format "Delete %d images? " (length files))
                              (format "Delete %s? " (file-name-nondirectory (car files))))))
      (dolist (file files)
        (when-let* ((buffer (find-buffer-visiting file)))
          (kill-buffer buffer))
        (delete-file file t))
      (suderman/gallery--reload
       (seq-remove (lambda (file) (member file files))
                   (append suderman/gallery-files nil)))
      (message "Deleted %d image%s" (length files) (if (cdr files) "s" "")))))

(defun suderman/gallery-larger ()
  "Show fewer, larger thumbnails."
  (interactive)
  (setq suderman/gallery-columns
        (max 1 (1- (or suderman/gallery-columns suderman/gallery-column-count))))
  (suderman/gallery--layout)
  (suderman/gallery--show-selected))

(defun suderman/gallery-smaller ()
  "Show more, smaller thumbnails."
  (interactive)
  (setq suderman/gallery-columns
        (1+ (or suderman/gallery-columns suderman/gallery-column-count)))
  (suderman/gallery--layout)
  (suderman/gallery--show-selected))

(defvar suderman/gallery--pinch-ready t
  "Non-nil while a pinch is near its starting spread and may take a step.")

(defun suderman/gallery-pinch (event)
  "Show one column fewer or more for each pinch EVENT gesture.
Spreading shows fewer, larger thumbnails, keeping the one under the fingers.
The fingers must come back near where they started before another step,
so one pinch never changes the grid twice."
  (interactive "e")
  (let* ((desktop (eq (car event) 'pinch))
         (posn (nth 1 event))
         (scale (if desktop (nth 4 event) (nth 2 event)))
         (window (posn-window posn)))
    (cond
     ((< (abs (- scale 1.0)) 0.08)
      (setq suderman/gallery--pinch-ready t))
     ((and suderman/gallery--pinch-ready
           (windowp window)
           (or (> scale 1.25) (< scale 0.8)))
      (setq suderman/gallery--pinch-ready nil)
      (with-selected-window window
        (let ((columns (+ suderman/gallery-column-count (if (> scale 1) -1 1))))
          (when (<= 1 columns 12)
            (setq suderman/gallery-columns columns)
            (suderman/gallery--layout
             (or (and (posn-point posn)
                      (get-text-property (posn-point posn) 'suderman/gallery-index))
                 (suderman/gallery--index)))
            (recenter))))))))

(defun suderman/gallery--header ()
  "Return the gallery's header line."
  (let ((marks (hash-table-count suderman/gallery-marks)))
    (concat (format " %d images" (length suderman/gallery-files))
            (if (> marks 0) (format ", %d marked" marks) "")
            (if suderman/gallery-newest-first ", newest first" "")
            "  " (abbreviate-file-name default-directory))))

(defvar-keymap suderman/gallery-mode-map
  :doc "Keys in the image gallery."
  "h" #'suderman/gallery-left
  "j" #'suderman/gallery-down
  "k" #'suderman/gallery-up
  "l" #'suderman/gallery-right
  "<left>" #'suderman/gallery-left
  "<down>" #'suderman/gallery-down
  "<up>" #'suderman/gallery-up
  "<right>" #'suderman/gallery-right
  "RET" #'suderman/gallery-open
  "o" #'suderman/gallery-open
  "m" #'suderman/gallery-toggle-mark
  "U" #'suderman/gallery-unmark-all
  "d" #'suderman/gallery-delete
  "s" #'suderman/gallery-toggle-order
  "g" #'suderman/gallery-refresh
  "+" #'suderman/gallery-larger
  "=" #'suderman/gallery-larger
  "-" #'suderman/gallery-smaller
  "q" #'suderman/gallery-quit
  "," #'suderman/ibuffer-toggle
  "SPC" #'meow-keypad
  "<down-mouse-1>" #'suderman/gallery-mouse-press
  "<double-down-mouse-1>" #'suderman/gallery-mouse-press
  "<mouse-1>" #'suderman/gallery-mouse-select
  "<double-mouse-1>" #'suderman/gallery-mouse-open
  "<touchscreen-hold>" #'suderman/gallery-hold
  "<touchscreen-pinch>" #'suderman/gallery-pinch
  "<pinch>" #'suderman/gallery-pinch
  "C-<wheel-up>" #'suderman/gallery-larger
  "C-<wheel-down>" #'suderman/gallery-smaller)

(define-derived-mode suderman/gallery-mode special-mode "Gallery"
  "Browse a directory's images as thumbnails."
  (suderman/meow-off)
  (setq-local cursor-type nil
              truncate-lines t
              ;; Rows never scroll sideways by touch.
              suderman/sideways-scroll (list nil nil t)
              suderman/gallery-marks (make-hash-table :test #'equal)
              header-line-format '(:eval (suderman/gallery--header))
              ;; Small chunks load only the rows redisplay shows.
              jit-lock-chunk-size 64)
  (jit-lock-register #'suderman/gallery--fontify)
  (add-hook 'post-command-hook #'suderman/gallery--select nil t)
  (add-hook 'window-size-change-functions #'suderman/gallery--refit nil t))

(keymap-set suderman/image-view-mode-map "G" #'suderman/gallery)

(provide 'suderman-gallery)
;;; suderman-gallery.el ends here
