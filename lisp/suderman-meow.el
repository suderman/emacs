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
(declare-function suderman/org-move "suderman-org" (command))
(declare-function suderman/org-goto-adjacent-heading "suderman-org" ())
(declare-function suderman/org-collapse-all "suderman-org" ())
(declare-function meow-insert-exit "meow" ())
(declare-function corfu-quit "corfu" ())
(declare-function meow-keypad-quit "meow-keypad" ())
(declare-function meow--keypad-handle-input-event "meow-keypad" (input-event))
(declare-function which-key--popup-showing-p "which-key" ())
(declare-function outline-on-heading-p "outline" (&optional invisible-ok))
(declare-function outline-invisible-p "outline" (&optional pos))
(declare-function outline-show-entry "outline" (&optional event))
(declare-function outline-show-children "outline" (&optional level))
(declare-function outline-hide-subtree "outline" (&optional event))
(declare-function hs-overlay-at "hideshow" (position))
(declare-function hs-show-block "hideshow" ())
(declare-function hs-get-first-block-on-line "hideshow" (&optional include-comments))
(declare-function hs-hide-block-at-point "hideshow" (&optional comment-reg))
(declare-function which-key--pages-num-pages "which-key" (pages))
(defvar which-key--pages-obj)
(defvar which-key--buffer)

;;;; Keypad

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

(defun suderman/meow-keypad-page-or-key (page)
  "Call PAGE while Which-Key shows several pages, else type the key.
Otherwise the key stays part of the keypad sequence, as in `SPC x <'."
  (if (and (which-key--popup-showing-p)
           which-key--pages-obj
           (> (which-key--pages-num-pages which-key--pages-obj) 1))
      (funcall page)
    (meow--keypad-handle-input-event last-input-event)))

(defun suderman/meow-keypad-next-page-or-key ()
  "Show the next Which-Key page, or type the key when there is one page."
  (interactive)
  (suderman/meow-keypad-page-or-key #'suderman/meow-keypad-next-page))

(defun suderman/meow-keypad-previous-page-or-key ()
  "Show the previous Which-Key page, or type the key when there is one page."
  (interactive)
  (suderman/meow-keypad-page-or-key #'suderman/meow-keypad-previous-page))

(defun suderman/which-key-tag-entry (replace key-binding)
  "Call REPLACE with KEY-BINDING, tagging the shown key with the original.
Replacements can change how a key is shown, so keep the key itself as
`suderman/which-key-key'."
  (let ((result (funcall replace key-binding))
        (key (car-safe key-binding)))
    (if (and (consp result) (stringp key) (stringp (car result)))
        (cons (propertize (car result) 'suderman/which-key-key key)
              (cdr result))
      result)))

(defun suderman/which-key-tag-entries (entries)
  "Spread each of ENTRIES' `suderman/which-key-key' over the whole entry.
ENTRIES are (KEY SEPARATOR DESCRIPTION) strings, so a click anywhere on
one, including a group's \"+\", finds its key."
  (dolist (entry entries entries)
    (when-let* ((key (and (stringp (car entry))
                          (get-text-property 0 'suderman/which-key-key
                                             (car entry)))))
      (setcdr entry (mapcar (lambda (part)
                              (if (stringp part)
                                  (propertize part 'suderman/which-key-key key)
                                part))
                            (cdr entry))))))

(defvar suderman/meow-keypad-read-key-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<mouse-1>" #'ignore)
    (keymap-set map "<mouse-2>" #'ignore)
    map)
  "Keymap `read-key' uses while Meow's keypad waits for a key.
touch-screen.el turns a tap into a click only where a click is bound, and
`read-key' normally hides every binding.")

(defvar suderman/meow-keypad-last-key nil
  "The last event `read-key' returned to Meow's keypad.
For a tap, `last-input-event' is the raw touch event instead.")

(defun suderman/meow-keypad-read-taps (read-key &rest args)
  "Call READ-KEY with ARGS, returning taps as clicks in Meow's keypad.
A tap also selects the window tapped, so select the original again."
  (if (not (bound-and-true-p meow-keypad-mode))
      (apply read-key args)
    (let ((read-key-empty-map suderman/meow-keypad-read-key-map)
          (window (selected-window)))
      (unwind-protect
          (setq suderman/meow-keypad-last-key (apply read-key args))
        (when (and (window-live-p window)
                   (not (eq window (selected-window))))
          (select-window window))))))

(defun suderman/meow-keypad-click ()
  "Type the key of the Which-Key entry under a click, as if pressed.
Meow's keypad popup lists the keys typed at this point, so a click acts
on that entry.  Ignore clicks elsewhere and the press half of a click."
  (interactive)
  (let* ((event suderman/meow-keypad-last-key)
         (posn (event-start event))
         (window (posn-window posn))
         (pos (posn-point posn))
         (key (and (memq (car-safe event) '(mouse-1 mouse-2))
                   (windowp window)
                   (eq (window-buffer window) which-key--buffer)
                   pos
                   (get-text-property pos 'suderman/which-key-key
                                      which-key--buffer)))
         (keys (and key (ignore-errors (key-parse key)))))
    (when (> (length keys) 0)
      (meow--keypad-handle-input-event (aref keys (1- (length keys)))))))

(defun suderman/meow-insert-escape ()
  "Close any completion popup and leave Insert state.
Corfu inserts a previewed candidate before this runs; `C-g' discards it."
  (interactive)
  (when (and (bound-and-true-p completion-in-region-mode) (fboundp 'corfu-quit))
    (corfu-quit))
  (meow-insert-exit))

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
  "Clear an active selection, otherwise run the mode's Return command.
A folded line unfolds first, so the new line is not typed out of sight.
Enter Insert when Return edited the buffer."
  (interactive)
  (if (region-active-p)
      (progn
        (meow--cancel-selection)
        (meow--remove-search-indicator))
    (suderman/meow--toggle-line-fold 'show)
    (let ((command (let ((meow-normal-mode nil))
                     (key-binding (this-command-keys-vector))))
          (tick (buffer-chars-modified-tick)))
      (call-interactively command)
      (when (and (bound-and-true-p meow-normal-mode)
                 (/= tick (buffer-chars-modified-tick)))
        (suderman/meow-insert)))))

(defun suderman/meow--line-hidden-p ()
  "Return non-nil when no text of the line at point shows.
Hidden markup, such as a Markdown heading's leading hashes, leaves the
rest of its line shown."
  (save-excursion
    (forward-line 0)
    (let ((eol (pos-eol)))
      (if (= (point) eol)
          (invisible-p (point))
        (catch 'shown
          (while (< (point) eol)
            (unless (invisible-p (point))
              (throw 'shown nil))
            (goto-char (next-single-char-property-change (point) 'invisible
                                                         nil eol)))
          t)))))

(defun suderman/goto-shown-line-end ()
  "Move from a hidden line to the end of the shown line above it.
A click after a fold's arrow leaves point at the end of the hidden text,
or on a line that starts right after it and so shows on the fold's line."
  (let ((bol (pos-bol))
        (hidden (suderman/meow--line-hidden-p)))
    (when (and (> bol (point-min))
               (or hidden (invisible-p (1- bol))))
      (goto-char (if hidden bol (1- bol)))
      (forward-line 0)
      (while (and (not (bobp)) (suderman/meow--line-hidden-p))
        (forward-line -1))
      (end-of-line))))

(defun suderman/meow--toggle-line-fold (&optional show)
  "Toggle the outline heading or Hideshow block that starts on this line.
With SHOW, only unfold.  Return non-nil when a fold was found."
  (suderman/goto-shown-line-end)
  (cond
   ((and (bound-and-true-p outline-minor-mode) (outline-on-heading-p t))
    (if (outline-invisible-p (pos-eol))
        (progn (outline-show-entry) (outline-show-children))
      (unless show (outline-hide-subtree)))
    t)
   ((not (bound-and-true-p hs-minor-mode)) nil)
   ((hs-overlay-at (pos-eol)) (hs-show-block) t)
   (show nil)
   ((when-let* ((beg (save-excursion
                       (forward-line 0)
                       (hs-get-first-block-on-line))))
      (save-excursion (goto-char beg) (hs-hide-block-at-point))))))

(defun suderman/meow--fold-move (bounce start fold)
  "Move to the line start or end after a fold toggle.
Without BOUNCE, go to the end.  FOLD is `folded' or `open' when the line
folds: go to the start when folded, else the end.  A line that cannot
fold goes to the start only when point stayed at START, the line end."
  (if (and bounce
           (if fold (eq fold 'folded)
             (and (= (point) start) (eolp) (not (bolp)))))
      (back-to-indentation)
    (end-of-line)))

(defun suderman/meow-toggle-fold (&optional bounce)
  "Toggle the fold that starts on this line, then move to the line end.
A line that cannot fold only moves to its end, so this then Return
opens a line below.  With BOUNCE, as from a key, a fold that closes
moves to the line start instead, and on a line that cannot fold a
press at the end moves to the start."
  (interactive (list t))
  (suderman/meow--cancel-active-selection)
  (let ((start (point)))
    (suderman/goto-shown-line-end)
    (let ((moved (/= start (point))))
      (suderman/meow--fold-move
       bounce (if moved -1 start)
       (and (suderman/meow--toggle-line-fold)
            (if (or (and (bound-and-true-p outline-minor-mode)
                         (outline-invisible-p (pos-eol)))
                    (and (bound-and-true-p hs-minor-mode)
                         (hs-overlay-at (pos-eol))))
                'folded
              'open))))))

(defun suderman/meow--hidden-ranges ()
  "Return the hidden ranges of the buffer, merging adjacent ones."
  (let ((pos (point-min)) ranges)
    (while (< pos (point-max))
      (let ((next (next-single-char-property-change pos 'invisible)))
        (when (invisible-p pos)
          (if (and ranges (= (cdar ranges) pos))
              (setcdr (car ranges) next)
            (push (cons pos next) ranges)))
        (setq pos next)))
    ranges))

(defun suderman/meow--hs-hide-all ()
  "Fold every top-level code block.
A lone block holding the whole file, such as a Nix attribute set, stays
open with its own blocks folded, as a lone Org heading does."
  (hs-hide-all)
  (let ((folds (seq-filter (lambda (overlay) (overlay-get overlay 'hs))
                           (overlays-in (point-min) (point-max)))))
    (when (length= folds 1)
      (let ((start (overlay-start (car folds))))
        (hs-show-all)
        (save-excursion
          (goto-char start)
          (forward-line 0)
          (goto-char (hs-get-first-block-on-line))
          (hs-hide-level 1))))))

(defun suderman/meow-fold-all ()
  "Fold the buffer to its top-level headings, or fold every code block.
When everything is already folded that way, open everything instead,
except Org drawers, which open only on request."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (let ((before (suderman/meow--hidden-ranges)))
    (cond
     ((derived-mode-p 'org-mode) (suderman/org-collapse-all))
     ((bound-and-true-p outline-minor-mode) (outline-hide-sublevels 1))
     ((bound-and-true-p hs-minor-mode) (suderman/meow--hs-hide-all))
     (t (user-error "Nothing to fold here")))
    (when (equal before (suderman/meow--hidden-ranges))
      (cond
       ((derived-mode-p 'org-mode)
        (org-fold-show-all '(headings blocks))
        (org-fold-hide-drawer-all))
       ((bound-and-true-p outline-minor-mode) (outline-show-all))
       (t (hs-show-all)))))
  (suderman/goto-shown-line-end))

(defun suderman/org--body-blocks ()
  "Return (BEGIN . TYPE) for each body element of the entry at point.
Planning, drawers, and clocks are skipped; a child heading ends the body."
  (save-excursion
    (let* ((start (if (org-before-first-heading-p)
                      (point-min)
                    (org-back-to-heading t)
                    (forward-line 1)
                    (point)))
           (end (progn (unless (org-at-heading-p) (outline-next-heading))
                       (point)))
           blocks)
      (goto-char start)
      (while (progn (skip-chars-forward " \t\n" end) (< (point) end))
        (let ((element (org-element-at-point)))
          ;; Climb from a nested element to the one directly in the body.
          (while (not (memq (org-element-type (org-element-parent element))
                            '(section org-data nil)))
            (setq element (org-element-parent element)))
          (unless (memq (org-element-type element)
                        '(planning property-drawer drawer clock))
            (push (cons (org-element-begin element) (org-element-type element))
                  blocks))
          (goto-char (org-element-end element))))
      (nreverse blocks))))

(defun suderman/org--step (forward)
  "Move to the next sibling, or previous unless FORWARD.
Headings step among headings and list items among items.  Body text
steps among the entry's body elements, stopping at its edges."
  (cond
   ((org-at-heading-p)
    (if forward (org-forward-heading-same-level 1 t)
      (org-backward-heading-same-level 1 t)))
   ;; Past a list's first or last item, continue through the body.
   ((and (org-in-item-p)
         (ignore-errors (if forward (org-next-item) (org-previous-item)) t)))
   (t (suderman/meow--step-body (suderman/org--body-blocks) forward))))

(defun suderman/meow--step-body (blocks forward)
  "Move to the next of BLOCKS after point, or the previous unless FORWARD.
BLOCKS holds (BEGIN . TYPE) pairs in order.  Stop at the body's edges."
  (let* ((starts (mapcar #'car blocks))
         (target (if forward
                     (seq-find (lambda (pos) (> pos (point))) starts)
                   (seq-find (lambda (pos) (< pos (point))) (reverse starts)))))
    (unless target
      (user-error (if forward "End of heading" "Start of heading")))
    (goto-char target)))

(defun suderman/markdown--node (type)
  "Return the Markdown node of TYPE that contains point, or nil."
  (treesit-parent-until (treesit-node-at (point) 'markdown)
                        (lambda (node) (equal (treesit-node-type node) type))
                        t))

(defun suderman/markdown--body-blocks ()
  "Return (BEGIN . TYPE) for each body element of the heading at point.
Child headings are not part of the body."
  (let ((section (or (suderman/markdown--node "section")
                     (treesit-buffer-root-node 'markdown))))
    (delq nil
          (mapcar (lambda (node)
                    (let ((type (treesit-node-type node)))
                      (unless (member type '("atx_heading" "setext_heading"
                                             "section"))
                        (cons (treesit-node-start node) type))))
                  (treesit-node-children section t)))))

(defun suderman/markdown--step (forward)
  "Move to the next sibling, or previous unless FORWARD.
Like `suderman/org--step', for Markdown's tree-sitter tree."
  (cond
   ((outline-on-heading-p t)
    (if forward (outline-forward-same-level 1)
      (outline-backward-same-level 1)))
   ;; Past a list's first or last item, continue through the body.
   ((when-let* ((item (suderman/markdown--node "list_item"))
                (sibling (if forward (treesit-node-next-sibling item t)
                           (treesit-node-prev-sibling item t))))
      (when (equal (treesit-node-type sibling) "list_item")
        (goto-char (treesit-node-start sibling)))))
   (t (suderman/meow--step-body (suderman/markdown--body-blocks) forward))))

(defun suderman/code--line-indent ()
  "Return the indentation of the line at point if it is navigable.
Blank and hidden lines, lines inside strings, and lines that open with a
closing bracket are skipped."
  (save-excursion
    (back-to-indentation)
    (unless (or (eolp)
                (invisible-p (point))
                (eq (char-syntax (char-after)) ?\))
                (nth 3 (syntax-ppss))
                ;; Tree-sitter knows strings that syntax tables miss, like
                ;; Nix's indented strings.
                (and (fboundp 'treesit-parser-list) (treesit-parser-list)
                     (when-let* ((string (treesit-parent-until
                                          (treesit-node-at (point))
                                          (lambda (node)
                                            (string-match-p
                                             "string" (treesit-node-type node)))
                                          t)))
                       (< (treesit-node-start string) (point)))))
      (current-column))))

(defun suderman/code--indent ()
  "Return the indentation that navigation measures from at point."
  (or (suderman/code--line-indent) (current-indentation)))

(defun suderman/code--find (direction match stop)
  "Move to the next navigable line in DIRECTION whose indentation MATCH accepts.
Give up at a line whose indentation is below STOP.  Return non-nil on success."
  (let (target)
    (save-excursion
      (catch 'done
        (while (and (zerop (forward-line direction)) (not (eobp)))
          (let ((other (suderman/code--line-indent)))
            (cond ((null other))
                  ((funcall match other)
                   (back-to-indentation)
                   (setq target (point))
                   (throw 'done nil))
                  ((< other stop) (throw 'done nil)))))))
    (when target (goto-char target))))

(defun suderman/code--step (forward)
  "Move to the next line at this indentation, or previous unless FORWARD.
Stop where indentation drops below this line."
  (let ((indent (suderman/code--indent)))
    (unless (suderman/code--find (if forward 1 -1)
                                 (lambda (other) (= other indent)) indent)
      (user-error (if forward "No next sibling line" "No previous sibling line")))))

(defun suderman/meow--leave-folded-body ()
  "Move from the hidden end of a folded Org subtree to its heading.
A click after a folded heading lands there; Tab and o do the same."
  (when (derived-mode-p 'org-mode)
    (suderman/org-goto-adjacent-heading)))

(defun suderman/meow-next-block (&optional n)
  "Move to the Nth next sibling block, or previous when N is negative.
Org and Markdown step among headings on a heading, among items in a
list, and among body elements in a heading's body.  Other outlines
move by the heading that contains point, and code by lines at the
same indentation."
  (interactive "p")
  (suderman/meow--cancel-active-selection)
  (suderman/meow--leave-folded-body)
  (let ((n (or n 1)))
    (cond
     ((derived-mode-p 'org-mode)
      (dotimes (_ (abs n))
        (suderman/org--step (> n 0))))
     ((derived-mode-p 'markdown-ts-mode)
      (dotimes (_ (abs n))
        (suderman/markdown--step (> n 0))))
     ((bound-and-true-p outline-minor-mode)
      (if (> n 0) (outline-forward-same-level n)
        (outline-backward-same-level (- n))))
     (t
      (dotimes (_ (abs n))
        (suderman/code--step (> n 0)))))))

(defun suderman/meow-previous-block (&optional n)
  "Move to the Nth previous sibling block."
  (interactive "p")
  (suderman/meow-next-block (- (or n 1))))

(defun suderman/meow-parent-block ()
  "Move to the block that contains point.
Org and Markdown list items go to their parent item or heading; body
text goes to its own heading.  Code goes to the line above with less
indentation."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (suderman/meow--leave-folded-body)
  (cond
   ((and (derived-mode-p 'org-mode) (org-in-item-p))
    (let* ((item (org-in-item-p))
           (struct (save-excursion (goto-char item) (org-list-struct)))
           (parent (org-list-get-parent item struct
                                        (org-list-parents-alist struct))))
      ;; A top-level item skips the plain-list stop `org-up-element' makes.
      (if parent (goto-char parent) (org-back-to-heading t))))
   ((derived-mode-p 'org-mode)
    (org-up-element))
   ((and (derived-mode-p 'markdown-ts-mode)
         (suderman/markdown--node "list_item"))
    (let ((parent (treesit-parent-until
                   (treesit-node-parent (suderman/markdown--node "list_item"))
                   (lambda (node) (equal (treesit-node-type node) "list_item")))))
      (if parent (goto-char (treesit-node-start parent))
        (outline-back-to-heading t))))
   ((bound-and-true-p outline-minor-mode)
    (if (outline-on-heading-p t)
        (outline-up-heading 1)
      (outline-back-to-heading t)))
   (t
    (let ((indent (suderman/code--indent)))
      (unless (suderman/code--find -1 (lambda (other) (< other indent)) 0)
        (user-error "No parent line"))))))

(defun suderman/meow-child-block ()
  "Move to the first child of the block at point, showing it if folded.
Org and Markdown list items go to their first nested item.  Headings
go to their first child heading, or else their first paragraph or list.  Code
goes to the next line when it is indented further, unfolding it first."
  (interactive)
  (suderman/meow--cancel-active-selection)
  (suderman/meow--leave-folded-body)
  (cond
   ((and (derived-mode-p 'org-mode) (org-in-item-p))
    (let* ((item (org-in-item-p))
           (child (org-list-has-child-p
                   item (save-excursion (goto-char item) (org-list-struct)))))
      (unless child (user-error "No nested item"))
      (goto-char child)))
   ((and (derived-mode-p 'org-mode) (org-at-heading-p))
    (org-fold-show-children)
    (unless (org-goto-first-child)
      (let ((text (seq-find (lambda (block)
                              (memq (cdr block) '(paragraph plain-list)))
                            (suderman/org--body-blocks))))
        (unless text (user-error "No child heading or body text"))
        (org-fold-show-entry)
        (goto-char (car text)))))
   ((derived-mode-p 'org-mode)
    (user-error "No child here; { goes up to the heading"))
   ((and (derived-mode-p 'markdown-ts-mode)
         (suderman/markdown--node "list_item"))
    (let ((list (seq-find (lambda (node) (equal (treesit-node-type node) "list"))
                          (treesit-node-children
                           (suderman/markdown--node "list_item") t))))
      (unless list (user-error "No nested item"))
      (goto-char (treesit-node-start (treesit-node-child list 0 t)))))
   ((and (derived-mode-p 'markdown-ts-mode) (not (outline-on-heading-p t)))
    (user-error "No child here; { goes up to the heading"))
   ((bound-and-true-p outline-minor-mode)
    (outline-back-to-heading t)
    (let* ((level (funcall outline-level))
           (heading (save-excursion
                      (outline-next-heading)
                      (and (outline-on-heading-p t)
                           (> (funcall outline-level) level)
                           (point))))
           (text (and (not heading) (derived-mode-p 'markdown-ts-mode)
                      (car (seq-find (lambda (block)
                                       (member (cdr block) '("paragraph" "list")))
                                     (suderman/markdown--body-blocks))))))
      (unless (or heading text) (user-error "No child heading or body text"))
      (if heading (outline-show-children) (outline-show-entry))
      (goto-char (or heading text))))
   (t
    (let ((indent (suderman/code--indent)))
      (suderman/meow--toggle-line-fold t)
      (unless (suderman/code--find 1 (lambda (other) (> other indent))
                                   most-positive-fixnum)
        (user-error "No indented child line"))))))

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
  (let ((selecting (region-active-p)))
    (meow-purrsist-beginning-of-line)
    (unless selecting (suderman/meow-insert))))

(defun suderman/meow-insert-at-end-of-line ()
  "Extend an active selection to smart line end, or insert there."
  (interactive)
  (let ((selecting (region-active-p)))
    (meow-purrsist-end-of-line)
    (unless selecting (suderman/meow-insert))))

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
      (suderman/org-move #'org-metaup)
    (if (use-region-p)
        (suderman/meow--move-selected-lines #'move-text-up)
      (call-interactively #'move-text-up))))

(defun suderman/move-down ()
  "Move the current Org element or ordinary lines downward."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (suderman/org-move #'org-metadown)
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
  "Cut the lines the selection touches, or the current line.
Stay in Normal: whole lines are usually cut to move them, not to type
in their place."
  (interactive)
  (pcase-let ((`(,beg . ,end)
               (if (use-region-p)
                   (let ((beg (region-beginning)) (end (region-end)))
                     (cons (save-excursion (goto-char beg) (pos-bol))
                           (save-excursion
                             (goto-char end)
                             (if (and (bolp) (> end beg)) end (pos-bol 2)))))
                 (suderman/meow--line-bounds))))
    (suderman/meow--cancel-active-selection)
    (let ((select-enable-clipboard meow-use-clipboard))
      (kill-region beg end))
    (goto-char beg)
    (back-to-indentation)))

;;;; Keymaps and mode activation

(use-package surround
  :demand t)

(defun suderman/meow--cheatsheet-command-name (original command)
  "Label Surround's anonymous prefix map, or call ORIGINAL for COMMAND."
  (if (and (keymapp command)
           (eq (lookup-key command (kbd "s")) #'surround-insert)
           (eq (lookup-key command (kbd "d")) #'surround-delete))
      (format "% 9s" "surround")
    (funcall original command)))

(defun suderman/meow-reset-state-keymap (symbol)
  "Restore Meow's stock bindings in the keymap held by SYMBOL.
The first call snapshots the stock map.  Later calls let a reload drop
bindings that were deleted from source."
  (let ((stock (or (get symbol 'suderman/stock-keymap)
                   (put symbol 'suderman/stock-keymap
                        (copy-keymap (symbol-value symbol))))))
    (setcdr (symbol-value symbol) (cdr (copy-keymap stock)))))

(defun suderman/meow-setup-qwerty ()
  "Install Suderman's QWERTY Meow bindings."
  (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
  (setf (alist-get ?h meow-keypad-start-keys) ?h)
  (suderman/meow-reset-state-keymap 'meow-normal-state-keymap)
  (suderman/meow-reset-state-keymap 'meow-motion-state-keymap)

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
   '("$" . meow-purrsist-end-of-line)
   '("%" . evilmi-jump-items-native)
   '("^" . meow-purrsist-beginning-of-line)
   '("(" . meow-left-expand)
   '(")" . meow-right-expand)
   '("," . suderman/ibuffer-toggle)
   '("." . suderman/dirvish)
   '("\\" . suderman/dirvish-side-toggle)
   '("<" . previous-buffer)
   '(">" . next-buffer)
   '("[" . suderman/meow-previous-block)
   '("]" . suderman/meow-next-block)
   '("{" . suderman/meow-parent-block)
   '("}" . suderman/meow-child-block)
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
   '("n" . meow-purrsist-search)
   '("N" . meow-page-down)
   '("o" . suderman/meow-toggle-fold)
   '("O" . meow-open-above)
   '("C-o" . meow-open-below)
   '("p" . meow-purrsist-search-backward)
   '("P" . meow-page-up)
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
   '("Z" . meow-purrsist-end-or-beginning-of-buffer)
   '(";" . meow-purrsist-repeat)
   '("/" . meow-purrsist-isearch)
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
  (when (featurep 'android)
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
    :demand t
    :init
    (setq meow-purrsist-repeat-function #'repeat-fu-execute))
  (advice-add 'meow--show-indicator :override
              #'suderman/meow-show-search-count)
  (advice-add 'meow--remove-search-indicator :after
              #'suderman/meow-clear-search-count)
  (doom-modeline-def-segment suderman-meow-search
    "Show Meow's search match count without changing buffer layout."
    (when (bound-and-true-p suderman/meow-search-count)
      (propertize suderman/meow-search-count 'face 'meow-search-indicator)))
  (doom-modeline-remove-segment 'suderman-meow-search)
  (doom-modeline-add-segment 'suderman-meow-search 'matches :after)
  (meow-purrsist-mode 1)
  (advice-add 'meow--short-command-name :around
              #'suderman/meow--cheatsheet-command-name)
  (add-hook 'meow-mode-hook
            #'suderman/android-initialize-meow-text-conversion)
  (add-hook 'meow-switch-state-hook
            #'suderman/android-meow-text-conversion)
  (suderman/meow-setup-qwerty)
  (keymap-set meow-insert-state-keymap "<escape>" #'suderman/meow-insert-escape)
  (keymap-set meow-keypad-state-keymap "<right>"
              #'suderman/meow-keypad-next-page)
  (keymap-set meow-keypad-state-keymap "<down>"
              #'suderman/meow-keypad-next-page)
  (keymap-set meow-keypad-state-keymap "<left>"
              #'suderman/meow-keypad-previous-page)
  (keymap-set meow-keypad-state-keymap "<up>"
              #'suderman/meow-keypad-previous-page)
  (keymap-set meow-keypad-state-keymap ">"
              #'suderman/meow-keypad-next-page-or-key)
  (keymap-set meow-keypad-state-keymap "<"
              #'suderman/meow-keypad-previous-page-or-key)
  ;; Click a Which-Key entry to type its key.
  (keymap-set meow-keypad-state-keymap "<down-mouse-1>" #'ignore)
  (keymap-set meow-keypad-state-keymap "<mouse-1>" #'suderman/meow-keypad-click)
  ;; A tap on a button, such as a description, arrives as mouse-2.
  (keymap-set meow-keypad-state-keymap "<mouse-2>" #'suderman/meow-keypad-click)
  (advice-add 'read-key :around #'suderman/meow-keypad-read-taps)
  (advice-add 'which-key--maybe-replace :around #'suderman/which-key-tag-entry)
  (advice-add 'which-key--format-and-replace :filter-return
              #'suderman/which-key-tag-entries)
  ;; Toolbar buttons without a keypad key, such as Esc, cancel the keypad.
  (keymap-set meow-keypad-state-keymap "<tool-bar>" #'meow-keypad-quit)
  ;; Enabling it again on reload calls `meow--enable' in every buffer without
  ;; running `meow-mode-hook', so views that keep Meow off get a state.
  (unless (bound-and-true-p meow-global-mode)
    (meow-global-mode 1))
  (suderman/android-initialize-meow-text-conversion))

(provide 'suderman-meow)
;;; suderman-meow.el ends here
