;;; suderman-packages.el --- package.el and use-package bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; `use-package' forms across lisp/ declare every package.  On NixOS the flake
;; reads those forms and supplies the packages, so `:ensure' finds them
;; installed.  Android, a brand-new package not yet in Nix, and `:vc' Git
;; packages fall through to package.el under ~/.local/share/emacs/elpa.

;;; Code:

(require 'package)
(require 'package-vc)

(defvar suderman/package-vc-specs nil
  "Package specs from `use-package' :vc forms, keyed by package name.")

(defun suderman/package-vc-remember-spec (arg &optional _local-path)
  "Remember the package spec in the `use-package' :vc ARG.
use-package skips installed packages, and package-vc saves a spec only
on first install, so the config is the reliable source."
  (pcase-let ((`(,name ,spec ,_rev) arg))
    (when spec
      (setf (alist-get name suderman/package-vc-specs) spec))))

(advice-add 'use-package-vc-install :before
            #'suderman/package-vc-remember-spec)

(defun suderman/package-upgrade-all ()
  "Upgrade mutable packages without confirmation.
Nix supplies archive packages on Linux, so only Android upgrades them here.
Git packages such as Edger and meow-purrsist upgrade everywhere."
  (interactive)
  (when (eq system-type 'android)
    (package-upgrade-all nil))
  ;; The rebuild after each pull reads specs such as Edger's :lisp-dir from
  ;; this variable, but custom.el may lack them.  Merge without saving.
  (pcase-dolist (`(,name . ,spec) suderman/package-vc-specs)
    (setf (alist-get name package-vc-selected-packages) spec))
  (package-vc-upgrade-all))

(defun suderman/package-import-keyring-from-android-assets
    (function &optional file)
  "Call FUNCTION with a physical copy when Android keyring FILE is an asset."
  (if (and (eq system-type 'android)
           file
           (string-match-p "\\`/assets/" (expand-file-name file)))
      (let ((temporary (make-temp-file "package-keyring-")))
        (unwind-protect
            (progn
              ;; Android assets are visible to Emacs but not external GPG.
              (copy-file file temporary t)
              (funcall function temporary))
          (ignore-errors (delete-file temporary))))
    (funcall function file)))

(when (eq system-type 'android)
  (advice-add 'package-import-keyring :around
              #'suderman/package-import-keyring-from-android-assets))

(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

(package-initialize)

;; Force fresh metadata before installing anything missing.
(setq package-archive-contents nil)

(unless (package-installed-p 'use-package)
  (unless package-archive-contents
    (package-refresh-contents))
  (package-install 'use-package))

(require 'use-package)

(setq use-package-always-ensure t
      use-package-always-defer t
      use-package-expand-minimally t)

;; Keep startup usable when an optional package cannot be installed.
(add-to-list 'use-package-defaults
             '(:if (lambda (name _args)
                     (list 'locate-library (symbol-name name)))
               t))

(provide 'suderman-packages)
;;; suderman-packages.el ends here
