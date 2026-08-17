;;; suderman-meow.el --- Meow modal editing setup -*- lexical-binding: t; -*-

;;; Commentary:
;; Meow gives modal editing while leaving vanilla Emacs keymaps available through
;; its keypad.  Keep the upstream QWERTY layout recognizable, then layer only the
;; personal behavior that belongs to the modal core.

;;; Code:

(require 'subr-x)
(require 'use-package)

(defvar suderman/meow-leader-map (make-sparse-keymap)
  "Owned keymap for Suderman's Meow SPC leader bindings.")

(defun suderman/meow-reset-leader-map ()
  "Reset and install Suderman's owned Meow leader map."
  (setq suderman/meow-leader-map (make-sparse-keymap))
  (when (boundp 'meow-keymap-alist)
    (setf (alist-get 'leader meow-keymap-alist)
          suderman/meow-leader-map))
  suderman/meow-leader-map)

(defun suderman/meow-insert ()
  "Enter insert state at the current point, discarding any selection."
  (interactive)
  (when (region-active-p)
    (meow--cancel-selection))
  (meow-insert))

(defun suderman/meow-delete ()
  "Delete selection, or one character forward.
Deleted text is not added to the kill ring or clipboard."
  (interactive)
  (if (use-region-p)
      (delete-active-region)
    (unless (eobp)
      (delete-forward-char 1))))

(defun suderman/meow-kill ()
  "Kill selection, or one character forward.
Killed text is added to the kill ring and, if enabled, the clipboard."
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (if (use-region-p)
        (delete-active-region t)
      (unless (eobp)
        (kill-region (point) (1+ (point)))))))

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

(defun suderman/meow-next-word (n)
  "Move forward N words, extending the current selection."
  (interactive "p")
  (let ((target
         (save-excursion
           (forward-thing meow-word-thing n)
           (point))))
    (suderman/meow--select-to target)))

(defun suderman/meow-back-word (n)
  "Move backward N words, extending the current selection."
  (interactive "p")
  (let ((target
         (save-excursion
           (forward-thing meow-word-thing (- n))
           (point))))
    (suderman/meow--select-to target)))

(defun suderman/meow-next-symbol (n)
  "Move forward N symbols, extending the current selection."
  (interactive "p")
  (let ((target
         (save-excursion
           (forward-thing meow-symbol-thing n)
           (point))))
    (suderman/meow--select-to target)))

(defun suderman/meow-back-symbol (n)
  "Move backward N symbols, extending the current selection."
  (interactive "p")
  (let ((target
         (save-excursion
           (forward-thing meow-symbol-thing (- n))
           (point))))
    (suderman/meow--select-to target)))
 
(defun suderman/meow-find (n char)
  "Find CHAR like Meow, leaving an expandable character selection."
  (interactive "p\ncFind: ")
  (meow-find n char t)
  (when (region-active-p)
    (suderman/meow--select-to (point))))

(defun suderman/meow-till (n char)
  "Move till CHAR like Meow, leaving an expandable character selection."
  (interactive "p\ncTill: ")
  (meow-till n char t)
  (when (region-active-p)
    (suderman/meow--select-to (point))))

(defun suderman/meow-find-backward (n char)
  "Find backward to CHAR, leaving an expandable character selection."
  (interactive "p\ncFind backward: ")
  (suderman/meow-find (- n) char))

(defun suderman/meow-till-backward (n char)
  "Move backward till CHAR, leaving an expandable character selection."
  (interactive "p\ncTill backward: ")
  (suderman/meow-till (- n) char))

(defun suderman/meow-smart-beginning-of-line ()
  "Select to indentation, or to beginning of line if already there."
  (interactive)
  (let ((target
         (save-excursion
           (let ((origin (point)))
             (back-to-indentation)
             (if (= origin (point))
                 (line-beginning-position)
               (point))))))
    (suderman/meow--select-to target)))

(defun suderman/meow-smart-end-of-line ()
  "Select to end of code, or end of line if already there."
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
    (suderman/meow--select-to target)))

(defun suderman/meow-insert-at-indentation ()
  "Enter Meow insert state at the first non-whitespace character."
  (interactive)
  (back-to-indentation)
  (suderman/meow-insert))

(defun suderman/meow-replace-char (char)
  "Replace the character immediately after point with CHAR."
  (interactive (list (read-char "Replace with: ")))
  (when (region-active-p)
    (meow--cancel-selection))
  (when (eolp)
    (user-error "No character to replace"))
  (delete-char 1)
  (insert-char char)
  (backward-char 1))

(defun suderman/meow-visual ()
  "Start or convert to an expandable character selection without moving."
  (interactive)
  (suderman/meow--select-to (point)))

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
      (newline)
      (let ((start (point)))
        (insert-for-yank text)
        ;; Leave point on the pasted line so repeated `p'
        ;; continues pasting below it.
        (goto-char start)
        (back-to-indentation)))

     ;; Characterwise text: paste exactly at point.
     (t
      (insert-for-yank text)))))

(defun suderman/meow-join-line ()
  "Join the current line with the following line, like Vim `J'."
  (interactive)
  (when (region-active-p)
    (meow--cancel-selection))
  (delete-indentation 1))

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
  (when (region-active-p)
    (meow--cancel-selection))
  (pcase-let ((`(,beg . ,end) (suderman/meow--line-bounds)))
    (delete-region beg end)
    (goto-char beg)
    (back-to-indentation)))

(defun suderman/meow-kill-line ()
  "Kill the entire current line, adding it to the kill ring and clipboard."
  (interactive)
  (when (region-active-p)
    (meow--cancel-selection))
  (pcase-let ((`(,beg . ,end) (suderman/meow--line-bounds)))
    (let ((select-enable-clipboard meow-use-clipboard))
      (kill-region beg end))
    (goto-char beg)
    (back-to-indentation)))

(defun suderman/meow-page-down ()
  "Cancel the selection and scroll down without replaying `C-v'."
  (interactive)
  (meow--cancel-selection)
  (call-interactively #'scroll-up-command))

(defun suderman/meow-setup-qwerty ()
  "Install Meow's upstream QWERTY layout with local paste/redo tweaks."
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (meow-motion-define-key
   '("j" . meow-next)
   '("k" . meow-prev)
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
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
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
   '("K" . ignore)
   '("m" . meow-mark-word)
   '("M" . meow-mark-symbol)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("J" . suderman/meow-join-line)
   '("n" . meow-search)
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

(use-package meow
  :demand t
  :init
  (setq meow-use-clipboard t
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
