;;; suderman-images.el --- Image navigation and clipboard support -*- lexical-binding: t; -*-

;;; Commentary:
;; Image mode navigation, transforms, animation, and clipboard behavior.

;;; Code:

(require 'subr-x)
(require 'image-dired)
(require 'suderman-files)
(require 'suderman-meow)

(defvar image-mode-map)
(defvar image-animate-loop)
(defvar dired-movement-style)
(declare-function image-next-file "image-mode")
(declare-function image-previous-file "image-mode")
(declare-function image-transform-reset-to-initial "image-mode")
(declare-function image-get-display-property "image-mode")
(declare-function image-toggle-animation "image-mode")
(declare-function image-multi-frame-p "image")
(declare-function image-animate-timer "image")

(defvar-local suderman/image-dired-window-configuration nil
  "Window configuration to restore when leaving the image gallery.")

(defvar-local suderman/image-dired-source-buffer nil
  "Dired or Dirvish buffer backing the current image gallery.")

(defvar-local suderman/image-dired-source-window nil
  "Window that opened the current image gallery.")

(defvar-local suderman/image-dired-gallery-buffer nil
  "Thumbnail buffer to restore from an Image-Dired image buffer.")

(defun suderman/image-dired--files (buffer)
  "Return top-level image files listed in Dired BUFFER."
  (with-current-buffer buffer
    (let ((directory (file-name-as-directory
                      (expand-file-name default-directory)))
          files)
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (when-let* ((file (dired-get-filename nil t))
                      ((equal (file-name-directory file) directory))
                      ((file-regular-p file))
                      ((string-match-p (image-dired--file-name-regexp) file)))
            (push file files))
          (forward-line 1)))
      (nreverse files))))

(defun suderman/image-dired--populate (buffer source files selected-file)
  "Populate BUFFER with FILES from SOURCE, selecting SELECTED-FILE."
  (setq image-dired--generate-thumbs-start (current-time))
  (with-current-buffer buffer
    (setq-local default-directory
                (buffer-local-value 'default-directory source))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (setq image-dired--number-of-thumbnails 0)
      (dolist (file files)
        (image-dired-insert-thumbnail
         (image-dired--get-create-thumbnail-file file) file source)
        (cl-incf image-dired--number-of-thumbnails)))
    (image-dired--line-up-with-method)
    (goto-char (or (and selected-file
                        (text-property-any
                         (point-min) (point-max)
                         'original-file-name selected-file))
                   (point-min)))
    (image-dired--update-header-line)
    (when (image-dired-image-at-point-p)
      (image-dired-track-original-file))))

(defun suderman/image-dired--restore-source ()
  "Restore the Dired or Dirvish window behind the current gallery."
  (let* ((gallery (current-buffer))
         (image-buffer (get-buffer image-dired-display-image-buffer))
         (configuration suderman/image-dired-window-configuration)
         (source suderman/image-dired-source-buffer)
         (source-window suderman/image-dired-source-window)
         (selected-file
          (or (image-dired-original-file-name)
              (and (buffer-live-p source)
                   (with-current-buffer source
                     (dired-get-filename nil t))))))
    (setq suderman/image-dired-window-configuration nil
          suderman/image-dired-source-buffer nil
          suderman/image-dired-source-window nil)
    (if (not configuration)
        (quit-window)
      (set-window-configuration configuration)
      (when (and selected-file (buffer-live-p source)
                 (window-live-p source-window))
        (with-current-buffer source
          (when (dired-goto-file selected-file)
            (set-window-point source-window (point)))))
      (when (buffer-live-p image-buffer)
        (kill-buffer image-buffer))
      (when (buffer-live-p gallery)
        (kill-buffer gallery)))))

(defun suderman/image-dired-gallery ()
  "Show images from the current Dired or Dirvish buffer as a gallery."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (user-error "The image gallery must be opened from Dired or Dirvish"))
  (let* ((source (current-buffer))
         (source-window (selected-window))
         (selected-file (dired-get-filename nil t))
         (files (suderman/image-dired--files source)))
    (unless files
      (user-error "No images in %s" (abbreviate-file-name default-directory)))
    (let* ((image-dired-thumbnail-buffer
            (generate-new-buffer-name "*image-gallery*"))
           (gallery (image-dired-create-thumbnail-buffer)))
      (with-current-buffer gallery
        (suderman/image-dired-setup)
        (setq-local image-dired-thumbnail-buffer (buffer-name)
                    image-dired-display-image-buffer
                    (generate-new-buffer-name "*image-gallery-image*"))
        (setq suderman/image-dired-window-configuration
              (current-window-configuration)
              suderman/image-dired-source-buffer source
              suderman/image-dired-source-window source-window))
      (condition-case error-data
          (let ((gallery-window
                 (display-buffer
                  gallery
                  '((display-buffer-pop-up-window)
                    (inhibit-same-window . t)))))
            (unless (window-live-p gallery-window)
              (error "Could not create an image gallery window"))
            (select-window gallery-window)
            (let ((ignore-window-parameters t))
              (delete-other-windows gallery-window))
            (suderman/image-dired--populate
             gallery source files selected-file))
        (error
         (with-current-buffer gallery
           (suderman/image-dired--restore-source))
         (signal (car error-data) (cdr error-data)))))))

(defun suderman/image-dired-quit ()
  "Leave the image gallery and restore its originating directory view."
  (interactive)
  (suderman/image-dired--restore-source))

(defun suderman/image-dired-refresh ()
  "Refresh the directory and rebuild the current image gallery."
  (interactive)
  (unless (buffer-live-p suderman/image-dired-source-buffer)
    (user-error "The gallery's directory buffer no longer exists"))
  (let* ((gallery (current-buffer))
         (source suderman/image-dired-source-buffer)
         (selected-file (image-dired-original-file-name))
         files)
    (with-current-buffer source
      (revert-buffer nil t)
      (setq files (suderman/image-dired--files source)))
    (if files
        (suderman/image-dired--populate
         gallery source files selected-file)
      (suderman/image-dired--restore-source)
      (message "No images remain in %s"
               (abbreviate-file-name
                (buffer-local-value 'default-directory source))))))

(defun suderman/image-dired-delete ()
  "Delete flagged images, returning to Dired when none remain."
  (interactive)
  (image-dired-do-flagged-delete)
  (let ((count 0))
    (save-excursion
      (goto-char (point-min))
      (while (text-property-search-forward
              'image-dired-thumbnail t t)
        (cl-incf count)))
    (setq image-dired--number-of-thumbnails count)
    (if (zerop count)
        (progn
          (suderman/image-dired--restore-source)
          (message "No images remain"))
      (image-dired--update-header-line))))

(defun suderman/image-dired--display-current (gallery)
  "Display GALLERY's current image and preserve its private buffers."
  (let ((image-buffer-name
         (buffer-local-value 'image-dired-display-image-buffer gallery))
        (display-buffer-overriding-action '(display-buffer-same-window)))
    (with-current-buffer gallery
      (image-dired-display-this))
    (when-let* ((buffer (get-buffer image-buffer-name)))
      (with-current-buffer buffer
        (setq-local suderman/image-dired-gallery-buffer gallery
                    image-dired-thumbnail-buffer (buffer-name gallery)
                    image-dired-display-image-buffer (buffer-name buffer))))))

(defun suderman/image-dired-display ()
  "Display the image at point in the gallery window."
  (interactive)
  (suderman/image-dired--display-current (current-buffer)))

(defun suderman/image-dired-display-next (n)
  "Display the Nth next gallery image, wrapping at either end."
  (interactive "p")
  (unless (buffer-live-p suderman/image-dired-gallery-buffer)
    (user-error "The image's thumbnail gallery no longer exists"))
  (let ((gallery suderman/image-dired-gallery-buffer))
    (with-current-buffer gallery
      (image-dired-forward-image n t))
    (suderman/image-dired--display-current gallery)))

(defun suderman/image-dired-display-previous (n)
  "Display the Nth previous gallery image, wrapping at either end."
  (interactive "p")
  (suderman/image-dired-display-next (- n)))

(defun suderman/image-dired-return-to-gallery ()
  "Return from an Image-Dired image to its thumbnail gallery."
  (interactive)
  (if (buffer-live-p suderman/image-dired-gallery-buffer)
      (switch-to-buffer suderman/image-dired-gallery-buffer)
    (quit-window)))

(defun suderman/image-dired-setup ()
  "Prepare the Image-Dired thumbnail gallery."
  (add-hook 'meow-mode-hook #'suderman/dired-disable-meow nil t)
  (suderman/dired-disable-meow))

(defun suderman/image-rotate-counterclockwise ()
  "Rotate the image at point 90 degrees counterclockwise."
  (interactive)
  (image-rotate -90))

(defun suderman/image-next-file (n)
  "Visit the Nth next image in cyclic directory order."
  (interactive "p")
  (let ((dired-movement-style 'cycle-files))
    (image-next-file n)))

(defun suderman/image-previous-file (n)
  "Visit the Nth previous image in cyclic directory order."
  (interactive "p")
  (let ((dired-movement-style 'cycle-files))
    (image-previous-file n)))

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
  "Prepare Image mode for Meow motion state."
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
      (meow-mode 1))))

(with-eval-after-load 'image-mode
  (setq image-animate-loop t)
  (keymap-set image-mode-map "," #'suderman/ibuffer-toggle)
  (keymap-set image-mode-map "." #'suderman/dirvish)
  (keymap-set image-mode-map "c" #'suderman/image-copy-to-clipboard)
  (keymap-set image-mode-map "n" #'suderman/image-next-file)
  (keymap-set image-mode-map "p" #'suderman/image-previous-file)
  (keymap-set image-mode-map "=" #'image-increase-size)
  (keymap-set image-mode-map "+" #'image-increase-size)
  (keymap-set image-mode-map "-" #'image-decrease-size)
  (keymap-set image-mode-map "r" #'image-rotate)
  (keymap-set image-mode-map "R" #'suderman/image-rotate-counterclockwise)
  (keymap-set image-mode-map "0" #'image-transform-reset-to-initial))

(setq image-dired-thumbnail-storage 'standard-large)

(dolist (map (list dired-mode-map dirvish-mode-map))
  (keymap-set map "G" #'suderman/image-dired-gallery))

(dolist (binding '(("h" . image-dired-backward-image)
                   ("j" . image-dired-next-line)
                   ("k" . image-dired-previous-line)
                   ("l" . image-dired-forward-image)
                   ("<left>" . image-dired-backward-image)
                   ("<down>" . image-dired-next-line)
                   ("<up>" . image-dired-previous-line)
                   ("<right>" . image-dired-forward-image)
                   ("RET" . suderman/image-dired-display)
                   ("<return>" . suderman/image-dired-display)
                   ("SPC" . meow-keypad)
                   ("g" . suderman/image-dired-refresh)
                   ("q" . suderman/image-dired-quit)
                   ("x" . suderman/image-dired-delete)))
  (keymap-set image-dired-thumbnail-mode-map
              (car binding) (cdr binding)))

(dolist (binding '(("n" . suderman/image-dired-display-next)
                   ("p" . suderman/image-dired-display-previous)
                   ("q" . suderman/image-dired-return-to-gallery)))
  (keymap-set image-dired-image-mode-map (car binding) (cdr binding)))

(add-hook 'image-mode-hook #'suderman/image-mode-setup)
(add-hook 'image-dired-thumbnail-mode-hook #'suderman/image-dired-setup)
(add-hook 'find-file-hook #'suderman/image-mode-setup t)

(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'image-mode)
      (suderman/image-mode-setup))))

(provide 'suderman-images)
;;; suderman-images.el ends here
