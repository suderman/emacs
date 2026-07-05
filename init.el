;;; init.el --- Evil + Consult starter config -*- lexical-binding: t; -*-

;;; Goals:
;; - XDG-friendly: ~/.config/emacs for config, ~/.local/share/emacs for packages,
;;   ~/.local/state/emacs for state, ~/.cache/emacs for cache.
;; - Evil-first editing with a \ leader and SPC picker.
;; - Modern picker stack: Vertico + Consult + Marginalia + Orderless + Embark.
;; - Sidebar file tree: Treemacs.
;; - Mutable/package.el-friendly; no Nix lock-in.

;;; XDG paths

(defun jon/xdg-dir (env fallback child)
  "Return CHILD inside ENV's directory, or FALLBACK when ENV is unset."
  (file-name-as-directory
   (expand-file-name child (or (getenv env) (expand-file-name fallback "~")))))

(defconst jon/cache-dir (jon/xdg-dir "XDG_CACHE_HOME" ".cache" "emacs"))
(defconst jon/data-dir  (jon/xdg-dir "XDG_DATA_HOME" ".local/share" "emacs"))
(defconst jon/state-dir (jon/xdg-dir "XDG_STATE_HOME" ".local/state" "emacs"))

(dolist (dir (list jon/cache-dir jon/data-dir jon/state-dir))
  (make-directory dir t))

(setq custom-file (expand-file-name "custom.el" jon/state-dir)
      package-user-dir (expand-file-name "elpa" jon/data-dir)
      auto-save-list-file-prefix (expand-file-name "auto-save-list/.saves-" jon/state-dir)
      backup-directory-alist `(("." . ,(expand-file-name "backups" jon/state-dir)))
      auto-save-file-name-transforms `((".*" ,(expand-file-name "auto-save/" jon/state-dir) t))
      create-lockfiles nil
      recentf-save-file (expand-file-name "recentf" jon/state-dir)
      savehist-file (expand-file-name "savehist" jon/state-dir)
      save-place-file (expand-file-name "places" jon/state-dir)
      url-history-file (expand-file-name "url/history" jon/state-dir)
      bookmark-default-file (expand-file-name "bookmarks" jon/state-dir))

(dolist (dir (list (file-name-directory auto-save-list-file-prefix)
                   (cdr (car backup-directory-alist))
                   (cadr (car auto-save-file-name-transforms))
                   (file-name-directory url-history-file)))
  (make-directory dir t))

(when (boundp 'native-comp-eln-load-path)
  (startup-redirect-eln-cache (expand-file-name "eln-cache" jon/cache-dir)))

;;; Package setup

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t
      use-package-always-defer t
      use-package-expand-minimally t)

;;; Sensible built-ins

(setq ring-bell-function #'ignore
      use-short-answers t
      confirm-kill-emacs #'y-or-n-p
      read-process-output-max (* 1024 1024)
      enable-recursive-minibuffers t)

;; Match Neovim-style split navigation from Evil states only. Native Emacs
;; state keeps its own global M-h/M-j/M-k/M-l bindings.
(defun jon/window-left-or-treemacs ()
  "Move focus left, falling back to a visible Treemacs side window."
  (interactive)
  (condition-case nil
      (windmove-left)
    (user-error
     (if-let ((window (and (fboundp 'treemacs-get-local-window)
                           (treemacs-get-local-window))))
         (select-window window)
       (user-error "No window left from selected window")))))

(defun jon/window-previous ()
  "Move focus to the previously selected window."
  (interactive)
  (other-window -1))

(defun jon/shrink-window-width ()
  "Shrink the selected window horizontally."
  (interactive)
  (shrink-window-horizontally 5))

(defun jon/enlarge-window-width ()
  "Enlarge the selected window horizontally."
  (interactive)
  (enlarge-window-horizontally 5))

(defun jon/enlarge-window-height ()
  "Enlarge the selected window vertically."
  (interactive)
  (enlarge-window 3))

(defun jon/shrink-window-height ()
  "Shrink the selected window vertically."
  (interactive)
  (shrink-window 3))

(defun jon/split-window-below-and-focus ()
  "Split the selected window below and focus the new window."
  (interactive)
  (select-window (split-window-below)))

(defun jon/split-window-right-and-focus ()
  "Split the selected window right and focus the new window."
  (interactive)
  (select-window (split-window-right)))

(defun jon/buffer-candidates ()
  "Return live buffer names in most-recently-used order, excluding current."
  (let ((current (current-buffer))
        names)
    (dolist (buffer (buffer-list) (or (nreverse names)
                                      (list (buffer-name current))))
      (let ((name (buffer-name buffer)))
        (when (and name
                   (not (eq buffer current))
                   (not (string-prefix-p " " name)))
          (push name names))))))

(defun jon/picker-minibuffer-setup ()
  "Use Vim-style navigation in a picker selection minibuffer."
  (let ((map (copy-keymap (current-local-map))))
    (define-key map (kbd "j") #'vertico-next)
    (define-key map (kbd "k") #'vertico-previous)
    (define-key map (kbd "l") #'vertico-exit)
    (define-key map (kbd "RET") #'vertico-exit)
    (use-local-map map)))

(defun jon/switch-buffer ()
  "Switch buffers in most-recently-used order."
  (interactive)
  (let* ((vertico-sort-override-function #'identity)
         (buffer (minibuffer-with-setup-hook
                     (:append #'jon/picker-minibuffer-setup)
                   (completing-read "Buffer: "
                                    (jon/buffer-candidates)
                                    nil
                                    t))))
    (switch-to-buffer buffer)))

(defun jon/alternate-buffer ()
  "Switch to the most recent alternate buffer."
  (interactive)
  (let ((buffer (other-buffer (current-buffer) t)))
    (if buffer
        (switch-to-buffer buffer)
      (user-error "No alternate buffer"))))

(defun jon/smart-picker ()
  "Pick a high-level source, then launch its picker."
  (interactive)
  (let* ((actions `(("buffers" . jon/switch-buffer)
                    ("files" . jon/find-file)
                    ("grep" . jon/search-project)
                    ("recent" . consult-recent-file)
                    ("commands" . execute-extended-command)
                    ("command history" . consult-complex-command)
                    ("line" . consult-line)
                    ("symbols" . consult-imenu)
                    ("keymaps" . describe-bindings)
                    ("explorer" . jon/treemacs-toggle)))
         (choice (let ((vertico-sort-override-function #'identity))
                   (minibuffer-with-setup-hook
                       (:append #'jon/picker-minibuffer-setup)
                     (completing-read "Picker: "
                                      (mapcar #'car actions)
                                      nil
                                      t)))))
    (call-interactively (cdr (assoc choice actions)))))

(defun jon/treemacs-root-for-file (file)
  "Return a Treemacs project root for FILE, preferring the nearest Git root."
  (file-name-as-directory
   (expand-file-name
    (or (locate-dominating-file file ".git")
        (file-name-directory file)))))

(defun jon/treemacs-project-name-candidates (root)
  "Return unique Treemacs project name candidates for ROOT."
  (let* ((dir (directory-file-name root))
         (base (file-name-nondirectory dir))
         (parent-dir (file-name-directory dir))
         (parent (when parent-dir
                   (file-name-nondirectory
                    (directory-file-name parent-dir))))
         (candidates (list base
                           (when (and parent (not (string= parent "")))
                             (format "%s (%s)" base parent))
                           (abbreviate-file-name root)
                           root))
         names)
    (dolist (name candidates (nreverse names))
      (when (and name (not (member name names)))
        (push name names)))))

(defun jon/treemacs-add-project-root (root)
  "Add ROOT to the current Treemacs workspace if possible."
  (let (result)
    (catch 'done
      (dolist (name (jon/treemacs-project-name-candidates root))
        (let ((attempt (treemacs-do-add-project-to-workspace root name)))
          (setq result attempt)
          (cond
           ((memq (car-safe attempt) '(success duplicate-project includes-project))
            (throw 'done attempt))
           ((memq (car-safe attempt) '(duplicate-name invalid-name))
            nil)
           ((eq (car-safe attempt) 'invalid-path)
            (user-error "Cannot add Treemacs project %s: %s" root (cadr attempt)))))))
    (unless result
      (user-error "Cannot add Treemacs project %s" root))
    result))

(defun jon/treemacs-toggle ()
  "Toggle/focus Treemacs, adding the current project before revealing the file."
  (interactive)
  (cond
   ((derived-mode-p 'treemacs-mode)
    (treemacs))
   ((not buffer-file-name)
    (treemacs-select-window))
   (t
    (require 'treemacs)
    (let ((file (treemacs-canonical-path (expand-file-name buffer-file-name))))
      (unless (treemacs-is-path file :in-workspace)
        (jon/treemacs-add-project-root
         (jon/treemacs-root-for-file buffer-file-name)))
      (unless (treemacs-is-path file :in-workspace)
        (user-error "%s does not fall under any Treemacs project" file))
      (treemacs-find-file)
      (treemacs-select-window)))))

(defun jon/clear-search ()
  "Clear Evil search highlighting."
  (interactive)
  (evil-ex-nohighlight))

(defun jon/evil-shift-left-visual (beg end)
  "Outdent the visual selection and keep it selected."
  (interactive "r")
  (evil-shift-left beg end)
  (evil-normal-state)
  (evil-visual-restore))

(defun jon/evil-shift-right-visual (beg end)
  "Indent the visual selection and keep it selected."
  (interactive "r")
  (evil-shift-right beg end)
  (evil-normal-state)
  (evil-visual-restore))

(savehist-mode 1)
(save-place-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(electric-pair-mode 1)

;;; Evil

(defvar jon/local-leader-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'delete-window)
    map)
  "Fallback keymap for the local leader key `,'.")

(use-package evil
  :demand t
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil
        evil-want-C-u-scroll t
        evil-want-C-i-jump nil
        evil-respect-visual-line-mode t
        evil-undo-system 'undo-redo)
  :config
  (evil-mode 1)
  ;; Use jk as a low-friction escape hatch from insert state.
  (define-key evil-insert-state-map (kbd "j k") #'evil-normal-state)
  (define-key evil-insert-state-map (kbd "M-h") #'left-char)
  (define-key evil-insert-state-map (kbd "M-j") #'next-line)
  (define-key evil-insert-state-map (kbd "M-k") #'previous-line)
  (define-key evil-insert-state-map (kbd "M-l") #'right-char)
  (define-key evil-insert-state-map (kbd "C-l") (lambda () (interactive) (insert " ")))

  (dolist (map (list evil-normal-state-map evil-motion-state-map))
    (define-key map (kbd "SPC") #'jon/smart-picker)
    (define-key map (kbd ";") #'evil-ex)
    (define-key map (kbd "j") #'evil-next-visual-line)
    (define-key map (kbd "k") #'evil-previous-visual-line)
    (define-key map (kbd "Y") (kbd "y$"))
    (define-key map (kbd "K") #'jon/switch-buffer)
    (define-key map (kbd "M-p") #'consult-recent-file)
    (define-key map (kbd "M-g") #'jon/search-project)
    (define-key map (kbd "-") #'dirvish)
    (define-key map (kbd "M-h") #'jon/window-left-or-treemacs)
    (define-key map (kbd "M-j") #'windmove-down)
    (define-key map (kbd "M-k") #'windmove-up)
    (define-key map (kbd "M-l") #'windmove-right)
    (define-key map (kbd "M-;") #'jon/window-previous)
    (define-key map (kbd "M-H") #'jon/shrink-window-width)
    (define-key map (kbd "M-J") #'jon/enlarge-window-height)
    (define-key map (kbd "M-K") #'jon/shrink-window-height)
    (define-key map (kbd "M-L") #'jon/enlarge-window-width)
    (define-key map (kbd "M-u") #'jon/split-window-below-and-focus)
    (define-key map (kbd "M-i") #'jon/split-window-right-and-focus)
    (define-key map (kbd "M-U") #'jon/split-window-below-and-focus)
    (define-key map (kbd "M-I") #'jon/split-window-right-and-focus)
    (define-key map (kbd "g u") #'jon/split-window-below-and-focus)
    (define-key map (kbd "g i") #'jon/split-window-right-and-focus)
    (define-key map (kbd "M-q") #'delete-window)
    (define-key map (kbd ",") jon/local-leader-map)
    (define-key map (kbd "[b") #'previous-buffer)
    (define-key map (kbd "]b") #'next-buffer)
    (define-key map (kbd "[c") #'previous-error)
    (define-key map (kbd "]c") #'next-error))

  (define-key evil-visual-state-map (kbd "j") #'evil-next-visual-line)
  (define-key evil-visual-state-map (kbd "k") #'evil-previous-visual-line)
  (define-key evil-visual-state-map (kbd "<") #'jon/evil-shift-left-visual)
  (define-key evil-visual-state-map (kbd ">") #'jon/evil-shift-right-visual)
  (define-key evil-visual-state-map (kbd "M-h") #'jon/shrink-window-width)
  (define-key evil-visual-state-map (kbd "M-j") #'jon/enlarge-window-height)
  (define-key evil-visual-state-map (kbd "M-k") #'jon/shrink-window-height)
  (define-key evil-visual-state-map (kbd "M-l") #'jon/enlarge-window-width))

(use-package evil-collection
  :after evil
  :demand t
  :config
  ;; Let Evil Collection handle special modes, but keep Treemacs on its own
  ;; keymap. Treemacs' mouse bindings work correctly in Evil's emacs state, and
  ;; evil-treemacs/normal-state mouse handling interferes with double-click.
  (setq evil-collection-mode-list
        (delq 'treemacs evil-collection-mode-list))
  (evil-collection-init))

;;; Leader keys + discoverability

(use-package which-key
  :demand t
  :init
  (setq which-key-idle-delay 0.35)
  :config
  (which-key-mode 1))

(use-package general
  :after evil
  :config
  (general-create-definer jon/leader
    :states '(normal visual motion)
    :keymaps 'override
    :prefix "\\")

  (jon/leader
    "SPC" '(execute-extended-command :which-key "M-x")
    "\\" '(jon/alternate-buffer :which-key "last buffer")
    "="   '(jon/treemacs-toggle :which-key "toggle explorer")
    "u"   '(jon/split-window-below-and-focus :which-key "split below")
    "i"   '(jon/split-window-right-and-focus :which-key "split right")
    "q"   '(delete-window :which-key "quit split")

    ;; Files
    "f"   '(:ignore t :which-key "files")
    "f f" '(jon/find-file :which-key "find file/project file")
    "f r" '(consult-recent-file :which-key "recent files")
    "f s" '(save-buffer :which-key "save file")

    ;; Buffers
    "b"   '(:ignore t :which-key "buffers")
    "b b" '(jon/switch-buffer :which-key "switch buffer")
    "b k" '(kill-current-buffer :which-key "kill buffer")
    "b n" '(next-buffer :which-key "next buffer")
    "b p" '(previous-buffer :which-key "previous buffer")

    ;; Search
    "s"   '(:ignore t :which-key "search")
    "s c" '(jon/clear-search :which-key "clear search")
    "s g" '(jon/search-project :which-key "grep project")
    "s l" '(consult-line :which-key "search line")
    "s i" '(consult-imenu :which-key "imenu symbols")

    ;; Pickers
    "t"   '(:ignore t :which-key "pickers")
    "t b" '(jon/switch-buffer :which-key "buffers")
    "t f" '(jon/find-file :which-key "files")
    "t g" '(jon/search-project :which-key "grep")
    "t r" '(consult-recent-file :which-key "recent")
    "t q" '(consult-complex-command :which-key "command history")
    "t l" '(consult-line :which-key "line")
    "t i" '(consult-imenu :which-key "symbols")
    "t k" '(describe-bindings :which-key "keymaps")

    ;; Windows
    "w"   '(:ignore t :which-key "windows")
    "w v" '(jon/split-window-right-and-focus :which-key "split right")
    "w s" '(jon/split-window-below-and-focus :which-key "split below")
    "w d" '(delete-window :which-key "delete window")
    "w o" '(delete-other-windows :which-key "only window")
    "w h" '(jon/window-left-or-treemacs :which-key "window left")
    "w j" '(windmove-down :which-key "window down")
    "w k" '(windmove-up :which-key "window up")
    "w l" '(windmove-right :which-key "window right")
    "w +" '(jon/enlarge-window-width :which-key "wider")
    "w -" '(jon/shrink-window-width :which-key "narrower")
    "w =" '(balance-windows :which-key "balance")

    ;; Projects
    "p"   '(:ignore t :which-key "projects")
    "p p" '(project-switch-project :which-key "switch project")
    "p f" '(project-find-file :which-key "project file")
    "p b" '(project-switch-to-buffer :which-key "project buffer")
    "p k" '(project-kill-buffers :which-key "kill project buffers")

    ;; Explorer / files
    "e"   '(jon/treemacs-toggle :which-key "explorer")
    "d"   '(dirvish :which-key "dirvish")

    ;; Help
    "h"   '(:ignore t :which-key "help")
    "h k" '(describe-key :which-key "describe key")
    "h f" '(describe-function :which-key "describe function")
    "h v" '(describe-variable :which-key "describe variable")
    "h m" '(describe-mode :which-key "describe mode")))

;;; Completion / picker stack

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
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package consult
  :init
  (setq consult-project-function #'consult--default-project-function)
  :bind
  (("C-x b" . consult-buffer)
   ("M-s r" . jon/search-project)
   ("M-s l" . consult-line)
   ("M-s i" . consult-imenu)))

(use-package embark
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)))

(use-package embark-consult
  :after (embark consult))

;;; Project helpers

(defun jon/project-root ()
  "Return current project root, or nil outside a project."
  (when-let ((project (project-current nil)))
    (if (fboundp 'project-root)
        (project-root project)
      (car (project-roots project)))))

(defun jon/find-file ()
  "Find a file, preferring project files when inside a project."
  (interactive)
  (if (jon/project-root)
      (call-interactively #'project-find-file)
    (call-interactively #'find-file)))

(defun jon/search-project ()
  "Run ripgrep from the project root, or from default-directory outside a project."
  (interactive)
  (consult-ripgrep (or (jon/project-root) default-directory)))

;;; Language modes / tree-sitter

(use-package treesit-auto
  :ensure nil
  :demand t
  :when (and (fboundp 'treesit-available-p) (treesit-available-p))
  :custom
  (treesit-auto-install nil)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

(use-package nix-ts-mode
  :ensure nil
  :mode "\\.nix\\'")

(defconst jon/markdown-preview-css
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
  "HTML header used for `jon/markdown-preview-buffer'.")

(defvar jon/markdown-preview-server-process nil
  "HTTP server process for Markdown previews.")

(defvar jon/markdown-preview-server-port nil
  "HTTP server port for Markdown previews.")

(defvar jon/markdown-preview-server-root
  (expand-file-name "jon-emacs-markdown-preview/" temporary-file-directory)
  "Directory served by the Markdown preview HTTP server.")

(defvar-local jon/markdown-preview-file nil
  "HTML file used for the current buffer's Markdown preview.")

(defvar-local jon/markdown-preview-version-file nil
  "Version file polled by the current buffer's Markdown preview.")

(defvar-local jon/markdown-preview-url nil
  "HTTP URL used for the current buffer's Markdown preview.")

(defun jon/markdown-preview-server-send (proc status content-type body)
  "Send HTTP STATUS with CONTENT-TYPE and BODY to PROC."
  (process-send-string
   proc
   (format "HTTP/1.1 %s\r\nContent-Type: %s\r\nCache-Control: no-store\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
           status content-type (string-bytes body)))
  (process-send-string proc body)
  (delete-process proc))

(defun jon/markdown-preview-server-handle (proc request)
  "Serve one Markdown preview HTTP REQUEST from PROC."
  (if (not (string-match "\\`GET \\([^ ?]+\\)" request))
      (jon/markdown-preview-server-send proc "405 Method Not Allowed" "text/plain; charset=utf-8" "Method not allowed")
    (let* ((name (file-name-nondirectory (match-string 1 request)))
           (file (expand-file-name name jon/markdown-preview-server-root)))
      (if (and (not (string-empty-p name))
               (file-regular-p file))
          (let ((body (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally file)
                        (buffer-string)))
                (content-type (if (string-suffix-p ".html" name)
                                  "text/html; charset=utf-8"
                                "text/plain; charset=utf-8")))
            (jon/markdown-preview-server-send proc "200 OK" content-type body))
        (jon/markdown-preview-server-send proc "404 Not Found" "text/plain; charset=utf-8" "Not found")))))

(defun jon/markdown-preview-server-filter (proc chunk)
  "Collect HTTP request CHUNK from PROC and serve it when complete."
  (let ((request (concat (process-get proc 'request) chunk)))
    (if (string-match-p "\r\n\r\n" request)
        (jon/markdown-preview-server-handle proc request)
      (process-put proc 'request request))))

(defun jon/markdown-preview-server-start ()
  "Start the Markdown preview HTTP server if needed."
  (unless (process-live-p jon/markdown-preview-server-process)
    (make-directory jon/markdown-preview-server-root t)
    (setq jon/markdown-preview-server-process
          (make-network-process
           :name "jon-markdown-preview-server"
           :server t
           :host "127.0.0.1"
           :service 0
           :filter #'jon/markdown-preview-server-filter
           :noquery t)
          jon/markdown-preview-server-port
          (process-contact jon/markdown-preview-server-process :service))))

(defun jon/markdown-preview-ensure-target ()
  "Create preview files and URL for the current buffer if needed."
  (jon/markdown-preview-server-start)
  (unless jon/markdown-preview-file
    (let ((base (file-name-nondirectory (make-temp-name "markdown-preview-"))))
      (setq jon/markdown-preview-file
            (expand-file-name (concat base ".html") jon/markdown-preview-server-root)
            jon/markdown-preview-version-file
            (expand-file-name (concat base ".version") jon/markdown-preview-server-root)
            jon/markdown-preview-url
            (format "http://127.0.0.1:%s/%s.html" jon/markdown-preview-server-port base)))))

(defun jon/markdown-preview-normalize-tables (html-file)
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

(defun jon/markdown-preview-render (&optional html-file)
  "Render current Markdown buffer to HTML-FILE, or the buffer preview file."
  (unless (executable-find "pandoc")
    (user-error "pandoc not found"))
  (unless html-file
    (jon/markdown-preview-ensure-target))
  (let ((output-file (or html-file jon/markdown-preview-file))
        (header-file (make-temp-file "markdown-preview-style-" nil ".html")))
    (unwind-protect
        (progn
          (write-region jon/markdown-preview-css nil header-file nil 'silent)
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
          (jon/markdown-preview-normalize-tables output-file)
          (when (and jon/markdown-preview-version-file
                     (equal output-file jon/markdown-preview-file))
            (write-region (format "%s\n" (float-time)) nil jon/markdown-preview-version-file nil 'silent)))
      (delete-file header-file))
    output-file))

(defun jon/markdown-preview-after-save ()
  "Update this buffer's live Markdown preview after saving."
  (when jon/markdown-preview-file
    (jon/markdown-preview-render jon/markdown-preview-file)))

(defun jon/markdown-preview-buffer ()
  "Render current Markdown buffer with pandoc and open it in a browser.

The preview uses a stable local HTTP URL for this buffer.  Once opened, saving
this Markdown buffer rerenders the HTML.  The browser polls a small version file
and updates only after a save changes the preview."
  (interactive)
  (jon/markdown-preview-ensure-target)
  (jon/markdown-preview-render jon/markdown-preview-file)
  (add-hook 'after-save-hook #'jon/markdown-preview-after-save nil t)
  (browse-url jon/markdown-preview-url))

(use-package markdown-ts-mode
  :ensure nil
  :mode "\\.\\(?:md\\|markdown\\)\\'"
  :config
  (evil-define-key '(normal motion visual) markdown-ts-mode-map
    (kbd ", p") #'jon/markdown-preview-buffer))

(use-package web-mode
  :ensure nil
  :mode ("\\.twig\\'" . web-mode))

(use-package php-mode
  :ensure nil
  :mode "\\.php\\'")

(add-to-list 'auto-mode-alist '("\\.zsh\\'" . sh-mode))

;;; Sidebar tree / file manager

(use-package treemacs
  :after evil
  :commands (treemacs treemacs-find-file treemacs-select-window)
  :init
  ;; Set this before any Treemacs buffer is created.
  (evil-set-initial-state 'treemacs-mode 'emacs)
  (setq treemacs-width 32
        treemacs-follow-after-init t
        treemacs-is-never-other-window t)
  :config
  ;; Do not enable treemacs-evil here: Treemacs' own keymap handles mouse input
  ;; correctly in emacs state, including double-click open/toggle.
  (add-hook 'treemacs-mode-hook #'evil-emacs-state)
  (define-key treemacs-mode-map (kbd "j") #'treemacs-next-line)
  (define-key treemacs-mode-map (kbd "k") #'treemacs-previous-line)
  (define-key treemacs-mode-map (kbd "M-h") #'jon/window-left-or-treemacs)
  (define-key treemacs-mode-map (kbd "M-j") #'windmove-down)
  (define-key treemacs-mode-map (kbd "M-k") #'windmove-up)
  (define-key treemacs-mode-map (kbd "M-l") #'windmove-right)
  (treemacs-follow-mode 1)
  (treemacs-filewatch-mode 1))

(use-package dirvish
  :commands (dirvish dirvish-side)
  :init
  (setq dirvish-use-mode-line t)
  :config
  (dirvish-override-dired-mode 1))

;;; Final startup cleanup

(setq gc-cons-threshold (* 64 1024 1024)
      gc-cons-percentage 0.1)

(when (file-exists-p custom-file)
  (load custom-file))

(message "Loaded Jon's XDG Emacs starter config")

(provide 'init)
;;; init.el ends here
