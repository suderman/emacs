;;; suderman-mail.el --- Folder-based Notmuch reading and local drafts -*- lexical-binding: t; -*-

;;; Commentary:
;; IMAP folders remain authoritative.  Notmuch handles search, Maildir flags,
;; and local drafts; mbsync and credentials stay in the NixOS account setup.

;;; Code:

(require 'use-package)
(require 'package)
(require 'message)
(eval-when-compile (require 'notmuch nil t))

(declare-function notmuch "notmuch")
(declare-function notmuch-unthreaded "notmuch-tree")
(declare-function meow--disable "meow")
(declare-function meow-mode "meow")

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

(defun suderman/mail-sync ()
  "Run the existing account sync services.  Use g to refresh after they finish."
  (interactive)
  (async-shell-command
   "systemctl --user start email-suderman.service email-nonfiction.service"
   "*Mail sync*"))

(defun suderman/mail-folder-action-pending ()
  "Explain why tag-only archive and delete actions are unavailable."
  (interactive)
  (user-error "Use phone/web for folder moves until Maildir-aware moves are tested"))

(defun suderman/mail-send-pending ()
  "Block sending until msmtp routing and failure recovery are verified."
  (user-error "Sending is not set up yet; C-x C-s saves a local Notmuch draft"))

(defun suderman/mail-disable-meow ()
  "Let Notmuch's native keys own the current buffer."
  (if (bound-and-true-p meow-mode)
      (meow-mode -1)
    (when (fboundp 'meow--disable)
      (meow--disable))))

(defun suderman/mail-buffer-setup ()
  "Keep Notmuch and Message keys usable without Meow's emulation maps."
  (add-hook 'meow-mode-hook #'suderman/mail-disable-meow nil t)
  (suderman/mail-disable-meow))

(defun suderman/mail-compose-setup ()
  "Keep this first mail setup draft-only, including direct Message sends."
  (suderman/mail-buffer-setup)
  ;; Run before Notmuch's send hook, which hides drafts before transport succeeds.
  (add-hook 'message-send-hook #'suderman/mail-send-pending -90 t))

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
        notmuch-show-text/html-blocked-images "."
        notmuch-archive-tags nil
        notmuch-identities '("Jon Suderman <jon@suderman.net>"
                             "Jon Suderman <jon@nonfiction.ca>")
        notmuch-always-prompt-for-sender t
        notmuch-draft-folder "drafts"
        notmuch-draft-tags '("+draft" "-inbox" "-unread")
        notmuch-draft-quoted-tags nil
        ;; Fcc and SMTP belong to the next, transport-tested slice.
        notmuch-fcc-dirs nil
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
  (add-hook 'notmuch-message-mode-hook #'suderman/mail-compose-setup)
  (add-hook 'notmuch-mua-send-hook #'suderman/mail-send-pending)
  (keymap-set notmuch-common-keymap "G" #'suderman/mail-sync)
  (keymap-set notmuch-common-keymap "J" #'notmuch-jump-search)
  (keymap-set notmuch-common-keymap "O" #'suderman/mail-folder)
  (keymap-set notmuch-common-keymap "C-SPC" #'meow-keypad)
  (keymap-set notmuch-hello-mode-map "j" #'widget-forward)
  (keymap-set notmuch-hello-mode-map "k" #'widget-backward)
  (keymap-set notmuch-search-mode-map "j" #'notmuch-search-next-thread)
  (keymap-set notmuch-search-mode-map "k" #'notmuch-search-previous-thread)
  (keymap-set notmuch-tree-mode-map "j" #'notmuch-tree-next-matching-message)
  (keymap-set notmuch-tree-mode-map "k" #'notmuch-tree-prev-matching-message)
  (keymap-set notmuch-show-mode-map "j" #'next-line)
  (keymap-set notmuch-show-mode-map "k" #'previous-line)
  (keymap-set notmuch-show-mode-map "SPC" #'notmuch-show-advance)
  (dolist (map (list notmuch-search-mode-map notmuch-tree-mode-map
                    notmuch-show-mode-map))
    (keymap-set map "t" #'notmuch-tag-jump)
    (dolist (key '("a" "A" "x" "X"))
      (keymap-set map key #'suderman/mail-folder-action-pending)))
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
