;;; suderman-toolbar.el --- Touch-friendly toolbar -*- lexical-binding: t; -*-

;;; Commentary:
;; A bottom toolbar with sticky Ctrl and Meta, previous and next buffer,
;; IBuffer, Dirvish, search, the software keyboard (the Meow keypad on
;; desktop), Tab, and Escape.  Both draw the theme-colored SVG icons in
;; assets/toolbar.  F9 toggles it.

;;; Code:

(defvar meow-normal-state-keymap)
(defvar modifier-bar-modifier-list)
(defvar overriding-text-conversion-style)
(defvar text-conversion-style)

(declare-function set-text-conversion-style "textconv.c"
                  (style &optional keep-selection))
(declare-function tool-bar-apply-modifiers "tool-bar" (event modifiers))

(defun suderman/tool-bar-image (name &optional active)
  "Return a theme-aware tool-bar image expression for NAME.
ACTIVE draws the icon cut out of a filled tile to show a latched modifier."
  (let ((file (expand-file-name (format "assets/toolbar/%s.svg" name)
                                user-emacs-directory))
        (size (if (featurep 'android) 56 24))
        ;; Android would otherwise scale the pixel size by screen density.
        (props (append (and (featurep 'android) '(:scale 1))
                       (list :foreground (face-foreground 'tool-bar nil t)
                             :background (face-background 'tool-bar nil t)))))
    ;; tool-bar.el masks the background color, so the tile must not reach the
    ;; corners and the cut-out icon must use the background color too.
    (if active
        `(create-image
          ,(format "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" \
height=\"24\"><mask id=\"m\"><rect width=\"24\" height=\"24\" \
fill=\"white\"/><svg x=\"3\" y=\"3\" width=\"18\" height=\"18\" \
viewBox=\"0 0 24 24\">%s</svg></mask><rect width=\"24\" height=\"24\" \
rx=\"5\" fill=\"currentColor\" mask=\"url(#m)\"/></svg>"
                   (with-temp-buffer
                     (insert-file-contents file)
                     (string-replace "currentColor" "black" (buffer-string))))
          'svg t :width ,size :height ,size ,@props)
      `(create-image ,file 'svg nil :width ,size :height ,size ,@props))))

(defun suderman/tool-bar-state-images (name)
  "Return platform-appropriate state images for toolbar item NAME."
  ;; GTK rejects the four-image state vectors supported by Android, so select
  ;; one image dynamically before GTK validates it.
  (if (not (featurep 'android))
      `(if (memq ',(intern name) modifier-bar-modifier-list)
           ,(suderman/tool-bar-image name t)
         ,(suderman/tool-bar-image name))
    (let ((active (eval (suderman/tool-bar-image name t) t))
          (normal (eval (suderman/tool-bar-image name) t)))
      (vector active normal active normal))))

(defun suderman/tool-bar-refresh ()
  "Rebuild the toolbar after its dynamic modifier state changes."
  (tool-bar--flush-cache)
  (force-mode-line-update t))

(defun suderman/tool-bar-modifier-button (modifier)
  "Toggle MODIFIER while decoding the next non-toolbar event."
  (let ((old-text-conversion-style text-conversion-style)
        result)
    (when (fboundp 'set-text-conversion-style)
      (set-text-conversion-style nil))
    (unwind-protect
        (setq result
              (let ((modifier-bar-modifier-list (list modifier)))
                (frame-toggle-on-screen-keyboard nil nil)
                (suderman/tool-bar-refresh)
                (redisplay)
                (let ((modifiers (list modifier))
                      (overriding-text-conversion-style nil)
                      event modifier-event)
                  (setq event (read-event))
                  (while (and modifiers (eq event 'tool-bar))
                    (setq modifier-event (event-basic-type (read-event)))
                    (unless (memq modifier-event
                                  '(alt super hyper shift control meta))
                      (user-error "Unknown tool-bar event %s" modifier-event))
                    (if (memq modifier-event modifiers)
                        (setq modifiers (delq modifier-event modifiers)
                              modifier-bar-modifier-list
                              (delq modifier-event modifier-bar-modifier-list))
                      (push modifier-event modifiers)
                      (push modifier-event modifier-bar-modifier-list))
                    (suderman/tool-bar-refresh)
                    (redisplay)
                    (when modifiers
                      (setq event (read-event))))
                  (if modifiers
                      (vector (tool-bar-apply-modifiers event modifiers))
                    []))))
      (unless (or (not (fboundp 'set-text-conversion-style))
                  (eq old-text-conversion-style text-conversion-style))
        (set-text-conversion-style old-text-conversion-style t))
      (suderman/tool-bar-refresh))
    result))

(defun suderman/tool-bar-toggle-control (_prompt)
  "Toggle Control while decoding the next event."
  (suderman/tool-bar-modifier-button 'control))

(defun suderman/tool-bar-toggle-meta (_prompt)
  "Toggle Meta while decoding the next event."
  (suderman/tool-bar-modifier-button 'meta))

(defun suderman/tool-bar-keypad-key (button)
  "Return a decoder that gives the Meow keypad BUTTON's Normal state key."
  (lambda (_prompt)
    (when (bound-and-true-p meow-keypad-mode)
      (where-is-internal (nth 3 (assq button (cdr (default-value 'tool-bar-map))))
                         meow-normal-state-keymap t))))

(defun suderman/setup-tool-bar (&optional theme)
  "Configure the touch-friendly input toolbar idempotently.
THEME is non-nil when refreshing the toolbar after a theme change."
  (require 'tool-bar)
  (modifier-bar-mode -1)
  (customize-set-variable 'tool-bar-position 'bottom)
  (set-face-attribute 'tool-bar nil
                      :foreground (face-foreground 'default nil t)
                      :background (face-background 'default nil t))
  (setq secondary-tool-bar-map nil
        tool-bar-button-margin (if (featurep 'android) '(24 . 20) 4)
        tool-bar-style 'image
        tool-bar-always-show-default t)
  (let ((map (make-sparse-keymap)))
    (define-key-after map [control]
      `(menu-item "Ctrl" ignore
                  :image ,(suderman/tool-bar-state-images "control")
                  :button (:toggle . (memq 'control
                                            modifier-bar-modifier-list))
                  :help "Apply Control to the next key"))
    (define-key-after map [meta]
      `(menu-item "Meta" ignore
                  :image ,(suderman/tool-bar-state-images "meta")
                  :button (:toggle . (memq 'meta
                                            modifier-bar-modifier-list))
                  :help "Apply Meta to the next key")
      'control)
    (define-key-after map [suderman-previous]
      `(menu-item "Previous" previous-buffer
                  :image ,(suderman/tool-bar-image "previous")
                  :help "Previous buffer")
      'meta)
    (define-key-after map [suderman-next]
      `(menu-item "Next" next-buffer
                  :image ,(suderman/tool-bar-image "next")
                  :help "Next buffer")
      'suderman-previous)
    (define-key-after map [suderman-buffers]
      `(menu-item "Buffers" suderman/ibuffer-toggle
                  :image ,(suderman/tool-bar-image "buffers")
                  :help "Open IBuffer")
      'suderman-next)
    (define-key-after map [suderman-files]
      `(menu-item "Files" suderman/dirvish
                  :image ,(suderman/tool-bar-image "files")
                  :help "Open Dirvish")
      'suderman-buffers)
    (define-key-after map [suderman-search]
      `(menu-item "Search" suderman/meow-start-search
                  :image ,(suderman/tool-bar-image "search")
                  :help "Search the buffer")
      'suderman-files)
    ;; Desktop has no software keyboard, so the slot opens the keypad instead.
    (define-key-after map [suderman-keyboard]
      (if (featurep 'android)
          `(menu-item "Keyboard" suderman/android-toggle-keyboard
                      :image ,(suderman/tool-bar-image "keyboard")
                      :help "Show or hide the software keyboard")
        `(menu-item "Keypad" meow-keypad
                    :image ,(suderman/tool-bar-image "keypad")
                    :help "Open the Meow keypad (SPC)"))
      'suderman-search)
    (define-key-after map [suderman-tab]
      `(menu-item "Tab" ignore
                  :image ,(suderman/tool-bar-image "tab")
                  :help "Send Tab")
      'suderman-keyboard)
    (define-key-after map [suderman-escape]
      `(menu-item "Esc" suderman/meow-escape
                  :image ,(suderman/tool-bar-image "escape")
                  :help "Leave Insert state or cancel")
      'suderman-tab)
    (set-default 'tool-bar-map map))
  (define-key input-decode-map [tool-bar suderman-escape] nil)
  (define-key input-decode-map [tool-bar suderman-tab] [tab])
  (dolist (button '(suderman-buffers suderman-files suderman-search
                    suderman-previous suderman-next))
    (define-key input-decode-map (vector 'tool-bar button)
                (suderman/tool-bar-keypad-key button)))
  (define-key input-decode-map [tool-bar control]
              #'suderman/tool-bar-toggle-control)
  (define-key input-decode-map [tool-bar meta]
              #'suderman/tool-bar-toggle-meta)
  (tool-bar--flush-cache)
  (unless theme
    (tool-bar-mode 1))
  (force-mode-line-update t))

;; Terminal-only builds such as Termux have no tool bar or images.
(when (fboundp 'tool-bar-mode)
  (add-hook 'enable-theme-functions #'suderman/setup-tool-bar t)
  (suderman/setup-tool-bar))

(provide 'suderman-toolbar)
;;; suderman-toolbar.el ends here
