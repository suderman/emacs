;;; suderman-defaults-test.el --- Focused default behavior checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'suderman-defaults)

(ert-deftest suderman/visual-line-mode-defaults-to-prose-buffers ()
  (should-not global-visual-line-mode)
  (with-temp-buffer
    (text-mode)
    (should visual-line-mode))
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not visual-line-mode)))

(ert-deftest suderman/so-long-keeps-long-code-writable-and-cheap-to-display ()
  (with-temp-buffer
    (insert (make-string (1+ so-long-threshold) ?x) "\n")
    (setq buffer-file-name "/tmp/suderman-so-long.el")
    (let ((so-long-invisible-buffer-function nil))
      (set-auto-mode))
    (should so-long-minor-mode)
    (should (derived-mode-p 'emacs-lisp-mode))
    (should-not buffer-read-only)
    (should-not visual-line-mode)
    (should-not display-fill-column-indicator-mode)
    (should-not (bound-and-true-p indent-bars-mode)))
  (with-temp-buffer
    (insert "(message \"short\")\n")
    (setq buffer-file-name "/tmp/suderman-short.el")
    (let ((so-long-invisible-buffer-function nil))
      (set-auto-mode))
    (should-not (bound-and-true-p so-long-minor-mode))
    (should (derived-mode-p 'emacs-lisp-mode))))

(provide 'suderman-defaults-test)
;;; suderman-defaults-test.el ends here
