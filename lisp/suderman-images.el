;;; suderman-images.el --- Image navigation and clipboard support -*- lexical-binding: t; -*-

;;; Commentary:
;; Image mode navigation, transforms, animation, and clipboard behavior.

;;; Code:

(require 'subr-x)
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

(add-hook 'image-mode-hook #'suderman/image-mode-setup)
(add-hook 'find-file-hook #'suderman/image-mode-setup t)

(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'image-mode)
      (suderman/image-mode-setup))))

(provide 'suderman-images)
;;; suderman-images.el ends here
