;;; suderman-meow.el --- Meow modal editing setup -*- lexical-binding: t; -*-

;;; Commentary:
;; Meow provides modal editing while retaining vanilla Emacs keymaps through its
;; keypad.  meow-purrsist owns persistent selections; this module owns personal
;; editing commands and layouts.  Leader bindings live in `suderman-keys'.

;;; Code:

(require 'subr-x)
(require 'use-package)

(declare-function suderman/dashboard "suderman-dashboard")
(declare-function suderman/dirvish "suderman-files")
(declare-function suderman/dirvish-side-toggle "suderman-files")
(declare-function meow-insert-exit "meow" ())

;;;; Leader integration

(defvar suderman/meow-leader-map (make-sparse-keymap)
  "Owned keymap for Suderman's Meow SPC leader bindings.")

(defun suderman/meow-reset-leader-map ()
  "Reset and install Suderman's owned Meow leader map."
  (setq suderman/meow-leader-map (make-sparse-keymap))
  (when (boundp 'meow-keymap-alist)
    (setf (alist-get 'leader meow-keymap-alist)
          suderman/meow-leader-map))
  suderman/meow-leader-map)

(defun suderman/meow-keypad-once ()
  "Run one keypad command without applying it to BEACON cursors."
  (interactive)
  (let (meow--beacon-overlays)
    (meow-keypad)))

(defun suderman/meow-keypad-next-page ()
  "Show the next Which-Key page without leaving Meow KEYPAD state."
  (interactive)
  (which-key-show-next-page-cycle)
  nil)

(defun suderman/meow-keypad-previous-page ()
  "Show the previous Which-Key page without leaving Meow KEYPAD state."
  (interactive)
  (which-key-show-previous-page-cycle)
  nil)

(defun suderman/meow-escape ()
  "Cancel any selection, then exit Insert state or return to the top level."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (if (bound-and-true-p meow-insert-mode)
      (meow-insert-exit)
    (top-level)))

;;;; Personal motion and search

(defun suderman/meow--cancel-active-selection ()
  "Cancel the current Meow selection when the region is active."
  (when (region-active-p)
    (meow--cancel-selection)))

(defun suderman/meow-return ()
  "Clear an active selection, otherwise run the mode's Return command."
  (interactive)
  (if (region-active-p)
      (progn
        (meow--cancel-selection)
        (meow--remove-search-indicator))
    (let ((command (let ((meow-normal-mode nil))
                     (key-binding (this-command-keys-vector)))))
      (call-interactively command))))

(defun suderman/meow--adopt-surround-selection (&rest _)
  "Convert Surround's active region for normal Meow motion."
  (when (bound-and-true-p meow-normal-mode)
    (meow-purrsist-adopt-region)))

(defun suderman/meow--adopt-touch-selection (&rest _)
  "Adopt an Android touch region for normal Meow motion."
  (when (and (eq system-type 'android)
             (bound-and-true-p meow-normal-mode))
    (meow-purrsist-adopt-region)))

(defun suderman/meow-repeat (n)
  "Repeat the previous find or till motion, or the last edit N times."
  (interactive "p")
  (cond
   ((and meow--last-find
         (memq last-command
               '(meow-purrsist-find meow-purrsist-find-backward)))
    (let ((command last-command))
      (setq this-command command)
      (funcall command n meow--last-find)))
   ((and meow--last-till
         (memq last-command
               '(meow-purrsist-till meow-purrsist-till-backward)))
    (let ((command last-command))
      (setq this-command command)
      (funcall command n meow--last-till)))
   (t
    (repeat-fu-execute n))))

(defun suderman/meow--finish-isearch ()
  "Make a successful Isearch match available to Meow's search motions."
  (remove-hook 'isearch-mode-end-hook #'suderman/meow--finish-isearch t)
  (when (and (not isearch-mode-end-hook-quit)
             isearch-success
             (not (string-empty-p isearch-string))
             isearch-other-end)
    ;; Meow searches with `case-fold-search' nil, so encode lowercase
    ;; queries as case-insensitive regexps for its n/p and count paths.
    (meow--push-search
     (if (string= isearch-string (downcase isearch-string))
         (mapconcat (lambda (char)
                      (if (= char (upcase char))
                          (regexp-quote (char-to-string char))
                        (regexp-opt-charset (list char (upcase char)))))
                    isearch-string "")
       (regexp-quote isearch-string)))
    (set-mark isearch-other-end)
    (activate-mark)
    (meow-purrsist-adopt-region)
    (meow--highlight-regexp-in-buffer (car regexp-search-ring))))

(defvar-local suderman/meow-search-count nil
  "Current Meow search match and total for the mode line.")

(defun suderman/meow-show-search-count (_pos idx cnt)
  "Show Meow search match IDX of CNT outside the buffer text."
  (setq suderman/meow-search-count (format " [%d/%d]" idx cnt))
  (force-mode-line-update))

(defun suderman/meow-clear-search-count (&rest _)
  "Clear the mode-line count when Meow removes its search indicator."
  (setq suderman/meow-search-count nil)
  (force-mode-line-update))

(defun suderman/meow-start-search ()
  "Search incrementally for literal text, then select it for Meow n/p."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (meow--remove-search-indicator)
  (add-hook 'isearch-mode-end-hook #'suderman/meow--finish-isearch nil t)
  (let ((case-fold-search t)
        (search-upper-case t)
        (search-default-mode nil))
    (isearch-forward)))

(defun suderman/meow-search (&optional backward)
  "Search in the requested direction, leaving a character selection.
Search backward when BACKWARD is non-nil, otherwise search forward."
  (interactive)
  (let ((selecting (region-active-p)))
    (when selecting
      (funcall (if backward
                   #'meow--direction-backward
                 #'meow--direction-forward)))
    (meow-search (and backward (not selecting) -1)))
  (meow-purrsist-adopt-region))

(defun suderman/meow-search-backward ()
  "Search backward, leaving an expandable character selection."
  (interactive)
  (suderman/meow-search t))

(defun suderman/meow-smart-beginning-of-line ()
  "Move to indentation, or to beginning of line if already there."
  (interactive)
  (let ((target
         (save-excursion
           (let ((origin (point)))
             (back-to-indentation)
             (if (= origin (point))
                 (line-beginning-position)
               (point))))))
    (meow-purrsist-move-to target)))

(defun suderman/meow-smart-end-of-line ()
  "Move to end of code, or end of line if already there."
  (interactive)
  (let* ((origin (point))
         (eol (line-end-position))
         (code-end
          (save-excursion
            (comment-normalize-vars)
            (goto-char eol)
            (when-let* ((comment-pos (comment-beginning)))
              (goto-char comment-pos)
              (skip-chars-backward " \t")
              (point))))
         (target
          (cond
           ;; Before trailing comment: end of code.
           ((and code-end
                 (> code-end (line-beginning-position))
                 (< origin code-end))
            code-end)

           ;; At end of code: physical EOL.
           ((and code-end (= origin code-end))
            eol)

           ;; No comment, or already inside comment.
           (t eol))))
    (meow-purrsist-move-to target)))

(defun suderman/meow-buffer-beginning ()
  "Move to the beginning of the buffer, extending an active selection."
  (interactive)
  (meow-purrsist-move-to (point-min)))

(defun suderman/meow-buffer-end ()
  "Move to the end of the buffer, extending an active selection."
  (interactive)
  (meow-purrsist-move-to (point-max)))

;;;; Editing

(defun suderman/meow--shift-lines (columns)
  "Shift the selected lines or current line by COLUMNS."
  (let* ((selection (region-active-p))
         (selection-beg (if selection (region-beginning) (point)))
         (selection-end (if selection (region-end) (point)))
         (beg (save-excursion
                (goto-char selection-beg)
                (line-beginning-position)))
         (end (if selection
                  selection-end
                (save-excursion
                  (goto-char selection-end)
                  (line-beginning-position 2))))
         (cursor (copy-marker (point) t)))
    (unwind-protect
        (progn
          (indent-rigidly beg end columns)
          (goto-char cursor)
          (when selection
            (setq deactivate-mark nil)))
      (set-marker cursor nil))))

(defun suderman/meow-indent ()
  "Demote the current Org element or indent ordinary lines."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'org-metaright)
    (suderman/meow--shift-lines 2)))

(defun suderman/meow-outdent ()
  "Promote the current Org element or outdent ordinary lines."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'org-metaleft)
    (suderman/meow--shift-lines -2)))

(defun suderman/meow-insert ()
  "Enter insert state, recording edits when in BEACON state."
  (interactive)
  (if (bound-and-true-p meow-beacon-mode)
      (meow-beacon-insert)
    (suderman/meow--cancel-active-selection)
    (meow-insert)))

(defun suderman/meow-insert-at-indentation ()
  "Extend an active selection to smart line start, or insert there."
  (interactive)
  (if (region-active-p)
      (meow-purrsist-extend-with-motion
       #'suderman/meow-smart-beginning-of-line)
    (suderman/meow-smart-beginning-of-line)
    (suderman/meow-insert)))

(defun suderman/meow-insert-at-end-of-line ()
  "Extend an active selection to smart line end, or insert there."
  (interactive)
  (if (region-active-p)
      (meow-purrsist-extend-with-motion
       #'suderman/meow-smart-end-of-line)
    (suderman/meow-smart-end-of-line)
    (suderman/meow-insert)))

(defun suderman/meow-delete ()
  "Delete selection, or one character forward.
Deleted text is not added to the kill ring or clipboard."
  (interactive)
  (if (use-region-p)
      (delete-active-region)
    (unless (eobp)
      (delete-char 1))))

(defun suderman/meow-kill ()
  "Cut a multi-character selection, then enter insert state.
Delete a single selected character or one character forward without cutting."
  (interactive)
  (cond
   ((use-region-p)
    (if (> (- (region-end) (region-beginning)) 1)
        (let ((select-enable-clipboard meow-use-clipboard))
          (delete-active-region t))
      (delete-active-region)))
   ((not (eobp))
    (delete-char 1)))
  (suderman/meow-insert))

(defun suderman/meow-replace-char (char)
  "Replace the character immediately after point with CHAR."
  (interactive (list (read-char "Replace with: ")))
  (suderman/meow--cancel-active-selection)
  (when (eolp)
    (user-error "No character to replace"))
  (delete-char 1)
  (insert-char char)
  (backward-char 1))

(defun suderman/meow-paste ()
  "Paste the current kill.

Characterwise text is inserted exactly at point.
Linewise text is inserted as a new line below the current line.
An active selection is replaced without modifying the kill ring."
  (interactive)
  (unless kill-ring
    (user-error "Kill ring is empty"))
  (let ((text (current-kill 0 t)))
    (cond
     ;; Explicit selection: replace it exactly.
     ((use-region-p)
      (delete-active-region)
      (insert-for-yank text))

     ;; Linewise text: paste below current line.
     ((string-suffix-p "\n" text)
      (end-of-line)
      (if (eobp)
          (insert "\n")
        (forward-char 1))
      (let ((start (point)))
        (insert-for-yank text)
        (goto-char start)
        (back-to-indentation)))

     ;; Characterwise text: paste exactly at point.
     (t
      (insert-for-yank text)))))

(defun suderman/meow--move-selected-lines (command)
  "Move complete lines in the active selection using COMMAND."
  (when (bound-and-true-p rectangle-mark-mode)
    (rectangle-mark-mode -1))
  (let ((backward (meow--direction-backward-p))
        (missing-final-newline
         (and (> (point-max) (point-min))
              (not (eq (char-before (point-max)) ?\n))))
        moved-beg
        moved-end)
    ;; `move-text' needs a terminating newline to move a final line cleanly.
    (when missing-final-newline
      (save-excursion
        (goto-char (point-max))
        (insert "\n")))
    (unwind-protect
        (let* ((beg (save-excursion
                      (goto-char (region-beginning))
                      (line-beginning-position)))
               (end (save-excursion
                      (goto-char (region-end))
                      (if (and (> (point) beg) (bolp))
                          (point)
                        (line-beginning-position 2)))))
          (goto-char end)
          (set-mark beg)
          (activate-mark)
          (funcall command beg end
                   (prefix-numeric-value current-prefix-arg))
          (setq moved-beg (copy-marker (region-beginning))
                moved-end (copy-marker (region-end) t)))
      (when missing-final-newline
        (save-excursion
          (goto-char (point-max))
          (delete-char -1))))
    (let ((beg (marker-position moved-beg))
          (end (marker-position moved-end)))
      (set-marker moved-beg nil)
      (set-marker moved-end nil)
      (when (and (> end beg) (eq (char-before end) ?\n))
        (setq end (1- end)))
      (goto-char (if backward beg end))
      (set-mark (if backward end beg))
      (activate-mark)
      (meow-purrsist-adopt-region 'line))))

(defun suderman/move-up ()
  "Move the current Org element or ordinary lines upward."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'org-metaup)
    (if (use-region-p)
        (suderman/meow--move-selected-lines #'move-text-up)
      (call-interactively #'move-text-up))))

(defun suderman/move-down ()
  "Move the current Org element or ordinary lines downward."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'org-metadown)
    (if (use-region-p)
        (suderman/meow--move-selected-lines #'move-text-down)
      (call-interactively #'move-text-down))))

(defun suderman/meow-join-line ()
  "Join the current line with the following line, like Vim `J'."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (delete-indentation 1))

(defun suderman/meow-join-sexp-unavailable ()
  "Report that no structural editing command is configured."
  (interactive)
  (user-error "No structural editing package configured"))

(defun suderman/meow-save ()
  "Copy the active selection, or the current buffer's file path."
  (interactive)
  (if (use-region-p)
      (save-excursion (meow-save))
    (if-let* ((file buffer-file-name))
        (let ((select-enable-clipboard meow-use-clipboard))
          (kill-new file))
      (user-error "Current buffer is not visiting a file"))))

(defun suderman/meow--line-bounds ()
  "Return bounds of current line, including its newline when present."
  (cons (line-beginning-position)
        (line-beginning-position 2)))

(defun suderman/meow-delete-line ()
  "Delete the selection or current line without adding it to the kill ring."
  (interactive)
  (if (use-region-p)
      (suderman/meow-delete)
    (suderman/meow--cancel-active-selection)
    (pcase-let ((`(,beg . ,end) (suderman/meow--line-bounds)))
      (delete-region beg end)
      (goto-char beg)
      (back-to-indentation))))

(defun suderman/meow-kill-line ()
  "Cut the selection or current line, then enter insert state."
  (interactive)
  (if (use-region-p)
      (suderman/meow-kill)
    (suderman/meow--cancel-active-selection)
    (pcase-let ((`(,beg . ,end) (suderman/meow--line-bounds)))
      (let ((select-enable-clipboard meow-use-clipboard))
        (kill-region beg end))
      (goto-char beg)
      (back-to-indentation)
      (suderman/meow-insert))))

;;;; Keymaps and mode activation

(use-package surround
  :demand t
  :config
  (advice-add 'surround--op-mark :after
              #'suderman/meow--adopt-surround-selection))

(defun suderman/meow--cheatsheet-command-name (original command)
  "Label Surround's anonymous prefix map, or call ORIGINAL for COMMAND."
  (if (and (keymapp command)
           (eq (lookup-key command (kbd "s")) #'surround-insert)
           (eq (lookup-key command (kbd "d")) #'surround-delete))
      (format "% 9s" "surround")
    (funcall original command)))

(defun suderman/meow-setup-qwerty ()
  "Install Suderman's QWERTY Meow bindings."
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (setf (alist-get ?h meow-keypad-start-keys) ?h)
  ;; Remove the former backslash prefix before installing its single-key command.
  (dolist (map (list meow-normal-state-keymap meow-motion-state-keymap))
    (define-key map (kbd "\\") nil))
  (dolist (key '("'" "\"" "`" "~"))
    (define-key meow-motion-state-keymap (kbd key) nil))
  (keymap-unset meow-motion-state-keymap "S" t)
  (keymap-unset meow-normal-state-keymap "S" t)
  (dolist (entry '((nil . "")
                   (ignore . "")
                   (suderman/format-buffer . "format")
                   (suderman/meow-smart-beginning-of-line . "code beg")
                   (beginning-of-line . "line beg")
                   (meow-purrsist-back-word . "word back")
                   (meow-purrsist-back-symbol . "sym back")
                   (suderman/meow-delete . "delete")
                   (suderman/meow-delete-line . "del line")
                   (suderman/meow-smart-end-of-line . "code end")
                   (end-of-line . "line end")
                   (execute-extended-command . "M-x")
                   (evilmi-jump-items-native . "match")
                   (kill-current-buffer . "kill buf")
                   (next-buffer . "next buf")
                   (previous-buffer . "prev buf")
                   (meow-purrsist-find . "find fwd")
                   (meow-purrsist-find-backward . "find back")
                   (suderman/meow-buffer-beginning . "buf beg")
                   (suderman/meow-buffer-end . "buf end")
                   (suderman/meow-indent . "indent")
                   (suderman/meow-insert . "insert")
                   (suderman/meow-insert-at-indentation . "at indent")
                   (suderman/meow-insert-at-end-of-line . "at eol")
                   (meow-purrsist-line-or-rectangle . "line/rect")
                   (meow-purrsist-next . "down")
                   (suderman/meow-outdent . "outdent")
                   (meow-purrsist-prev . "up")
                   (suderman/meow-start-search . "search")
                   (suderman/meow-search . "search +")
                   (suderman/meow-search-backward . "search -")
                   (suderman/meow-join-line . "join line")
                   (suderman/move-down . "move down")
                   (suderman/move-up . "move up")
                   (suderman/meow-paste . "paste")
                   (suderman/meow-replace-char . "rep char")
                   (suderman/meow-repeat . "repeat")
                   (meow-purrsist-till . "till fwd")
                   (meow-purrsist-till-backward . "till back")
                   (meow-purrsist-visual . "select")
                   (suderman/ibuffer-toggle . "buffers")
                   (suderman/dashboard . "dashboard")
                   (suderman/dirvish . "files")
                   (suderman/dirvish-side-toggle . "sidebar")
                   (surround-insert . "surround")
                   (meow-purrsist-next-word . "word fwd")
                   (meow-purrsist-next-word-start . "word beg")
                   (meow-purrsist-next-symbol . "sym fwd")
                   (meow-purrsist-next-symbol-start . "sym beg")
                   (suderman/meow-kill . "cut")
                   (suderman/meow-kill-line . "cut line")
                   (suderman/meow-save . "copy")))
    (setf (alist-get (car entry) meow-command-to-short-name-list)
          (cdr entry)))

  (meow-define-keys
      'beacon
    '("SPC" . suderman/meow-keypad-once))
  
  (meow-motion-define-key
   '("\\" . suderman/dirvish-side-toggle)
   '("h" . meow-left)
   '("j" . meow-next)
   '("k" . meow-prev)
   '("l" . meow-right)
   '("B" . meow-purrsist-back-symbol)
   '("<" . previous-buffer)
   '(">" . next-buffer)
   '("`" . suderman/dashboard)
   '("<escape>" . suderman/meow-escape))
  
  (meow-normal-define-key
   '("0" . meow-expand-0)
   '("9" . meow-expand-9)
   '("8" . meow-expand-8)
   '("7" . meow-expand-7)
   '("6" . meow-expand-6)
   '("5" . meow-expand-5)
   '("4" . meow-expand-4)
   '("3" . meow-expand-3)
   '("2" . meow-expand-2)
   '("1" . meow-expand-1)
   '("-" . negative-argument)
   '("=" . suderman/format-buffer)
   '("'" . ignore)
   '("?" . meow-reverse)
   '(":" . execute-extended-command)
   '("#" . meow-goto-line)
   '("$" . suderman/meow-smart-end-of-line)
   '("%" . evilmi-jump-items-native)
   '("^" . suderman/meow-smart-beginning-of-line)
   '("(" . meow-left-expand)
   '(")" . meow-right-expand)
   '("," . suderman/ibuffer-toggle)
   '("." . suderman/dirvish)
   '("\\" . suderman/dirvish-side-toggle)
   '("<" . previous-buffer)
   '(">" . next-buffer)
   '("[" . meow-inner-of-thing)
   '("]" . meow-bounds-of-thing)
   '("{" . meow-beginning-of-thing)
   '("}" . meow-end-of-thing)
   '("\"" . ignore)
   '("`" . suderman/dashboard)
   '("~" . ignore)
   '("C-j" . suderman/meow-join-line)
   '("a" . meow-append)
   '("A" . suderman/meow-insert-at-end-of-line)
   '("b" . meow-purrsist-back-word)
   '("B" . meow-purrsist-back-symbol)
   '("c" . suderman/meow-save)
   '("C" . meow-page-up)
   '("d" . suderman/meow-delete)
   '("D" . suderman/meow-delete-line)
   '("e" . meow-purrsist-next-word)
   '("E" . meow-purrsist-next-symbol)
   '("f" . meow-purrsist-find)
   '("F" . meow-purrsist-find-backward)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . suderman/meow-outdent)
   '("i" . suderman/meow-insert)
   '("I" . suderman/meow-insert-at-indentation)
   '("j" . meow-purrsist-next)
   '("J" . suderman/move-down)
   '("k" . meow-purrsist-prev)
   '("K" . suderman/move-up)
   '("l" . meow-right)
   '("L" . suderman/meow-indent)
   '("m" . meow-purrsist-visual)
   '("M" . meow-purrsist-line-or-rectangle)
   '("n" . suderman/meow-search)
   '("N" . suderman/meow-buffer-end)
   '("o" . meow-open-below)
   '("O" . meow-open-above)
   '("p" . suderman/meow-search-backward)
   '("P" . suderman/meow-buffer-beginning)
   '("q" . meow-quit)
   '("Q" . kill-current-buffer)
   '("r" . suderman/meow-replace-char)
   '("R" . meow-swap-grab)
   '("RET" . suderman/meow-return)
   (cons "s" surround-keymap)
   '("t" . meow-purrsist-till)
   '("T" . meow-purrsist-till-backward)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("v" . suderman/meow-paste)
   '("V" . meow-page-down)
   '("w" . meow-purrsist-next-word-start)
   '("W" . meow-purrsist-next-symbol-start)
   '("x" . suderman/meow-kill)
   '("X" . suderman/meow-kill-line)
   '("y" . undo-redo)
   '("Y" . meow-sync-grab)
   '("z" . meow-pop-selection)
   '("Z" . suderman/meow-buffer-end)
   '(";" . suderman/meow-repeat)
   '("/" . suderman/meow-start-search)
   '("<escape>" . suderman/meow-escape)))

(use-package evil-matchit
  :commands evilmi-jump-items-native)

(use-package move-text
  :commands (move-text-up move-text-down))

(declare-function set-text-conversion-style "textconv.c"
                  (value &optional after-key-sequence))

(defvar meow--current-state)

;; FUTO spacebar swipes work only in Insert.  Normal and Motion disable text
;; conversion so IME text cannot bypass Meow's command keymaps.
(defun suderman/android-meow-text-conversion (state)
  "Set Android text conversion appropriately for Meow STATE."
  (when (eq system-type 'android)
    (let ((style (eq state 'insert)))
      (unless (eq text-conversion-style style)
        (set-text-conversion-style style)))))

(defun suderman/android-initialize-meow-text-conversion ()
  "Set Android text conversion for the current Meow state."
  (suderman/android-meow-text-conversion meow--current-state))

(defun suderman/repeat-fu-mode-maybe ()
  "Enable Repeat-FU in buffers that start in Meow normal state."
  (repeat-fu-mode
   (if (and (bound-and-true-p meow-mode)
            (bound-and-true-p meow-normal-mode))
       1
     -1)))

(use-package repeat-fu
  :commands (repeat-fu-mode repeat-fu-execute)
  :init
  (setq repeat-fu-preset 'meow
        repeat-fu-global-mode t)
  :hook (meow-mode . suderman/repeat-fu-mode-maybe))

(use-package meow
  :demand t
  :init
  (setq meow-use-clipboard t
        meow-keypad-ctrl-meta-prefix ?M
        meow-use-cursor-position-hack t
        meow--kbd-undo #'undo-only
        ;; Keep Meow editing commands independent from modal key overrides.
        meow--kbd-join-sexp #'suderman/meow-join-sexp-unavailable
        meow--kbd-kill-ring-save #'kill-ring-save
        meow-expand-selection-type 'expand
        meow-expand-hint-counts
        '((word . 0)
          (line . 30)
          (block . 30)
          (find . 30)
          (till . 30))
        meow-mode-state-list
        '((image-mode . motion)
          (conf-mode . normal)
          (fundamental-mode . normal)
          (prog-mode . normal)
          (text-mode . normal)
          (dired-mode . motion)
          (dirvish-mode . motion)
          (help-mode . motion)
          (Info-mode . motion)
          (special-mode . motion)
          (compilation-mode . motion)
          (grep-mode . motion)
          (occur-mode . motion)
          (messages-buffer-mode . motion)
          (eshell-mode . insert)
          (shell-mode . insert)
          (term-mode . insert)
          (ghostel-mode . insert)))
  :config
  (use-package meow-purrsist
    :vc (:url "https://github.com/suderman/meow-purrsist" :rev :newest)
    :ensure nil
    :if t
    :demand t)
  (advice-remove 'meow--show-indicator #'suderman/meow-show-search-count)
  (advice-add 'meow--show-indicator :override
              #'suderman/meow-show-search-count)
  (advice-remove 'meow--remove-search-indicator
                 #'suderman/meow-clear-search-count)
  (advice-add 'meow--remove-search-indicator :after
              #'suderman/meow-clear-search-count)
  (doom-modeline-def-segment suderman-meow-search
    "Show Meow's search match count without changing buffer layout."
    (when (bound-and-true-p suderman/meow-search-count)
      (propertize suderman/meow-search-count 'face 'meow-search-indicator)))
  (doom-modeline-remove-segment 'suderman-meow-search)
  (doom-modeline-add-segment 'suderman-meow-search 'matches :after)
  ;; Drop the old thing advice in sessions upgraded through hot reload.
  (dolist (command '(meow-beginning-of-thing meow-end-of-thing
                     meow-inner-of-thing meow-bounds-of-thing))
    (advice-remove command #'suderman/meow--adopt-surround-selection))
  (meow-purrsist-mode 1)
  (advice-remove 'touch-screen-hold #'suderman/meow--adopt-touch-selection)
  (advice-add 'touch-screen-hold :after #'suderman/meow--adopt-touch-selection)
  (advice-remove 'meow--short-command-name
                 #'suderman/meow--cheatsheet-command-name)
  (advice-add 'meow--short-command-name :around
              #'suderman/meow--cheatsheet-command-name)
  (remove-hook 'meow-mode-hook 'suderman/android-sync-meow-text-conversion)
  (remove-hook 'meow-insert-enter-hook
               'suderman/android-sync-meow-text-conversion)
  (remove-hook 'meow-insert-exit-hook
               'suderman/android-sync-meow-text-conversion)
  (add-hook 'meow-mode-hook
            #'suderman/android-initialize-meow-text-conversion)
  (add-hook 'meow-switch-state-hook
            #'suderman/android-meow-text-conversion)
  (suderman/meow-reset-leader-map)
  (suderman/meow-setup-qwerty)
  (keymap-set meow-keypad-state-keymap "<right>"
              #'suderman/meow-keypad-next-page)
  (keymap-set meow-keypad-state-keymap "<down>"
              #'suderman/meow-keypad-next-page)
  (keymap-set meow-keypad-state-keymap "<left>"
              #'suderman/meow-keypad-previous-page)
  (keymap-set meow-keypad-state-keymap "<up>"
              #'suderman/meow-keypad-previous-page)
  (meow-global-mode 1)
  (suderman/android-initialize-meow-text-conversion))

(provide 'suderman-meow)
;;; suderman-meow.el ends here
