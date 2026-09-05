;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android input helpers and Termux executable discovery.

;;; Code:

(require 'subr-x)

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

(defun suderman/android-tool-bar-image (name)
  "Return a theme-aware tool-bar image expression for NAME."
  `(create-image
    ,(expand-file-name (format "assets/android-toolbar/%s.pbm" name)
                       user-emacs-directory)
    'pbm nil :scale 1
    :foreground ,(face-foreground 'tool-bar nil t)
    :background ,(face-background 'tool-bar nil t)))

(defun suderman/android-show-keyboard ()
  "Show the Android software keyboard for the selected frame."
  (interactive)
  (frame-toggle-on-screen-keyboard (selected-frame) nil))

(defun suderman/android-setup-tool-bar (&optional _theme)
  "Configure the touch-friendly Android input toolbar idempotently."
  (require 'tool-bar)
  (modifier-bar-mode -1)
  (customize-set-variable 'tool-bar-position 'bottom)
  (set-face-attribute 'tool-bar nil
                      :foreground (face-background 'default nil t)
                      :background (face-foreground 'default nil t))
  (setq secondary-tool-bar-map nil
        tool-bar-button-margin '(48 . 20)
        tool-bar-always-show-default t)
  (let ((map (make-sparse-keymap)))
    (define-key-after map [suderman-escape]
      `(menu-item "ESC" meow-insert-exit
                  :image ,(suderman/android-tool-bar-image "escape")
                  :help "Leave Meow Insert state"))
    (define-key-after map [suderman-tab]
      `(menu-item "TAB" ignore
                  :image ,(suderman/android-tool-bar-image "tab")
                  :help "Send Tab")
      'suderman-escape)
    (define-key-after map [suderman-files]
      `(menu-item "FILES" suderman/dirvish
                  :image ,(suderman/android-tool-bar-image "files")
                  :help "Open Dirvish")
      'suderman-tab)
    (define-key-after map [suderman-buffers]
      `(menu-item "BUFFERS" suderman/ibuffer-toggle
                  :image ,(suderman/android-tool-bar-image "buffers")
                  :help "Open IBuffer")
      'suderman-files)
    (define-key-after map [suderman-keyboard]
      `(menu-item "KEYBOARD" suderman/android-show-keyboard
                  :image ,(suderman/android-tool-bar-image "keyboard")
                  :help "Show the software keyboard")
      'suderman-buffers)
    (define-key-after map [control]
      `(menu-item "CTRL" ignore
                  :image ,(suderman/android-tool-bar-image "control")
                  :help "Apply Control to the next key")
      'suderman-keyboard)
    (define-key-after map [meta]
      `(menu-item "META" ignore
                  :image ,(suderman/android-tool-bar-image "meta")
                  :help "Apply Meta to the next key")
      'control)
    (set-default 'tool-bar-map map))
  (define-key input-decode-map [tool-bar suderman-escape] nil)
  (define-key input-decode-map [tool-bar suderman-tab] [tab])
  (define-key input-decode-map [tool-bar control]
              #'tool-bar-event-apply-control-modifier)
  (define-key input-decode-map [tool-bar meta]
              #'tool-bar-event-apply-meta-modifier)
  (tool-bar--flush-cache)
  (tool-bar-mode 1)
  (force-mode-line-update t))

(when (eq system-type 'android)
  (add-to-list 'exec-path suderman/android-termux-bin)
  (setenv "PATH"
          (string-join (delete-dups
                        (cons suderman/android-termux-bin
                              (parse-colon-path (getenv "PATH"))))
                       path-separator))
  (add-hook 'enable-theme-functions #'suderman/android-setup-tool-bar t)
  (suderman/android-setup-tool-bar)
  (define-key function-key-map [volume-down] #'suderman/android-volume-control)
  (define-key function-key-map [volume-up] #'suderman/android-volume-meta))

(provide 'suderman-android)
;;; suderman-android.el ends here
