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

(defun suderman/meow-find (n char)
  "Find CHAR like Meow, extending an active selection."
  (interactive "p\ncFind: ")
  (let ((selecting (region-active-p)))
    (meow-find n char t)
    (suderman/meow--finish-find-motion selecting)))

(defun suderman/meow-till (n char)
  "Move till CHAR like Meow, extending an active selection."
  (interactive "p\ncTill: ")
  (let ((selecting (region-active-p)))
    (meow-till n char t)
    (suderman/meow--finish-find-motion selecting)))

(defun suderman/meow-find-backward (n char)
  "Find backward to CHAR, extending an active selection."
  (interactive "p\ncFind backward: ")
  (suderman/meow-find (- n) char))

(defun suderman/meow-till-backward (n char)
  "Move backward till CHAR, extending an active selection."
  (interactive "p\ncTill backward: ")
  (suderman/meow-till (- n) char))

(defun suderman/meow-search (arg)
  "Search like Meow, leaving an expandable character selection."
  (interactive "P")
  (meow-search arg)
  (when (region-active-p)
    (suderman/meow--select-to (point))))

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

(defun suderman/meow-page-down ()
  "Cancel the selection and scroll down without replaying `C-v'."
  (interactive)
  (meow--cancel-selection)
  (call-interactively #'scroll-up-command))

;;;; Editing

(defun suderman/meow--shift-selection (columns)
  "Shift every line touched by the active selection by COLUMNS."
  (unless (region-active-p)
    (user-error "No active selection"))
  (let* ((selection-beg (region-beginning))
         (selection-end (region-end))
         (beg (save-excursion
                (goto-char selection-beg)
                (line-beginning-position)))
         (end (if (= selection-beg selection-end)
                  (save-excursion
                    (goto-char selection-end)
                    (line-end-position))
                selection-end)))
    (indent-rigidly beg end columns)
    (setq deactivate-mark nil)))

(defun suderman/meow-indent ()
  "Indent every line touched by the active selection by two columns."
  (interactive)
  (suderman/meow--shift-selection 2))

(defun suderman/meow-outdent ()
  "Outdent every line touched by the active selection by two columns."
  (interactive)
  (suderman/meow--shift-selection -2))

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

(defun suderman/meow-delete ()
  "Delete selection, or one character forward.
Deleted text is not added to the kill ring or clipboard."
  (interactive)
  (if (use-region-p)
      (delete-active-region)
    (unless (eobp)
      (delete-char 1))))

(defun suderman/meow-kill ()
  "Kill selection, or one character forward.
Killed text is added to the kill ring and, if enabled, the clipboard."
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (if (use-region-p)
        (delete-active-region t)
      (unless (eobp)
        (kill-region (point) (1+ (point)))))))

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
    (back-to-indentation)))

;;;; Keymaps and mode activation

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
                   (evilmi-jump-items-native . "match")
                   (suderman/meow-find . "find fwd")
                   (suderman/meow-find-backward . "find back")
                   (suderman/meow-indent . "indent")
                   (suderman/meow-insert . "insert")
                   (suderman/meow-insert-at-indentation . "at indent")
                   (suderman/meow-next . "down")
                   (suderman/meow-outdent . "outdent")
                   (suderman/meow-prev . "up")
                   (suderman/meow-search . "search")
                   (suderman/switch-buffer . "buffers")
                   (suderman/meow-join-line . "join line")
                   (suderman/meow-paste . "paste")
                   (suderman/meow-replace-char . "rep char")
                   (suderman/meow-till . "till fwd")
                   (suderman/meow-till-backward . "till back")
                   (suderman/meow-visual . "select")
                   (suderman/meow-next-word . "word fwd")
                   (suderman/meow-next-symbol . "sym fwd")
                   (suderman/meow-kill . "cut")
                   (suderman/meow-kill-line . "cut line")
                   (suderman/meow-save . "copy")
                   (suderman/meow-page-down . "page down")))
    (setf (alist-get (car entry) meow-command-to-short-name-list)
          (cdr entry)))
  
  (meow-motion-define-key
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
   '("%" . evilmi-jump-items-native)
   '("<" . suderman/meow-outdent)
   '(">" . suderman/meow-indent)
   '("," . ignore)
   '("." . ignore)
   '("[" . meow-inner-of-thing)
   '("]" . meow-bounds-of-thing)
   '("{" . meow-beginning-of-thing)
   '("}" . meow-end-of-thing)
   '("\\ \\" . suderman/alternate-buffer)
   '("\\ =" . speedbar)
   '("\\ ]" . speedbar)
   '("a" . suderman/meow-smart-beginning-of-line)
   '("A" . beginning-of-line)
   '("b" . suderman/meow-back-word)
   '("B" . suderman/meow-back-symbol)
   '("c" . meow-change)
   '("d" . suderman/meow-delete)
   '("D" . suderman/meow-delete-line)
   '("e" . suderman/meow-smart-end-of-line)
   '("E" . end-of-line)
   '("f" . suderman/meow-find)
   '("F" . suderman/meow-find-backward)
   '("g" . meow-cancel-selection)
   '("G" . meow-grab)
   '("h" . meow-left)
   '("H" . meow-left-expand)
   '("i" . suderman/meow-insert)
   '("I" . suderman/meow-insert-at-indentation)
   '("j" . suderman/meow-next)
   '("k" . suderman/meow-prev)
   '("K" . suderman/switch-buffer)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("J" . suderman/meow-join-line)
   '("n" . suderman/meow-search)
   '("o" . meow-open-below)
   '("O" . meow-open-above)
   '("p" . suderman/meow-paste)
   '("P" . ignore)
   '("q" . meow-quit)
   '("Q" . meow-goto-line)
   '("r" . suderman/meow-replace-char)
   '("R" . meow-swap-grab)
   '("s" . ignore)
   '("t" . suderman/meow-till)
   '("T" . suderman/meow-till-backward)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("v" . suderman/meow-visual)
   '("V" . meow-line)
   '("C-v" . rectangle-mark-mode)
   '("w" . suderman/meow-next-word)
   '("W" . suderman/meow-next-symbol)
   '("x" . suderman/meow-kill)
   '("X" . suderman/meow-kill-line)
   '("y" . suderman/meow-save)
   '("Y" . meow-sync-grab)
   '("z" . meow-pop-selection)
   '("C-r" . undo-redo)
   '("C-u" . meow-page-up)
   '("C-d" . suderman/meow-page-down)
   '("'" . repeat)
   '("/" . meow-visit)
   '("<escape>" . meow-cancel-selection)))

(use-package evil-matchit
  :commands evilmi-jump-items-native)

(use-package meow
  :demand t
  :init
  (setq meow-use-clipboard t
        ;; Keep Meow editing commands independent from modal key overrides.
        meow--kbd-delete-char #'delete-char
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
