;;; suderman-completion.el --- Minibuffer and in-buffer completion -*- lexical-binding: t; -*-

;;; Commentary:
;; Vertico handles the minibuffer; Corfu displays mode CAPFs in editing buffers.

;;; Code:

(require 'use-package)

(defvar vertico--scroll)
(defvar vertico-count)
(defvar vertico-map)
(defvar vertico-mouse-map)
(defvar vertico-scroll-margin)
(defvar xref-show-xrefs-function)
(defvar xref-show-definitions-function)

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
      (let ((begin-scroll-pos vertico--scroll)
            (last-dline 0))
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
                              (or (> (abs dx) 10) (> (abs dy) 10)))
                     (setq moved t))
                   (when moved
                     (let ((dline
                            (round (/ (float dy) (default-line-height)))))
                       (unless (= dline last-dline)
                         (setq last-dline dline)
                         (let ((new-scroll-pos (- begin-scroll-pos dline)))
                           (cond
                            ((< new-scroll-pos vertico--scroll)
                             (vertico--goto
                              (+ new-scroll-pos vertico-scroll-margin)))
                            ((> new-scroll-pos vertico--scroll)
                             (vertico--goto
                              (+ new-scroll-pos vertico-count
                                 (- vertico-scroll-margin)))))
                           (vertico--exhibit)))))
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

(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map
              ("DEL" . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

(use-package marginalia
  :init
  (marginalia-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles basic partial-completion orderless)))))

(use-package consult
  ;; consult-customize expands to this non-autoloaded helper.
  :functions consult--customize-put
  :bind
  (("C-x b" . consult-buffer)
   ("M-s r" . consult-ripgrep)
   ("M-s l" . consult-line)
   ("M-s i" . consult-imenu)
   ([remap bookmark-jump] . consult-bookmark)
   :map minibuffer-local-map
   ("M-r" . consult-history))
  :init
  (with-eval-after-load 'xref
    (setq xref-show-xrefs-function #'consult-xref
          xref-show-definitions-function #'consult-xref))
  :custom
  (consult-narrow-key "<")
  :config
  (require 'consult-compile)
  ;; Keep in-buffer previews immediate; avoid opening files on every keypress.
  (consult-customize
   consult-ripgrep consult-git-grep consult-grep
   :preview-key '("C-SPC" :debounce 0.2 any))
  (consult-customize
   consult-bookmark consult-source-bookmark
   :preview-key "C-SPC"))

(use-package embark
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)
   :map minibuffer-local-map
   ("C-c C-e" . embark-export)
   ("C-c C-l" . embark-collect)))

(use-package embark-consult
  :after (embark consult)
  :demand t
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; Keep TAB's usual indentation, with completion when indentation is done.
(setq tab-always-indent 'complete
      text-mode-ispell-word-completion nil)

(use-package corfu
  :custom
  (global-corfu-minibuffer nil)
  (corfu-auto t)
  (corfu-auto-prefix 2)
  (corfu-auto-delay 0.15)
  (corfu-cycle t)
  (corfu-preselect 'prompt)
  (corfu-preview-current nil)
  (corfu-popupinfo-delay '(0.5 . 0.5))
  :bind (:map corfu-map
              ("TAB" . corfu-next)
              ([tab] . corfu-next)
              ("S-TAB" . corfu-previous)
              ([backtab] . corfu-previous))
  :init
  ;; Emacs 31 child frames float over both GUI and TTY buffers.
  (global-corfu-mode 1)
  (corfu-history-mode 1)
  (corfu-popupinfo-mode 1))

;; Savehist is already enabled in suderman-defaults; retain choices across runs.
(add-to-list 'savehist-additional-variables 'corfu-history)

(use-package nerd-icons-corfu
  :after corfu
  :demand t
  :config
  (when (suderman/nerd-fonts-available-p)
    (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter)))

(use-package cape
  :demand t
  :config
  ;; Mode CAPFs (including Eglot and pcomplete) win; no merged LSP candidates.
  (defalias 'suderman/cape-dabbrev
    (cape-capf-prefix-length #'cape-dabbrev 3))
  (add-hook 'completion-at-point-functions #'cape-file t)
  (add-hook 'completion-at-point-functions #'suderman/cape-dabbrev t))

;; Shell prompts already complete on TAB; avoid unsolicited menus while typing.
(add-hook 'eshell-mode-hook (lambda () (setq-local corfu-auto nil)))
(add-hook 'comint-mode-hook (lambda () (setq-local corfu-auto nil)))

(provide 'suderman-completion)
;;; suderman-completion.el ends here
