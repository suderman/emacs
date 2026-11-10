;;; suderman-images.el --- Image viewing -*- lexical-binding: t; -*-

;;; Commentary:
;; Loupe zooms, pans, and pages through images and PDFs, and shows a folder
;; as a gallery.  This module fits it to Meow, Doom Modeline, Dirvish, and
;; terminal frames, and adds animation and clipboard copy.

;;; Code:

(require 'image-mode)
(require 'suderman-paths)
(require 'suderman-files)
(require 'suderman-meow)

(defvar image-animate-loop)
(defvar meow-cursor-type-motion)
(defvar meow-cursor-type-default)
(defvar doom-modeline-buffer-file-name-style)
(defvar doc-view-resolution)
(defvar doc-view-continuous)
(defvar suderman/sideways-scroll)
(defvar loupe-gallery-mode-map)

(use-package loupe
  :vc (:url "https://github.com/suderman/loupe" :rev :newest)
  :ensure nil
  :if t
  :demand t
  :init
  (setq loupe-proxy-directory (expand-file-name "image-proxy/" suderman/cache-dir))
  :config
  ;; Meow's Motion keys move point, which means nothing in an image.
  (keymap-set loupe-image-mode-map "<remap> <meow-left>" #'loupe-left)
  (keymap-set loupe-image-mode-map "<remap> <meow-right>" #'loupe-right)
  (keymap-set loupe-image-mode-map "<remap> <meow-prev>" #'loupe-up)
  (keymap-set loupe-image-mode-map "<remap> <meow-next>" #'loupe-down)
  (loupe-mode 1))

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
  "Prepare Image mode for Meow Motion state and animation."
  (when (derived-mode-p 'image-mode)
    (when-let* ((image (image-get-display-property))
                ((image-multi-frame-p image))
                ((not (image-animate-timer image))))
      (image-toggle-animation))
    (when (and (bound-and-true-p meow-global-mode)
               (not (and (bound-and-true-p meow-mode)
                         (bound-and-true-p meow-motion-mode)
                         (eq meow--current-state 'motion))))
      (meow-mode 1))
    ;; Meow's cursor would frame and blink around the whole image.  Meow
    ;; resets a nil cursor to its default type, so hide that one too.
    ;; Doom Modeline's usual style looks for a project, which lists the
    ;; whole directory: 1.2 s per photo in a phone's camera folder.
    (setq-local meow-cursor-type-motion nil
                meow-cursor-type-default nil
                doom-modeline-buffer-file-name-style 'file-name)))

(defun suderman/image-metadata-graphic-frame (arguments)
  "Measure images on a GUI frame while a terminal frame is selected.
Animation timers call `image-metadata' with ARGUMENTS lacking a frame, which
fails and kills a GUI animation whenever a daemon's terminal frame is in use."
  (if (or (cadr arguments) (display-graphic-p))
      arguments
    (list (car arguments) (seq-find #'display-graphic-p (frame-list)))))

(advice-add 'image-metadata :filter-args #'suderman/image-metadata-graphic-frame)

(setq image-animate-loop t)

(keymap-set image-mode-map "," #'suderman/ibuffer-toggle)
(keymap-set image-mode-map "." #'suderman/dirvish)
(keymap-set image-mode-map "c" #'suderman/image-copy-to-clipboard)

(defun suderman/gallery-setup ()
  "Give the gallery its own letter keys and vertical-only touch scrolling."
  (suderman/meow-off)
  (setq-local suderman/sideways-scroll (list nil nil t)))

(with-eval-after-load 'loupe-gallery
  (keymap-set loupe-gallery-mode-map "SPC" #'meow-keypad)
  (keymap-set loupe-gallery-mode-map "," #'suderman/ibuffer-toggle)
  (add-hook 'loupe-gallery-mode-hook #'suderman/gallery-setup))

(with-eval-after-load 'doc-view
  ;; Android renders PDFs with Termux's Ghostscript; render sharp enough
  ;; to zoom, and keep pages flowing.
  (setq doc-view-resolution 200
        doc-view-continuous t))

(add-hook 'image-mode-hook #'suderman/image-mode-setup)
(add-hook 'find-file-hook #'suderman/image-mode-setup t)

(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'image-mode)
      (suderman/image-mode-setup))))

(provide 'suderman-images)
;;; suderman-images.el ends here
