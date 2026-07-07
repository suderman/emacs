;;; early-init.el --- Early startup tweaks -*- lexical-binding: t; -*-

;; Keep package.el from initializing before init.el configures XDG paths.
(setq package-enable-at-startup nil)

;; Reduce startup noise and work. Keep this boring and reversible.
(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      frame-inhibit-implied-resize t)

;; Temporarily raise GC threshold during startup. init.el restores it.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; Keep package-native-comp warnings out of the UI; they are usually upstream
;; package compiler warnings, not startup failures.
(when (boundp 'native-comp-async-report-warnings-errors)
  (setq native-comp-async-report-warnings-errors 'silent))

;; Basic UI cleanup. Keep the menu while getting acquainted.
(menu-bar-mode 1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

;; GUI frame defaults need to be available before the first frame is built.
(dolist (parameter '((font . "JetBrainsMono Nerd Font Mono-11")
                     (alpha-background . 90)))
  (add-to-list 'default-frame-alist parameter)
  (add-to-list 'initial-frame-alist parameter))

(provide 'early-init)
;;; early-init.el ends here
