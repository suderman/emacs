;;; suderman-completion.el --- Minibuffer completion stack -*- lexical-binding: t; -*-

;;; Commentary:
;; Vertico, Orderless, Consult, Marginalia, and Embark stay together because they
;; are one coherent minibuffer UX.

;;; Code:

(require 'use-package)

(defvar vertico--scroll)
(defvar vertico-count)
(defvar vertico-map)
(defvar vertico-mouse-map)
(defvar vertico-scroll-margin)

(declare-function touch-screen-relative-xy "touch-screen" (posn window))
(declare-function vertico--exhibit "vertico" ())
(declare-function vertico--goto "vertico" (index))
(declare-function vertico-exit "vertico" ())
(declare-function vertico-mouse--index "vertico-mouse" (event))
(declare-function vertico-mouse-mode "vertico-mouse" (&optional arg))

(defun suderman/clear-search ()
  "Clear active isearch and lazy search highlighting."
  (interactive)
  (when (bound-and-true-p isearch-mode)
    (isearch-exit))
  (when (fboundp 'lazy-highlight-cleanup)
    (lazy-highlight-cleanup t))
  (when (fboundp 'isearch-dehighlight)
    (isearch-dehighlight)))

;; https://github.com/minad/vertico/discussions/615#discussioncomment-13872270
;; This relies on private Vertico scrolling and mouse APIs.
(defun suderman/vertico-touchscreen-begin (begin-event)
  "Scroll or select Vertico candidates from touch BEGIN-EVENT."
  (interactive "e")
  (let* ((begin-posn (cdadr begin-event))
         (begin-window (posn-window begin-posn))
         (begin-xy (posn-x-y begin-posn))
         (moved nil))
    (with-selected-window begin-window
      (let ((begin-scroll-pos vertico--scroll))
        (while
            (let ((event (read-event)))
              (pcase (car-safe event)
                ('touchscreen-update
                 (let* ((update-xy
                         (touch-screen-relative-xy
                          (cdaadr event) begin-window))
                        (dx (- (car update-xy) (car begin-xy)))
                        (dy (- (cdr update-xy) (cdr begin-xy))))
                   (when (and (not moved)
                              (>= (+ (* dx dx) (* dy dy)) (* 2 2)))
                     (setq moved t))
                   (when moved
                     (let* ((dline (/ dy (default-line-height)))
                            (new-scroll-pos (- begin-scroll-pos dline)))
                       (cond
                        ((< new-scroll-pos vertico--scroll)
                         (vertico--goto
                          (+ new-scroll-pos vertico-scroll-margin)))
                        ((> new-scroll-pos vertico--scroll)
                         (vertico--goto
                          (+ new-scroll-pos vertico-count
                             (- vertico-scroll-margin)))))
                       (vertico--exhibit)))
                   t))
                ('touchscreen-end
                 (unless moved
                   (vertico--goto (vertico-mouse--index begin-event))
                   (vertico-exit))
                 nil))))))))

(defun suderman/vertico-setup-touchscreen ()
  "Enable touchscreen scrolling and selection for Vertico."
  (require 'vertico-mouse)
  (keymap-unset vertico-map "<touchscreen-begin>")
  (vertico-mouse-mode 1)
  (keymap-set vertico-mouse-map "<touchscreen-begin>"
              #'suderman/vertico-touchscreen-begin))

(use-package vertico
  :init
  (vertico-mode 1))

(when (eq system-type 'android)
  (with-eval-after-load 'vertico
    (suderman/vertico-setup-touchscreen)))

(use-package marginalia
  :init
  (marginalia-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles basic partial-completion orderless)))))

(use-package consult
  :bind
  (("C-x b" . consult-buffer)
   ("M-s r" . consult-ripgrep)
   ("M-s l" . consult-line)
   ("M-s i" . consult-imenu))
  :custom
  (consult-narrow-key "<"))

(use-package embark
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)))

(use-package embark-consult
  :after (embark consult))

(provide 'suderman-completion)
;;; suderman-completion.el ends here
