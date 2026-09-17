;;; suderman-formatting-test.el --- Focused formatting checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'suderman-formatting)

(ert-deftest suderman/treefmt-uses-the-source-buffer-environment ()
  (let* ((directory (make-temp-file "suderman-treefmt-" t))
         (source-file (expand-file-name "sample.nix" directory))
         (source (generate-new-buffer " *suderman-treefmt-source*"))
         (scratch (generate-new-buffer " *suderman-treefmt-scratch*"))
         captured callback-called)
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "treefmt.nix" directory))
          (with-current-buffer source
            (setq buffer-file-name source-file)
            (setq-local exec-path '("/source/bin"))
            (setq-local process-environment '("SOURCE_ENV=1")))
          (with-current-buffer scratch
            (insert "{ value = true; }\n"))
          (cl-letf (((symbol-function 'process-file)
                     (lambda (&rest _)
                       (setq captured
                             (list exec-path process-environment
                                   default-directory))
                       0)))
            (suderman/formatting-treefmt
             :buffer source
             :scratch scratch
             :callback (lambda (&optional error)
                         (should-not error)
                         (setq callback-called t))))
          (should callback-called)
          (should (equal captured
                         (list '("/source/bin") '("SOURCE_ENV=1")
                               (file-name-as-directory directory)))))
      (kill-buffer source)
      (kill-buffer scratch)
      (delete-directory directory t))))

(provide 'suderman-formatting-test)
;;; suderman-formatting-test.el ends here
