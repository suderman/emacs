;;; suderman-input-test.el --- Input and editing behavior checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for custom behavior with enough moving parts to merit a safety net.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'pixel-scroll)
(require 'suderman-android)
(require 'suderman-completion)
(require 'suderman-meow)
(require 'suderman-help)
(require 'suderman-git)
(require 'org-agenda)
(require 'touch-screen)
(require 'vertico-mouse)

(defvar vertico--scroll)
(defvar vertico-count)
(defvar vertico-scroll-margin)

;; Vertico touch input

(ert-deftest suderman/android-vertico-touch-drag-scrolls-candidates ()
  (let ((events '((touchscreen-update ((1 . update-position)))
                  (touchscreen-end (1 . end-position) nil)))
        (vertico--scroll 5)
        (vertico-count 10)
        (vertico-scroll-margin 2)
        gotos
        exhibits
        exited)
    (cl-letf (((symbol-function 'posn-window)
               (lambda (_posn) (selected-window)))
              ((symbol-function 'posn-x-y)
               (lambda (_posn) '(0 . 0)))
              ((symbol-function 'touch-screen-relative-xy)
               (lambda (_posn _window) '(0 . 30)))
              ((symbol-function 'default-line-height) (lambda () 10))
              ((symbol-function 'read-event) (lambda () (pop events)))
              ((symbol-function 'vertico--goto)
               (lambda (index) (push index gotos)))
              ((symbol-function 'vertico--exhibit)
               (lambda () (setq exhibits (1+ (or exhibits 0)))))
              ((symbol-function 'vertico-exit) (lambda () (setq exited t))))
      (suderman/vertico-touchscreen-begin
       '(touchscreen-begin (1 . begin-position)))
      (should (equal gotos '(4)))
      (should (= exhibits 1))
      (should-not exited))))

;; Android gestures and modifiers

(ert-deftest suderman/android-modifier-buttons-toggle-independently ()
  (dolist (case '((suderman/tool-bar-toggle-control
                   control meta)
                  (suderman/tool-bar-toggle-meta
                   meta control)))
    (let* ((function (car case))
           (initial (cadr case))
           (remaining (caddr case))
           (events (list 'tool-bar remaining 'tool-bar initial ?x))
           applied)
      (cl-letf (((symbol-function 'read-event)
                 (lambda (&rest _) (pop events)))
                ((symbol-function 'event-basic-type) #'identity)
                ((symbol-function 'frame-toggle-on-screen-keyboard) #'ignore)
                ((symbol-function 'suderman/tool-bar-refresh) #'ignore)
                ((symbol-function 'redisplay) #'ignore)
                ((symbol-function 'set-text-conversion-style) #'ignore)
                ((symbol-function 'tool-bar-apply-modifiers)
                 (lambda (event modifiers)
                   (setq applied (list event modifiers))
                   'translated)))
        (should (equal (funcall function nil) [translated]))
        (should-not events)
        (should (equal applied (list ?x (list remaining))))))))

(ert-deftest suderman/android-volume-buttons-support-modifiers-and-chords ()
  (cl-letf (((symbol-function 'read-event) (lambda (&rest _) 'volume-up)))
    (should (equal (suderman/android-volume-control nil) [escape])))
  (cl-letf (((symbol-function 'read-event) (lambda (&rest _) 'volume-down)))
    (should (equal (suderman/android-volume-meta nil) [tab])))
  (cl-letf (((symbol-function 'read-event) (lambda (&rest _) ?x))
            ((symbol-function 'event-apply-modifier)
             (lambda (event modifier bit prefix)
               (list event modifier bit prefix))))
    (should (equal (suderman/android-volume-control nil)
                   [(120 control 26 "C-")]))
    (should (equal (suderman/android-volume-meta nil)
                   [(120 meta 27 "M-")]))))


;; Meow editing behavior

(ert-deftest suderman/android-meow-text-conversion-follows-state ()
  (with-temp-buffer
    (dlet ((features (cons 'android features))
           (text-conversion-style t))
      (let (calls)
        (cl-letf (((symbol-function 'set-text-conversion-style)
                   (lambda (style &optional _after-key-sequence)
                     (setq text-conversion-style style)
                     (push style calls))))
          (suderman/android-meow-text-conversion 'normal)
          (suderman/android-meow-text-conversion 'motion)
          (suderman/android-meow-text-conversion 'insert)
          (suderman/android-meow-text-conversion 'keypad)
          (should-not text-conversion-style)
          (should (equal (nreverse calls) '(nil t nil))))))))

(ert-deftest suderman/meow-slash-search-smartcase-survives-meow-navigation ()
  (let ((transient-mark-mode t)
        (regexp-search-ring nil))
    (save-window-excursion
      (with-temp-buffer
        (set-window-buffer (selected-window) (current-buffer))
        (insert "Home home HOME")
        (goto-char (point-min))
        (setq-local meow-normal-mode t)
        (execute-kbd-macro (kbd "/ h o m e RET"))
        (should (= (region-beginning) 1))
        (should (equal suderman/meow-search-count " [1/3]"))
        (execute-kbd-macro (kbd "n"))
        (should (= (region-beginning) 6))
        (should (equal suderman/meow-search-count " [2/3]"))
        (execute-kbd-macro (kbd "n"))
        (should (= (region-beginning) 11))
        (execute-kbd-macro (kbd "p"))
        (should (= (region-beginning) 6))
        (meow--cancel-selection)
        (goto-char (point-min))
        (execute-kbd-macro (kbd "/ H o m e RET"))
        (should (= (region-beginning) 1))
        (should (equal suderman/meow-search-count " [1/1]"))
        (execute-kbd-macro (kbd "n"))
        (should (= (region-beginning) 1))))))

(ert-deftest suderman/meow-search-count-does-not-wrap-text ()
  (let ((transient-mark-mode t)
        (regexp-search-ring nil))
    (save-window-excursion
      (with-temp-buffer
        (set-window-buffer (selected-window) (current-buffer))
        (insert "foo at the end of a long line foo\nfoo")
        (goto-char (point-min))
        (setq-local meow-normal-mode t)
        (execute-kbd-macro (kbd "/ f o o RET"))
        (should (equal suderman/meow-search-count " [1/3]"))
        (should (string-match-p "1/3"
                                (doom-modeline-segment--suderman-meow-search)))
        (should-not meow--search-indicator-overlay)
        (should-not (cl-some (lambda (ov)
                               (or (overlay-get ov 'after-string)
                                   (overlay-get ov 'display)))
                             (overlays-at (line-end-position))))
        (execute-kbd-macro (kbd "n"))
        (should (equal suderman/meow-search-count " [2/3]"))
        (meow--remove-search-indicator)
        (should-not suderman/meow-search-count)))))

;; Context-aware keyboard help

(ert-deftest suderman/cheatsheet-resolves-source-remaps-and-restores-view ()
  (save-window-excursion
    (with-temp-buffer
      (let ((source (current-buffer))
            (meow-command-to-short-name-list
             '((forward-char . "fixture")
               (forward-word . "preview fixture")
               (undefined . "")
               (self-insert-command . ""))))
        (set-window-buffer (selected-window) source)
        (org-agenda-mode)
        (use-local-map (copy-keymap (current-local-map)))
        (keymap-set (current-local-map) "j" #'backward-char)
        (keymap-set (current-local-map) "<remap> <backward-char>" #'forward-char)
        (keymap-set (current-local-map) "C-SPC" #'forward-word)
        (keymap-set (current-local-map) "K" #'undefined)
        (let ((original-terminal-map overriding-terminal-local-map)
              (original-local-map overriding-local-map))
          ;; Ambient current-buffer must not replace the visible view's context.
          (with-temp-buffer (suderman/cheatsheet))
          (should (eq overriding-terminal-local-map original-terminal-map))
          (should (eq overriding-local-map original-local-map)))
        (let ((sheet (window-buffer)))
          (unwind-protect
              (progn
                (with-current-buffer sheet
                  (should (derived-mode-p 'suderman/cheatsheet-mode))
                  (should-not meow-mode)
                  (should buffer-read-only)
                  (should (string-match-p "fixture" (buffer-string)))
                  (should (string-match-p "C-SPC  preview fixture" (buffer-string)))
                  (should-not (string-match-p "<AD01>" (buffer-string))))
                (execute-kbd-macro (kbd "q"))
                (should (eq (window-buffer) source))
                (should (eq (with-current-buffer source (key-binding (kbd "j")))
                            #'forward-char)))
            (kill-buffer sheet)))))))

(provide 'suderman-input-test)
;;; suderman-input-test.el ends here
