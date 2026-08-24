;;; suderman-git-test.el --- Focused Git integration checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-git-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'magit)
(require 'suderman-git)
(require 'suderman-keys)

(defun suderman/git-test--run (directory &rest arguments)
  "Run Git with ARGUMENTS in DIRECTORY and return its exit status."
  (let ((default-directory directory))
    (apply #'process-file "git" nil nil nil arguments)))

(ert-deftest suderman/git-leader-map-is-project-aware ()
  (should (eq (lookup-key suderman/leader-git-map (kbd "v"))
              #'magit-status))
  (should (eq (lookup-key suderman/leader-git-map (kbd "d"))
              #'magit-diff-buffer-file))
  (should (eq (lookup-key suderman/leader-git-hunk-map (kbd "s"))
              #'diff-hl-stage-current-hunk))
  (should (eq (lookup-key suderman/leader-git-conflict-map (kbd "u"))
              #'smerge-keep-upper))
  (should (eq (lookup-key suderman/leader-git-conflict-map (kbd "l"))
              #'smerge-keep-lower)))

(ert-deftest suderman/git-prefix-enters-through-meow-keypad ()
  (let (called)
    (cl-letf (((symbol-function 'magit-status)
               (lambda ()
                 (interactive)
                 (setq called t))))
      (with-temp-buffer
        (text-mode)
        (meow-normal-mode 1)
        (execute-kbd-macro (kbd "SPC v v"))
        (should called)))))

(ert-deftest suderman/magit-uses-native-keys-with-shared-window-commands ()
  (dolist (mode '(magit-status-mode
                  magit-diff-mode
                  magit-log-mode
                  magit-revision-mode))
    (with-temp-buffer
      (funcall mode)
      (should-not (bound-and-true-p meow-mode))
      (should (memq #'suderman/magit-disable-meow meow-mode-hook))
      (should (eq (key-binding (kbd "j")) #'magit-section-forward))
      (should (eq (key-binding (kbd "k")) #'magit-section-backward))
      (should (eq (key-binding (kbd "n")) #'magit-section-forward))
      (should (eq (key-binding (kbd "p")) #'magit-section-backward))
      (should (eq (key-binding (kbd "h")) #'magit-dispatch))
      (should (eq (key-binding (kbd "l")) #'magit-log))
      (should (eq (key-binding (kbd ",")) #'magit-mode-bury-buffer))
      (should (eq (key-binding (kbd "M-w")) #'suderman/delete-window-or-tab))
      (should (eq (key-binding (kbd "M-z")) #'suderman/zoom-window-toggle)))))

(ert-deftest suderman/git-refresh-and-live-diff-hooks-are-enabled-once ()
  (should global-diff-hl-mode)
  (should diff-hl-flydiff-mode)
  (should (= (cl-count #'magit-after-save-refresh-status
                       (default-value 'after-save-hook))
             1))
  (should (= (cl-count #'diff-hl-magit-post-refresh magit-post-refresh-hook) 1)))

(ert-deftest suderman/transient-escape-quits-without-replacing-meta-prefix ()
  (should (eq (lookup-key transient-base-map (kbd "<escape>"))
              #'transient-quit-one))
  (should (keymapp (lookup-key transient-base-map (kbd "ESC"))))
  (should (eq (lookup-key transient-base-map (kbd "ESC ESC ESC"))
              #'transient-quit-all)))

(ert-deftest suderman/diff-hl-stages-and-unstages-a-real-hunk ()
  (let* ((directory (make-temp-file "suderman-git-test-" t))
         (file (expand-file-name "sample.txt" directory))
         buffer)
    (unwind-protect
        (progn
          (should (zerop (suderman/git-test--run directory "init" "-q")))
          (write-region "one\n" nil file nil 'silent)
          (should (zerop (suderman/git-test--run directory "add" "sample.txt")))
          (should
           (zerop
            (suderman/git-test--run
             directory "-c" "user.name=Test" "-c" "user.email=test@example.com"
             "commit" "-qm" "initial")))
          (let ((window (selected-window))
                (magit-save-repository-buffers nil)
                status-buffer)
            (save-window-excursion
              (setq status-buffer (magit-status-setup-buffer directory))
              (should (eq (selected-window) window))
              (should (eq (current-buffer) status-buffer)))
            (kill-buffer status-buffer))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "two\n")
            (save-buffer)
            (diff-hl-mode 1)
            (diff-hl-update)
            (should (seq-some (lambda (overlay)
                                (overlay-get overlay 'diff-hl))
                              (overlays-in (point-min) (point-max))))
            (forward-line -1)
            (diff-hl-stage-current-hunk)
            (should (= (suderman/git-test--run
                        directory "diff" "--cached" "--quiet")
                       1))
            (diff-hl-unstage-file)
            (should (zerop (suderman/git-test--run
                            directory "diff" "--cached" "--quiet")))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

;;; suderman-git-test.el ends here
