;;; suderman-markdown.el --- Markdown editing and live preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Markdown has enough custom behavior to deserve its own home: a Pandoc-backed
;; browser preview, table normalization, and mode-local bindings.

;;; Code:

(require 'subr-x)
(require 'use-package)

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

(defun suderman/markdown-preview-render (&optional html-file)
  "Render current Markdown buffer to HTML-FILE, or the buffer preview file."
  (unless (executable-find "pandoc")
    (user-error "pandoc not found"))
  (unless html-file
    (suderman/markdown-preview-ensure-target))
  (let ((output-file (or html-file suderman/markdown-preview-file))
        (header-file (make-temp-file "markdown-preview-style-" nil ".html")))
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
                         "--output" output-file)))
            (unless (zerop status)
              (user-error "pandoc failed with exit code %s" status)))
          (suderman/markdown-preview-normalize-tables output-file)
          (when (and suderman/markdown-preview-version-file
                     (equal output-file suderman/markdown-preview-file))
            (write-region (format "%s\n" (float-time)) nil suderman/markdown-preview-version-file nil 'silent)))
      (delete-file header-file))
    output-file))

(defun suderman/markdown-preview-after-save ()
  "Update this buffer's live Markdown preview after saving."
  (when suderman/markdown-preview-file
    (suderman/markdown-preview-render suderman/markdown-preview-file)))

(defun suderman/markdown-preview-buffer ()
  "Render current Markdown buffer with pandoc and open it in a browser.

The preview uses a stable local HTTP URL for this buffer.  Once opened, saving
this Markdown buffer rerenders the HTML.  The browser polls a small version file
and updates only after a save changes the preview."
  (interactive)
  (suderman/markdown-preview-ensure-target)
  (suderman/markdown-preview-render suderman/markdown-preview-file)
  (add-hook 'after-save-hook #'suderman/markdown-preview-after-save nil t)
  (browse-url suderman/markdown-preview-url))

(use-package markdown-ts-mode
  :ensure nil
  :mode "\\.\\(?:md\\|markdown\\)\\'"
  :bind (:map markdown-ts-mode-map
              ("C-c C-p" . suderman/markdown-preview-buffer)))

(provide 'suderman-markdown)
;;; suderman-markdown.el ends here
