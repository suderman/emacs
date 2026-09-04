;;; suderman-packages.el --- package.el and use-package bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Mutable package.el setup on top of the XDG paths from suderman-paths.  This stays
;; small so future package-manager experiments have one obvious replacement file.

;;; Code:

(require 'package)

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
  (advice-remove 'package-import-keyring
                 #'suderman/package-import-keyring-from-android-assets)
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
