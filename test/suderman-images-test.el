;;; suderman-images-test.el --- Focused Image mode checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-images-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'ert)
(require 'image-mode)
(require 'suderman-images)

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

(ert-deftest suderman/image-mode-owns-navigation-and-transform-bindings ()
  (dolist (binding '(("," . suderman/ibuffer-toggle)
                     ("." . suderman/dirvish)
                     ("c" . suderman/image-copy-to-clipboard)
                     ("n" . suderman/image-next-file)
                     ("p" . suderman/image-previous-file)
                     ("=" . image-increase-size)
                     ("+" . image-increase-size)
                     ("-" . image-decrease-size)
                     ("r" . image-rotate)
                     ("R" . suderman/image-rotate-counterclockwise)
                     ("0" . image-transform-reset-to-initial)))
    (should (eq (lookup-key image-mode-map (kbd (car binding)))
                (cdr binding))))
  (should image-animate-loop)
  (should (memq #'suderman/image-mode-setup image-mode-hook))
  (should (memq #'suderman/image-mode-setup find-file-hook))
  (should-not (lookup-key meow-motion-state-keymap (kbd "c"))))

(ert-deftest suderman/image-gallery-uses-xdg-thumbnails-and-owned-bindings ()
  (should (eq image-dired-thumbnail-storage 'standard-large))
  (dolist (map (list dired-mode-map dirvish-mode-map))
    (should (eq (lookup-key map (kbd "G"))
                #'suderman/image-dired-gallery)))
  (dolist (binding '(("h" . image-dired-backward-image)
                     ("j" . image-dired-next-line)
                     ("k" . image-dired-previous-line)
                     ("l" . image-dired-forward-image)
                     ("RET" . suderman/image-dired-display)
                     ("SPC" . meow-keypad)
                     ("g" . suderman/image-dired-refresh)
                     ("q" . suderman/image-dired-quit)
                     ("x" . suderman/image-dired-delete)))
    (should (eq (lookup-key image-dired-thumbnail-mode-map
                            (kbd (car binding)))
                (cdr binding))))
  (should (eq (lookup-key image-dired-image-mode-map (kbd "q"))
              #'suderman/image-dired-return-to-gallery))
  (should (eq (lookup-key image-dired-image-mode-map (kbd "n"))
              #'suderman/image-dired-display-next))
  (should (eq (lookup-key image-dired-image-mode-map (kbd "p"))
              #'suderman/image-dired-display-previous))
  (should (memq #'suderman/image-dired-setup
                image-dired-thumbnail-mode-hook)))

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

(provide 'suderman-images-test)
;;; suderman-images-test.el ends here
