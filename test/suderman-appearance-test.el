;;; suderman-appearance-test.el --- Focused appearance checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-appearance-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'ert)
(require 'suderman-appearance)

(ert-deftest suderman/android-uses-nerd-fonts-only-when-both-are-available ()
  (let ((system-type 'android))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
              ((symbol-function 'find-font)
               (lambda (spec &optional _frame)
                 (equal (font-get spec :family) suderman/font-family))))
      (should-not (suderman/nerd-fonts-available-p)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
              ((symbol-function 'find-font) (lambda (&rest _) 'font)))
      (should (suderman/nerd-fonts-available-p)))))

(ert-deftest suderman/base16-gnus-faces-avoid-emacs-31-inheritance-cycles ()
  (let (faces transformed)
    (dolist (group '(mail news))
      (dotimes (index 6)
        (let* ((level (1+ index))
               (face (intern (format "gnus-group-%s-%d" group level)))
               (empty-face (intern (format "%s-empty" face)))
               (outline (intern (format "outline-%d" level))))
          (push `(,face :inherit ,outline) faces)
          (push `(,empty-face :foreground base04 :inherit ,face) faces))))
    (push '(default :foreground base05) faces)
    (let ((original (copy-tree faces)))
      (suderman/base16-theme-set-faces-without-gnus-cycles
       (lambda (_theme _colors fixed-faces)
         (setq transformed fixed-faces))
       'base16-test nil faces)
      (should (equal faces original)))
    (dolist (face transformed)
      (when (string-match
             "\\`\\(gnus-group-\\(?:mail\\|news\\)-[1-6]\\)-empty\\'"
             (symbol-name (car face)))
        (let* ((base-face (intern (match-string 1 (symbol-name (car face)))))
               (base-inherit (plist-get (cdr (assq base-face transformed)) :inherit)))
          (should (eq (plist-get (cdr face) :inherit) base-inherit)))))
    (should (equal (assq 'default transformed)
                   '(default :foreground base05)))))

(ert-deftest suderman/selection-faces-wait-for-a-graphical-frame ()
  (let ((frames nil)
        (original-region (face-background 'region nil t)))
    (cl-letf (((symbol-function 'filtered-frame-list)
               (lambda (_predicate) frames))
              ((symbol-function 'suderman/theme-blend)
               (lambda (face _alpha)
                 (if (eq face 'font-lock-function-name-face)
                     "#112233"
                   "#445566"))))
      (suderman/apply-selection-faces)
      (should (equal (face-background 'region nil t) original-region))

      (setq frames (list (selected-frame)))
      (suderman/apply-selection-faces)
      (should (equal (face-background 'region nil t) "#112233"))
      (should (equal (face-background 'secondary-selection nil t) "#445566")))))

(ert-deftest suderman/tty-menu-faces-follow-semantic-theme-faces ()
  (let ((frame (selected-frame))
        calls)
    (cl-letf (((symbol-function 'frame-list) (lambda () (list frame)))
              ((symbol-function 'display-graphic-p) (lambda (_) nil))
              ((symbol-function 'face-foreground)
               (lambda (face &rest _)
                 (pcase face
                   ('default "foreground")
                   ('shadow "disabled"))))
              ((symbol-function 'face-background)
               (lambda (face &rest _)
                 (pcase face
                   ('highlight "background")
                   ('region "selected"))))
              ((symbol-function 'set-face-attribute)
               (lambda (face target &rest attributes)
                 (push (append (list face target) attributes) calls))))
      (suderman/apply-tty-menu-faces)
      (should (member `(menu ,frame
                            :foreground "foreground"
                            :background "background"
                            :inverse-video nil)
                      calls))
      (should (member `(tty-menu-enabled-face ,frame
                                             :foreground "foreground"
                                             :background "background")
                      calls))
      (should (member `(tty-menu-disabled-face ,frame
                                              :foreground "disabled"
                                              :background "background")
                      calls))
      (should (member `(tty-menu-selected-face ,frame
                                              :foreground "foreground"
                                              :background "selected"
                                              :inverse-video nil)
                      calls)))))

(ert-deftest suderman/line-number-toggle-preserves-special-buffer-exclusions ()
  (let ((original-state global-display-line-numbers-mode)
        (text-buffer (generate-new-buffer " *suderman-line-numbers-text*"))
        (special-buffer (generate-new-buffer " *suderman-line-numbers-special*"))
        (image-buffer (generate-new-buffer " *suderman-line-numbers-image*")))
    (unwind-protect
        (progn
          (with-current-buffer text-buffer
            (text-mode))
          (with-current-buffer special-buffer
            (special-mode))
          (with-current-buffer image-buffer
            (setq major-mode 'image-mode))
          (unless global-display-line-numbers-mode
            (global-display-line-numbers-mode 1)
            (suderman/disable-line-numbers-in-special-buffers))

          (suderman/toggle-line-numbers)
          (should-not global-display-line-numbers-mode)
          (should-not (buffer-local-value 'display-line-numbers-mode text-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode special-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode image-buffer))

          (suderman/toggle-line-numbers)
          (should global-display-line-numbers-mode)
          (should (buffer-local-value 'display-line-numbers-mode text-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode special-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode image-buffer)))
      (global-display-line-numbers-mode (if original-state 1 -1))
      (when original-state
        (suderman/disable-line-numbers-in-special-buffers))
      (kill-buffer text-buffer)
      (kill-buffer special-buffer)
      (kill-buffer image-buffer))))

(ert-deftest suderman/dirvish-preview-keeps-line-numbers-disabled ()
  (with-temp-buffer
    (display-line-numbers-mode 1)
    (suderman/dirvish-preview-disable-line-numbers)
    (should-not display-line-numbers-mode)
    (display-line-numbers-mode 1)
    (should-not display-line-numbers-mode)))

(provide 'suderman-appearance-test)
;;; suderman-appearance-test.el ends here
