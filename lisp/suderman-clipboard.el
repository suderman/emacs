;;; suderman-clipboard.el --- Clipboard copy in terminal frames -*- lexical-binding: t; -*-

;;; Commentary:
;; Use Wayland locally and OSC 52 through remote terminal connections.

;;; Code:

(defun suderman/select-text (text)
  "Copy TEXT using Emacs selection support or local Wayland in a terminal."
  (gui-select-text text)
  (when (and (not (display-graphic-p))
             (not (terminal-parameter nil 'xterm--set-selection)))
    (if (and (getenv "WAYLAND_DISPLAY" (selected-frame))
             (not (getenv "SSH_CONNECTION" (selected-frame)))
             (not (getenv "SSH_TTY" (selected-frame)))
             (executable-find "wl-copy"))
        (with-temp-buffer
          (insert text)
          (unless (zerop (call-process-region (point-min) (point-max)
                                             "wl-copy" nil nil nil))
            (error "wl-copy failed")))
      (send-string-to-terminal
       (concat "\e]52;c;"
               (base64-encode-string (encode-coding-string text 'utf-8-unix) t)
               "\a")))))

(setq interprogram-cut-function #'suderman/select-text)

(provide 'suderman-clipboard)
;;; suderman-clipboard.el ends here
