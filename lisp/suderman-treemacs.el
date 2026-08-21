;;; suderman-treemacs.el --- Project-focused Treemacs browsing -*- lexical-binding: t; -*-

;;; Commentary:
;; Configure Treemacs as a project-focused file tree.

;;; Code:

(require 'use-package)
(require 'suderman-buffers)
(require 'suderman-windows)

(use-package treemacs
  :demand t
  :init
  (setq treemacs-position 'left
        treemacs-show-hidden-files nil
        treemacs-width 50
        treemacs-width-is-initially-locked nil))

(defun suderman/treemacs-disable-meow ()
  "Disable Meow in the current Treemacs buffer."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/treemacs-disable-visual-line-mode ()
  "Keep visual line wrapping disabled in the current Treemacs buffer."
  (when visual-line-mode
    (visual-line-mode -1)))

(defun suderman/treemacs-setup ()
  "Use Treemacs's native navigation in the current buffer."
  (add-hook 'meow-mode-hook #'suderman/treemacs-disable-meow nil t)
  (add-hook 'visual-line-mode-hook
            #'suderman/treemacs-disable-visual-line-mode nil t)
  (suderman/treemacs-disable-meow)
  (suderman/treemacs-disable-visual-line-mode))

(defun suderman/treemacs--rendered-project (&optional buffer)
  "Return the project rendered in BUFFER's tree."
  (with-current-buffer (or buffer (current-buffer))
    (save-excursion
      (goto-char (point-min))
      (when-let* ((button (or (treemacs-current-button)
                              (next-button (point)))))
        (treemacs-project-of-node button)))))

(defun suderman/treemacs--ensure-frame-workspace ()
  "Give the selected frame its own private Treemacs workspace."
  (let* ((frame (selected-frame))
         (workspace (frame-parameter frame 'suderman/treemacs-workspace)))
    (unless workspace
      (let* ((shared (treemacs-current-workspace))
             (buffer (treemacs-get-local-buffer))
             (rendered (and (buffer-live-p buffer)
                            (suderman/treemacs--rendered-project buffer))))
        (setq workspace
              (treemacs-workspace->create!
               :name (format "Frame %s" (frame-parameter frame 'name))
               :projects (if rendered
                             (list rendered)
                           (copy-sequence
                            (treemacs-workspace->projects shared)))))
        (set-frame-parameter frame 'suderman/treemacs-workspace workspace)))
    (setf (treemacs-current-workspace) workspace)
    workspace))

(defun suderman/treemacs--rebuild-tree (workspace)
  "Rebuild the current frame's tree from WORKSPACE."
  (treemacs-with-workspace workspace
    (treemacs--reset-dom)
    (treemacs-with-writable-buffer
      (erase-buffer)
      (treemacs--render-projects (treemacs-workspace->projects workspace)))
    (goto-char (point-min))
    (when-let* ((button (treemacs-current-button)))
      (unless (treemacs-is-node-expanded? button)
        (treemacs--expand-root-node button)))
    (treemacs--evade-image)))

(defun suderman/treemacs--repair-tree ()
  "Redraw the current tree when it does not match its frame workspace."
  (let* ((workspace (suderman/treemacs--ensure-frame-workspace))
         (project (suderman/treemacs--rendered-project)))
    (unless (memq project (treemacs-workspace->projects workspace))
      (suderman/treemacs--rebuild-tree workspace))))

(defun suderman/treemacs--isolate-existing-frames ()
  "Move existing frame trees from shared to private workspaces."
  (dolist (entry (treemacs--scope-store))
    (let ((frame (car entry))
          (shelf (cdr entry)))
      (when (frame-live-p frame)
        (with-selected-frame frame
          (suderman/treemacs--ensure-frame-workspace)
          (setf (treemacs-scope-shelf->workspace shelf)
                (frame-parameter frame 'suderman/treemacs-workspace))
          (when-let* ((buffer (treemacs-scope-shelf->buffer shelf))
                      ((buffer-live-p buffer)))
            (with-current-buffer buffer
              (suderman/treemacs--repair-tree))))))))

(defun suderman/treemacs-close ()
  "Close the current frame's Treemacs without burying the editor buffer."
  (when-let* ((window (treemacs-get-local-window)))
    (with-selected-window window
      (treemacs-quit))))

(defun suderman/treemacs--show (select &optional context-buffer)
  "Show Treemacs for CONTEXT-BUFFER, selecting it when SELECT."
  (let* ((source-window (selected-window))
         (source-buffer (if (buffer-live-p context-buffer)
                            context-buffer
                          (window-buffer source-window)))
         (file (buffer-local-value 'buffer-file-name source-buffer)))
    (with-current-buffer source-buffer
      (suderman/treemacs--ensure-frame-workspace)
      (treemacs-add-and-display-current-project-exclusively))
    (with-selected-window (treemacs-get-local-window)
      (suderman/treemacs--repair-tree))
    (when file
      (with-current-buffer source-buffer
        (treemacs-find-file)))
    (when-let* ((window (treemacs-get-local-window)))
      (select-window (if select window source-window)))))

(defun suderman/treemacs-focus ()
  "Focus Treemacs, or return to the editor when already inside it."
  (interactive)
  (if-let* ((window (treemacs-get-local-window)))
      (if (eq window (selected-window))
          (when-let* ((editor (get-mru-window (selected-frame) nil t t)))
            (select-window editor))
        (select-window window))
    (suderman/treemacs--show t)))

(defun suderman/ibuffer-focus-treemacs ()
  "Visit the buffer at point, then reveal it in Treemacs."
  (interactive)
  (if (ibuffer-current-buffer)
      (ibuffer-visit-buffer)
    (quit-window))
  (suderman/treemacs--show t))

(defun suderman/ibuffer-toggle-treemacs ()
  "Toggle Treemacs for the buffer or project group at point."
  (interactive)
  (if (treemacs-get-local-window)
      (suderman/treemacs-close)
    (let* ((group (get-text-property (line-beginning-position)
                                     'ibuffer-filter-group-name))
           (default-directory
            (if (and (stringp group) (file-directory-p group))
                (file-name-as-directory (expand-file-name group))
              default-directory)))
      (suderman/treemacs--show nil (ibuffer-current-buffer)))))

(defun suderman/treemacs-ibuffer ()
  "Visit the current file or tag, then focus IBuffer."
  (interactive)
  (let* ((button (treemacs-current-button))
         (state (and button (treemacs-button-get button :state))))
    (if (memq state '(file-node-open file-node-closed tag-node))
        (progn
          (treemacs-visit-node-in-most-recently-used-window)
          (suderman/ibuffer-toggle))
      (if-let* ((window
                 (seq-find
                  (lambda (candidate)
                    (with-current-buffer (window-buffer candidate)
                      (derived-mode-p 'ibuffer-mode)))
                  (window-list (selected-frame) 'no-minibuffer))))
          (select-window window)
        (select-window
         (or (get-mru-window (selected-frame) nil t t)
             (user-error "No editor window available")))
        (suderman/ibuffer-toggle)))))

(defun suderman/treemacs-toggle ()
  "Toggle Treemacs without moving focus into it when opened."
  (interactive)
  (if (treemacs-get-local-window)
      (suderman/treemacs-close)
    (suderman/treemacs--show nil)))

(defun suderman/treemacs-root-up ()
  "Move this frame's Treemacs root one directory upward."
  (interactive)
  (suderman/treemacs--repair-tree)
  (treemacs-root-up))

(defun suderman/treemacs-root-down ()
  "Move this frame's Treemacs root into the directory at point."
  (interactive)
  (suderman/treemacs--repair-tree)
  (treemacs-root-down))

(defun suderman/treemacs-smart-open (&optional arg)
  "Expand the current node, or visit it when already open or a leaf.
With prefix ARG, expand recursively."
  (interactive "P")
  (when-let* ((button (treemacs-current-button)))
    (let ((state (treemacs-button-get button :state)))
      (pcase state
        ('dir-node-open
         (suderman/treemacs-root-down))
        ((or 'file-node-open 'tag-node-open 'tag-node)
         (treemacs-visit-node-in-most-recently-used-window arg))
        ((or 'file-node-closed 'tag-node-closed)
         (treemacs-TAB-action arg)
         (when (eq state (treemacs-button-get button :state))
           (treemacs-visit-node-in-most-recently-used-window arg)))
        ((or 'root-node-closed 'dir-node-closed)
         (treemacs-TAB-action arg))))))

(defun suderman/treemacs-smart-close ()
  "Collapse the current node, or move the single root upward."
  (interactive)
  (if-let* ((button (treemacs-current-button))
             ((treemacs-is-node-expanded? button)))
      (treemacs-TAB-action)
    (suderman/treemacs-root-up)))

(defun suderman/treemacs-expand-recursively ()
  "Expand the current node and its descendants."
  (interactive)
  (when-let* ((button (treemacs-current-button)))
    (unless (eq (treemacs-button-get button :state) 'tag-node)
      (when (treemacs-is-node-expanded? button)
        (treemacs-TAB-action))
      (treemacs-TAB-action '(4)))))

(defun suderman/treemacs-collapse-recursively ()
  "Collapse the current node and its descendants."
  (interactive)
  (when-let* ((button (treemacs-current-button)))
    (when (treemacs-is-node-expanded? button)
      (treemacs-TAB-action '(4)))))

(defun suderman/treemacs-open ()
  "Enter the directory at point, or visit the current file or tag."
  (interactive)
  (when-let* ((button (treemacs-current-button)))
    (if (memq (treemacs-button-get button :state)
              '(dir-node-open dir-node-closed))
        (suderman/treemacs-root-down)
      (treemacs-visit-node-in-most-recently-used-window))))

(defun suderman/treemacs-create-item ()
  "Create a file, or a directory when its name ends in a slash."
  (interactive)
  (let* ((nearest (treemacs--nearest-path (treemacs-current-button)))
         (base (if (file-directory-p nearest)
                   nearest
                 (file-name-directory nearest)))
         (input (read-file-name "Create file or directory: " base))
         (directoryp (directory-name-p input))
         (path (expand-file-name input)))
    (when (file-exists-p path)
      (user-error "%s already exists" path))
    (if directoryp
        (make-directory path t)
      (make-empty-file path t))
    (treemacs-refresh)
    (treemacs-goto-file-node
     (if directoryp (directory-file-name path) path))))

(use-package treemacs
  :config
  (add-hook 'treemacs-mode-hook #'suderman/treemacs-setup)
  (suderman/treemacs--isolate-existing-frames)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'treemacs-mode)
        (suderman/treemacs-setup))))
  (treemacs-follow-mode 1)
  (treemacs-filewatch-mode 1)
  (when (executable-find "git")
    (treemacs-git-mode (if (executable-find "python3") 'deferred 'simple)))

  (keymap-set ibuffer-mode-map "h" #'suderman/ibuffer-focus-treemacs)
  (keymap-set ibuffer-mode-map "H" #'suderman/ibuffer-toggle-treemacs)
  (keymap-unset ibuffer-mode-map "i" t)
  (keymap-set ibuffer-mode-map "SPC" #'suderman/ibuffer-toggle-treemacs)
  (keymap-set treemacs-mode-map "j" #'treemacs-next-line)
  (keymap-set treemacs-mode-map "k" #'treemacs-previous-line)
  (keymap-set treemacs-mode-map "," #'suderman/treemacs-ibuffer)
  (keymap-set treemacs-mode-map "h" #'suderman/treemacs-smart-close)
  (keymap-set treemacs-mode-map "l" #'suderman/treemacs-smart-open)
  (keymap-set treemacs-mode-map "H" #'suderman/treemacs-collapse-recursively)
  (keymap-set treemacs-mode-map "L" #'suderman/treemacs-expand-recursively)
  (keymap-set treemacs-mode-map "RET" #'suderman/treemacs-open)
  (keymap-set treemacs-mode-map "<return>" #'suderman/treemacs-open)
  (keymap-set treemacs-mode-map "o" #'suderman/treemacs-open)
  (keymap-set treemacs-mode-map "u" #'suderman/treemacs-root-up)
  (keymap-set treemacs-mode-map "n" #'suderman/treemacs-create-item)
  (keymap-set treemacs-mode-map "c" #'treemacs-copy-file)
  (keymap-set treemacs-mode-map "d" #'treemacs-delete-file)
  (keymap-set treemacs-mode-map "r" #'treemacs-rename-file)
  (keymap-set treemacs-mode-map "g" #'treemacs-refresh)
  (keymap-set treemacs-mode-map "t" #'treemacs-filewatch-mode)
  (keymap-set treemacs-mode-map "?" #'treemacs-common-helpful-hydra)
  (keymap-set treemacs-mode-map "q" #'suderman/treemacs-toggle)
  (keymap-set treemacs-mode-map "'" #'ignore)
  (keymap-set treemacs-mode-map "\"" #'ignore)
  (keymap-set treemacs-mode-map "`" #'ignore)
  (keymap-set treemacs-mode-map "~" #'ignore)
  (keymap-set treemacs-mode-map "S" #'ignore)
  (keymap-set treemacs-mode-map "M-h" #'suderman/window-left)
  (keymap-set treemacs-mode-map "M-j" #'windmove-down)
  (keymap-set treemacs-mode-map "M-k" #'windmove-up)
  (keymap-set treemacs-mode-map "M-l" #'windmove-right)
  (keymap-set treemacs-mode-map "M-H" #'suderman/shrink-window-width)
  (keymap-set treemacs-mode-map "M-J" #'suderman/enlarge-window-height)
  (keymap-set treemacs-mode-map "M-K" #'suderman/shrink-window-height)
  (keymap-set treemacs-mode-map "M-L" #'suderman/enlarge-window-width))

(use-package treemacs-nerd-icons
  :after treemacs
  :demand t
  :config
  (treemacs-nerd-icons-config))

(provide 'suderman-treemacs)
;;; suderman-treemacs.el ends here
