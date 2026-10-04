;;; suderman-mail.el --- Folder-based Notmuch reading and local drafts -*- lexical-binding: t; -*-

;;; Commentary:
;; IMAP folders remain authoritative.  Notmuch handles search, Maildir flags,
;; and local drafts; mbsync and credentials stay in the NixOS account setup.

;;; Code:

(require 'use-package)
(require 'package)
(require 'message)
(require 'mail-parse)
(require 'wid-edit)
(require 'suderman-mail-moves)
(eval-when-compile (require 'notmuch nil t))

(declare-function notmuch "notmuch")
(declare-function notmuch-unthreaded "notmuch-tree")
(declare-function notmuch-fcc-header-setup "notmuch-maildir-fcc")
(declare-function notmuch-draft--mark-deleted "notmuch-draft")
(declare-function meow--disable "meow")
(declare-function meow-mode "meow")
(declare-function suderman/ibuffer-toggle "suderman-buffers")
(declare-function suderman/dirvish "suderman-files")
(declare-function suderman/meow-escape "suderman-meow")

(defconst suderman/mail-folders
  '("suderman/Inbox" "suderman/Archive" "suderman/Drafts"
    "suderman/Sent" "suderman/Junk" "suderman/Trash"
    "nonfiction/Inbox" "nonfiction/Archive" "nonfiction/Drafts"
    "nonfiction/Sent" "nonfiction/Junk" "nonfiction/Trash")
  "IMAP folders mirrored by the NixOS mbsync accounts.")

(defun suderman/mail ()
  "Open Notmuch's mail overview on a host with the local mail store."
  (interactive)
  (unless (executable-find "notmuch")
    (user-error "Notmuch CLI and local mail store are required on this host"))
  (notmuch))

(defun suderman/mail-folder ()
  "Browse an IMAP folder as individual messages, not whole threads."
  (interactive)
  (notmuch-unthreaded
   (format "folder:\"%s\""
           (completing-read "Mail folder: " suderman/mail-folders nil t))))

(defun suderman/mail-open ()
  "Run the current reader's Return action, including links and MIME buttons."
  (interactive)
  (call-interactively (key-binding (kbd "RET"))))

(defun suderman/mail-overview-escape ()
  "Leave the current overview input field without submitting or clearing it."
  (interactive)
  (if (widget-field-find (point))
      ;; End positions retain typing maps.  Skip adjacent fields as well.
      (while-let ((field (widget-field-find (point))))
        (goto-char (1+ (widget-field-end field))))
    (suderman/meow-escape)))

(defun suderman/mail-overview-field-setup ()
  "Keep Escape available in overview fields without changing global widgets."
  (dolist (field widget-field-list)
    (let ((map (copy-keymap (widget-get field :keymap))))
      (keymap-set map "<escape>" #'suderman/mail-overview-escape)
      (widget-put field :keymap map)
      ;; Fields replace the reader's local map, including at their end boundary.
      (dolist (property '(:field-overlay :field-end-overlay))
        (when-let* ((overlay (widget-get field property)))
          (overlay-put overlay 'local-map map))))))

(defun suderman/mail-sync ()
  "Run account sync services, then g refreshes the view.
Gmail needs a second pass to settle All Mail after Inbox and Trash changes."
  (interactive)
  (async-shell-command
   (concat "systemctl --user start email-suderman.service email-nonfiction.service"
           " && systemctl --user start email-nonfiction.service")
   "*Mail sync*"))

(defun suderman/mail-folder-action-pending ()
  "Explain why thread-wide and bulk folder moves are unavailable."
  (interactive)
  (user-error "Use a single-message row or message view; thread-wide/bulk moves are disabled"))

(defconst suderman/mail-accounts
  '(("jon@suderman.net" :account "suderman"
     :fcc "suderman/Sent -inbox -unread -draft"
     :signature "Jon Suderman\nhttps://suderman.net\n")
    ("jon@nonfiction.ca" :account "nonfiction"
     :fcc nil
     :signature "Jon Suderman\nhttps://www.nonfiction.ca\n"))
  "Sender identities and their existing msmtp accounts.
Fastmail needs a local Sent copy; Gmail creates its own server-side copy.")

(defun suderman/mail-account ()
  "Return settings for the single known mailbox in the From header.
Reject missing, multiple, and unknown senders rather than using msmtp's default."
  (save-excursion
    (save-restriction
      (message-narrow-to-headers)
      (let* ((addresses (mail-header-parse-addresses
                         (or (message-fetch-field "From") "")))
             (account (and (= (length addresses) 1)
                           (assoc-string (caar addresses)
                                         suderman/mail-accounts t))))
        (unless account
          (user-error "From must contain one known sender: jon@suderman.net or jon@nonfiction.ca"))
        (cdr account)))))

(defun suderman/mail-signature ()
  "Choose the initial signature from the compose buffer's From header."
  (plist-get (suderman/mail-account) :signature))

(defun suderman/mail-prepare-send ()
  "Recompute msmtp routing and Fcc from the current From header."
  (let ((account (suderman/mail-account)))
    (setq-local message-sendmail-extra-arguments
                (list (concat "--account=" (plist-get account :account)))
                message-sendmail-envelope-from 'header)
    (save-excursion
      (save-restriction
        (message-narrow-to-headers)
        ;; A saved draft or edited From must not retain stale routing headers.
        (message-remove-header "Fcc")
        (message-remove-header "X-Message-SMTP-Method")))
    (let ((notmuch-fcc-dirs (plist-get account :fcc)))
      (notmuch-fcc-header-setup))))

(defun suderman/mail-mark-sent-draft (&rest _)
  "Retire the saved draft after transport succeeds, before Fcc storage.
A Sent-copy failure must not leave a delivered message ready to resume and send."
  (notmuch-draft--mark-deleted))

(defun suderman/mail-disable-meow ()
  "Let Notmuch's native keys own the current buffer."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/mail-buffer-setup ()
  "Keep Notmuch reader keys usable without Meow's emulation maps."
  (add-hook 'meow-mode-hook #'suderman/mail-disable-meow nil t)
  (suderman/mail-disable-meow)
  (when (eq major-mode 'notmuch-hello-mode)
    (suderman/mail-overview-field-setup)))

(defun suderman/mail-compose-setup ()
  "Set up modal editing, sender signatures, and guarded sending."
  ;; Reader keys own reader buffers, but replies and drafts are text editors.
  (remove-hook 'meow-mode-hook #'suderman/mail-disable-meow t)
  (when (and (bound-and-true-p meow-global-mode)
             (not (bound-and-true-p meow-mode)))
    (meow-mode 1))
  ;; Remove the first slice's blocker from buffers already open during reload.
  (remove-hook 'message-send-hook 'suderman/mail-send-pending t)
  (setq-local message-signature #'suderman/mail-signature
              message-confirm-send t)
  (add-hook 'message-send-hook #'suderman/mail-prepare-send -90 t))

;; The stable frontend must match the system CLI, currently Notmuch 0.40.
(add-to-list 'package-archives '("melpa-stable" . "https://stable.melpa.org/packages/"))

(use-package notmuch
  :if (executable-find "notmuch")
  :pin melpa-stable
  :commands (notmuch notmuch-unthreaded notmuch-mua-new-mail)
  :init
  (setq mail-user-agent 'notmuch-user-agent
        notmuch-search-oldest-first nil
        notmuch-show-empty-saved-searches t
        ;; 0.40's window refresh can change the current buffer during composition.
        ;; Refresh explicitly with g instead.
        notmuch-hello-auto-refresh nil
        notmuch-show-text/html-blocked-images "."
        notmuch-archive-tags nil
        notmuch-identities '("Jon Suderman <jon@suderman.net>"
                             "Jon Suderman <jon@nonfiction.ca>")
        notmuch-always-prompt-for-sender t
        notmuch-draft-folder "drafts"
        notmuch-draft-tags '("+draft" "-inbox" "-unread")
        notmuch-draft-quoted-tags nil
        message-send-mail-function #'message-send-mail-with-sendmail
        sendmail-program "msmtp"
        message-sendmail-envelope-from 'header
        notmuch-fcc-dirs
        (mapcar (lambda (account)
                  (cons (regexp-quote (car account))
                        (plist-get (cdr account) :fcc)))
                suderman/mail-accounts)
        notmuch-tagging-keys '(("r" ("-unread") "Read")
                              ("u" ("+unread") "Unread")
                              ("f" ("+flagged") "Star")
                              ("F" ("-flagged") "Unstar"))
        notmuch-saved-searches
        '((:name "Personal inbox" :query "folder:suderman/Inbox"
           :key "i" :search-type unthreaded)
          (:name "Work inbox" :query "folder:nonfiction/Inbox"
           :key "w" :search-type unthreaded)
          (:name "Unread inboxes"
           :query "(folder:suderman/Inbox or folder:nonfiction/Inbox) and tag:unread"
           :key "u" :search-type unthreaded)
          (:name "Stars" :query "tag:flagged" :key "f" :search-type unthreaded)
          (:name "Local drafts" :query "folder:drafts and tag:draft and not tag:deleted"
           :key "d" :search-type unthreaded)
          (:name "Sent" :query "folder:suderman/Sent or folder:nonfiction/Sent"
           :key "s" :search-type unthreaded))
        notmuch-hello-sections
        '(notmuch-hello-insert-header
          notmuch-hello-insert-saved-searches
          (notmuch-hello-insert-searches "IMAP folders"
           ((:name "Personal archive" :query "folder:suderman/Archive"
             :search-type unthreaded :excluded show)
            (:name "Personal drafts" :query "folder:suderman/Drafts"
             :search-type unthreaded :excluded show)
            (:name "Personal junk" :query "folder:suderman/Junk"
             :search-type unthreaded :excluded show)
            (:name "Personal trash" :query "folder:suderman/Trash"
             :search-type unthreaded :excluded show)
            (:name "Work archive" :query "folder:nonfiction/Archive"
             :search-type unthreaded :excluded show)
            (:name "Work drafts" :query "folder:nonfiction/Drafts"
             :search-type unthreaded :excluded show)
            (:name "Work junk" :query "folder:nonfiction/Junk"
             :search-type unthreaded :excluded show)
            (:name "Work trash" :query "folder:nonfiction/Trash"
             :search-type unthreaded :excluded show))
           :show-empty-searches t :disable-excludes t)
          notmuch-hello-insert-search
          notmuch-hello-insert-recent-searches))
  :config
  (dolist (hook '(notmuch-hello-mode-hook notmuch-search-mode-hook
                  notmuch-tree-mode-hook notmuch-show-mode-hook))
    (add-hook hook #'suderman/mail-buffer-setup))
  (add-hook 'notmuch-hello-refresh-hook #'suderman/mail-overview-field-setup)
  (add-hook 'notmuch-message-mode-hook #'suderman/mail-compose-setup)
  (remove-hook 'notmuch-mua-send-hook 'suderman/mail-send-pending)
  (add-hook 'notmuch-mua-send-hook #'suderman/mail-prepare-send -90)
  ;; Native Notmuch hides drafts before SMTP.  Wait for successful transport.
  (remove-hook 'message-send-hook #'notmuch-draft--mark-deleted)
  (advice-add 'message-send-mail :after #'suderman/mail-mark-sent-draft)
  (keymap-set notmuch-common-keymap "G" #'suderman/mail-sync)
  (keymap-set notmuch-common-keymap "J" #'notmuch-jump-search)
  (keymap-set notmuch-common-keymap "O" #'suderman/mail-folder)
  (keymap-set notmuch-common-keymap "C-SPC" #'meow-keypad)
  (dolist (map (list notmuch-hello-mode-map notmuch-search-mode-map
                    notmuch-tree-mode-map notmuch-show-mode-map))
    (keymap-set map "SPC" #'meow-keypad)
    (keymap-set map "," #'suderman/ibuffer-toggle)
    (keymap-set map "." #'suderman/dirvish)
    (keymap-set map "h" #'notmuch-bury-or-kill-this-buffer)
    (keymap-set map "l" #'suderman/mail-open))
  (keymap-set notmuch-tree-mode-map "h" #'notmuch-tree-quit)
  (keymap-set notmuch-hello-mode-map "/" #'notmuch-unthreaded)
  (keymap-set notmuch-search-mode-map "/" #'notmuch-search-filter)
  (keymap-set notmuch-tree-mode-map "/" #'notmuch-tree-filter)
  (keymap-set notmuch-show-mode-map "/" #'notmuch-show-filter-thread)
  ;; Preserve reader paging and displaced header/part commands away from SPC/h/.
  (keymap-set notmuch-search-mode-map "C-v" #'notmuch-search-scroll-up)
  (keymap-set notmuch-tree-mode-map "C-v" #'notmuch-tree-scroll-or-next)
  (keymap-set notmuch-show-mode-map "C-v" #'notmuch-show-advance)
  (keymap-set notmuch-show-mode-map "H" #'notmuch-show-toggle-visibility-headers)
  (keymap-set notmuch-show-mode-map "C-c ." #'notmuch-show-part-map)
  (keymap-set notmuch-hello-mode-map "<escape>" #'suderman/mail-overview-escape)
  (keymap-set notmuch-hello-mode-map "j" #'widget-forward)
  (keymap-set notmuch-hello-mode-map "k" #'widget-backward)
  (keymap-set notmuch-search-mode-map "j" #'notmuch-search-next-thread)
  (keymap-set notmuch-search-mode-map "k" #'notmuch-search-previous-thread)
  (keymap-set notmuch-tree-mode-map "j" #'notmuch-tree-next-matching-message)
  (keymap-set notmuch-tree-mode-map "k" #'notmuch-tree-prev-matching-message)
  (keymap-set notmuch-show-mode-map "j" #'next-line)
  (keymap-set notmuch-show-mode-map "k" #'previous-line)
  (dolist (map (list notmuch-search-mode-map notmuch-tree-mode-map
                    notmuch-show-mode-map))
    (keymap-set map "t" #'notmuch-tag-jump)
    (dolist (key '("a" "A" "x" "X"))
      (keymap-set map key #'suderman/mail-folder-action-pending)))
  (dolist (map (list notmuch-tree-mode-map notmuch-show-mode-map))
    (keymap-set map "a" #'suderman/mail-archive)
    (keymap-set map "x" #'suderman/mail-trash))
  ;; Apply hooks to already-open buffers after a hot reload.
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (cond
       ((derived-mode-p 'notmuch-message-mode) (suderman/mail-compose-setup))
       ((memq major-mode '(notmuch-hello-mode notmuch-search-mode
                           notmuch-tree-mode notmuch-show-mode))
        (suderman/mail-buffer-setup))))))

(provide 'suderman-mail)
;;; suderman-mail.el ends here
