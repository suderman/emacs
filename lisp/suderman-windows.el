;;; suderman-windows.el --- Window movement and split helpers -*- lexical-binding: t; -*-

;;; Commentary:
;; Small commands used from Evil and leader maps.  They intentionally wrap core
;; Emacs window functions so keybindings read like intent instead of plumbing.

;;; Code:

(require 'subr-x)

(defun suderman/window-left-or-treemacs ()
  "Move focus left, falling back to a visible Treemacs side window."
  (interactive)
  (condition-case nil
      (windmove-left)
    (user-error
     (if-let ((window (and (fboundp 'treemacs-get-local-window)
                           (treemacs-get-local-window))))
         (select-window window)
       (user-error "No window left from selected window")))))

(defun suderman/window-previous ()
  "Move focus to the previously selected window."
  (interactive)
  (other-window -1))

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
