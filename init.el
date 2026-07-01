;;; init.el --- Literate-config bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Tangles `config.org' to `config.el' and loads it with per-top-level-form
;; error isolation.  A failure in one section is recorded and reported, but
;; does NOT abort the rest of startup — so a single broken package can never
;; silently take down everything defined after it.

;;; Code:

(defvar my/config-org (expand-file-name "config.org" user-emacs-directory)
  "Literate configuration source.")

(defvar my/config-el (expand-file-name "config.el" user-emacs-directory)
  "Tangled output that is actually loaded at startup.")

(defvar my/init-errors nil
  "List of (FORM . ERROR) captured while loading the config.")

(defun my/load-config-isolated (file)
  "Load FILE one top-level form at a time, isolating errors.
A failing form is recorded in `my/init-errors' and logged, but the
remaining forms still load.  Returns the number of errors."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((load-file-name file))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (condition-case err
                  (eval form t)
                (error
                 (push (cons form err) my/init-errors)
                 (message "init: error in `%s': %s"
                          (if (consp form) (car form) form)
                          (error-message-string err))))))
        (end-of-file nil))))
  (length my/init-errors))

;; (Re)tangle only when the literate source is newer than its output.
(when (or (not (file-exists-p my/config-el))
          (file-newer-than-file-p my/config-org my/config-el))
  (require 'org)
  (org-babel-tangle-file my/config-org my/config-el))

(my/load-config-isolated my/config-el)

;; Surface any captured failures without blocking startup.
(when my/init-errors
  (with-current-buffer (get-buffer-create "*init-errors*")
    (erase-buffer)
    (insert (format ";; %d error(s) while loading the config:\n\n"
                    (length my/init-errors)))
    (dolist (e (reverse my/init-errors))
      (insert (format "• %s\n    %s\n\n"
                      (if (consp (car e)) (car (car e)) (car e))
                      (error-message-string (cdr e))))))
  (let ((n (length my/init-errors)))
    (run-with-idle-timer
     1 nil
     (lambda ()
       (message "Config loaded with %d error(s) — see the *init-errors* buffer."
                n)))))

;;; init.el ends here
