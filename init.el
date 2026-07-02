;;; init.el --- Evil + Consult starter config -*- lexical-binding: t; -*-

;;; Goals:
;; - XDG-friendly: ~/.config/emacs for config, ~/.local/share/emacs for packages,
;;   ~/.local/state/emacs for state, ~/.cache/emacs for cache.
;; - Evil-first editing with a SPC leader.
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
  (define-key evil-insert-state-map (kbd "j k") #'evil-normal-state))

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
    :prefix "SPC"
    :global-prefix "C-SPC")

  (jon/leader
    "SPC" '(execute-extended-command :which-key "M-x")

    ;; Files
    "f"   '(:ignore t :which-key "files")
    "f f" '(jon/find-file :which-key "find file/project file")
    "f r" '(consult-recent-file :which-key "recent files")
    "f s" '(save-buffer :which-key "save file")

    ;; Buffers
    "b"   '(:ignore t :which-key "buffers")
    "b b" '(consult-buffer :which-key "switch buffer")
    "b k" '(kill-current-buffer :which-key "kill buffer")
    "b n" '(next-buffer :which-key "next buffer")
    "b p" '(previous-buffer :which-key "previous buffer")

    ;; Search
    "s"   '(:ignore t :which-key "search")
    "s g" '(jon/search-project :which-key "grep project")
    "s l" '(consult-line :which-key "search line")
    "s i" '(consult-imenu :which-key "imenu symbols")

    ;; Windows
    "w"   '(:ignore t :which-key "windows")
    "w v" '(split-window-right :which-key "split right")
    "w s" '(split-window-below :which-key "split below")
    "w d" '(delete-window :which-key "delete window")
    "w o" '(delete-other-windows :which-key "only window")
    "w h" '(windmove-left :which-key "window left")
    "w j" '(windmove-down :which-key "window down")
    "w k" '(windmove-up :which-key "window up")
    "w l" '(windmove-right :which-key "window right")

    ;; Projects
    "p"   '(:ignore t :which-key "projects")
    "p p" '(project-switch-project :which-key "switch project")
    "p f" '(project-find-file :which-key "project file")
    "p b" '(project-switch-to-buffer :which-key "project buffer")
    "p k" '(project-kill-buffers :which-key "kill project buffers")

    ;; Explorer / files
    "e"   '(treemacs :which-key "explorer")
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

(use-package markdown-ts-mode
  :ensure nil
  :mode "\\.\\(?:md\\|markdown\\)\\'")

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
