;;; suderman-terminal-test.el --- Checks for Ghostel integration -*- lexical-binding: t; -*-

(require 'ert)
(require 'suderman-terminal)

(ert-deftest suderman/ghostel-preserves-emacs-escape-keys ()
  (dolist (key '("C-c" "C-x" "C-u" "C-h" "M-x" "M-:" "C-\\"
                 "M-h" "M-j" "M-k" "M-l" "M-H" "M-J" "M-K" "M-L"))
    (should (member key ghostel-keymap-exceptions))))

(ert-deftest suderman/ghostel-preserves-window-bindings ()
  (dolist (binding '(("M-h" . suderman/window-left)
                     ("M-j" . windmove-down)
                     ("M-k" . windmove-up)
                     ("M-l" . windmove-right)
                     ("M-H" . suderman/resize-window-left)
                     ("M-J" . suderman/resize-window-down)
                     ("M-K" . suderman/resize-window-up)
                     ("M-L" . suderman/resize-window-right)))
    (should (eq (lookup-key ghostel-semi-char-mode-map (kbd (car binding)))
                (cdr binding)))))

(ert-deftest suderman/ghostel-and-meow-share-modal-state ()
  (with-temp-buffer
    (ghostel-mode)
    (should (meow-insert-mode-p))
    (ghostel-copy-mode)
    (should (eq ghostel--input-mode 'copy))
    (should (meow-normal-mode-p))
    (suderman/meow-insert)
    (should (eq ghostel--input-mode 'semi-char))
    (should (meow-insert-mode-p))))

(ert-deftest suderman/ghostel-has-project-leader-binding ()
  (should (eq (lookup-key suderman/meow-leader-map (kbd "RET"))
              #'ghostel-project)))

(provide 'suderman-terminal-test)
;;; suderman-terminal-test.el ends here
