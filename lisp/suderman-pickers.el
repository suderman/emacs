;;; suderman-pickers.el --- High-level picker commands -*- lexical-binding: t; -*-

;;; Commentary:
;; Commands that compose completion sources into Suderman's preferred picker flow.
;; Package setup stays in suderman-completion; this file owns behavior.

;;; Code:

(require 'suderman-completion)
(require 'suderman-projects)

(defun suderman/picker-minibuffer-setup ()
  "Use Vim-style navigation in a picker selection minibuffer."
  (let ((map (copy-keymap (current-local-map))))
    (define-key map (kbd "j") #'vertico-next)
    (define-key map (kbd "k") #'vertico-previous)
    (define-key map (kbd "l") #'vertico-exit)
    (define-key map (kbd "RET") #'vertico-exit)
    (use-local-map map)))

(defun suderman/alternate-buffer ()
  "Switch to the most recent alternate buffer."
  (interactive)
  (let ((buffer (other-buffer (current-buffer) t)))
    (if buffer
        (switch-to-buffer buffer)
      (user-error "No alternate buffer"))))

(defun suderman/smart-picker ()
  "Pick a high-level source, then launch its picker."
  (interactive)
  (let* ((actions `(("buffers" . consult-buffer)
                    ("files" . suderman/find-file)
                    ("grep" . consult-ripgrep)
                    ("recent" . consult-recent-file)
                    ("commands" . execute-extended-command)
                    ("command history" . consult-complex-command)
                    ("line" . consult-line)
                    ("symbols" . consult-imenu)
                    ("keymaps" . describe-bindings)
                    ("explorer" . dirvish-side)))
         (choice (let ((vertico-sort-override-function #'identity))
                   (minibuffer-with-setup-hook
                       (:append #'suderman/picker-minibuffer-setup)
                     (completing-read "Picker: "
                                      (mapcar #'car actions)
                                      nil
                                      t)))))
    (call-interactively (cdr (assoc choice actions)))))

(provide 'suderman-pickers)
;;; suderman-pickers.el ends here
