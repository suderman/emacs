;;; suderman-completion.el --- Minibuffer completion stack -*- lexical-binding: t; -*-

;;; Commentary:
;; Vertico, Orderless, Consult, Marginalia, and Embark stay together because they
;; are one coherent minibuffer UX.

;;; Code:

(require 'use-package)

(defun suderman/clear-search ()
  "Clear active isearch and lazy search highlighting."
  (interactive)
  (when (bound-and-true-p isearch-mode)
    (isearch-exit))
  (when (fboundp 'lazy-highlight-cleanup)
    (lazy-highlight-cleanup t))
  (when (fboundp 'isearch-dehighlight)
    (isearch-dehighlight)))

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
