;;; suderman-images-test.el --- Focused Image mode checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-images-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'ert)
(require 'image-mode)
(require 'suderman-images)

(ert-deftest suderman/image-copy-sends-static-image-data-with-its-mime-type ()
  (with-temp-buffer
    (setq-local buffer-file-name "/tmp/example.png")
    (let (call)
      (cl-letf (((symbol-function 'file-readable-p) (lambda (_) t))
                ((symbol-function 'file-remote-p) (lambda (_) nil))
                ((symbol-function 'mailcap-file-name-to-mime-type)
                 (lambda (_) "image/png"))
                ((symbol-function 'executable-find) (lambda (_) "/bin/wl-copy"))
                ((symbol-function 'call-process)
                 (lambda (&rest arguments)
                   (setq call arguments)
                   0)))
        (suderman/image-copy-to-clipboard))
      (should (equal call '("wl-copy" "/tmp/example.png" nil nil
                            "--type" "image/png"))))))

(ert-deftest suderman/image-copy-sends-gifs-as-local-files ()
  (with-temp-buffer
    (setq-local buffer-file-name "/tmp/example gif.gif")
    (let (call)
      (cl-letf (((symbol-function 'file-readable-p) (lambda (_) t))
                ((symbol-function 'file-remote-p) (lambda (_) nil))
                ((symbol-function 'mailcap-file-name-to-mime-type)
                 (lambda (_) "image/gif"))
                ((symbol-function 'executable-find) (lambda (_) "/bin/wl-copy"))
                ((symbol-function 'call-process)
                 (lambda (&rest arguments)
                   (setq call arguments)
                   0)))
        (suderman/image-copy-to-clipboard))
      (should (equal call '("wl-copy" nil nil nil
                            "--type" "text/uri-list"
                            "file:///tmp/example%20gif.gif"))))))

(ert-deftest suderman/image-copy-requires-a-local-image-file ()
  (with-temp-buffer
    (should-error (suderman/image-copy-to-clipboard) :type 'user-error))
  (with-temp-buffer
    (setq-local buffer-file-name "/tmp/example.txt")
    (cl-letf (((symbol-function 'file-readable-p) (lambda (_) t))
              ((symbol-function 'file-remote-p) (lambda (_) nil))
              ((symbol-function 'mailcap-file-name-to-mime-type)
               (lambda (_) "text/plain")))
      (should-error (suderman/image-copy-to-clipboard) :type 'user-error))))

(ert-deftest suderman/image-mode-owns-navigation-and-transform-bindings ()
  (dolist (binding '(("," . suderman/ibuffer-toggle)
                     ("." . suderman/dirvish)
                     ("c" . suderman/image-copy-to-clipboard)
                     ("n" . suderman/image-next-file)
                     ("p" . suderman/image-previous-file)
                     ("=" . image-increase-size)
                     ("+" . image-increase-size)
                     ("-" . image-decrease-size)
                     ("r" . image-rotate)
                     ("R" . suderman/image-rotate-counterclockwise)
                     ("0" . image-transform-reset-to-initial)))
    (should (eq (lookup-key image-mode-map (kbd (car binding)))
                (cdr binding))))
  (should image-animate-loop)
  (should (memq #'suderman/image-mode-setup image-mode-hook))
  (should (memq #'suderman/image-mode-setup find-file-hook))
  (should-not (lookup-key meow-motion-state-keymap (kbd "c"))))

(provide 'suderman-images-test)
;;; suderman-images-test.el ends here
