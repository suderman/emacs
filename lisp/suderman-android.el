;;; suderman-android.el --- Android platform bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Android input helpers, Termux executable discovery, and local font setup.

;;; Code:

(require 'seq)
(require 'subr-x)

(defconst suderman/android-termux-bin
  "/data/data/com.termux/files/usr/bin")

(defconst suderman/android-font-directory
  (expand-file-name "fonts" "~"))

(defconst suderman/android-fonts
  `(("JetBrainsMonoNerdFontMono-Regular.ttf"
     . (,(concat
          "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/"
          "fa7b859994228a9c8759f99c55a8d31ee92a1b5e/"
          "patched-fonts/JetBrainsMono/Ligatures/Regular/"
          "JetBrainsMonoNerdFontMono-Regular.ttf")
        "f01031f40e48dc29e1112e6b0b0450a2c6cd097f3f35cfff05c55cb311f8034c"))
    ("JetBrainsMonoNerdFontMono-Bold.ttf"
     . (,(concat
          "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/"
          "fa7b859994228a9c8759f99c55a8d31ee92a1b5e/"
          "patched-fonts/JetBrainsMono/Ligatures/Bold/"
          "JetBrainsMonoNerdFontMono-Bold.ttf")
        "5bdd4a873f3cd32f882d2c55545089123926e27707d5880fc9eaf84eb01b6686"))
    ("SymbolsNerdFontMono-Regular.ttf"
     . (,(concat
          "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/"
          "fa7b859994228a9c8759f99c55a8d31ee92a1b5e/"
          "patched-fonts/NerdFontsSymbolsOnly/"
          "SymbolsNerdFontMono-Regular.ttf")
        "f0f624d9b474bea1662cf7e862d44aebe1ae1f6c7f9cb7a0ca5d0e5ac9561c60")))
  "Android font file names, immutable URLs, and SHA-256 checksums.")

(defun suderman/android-missing-fonts ()
  "Return entries from `suderman/android-fonts' not installed locally."
  (seq-filter
   (lambda (font)
     (not (file-exists-p
           (expand-file-name (car font) suderman/android-font-directory))))
   suderman/android-fonts))

(defun suderman/android-install-fonts ()
  "Download and verify missing Android fonts, then request an Emacs restart."
  (interactive)
  (let ((fonts (suderman/android-missing-fonts))
        downloads
        installed)
    (if (null fonts)
        (message "Android fonts are already installed")
      (make-directory suderman/android-font-directory t)
      (condition-case error-data
          (progn
            (require 'url-handlers)
            (dolist (font fonts)
              (let* ((name (car font))
                     (url (cadr font))
                     (checksum (caddr font))
                     (temporary
                      (make-temp-file
                       (expand-file-name (concat "." name ".")
                                         suderman/android-font-directory))))
                (push (cons temporary
                            (expand-file-name
                             name suderman/android-font-directory))
                      downloads)
                (url-copy-file url temporary t)
                (unless (equal
                         (with-temp-buffer
                           (insert-file-contents-literally temporary)
                           (secure-hash 'sha256 (current-buffer)))
                         checksum)
                  (error "Checksum mismatch for %s" name))))
            (dolist (download downloads)
              (rename-file (car download) (cdr download))
              (push (cdr download) installed))
            (setq downloads nil
                  installed nil)
            (message "Android fonts installed; restart Emacs to use them"))
        (error
         (message "Could not install Android fonts: %s"
                  (error-message-string error-data))))
      (dolist (download downloads)
        (ignore-errors (delete-file (car download))))
      (dolist (file installed)
        (ignore-errors (delete-file file))))))

(defun suderman/android-offer-font-install ()
  "Offer to install missing Android fonts after startup."
  (when (and (eq system-type 'android)
             (suderman/android-missing-fonts)
             (y-or-n-p "Install the missing Nerd Fonts for Emacs? "))
    (suderman/android-install-fonts)))

(defun suderman/android-volume-control (_prompt)
  "Apply Control to the next event, or make Volume Up send Escape."
  (let ((event (read-event)))
    (if (eq event 'volume-up)
        [escape]
      (vector (event-apply-modifier event 'control 26 "C-")))))

(defun suderman/android-volume-meta (_prompt)
  "Apply Meta to the next event, or make Volume Down send Tab."
  (let ((event (read-event)))
    (if (eq event 'volume-down)
        [tab]
      (vector (event-apply-modifier event 'meta 27 "M-")))))

(defun suderman/android-setup-tool-bar ()
  "Configure the compact Android input toolbar idempotently."
  (require 'tool-bar)
  (modifier-bar-mode -1)
  (setq secondary-tool-bar-map nil
        tool-bar-position 'bottom
        tool-bar-button-margin 10)
  (dolist (key '(suderman-escape suderman-tab control meta))
    (define-key tool-bar-map (vector key) nil))
  (define-key tool-bar-map [suderman-escape]
    `(menu-item "Escape" ignore
                :image ,(tool-bar--image-expression "left-arrow")
                :help "Send Escape"))
  (define-key-after tool-bar-map [suderman-tab]
    `(menu-item "Tab" ignore
                :image ,(tool-bar--image-expression "right-arrow")
                :help "Send Tab")
    'suderman-escape)
  (tool-bar-add-item "ctrl" #'ignore 'control
                     :label "Ctrl" :help "Apply Control to the next key")
  (tool-bar-add-item "meta" #'ignore 'meta
                     :label "Meta" :help "Apply Meta to the next key")
  (define-key input-decode-map [tool-bar suderman-escape] [escape])
  (define-key input-decode-map [tool-bar suderman-tab] [tab])
  (define-key input-decode-map [tool-bar control]
              #'tool-bar-event-apply-control-modifier)
  (define-key input-decode-map [tool-bar meta]
              #'tool-bar-event-apply-meta-modifier)
  (tool-bar--flush-cache)
  (tool-bar-mode 1)
  (force-mode-line-update t))

(when (eq system-type 'android)
  (add-to-list 'exec-path suderman/android-termux-bin)
  (setenv "PATH"
          (string-join (delete-dups
                        (cons suderman/android-termux-bin
                              (parse-colon-path (getenv "PATH"))))
                       path-separator))
  (suderman/android-setup-tool-bar)
  (define-key function-key-map [volume-down] #'suderman/android-volume-control)
  (define-key function-key-map [volume-up] #'suderman/android-volume-meta)
  (add-hook 'after-init-hook #'suderman/android-offer-font-install))

(provide 'suderman-android)
;;; suderman-android.el ends here
