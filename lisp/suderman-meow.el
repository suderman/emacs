;;; suderman-meow.el --- Meow modal editing setup -*- lexical-binding: t; -*-

;;; Commentary:
;; Meow provides modal editing while retaining vanilla Emacs keymaps through its
;; keypad.  This module owns custom selection and editing commands plus the
;; normal and motion layouts; leader command bindings live in `suderman-keys'.

;;; Code:

(require 'subr-x)
(require 'use-package)

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

;;;; Selection and motion

;; Selection construction is intentionally centralized here because exact
;; selection type and history behavior require Meow's internal API.

(defvar-local suderman/meow-visual-stage 0
  "Current consecutive `suderman/meow-visual' expansion stage.")

(defun suderman/meow--cancel-active-selection ()
  "Cancel the current Meow selection when the region is active."
  (when (region-active-p)
    (meow--cancel-selection)))

(defun suderman/meow--move-line-selection (n)
  "Move the active end of a line selection by N lines.

Unlike `meow-line-expand', direction is physical:
positive N moves down and negative N moves up.
Crossing the anchor reverses the selection naturally."
  (let* ((anchor (mark t))
         (active (point))
         (anchor-bounds
          (save-excursion
            (goto-char anchor)
            (cons (line-beginning-position)
                  (line-end-position))))
         (target-bounds
          (save-excursion
            (goto-char active)
            (forward-line n)
            (cons (line-beginning-position)
                  (line-end-position))))
         (anchor-beg (car anchor-bounds))
         (anchor-end (cdr anchor-bounds))
         (target-beg (car target-bounds))
         (target-end (cdr target-bounds)))
    (cond
     ;; Active line is below anchor.
     ((> target-beg anchor-beg)
      (thread-first
          (meow--make-selection
           '(expand . line) anchor-beg target-end)
        (meow--select t)))

     ;; Active line is above anchor.
     ((< target-beg anchor-beg)
      (thread-first
          (meow--make-selection
           '(expand . line) anchor-end target-beg)
        (meow--select t)))

     ;; Back on the anchor line.
     (t
      (thread-first
          (meow--make-selection
           '(expand . line) anchor-beg anchor-end)
        (meow--select t))))))

(defun suderman/meow-next (arg)
  "Move down, preserving Meow selection behavior."
  (interactive "P")
  (if (equal (meow--selection-type) '(expand . line))
      (suderman/meow--move-line-selection
       (prefix-numeric-value arg))
    (meow-next arg)))

(defun suderman/meow-prev (arg)
  "Move up, preserving Meow selection behavior."
  (interactive "P")
  (if (equal (meow--selection-type) '(expand . line))
      (suderman/meow--move-line-selection
       (- (prefix-numeric-value arg)))
    (meow-prev arg)))

(defun suderman/meow--select-to (pos)
  "Select from the current anchor to POS as an expandable char selection."
  (let ((anchor (if (region-active-p)
                    (mark)
                  (point))))
    (thread-first
        (meow--make-selection '(expand . char) anchor pos)
      (meow--select t))))

(defun suderman/meow--adopt-surround-selection (&rest _)
  "Convert Surround's active region to a Meow character selection."
  (when (and (bound-and-true-p meow-normal-mode)
             (region-active-p))
    (suderman/meow--select-to (point))))

(defun suderman/meow--move-to (pos)
  "Move to POS, extending the active selection when present."
  (if (region-active-p)
      (suderman/meow--select-to pos)
    (goto-char pos)))

(defun suderman/meow--select-thing (thing n)
  "Move forward N instances of THING, extending an active selection."
  (let ((target
         (save-excursion
           (forward-thing thing n)
           (point))))
    (suderman/meow--move-to target)))

(defun suderman/meow-next-word (n)
  "Move forward N words, extending an active selection."
  (interactive "p")
  (suderman/meow--select-thing meow-word-thing n))

(defun suderman/meow-back-word (n)
  "Move backward N words, extending an active selection."
  (interactive "p")
  (suderman/meow--select-thing meow-word-thing (- n)))

(defun suderman/meow-next-symbol (n)
  "Move forward N symbols, extending an active selection."
  (interactive "p")
  (suderman/meow--select-thing meow-symbol-thing n))

(defun suderman/meow-back-symbol (n)
  "Move backward N symbols, extending an active selection."
  (interactive "p")
  (suderman/meow--select-thing meow-symbol-thing (- n)))

(defun suderman/meow--finish-find-motion (selecting)
  "Keep a find motion's selection only when SELECTING was already active."
  (when (region-active-p)
    (if selecting
        (suderman/meow--select-to (point))
      (let ((target (point)))
        (meow--cancel-selection)
        (goto-char target)))))

(defun suderman/meow-till (n char)
  "Move till CHAR like Meow, extending an active selection."
  (interactive "p\ncTill: ")
  (let ((selecting (region-active-p)))
    (setq meow--last-till nil)
    (meow-till n char t)
    (suderman/meow--finish-find-motion selecting)))

(defun suderman/meow-till-backward (n char)
  "Move backward till CHAR, extending an active selection."
  (interactive "p\ncTill backward: ")
  (suderman/meow-till (- n) char))

(defun suderman/meow-repeat (n)
  "Repeat the previous till motion, or the last edit N times."
  (interactive "p")
  (if (and meow--last-till
           (memq last-command
                 '(suderman/meow-till suderman/meow-till-backward)))
      (let ((command last-command))
        (setq this-command command)
        (funcall command n meow--last-till))
    (repeat-fu-execute n)))

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
  (when (region-active-p)
    (suderman/meow--select-to (point))))

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
    (suderman/meow--move-to target)))

(defun suderman/meow-smart-end-of-line ()
  "Move to end of code, or end of line if already there."
  (interactive)
  (let* ((origin (point))
         (eol (line-end-position))
         (code-end
          (save-excursion
            (comment-normalize-vars)
            (goto-char eol)
            (when-let ((comment-pos (comment-beginning)))
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
    (suderman/meow--move-to target)))

(defun suderman/meow-buffer-beginning ()
  "Move to the beginning of the buffer, extending an active selection."
  (interactive)
  (suderman/meow--move-to (point-min)))

(defun suderman/meow-buffer-end ()
  "Move to the end of the buffer, extending an active selection."
  (interactive)
  (suderman/meow--move-to (point-max)))

(defun suderman/meow-line-or-rectangle (n)
  "Select a rectangle, N lines, then the buffer when repeated."
  (interactive "p")
  (cond
   ((not (eq last-command 'suderman/meow-line-or-rectangle))
    (rectangle-mark-mode 1))
   ((bound-and-true-p rectangle-mark-mode)
    (meow--cancel-selection)
    (rectangle-mark-mode -1)
    (meow-line n))
   (t
    (thread-first
        (meow--make-selection '(expand . char) (point-min) (point-max))
      (meow--select t)))))

(defun suderman/meow-visual ()
  "Select a word, then expand through symbol and blocks.

Keep every result as a char selection so motion commands can fine-tune it."
  (interactive)
  (setq suderman/meow-visual-stage
        (if (eq last-command 'suderman/meow-visual)
            (min 3 (1+ suderman/meow-visual-stage))
          1))
  (pcase suderman/meow-visual-stage
    (1
     (meow-mark-word 1)
     (suderman/meow--select-to (point)))
    (2
     (goto-char (region-beginning))
     (meow-mark-symbol 1)
     (suderman/meow--select-to (point)))
    (3
     (meow-block nil)
     (suderman/meow--select-to (point)))))

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
  "Enter insert state at the current point, discarding any selection."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (meow-insert))

(defun suderman/meow-insert-at-indentation ()
  "Enter Meow insert state at the first non-whitespace character."
  (interactive)
  (back-to-indentation)
  (suderman/meow-insert))

(defun suderman/meow-insert-at-end-of-line ()
  "Enter Meow insert state at the end of the current line."
  (interactive)
  (end-of-line)
  (suderman/meow-insert))

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
      (thread-first
          (meow--make-selection '(expand . line) beg end)
        (meow--select t backward)))))

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
  "Copy the active selection, or the current line if none is active."
  (interactive)
  (if (use-region-p)
      (meow-save)
    (let ((select-enable-clipboard meow-use-clipboard))
      (kill-ring-save
       (line-beginning-position)
       (line-beginning-position 2)))))

(defun suderman/meow--line-bounds ()
  "Return bounds of current line, including its newline when present."
  (cons (line-beginning-position)
        (line-beginning-position 2)))

(defun suderman/meow-delete-line ()
  "Delete the entire current line without adding it to the kill ring."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (pcase-let ((`(,beg . ,end) (suderman/meow--line-bounds)))
    (delete-region beg end)
    (goto-char beg)
    (back-to-indentation)))

(defun suderman/meow-kill-line ()
  "Kill the entire current line, adding it to the kill ring and clipboard."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (pcase-let ((`(,beg . ,end) (suderman/meow--line-bounds)))
    (let ((select-enable-clipboard meow-use-clipboard))
      (kill-region beg end))
    (goto-char beg)
    (back-to-indentation)
    (suderman/meow-insert)))

;;;; Keymaps and mode activation

(use-package surround
  :demand t
  :config
  (advice-add 'surround--op-mark :after
              #'suderman/meow--adopt-surround-selection))

(defun suderman/meow-setup-qwerty ()
  "Install Suderman's QWERTY Meow bindings."
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (dolist (entry '((suderman/meow-smart-beginning-of-line . "code beg")
                   (beginning-of-line . "line beg")
                   (suderman/meow-back-word . "word back")
                   (suderman/meow-back-symbol . "sym back")
                   (suderman/meow-delete . "delete")
                   (suderman/meow-delete-line . "del line")
                   (suderman/meow-smart-end-of-line . "code end")
                   (end-of-line . "line end")
                   (execute-extended-command . "M-x")
                   (evilmi-jump-items-native . "match")
                   (kill-current-buffer . "kill buf")
                   (suderman/meow-buffer-beginning . "buf beg")
                   (suderman/meow-buffer-end . "buf end")
                   (suderman/meow-indent . "indent")
                   (suderman/meow-insert . "insert")
                   (suderman/meow-insert-at-indentation . "at indent")
                   (suderman/meow-insert-at-end-of-line . "at eol")
                   (suderman/meow-line-or-rectangle . "line/rect")
                   (suderman/meow-next . "down")
                   (suderman/meow-outdent . "outdent")
                   (suderman/meow-prev . "up")
                   (suderman/meow-search . "search +")
                   (suderman/meow-search-backward . "search -")
                   (suderman/meow-join-line . "join line")
                   (suderman/move-down . "move down")
                   (suderman/move-up . "move up")
                   (suderman/meow-paste . "paste")
                   (suderman/meow-replace-char . "rep char")
                   (suderman/meow-repeat . "repeat")
                   (suderman/meow-till . "till fwd")
                   (suderman/meow-till-backward . "till back")
                   (suderman/meow-visual . "select")
                   (suderman/speedbar-toggle . "speedbar")
                   (suderman/treemacs-toggle . "treemacs")
                   (surround-insert . "surround")
                   (suderman/meow-next-word . "word fwd")
                   (suderman/meow-next-symbol . "sym fwd")
                   (suderman/meow-kill . "cut")
                   (suderman/meow-kill-line . "cut line")
                   (suderman/meow-save . "copy")))
    (setf (alist-get (car entry) meow-command-to-short-name-list)
          (cdr entry)))
  
  (meow-motion-define-key
   '("S" . suderman/speedbar-toggle)
   '("`" . suderman/treemacs-toggle)
   '("~" . ignore)
   '("\\ \\" . suderman/alternate-buffer)
   '("h" . meow-left)
   '("j" . meow-next)
   '("k" . meow-prev)
   '("l" . meow-right)
   '("<escape>" . ignore))
  
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
   '(";" . meow-reverse)
   '(":" . execute-extended-command)
   '("#" . meow-goto-line)
   '("%" . evilmi-jump-items-native)
   '("<" . meow-left-expand)
   '(">" . meow-right-expand)
   '("," . ignore)
   '("." . suderman/meow-repeat)
   '("[" . meow-inner-of-thing)
   '("]" . meow-bounds-of-thing)
   '("{" . meow-beginning-of-thing)
   '("}" . meow-end-of-thing)
   '("`" . suderman/treemacs-toggle)
   '("~" . ignore)
   '("\\ \\" . suderman/alternate-buffer)
   '("\\ =" . suderman/speedbar-toggle)
   '("\\ J" . suderman/meow-join-line)
   '("\\ ]" . suderman/speedbar-toggle)
   '("a" . suderman/meow-smart-beginning-of-line)
   '("A" . suderman/meow-buffer-beginning)
   '("b" . suderman/meow-back-word)
   '("B" . suderman/meow-back-symbol)
   '("c" . suderman/meow-save)
   '("C" . meow-page-up)
   '("d" . suderman/meow-delete)
   '("D" . suderman/meow-delete-line)
   '("e" . suderman/meow-smart-end-of-line)
   '("E" . suderman/meow-insert-at-end-of-line)
   '("f" . suderman/meow-next-word)
   '("F" . suderman/meow-next-symbol)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . suderman/meow-outdent)
   '("i" . suderman/meow-insert)
   '("I" . suderman/meow-insert-at-indentation)
   '("j" . suderman/meow-next)
   '("J" . suderman/move-down)
   '("k" . suderman/meow-prev)
   '("K" . suderman/move-up)
   '("l" . meow-right)
   '("L" . suderman/meow-indent)
   '("m" . suderman/meow-visual)
   '("M" . suderman/meow-line-or-rectangle)
   '("n" . suderman/meow-search)
   '("o" . meow-open-below)
   '("O" . meow-open-above)
   '("p" . suderman/meow-search-backward)
   '("P" . ignore)
   '("q" . meow-quit)
   '("Q" . kill-current-buffer)
   '("r" . suderman/meow-replace-char)
   '("R" . meow-swap-grab)
   (cons "s" surround-keymap)
   '("S" . suderman/speedbar-toggle)
   '("t" . suderman/meow-till)
   '("T" . suderman/meow-till-backward)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("v" . suderman/meow-paste)
   '("V" . meow-page-down)
   '("w" . ignore)
   '("W" . ignore)
   '("x" . suderman/meow-kill)
   '("X" . suderman/meow-kill-line)
   '("y" . undo-redo)
   '("Y" . meow-sync-grab)
   '("z" . meow-pop-selection)
   '("Z" . suderman/meow-buffer-end)
   '("'" . ignore)
   '("/" . meow-visit)
   '("<escape>" . meow-cancel-selection)))

(use-package evil-matchit
  :commands evilmi-jump-items-native)

(use-package move-text
  :commands (move-text-up move-text-down))

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
        '((conf-mode . normal)
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
          (vterm-mode . insert)))
  :config
  (suderman/meow-reset-leader-map)
  (suderman/meow-setup-qwerty)
  (meow-global-mode 1))

(provide 'suderman-meow)
;;; suderman-meow.el ends here
