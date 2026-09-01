;;; suderman-dashboard-test.el --- Focused Dashboard checks -*- lexical-binding: t; -*-

;; Run with:
;; emacs --batch -l init.el -l test/suderman-dashboard-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'ert)
(require 'suderman-dashboard)

(ert-deftest suderman/dashboard-has-only-requested-sections ()
  (should (equal dashboard-items '((projects . 5) (recents . 5))))
  (should (eq dashboard-projects-backend 'project-el))
  (should (eq dashboard-projects-switch-function #'suderman/dirvish))
  (should (eq initial-buffer-choice #'dashboard-open))
  (should (commandp #'suderman/dashboard)))

(ert-deftest suderman/dashboard-closes-full-frame-dirvish-first ()
  (let ((session (make-dirvish :curr-layout t))
        calls)
    (cl-letf (((symbol-function 'dirvish-curr) (lambda () session))
              ((symbol-function 'dirvish-quit)
               (lambda () (push 'quit calls)))
              ((symbol-function 'dashboard-open)
               (lambda () (push 'open calls))))
      (suderman/dashboard))
    (should (equal (nreverse calls) '(quit open)))))

(ert-deftest suderman/dashboard-destinations-use-dirvish ()
  (let ((buttons (car dashboard-navigator-buttons))
        destinations)
    (should
     (equal (mapcar (lambda (button)
                      (substring-no-properties (car button)))
                    buttons)
            (mapcar #'substring-no-properties
                    (list (nerd-icons-mdicon "nf-md-home")
                          (nerd-icons-sucicon "nf-custom-orgmode")
                          (nerd-icons-mdicon "nf-md-account")
                          (nerd-icons-mdicon "nf-md-briefcase")
                          (nerd-icons-sucicon "nf-custom-emacs")
                          (nerd-icons-mdicon "nf-md-nix")
                          (nerd-icons-mdicon "nf-md-folder_cog")
                          (nerd-icons-mdicon "nf-md-note_edit")))))
    (should (equal (mapcar #'cadr buttons)
                   '("1" "2" "3" "4" "5" "6" "7" "8")))
    (should (equal (mapcar #'caddr buttons)
                   '("Open home directory"
                     "Open Org directory"
                     "Open personal source"
                     "Open work source"
                     "Open Emacs configuration"
                     "Open NixOS configuration"
                     "Open config directory"
                     "Open scratch buffer")))
    (cl-letf (((symbol-function 'suderman/dirvish)
                (lambda (&optional path)
                  (push path destinations)))
              ((symbol-function 'scratch-buffer)
               (lambda () (push 'scratch destinations))))
      (dotimes (index 8)
        (suderman/dashboard-open-destination index)))
    (should (equal (nreverse destinations)
                   (list "~/"
                         "~/org/"
                         "~/src/suderman/"
                         "~/src/nonfiction/"
                         user-emacs-directory
                         "/etc/nixos/"
                         "~/.config/"
                         'scratch)))))

(ert-deftest suderman/dashboard-uses-native-navigation ()
  (dolist (key '("h" "j" "k" "l"))
    (should (eq (lookup-key dashboard-mode-map (kbd key))
                #'suderman/dashboard-move)))
  (dolist (key '("1" "2" "3" "4" "5" "6" "7" "8"))
    (should (eq (lookup-key dashboard-mode-map (kbd key))
                #'suderman/dashboard-open-destination)))
  (should (eq (lookup-key dashboard-mode-map (kbd "RET"))
              #'dashboard-return))
  (should (eq (lookup-key dashboard-mode-map (kbd "SPC")) #'meow-keypad))
  (should (eq (lookup-key dashboard-mode-map (kbd ","))
              #'suderman/ibuffer-toggle))
  (should (eq (lookup-key dashboard-mode-map (kbd ".")) #'suderman/dirvish))
  (should (eq (lookup-key dashboard-mode-map (kbd "s")) #'scratch-buffer))
  (with-temp-buffer
    (dashboard-mode)
    (should-not (bound-and-true-p meow-mode))
    (should (memq #'suderman/dashboard-disable-meow meow-mode-hook))))

(ert-deftest suderman/dashboard-moves-between-buttons-spatially ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert "  ")
      (widget-create 'push-button :tag "Work" :action #'ignore)
      (insert "        ")
      (widget-create 'push-button :tag "Personal" :action #'ignore)
      (insert "\n\nProjects:\n  ")
      (widget-create 'push-button :tag "Alpha" :action #'ignore)
      (insert "       ")
      (widget-create 'push-button :tag "Beta" :action #'ignore)
      (dashboard-mode)
      (cl-labels ((label ()
                    (substring-no-properties
                     (widget-get (get-char-property (point) 'button) :tag))))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "l"))
        (should (equal (label) "Personal"))
        (execute-kbd-macro (kbd "h"))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "j"))
        (should (equal (label) "Alpha"))
        (execute-kbd-macro (kbd "k"))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "h"))
        (should (equal (label) "Work"))
        (execute-kbd-macro (kbd "k"))
        (should (equal (label) "Work"))))))

(ert-deftest suderman/dashboard-opens-the-rendered-dashboard ()
  (save-window-excursion
    (suderman/dashboard)
    (with-current-buffer (window-buffer)
      (should (derived-mode-p 'dashboard-mode))
      (should-not (bound-and-true-p meow-mode))
      (should (equal (substring-no-properties
                      (widget-get (get-char-property (point) 'button) :tag))
                     (concat (substring-no-properties
                              (nerd-icons-mdicon "nf-md-home"))
                             " 1")))
      (goto-char (point-min))
      (should (search-forward "██████╗██╗" nil t))
      (should (search-forward "╱ emacs" nil t))
      (dolist (icon (mapcar #'substring-no-properties
                            (list (nerd-icons-mdicon "nf-md-home")
                                  (nerd-icons-sucicon "nf-custom-orgmode")
                                  (nerd-icons-mdicon "nf-md-account")
                                  (nerd-icons-mdicon "nf-md-briefcase")
                                  (nerd-icons-sucicon "nf-custom-emacs")
                                  (nerd-icons-mdicon "nf-md-nix")
                                  (nerd-icons-mdicon "nf-md-folder_cog")
                                  (nerd-icons-mdicon "nf-md-note_edit"))))
        (goto-char (point-min))
        (should (search-forward icon nil t)))
      (dolist (heading '("Projects:" "Recent Files:"))
        (goto-char (point-min))
        (should (search-forward heading nil t))))))

(provide 'suderman-dashboard-test)
;;; suderman-dashboard-test.el ends here
