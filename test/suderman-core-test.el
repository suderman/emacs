;;; suderman-core-test.el --- Core behavior checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for custom behavior with enough moving parts to merit a safety net.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'suderman-appearance)
(require 'suderman-buffers)
(require 'suderman-clipboard)
(require 'suderman-defaults)
(require 'suderman-formatting)
(require 'suderman-packages)
(require 'suderman-org)
(require 'suderman-projects)
(require 'suderman-reload)
(require 'suderman-windows)

;; Project roots

(ert-deftest suderman/work-projects-share-identity-with-local-companions ()
  (let* ((home (make-temp-file "suderman-project-" t))
         (suderman/project-org-root (expand-file-name "org/work/" home))
         (suderman/project-source-root (expand-file-name "src/" home))
         (suderman/project-data-root (expand-file-name "data/work/" home))
         (buffers nil))
    (unwind-protect
        (progn
          (dolist (name '("suderman/foo" "davy/cool-comic"
                          "nonfiction/example" "davy/solo"))
            (make-directory (expand-file-name name suderman/project-org-root) t))
          (let* ((org (expand-file-name "suderman/foo/" suderman/project-org-root))
                 (src (expand-file-name "suderman/foo/" suderman/project-source-root))
                 (data (expand-file-name "davy/cool-comic/" suderman/project-data-root))
                 (all-org (expand-file-name "nonfiction/example/" suderman/project-org-root))
                 (all-src (expand-file-name "nonfiction/example/" suderman/project-source-root))
                 (all-data (expand-file-name "nonfiction/example/" suderman/project-data-root)))
            (dolist (dir (list src data all-src all-data))
              (make-directory dir t))
            (dolist (entry `((,org "foo.org") (,src "README.md")
                             (,(expand-file-name "davy/cool-comic/" suderman/project-org-root)
                              "cool-comic.org")
                             (,data "art/page-01.psd")
                             (,all-org "notes/art-direction.org")
                             (,all-src "tools/export.py")
                             (,all-data "video/trailer.kdenlive")
                             (,(expand-file-name "davy/solo/" suderman/project-org-root)
                              "solo.org")))
              (let ((file (expand-file-name (cadr entry) (car entry))))
                (make-directory (file-name-directory file) t)
                (with-temp-file file (insert "sample"))
                (let ((buffer (generate-new-buffer "project-fixture")))
                  (push buffer buffers)
                  (with-current-buffer buffer
                    (setq buffer-file-name file
                          default-directory (file-name-directory file))))))
            (dolist (name '("suderman/foo" "davy/cool-comic"
                            "nonfiction/example" "davy/solo"))
              (let* ((root (expand-file-name (concat name "/") suderman/project-org-root))
                     (project (project-current nil root)))
                (should (suderman/project-p project))
                (should (equal (project-root project) root))
                (should (equal (project-name project) name))
                (dolist (companion (list suderman/project-source-root
                                         suderman/project-data-root))
                  (let ((dir (expand-file-name name companion)))
                    (when (file-directory-p dir)
                      (should (equal (project-current nil dir) project))
                      (should (equal (project-current nil
                                                      (expand-file-name "nested/deeper/" dir))
                                     project)))))
                (should (equal (length (project-buffers project))
                               (pcase name
                                 ("suderman/foo" 2)
                                 ("davy/cool-comic" 2)
                                 ("davy/solo" 1)
                                 (_ 3))))
                (dolist (buffer (project-buffers project))
                  (should (equal (project-current nil
                                                  (buffer-local-value 'default-directory buffer))
                                 project)))))
            (let ((project (project-current nil all-org)))
              (should (equal (length (project-external-roots project)) 2))
              (should (equal (length (project-files project)) 2))
              ;; project-find-file passes the canonical root explicitly.
              (let ((project-files-relative-names t))
                (should (equal (length (project-files project (list all-org))) 2))
                (should (cl-every #'file-name-absolute-p
                                  (project-files project (list all-org)))))
              (dolist (entry `((,all-src "tools/export.py" "src/tools/export.py")
                               (,all-data "video/trailer.kdenlive"
                                          "data/video/trailer.kdenlive")))
                (let ((buffer (cl-find-if
                               (lambda (buffer)
                                 (equal (buffer-local-value 'buffer-file-name buffer)
                                        (expand-file-name (cadr entry) (car entry))))
                               buffers)))
                  (should (equal (ibuffer-make-column-suderman-project-file-relative
                                  buffer ?\s)
                                 (caddr entry)))))
              (should (= (length (project-files project (list all-data))) 1))
              (should (= (length (project-files project
                                               (cons all-org (project-external-roots project)))) 3))
              (let ((default-directory all-src)
                    offered)
                (cl-letf (((symbol-function 'project--read-file-name)
                           (lambda (_project _prompt files &rest _)
                             (setq offered files)
                             (car files)))
                          ((symbol-function 'find-file) #'ignore))
                  (project-find-file)
                  (should (= (length offered) 2))
                  (project-or-external-find-file)
                  (should (= (length offered) 3))))
              (delete-directory all-data t)
              (should-not (suderman/project-try-work all-data))
              (should (equal (project-external-roots project) (list all-src)))
              (should (= (length (project-buffers project)) 2))
              (should (= (length (project-files project)) 2))
              (delete-directory all-src t)
              (should-not (suderman/project-try-work all-src))
              (should-not (project-external-roots project))
              (should (= (length (project-buffers project)) 1))
              (should (= (length (project-files project)) 1))
              (let ((default-directory all-org))
                (should-error (suderman/project-source-dired) :type 'user-error)
                (should-error (suderman/project-data-dired) :type 'user-error)))
            (should (= (length (project-files (project-current nil org))) 2))
            (should (= (length (project-files
                                (project-current nil
                                                 (expand-file-name "davy/cool-comic"
                                                                   suderman/project-org-root)))) 1))
            (let ((unclaimed (expand-file-name "other/random/" suderman/project-source-root))
                  (unclaimed-data (expand-file-name "other/random/" suderman/project-data-root))
                  (outside (expand-file-name "elsewhere/repo/" home)))
              (dolist (dir (list unclaimed unclaimed-data outside))
                (make-directory dir t))
              (should-not (suderman/project-try-work unclaimed))
              (should-not (suderman/project-try-work unclaimed-data))
              (should-not (project-current nil unclaimed-data))
              (dolist (dir (list unclaimed outside))
                (should (= (process-file "git" nil nil nil "-C" dir "init" "-q") 0))
                (should (eq (car (project-current nil dir)) 'vc))))))
      (mapc #'kill-buffer buffers)
      (delete-directory home t))))

;; Clipboard selection

(ert-deftest suderman/terminal-copy-routes-to-local-or-remote-clipboard ()
  (let (selection copied output osc52 graphical ssh wayland)
    (setq wayland t)
    (cl-letf (((symbol-function 'gui-select-text)
               (lambda (text) (setq selection text)))
              ((symbol-function 'display-graphic-p)
               (lambda (&rest _) graphical))
              ((symbol-function 'terminal-parameter)
               (lambda (&rest _) osc52))
              ((symbol-function 'getenv)
               (lambda (name &rest _)
                 (pcase name
                   ("WAYLAND_DISPLAY" wayland)
                   ("SSH_CONNECTION" ssh))))
              ((symbol-function 'executable-find) (lambda (&rest _) "wl-copy"))
              ((symbol-function 'call-process-region)
               (lambda (beg end &rest _)
                 (setq copied (buffer-substring-no-properties beg end))
                 0))
              ((symbol-function 'send-string-to-terminal)
               (lambda (text &rest _) (setq output text))))
      (suderman/select-text "CSV,α\n")
      (should (equal selection copied))
      (should-not output)
      (setq copied nil ssh t)
      (suderman/select-text "remote,α\n")
      (should-not copied)
      (should (equal output (concat "\e]52;c;"
                                    (base64-encode-string
                                     (encode-coding-string "remote,α\n" 'utf-8-unix) t)
                                    "\a")))
      (setq output nil ssh nil wayland nil)
      (suderman/select-text "remote in Herdr")
      (should (equal output "\e]52;c;cmVtb3RlIGluIEhlcmRy\a"))
      (setq output nil osc52 t)
      (suderman/select-text "native")
      (should-not output)
      (setq osc52 nil graphical t)
      (suderman/select-text "graphical")
      (should-not output))))

;; Large-file behavior

(ert-deftest suderman/so-long-keeps-long-code-writable-and-cheap-to-display ()
  (with-temp-buffer
    (insert (make-string (1+ so-long-threshold) ?x) "\n")
    (setq buffer-file-name "/tmp/suderman-so-long.el")
    (let ((so-long-invisible-buffer-function nil))
      (set-auto-mode))
    (should so-long-minor-mode)
    (should (derived-mode-p 'emacs-lisp-mode))
    (should-not buffer-read-only)
    (should-not visual-line-mode)
    (should-not display-fill-column-indicator-mode)
    (should-not (bound-and-true-p indent-bars-mode)))
  (with-temp-buffer
    (insert "(message \"short\")\n")
    (setq buffer-file-name "/tmp/suderman-short.el")
    (let ((so-long-invisible-buffer-function nil))
      (set-auto-mode))
    (should-not (bound-and-true-p so-long-minor-mode))
    (should (derived-mode-p 'emacs-lisp-mode))))


;; Formatting

(ert-deftest suderman/treefmt-uses-the-source-buffer-environment ()
  (let* ((directory (make-temp-file "suderman-treefmt-" t))
         (source-file (expand-file-name "sample.nix" directory))
         (source (generate-new-buffer " *suderman-treefmt-source*"))
         (scratch (generate-new-buffer " *suderman-treefmt-scratch*"))
         captured callback-called)
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "treefmt.nix" directory))
          (with-current-buffer source
            (setq buffer-file-name source-file)
            (setq-local exec-path '("/source/bin"))
            (setq-local process-environment '("SOURCE_ENV=1")))
          (with-current-buffer scratch
            (insert "{ value = true; }\n"))
          (cl-letf (((symbol-function 'process-file)
                     (lambda (&rest _)
                       (setq captured
                             (list exec-path process-environment
                                   default-directory))
                       0)))
            (suderman/formatting-treefmt
             :buffer source
             :scratch scratch
             :callback (lambda (&optional error)
                         (should-not error)
                         (setq callback-called t))))
          (should callback-called)
          (should (equal captured
                         (list '("/source/bin") '("SOURCE_ENV=1")
                               (file-name-as-directory directory)))))
      (kill-buffer source)
      (kill-buffer scratch)
      (delete-directory directory t))))


;; Android package bootstrap

(ert-deftest suderman/android-package-keyring-is-materialized-for-gpg ()
  (let ((system-type 'android)
        imported-file
        imported-content)
    (cl-letf (((symbol-function 'copy-file)
               (lambda (source destination &rest _)
                 (should (equal source "/assets/etc/package-keyring.gpg"))
                 (with-temp-file destination
                   (set-buffer-multibyte nil)
                   (insert "keyring")))))
      (suderman/package-import-keyring-from-android-assets
       (lambda (file)
         (setq imported-file file)
         (should-not (string-prefix-p "/assets/" file))
         (setq imported-content
               (with-temp-buffer
                 (insert-file-contents-literally file)
                 (buffer-string))))
       "/assets/etc/package-keyring.gpg"))
    (should (equal imported-content "keyring"))
    (should-not (file-exists-p imported-file))))

(ert-deftest suderman/physical-package-keyring-passes-through-unchanged ()
  (let ((system-type 'android)
        imported-file)
    (suderman/package-import-keyring-from-android-assets
     (lambda (file) (setq imported-file file))
     "/tmp/package-keyring.gpg")
    (should (equal imported-file "/tmp/package-keyring.gpg"))))


;; Hot reload

(ert-deftest suderman/reload-reads-source-when-emacs-loaded-init-elc ()
  (let ((user-init-file "/tmp/emacs/init.elc"))
    (should (equal (suderman/reload--user-init-file)
                   "/tmp/emacs/init.el"))))

(ert-deftest suderman/reload-loads-keys-after-command-modules ()
  (let ((modules (suderman/reload--config-modules)))
    (should (eq (car (last modules)) 'suderman-keys))
    (should (< (seq-position modules 'suderman-formatting)
               (seq-position modules 'suderman-keys)))
    (should-not (memq 'suderman-reload modules))))

(ert-deftest suderman/org-unload-removes-theme-callback ()
  (let ((enable-theme-functions '(suderman/org-apply-heading-faces
                                  other-theme-callback)))
    (should-not (suderman-org-unload-function))
    (should (equal enable-theme-functions '(other-theme-callback)))))


;; Window layouts

(ert-deftest suderman/zoom-window-toggle-restores-side-windows ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((left (selected-window))
           (right (split-window-right))
           (side (display-buffer-in-side-window
                  (get-buffer-create " *zoom-window-side-test*")
                  '((side . left)))))
      (select-window left)
      (suderman/zoom-window-toggle)
      (should (one-window-p))
      (suderman/zoom-window-toggle)
      (should (memq left (window-list)))
      (should (memq right (window-list)))
      (should (memq side (window-list))))))

(ert-deftest suderman/resize-window-moves-trailing-edge-in-nested-layout ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((left (selected-window))
           (middle (split-window-right))
           (right (with-selected-window middle (split-window-right)))
           (left-width (window-total-width left))
           (middle-width (window-total-width middle))
           (right-width (window-total-width right)))
      (select-window left)
      (suderman/resize-window-left)
      (should (= (window-total-width left) (- left-width 5)))
      (should (= (window-total-width middle) (+ middle-width 5)))
      (should (= (window-total-width right) right-width))
      (balance-windows)
      (select-window middle)
      (setq left-width (window-total-width left)
            middle-width (window-total-width middle)
            right-width (window-total-width right))
      (suderman/resize-window-left)
      (should (= (window-total-width left) left-width))
      (should (= (window-total-width middle) (- middle-width 5)))
      (should (= (window-total-width right) (+ right-width 5)))
      (balance-windows)
      (select-window right)
      (setq left-width (window-total-width left)
            middle-width (window-total-width middle)
            right-width (window-total-width right))
      (suderman/resize-window-left)
      (should (= (window-total-width left) left-width))
      (should (= (window-total-width middle) (- middle-width 5)))
      (should (= (window-total-width right) (+ right-width 5))))
    (delete-other-windows)
    (let* ((top (selected-window))
           (middle (split-window-below))
           (bottom (with-selected-window middle (split-window-below)))
           (top-height (window-total-height top))
           (middle-height (window-total-height middle))
           (bottom-height (window-total-height bottom)))
      (select-window top)
      (suderman/resize-window-up)
      (should (= (window-total-height top) (- top-height 3)))
      (should (= (window-total-height middle) (+ middle-height 3)))
      (should (= (window-total-height bottom) bottom-height))
      (balance-windows)
      (select-window middle)
      (setq top-height (window-total-height top)
            middle-height (window-total-height middle)
            bottom-height (window-total-height bottom))
      (suderman/resize-window-up)
      (should (= (window-total-height top) top-height))
      (should (= (window-total-height middle) (- middle-height 3)))
      (should (= (window-total-height bottom) (+ bottom-height 3)))
      (balance-windows)
      (select-window bottom)
      (setq top-height (window-total-height top)
            middle-height (window-total-height middle)
            bottom-height (window-total-height bottom))
      (suderman/resize-window-up)
      (should (= (window-total-height top) top-height))
      (should (= (window-total-height middle) (- middle-height 3)))
      (should (= (window-total-height bottom) (+ bottom-height 3))))))


;; Shared appearance

(ert-deftest suderman/base16-gnus-faces-avoid-emacs-31-inheritance-cycles ()
  (let (faces transformed)
    (dolist (group '(mail news))
      (dotimes (index 6)
        (let* ((level (1+ index))
               (face (intern (format "gnus-group-%s-%d" group level)))
               (empty-face (intern (format "%s-empty" face)))
               (outline (intern (format "outline-%d" level))))
          (push `(,face :inherit ,outline) faces)
          (push `(,empty-face :foreground base04 :inherit ,face) faces))))
    (push '(default :foreground base05) faces)
    (let ((original (copy-tree faces)))
      (suderman/base16-theme-set-faces-without-gnus-cycles
       (lambda (_theme _colors fixed-faces)
         (setq transformed fixed-faces))
       'base16-test nil faces)
      (should (equal faces original)))
    (dolist (face transformed)
      (when (string-match
             "\\`\\(gnus-group-\\(?:mail\\|news\\)-[1-6]\\)-empty\\'"
             (symbol-name (car face)))
        (let* ((base-face (intern (match-string 1 (symbol-name (car face)))))
               (base-inherit (plist-get (cdr (assq base-face transformed)) :inherit)))
          (should (eq (plist-get (cdr face) :inherit) base-inherit)))))
    (should (equal (assq 'default transformed)
                   '(default :foreground base05)))))

(ert-deftest suderman/line-number-toggle-preserves-special-buffer-exclusions ()
  (let ((original-state global-display-line-numbers-mode)
        (text-buffer (generate-new-buffer " *suderman-line-numbers-text*"))
        (special-buffer (generate-new-buffer " *suderman-line-numbers-special*"))
        (image-buffer (generate-new-buffer " *suderman-line-numbers-image*")))
    (unwind-protect
        (progn
          (with-current-buffer text-buffer
            (text-mode))
          (with-current-buffer special-buffer
            (special-mode))
          (with-current-buffer image-buffer
            (setq major-mode 'image-mode))
          (unless global-display-line-numbers-mode
            (global-display-line-numbers-mode 1)
            (suderman/disable-line-numbers-in-special-buffers))

          (suderman/toggle-line-numbers)
          (should-not global-display-line-numbers-mode)
          (should-not (buffer-local-value 'display-line-numbers-mode text-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode special-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode image-buffer))

          (suderman/toggle-line-numbers)
          (should global-display-line-numbers-mode)
          (should (buffer-local-value 'display-line-numbers-mode text-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode special-buffer))
          (should-not (buffer-local-value 'display-line-numbers-mode image-buffer)))
      (global-display-line-numbers-mode (if original-state 1 -1))
      (when original-state
        (suderman/disable-line-numbers-in-special-buffers))
      (kill-buffer text-buffer)
      (kill-buffer special-buffer)
      (kill-buffer image-buffer))))

(ert-deftest suderman/shared-style-is-optional-and-reloadable ()
  (let ((directory (make-temp-file "emacs-style-" t))
        (suderman/system-style '(:mono-font "old")))
    (unwind-protect
        (let ((file (expand-file-name "style.el" directory)))
          (suderman/load-system-style file)
          (should-not suderman/system-style)
          (with-temp-file file
            (insert ";;; -*- lexical-binding: t; -*-\n"
                    "(setq suderman/system-style '(:mono-font \"Example\" :font-size 12.0))"))
          (suderman/load-system-style file)
          (should (equal (plist-get suderman/system-style :mono-font) "Example")))
      (delete-directory directory t))))

(ert-deftest suderman/system-palettes-switch-without-stacking-themes ()
  (let* ((colors (cl-loop for index below 16
                          append (list (intern (format ":base%02X" index))
                                       "#777777")))
         (light (plist-put (copy-sequence colors) :base00 "#ffffff"))
         (dark (plist-put (copy-sequence colors) :base00 "#111111"))
         (suderman/system-style (list :palettes (list :light light :dark dark)))
         (original-themes custom-enabled-themes)
         (toolkit-theme 'light)
         setting-count)
    (unwind-protect
        (cl-letf (((symbol-function 'suderman/load-system-style) #'ignore))
          ;; Startup reads the current toolkit value, not a separate preference.
          (suderman/apply-system-palette)
          (should (equal custom-enabled-themes '(suderman-light)))
          (setq setting-count (length (get 'suderman-light 'theme-settings)))
          ;; Face corrections must replace Base16 entries, not create duplicates.
          (should (= setting-count
                     (length (delete-dups
                              (mapcar #'cadr (get 'suderman-light 'theme-settings))))))
          (dolist (appearance '(dark light light dark light))
            (run-hook-with-args 'toolkit-theme-set-functions appearance)
            (let* ((theme (if (eq appearance 'light) 'suderman-light 'suderman-dark))
                   (setting (cl-find 'default (get theme 'theme-settings) :key #'cadr)))
              (should (equal custom-enabled-themes (list theme)))
              (should (= setting-count (length (get theme 'theme-settings))))
              ;; Inspect the graphic spec even when this test runs in batch.
              (should (equal (plist-get (cadar (nth 3 setting)) :background)
                             (if (eq appearance 'light) "#ffffff" "#111111")))))
          ;; Re-read palette data even when the appearance has not changed.
          (setf (plist-get light :base00) "#eeeeee")
          (suderman/apply-system-palette 'light)
          (let ((setting (cl-find 'default (get 'suderman-light 'theme-settings)
                                  :key #'cadr)))
            (should (equal (plist-get (cadar (nth 3 setting)) :background)
                           "#eeeeee"))))
      (mapc #'disable-theme custom-enabled-themes)
      (mapc #'enable-theme (reverse original-themes)))))

(ert-deftest suderman/missing-system-palettes-preserve-current-theme ()
  (let ((suderman/system-style nil)
        (original-themes custom-enabled-themes))
    (cl-letf (((symbol-function 'suderman/load-system-style) #'ignore))
      (dolist (appearance '(light dark nil))
        (suderman/apply-system-palette appearance)
        (should (equal custom-enabled-themes original-themes))))))

(ert-deftest suderman/shared-fonts-are-gui-only-and-keep-point-sizes ()
  (let ((suderman/system-style '(:mono-font "Mono" :fallback-font "Fallback"
                                :variable-font "Prose" :font-size 12.0))
        (system-type 'gnu/linux)
        calls fontsets)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
              ((symbol-function 'find-font) (lambda (&rest _) t))
              ((symbol-function 'set-face-attribute)
               (lambda (face frame &rest attributes)
                 (push (list face frame attributes) calls)))
              ((symbol-function 'suderman/set-nerd-font-fallbacks) #'ignore)
              ((symbol-function 'set-fontset-font)
               (lambda (&rest args) (push args fontsets))))
      (suderman/apply-system-fonts)
      (should-not fontsets)
      (should (equal (font-get (plist-get (caddr (assq 'default calls)) :font) :size)
                     12.0))
      (should (equal (plist-get (caddr (assq 'fixed-pitch calls)) :family) "Mono"))
      (should (equal (plist-get (caddr (assq 'variable-pitch calls)) :family) "Prose"))
      (setq calls nil)
      (let ((system-type 'android))
        (suderman/apply-system-fonts)
        (should (= (font-get (plist-get (caddr (assq 'default calls)) :font) :size)
                   17.0))
        (should (equal (nreverse fontsets)
                       (list (list t nil (font-spec :family "Mono") nil 'append)
                             (list t nil (font-spec :family "Fallback") nil 'append)))))
      (setq calls nil fontsets nil)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) nil)))
        (suderman/apply-system-fonts)
        (should-not calls)
        (should-not fontsets))
      (let ((system-type 'android))
        (cl-letf (((symbol-function 'find-font) (lambda (&rest _) nil)))
          (suderman/apply-system-fonts)
          (should-not calls)
          (should-not fontsets))))))

(provide 'suderman-core-test)
;;; suderman-core-test.el ends here
