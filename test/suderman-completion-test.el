;;; suderman-completion-test.el --- Completion checks -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'suderman-completion)
(require 'vertico-mouse)

(defvar vertico--scroll)
(defvar vertico-count)
(defvar vertico-mouse-map)
(defvar vertico-scroll-margin)

(ert-deftest suderman/android-vertico-touch-setup-enables-the-mouse-map ()
  (let (calls)
    (cl-letf (((symbol-function 'keymap-unset)
               (lambda (map key)
                 (push (list 'unset map key) calls)))
              ((symbol-function 'vertico-mouse-mode)
               (lambda (arg) (push (list 'mode arg) calls)))
              ((symbol-function 'keymap-set)
               (lambda (map key command)
                 (push (list 'set map key command) calls))))
      (suderman/vertico-setup-touchscreen)
      (should
       (equal
        (nreverse calls)
        `((unset ,vertico-map "<touchscreen-begin>")
          (mode 1)
          (set ,vertico-mouse-map "<touchscreen-begin>"
               suderman/vertico-touchscreen-begin)))))))

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

(ert-deftest suderman/android-vertico-touch-tap-selects-and-exits ()
  (let ((events '((touchscreen-end (1 . end-position) nil)))
        gotos
        exited)
    (cl-letf (((symbol-function 'posn-window)
               (lambda (_posn) (selected-window)))
              ((symbol-function 'posn-x-y)
               (lambda (_posn) '(0 . 0)))
              ((symbol-function 'read-event) (lambda () (pop events)))
              ((symbol-function 'vertico-mouse--index) (lambda (_event) 7))
              ((symbol-function 'vertico--goto)
               (lambda (index) (push index gotos)))
              ((symbol-function 'vertico-exit) (lambda () (setq exited t))))
      (suderman/vertico-touchscreen-begin
       '(touchscreen-begin (1 . begin-position)))
      (should (equal gotos '(7)))
      (should exited))))

(provide 'suderman-completion-test)
;;; suderman-completion-test.el ends here
