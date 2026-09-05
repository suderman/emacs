;;; suderman-appearance.el --- Fonts and frame appearance -*- lexical-binding: t; -*-

;;; Commentary:
;; GUI-only appearance that needs to apply to both the first frame and later
;; daemon/client frames.  early-init.el sets matching frame opacity before this
;; module loads.

;;; Code:

(require 'color)
(require 'use-package)

(defvar base16-theme-256-color-source)

(declare-function suderman/dashboard "suderman-dashboard")
(declare-function suderman/dirvish "suderman-files")
(declare-function suderman/ibuffer-toggle "suderman-buffers")

(defconst suderman/font-family "JetBrainsMono Nerd Font Mono")
(defconst suderman/nerd-symbol-font "Symbols Nerd Font Mono")
(defconst suderman/background-opacity 90)

(defun suderman/default-font-size ()
  "Return the platform's default `font-spec' size."
  ;; A floating-point font size is measured in points; an integer is pixels.
  (if (eq system-type 'android) 17.0 11))

(defun suderman/nerd-fonts-available-p (&optional frame)
  "Return non-nil when FRAME can display the configured Nerd Fonts."
  (or (not (eq system-type 'android))
      (and (display-graphic-p frame)
           (find-font (font-spec :family suderman/font-family) frame)
           (find-font (font-spec :family suderman/nerd-symbol-font) frame))))

(defun suderman/mode-line-navigation-segments ()
  "Return navigation segments appropriate for the current platform."
  (append '(suderman-dashboard)
          (unless (eq system-type 'android)
            '(suderman-dirvish suderman-ibuffer))))

;; Emacs 31 rejects the Gnus inheritance cycles created by base16-theme
;; 20260419.235 and upstream main as of 2026-08-25.  Remove this when the empty
;; Gnus faces inherit their corresponding outline faces instead of the
;; non-empty faces:
;; https://github.com/tinted-theming/base16-emacs/blob/main/base16-theme.el
(defun suderman/base16-theme-set-faces-without-gnus-cycles
    (function theme colors faces)
  "Call FUNCTION for THEME and COLORS with safe Gnus FACES."
  (funcall
   function theme colors
   (mapcar
    (lambda (face)
      (let* ((name (symbol-name (car face)))
             (base-face
              (when (string-match
                     "\\`\\(gnus-group-\\(?:mail\\|news\\)-[1-6]\\)-empty\\'"
                     name)
                (intern (match-string 1 name))))
             (base-spec (assq base-face faces))
             (inherit (plist-get (cdr base-spec) :inherit)))
        (if inherit
            (cons (car face)
                  (plist-put (copy-sequence (cdr face)) :inherit inherit))
          face)))
    faces)))

(with-eval-after-load 'base16-theme
  ;; Do not trust an SSH client's ANSI palette to match Stylix.  In a
  ;; 256-color terminal, translate the active theme's actual colors instead.
  (setq base16-theme-256-color-source 'colors)
  (advice-remove 'base16-theme-set-faces
                 #'suderman/base16-theme-set-faces-without-gnus-cycles)
  (advice-add 'base16-theme-set-faces :around
              #'suderman/base16-theme-set-faces-without-gnus-cycles))

(defun suderman/apply-default-font ()
  "Apply the platform font fallback unless Stylix already owns it."
  (unless (memq 'base16-stylix custom-enabled-themes)
    (if (suderman/nerd-fonts-available-p)
        (set-face-attribute 'default nil :font
                            (font-spec :family suderman/font-family
                                       :size (suderman/default-font-size)))
      (when (eq system-type 'android)
        (set-face-attribute 'default nil
                            :height (round
                                     (* 10 (suderman/default-font-size))))))))

;; Stylix's default.el loads after init.el and replaces this fallback when
;; enabled.  Avoid overriding it on systems where it loads earlier instead.
(suderman/apply-default-font)

(defun suderman/set-nerd-font-fallbacks ()
  "Teach Emacs where Nerd Font private-use icons live."
  (when (suderman/nerd-fonts-available-p)
    (dolist (range (list (cons #xe000 #xf8ff)
                         (cons #xf0000 #xffffd)
                         (cons #x100000 #x10fffd)))
      (set-fontset-font t range
                        (font-spec :family suderman/nerd-symbol-font)
                        nil 'prepend))))

(defun suderman/apply-gui-appearance (&optional frame)
  "Apply GUI background opacity to FRAME."
  (let ((target-frame (or frame (selected-frame))))
    (when (and (display-graphic-p target-frame)
               (not (eq system-type 'android)))
      (set-frame-parameter target-frame 'alpha-background
                           suderman/background-opacity))))

(defun suderman/frame-text-scale-adjust (delta)
  "Adjust the selected graphical frame's text size by DELTA points."
  (let ((frame (selected-frame)))
    (unless (display-graphic-p frame)
      (user-error "Text scaling requires a graphical frame"))
    ;; PGTK rounds rendered font sizes, so track the requested height instead.
    (let* ((state
            (or (frame-parameter frame 'suderman/frame-text-scale-state)
                (let ((height
                       (face-attribute 'default :height frame 'default)))
                  (list height (frame-parameter frame 'font) height))))
           (base-height (nth 0 state))
           (base-font (nth 1 state))
           (new-height (+ (nth 2 state) (* delta 10))))
      (when (< 10 new-height 500)
        (set-frame-parameter
         frame 'suderman/frame-text-scale-state
         (list base-height base-font new-height))
        (if (= new-height base-height)
            (set-frame-font base-font t nil t)
          (set-face-attribute 'default frame :height new-height))))))

(defun suderman/frame-text-scale-decrease ()
  "Decrease text size in the selected graphical frame by one point."
  (interactive)
  (suderman/frame-text-scale-adjust -1))

(defun suderman/frame-text-scale-increase ()
  "Increase text size in the selected graphical frame by one point."
  (interactive)
  (suderman/frame-text-scale-adjust 1))

(unless (eq system-type 'android)
  (add-to-list 'default-frame-alist
               `(alpha-background . ,suderman/background-opacity))
  (add-to-list 'initial-frame-alist
               `(alpha-background . ,suderman/background-opacity)))

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
(add-hook 'window-setup-hook #'suderman/apply-tty-menu-faces)
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

(use-package indent-bars
  :hook ((prog-mode conf-mode toml-ts-mode yaml-ts-mode html-ts-mode)
         . indent-bars-mode)
  :custom
  (indent-bars-color '(line-number :blend 1))
  (indent-bars-color-by-depth nil)
  (indent-bars-highlight-current-depth nil)
  (indent-bars-pattern ".")
  (indent-bars-width-frac 0.1)
  (indent-bars-pad-frac 0.1)
  (indent-bars-starting-column 0)
  (indent-bars-display-on-blank-lines 'least))

(defun suderman/dashboard-from-mode-line (event)
  "Open Dashboard for the window whose mode line EVENT clicked."
  (interactive "e")
  (select-window (posn-window (event-start event)))
  (suderman/dashboard))

(defun suderman/dirvish-from-mode-line (event)
  "Open Dirvish for the window whose mode line EVENT clicked."
  (interactive "e")
  (select-window (posn-window (event-start event)))
  (suderman/dirvish))

(defun suderman/ibuffer-from-mode-line (event)
  "Open IBuffer for the window whose mode line EVENT clicked."
  (interactive "e")
  (select-window (posn-window (event-start event)))
  (suderman/ibuffer-toggle))

(with-eval-after-load 'dirvish
  (advice-remove 'dirvish--setup-mode-line
                 'suderman/dirvish-use-doom-modeline))

(use-package doom-modeline
  :demand t
  :init
  (when (and (eq system-type 'android)
             (not (suderman/nerd-fonts-available-p)))
    (setq doom-modeline-icon nil))
  (setq doom-modeline-modal-icon nil
        doom-modeline-buffer-file-name-style 'relative-to-project
        doom-modeline-buffer-encoding 'nondefault)
  :config
  (doom-modeline-def-segment suderman-dashboard
    "Clickable Dashboard button."
    (propertize (concat " "
                       (doom-modeline-icon 'codicon "nf-cod-dashboard" "D" "D"
                                            :face (doom-modeline-face))
                       " ")
                'mouse-face 'doom-modeline-highlight
                'help-echo "mouse-1: Open Dashboard"
                'local-map (let ((map (make-sparse-keymap)))
                             (define-key map [mode-line mouse-1]
                                         #'suderman/dashboard-from-mode-line)
                             map)))
  (doom-modeline-def-segment suderman-dirvish
    "Clickable Dirvish button."
    (propertize (concat " "
                       (doom-modeline-icon 'codicon "nf-cod-folder" "🗀" "D"
                                            :face (doom-modeline-face))
                       " ")
                'mouse-face 'doom-modeline-highlight
                'help-echo "mouse-1: Toggle Dirvish"
                'local-map (let ((map (make-sparse-keymap)))
                             (define-key map [mode-line mouse-1]
                                         #'suderman/dirvish-from-mode-line)
                             map)))
  (doom-modeline-def-segment suderman-ibuffer
    "Clickable IBuffer button."
    (propertize (concat " "
                       (doom-modeline-icon 'codicon "nf-cod-files" "🗎" "B"
                                            :face (doom-modeline-face))
                       " ")
                'mouse-face 'doom-modeline-highlight
                'help-echo "mouse-1: Toggle IBuffer"
                'local-map (let ((map (make-sparse-keymap)))
                             (define-key map [mode-line mouse-1]
                                         #'suderman/ibuffer-from-mode-line)
                             map)))
  (doom-modeline-remove-segment 'suderman-dashboard)
  (doom-modeline-remove-segment 'suderman-dirvish)
  (doom-modeline-remove-segment 'suderman-ibuffer)
  (let ((anchor 'bar))
    (dolist (segment (suderman/mode-line-navigation-segments))
      (doom-modeline-add-segment segment anchor :after)
      (setq anchor segment)))
  (doom-modeline-mode 1))

(suderman/set-nerd-font-fallbacks)
(suderman/apply-gui-appearance)
(add-hook 'after-make-frame-functions #'suderman/apply-selection-faces)
(add-hook 'after-make-frame-functions #'suderman/apply-tty-menu-faces)
(add-hook 'after-make-frame-functions #'suderman/apply-gui-appearance)

(provide 'suderman-appearance)
;;; suderman-appearance.el ends here
