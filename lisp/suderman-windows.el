;;; suderman-windows.el --- Window movement and split helpers -*- lexical-binding: t; -*-

;;; Commentary:
;; Small commands used from modal and leader maps.  They intentionally wrap core
;; Emacs window functions so keybindings read like intent instead of plumbing.

;;; Code:

(require 'subr-x)
(require 'tab-bar)
(require 'use-package)
(require 'windmove)

(setq windmove-allow-all-windows t)

(use-package scroll-on-jump
  :demand t
  :custom
  (scroll-on-jump-duration 0.2)
  (scroll-on-jump-curve 'linear)
  :config
  (scroll-on-jump-with-scroll-advice-add scroll-up-command)
  (scroll-on-jump-with-scroll-advice-add scroll-down-command)
  (scroll-on-jump-with-scroll-advice-add recenter-top-bottom)
  (scroll-on-jump-advice-add beginning-of-buffer)
  (scroll-on-jump-advice-add end-of-buffer)
  (scroll-on-jump-advice-add next-error)
  (scroll-on-jump-advice-add previous-error)
  (scroll-on-jump-advice-add pop-to-mark-command)
  (scroll-on-jump-advice-add pop-global-mark)
  (scroll-on-jump-advice-add xref-go-back)
  (scroll-on-jump-advice-add xref-go-forward)
  (with-eval-after-load 'suderman-meow
    (scroll-on-jump-advice-add suderman/meow-buffer-beginning)
    (scroll-on-jump-advice-add suderman/meow-buffer-end)
    (scroll-on-jump-advice-add meow-goto-line)
    (scroll-on-jump-advice-add suderman/meow-search)))

(defvar zoom-window-mode-line-color)

(use-package zoom-window
  :commands zoom-window-zoom)

(defun suderman/zoom-window-toggle ()
  "Toggle the selected window's zoomed layout."
  (interactive)
  (let ((zoom-window-mode-line-color
         (or (suderman/theme-blend 'success 0.2)
             (face-background 'mode-line nil t))))
    (zoom-window-zoom)
    (when (frame-parameter (selected-frame) 'zoom-window-enabled)
      ;; `delete-other-windows' preserves side windows after zoom saves the layout.
      (dolist (window (delq (selected-window) (window-list)))
        (delete-window window)))))

(defun suderman/window-left ()
  "Move focus to the window left of the selected window."
  (interactive)
  (windmove-left))

(defun suderman/window-previous ()
  "Move focus to the previously selected window."
  (interactive)
  (other-window -1))

(defun suderman/delete-window-or-tab ()
  "Delete the selected window, or close its tab when it is the only window."
  (interactive)
  (cond
   ((not (one-window-p t))
    (delete-window))
   ((> (length (tab-bar-tabs (selected-frame))) 1)
    (tab-bar-close-tab))
   (t
    (user-error "Cannot delete the only window in the only tab"))))

(defun suderman/shrink-window-width ()
  "Shrink the selected window horizontally."
  (interactive)
  (shrink-window-horizontally 5))

(defun suderman/enlarge-window-width ()
  "Enlarge the selected window horizontally."
  (interactive)
  (enlarge-window-horizontally 5))

(defun suderman/enlarge-window-height ()
  "Enlarge the selected window vertically."
  (interactive)
  (enlarge-window 3))

(defun suderman/shrink-window-height ()
  "Shrink the selected window vertically."
  (interactive)
  (shrink-window 3))

(defun suderman/resize-window-in-direction (direction)
  "Move a window divider in DIRECTION, favoring the selected window's edge."
  (let* ((horizontal (memq direction '(left right)))
         (amount (if horizontal 5 3))
         (window (selected-window))
         (delta (if (memq direction '(left above)) (- amount) amount))
         (forward (if horizontal 'right 'below))
         (backward (if horizontal 'left 'above)))
    (if (window-in-direction forward window)
        (adjust-window-trailing-edge window delta horizontal)
      (if-let* ((neighbor (window-in-direction backward window)))
          (adjust-window-trailing-edge neighbor delta horizontal)
        (user-error "No neighboring window")))))

(defun suderman/resize-window-left ()
  "Move a vertical window divider left."
  (interactive)
  (suderman/resize-window-in-direction 'left))

(defun suderman/resize-window-down ()
  "Move a horizontal window divider down."
  (interactive)
  (suderman/resize-window-in-direction 'below))

(defun suderman/resize-window-up ()
  "Move a horizontal window divider up."
  (interactive)
  (suderman/resize-window-in-direction 'above))

(defun suderman/resize-window-right ()
  "Move a vertical window divider right."
  (interactive)
  (suderman/resize-window-in-direction 'right))

(defun suderman/split-window-below-and-focus ()
  "Split the selected window below and focus the new window."
  (interactive)
  (select-window (split-window-below)))

(defun suderman/split-window-right-and-focus ()
  "Split the selected window right and focus the new window."
  (interactive)
  (select-window (split-window-right)))

(provide 'suderman-windows)
;;; suderman-windows.el ends here
