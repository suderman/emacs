;;; suderman-appearance.el --- Fonts and frame appearance -*- lexical-binding: t; -*-

;;; Commentary:
;; GUI-only appearance that needs to apply to both the first frame and later
;; daemon/client frames.  early-init.el sets matching frame defaults so startup
;; frames get the same font and opacity before this module loads.

;;; Code:

(defconst suderman/font-family "JetBrainsMono Nerd Font Mono")
(defconst suderman/font-size 11)
(defconst suderman/font-height (* suderman/font-size 10))
(defconst suderman/nerd-symbol-font "Symbols Nerd Font Mono")
(defconst suderman/background-opacity 90)

(defun suderman/set-nerd-font-fallbacks ()
  "Teach Emacs where Nerd Font private-use icons live."
  (dolist (range (list (cons #xe000 #xf8ff)
                       (cons #xf0000 #xffffd)
                       (cons #x100000 #x10fffd)))
    (set-fontset-font t range
                      (font-spec :family suderman/nerd-symbol-font)
                      nil 'prepend)))

(defun suderman/apply-gui-appearance (&optional frame)
  "Apply GUI font and background opacity to FRAME."
  (let ((target-frame (or frame (selected-frame))))
    (when (display-graphic-p target-frame)
      (set-face-attribute 'default target-frame
                          :family suderman/font-family
                          :height suderman/font-height)
      (set-face-attribute 'fixed-pitch target-frame
                          :family suderman/font-family
                          :height suderman/font-height)
      (set-frame-parameter target-frame 'alpha-background
                           suderman/background-opacity))))

(add-to-list 'default-frame-alist `(font . ,(format "%s-%d" suderman/font-family suderman/font-size)))
(add-to-list 'default-frame-alist `(alpha-background . ,suderman/background-opacity))
(add-to-list 'initial-frame-alist `(font . ,(format "%s-%d" suderman/font-family suderman/font-size)))
(add-to-list 'initial-frame-alist `(alpha-background . ,suderman/background-opacity))

(suderman/set-nerd-font-fallbacks)
(suderman/apply-gui-appearance)
(add-hook 'after-make-frame-functions #'suderman/apply-gui-appearance)

(provide 'suderman-appearance)
;;; suderman-appearance.el ends here
