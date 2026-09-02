;;; suderman-paths.el --- XDG paths and state files -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep Emacs' mutable state out of ~/.config/emacs.  Config lives here; cache,
;; package, history, backup, and Custom files follow XDG locations.

;;; Code:

(defun suderman/xdg-dir (env fallback child)
  "Return CHILD inside ENV's directory, or FALLBACK when ENV is unset."
  (file-name-as-directory
   (expand-file-name child (or (getenv env) (expand-file-name fallback "~")))))

(defconst suderman/cache-dir (suderman/xdg-dir "XDG_CACHE_HOME" ".cache" "emacs")
  "Root directory for Emacs cache files.")

(defconst suderman/data-dir (suderman/xdg-dir "XDG_DATA_HOME" ".local/share" "emacs")
  "Root directory for Emacs data files.")

(defconst suderman/state-dir (suderman/xdg-dir "XDG_STATE_HOME" ".local/state" "emacs")
  "Root directory for Emacs state files.")

(let ((local-bin (expand-file-name ".local/bin" "~")))
  (add-to-list 'exec-path local-bin)
  (setenv "PATH" (mapconcat #'identity exec-path path-separator)))

(dolist (dir (list suderman/cache-dir suderman/data-dir suderman/state-dir))
  (make-directory dir t))

(setq custom-file (expand-file-name "custom.el" suderman/state-dir)
      package-user-dir (expand-file-name "elpa" suderman/data-dir)
      gamegrid-user-score-file-directory (expand-file-name "games" suderman/state-dir)
      auto-save-list-file-prefix (expand-file-name "auto-save-list/.saves-" suderman/state-dir)
      backup-directory-alist `(("." . ,(expand-file-name "backups" suderman/state-dir)))
      auto-save-file-name-transforms `((".*" ,(expand-file-name "auto-save/" suderman/state-dir) t))
      create-lockfiles nil
      dirvish-cache-dir (expand-file-name "dirvish/" suderman/cache-dir)
      eshell-directory-name (expand-file-name "eshell/" suderman/state-dir)
      multisession-directory (expand-file-name "multisession/" suderman/state-dir)
      project-list-file (expand-file-name "projects" suderman/state-dir)
      recentf-save-file (expand-file-name "recentf" suderman/state-dir)
      savehist-file (expand-file-name "savehist" suderman/state-dir)
      save-place-file (expand-file-name "places" suderman/state-dir)
      tramp-persistency-file-name (expand-file-name "tramp" suderman/state-dir)
      transient-history-file (expand-file-name "transient/history.el" suderman/state-dir)
      transient-levels-file (expand-file-name "transient/levels.el" suderman/state-dir)
      transient-values-file (expand-file-name "transient/values.el" suderman/state-dir)
      url-configuration-directory (expand-file-name "url/" suderman/state-dir)
      url-history-file (expand-file-name "history" url-configuration-directory)
      bookmark-default-file (expand-file-name "bookmarks" suderman/state-dir))

(dolist (dir (list (file-name-directory auto-save-list-file-prefix)
                   (cdr (car backup-directory-alist))
                   (cadr (car auto-save-file-name-transforms))
                   (file-name-directory url-history-file)))
  (make-directory dir t))

(when (boundp 'native-comp-eln-load-path)
  (startup-redirect-eln-cache (expand-file-name "eln-cache" suderman/cache-dir)))

(provide 'suderman-paths)
;;; suderman-paths.el ends here
