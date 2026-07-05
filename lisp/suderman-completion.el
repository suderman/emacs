;;; suderman-completion.el --- Minibuffer completion stack -*- lexical-binding: t; -*-

;;; Commentary:
;; Vertico, Orderless, Consult, Marginalia, and Embark stay together because they
;; are one coherent minibuffer UX.  Higher-level pickers live in suderman-pickers.

;;; Code:

(require 'use-package)
(require 'suderman-projects)

(use-package vertico
  :init
  (vertico-mode 1))

(use-package marginalia
  :init
  (marginalia-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles basic partial-completion orderless)))))

(use-package consult
  :init
  (setq consult-project-function #'consult--default-project-function)
  :bind
  (("C-x b" . consult-buffer)
   ("M-s r" . suderman/search-project)
   ("M-s l" . consult-line)
   ("M-s i" . consult-imenu)))

(use-package embark
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)))

(use-package embark-consult
  :after (embark consult))

(provide 'suderman-completion)
;;; suderman-completion.el ends here
