;;; suderman-packages.el --- package.el and use-package bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Mutable package.el setup on top of the XDG paths from suderman-paths.  This stays
;; small so future package-manager experiments have one obvious replacement file.

;;; Code:

(require 'package)

(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

(package-initialize)

(unless (package-installed-p 'use-package)
  (unless package-archive-contents
    (package-refresh-contents))
  (package-install 'use-package))

(require 'use-package)

(setq use-package-always-ensure t
      use-package-always-defer t
      use-package-expand-minimally t)

(provide 'suderman-packages)
;;; suderman-packages.el ends here
