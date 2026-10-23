;;; suderman-windows.el --- Window movement and split helpers -*- lexical-binding: t; -*-

;;; Commentary:
;; Small commands used from modal and leader maps.  They intentionally wrap core
;; Emacs window functions so keybindings read like intent instead of plumbing.
;; Views with their own single-letter maps, such as IBuffer and Dirvish, share
;; the Meta window keys and `suderman/meow-off' from here.

;;; Code:

(require 'subr-x)
(require 'tab-bar)
(require 'use-package)
(require 'windmove)

(declare-function meow--disable "meow")
(declare-function meow-mode "meow")

(use-package edger
  :vc (:url "https://github.com/suderman/edger" :lisp-dir "emacs" :rev :newest)
  :ensure nil
  :if t
  :demand t
  :config (when (fboundp 'edger-setup) (edger-setup)))

(setq windmove-allow-all-windows t)

(defvar-keymap suderman/window-keys
  :doc "Meta window keys shared by editors, IBuffer, Dirvish, and Magit."
  "M-h" '("window left" . edger-left)
  "M-j" '("window down" . edger-down)
  "M-k" '("window up" . edger-up)
  "M-l" '("window right" . edger-right)
  "M-H" '("divider left" . edger-resize-left)
  "M-J" '("divider down" . edger-resize-down)
  "M-K" '("divider up" . edger-resize-up)
  "M-L" '("divider right" . edger-resize-right)
  "M-u" '("split below" . edger-horizontal)
  "M-i" '("split right" . edger-vertical)
  "M-n" '("new frame" . suderman/new-frame)
  "M-N" '("new tab" . tab-bar-new-tab)
  "M-w" '("close window" . edger-close))

(defun suderman/install-keys (map keys &optional prefix)
  "Copy every binding in KEYS into MAP below PREFIX.
Prefixes such as ESC are merged key by key, so MAP keeps its other bindings."
  (map-keymap (lambda (event binding)
                (let ((key (vconcat prefix (vector event))))
                  (if (keymapp binding)
                      (suderman/install-keys map binding key)
                    (define-key map key binding))))
              keys))

(defun suderman/meow-off ()
  "Keep Meow off in the current buffer so its own map owns letter keys.
Meow's emulation maps would otherwise outrank the major mode's map.
SPC in these views calls `meow-keypad' directly."
  (add-hook 'meow-mode-hook #'suderman/meow-off nil t)
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

;; Kinetic scrolling after a touch swipe on the Android APK.
(use-package fling
  :vc (:url "https://github.com/suderman/fling" :rev :newest)
  :ensure nil
  :if (featurep 'android)
  :demand t
  :config (fling-mode 1))

(use-package scroll-on-jump
  :demand t
  :custom
  (scroll-on-jump-duration 0.2)
  (scroll-on-jump-curve 'linear)
  :config
  (scroll-on-jump-with-scroll-advice-add scroll-up-command)
  (scroll-on-jump-with-scroll-advice-add scroll-down-command)
  (scroll-on-jump-with-scroll-advice-add recenter-top-bottom)
  (scroll-on-jump-advice-add beginning-of-buffer)
  (scroll-on-jump-advice-add end-of-buffer)
  (scroll-on-jump-advice-add next-error)
  (scroll-on-jump-advice-add previous-error)
  (scroll-on-jump-advice-add pop-to-mark-command)
  (scroll-on-jump-advice-add pop-global-mark)
  (scroll-on-jump-advice-add xref-go-back)
  (scroll-on-jump-advice-add xref-go-forward)
  (with-eval-after-load 'suderman-meow
    (scroll-on-jump-advice-add meow-purrsist-beginning-of-buffer)
    (scroll-on-jump-advice-add meow-purrsist-end-of-buffer)
    (scroll-on-jump-advice-add meow-goto-line)
    (scroll-on-jump-advice-add meow-purrsist-search)
    (scroll-on-jump-advice-add suderman/meow-next-block)
    (scroll-on-jump-advice-add suderman/meow-parent-block)
    (scroll-on-jump-advice-add suderman/meow-child-block)))

(defvar zoom-window-mode-line-color)

(use-package zoom-window
  :commands zoom-window-zoom)

(defun suderman/zoom-window-toggle ()
  "Toggle the selected window's zoomed layout."
  (interactive)
  (let ((zoom-window-mode-line-color
         (or (suderman/theme-blend 'success 0.2)
             (face-background 'mode-line nil t))))
    (zoom-window-zoom)
    (when (frame-parameter (selected-frame) 'zoom-window-enabled)
      ;; `delete-other-windows' preserves side windows after zoom saves the layout.
      (dolist (window (delq (selected-window) (window-list)))
        (delete-window window)))))

(defun suderman/delete-window-or-tab ()
  "Delete the selected window, or close its tab when it is the only window."
  (interactive)
  (cond
   ((not (one-window-p t))
    (delete-window))
   ((> (length (tab-bar-tabs (selected-frame))) 1)
    (tab-bar-close-tab))
   (t
    (user-error "Cannot delete the only window in the only tab"))))

(defun suderman/new-frame ()
  "Open a new graphical frame, or a new tab in a terminal.
A terminal frame would only hide the current one; the multiplexer owns
new windows there.  An Org buffer opens as an indirect clone so each
frame can narrow to its own heading."
  (interactive)
  (if (display-graphic-p)
      (let* ((buffer (window-buffer))
             (clone (with-current-buffer buffer
                      (when (derived-mode-p 'org-mode)
                        (clone-indirect-buffer nil nil))))
             (frame (make-frame-command)))
        (when clone
          (set-window-buffer (frame-selected-window frame) clone)
          (set-frame-parameter frame 'suderman/clone clone)))
    (tab-bar-new-tab)))

(defun suderman/kill-frame-clone (frame)
  "Kill FRAME's indirect clone unless another frame shows it."
  (let ((clone (frame-parameter frame 'suderman/clone)))
    (when (and (buffer-live-p clone)
               (not (seq-some (lambda (window)
                                (not (eq (window-frame window) frame)))
                              (get-buffer-window-list clone nil t))))
      (kill-buffer clone))))

(add-hook 'delete-frame-functions #'suderman/kill-frame-clone)

(defun suderman/save-and-quit ()
  "Save every modified file, then close this client without asking.
A standalone Emacs exits instead."
  (interactive)
  (save-some-buffers t)
  (let ((confirm-kill-emacs nil)
        (confirm-kill-processes nil))
    (save-buffers-kill-terminal)))

(defun suderman/quit-without-saving ()
  "Discard unsaved changes to this client's files, then close it.
A client's files are the ones it opened and those shown in its frames,
so edits in other frames survive.  A standalone Emacs discards all."
  (interactive)
  (let* ((client (frame-parameter nil 'client))
         (buffers
          (if client
              (append (and (processp client) (process-get client 'buffers))
                      (seq-mapcat
                       (lambda (frame)
                         (when (eq (frame-parameter frame 'client) client)
                           (mapcar #'window-buffer (window-list frame 'no-minibuf))))
                       (frame-list)))
            (buffer-list)))
         (discard (seq-filter (lambda (buffer)
                                (and (buffer-file-name buffer)
                                     (buffer-modified-p buffer)))
                              (delete-dups buffers))))
    (dolist (buffer discard)
      (with-current-buffer buffer
        (delete-auto-save-file-if-necessary t)
        (set-buffer-modified-p nil)))
    ;; Close the client first: killing its buffers would end it early.
    (let ((confirm-kill-emacs nil)
          (confirm-kill-processes nil))
      (save-buffers-kill-terminal))
    (mapc #'kill-buffer discard)))

(defun suderman/split-window-below-and-focus ()
  "Split the selected window below and focus the new window."
  (interactive)
  (select-window (split-window-below)))

(defun suderman/split-window-right-and-focus ()
  "Split the selected window right and focus the new window."
  (interactive)
  (select-window (split-window-right)))

(provide 'suderman-windows)
;;; suderman-windows.el ends here
