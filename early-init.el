;;; early-init.el --- Early startup tweaks -*- lexical-binding: t; -*-

;; Keep package.el from initializing before init.el configures XDG paths.
(setq package-enable-at-startup nil)

;; Load source over stale bytecode, such as an old .elc beside an updated .el.
(setq load-prefer-newer t)

;; Reduce startup noise and work. Keep this boring and reversible.
(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      frame-inhibit-implied-resize t)

;; Temporarily raise GC threshold during startup. suderman-defaults restores it.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; Keep package-native-comp warnings out of the UI; they are usually upstream
;; package compiler warnings, not startup failures.
(when (boundp 'native-comp-async-report-warnings-errors)
  (setq native-comp-async-report-warnings-errors 'silent))

;; Basic UI cleanup. Terminal-only builds such as Termux lack these bars.
(dolist (mode '(menu-bar-mode tool-bar-mode scroll-bar-mode))
  (when (fboundp mode)
    (funcall mode -1)))

;; GUI frame opacity needs to be available before the first frame is built.
(unless (featurep 'android)
  (add-to-list 'default-frame-alist '(alpha-background . 90))
  (add-to-list 'initial-frame-alist '(alpha-background . 90)))

;; Start Android's first frame in the system's light or dark color until the
;; theme loads.  The display sets `toolkit-theme' after this file but before
;; `before-init-hook'.  Fall back to dark so a night start never flashes white.
(when (featurep 'android)
  (add-hook 'before-init-hook
            (lambda ()
              (let ((dark (not (eq toolkit-theme 'light))))
                (push `(background-color . ,(if dark "black" "white"))
                      initial-frame-alist)
                (push `(foreground-color . ,(if dark "white" "black"))
                      initial-frame-alist)))))

(provide 'early-init)
;;; early-init.el ends here
