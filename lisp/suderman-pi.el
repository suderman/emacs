;;; suderman-pi.el --- Pi coding agent integration -*- lexical-binding: t; -*-

;;; Code:

(unless (eq system-type 'android)
  (use-package pi-coding-agent
    :demand t))
(declare-function pi-coding-agent--read-prompt-image "pi-coding-agent-input" (path))
(declare-function pi-coding-agent--get-prompt-image "pi-coding-agent-ui" (&optional input-buffer))
(declare-function pi-coding-agent--set-prompt-image "pi-coding-agent-ui" (image &optional input-buffer))
(declare-function pi-coding-agent--get-input-buffer "pi-coding-agent-ui" ())
(declare-function pi-coding-agent--prompt-image-byte-size "pi-coding-agent-input" (image))
(declare-function pi-coding-agent--prompt-image-data "pi-coding-agent-input" (image))
(declare-function pi-coding-agent--prompt-image-mime-type "pi-coding-agent-input" (image))
(declare-function pi-coding-agent--prompt-image-name "pi-coding-agent-input" (image))

(unless (eq system-type 'android)
  (require 'pi-coding-agent)
  (defalias 'pi 'pi-coding-agent))

(defvar-local suderman-pi--image-indicator nil)

(defun suderman-pi--prompt-image-preview (image)
  "Return a small display image for IMAGE, or nil when unavailable."
  (condition-case nil
      (let ((type (pcase (pi-coding-agent--prompt-image-mime-type image)
                    ("image/png" 'png)
                    ("image/jpeg" 'jpeg)
                    ("image/gif" 'gif)
                    ("image/webp" 'webp))))
        (when (and type (display-images-p) (image-type-available-p type))
          (create-image (base64-decode-string
                         (pi-coding-agent--prompt-image-data image))
                        type t :max-width 360 :max-height 180)))
    (error nil)))

(defun suderman-pi-refresh-image-indicator (_image &optional input-buffer)
  "Show attached prompt image above INPUT-BUFFER's text."
  (with-current-buffer (or input-buffer (current-buffer))
    (when (overlayp suderman-pi--image-indicator)
      (delete-overlay suderman-pi--image-indicator))
    (setq suderman-pi--image-indicator nil)
    (when-let* ((image (pi-coding-agent--get-prompt-image)))
      (setq suderman-pi--image-indicator (make-overlay (point-min) (point-min)))
      (overlay-put
       suderman-pi--image-indicator 'before-string
       (concat
        (propertize
         (format "[Image attached: %s, %s. C-u C-c C-a clears.]\n"
                 (pi-coding-agent--prompt-image-name image)
                 (file-size-human-readable
                  (pi-coding-agent--prompt-image-byte-size image)
                  'iec " " "B"))
         'face 'success)
        (when-let* ((preview (suderman-pi--prompt-image-preview image)))
          (concat (propertize " " 'display preview) "\n")))))
    (force-window-update (current-buffer))))

(unless (eq system-type 'android)
  (unless (advice-member-p #'suderman-pi-refresh-image-indicator
                           'pi-coding-agent--set-prompt-image)
    (advice-add 'pi-coding-agent--set-prompt-image :after
                #'suderman-pi-refresh-image-indicator)))

(defun suderman-pi-attach-clipboard-image ()
  "Attach the Wayland clipboard image to the current Pi draft."
  (interactive)
  (unless (member "image/png" (process-lines "wl-paste" "--list-types"))
    (user-error "Clipboard does not contain a PNG image"))
  (let ((file (make-temp-file "pi-clipboard-" nil ".png")))
    (unwind-protect
        (progn
          (with-temp-buffer
            (unless (zerop (call-process "wl-paste" nil t nil
                                         "--type" "image/png" "--no-newline"))
              (user-error "Could not read PNG image from clipboard"))
            (write-region (point-min) (point-max) file nil 'silent))
          (with-current-buffer (pi-coding-agent--get-input-buffer)
            (let ((image (pi-coding-agent--read-prompt-image file)))
              (pi-coding-agent--set-prompt-image image)
              (message "Pi: Attached clipboard image (%s)"
                       (file-size-human-readable
                        (pi-coding-agent--prompt-image-byte-size image)
                        'iec " " "B")))))
      (delete-file file))))

(unless (eq system-type 'android)
  (define-key pi-coding-agent-input-mode-map (kbd "C-c C-v")
              #'suderman-pi-attach-clipboard-image))

(provide 'suderman-pi)
;;; suderman-pi.el ends here
