;;; suderman-markdown.el --- Markdown editing and live preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Markdown has enough custom behavior to deserve its own home: a Pandoc-backed
;; browser preview, table normalization, and mode-local bindings.

;;; Code:

(require 'subr-x)
(require 'use-package)

(defvar hs-treesit-things)
(declare-function suderman/meow-toggle-fold "suderman-meow" ())
(declare-function hs-overlay-at "hideshow" (position))
(declare-function hs-get-first-block-on-line "hideshow" ())
(declare-function suderman/enable-fold-taps "suderman-android" (line-p toggle))
(declare-function suderman/tap-repeats-p "suderman-android" (beg end))
(declare-function touch-screen-track-tap "touch-screen"
                  (event &optional update data threshold))
(declare-function suderman/goto-shown-line-end "suderman-meow" ())
(declare-function suderman/meow-insert "suderman-meow" ())
(declare-function markdown-ts-insert-list-item "markdown-ts-mode" ())
(declare-function markdown-ts-newline "markdown-ts-mode" ())

(defconst suderman/markdown-preview-css
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "assets/markdown-preview.html" user-emacs-directory))
    (buffer-string))
  "HTML header used for `suderman/markdown-preview-buffer'.")

(defvar suderman/markdown-preview-server-process nil
  "HTTP server process for Markdown previews.")

(defvar suderman/markdown-preview-server-port nil
  "HTTP server port for Markdown previews.")

(defvar suderman/markdown-preview-server-root
  (expand-file-name "suderman-emacs-markdown-preview/" temporary-file-directory)
  "Directory served by the Markdown preview HTTP server.")

(defvar-local suderman/markdown-preview-file nil
  "HTML file used for the current buffer's Markdown preview.")

(defvar-local suderman/markdown-preview-version-file nil
  "Version file polled by the current buffer's Markdown preview.")

(defvar-local suderman/markdown-preview-url nil
  "HTTP URL used for the current buffer's Markdown preview.")

(defun suderman/markdown-preview-server-send (proc status content-type body)
  "Send HTTP STATUS with CONTENT-TYPE and BODY to PROC."
  (process-send-string
   proc
   (format "HTTP/1.1 %s\r\nContent-Type: %s\r\nCache-Control: no-store\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
           status content-type (string-bytes body)))
  (process-send-string proc body)
  (delete-process proc))

(defun suderman/markdown-preview-server-handle (proc request)
  "Serve one Markdown preview HTTP REQUEST from PROC."
  (if (not (string-match "\\`GET \\([^ ?]+\\)" request))
      (suderman/markdown-preview-server-send proc "405 Method Not Allowed" "text/plain; charset=utf-8" "Method not allowed")
    (let* ((name (file-name-nondirectory (match-string 1 request)))
           (file (expand-file-name name suderman/markdown-preview-server-root)))
      (if (and (not (string-empty-p name))
               (file-regular-p file))
          (let ((body (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally file)
                        (buffer-string)))
                (content-type (if (string-suffix-p ".html" name)
                                  "text/html; charset=utf-8"
                                "text/plain; charset=utf-8")))
            (suderman/markdown-preview-server-send proc "200 OK" content-type body))
        (suderman/markdown-preview-server-send proc "404 Not Found" "text/plain; charset=utf-8" "Not found")))))

(defun suderman/markdown-preview-server-filter (proc chunk)
  "Collect HTTP request CHUNK from PROC and serve it when complete."
  (let ((request (concat (process-get proc 'request) chunk)))
    (if (string-match-p "\r\n\r\n" request)
        (suderman/markdown-preview-server-handle proc request)
      (process-put proc 'request request))))

(defun suderman/markdown-preview-server-start ()
  "Start the Markdown preview HTTP server if needed."
  (unless (process-live-p suderman/markdown-preview-server-process)
    (make-directory suderman/markdown-preview-server-root t)
    (setq suderman/markdown-preview-server-process
          (make-network-process
           :name "suderman-markdown-preview-server"
           :server t
           :host "127.0.0.1"
           :service 0
           :filter #'suderman/markdown-preview-server-filter
           :noquery t)
          suderman/markdown-preview-server-port
          (process-contact suderman/markdown-preview-server-process :service))))

(defun suderman/markdown-preview-ensure-target ()
  "Create preview files and URL for the current buffer if needed."
  (suderman/markdown-preview-server-start)
  (unless suderman/markdown-preview-file
    (let ((base (file-name-nondirectory (make-temp-name "markdown-preview-"))))
      (setq suderman/markdown-preview-file
            (expand-file-name (concat base ".html") suderman/markdown-preview-server-root)
            suderman/markdown-preview-version-file
            (expand-file-name (concat base ".version") suderman/markdown-preview-server-root)
            suderman/markdown-preview-url
            (format "http://127.0.0.1:%s/%s.html" suderman/markdown-preview-server-port base)))))

(defun suderman/markdown-preview-normalize-tables (html-file)
  "Wrap tables in HTML-FILE and remove Pandoc column width hints."
  (with-temp-buffer
    (insert-file-contents html-file)
    (goto-char (point-min))
    (while (re-search-forward "<colgroup[^>]*>" nil t)
      (let ((start (match-beginning 0)))
        (when (search-forward "</colgroup>" nil t)
          (delete-region start (point))
          (when (looking-at "\n")
            (delete-char 1)))))
    (goto-char (point-min))
    (while (re-search-forward "<table\\([^>]*\\)>" nil t)
      (replace-match "<div class=\"table-wrapper\">\n<table\\1>" nil nil))
    (goto-char (point-min))
    (while (search-forward "</table>" nil t)
      (replace-match "</table>\n</div>" nil nil))
    (write-region (point-min) (point-max) html-file nil 'silent)))

(defun suderman/markdown-preview-render ()
  "Render the current Markdown buffer to its preview file."
  (unless (executable-find "pandoc")
    (user-error "pandoc not found"))
  (suderman/markdown-preview-ensure-target)
  (let ((header-file (make-temp-file "markdown-preview-style-" nil ".html")))
    (unwind-protect
        (progn
          (write-region suderman/markdown-preview-css nil header-file nil 'silent)
          (let ((status (call-process-region
                         (point-min) (point-max)
                         "pandoc" nil nil nil
                         "--standalone"
                         "--from=markdown"
                         "--to=html5"
                         "--metadata" (format "pagetitle=%s" (buffer-name))
                         "--include-in-header" header-file
                         "--output" suderman/markdown-preview-file)))
            (unless (zerop status)
              (user-error "pandoc failed with exit code %s" status)))
          (suderman/markdown-preview-normalize-tables suderman/markdown-preview-file)
          (write-region (format "%s\n" (float-time)) nil
                        suderman/markdown-preview-version-file nil 'silent))
      (delete-file header-file))
    suderman/markdown-preview-file))

(defun suderman/markdown-preview-cleanup ()
  "Delete preview files owned by the current buffer."
  (dolist (file (list suderman/markdown-preview-file
                      suderman/markdown-preview-version-file))
    (when (and file (file-exists-p file))
      (delete-file file)))
  (setq suderman/markdown-preview-file nil
        suderman/markdown-preview-version-file nil
        suderman/markdown-preview-url nil))

(defun suderman/markdown-preview-after-save ()
  "Update this buffer's live Markdown preview after saving."
  (when suderman/markdown-preview-file
    (suderman/markdown-preview-render)))

(defun suderman/markdown-preview-buffer ()
  "Render current Markdown buffer with pandoc and open it in a browser.

The preview uses a stable local HTTP URL for this buffer.  Once opened, saving
this Markdown buffer rerenders the HTML.  The browser polls a small version file
and updates only after a save changes the preview."
  (interactive)
  (suderman/markdown-preview-render)
  (add-hook 'after-save-hook #'suderman/markdown-preview-after-save nil t)
  (add-hook 'kill-buffer-hook #'suderman/markdown-preview-cleanup nil t)
  (browse-url suderman/markdown-preview-url))

(defun suderman/markdown-fence-end (_arg)
  "Move to the end of the fenced code block at point, before its newline."
  (goto-char (treesit-node-end (treesit-thing-at (point) hs-treesit-things)))
  (skip-chars-backward "\n"))

(defun suderman/markdown-mouse-toggle-fold (event)
  "Toggle the heading whose trailing arrow received EVENT."
  (interactive "e")
  (mouse-set-point event)
  (suderman/meow-toggle-fold))

(defun suderman/markdown-push-button (&optional pos use-mouse-action)
  "Push the button at POS, as `push-button' does with USE-MOUSE-ACTION.
On Android the first tap on a link only moves point; a second tap follows
it, as in Org.  A touch that turns into a swipe still scrolls."
  (interactive
   (list (if (integerp last-command-event) (point) last-command-event)))
  (if (not (and (featurep 'android) (consp pos)))
      (push-button pos use-mouse-action)
    (let* ((posn (event-start pos))
           (target (posn-point posn)))
      (when (and target
                 (or (not (eq (car pos) 'touchscreen-down))
                     (touch-screen-track-tap pos nil nil t)))
        (when (windowp (posn-window posn))
          (select-window (posn-window posn)))
        (let ((button (button-at target)))
          (if (and button
                   (suderman/tap-repeats-p (button-start button)
                                           (button-end button)))
              (push-button target t)
            (goto-char target)))))))

(defun suderman/markdown-fold-arrow-press ()
  "Ignore a press on a fold arrow; the click toggles it."
  (interactive))

;; A touch that starts on an arrow still scrolls instead of dragging a region.
(put 'suderman/markdown-fold-arrow-press 'ignored-mouse-command t)

(defvar suderman/markdown-fold-arrow-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'suderman/markdown-fold-arrow-press)
    (define-key map [mouse-1] #'suderman/markdown-mouse-toggle-fold)
    (define-key map [mouse-2] #'suderman/markdown-mouse-toggle-fold)
    map)
  "Mouse bindings on trailing Markdown heading arrows.")

(defun suderman/markdown--heading-has-content-p ()
  "Return non-nil when the heading at point has non-blank text below it."
  (let ((end (save-excursion (outline-end-of-subtree) (point))))
    (save-excursion
      (end-of-line)
      (re-search-forward "[^ \t\n]" end t))))

(defun suderman/markdown--foldable-line-p ()
  "Return non-nil on a heading with content or a fenced code block's start."
  (if (outline-on-heading-p t)
      (suderman/markdown--heading-has-content-p)
    (and (bound-and-true-p hs-minor-mode)
         (or (hs-overlay-at (pos-eol))
             (save-excursion (forward-line 0) (hs-get-first-block-on-line))))))

(defun suderman/markdown-fontify-fold-arrows (beg end)
  "Show fold arrows after headings with content between BEG and END.
The arrow replaces Outline's ellipsis, as in Org."
  (save-excursion
    (goto-char end)
    (setq end (min (point-max) (1+ (pos-eol))))
    ;; An edit in a section body can give its heading content.
    (goto-char beg)
    (ignore-errors (outline-back-to-heading t))
    (setq beg (pos-bol))
    (remove-overlays beg end 'suderman/markdown-fold-arrow t)
    (unless (outline-on-heading-p t)
      (outline-next-heading))
    (while (and (< (point) end) (not (eobp)))
      (let ((eol (pos-eol)))
        (when (suderman/markdown--heading-has-content-p)
          (let* ((pos (1- eol))
                 ;; Inherit the face; copying it would scale the heading twice.
                 (char (buffer-substring-no-properties pos eol))
                 (overlay (make-overlay pos eol))
                 (folded '(with-current-buffer object
                            (save-excursion
                              (goto-char buffer-position)
                              (outline-invisible-p (pos-eol))))))
            (overlay-put overlay 'suderman/markdown-fold-arrow t)
            (overlay-put overlay 'evaporate t)
            (overlay-put
             overlay 'display
             (mapcar
              (lambda (state)
                `(when ,(if (car state) folded `(not ,folded))
                   . ,(concat char
                              (propertize (cdr state)
                                          'face '(org-ellipsis
                                                  suderman/fixed-pitch-text)
                                          'mouse-face 'highlight
                                          'pointer 'hand
                                          'help-echo "Toggle section"
                                          'keymap suderman/markdown-fold-arrow-map))))
              '((t . " ▸") (nil . " ▾")))))))
      (outline-next-heading))))

(defconst suderman/markdown-item-regexp
  "^[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]+\\(\\[[ xX]\\][ \t]+\\)?"
  "Match a list marker and an optional task checkbox at line start.")

(defun suderman/markdown--item-line-p ()
  "Return non-nil when this line starts a list item outside code.
Leave match data for `suderman/markdown-item-regexp'."
  (and (not (treesit-parent-until
             (treesit-node-at (pos-bol) 'markdown)
             "\\`\\(?:fenced\\|indented\\)_code_block\\'"))
       (save-excursion
         (beginning-of-line)
         (looking-at suderman/markdown-item-regexp))))

(defun suderman/markdown-insert-item ()
  "Insert a list item after this one, continuing a task checkbox."
  (let ((task (match-beginning 1)))
    (markdown-ts-insert-list-item)
    (when task (insert "[ ] "))))

(defun suderman/markdown-return ()
  "Continue a list item at its end, like Org; otherwise use Markdown's Return.
Return on an empty item removes it and ends the list.  Enter Insert
from Normal."
  (interactive)
  (if (and (eolp) (suderman/markdown--item-line-p))
      (if (= (point) (match-end 0))
          (progn
            (delete-region (pos-bol) (point))
            (insert "\n"))
        (suderman/markdown-insert-item))
    (call-interactively #'markdown-ts-newline))
  (when (bound-and-true-p meow-normal-mode)
    (suderman/meow-insert)))

(defun suderman/markdown-meta-return ()
  "Insert a list item in a list, otherwise a heading at this section's level.
The heading goes after the whole section, as M-RET does in Org.  Enter
Insert from Normal."
  (interactive)
  (if (suderman/markdown--item-line-p)
      (suderman/markdown-insert-item)
    (let* ((section (save-excursion (ignore-errors (outline-back-to-heading t))))
           (level (or (and section
                           (save-excursion
                             (goto-char section)
                             (and (looking-at "#+") (length (match-string 0)))))
                      1))
           (heading (concat (make-string level ?#) " ")))
      (if section
          (progn
            (goto-char section)
            (outline-end-of-subtree)
            (outline-next-heading))
        (end-of-line))
      (if (and (bolp) (not (eobp)))
          (save-excursion (insert heading "\n\n"))
        (unless (bolp) (insert "\n"))
        (unless (save-excursion (forward-line -1) (looking-at-p "[ \t]*$"))
          (insert "\n"))
        (save-excursion (insert heading)))
      (end-of-line)))
  (when (bound-and-true-p meow-normal-mode)
    (suderman/meow-insert)))

(defun suderman/markdown-folding ()
  "Fold headings with Outline and fenced code blocks with Hideshow."
  (require 'hideshow)
  (outline-minor-mode 1)
  ;; Arrows replace the ellipsis.
  (remove-from-invisibility-spec '(outline . t))
  (add-to-invisibility-spec 'outline)
  (jit-lock-register #'suderman/markdown-fontify-fold-arrows)
  ;; The mode defines no tree-sitter `list' thing, so point Hideshow's
  ;; tree-sitter search at fences instead of its bracket defaults.
  (setq-local hs-treesit-things "\\`fenced_code_block\\'"
              hs-c-start-regexp nil
              hs-block-start-regexp nil
              hs-block-end-regexp nil
              hs-forward-sexp-function #'suderman/markdown-fence-end
              hs-find-block-beginning-function #'treesit-hs-find-block-beginning
              hs-find-next-block-function #'treesit-hs-find-next-block
              hs-looking-at-block-start-predicate
              #'treesit-hs-looking-at-block-start-p
              hs-inside-comment-predicate #'ignore)
  (hs-minor-mode 1)
  (suderman/enable-fold-taps #'suderman/markdown--foldable-line-p
                             #'suderman/meow-toggle-fold))

(use-package markdown-ts-mode
  :ensure nil
  :mode "\\.\\(?:md\\|markdown\\)\\'"
  :hook (markdown-ts-mode . suderman/markdown-folding)
  :config
  ;; TAB after a folded heading's arrow should still cycle that heading.
  (advice-add 'markdown-ts-outline-cycle :before #'suderman/goto-shown-line-end)
  :bind (:map markdown-ts-mode-map
              ("RET" . suderman/markdown-return)
              ("M-RET" . suderman/markdown-meta-return)
              ("<mouse-1>" . suderman/mouse-set-point-or-fold)
              ([remap push-button] . suderman/markdown-push-button)
              ("C-c C-p" . suderman/markdown-preview-buffer)))

(provide 'suderman-markdown)
;;; suderman-markdown.el ends here
