(defvar elpaca-installer-version 0.7)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-repos-directory (expand-file-name "repos/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca--activate-package)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-repos-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (< emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                 ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                 ,@(when-let ((depth (plist-get order :depth)))
                                                     (list (format "--depth=%d" depth) "--no-single-branch"))
                                                 ,(plist-get order :repo) ,repo))))
                 ((zerop (call-process "git" nil buffer t "checkout"
                                       (or (plist-get order :ref) "--"))))
                 (emacs (concat invocation-directory invocation-name))
                 ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                       "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                 ((require 'elpaca))
                 ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (load "./elpaca-autoloads")))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; Uncomment for systems which cannot create symlinks:
(elpaca-no-symlink-mode)

;; Install use-package support
(elpaca elpaca-use-package
  ;; Enable use-package :ensure support for Elpaca.
  (elpaca-use-package-mode)
  (setq elpaca-use-package-by-default t))

(cl-defun slot/vc-install (&key (fetcher "github") repo name rev backend)
  "Install a package from a remote if it's not already installed.
This is a thin wrapper around `package-vc-install' in order to
make non-interactive usage more ergonomic.  Takes the following
named arguments:

- FETCHER the remote where to get the package (e.g., \"gitlab\").
  If omitted, this defaults to \"github\".

- REPO should be the name of the repository (e.g.,
  \"slotThe/arXiv-citation\".

- NAME, REV, and BACKEND are as in `package-vc-install' (which
  see)."
  (let* ((url (format "https://www.%s.com/%s" fetcher repo))
         (iname (when name (intern name)))
         (pac-name (or iname (intern (file-name-base repo)))))
    (unless (package-installed-p pac-name)
      (package-vc-install url iname rev backend))))

(setq inhibit-startup-message t)

(setq use-dialog-box nil)

(scroll-bar-mode -1)
(tool-bar-mode -1)
(tooltip-mode -1)
(set-fringe-mode 10)

(menu-bar-mode -1)

(setq ring-bell-function 'ignore)

(add-hook 'prog-mode-hook 'display-line-numbers-mode)
;; (setq display-line-numbers-type 'relative)

(recentf-mode 1)

(setq default-directory "~/")

(setq warning-minimum-level :emergency)

(global-auto-revert-mode 1)

;; Revert Dired and other buffers
(setq global-auto-revert-non-file-buffers t)

(save-place-mode 1)

(use-package exec-path-from-shell
  :ensure t
  :config
  (exec-path-from-shell-initialize))

(delete-selection-mode 1)    ;; You can select text and delete it by typing.
(electric-indent-mode 1)    ;; Turn On/Off the indention that Emacs does by default.

(use-package emacs
  :ensure nil
  :init
  (defalias 'yes-or-no-p 'y-or-n-p))

(setq confirm-kill-emacs 'y-or-n-p)

(use-package emacs
  :ensure nil
  :init
  (defun display-startup-echo-area-message ()
    (message "")))

(use-package ef-themes
  ;; :config
  ;; (load-theme 'ef-bio t)
  )

(use-package catppuccin-theme
  ;; :config
  ;; (load-theme 'catppuccin t)
  )


(use-package doom-themes
  :ensure t
  :config
  ;; Enable a Doom theme of your choice
  (load-theme 'doom-one t)   ;; 'doom-one', 'doom-dracula', 'doom-solarized-light', etc.

  ;; Enable flashing mode-line on errors
  ;; (doom-themes-visual-bell-config)

  ;; Enable custom neotree / treemacs theme
  (doom-themes-treemacs-config)

  ;; Corrects org-mode faces
  (doom-themes-org-config))

(use-package all-the-icons
  :ensure t
  :if (display-graphic-p))

(setq doom-themes-enable-bold t
      doom-themes-enable-italic t)

;; Optional: if using org-mode, improve fontification
(setq doom-themes-org-fontify-whole-heading-line t
      doom-themes-org-agenda-height 1.1)

(use-package general
  :ensure (:wait t)
  :config
  (general-evil-setup)

  ;; set up 'SPC' as the global leader key
  (general-create-definer wk/leader-keys
    :states '(normal insert visual emacs)
    :keymaps 'override
    :prefix "SPC" ;; set leader
    :global-prefix "M-SPC") ;; access leader in insert mode

  (wk/leader-keys
    "SPC" '(execute-extended-command :wk "M-x")
    "RET" '(consult-bookmark :wk "Consult Bookmarks")
    "." '(find-file :wk "Find file")
    "<" '(consult-buffer :wk "Switch to buffer")
    "=" '(perspective-map :wk "Perspective") ;; Lists all the perspective keybindings
    "TAB TAB" '(comment-line :wk "Comment lines")
    "u" '(universal-argument :wk "Universal argument"))

  (wk/leader-keys
    "b" '(:ignore t :wk "Bookmarks/Buffers")
    "b b" '(switch-to-buffer :wk "Switch to buffer")
    "b c" '(clone-indirect-buffer :wk "Create indirect buffer copy in a split")
    "b C" '(clone-indirect-buffer-other-window :wk "Clone indirect buffer in new window")
    "b d" '(bookmark-delete :wk "Delete bookmark")
    "b i" '(ibuffer :wk "Ibuffer")
    "b k" '(kill-current-buffer :wk "Kill current buffer")
    "b K" '(kill-some-buffers :wk "Kill multiple buffers")
    "b l" '(list-bookmarks :wk "List bookmarks")
    "b m" '(bookmark-set :wk "Set bookmark")
    "b n" '(next-buffer :wk "Next buffer")
    "b p" '(previous-buffer :wk "Previous buffer")
    "b r" '(revert-buffer :wk "Reload buffer")
    "b R" '(rename-buffer :wk "Rename buffer")
    "b s" '(basic-save-buffer :wk "Save buffer")
    "b S" '(save-some-buffers :wk "Save multiple buffers")
    "b w" '(bookmark-save :wk "Save current bookmarks to bookmark file"))
  
  (wk/leader-keys
    "c" '(flyspell-correct-wrapper :wk "Flyspell correct wrapper"))

  
  (wk/leader-keys
    "d" '(:ignore t :wk "Describe")
    "d a" '(counsel-apropos :wk "Apropos")
    "d b" '(describe-bindings :wk "Describe bindings")
    "d c" '(describe-char :wk "Describe character under cursor")
    "d d" '(:ignore t :wk "Emacs documentation")
    "d d a" '(about-emacs :wk "About Emacs")
    "d d d" '(view-emacs-debugging :wk "View Emacs debugging")
    "d d f" '(view-emacs-FAQ :wk "View Emacs FAQ")
    "d d m" '(info-emacs-manual :wk "The Emacs manual")
    "d d n" '(view-emacs-news :wk "View Emacs news")
    "d d o" '(describe-distribution :wk "How to obtain Emacs")
    "d d p" '(view-emacs-problems :wk "View Emacs problems")
    "d d t" '(view-emacs-todo :wk "View Emacs todo")
    "d d w" '(describe-no-warranty :wk "Describe no warranty")
    "d e" '(view-echo-area-messages :wk "View echo area messages")
    "d f" '(describe-function :wk "Describe function")
    "d F" '(describe-face :wk "Describe face")
    "d g" '(describe-gnu-project :wk "Describe GNU Project")
    "d i" '(info :wk "Info")
    "d I" '(describe-input-method :wk "Describe input method")
    "d k" '(describe-key :wk "Describe key")
    "d l" '(view-lossage :wk "Display recent keystrokes and the commands run")
    "d L" '(describe-language-environment :wk "Describe language environment")
    "d m" '(describe-mode :wk "Describe mode")
    "d p" '(describe-package :wk "Describe a package")
    "d r" '(:ignore t :wk "Reload")
    "d r r" '((lambda () (interactive)
                (load-file "~/.emacs.d/init.el"))
              :wk "Reload emacs config")
    "d t" '(consult-theme :wk "Load theme")
    "d v" '(describe-variable :wk "Describe variable")
    "d w" '(where-is :wk "Prints keybinding for command if set")
    "d x" '(describe-command :wk "Display full documentation for command"))

  (wk/leader-keys
    "e" '(:ignore t :wk "Evaluate")
    "e b" '(eval-buffer :wk "Evaluate elisp in buffer")
    "e d" '(eval-defun :wk "Evaluate defun containing or after point")
    "e e" '(eval-expression :wk "Evaluate and elisp expression")
    "e l" '(eval-last-sexp :wk "Evaluate elisp expression before point")
    "e r" '(eval-region :wk "Evaluate elisp in region")
    "e R" '(eww-reload :which-key "Reload current page in EWW")
    "e w" '(eww :which-key "EWW emacs web wowser"))

  (wk/leader-keys
    "f" '(:ignore t :wk "Files")
    "f c" '((lambda () (interactive)
              (find-file "~/.config/emacs/config.org"))
            :wk "Open emacs config file")
    "f p" '((lambda () (interactive)
              (dired "~/.config/emacs/"))
            :wk "Open user-emacs-directory in dired")
    "f d" '(find-grep-dired :wk "Search for string in files in DIR")
    "f g" '(consult-grep :wk "Search for string current file")
    "f f" '(find-file :wk "Find file")
    "f i" '((lambda () (interactive)
              (find-file "~/.config/emacs/init.el"))
            :wk "Open emacs init.el")
    "f l" '(consult-locate :wk "Locate a file")
    "f r" '(consult-recent-file :wk "Find recent files")
    "f u" '(sudo-edit-find-file :wk "Sudo find file")
    "f U" '(sudo-edit :wk "Sudo edit file"))

  (wk/leader-keys
    "g" '(:ignore t :wk "Git")
    "g /" '(magit-displatch :wk "Magit dispatch")
    "g ." '(magit-file-displatch :wk "Magit file dispatch")
    "g b" '(magit-branch-checkout :wk "Switch branch")
    "g c" '(:ignore t :wk "Create")
    "g c b" '(magit-branch-and-checkout :wk "Create branch and checkout")
    "g c c" '(magit-commit-create :wk "Create commit")
    "g c f" '(magit-commit-fixup :wk "Create fixup commit")
    "g C" '(magit-clone :wk "Clone repo")
    "g f" '(:ignore t :wk "Find")
    "g f c" '(magit-show-commit :wk "Show commit")
    "g f f" '(magit-find-file :wk "Magit find file")
    "g f g" '(magit-find-git-config-file :wk "Find gitconfig file")
    "g F" '(magit-fetch :wk "Git fetch")
    "g g" '(magit-status :wk "Magit status")
    "g i" '(magit-init :wk "Initialize git repo")
    "g l" '(magit-log-buffer-file :wk "Magit buffer log")
    "g r" '(vc-revert :wk "Git revert file")
    "g s" '(magit-stage-file :wk "Git stage file")
    "g t" '(git-timemachine :wk "Git time machine")
    "g u" '(magit-stage-file :wk "Git unstage file"))
 
  (wk/leader-keys
    "i" '(package-install :wk "Package Installer"))

  (wk/leader-keys
    "l" '(:ignore t :wk "LaTeX")
    "l r" '(my-latex-compile :wk "Complie LaTeX File")
    "l v" '(my-latex-view :wk "View current latex file's PDF"))

  (wk/leader-keys
    "m" '(:ignore t :wk "Org")
    "m a" '(org-agenda :wk "Org agenda")
    "m e" '(org-export-dispatch :wk "Org export dispatch")
    "m i" '(org-toggle-item :wk "Org toggle item")
    "m t" '(org-todo :wk "Org todo")
    "m B" '(org-babel-tangle :wk "Org babel tangle")
    "m T" '(org-todo-list :wk "Org todo list"))

  (wk/leader-keys
    "m b" '(:ignore t :wk "Tables")
    "m b -" '(org-table-insert-hline :wk "Insert hline in table"))

  (wk/leader-keys
    "m d" '(:ignore t :wk "Date/deadline")
    "m d t" '(org-time-stamp :wk "Org time stamp"))

  (wk/leader-keys
    "o" '(:ignore t :wk "Open")
    "o d" '(dashboard-open :wk "Dashboard")
    "o e" '(cmd :which-key "Toggle Shell")
    "o f" '(make-frame :wk "Open buffer in new frame")
    "o F" '(select-frame-by-name :wk "Select frame by name")
    "o p" '(treemacs :wk "Treemacs"))

  ;; projectile-command-map already has a ton of bindings
  ;; set for us, so no need to specify each individually.
  (wk/leader-keys
    "p" '(projectile-command-map :wk "Projectile"))

  (wk/leader-keys
    "s" '(:ignore t :wk "Search")
    "s d" '(dictionary-search :wk "Search dictionary")
    "s m" '(man :wk "Man pages")
    "s t" '(tldr :wk "Lookup TLDR docs for a command")
    "s w" '(woman :wk "Similar to man but doesn't require man"))

  (wk/leader-keys
    "t" '(:ignore t :wk "Toggle")
    "t e" '(eshell-toggle :wk "Toggle eshell")
    "t f" '(flycheck-mode :wk "Toggle flycheck")
    "t l" '(display-line-numbers-mode :wk "Toggle line numbers")
    "t n" '(neotree-toggle :wk "Toggle neotree file viewer")
    "t o" '(org-mode :wk "Toggle org mode")
    "t r" '(rainbow-mode :wk "Toggle rainbow mode")
    "t t" '(visual-line-mode :wk "Toggle truncated lines")
    "t v" '(vterm-toggle :wk "Toggle vterm"))

  (wk/leader-keys
    "w" '(:ignore t :wk "Windows")
    ;; Window splits
    "w c" '(evil-window-delete :wk "Close window")
    "w n" '(evil-window-new :wk "New window")
    "w s" '(evil-window-split :wk "Horizontal split window")
    "w v" '(evil-window-vsplit :wk "Vertical split window")
    ;; Window motions
    "w h" '(evil-window-left :wk "Window left")
    "w j" '(evil-window-down :wk "Window down")
    "w k" '(evil-window-up :wk "Window up")
    "w l" '(evil-window-right :wk "Window right")
    "w w" '(evil-window-next :wk "Goto next window")
    ;; Move Windows
    "w H" '(buf-move-left :wk "Buffer move left")
    "w J" '(buf-move-down :wk "Buffer move down")
    "w K" '(buf-move-up :wk "Buffer move up")
    "w L" '(buf-move-right :wk "Buffer move right"))


  (wk/leader-keys
    "y" '(:ignore t :wk "YASnippets")
    "y n" '(yas-new-snippet :wk "Create new YASnippet"))
  )

(add-to-list 'default-frame-alist '(font . "Menlo-15"))

(add-to-list 'default-frame-alist '(fullscreen . maximized))

;; Make ESC quit prompts
(global-set-key (kbd "<escape>") 'keyboard-escape-quit)

(defun my/minibuffer-custom-keys ()
  "Set custom keybindings for minibuffer."
  (local-set-key (kbd "C-j") 'next-line)
  (local-set-key (kbd "C-k") 'previous-line))

(add-hook 'minibuffer-setup-hook 'my/minibuffer-custom-keys)

(use-package evil
  :init      ;; tweak evil's configuration before loading it
  (setq evil-want-integration t  ;; This is optional since it's already set to t by default.
        evil-want-keybinding nil
        evil-vsplit-window-right t
        evil-split-window-below t
        evil-undo-system 'undo-redo)  ;; Adds vim-like C-r redo functionality
  (evil-mode))

(use-package evil-collection
  :after evil
  :config
  ;; Do not uncomment this unless you want to specify each and every mode
  ;; that evil-collection should works with.  The following line is here
  ;; for documentation purposes in case you need it.
  ;; (setq evil-collection-mode-list '(calendar dashboard dired ediff info magit ibuffer))
  (add-to-list 'evil-collection-mode-list 'help) ;; evilify help mode
  (evil-collection-init))

;; Using RETURN to follow links in Org/Evil
;; Unmap keys in 'evil-maps if not done, (setq org-return-follows-link t) will not work
(with-eval-after-load 'evil-maps
  (define-key evil-motion-state-map (kbd "SPC") nil)
  (define-key evil-motion-state-map (kbd "RET") nil)
  (define-key evil-motion-state-map (kbd "TAB") nil))
;; Setting RETURN key in org-mode to follow links
(setq org-return-follows-link  t)

(use-package evil-surround
  :after evil
  :config (global-evil-surround-mode))

(use-package evil-indent-textobject)

(use-package evil-goggles
  :after evil
  :config
  (evil-goggles-mode)

  ;; optionally use diff-mode's faces; as a result, deleted text
  ;; will be highlighed with `diff-removed` face which is typically
  ;; some red color (as defined by the color theme)
  ;; other faces such as `diff-added` will be used for other actions
  (evil-goggles-use-diff-faces))

(use-package evil-commentary
  :after evil
  :init
  (evil-commentary-mode))

(use-package which-key
  :defer 0
  :diminish which-key-mode
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 1))

(use-package vertico
  :init
  (vertico-mode)
  :config
  (setq vertico-resize nil
        vertico-cycle t
        vertico-scroll-margin 2
        vertico-count 5))

;; Configure directory extension.
(use-package vertico-directory
  :after vertico
  :ensure nil
  ;; More convenient directory navigation commands
  :bind (:map vertico-map
              ("RET" . vertico-directory-enter)
              ("DEL" . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  ;; Tidy shadowed file names
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; (use-package vertico-posframe
;;   :after vertico
;;   :config
;;   (vertico-posframe-mode)
;;   (setq vertico-posframe-min-width 100))

(use-package savehist
  :ensure nil
  :init
  (savehist-mode)
  :config
  (setq history-length 25))

(use-package marginalia
  :bind (:map minibuffer-local-map
              ("M-A" . marginalia-cycle))

  :init
  (marginalia-mode)
  :custom
  ;; (marginalia-align 'right)
  (marginalia-align 'left)
  )

(use-package nerd-icons-completion
  :after (marginalia nerd-icons)
  :hook
  (marginalia-mode . nerd-icons-completion-marginalia-setup)
  :init
  (nerd-icons-completion-mode))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; Auto completion example
(use-package corfu
  :custom
  (corfu-auto t)          ;; Enable auto completion
  ;; (corfu-separator ?_) ;; Set to orderless separator, if not using space
  :bind
  ;; Another key binding can be used, such as S-SPC.
  ;; (:map corfu-map ("M-SPC" . corfu-insert-separator))
  :init
  (global-corfu-mode))

;; Manual completion example
(use-package corfu
  :custom
  ;; (corfu-separator ?_) ;; Set to orderless separator, if not using space
  :bind
  ;; Configure SPC for separator insertion
  (:map corfu-map ("SPC" . corfu-insert-separator))
  :init
  (global-corfu-mode))

;; (use-package corfu
;;   :init
;;   (global-corfu-mode)
;;   (corfu-popupinfo-mode 1)
;;   :custom
;;   (corfu-auto t)
;;   (corfu-auto-delay 0.0)
;;   (corfu-auto-prefix 1)
;;   (corfu-cycle t)
;;   (corfu-scroll-margin 2)
;;   (corfu-popupinfo-delay 0.0)
;;   (corfu-min-width 25)
;;   (corfu-max-width 80)
;;   (corfu-count 10)
;;   (corfu-preview-current nil)
;;   (corfu-quit-no-match 'separator)
;;   (corfu-preselect-first nil)
;;   :config
;;   ;; Ensure corfu is used for all in-region completions
;;   ;; (setq completion-in-region-function #'corfu-completion-in-region)
;;   )

(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (add-to-list 'completion-at-point-functions #'cape-file))

(setq tab-always-indent 'complete)
(setq completion-cycle-threshold 3)
(setq read-extended-command-predicate #'command-completion-default-include-p)

(use-package kind-icon
  :after corfu
  :custom
  (kind-icon-use-icons t)
  (kind-icon-default-face 'corfu-default) ; Have background color be the same as `corfu' face background
  (kind-icon-blend-background nil)  ; Use midpoint color between foreground and background colors ("blended")?
  (kind-icon-blend-frac 0.08)

  ;; NOTE 2022-02-05: `kind-icon' depends `svg-lib' which creates a cache
  ;; directory that defaults to the `user-emacs-directory'. Here, I change that
  ;; directory to a location appropriate to `no-littering' conventions, a
  ;; package which moves directories of other packages to sane locations.
  (svg-lib-icons-dir (no-littering-expand-var-file-name "svg-lib/cache/")) ; Change cache dir
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter) ; Enable `kind-icon'

  ;; Add hook to reset cache so the icon colors match my theme
  ;; NOTE 2022-02-05: This is a hook which resets the cache whenever I switch
  ;; the theme using my custom defined command for switching themes. If I don't
  ;; do this, then the backgound color will remain the same, meaning it will not
  ;; match the background color corresponding to the current theme. Important
  ;; since I have a light theme and dark theme I switch between. This has no
  ;; function unless you use something similar
  (add-hook 'kb/themes-hooks #'(lambda () (interactive) (kind-icon-reset-cache))))

(use-package corfu-doc
  ;; NOTE 2022-02-05: At the time of writing, `corfu-doc' is not yet on melpa
  :straight (corfu-doc :type git :host github :repo "galeo/corfu-doc")
  :after corfu
  :hook (corfu-mode . corfu-doc-mode)
  :general (:keymaps 'corfu-map
                     ;; This is a manual toggle for the documentation popup.
                     [remap corfu-show-documentation] #'corfu-doc-toggle ; Remap the default doc command
                     ;; Scroll in the documentation window
                     "M-n" #'corfu-doc-scroll-up
                     "M-p" #'corfu-doc-scroll-down)
  :custom
  (corfu-doc-delay 0.1)
  (corfu-doc-max-width 70)
  (corfu-doc-max-height 20)

  ;; NOTE 2022-02-05: I've also set this in the `corfu' use-package to be
  ;; extra-safe that this is set when corfu-doc is loaded. I do not want
  ;; documentation shown in both the echo area and in the `corfu-doc' popup.
  (corfu-echo-documentation nil)
  )

(use-package consult
  :config
  (global-set-key (kbd "C-s") 'consult-line))

(setq org-edit-src-content-indentation 0)

(defun custom/org-mode-setup ()
  (org-indent-mode)
  (visual-line-mode 1))

(use-package org
  :ensure nil
  :hook (org-mode . custom/org-mode-setup))

(use-package org-modern
  :hook (org-mode . org-modern-mode))

(use-package toc-org
  :init
  (add-hook 'org-mode-hook 'toc-org-enable)
  (add-hook 'org-mode-hook 'toc-org-insert-toc))

(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (python . t)))

(setq org-confirm-babel-evaluate nil)

(require 'org-tempo)

(add-to-list 'org-structure-template-alist '("el" . "src emacs-lisp"))
(add-to-list 'org-structure-template-alist '("py" . "src python"))
(add-to-list 'org-structure-template-alist '("lc" . "src c"))
(add-to-list 'org-structure-template-alist '("cp" . "src c++"))

(use-package auctex
  :defer t
  :hook (LaTeX-mode . TeX-PDF-mode) ;; always compile to PDF
  :config
  ;; Save automatically before compiling
  (setq TeX-save-query nil)
  ;; Automatically parse for completions
  (setq TeX-auto-save t
        TeX-parse-self t)
  ;; Enable forward/inverse search
  (setq TeX-source-correlate-method 'synctex)
  (add-hook 'LaTeX-mode-hook 'TeX-source-correlate-mode)
  ;; Use PDF Tools to view PDFs inside Emacs
  (setq TeX-view-program-selection '((output-pdf "PDF Tools")))
  ;; Don't prompt for command every time
  (setq TeX-command-default "PDFLaTeX"))

(defun my-latex-compile ()
  "Compile LaTeX without asking for master file."
  (interactive)
  (let ((TeX-master t)) ;; treat current file as master
    (TeX-command "LaTeX" 'TeX-master-file -1)))

(defun my-latex-view ()
  "View compiled PDF."
  (interactive)
  (TeX-view))

(use-package pdf-tools
  :ensure t
  :config
  (pdf-tools-install) ;; automatically sets up pdf-tools
  ;; (setq-default pdf-view-display-size 'fit-page)
  )

(use-package yasnippet
  :hook ((prog-mode text-mode LaTeX-mode latex-mode) . yas-minor-mode)
  :config
  (setq yas-snippet-dirs '("~/.config/doom/snippets/"))
  (yas-reload-all)
  (yas-global-mode 1))

(use-package doom-modeline
  :ensure t
  :init (doom-modeline-mode 1)
  :config
  ;; Optional tweaks to mimic Doom Emacs exactly
  (setq doom-modeline-height 30
        doom-modeline-bar-width 4
        doom-modeline-icon t
        doom-modeline-major-mode-icon t
        doom-modeline-minor-modes nil
        doom-modeline-enable-word-count t
        doom-modeline-buffer-file-name-style 'truncate-except-project
        doom-modeline-vcs-max-length 12
        doom-modeline-env-version t
        doom-modeline-env-enable-python t
        doom-modeline-env-enable-rust t
        doom-modeline-env-enable-go t
        doom-modeline-env-enable-elixir t
        doom-modeline-env-enable-ruby t
        doom-modeline-env-enable-perl t
        doom-modeline-env-enable-javascript t
        doom-modeline-env-enable-php t
        doom-modeline-env-enable-java t
        doom-modeline-env-enable-imenu t
        doom-modeline-major-mode-color-icon t
        doom-modeline-buffer-state-icon t
        doom-modeline-checker-simple-format t
        doom-modeline-indent-info t
	)
  )

(setenv "LSP_USE_PLISTS" "true")

(defun lsp-booster--advice-json-parse (old-fn &rest args)
  "Try to parse bytecode instead of json."
  (or
   (when (equal (following-char) ?#)
     (let ((bytecode (read (current-buffer))))
       (when (byte-code-function-p bytecode)
         (funcall bytecode))))
   (apply old-fn args)))
(advice-add (if (progn (require 'json)
                       (fboundp 'json-parse-buffer))
                'json-parse-buffer
              'json-read)
            :around
            #'lsp-booster--advice-json-parse)

(defun lsp-booster--advice-final-command (old-fn cmd &optional test?)
  "Prepend emacs-lsp-booster command to lsp CMD."
  (let ((orig-result (funcall old-fn cmd test?)))
    (if (and (not test?)                             ;; for check lsp-server-present?
             (not (file-remote-p default-directory)) ;; see lsp-resolve-final-command, it would add extra shell wrapper
             lsp-use-plists
             (not (functionp 'json-rpc-connection))  ;; native json-rpc
             (executable-find "emacs-lsp-booster"))
        (progn
          (when-let ((command-from-exec-path (executable-find (car orig-result))))  ;; resolve command from exec-path (in case not found in $PATH)
            (setcar orig-result command-from-exec-path))
          (message "Using emacs-lsp-booster for %s!" orig-result)
          (cons "emacs-lsp-booster" orig-result))
      orig-result)))
(advice-add 'lsp-resolve-final-command :around #'lsp-booster--advice-final-command)

(use-package lsp-mode
  :hook (c++-mode . lsp-mode)
  :config
  (setq lsp-completion-enable nil))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :config
  (setq lsp-ui-sideline-show-symbol nil
        lsp-ui-sideline-enable t
        lsp-ui-sideline-show-hover nil))

(use-package treemacs-all-the-icons)

(use-package lsp-treemacs)

;; (use-package eglot
;;   :ensure nil
;;   :hook (prog-mode . eglot-ensure))

(use-package format-all
  :commands format-all-mode
  :hook (prog-mode . format-all-mode)
  :config
  (setq-default format-all-formatters
                '(("C++"   (clang-format)))))

(use-package indent-guide
  :hook (prog-mode . indent-guide-mode))


(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(add-hook 'text-mode-hook 'flyspell-mode)
(add-hook 'prog-mode-hook 'flyspell-prog-mode)

(use-package flyspell-correct
  :after flyspell)

(use-package flyspell-correct-popup
  :after flyspell-correct)
