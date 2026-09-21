;;; suderman-files-test.el --- File and view behavior checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for custom behavior with enough moving parts to merit a safety net.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'image-mode)
(require 'suderman-dashboard)
(require 'suderman-files)
(require 'suderman-images)
(require 'suderman-markdown)

;; Dashboard behavior

(ert-deftest suderman/dashboard-is-only-the-bare-startup-buffer ()
  (let (command-line-args-left)
    (should (eq (suderman/dashboard-initial-buffer-choice)
                #'dashboard-open)))
  (let ((command-line-args-left '("COMMIT_EDITMSG")))
    (should-not (suderman/dashboard-initial-buffer-choice))))

(ert-deftest suderman/dashboard-closes-full-frame-dirvish-first ()
  (let ((session (make-dirvish :curr-layout t :root-window (selected-window)))
        calls)
    (cl-letf (((symbol-function 'dirvish-curr) (lambda () session))
              ((symbol-function 'dirvish-quit)
               (lambda () (push 'quit calls)))
              ((symbol-function 'dashboard-open)
               (lambda () (push 'open calls))))
      (suderman/dashboard))
    (should (equal (nreverse calls) '(quit open)))))

(ert-deftest suderman/dashboard-filters-and-renumbers-missing-destinations ()
  (let ((user-emacs-directory "/config/emacs/")
        (existing (list (expand-file-name "~/") "/config/emacs/")))
    (cl-letf (((symbol-function 'file-directory-p)
               (lambda (path) (member path existing)))
              ((symbol-function 'suderman/nerd-fonts-available-p) #'ignore))
      (let ((buttons (suderman/dashboard-destinations)))
        (should (equal (mapcar #'car buttons) '("Home" "Emacs" "Scratch")))
        (should (equal (mapcar #'cadr buttons) '("1" "2" "3")))))))

(ert-deftest suderman/dashboard-moves-between-buttons-spatially ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert "  ")
      (widget-create 'push-button :tag "Work" :action #'ignore)
      (insert "        ")
      (widget-create 'push-button :tag "Personal" :action #'ignore)
      (insert "\n\nProjects:\n  ")
      (widget-create 'push-button :tag "Alpha" :action #'ignore)
      (insert "       ")
      (widget-create 'push-button :tag "Beta" :action #'ignore)
      (dashboard-mode)
      (cl-labels ((label ()
                    (substring-no-properties
                     (widget-get (get-char-property (point) 'button) :tag))))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "l"))
        (should (equal (label) "Personal"))
        (execute-kbd-macro (kbd "h"))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "j"))
        (should (equal (label) "Alpha"))
        (execute-kbd-macro (kbd "k"))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "h"))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "k"))
        (should (equal (label) "Work"))))))


;; Markdown preview

(ert-deftest suderman/markdown-preview-render-owns-its-target ()
  (let ((root (make-temp-file "markdown-preview-test-" t)))
    (unwind-protect
        (with-temp-buffer
          (insert "| A |\n|---|\n| B |\n")
          (let ((suderman/markdown-preview-server-root root)
                (suderman/markdown-preview-css "<style>table { width: 100%; }</style>"))
            (cl-letf (((symbol-function 'executable-find) (lambda (_) "/bin/pandoc"))
                      ((symbol-function 'suderman/markdown-preview-server-start)
                       (lambda ()
                         (setq suderman/markdown-preview-server-port 4321)))
                      ((symbol-function 'call-process-region)
                       (lambda (&rest arguments)
                         (with-temp-file (car (last arguments))
                           (insert "<colgroup><col></colgroup>\n<table><tr><td>A</td></tr></table>"))
                         0)))
              (should (equal (suderman/markdown-preview-render)
                             suderman/markdown-preview-file)))
            (should (file-exists-p suderman/markdown-preview-version-file))
            (should (string-prefix-p "http://127.0.0.1:4321/"
                                     suderman/markdown-preview-url))
            (let ((html-file suderman/markdown-preview-file))
              (with-temp-buffer
                (insert-file-contents html-file)
                (should-not (search-forward "<colgroup" nil t))
                (goto-char (point-min))
                (should (search-forward "<div class=\"table-wrapper\">" nil t))))))
      (delete-directory root t))))

(ert-deftest suderman/markdown-preview-cleanup-removes-buffer-files ()
  (with-temp-buffer
    (setq-local suderman/markdown-preview-file (make-temp-file "markdown-preview-"))
    (setq-local suderman/markdown-preview-version-file (make-temp-file "markdown-preview-version-"))
    (setq-local suderman/markdown-preview-url "http://127.0.0.1/preview.html")
    (let ((html-file suderman/markdown-preview-file)
          (version-file suderman/markdown-preview-version-file))
      (suderman/markdown-preview-cleanup)
      (should-not (file-exists-p html-file))
      (should-not (file-exists-p version-file))
      (should-not suderman/markdown-preview-file)
      (should-not suderman/markdown-preview-version-file)
      (should-not suderman/markdown-preview-url))))


;; Images and galleries

(ert-deftest suderman/image-copy-sends-static-image-data-with-its-mime-type ()
  (with-temp-buffer
    (setq-local buffer-file-name "/tmp/example.png")
    (let (call)
      (cl-letf (((symbol-function 'file-readable-p) (lambda (_) t))
                ((symbol-function 'file-remote-p) (lambda (_) nil))
                ((symbol-function 'mailcap-file-name-to-mime-type)
                 (lambda (_) "image/png"))
                ((symbol-function 'executable-find) (lambda (_) "/bin/wl-copy"))
                ((symbol-function 'call-process)
                 (lambda (&rest arguments)
                   (setq call arguments)
                   0)))
        (suderman/image-copy-to-clipboard))
      (should (equal call '("wl-copy" "/tmp/example.png" nil nil
                            "--type" "image/png"))))))

(ert-deftest suderman/image-copy-sends-gifs-as-local-files ()
  (with-temp-buffer
    (setq-local buffer-file-name "/tmp/example gif.gif")
    (let (call)
      (cl-letf (((symbol-function 'file-readable-p) (lambda (_) t))
                ((symbol-function 'file-remote-p) (lambda (_) nil))
                ((symbol-function 'mailcap-file-name-to-mime-type)
                 (lambda (_) "image/gif"))
                ((symbol-function 'executable-find) (lambda (_) "/bin/wl-copy"))
                ((symbol-function 'call-process)
                 (lambda (&rest arguments)
                   (setq call arguments)
                   0)))
        (suderman/image-copy-to-clipboard))
      (should (equal call '("wl-copy" nil nil nil
                            "--type" "text/uri-list"
                            "file:///tmp/example%20gif.gif"))))))

(ert-deftest suderman/image-copy-requires-a-local-image-file ()
  (with-temp-buffer
    (should-error (suderman/image-copy-to-clipboard) :type 'user-error))
  (with-temp-buffer
    (setq-local buffer-file-name "/tmp/example.txt")
    (cl-letf (((symbol-function 'file-readable-p) (lambda (_) t))
              ((symbol-function 'file-remote-p) (lambda (_) nil))
              ((symbol-function 'mailcap-file-name-to-mime-type)
               (lambda (_) "text/plain")))
      (should-error (suderman/image-copy-to-clipboard) :type 'user-error))))

(ert-deftest suderman/image-gallery-image-keeps-its-private-thumbnail-buffer ()
  (let ((gallery (generate-new-buffer " *image-gallery-test*"))
        (image (generate-new-buffer " *image-gallery-image-test*"))
        displayed)
    (unwind-protect
        (save-window-excursion
          (with-current-buffer gallery
            (image-dired-thumbnail-mode)
            (setq-local image-dired-thumbnail-buffer (buffer-name gallery)
                        image-dired-display-image-buffer (buffer-name image)
                        image-dired-track-movement nil)
            (let ((inhibit-read-only t))
              (insert (propertize "a" 'image-dired-thumbnail t
                                  'original-file-name "/tmp/a.png")
                      " "
                      (propertize "b" 'image-dired-thumbnail t
                                  'original-file-name "/tmp/b.png")
                      " "
                      (propertize "c" 'image-dired-thumbnail t
                                  'original-file-name "/tmp/c.png")))
            (goto-char (point-min)))
          (switch-to-buffer gallery)
          (cl-letf (((symbol-function 'image-dired-display-this)
                     (lambda () (switch-to-buffer image))))
            (suderman/image-dired-display))
          (with-current-buffer image
            (should (eq suderman/image-dired-gallery-buffer gallery))
            (should (equal image-dired-thumbnail-buffer
                           (buffer-name gallery)))
            (should (equal image-dired-display-image-buffer
                           (buffer-name image))))
          (cl-letf (((symbol-function 'image-dired-display-image)
                     (lambda (file)
                       (setq displayed file)
                       (with-current-buffer image
                         (kill-all-local-variables)))))
            (with-current-buffer image
              (suderman/image-dired-display-next 1))
            (should (equal displayed "/tmp/b.png"))
            (with-current-buffer image
              (suderman/image-dired-display-next 1))
            (should (equal displayed "/tmp/c.png"))
            (with-current-buffer image
              (suderman/image-dired-display-previous 1))
            (should (equal displayed "/tmp/b.png"))))
      (kill-buffer gallery)
      (kill-buffer image))))

(ert-deftest suderman/image-gallery-lists-only-top-level-images ()
  (let* ((directory (make-temp-file "suderman-image-gallery-" t))
         (nested (expand-file-name "nested" directory))
         (image (expand-file-name "one.png" directory))
         (upper-image (expand-file-name "two.JPG" directory))
         (text (expand-file-name "notes.txt" directory))
         (nested-image (expand-file-name "three.webp" nested))
         buffer)
    (unwind-protect
        (progn
          (make-directory nested)
          (dolist (file (list image upper-image text nested-image))
            (write-region "" nil file))
          (let (dired-buffers)
            (setq buffer
                  (dired-internal-noselect
                   (file-name-as-directory directory)
                   dired-listing-switches)))
          (should (equal (suderman/image-dired--files buffer)
                         (list image upper-image))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest suderman/image-gallery-leaves-an-empty-directory-untouched ()
  (let* ((directory (make-temp-file "suderman-empty-gallery-" t))
         buffer)
    (unwind-protect
        (save-window-excursion
          (let (dired-buffers)
            (setq buffer
                  (dired-internal-noselect
                   (file-name-as-directory directory)
                   dired-listing-switches)))
          (set-window-buffer (selected-window) buffer)
          (let ((windows (window-list)))
            (should-error (suderman/image-dired-gallery) :type 'user-error)
            (should (equal (window-list) windows))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest suderman/image-gallery-restores-its-dirvish-window ()
  (let* ((directory (make-temp-file "suderman-gallery-window-" t))
         (image (expand-file-name "photo.png" directory))
         source gallery source-window windows)
    (unwind-protect
        (save-window-excursion
          (write-region "" nil image)
          (let (dired-buffers)
            (setq source
                  (dired-internal-noselect
                   (file-name-as-directory directory)
                   dired-listing-switches)))
          (delete-other-windows)
          (set-window-buffer (selected-window) source)
          (setq source-window (selected-window))
          (split-window-right)
          (select-window source-window)
          (setq windows (window-list))
          (cl-letf (((symbol-function 'suderman/image-dired--populate)
                     (lambda (buffer backing files _selected-file)
                       (should (equal files (list image)))
                       (with-current-buffer buffer
                         (let ((inhibit-read-only t))
                           (erase-buffer)
                           (insert (propertize "x"
                                               'image-dired-thumbnail t
                                               'original-file-name image
                                               'associated-dired-buffer
                                               backing))
                           (goto-char (point-min)))))))
            (suderman/image-dired-gallery))
          (setq gallery (current-buffer))
          (should (derived-mode-p 'image-dired-thumbnail-mode))
          (should (= (length (window-list)) 1))
          (should (eq (get-text-property
                       (point) 'associated-dired-buffer)
                      source))
          (suderman/image-dired-quit)
          (should (eq (selected-window) source-window))
          (should (equal (window-list) windows))
          (should (eq (window-buffer source-window) source))
          (should (equal (with-selected-window source-window
                           (dired-get-filename nil t))
                         image)))
      (when (buffer-live-p gallery)
        (with-current-buffer gallery
          (setq suderman/image-dired-window-configuration nil
                suderman/image-dired-source-buffer nil
                suderman/image-dired-source-window nil))
        (kill-buffer gallery))
      (when (buffer-live-p source)
        (kill-buffer source))
      (delete-directory directory t))))

(ert-deftest suderman/image-gallery-updates-count-after-deletion ()
  (with-temp-buffer
    (image-dired-thumbnail-mode)
    (let ((inhibit-read-only t))
      (insert (propertize "x" 'image-dired-thumbnail t) " "
              (propertize "x" 'image-dired-thumbnail t)))
    (setq image-dired--number-of-thumbnails 2)
    (cl-letf (((symbol-function 'image-dired-do-flagged-delete)
               (lambda ()
                 (let ((inhibit-read-only t))
                   (delete-region (point-min) (+ (point-min) 2)))))
              ((symbol-function 'image-dired--update-header-line) #'ignore))
      (suderman/image-dired-delete))
    (should (= image-dired--number-of-thumbnails 1))))


;; Dirvish and file operations

(ert-deftest suderman/android-dired-tap-opens-in-current-window ()
  (dolist (android '(nil t))
    (let ((system-type (if android 'android 'gnu/linux))
          same-window other-window)
      (cl-letf (((symbol-function 'suderman/dired-mouse-open)
                 (lambda (event) (setq same-window event)))
                ((symbol-function 'dired-mouse-find-file-other-window)
                 (lambda (event) (setq other-window event))))
        (suderman/dired-mouse-secondary-open 'tap)
        (if android
            (progn
              (should (eq same-window 'tap))
              (should-not other-window))
          (should-not same-window)
          (should (eq other-window 'tap)))))))

(ert-deftest suderman/dirvish-normalizes-layout-from-an-ambient-buffer ()
  (save-window-excursion
    (let* ((root-buffer (generate-new-buffer " *suderman-dirvish-root*"))
           (root-window (selected-window))
           (session (make-dirvish :curr-layout 'full-frame
                                  :root-window root-window))
           toggled)
      (unwind-protect
          (progn
            (set-window-buffer root-window root-buffer)
            (with-temp-buffer
              (cl-letf (((symbol-function 'dirvish-curr)
                         (lambda ()
                           (and (eq (current-buffer) root-buffer) session)))
                        ((symbol-function 'dirvish) #'ignore)
                        ((symbol-function 'dirvish-layout-toggle)
                         (lambda ()
                           (should (eq (selected-window) root-window))
                           (setq toggled t)
                           (setf (dv-curr-layout session) nil))))
                (suderman/dirvish "/tmp/")))
            (should toggled)
            (should-not (dv-curr-layout session)))
        (kill-buffer root-buffer)))))

(ert-deftest suderman/dired-paste-image-preserves-binary-and-avoids-collisions ()
  (let* ((directory (make-temp-file "suderman-paste-image-" t))
         (timestamp "20260910-141600")
         (existing (expand-file-name
                    (format "screenshot-%s.png" timestamp) directory))
         (expected (expand-file-name
                    (format "screenshot-%s-2.png" timestamp) directory))
         (png (unibyte-string #x89 #x50 #x4e #x47 #x0d #x0a #x1a #x0a
                              #x00 #xff))
         (call-process-function (symbol-function 'call-process))
         process-directories process-coding buffer)
    (unwind-protect
        (progn
          (write-region "occupied" nil existing)
          (setq buffer (dired-noselect directory))
          (with-current-buffer buffer
            (cl-letf (((symbol-function 'executable-find)
                       (lambda (program)
                         (should (equal program "wl-paste"))
                         (should (equal default-directory "/"))
                         "/usr/bin/wl-paste"))
                      ((symbol-function 'call-process)
                       (lambda (program infile destination display &rest args)
                         (if (equal program "/usr/bin/wl-paste")
                             (progn
                               (push default-directory process-directories)
                               (push coding-system-for-read process-coding)
                               (should-not enable-multibyte-characters)
                               (insert (if (equal args '("--list-types"))
                                           "text/plain\nimage/png\n"
                                         png))
                               0)
                           (apply call-process-function program infile
                                  destination display args))))
                      ((symbol-function 'format-time-string)
                       (lambda (&rest _) timestamp)))
              (suderman/dired-paste-image)))
          (should (equal process-directories '("/" "/")))
          (should (equal process-coding '(binary binary)))
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert-file-contents-literally expected)
            (should (equal (buffer-string) png)))
          (with-current-buffer buffer
            (should (equal (dired-get-filename nil t) expected))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest suderman/dired-paste-image-reports-clipboard-errors ()
  (dolist (case '((types-fail . "Could not inspect clipboard types")
                  (text . "Clipboard does not contain image/png")
                  (read-fail . "Could not read PNG image")
                  (empty . "Clipboard returned no PNG image data")))
    (with-temp-buffer
      (let ((default-directory temporary-file-directory)
            (calls 0))
        (cl-letf (((symbol-function 'dired-current-directory)
                   (lambda () temporary-file-directory))
                  ((symbol-function 'executable-find)
                   (lambda (_) "/usr/bin/wl-paste"))
                  ((symbol-function 'call-process)
                   (lambda (&rest _)
                     (cl-incf calls)
                     (pcase (car case)
                       ('types-fail 1)
                       ('text (insert "text/plain\n") 0)
                       ('read-fail
                        (if (= calls 1) (progn (insert "image/png\n") 0) 1))
                       ('empty
                        (when (= calls 1) (insert "image/png\n"))
                        0)))))
          (let ((error (should-error (suderman/dired-paste-image)
                                     :type 'user-error)))
            (should (string-match-p (cdr case) (error-message-string error)))))))))

(ert-deftest suderman/dired-paste-image-keeps-wl-paste-local-for-tramp ()
  (with-temp-buffer
    (let ((remote-directory "/ssh:server:/path/to/directory/")
          (calls 0)
          written refreshed selected)
      (cl-letf (((symbol-function 'dired-current-directory)
                 (lambda () remote-directory))
                ((symbol-function 'executable-find)
                 (lambda (_)
                   (should (equal default-directory "/"))
                   "/usr/bin/wl-paste"))
                ((symbol-function 'call-process)
                 (lambda (&rest _)
                   (should (equal default-directory "/"))
                   (cl-incf calls)
                   (insert (if (= calls 1) "image/png\n" "png"))
                   0))
                ((symbol-function 'write-region)
                 (lambda (_start _end file &rest _)
                   (setq written file)))
                ((symbol-function 'revert-buffer)
                 (lambda (&rest _) (setq refreshed t)))
                ((symbol-function 'dired-goto-file)
                 (lambda (file) (setq selected file))))
        (suderman/dired-paste-image))
      (should (string-prefix-p
               (concat remote-directory "screenshot-") written))
      (should (equal selected written))
      (should refreshed))))

(ert-deftest suderman/dired-paste-image-reports-missing-command-and-write-errors ()
  (with-temp-buffer
    (cl-letf (((symbol-function 'dired-current-directory) (lambda () "/missing/"))
              ((symbol-function 'executable-find) #'ignore))
      (should-error (suderman/dired-paste-image) :type 'user-error
                    :exclude-subtypes nil))
    (let ((calls 0))
      (cl-letf (((symbol-function 'dired-current-directory) (lambda () "/missing/"))
                ((symbol-function 'executable-find)
                 (lambda (_) "/usr/bin/wl-paste"))
                ((symbol-function 'call-process)
                 (lambda (&rest _)
                   (cl-incf calls)
                   (insert (if (= calls 1) "image/png\n" "png"))
                   0)))
        (let ((error (should-error (suderman/dired-paste-image)
                                   :type 'user-error)))
          (should (string-match-p "Could not write PNG image"
                                  (error-message-string error))))))))

(ert-deftest suderman/dirvish-windmove-rejects-breadcrumb-window ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((window (split-window-right))
           (buffer (generate-new-buffer " *dirvish-misc-test*")))
      (unwind-protect
          (progn
            (set-window-buffer window buffer)
            (with-current-buffer buffer (dirvish-misc-mode))
            (should-not
             (suderman/dirvish-ignore-misc-window
              (lambda (&rest _) window)))
            (with-current-buffer buffer (fundamental-mode))
            (should
             (eq (suderman/dirvish-ignore-misc-window
                  (lambda (&rest _) window))
                 window)))
        (kill-buffer buffer)))))

(ert-deftest suderman/dirvish-narrow-renders-after-live-update ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((root (selected-window))
           (session (make-dirvish :root-window root))
           events received)
      (cl-letf (((symbol-function 'dirvish-curr) (lambda () session))
                ((symbol-function 'dirvish--render-attrs)
                 (lambda (window selected)
                   (push (list 'render window selected) events))))
        (suderman/dirvish-render-after-narrow
         (lambda (action record callback debounce throttle)
           (setq received (list action record debounce throttle))
           (funcall callback 'input))
         "pdf" :narrow
         (lambda (input) (push (list 'update input) events))
         0.1 0.2)
        (should (equal received '("pdf" :narrow 0.1 0.2)))
        (should (equal (nreverse events)
                       `((update input) (render ,root ,root))))))))

(ert-deftest suderman/dirvish-parent-navigation-preserves-parent-focus ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((root (selected-window))
           (parent (split-window root nil 'left))
           navigation)
      (set-window-parameter parent 'no-other-window t)
      (select-window parent)
      (cl-letf (((symbol-function 'dirvish-curr) (lambda () 'session))
                ((symbol-function 'dv-root-window) (lambda (_) root))
                ((symbol-function 'dirvish--find-entry)
                 (lambda (find entry) (setq navigation (list find entry)))))
        (suderman/dirvish-parent-navigate "/tmp/next/")
        (should (equal navigation '(find-alternate-file "/tmp/next/")))
        (should (eq (selected-window) parent))))))

(ert-deftest suderman/dirvish-sidebar-open-preserves-editor-focus ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((editor (selected-window))
           (sidebar (split-window-right))
           opened)
      (cl-letf (((symbol-function 'dirvish-curr) #'ignore)
                ((symbol-function 'dirvish-side--session-visible-p) #'ignore)
                ((symbol-function 'dirvish-side)
                 (lambda (path)
                   (setq opened path)
                   (select-window sidebar))))
        (suderman/dirvish-side-toggle "/tmp/")
        (should (equal opened "/tmp/"))
        (should (eq (selected-window) editor))))))

(ert-deftest suderman/dirvish-sidebar-hide-preserves-editor-focus ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((editor (selected-window))
           (sidebar (split-window-right))
           quit-window)
      (select-window editor)
      (cl-letf (((symbol-function 'dirvish-curr) #'ignore)
                ((symbol-function 'dirvish-side--session-visible-p)
                 (lambda () sidebar))
                ((symbol-function 'dirvish-quit)
                 (lambda () (setq quit-window (selected-window)))))
        (suderman/dirvish-side-toggle)
        (should (eq quit-window sidebar))
        (should (eq (selected-window) editor))))))

(ert-deftest suderman/dirvish-breadcrumb-navigation-uses-root-window ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((root (selected-window))
           (misc (split-window-right))
           (misc-buffer (generate-new-buffer " *dirvish-misc-test*"))
           called-window)
      (unwind-protect
          (progn
            (set-window-buffer misc misc-buffer)
            (select-window misc)
            (with-current-buffer misc-buffer
              (dirvish-misc-mode)
              (cl-letf (((symbol-function 'dirvish-curr) (lambda () 'session))
                        ((symbol-function 'dv-root-window) (lambda (_) root)))
                (suderman/dirvish-find-entry-at-root
                 (lambda (_find _entry)
                   (setq called-window (selected-window)))
                 #'find-file "/tmp/")))
            (should (eq called-window root))
            (should (eq (selected-window) root)))
        (kill-buffer misc-buffer)))))

(ert-deftest suderman/dirvish-parent-file-click-centers-and-selects-file ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((root (selected-window))
           (parent (split-window-right))
           (file "/tmp/example.txt")
           navigation selected)
      (select-window parent)
      (cl-letf (((symbol-function 'event-start) (lambda (_) 'position))
                ((symbol-function 'posn-window) (lambda (_) parent))
                ((symbol-function 'posn-point) (lambda (_) 1))
                ((symbol-function 'dired-get-filename) (lambda (&rest _) file))
                ((symbol-function 'dirvish-curr) (lambda () 'session))
                ((symbol-function 'dv-root-window) (lambda (_) root))
                ((symbol-function 'file-directory-p) #'ignore)
                ((symbol-function 'dirvish--find-entry)
                 (lambda (find entry) (setq navigation (list find entry))))
                ((symbol-function 'dired-goto-file)
                 (lambda (entry) (setq selected entry))))
        (suderman/dirvish-parent-mouse-select 'event))
      (should (equal navigation '(find-alternate-file "/tmp/")))
      (should (equal selected file))
      (should (eq (selected-window) root)))))

(ert-deftest suderman/dirvish-gif-preview-loops-only-while-displayed ()
  (with-temp-buffer
    (insert (propertize " " 'display 'image-spec))
    (let ((recipe (cons 'buffer (current-buffer)))
          callback callback-arg animate-args)
      (cl-letf (((symbol-function 'dirvish--find-file-temporarily)
                 (lambda (_) recipe))
                ((symbol-function 'run-with-idle-timer)
                 (lambda (_seconds _repeat function argument)
                   (setq callback function callback-arg argument)))
                ((symbol-function 'image-animate)
                 (lambda (&rest args) (setq animate-args args))))
        (should (eq (dirvish-gif-dp "example.gif" "gif" nil nil) recipe))
        (funcall callback callback-arg)
        (should (equal animate-args '(image-spec nil t 1)))))))

(provide 'suderman-files-test)
;;; suderman-files-test.el ends here
