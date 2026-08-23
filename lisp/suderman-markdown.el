;;; suderman-markdown.el --- Markdown editing and live preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Markdown has enough custom behavior to deserve its own home: a Pandoc-backed
;; browser preview, table normalization, and mode-local bindings.

;;; Code:

(require 'subr-x)
(require 'use-package)

(defconst suderman/markdown-preview-css
  "<style>
:root {
  color-scheme: light dark;
  --bg: #ffffff;
  --fg: #1f2328;
  --muted: #656d76;
  --border: #d0d7de;
  --code-bg: #f6f8fa;
  --accent: #0969da;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117;
    --fg: #e6edf3;
    --muted: #8b949e;
    --border: #30363d;
    --code-bg: #161b22;
    --accent: #58a6ff;
  }
}

* { box-sizing: border-box; }

body {
  margin: 0;
  max-width: none;
  padding: 32px;
  background: var(--bg);
  color: var(--fg);
  font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  hyphens: manual;
  overflow-wrap: normal;
  word-break: normal;
}


a { color: var(--accent); }

h1, h2, h3, h4, h5, h6 {
  line-height: 1.25;
  margin-top: 24px;
  margin-bottom: 16px;
  font-weight: 600;
}

h1, h2 {
  padding-bottom: 0.3em;
  border-bottom: 1px solid var(--border);
}

pre, code, kbd, samp {
  font-family: ui-monospace, SFMono-Regular, \"SF Mono\", Consolas, \"Liberation Mono\", Menlo, monospace;
  font-size: 85%;
}

code {
  padding: 0.2em 0.4em;
  border-radius: 6px;
  background: var(--code-bg);
}

pre {
  overflow-x: auto;
  padding: 16px;
  border-radius: 6px;
  background: var(--code-bg);
}

pre code {
  padding: 0;
  background: transparent;
}

blockquote {
  padding: 0 1em;
  color: var(--muted);
  border-left: 0.25em solid var(--border);
}

img, svg {
  max-width: none;
}

.table-wrapper {
  width: 100%;
  overflow-x: auto;
  margin: 24px 0;
}

.table-wrapper table {
  display: table;
  width: auto;
  max-width: none;
  margin: 0;
  border-spacing: 0;
  border-collapse: collapse;
  table-layout: auto;
}

.table-wrapper col {
  width: auto !important;
}

th, td {
  padding: 6px 13px;
  border: 1px solid var(--border);
  overflow-wrap: normal;
  word-break: normal;
  vertical-align: top;
}

td code, th code {
  white-space: nowrap;
}

tr:nth-child(2n) {
  background: color-mix(in srgb, var(--code-bg) 70%, transparent);
}

</style>
<script>
(() => {
  const versionUrl = window.location.pathname.replace(/\\.html$/, '.version');
  let currentVersion = null;

  function tableScrolls() {
    return Array.from(document.querySelectorAll('.table-wrapper'), (table) => table.scrollLeft);
  }

  function restoreScroll(state) {
    window.scrollTo(state.x, state.y);
    document.querySelectorAll('.table-wrapper').forEach((table, index) => {
      table.scrollLeft = state.tables[index] || 0;
    });
  }

  async function getVersion() {
    const response = await fetch(`${versionUrl}?t=${Date.now()}`, { cache: 'no-store' });
    return response.ok ? (await response.text()).trim() : null;
  }

  async function refreshIfChanged() {
    try {
      const nextVersion = await getVersion();
      if (!nextVersion) return;
      if (currentVersion === null) {
        currentVersion = nextVersion;
        return;
      }
      if (nextVersion === currentVersion) return;

      const state = { x: window.scrollX, y: window.scrollY, tables: tableScrolls() };
      const response = await fetch(`${window.location.pathname}?t=${Date.now()}`, { cache: 'no-store' });
      if (!response.ok) return;

      const nextDocument = new DOMParser().parseFromString(await response.text(), 'text/html');
      document.body.replaceWith(nextDocument.body);
      document.title = nextDocument.title;
      currentVersion = nextVersion;
      requestAnimationFrame(() => requestAnimationFrame(() => restoreScroll(state)));
    } catch (error) {
      console.warn('Markdown preview refresh failed', error);
    }
  }

  window.addEventListener('DOMContentLoaded', () => {
    refreshIfChanged();
    setInterval(refreshIfChanged, 1000);
  });
})();
</script>"
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

(defun suderman/markdown-ts-imenu-heading-p (node)
  "Return non-nil when NODE is an ATX heading's inline content."
  (and (equal (treesit-node-type node) "inline")
       (equal (treesit-node-type (treesit-node-parent node))
              "atx_heading")))

(defun suderman/markdown-ts-imenu-heading-name (node)
  "Return the complete heading containing NODE."
  (car (split-string (treesit-node-text (treesit-node-parent node))
                     "\n" t " ")))

(defun suderman/markdown-ts-imenu-setup ()
  "Use one Imenu entry per Markdown heading."
  (setq-local treesit-simple-imenu-settings
              `(("Headings" ,#'suderman/markdown-ts-imenu-heading-p
                 nil ,#'suderman/markdown-ts-imenu-heading-name))
              imenu--index-alist nil)
  (when (boundp 'treemacs--imenu-cache)
    (setq-local treemacs--imenu-cache nil)))

(use-package markdown-ts-mode
  :ensure nil
  :mode "\\.\\(?:md\\|markdown\\)\\'"
  :hook (markdown-ts-mode . suderman/markdown-ts-imenu-setup)
  :bind (:map markdown-ts-mode-map
              ("C-c C-p" . suderman/markdown-preview-buffer))
  :config
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'markdown-ts-mode)
        (suderman/markdown-ts-imenu-setup)))))

(provide 'suderman-markdown)
;;; suderman-markdown.el ends here
