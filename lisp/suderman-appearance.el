;;; suderman-appearance.el --- Fonts and frame appearance -*- lexical-binding: t; -*-

;;; Commentary:
;; GUI-only appearance that needs to apply to both the first frame and later
;; daemon/client frames.  early-init.el sets matching frame opacity before this
;; module loads.

;;; Code:

(require 'color)
(require 'use-package)

(defconst suderman/font-family "JetBrainsMono Nerd Font Mono")
(defconst suderman/font-size 11)
(defconst suderman/nerd-symbol-font "Symbols Nerd Font Mono")
(defconst suderman/background-opacity 90)

;; Stylix's default.el loads after init.el and replaces this fallback when
;; enabled.  Avoid overriding it on systems where it loads earlier instead.
(unless (memq 'base16-stylix custom-enabled-themes)
  (set-face-attribute 'default nil :font
                      (font-spec :family suderman/font-family
                                 :size suderman/font-size)))

(defun suderman/set-nerd-font-fallbacks ()
  "Teach Emacs where Nerd Font private-use icons live."
  (dolist (range (list (cons #xe000 #xf8ff)
                       (cons #xf0000 #xffffd)
                       (cons #x100000 #x10fffd)))
    (set-fontset-font t range
                      (font-spec :family suderman/nerd-symbol-font)
                      nil 'prepend)))

(defun suderman/apply-gui-appearance (&optional frame)
  "Apply GUI background opacity to FRAME."
  (let ((target-frame (or frame (selected-frame))))
    (when (display-graphic-p target-frame)
      (set-frame-parameter target-frame 'alpha-background
                           suderman/background-opacity))))

(add-to-list 'default-frame-alist `(alpha-background . ,suderman/background-opacity))
(add-to-list 'initial-frame-alist `(alpha-background . ,suderman/background-opacity))

(defun suderman/theme-blend (face alpha)
  "Blend FACE's foreground into the theme background by ALPHA."
  (let ((accent (face-foreground face nil t))
        (background (face-background 'default nil t)))
    (when (and (stringp accent) (stringp background))
      (when-let* ((accent-rgb (color-name-to-rgb accent))
                  (background-rgb (color-name-to-rgb background)))
        (apply #'color-rgb-to-hex
               (append (color-blend accent-rgb background-rgb alpha)
                       '(2)))))))

(defun suderman/apply-selection-faces (&optional _theme)
  "Derive selection faces from the active theme's semantic colors."
  (when-let* ((frame (car (filtered-frame-list #'display-graphic-p))))
    (with-selected-frame frame
      (let ((foreground (face-foreground 'default nil t))
            (region-background
             (suderman/theme-blend 'font-lock-function-name-face 0.4))
            (grab-background
             (suderman/theme-blend 'font-lock-keyword-face 0.3))
            (match-accent (face-foreground 'font-lock-builtin-face nil t)))
        (when (and (stringp foreground) region-background)
          (set-face-attribute 'region nil
                              :foreground foreground
                              :background region-background
                              :extend t))
        (when (and (stringp foreground) grab-background)
          (set-face-attribute 'secondary-selection nil
                              :foreground foreground
                              :background grab-background
                              :extend t))
        (when (and (facep 'meow-search-highlight)
                   (stringp match-accent))
          (set-face-attribute 'meow-search-highlight nil
                              :inherit nil
                              :foreground 'unspecified
                              :background 'unspecified
                              :underline match-accent))
        (when (fboundp 'meow--prepare-face)
          (meow--prepare-face))))))

(defun suderman/apply-tty-menu-faces (&optional _)
  "Derive terminal menu faces from the active theme."
  (dolist (frame (frame-list))
    (unless (display-graphic-p frame)
      (let ((foreground (face-foreground 'default frame t))
            (background (face-background 'highlight frame t))
            (disabled-foreground (face-foreground 'shadow frame t))
            (selected-background (face-background 'region frame t)))
        (when (and (stringp foreground)
                   (stringp background)
                   (stringp disabled-foreground)
                   (stringp selected-background))
          (set-face-attribute 'menu frame
                              :foreground foreground
                              :background background
                              :inverse-video nil)
          (set-face-attribute 'tty-menu-enabled-face frame
                              :foreground foreground
                              :background background)
          (set-face-attribute 'tty-menu-disabled-face frame
                              :foreground disabled-foreground
                              :background background)
          (set-face-attribute 'tty-menu-selected-face frame
                              :foreground foreground
                              :background selected-background
                              :inverse-video nil))))))

(add-hook 'enable-theme-functions #'suderman/apply-selection-faces t)
(add-hook 'enable-theme-functions #'suderman/apply-tty-menu-faces t)
(suderman/apply-selection-faces)
(suderman/apply-tty-menu-faces)
(with-eval-after-load 'meow
  (suderman/apply-selection-faces))

(defun suderman/hl-line-range ()
  "Return the current line range, except in one-line file buffers."
  (let ((single-line-file
         (and buffer-file-name
              (save-restriction
                (widen)
                (save-excursion
                  (goto-char (point-min))
                  (not (and (search-forward "\n" nil t)
                            (< (point) (point-max)))))))))
    (unless single-line-file
      (cons (line-beginning-position)
            (line-beginning-position 2)))))

(defun suderman/disable-line-numbers-in-special-mode ()
  "Disable line numbers in the current special or image buffer."
  (display-line-numbers-mode -1))

(defun suderman/disable-line-numbers-in-special-buffers ()
  "Disable line numbers in existing special and image buffers."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'special-mode 'image-mode)
        (suderman/disable-line-numbers-in-special-mode)))))

(defun suderman/toggle-line-numbers ()
  "Toggle line numbers globally, preserving special and image exclusions."
  (interactive)
  (if global-display-line-numbers-mode
      (global-display-line-numbers-mode -1)
    (global-display-line-numbers-mode 1)
    (suderman/disable-line-numbers-in-special-buffers)))

(defun suderman/disable-line-numbers-in-meow-cheatsheet (&rest _)
  "Disable line numbers in Meow's read-only cheatsheet."
  (display-line-numbers-mode -1))

(defun suderman/meow-describe-keymap-without-line-numbers (function keymap)
  "Call FUNCTION with KEYMAP without a line-number gutter."
  (let ((line-numbers display-line-numbers))
    (setq display-line-numbers nil)
    (unwind-protect
        (funcall function keymap)
      (setq display-line-numbers line-numbers))))

(setq-default hl-line-range-function #'suderman/hl-line-range)
(global-hl-line-mode 1)
(add-hook 'special-mode-hook #'suderman/disable-line-numbers-in-special-mode)
(add-hook 'image-mode-hook #'suderman/disable-line-numbers-in-special-mode)
(global-display-line-numbers-mode 1)
(suderman/disable-line-numbers-in-special-buffers)
(with-eval-after-load 'meow-cheatsheet
  (advice-add 'meow-cheatsheet :after
              #'suderman/disable-line-numbers-in-meow-cheatsheet))
(with-eval-after-load 'meow-keypad
  (advice-add 'meow-describe-keymap :around
              #'suderman/meow-describe-keymap-without-line-numbers))
(setq-default display-fill-column-indicator-column 100)
(global-display-fill-column-indicator-mode 1)

(use-package doom-modeline
  :demand t
  :init
  (setq doom-modeline-modal-icon nil
        doom-modeline-buffer-file-name-style 'relative-to-project
        doom-modeline-buffer-encoding 'nondefault)
  :config
  (doom-modeline-mode 1))

(suderman/set-nerd-font-fallbacks)
(suderman/apply-gui-appearance)
(add-hook 'after-make-frame-functions #'suderman/apply-selection-faces)
(add-hook 'after-make-frame-functions #'suderman/apply-tty-menu-faces)
(add-hook 'after-make-frame-functions #'suderman/apply-gui-appearance)

(provide 'suderman-appearance)
;;; suderman-appearance.el ends here
