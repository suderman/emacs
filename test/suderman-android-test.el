;;; suderman-android-test.el --- Focused Android checks -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'pixel-scroll)
(require 'suderman-android)
(require 'touch-screen)

(ert-deftest suderman/android-toolbar-has-only-phone-actions ()
  (let ((original-tool-bar-map (default-value 'tool-bar-map))
        (tool-bar-map (make-sparse-keymap))
        (input-decode-map (make-sparse-keymap))
        (tool-bar-button-margin 4)
        (tool-bar-always-show-default nil)
        images
        face-changes
        customizations)
    (define-key tool-bar-map [stock-save]
      '(menu-item "Save" save-buffer))
    (cl-letf (((symbol-function 'modifier-bar-mode) #'ignore)
              ((symbol-function 'customize-set-variable)
               (lambda (symbol value)
                 (push (list symbol value) customizations)))
              ((symbol-function 'suderman/android-tool-bar-image)
               (lambda (name)
                  (let ((image `(test-image ,name)))
                    (push image images)
                    image)))
              ((symbol-function 'face-foreground)
               (lambda (&rest _) "ink"))
              ((symbol-function 'face-background)
               (lambda (&rest _) "paper"))
              ((symbol-function 'set-face-attribute)
               (lambda (&rest arguments)
                 (push arguments face-changes)))
              ((symbol-function 'tool-bar--flush-cache) #'ignore)
              ((symbol-function 'tool-bar-mode) #'ignore)
              ((symbol-function 'force-mode-line-update) #'ignore))
      (unwind-protect
          (progn
            (suderman/android-setup-tool-bar)
            (setq tool-bar-map (default-value 'tool-bar-map))
            (should (member '(tool-bar-position bottom) customizations))
            (should (member '(tool-bar nil :foreground "paper"
                                       :background "ink")
                            face-changes))
            (should (equal tool-bar-button-margin '(48 . 20)))
            (should tool-bar-always-show-default)
            (should (equal (mapcar #'car (cdr tool-bar-map))
                            '(suderman-escape suderman-tab suderman-files
                              suderman-buffers suderman-keyboard control meta)))
            (should (equal (mapcar (lambda (binding) (nth 2 binding))
                                    (cdr tool-bar-map))
                             '("ESC" "TAB" "FILES" "BUFFERS" "KEYBOARD"
                               "CTRL" "META")))
            (should
             (equal
              (mapcar (lambda (binding)
                        (plist-get (nthcdr 4 binding) :image))
                      (cdr tool-bar-map))
               '((test-image "escape") (test-image "tab")
                 (test-image "files") (test-image "buffers")
                 (test-image "keyboard") (test-image "control")
                 (test-image "meta"))))
            (should (eq (lookup-key tool-bar-map [suderman-escape])
                        'meow-insert-exit))
            (should (eq (lookup-key tool-bar-map [suderman-files])
                        'suderman/dirvish))
            (should (eq (lookup-key tool-bar-map [suderman-buffers])
                        'suderman/ibuffer-toggle))
            (should (eq (lookup-key tool-bar-map [suderman-keyboard])
                        'suderman/android-show-keyboard))
            (should-not
             (lookup-key input-decode-map [tool-bar suderman-escape]))
            (should (equal
                     (lookup-key input-decode-map [tool-bar suderman-tab])
                     [tab]))
            (should (eq
                     (lookup-key input-decode-map [tool-bar control])
                     'tool-bar-event-apply-control-modifier))
            (should (eq
                     (lookup-key input-decode-map [tool-bar meta])
                     'tool-bar-event-apply-meta-modifier)))
        (set-default 'tool-bar-map original-tool-bar-map)))))

(ert-deftest suderman/android-toolbar-images-are-native-sized ()
  (dolist (name '("escape" "tab" "files" "buffers" "keyboard"
                  "control" "meta"))
    (let ((file (expand-file-name
                 (format "assets/android-toolbar/%s.pbm" name)
                 user-emacs-directory)))
      (should (file-readable-p file))
      (with-temp-buffer
        (insert-file-contents-literally file)
        (should (looking-at-p
                 "P1[[:space:]]+56[[:space:]]+56[[:space:]]"))))))

(ert-deftest suderman/android-toolbar-images-use-native-scale ()
  (let ((user-emacs-directory "/tmp/emacs-config/"))
    (cl-letf (((symbol-function 'face-foreground) (lambda (&rest _) "black"))
              ((symbol-function 'face-background) (lambda (&rest _) "white")))
      (let ((image (suderman/android-tool-bar-image "escape")))
        (should (eq (car image) 'create-image))
        (should (equal (nth 1 image)
                       "/tmp/emacs-config/assets/android-toolbar/escape.pbm"))
        (should (equal (nth 2 image) ''pbm))
        (should (= (plist-get (nthcdr 4 image) :scale) 1))))))

(ert-deftest suderman/android-toolbar-can-show-the-software-keyboard ()
  (let ((frame 'phone-frame)
        call)
    (cl-letf (((symbol-function 'selected-frame) (lambda () frame))
              ((symbol-function 'frame-toggle-on-screen-keyboard)
               (lambda (&rest arguments) (setq call arguments))))
      (suderman/android-show-keyboard)
      (should (equal call '(phone-frame nil))))))

(ert-deftest suderman/android-touch-scroll-enables-momentum-idempotently ()
  (let ((touch-screen-precision-scroll nil)
        (pixel-scroll-precision-use-momentum nil)
        calls
        defaults)
    (cl-letf (((symbol-function 'advice-remove)
               (lambda (symbol function)
                 (push (list 'remove symbol function) calls)))
              ((symbol-function 'advice-add)
               (lambda (symbol where function &rest _)
                 (push (list 'add symbol where function) calls)))
              ((symbol-function 'set-default)
               (lambda (symbol value)
                 (push (list symbol value) defaults))))
      (suderman/android-setup-touch-scrolling)
      (should touch-screen-precision-scroll)
      (should pixel-scroll-precision-use-momentum)
      (should (equal defaults
                     '((make-cursor-line-fully-visible nil))))
      (should
       (equal
        (nreverse calls)
        '((remove touch-screen-handle-scroll
                  suderman/android-record-touch-scroll)
          (add touch-screen-handle-scroll :before
               suderman/android-record-touch-scroll)
          (remove touch-screen-handle-touch
                  suderman/android-start-touch-momentum)
          (add touch-screen-handle-touch :before
               suderman/android-start-touch-momentum)))))))

(ert-deftest suderman/android-touch-scroll-records-finger-velocity ()
  (let (velocity)
    (cl-letf (((symbol-function 'pixel-scroll-accumulate-velocity)
               (lambda (delta) (setq velocity delta))))
      (suderman/android-record-touch-scroll 4 17)
      (should (= velocity -17)))))

(ert-deftest suderman/android-touch-scroll-flings-only-after-scrolling ()
  (let ((touch-screen-current-tool '(1 nil nil scroll))
        events)
    (cl-letf (((symbol-function 'pixel-scroll-start-momentum)
               (lambda (event) (push event events))))
      (suderman/android-start-touch-momentum
       '(touchscreen-update ((1 . position))))
      (let ((touch-screen-current-tool '(1 nil nil held)))
        (suderman/android-start-touch-momentum
         '(touchscreen-end (1 . position) nil)))
      (suderman/android-start-touch-momentum
       '(touchscreen-end (2 . position) nil))
      (suderman/android-start-touch-momentum
       '(touchscreen-end (1 . position) t))
      (suderman/android-start-touch-momentum
       '(touchscreen-end (1 . position) nil))
      (should (equal events
                     '((touchscreen-end (1 . position) nil)))))))

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

(provide 'suderman-android-test)
;;; suderman-android-test.el ends here
