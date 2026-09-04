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

(defun suderman/android-setup-tool-bar ()
  "Configure the compact Android input toolbar idempotently."
  (require 'tool-bar)
  (modifier-bar-mode -1)
  (customize-set-variable 'tool-bar-position 'bottom)
  (setq secondary-tool-bar-map nil
        tool-bar-button-margin 10)
  (dolist (key '(suderman-escape suderman-tab control meta))
    (define-key tool-bar-map (vector key) nil))
  (define-key tool-bar-map [suderman-escape]
    `(menu-item "Escape" meow-insert-exit
                 :image ,(tool-bar--image-expression "left-arrow")
                 :help "Leave Meow Insert state"))
  (define-key-after tool-bar-map [suderman-tab]
    `(menu-item "Tab" ignore
                :image ,(tool-bar--image-expression "right-arrow")
                :help "Send Tab")
    'suderman-escape)
  (tool-bar-add-item "ctrl" #'ignore 'control
                     :label "Ctrl" :help "Apply Control to the next key")
  (tool-bar-add-item "meta" #'ignore 'meta
                     :label "Meta" :help "Apply Meta to the next key")
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
  (suderman/android-setup-tool-bar)
  (define-key function-key-map [volume-down] #'suderman/android-volume-control)
  (define-key function-key-map [volume-up] #'suderman/android-volume-meta))

(provide 'suderman-android)
;;; suderman-android.el ends here
