(defvar elpaca-installer-version 0.11)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-repos-directory (expand-file-name "repos/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca--activate-package)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-repos-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
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
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; ── Enable symlink mode for systems that cannot create symlinks ──
(elpaca-no-symlink-mode)

;; ── Install use-package support ──
(elpaca elpaca-use-package
  ;; Enable use-package :ensure support for Elpaca.
  (elpaca-use-package-mode)
  (setq elpaca-use-package-by-default t))

(elpaca-wait)

(require 'cl-lib)

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

;; ── Disable startup distractions ──
(setq inhibit-startup-message t
      use-dialog-box nil
      ring-bell-function 'ignore)

;; ── Clean interface ──
(scroll-bar-mode -1)
(tool-bar-mode -1)
(tooltip-mode -1)
(menu-bar-mode -1)
(set-fringe-mode 10)

;; ── Programming enhancements ──
(add-hook 'prog-mode-hook 'display-line-numbers-mode)
;; (setq display-line-numbers-type 'relative)

;; ── File management ──
(recentf-mode 1)
(save-place-mode 1)
(setq default-directory "~/")

;; ── Auto-revert buffers ──
(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t)

;; ── Warning levels ──
(setq warning-minimum-level :emergency)

;; ── Suppress specific warnings ──
(setq byte-compile-warnings '(cl-functions))

;; ── Environment path integration ──
(use-package exec-path-from-shell
  :ensure t
  :config
  (exec-path-from-shell-initialize))

;; macOS-Specific Configurations
(when (eq system-type 'darwin)
  (setq mac-option-key-is-meta nil
        mac-command-key-is-meta t
        mac-command-modifier 'meta
        mac-option-modifier 'none))

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
  :config
  (load-theme 'ef-night t)
  )

(use-package catppuccin-theme
  ;; :config
  ;; (load-theme 'catppuccin t)
  )

(use-package doom-themes
  :ensure t
  :config
  ;; Enable a Doom theme of your choice
  ;; (load-theme 'doom-one t)   ;; 'doom-one', 'doom-dracula', 'doom-solarized-light', etc.

  ;; ── Enable Doom theme integrations ──
  ;; (doom-themes-visual-bell-config)    ; Flash modeline on errors
  (doom-themes-treemacs-config)          ; Treemacs theme support
  (doom-themes-org-config))              ; Enhanced org-mode faces

(use-package all-the-icons
  :ensure t
  :if (display-graphic-p))

(setq doom-themes-enable-bold t
      doom-themes-enable-italic t
      doom-themes-org-fontify-whole-heading-line t
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
    "c" '(:ignore t :wk "C/C++/Flyspell")
    "c c" '(flyspell-correct-wrapper :wk "Flyspell correct")
    "c f" '(clang-format-buffer :wk "Format buffer")
    "c r" '(clang-format-region :wk "Format region")
    "c m c" '(my/cmake-project-configure :wk "CMake configure")
    "c m b" '(my/cmake-project-build :wk "CMake build")
    "c d" '(disaster :wk "Show assembly"))

  
  (wk/leader-keys
    "d" '(:ignore t :wk "Debug/Describe")
    ;; Debug (DAP) keybindings
    "d d" '(dap-debug :wk "Start debugging")
    "d b" '(dap-breakpoint-toggle :wk "Toggle breakpoint")
    "d c" '(dap-continue :wk "Continue")
    "d n" '(dap-next :wk "Next")
    "d s" '(dap-step-in :wk "Step in")
    "d o" '(dap-step-out :wk "Step out")
    "d r" '(dap-restart-frame :wk "Restart frame")
    "d q" '(dap-disconnect :wk "Disconnect")
    "d e" '(dap-eval :wk "Eval")
    "d u" '(dap-ui-repl :wk "REPL")
    ;; Describe commands
    "d a" '(counsel-apropos :wk "Apropos")
    "d B" '(describe-bindings :wk "Describe bindings")
    "d C" '(describe-char :wk "Describe character under cursor")
    "d D" '(:ignore t :wk "Emacs documentation")
    "d D a" '(about-emacs :wk "About Emacs")
    "d D d" '(view-emacs-debugging :wk "View Emacs debugging")
    "d D f" '(view-emacs-FAQ :wk "View Emacs FAQ")
    "d D m" '(info-emacs-manual :wk "The Emacs manual")
    "d D n" '(view-emacs-news :wk "View Emacs news")
    "d D o" '(describe-distribution :wk "How to obtain Emacs")
    "d D p" '(view-emacs-problems :wk "View Emacs problems")
    "d D t" '(view-emacs-todo :wk "View Emacs todo")
    "d D w" '(describe-no-warranty :wk "Describe no warranty")
    "d E" '(view-echo-area-messages :wk "View echo area messages")
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
    "d R" '(:ignore t :wk "Reload")
    "d R r" '((lambda () (interactive)
                (load-file "~/.config/emacs/init.el"))
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
    "l" '(:ignore t :wk "LSP/LaTeX")
    ;; LSP keybindings
    "l a" '(lsp-execute-code-action :wk "Code action")
    "l r" '(lsp-rename :wk "Rename")
    "l f" '(lsp-format-buffer :wk "Format buffer")
    "l d" '(lsp-find-definition :wk "Find definition")
    "l D" '(lsp-find-declaration :wk "Find declaration")
    "l i" '(lsp-find-implementation :wk "Find implementation")
    "l t" '(lsp-find-type-definition :wk "Find type definition")
    "l R" '(lsp-find-references :wk "Find references")
    "l s" '(lsp-describe-thing-at-point :wk "Describe at point")
    "l h" '(lsp-signature-activate :wk "Signature help")
    "l L" '(lsp-avy-lens :wk "Avy lens")
    "l w r" '(lsp-workspace-restart :wk "Restart workspace")
    "l w s" '(lsp-workspace-shutdown :wk "Shutdown workspace")
    "l e" '(lsp-treemacs-errors-list :wk "Error list")
    "l o" '(lsp-organize-imports :wk "Organize imports")
    ;; LaTeX keybindings
    "l x c" '(my-latex-compile :wk "Compile LaTeX File")
    "l x v" '(my-latex-view :wk "View current latex file's PDF"))

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
    "o e" '(vterm-toggle :which-key "Toggle Shell")
    "o f" '(make-frame :wk "Open buffer in new frame")
    "o F" '(select-frame-by-name :wk "Select frame by name")
    "o p" '(treemacs :wk "Treemacs")
    "o t" '(vterm-toggle :which-key "Toggle Shell"))

  (wk/leader-keys
    "p" '(:ignore t :wk "Python/Projectile")
    ;; Python-specific keybindings
    "p p v" '(pyvenv-activate :wk "Activate venv")
    "p p V" '(pyvenv-deactivate :wk "Deactivate venv")
    "p p t" '(python-pytest :wk "Run pytest")
    "p p f" '(python-black-buffer :wk "Format with Black")
    "p p i" '(py-isort-buffer :wk "Sort imports")
    "p p r" '(run-python :wk "Run Python REPL")
    ;; Projectile commands (kept for backward compatibility)
    "p !" '(projectile-run-shell-command-in-root :wk "Run shell command")
    "p &" '(projectile-run-async-shell-command-in-root :wk "Run async shell command")
    "p a" '(projectile-toggle-between-implementation-and-test :wk "Toggle impl/test")
    "p b" '(projectile-switch-to-buffer :wk "Switch to buffer")
    "p c" '(projectile-compile-project :wk "Compile project")
    "p d" '(projectile-find-dir :wk "Find directory")
    "p D" '(projectile-dired :wk "Dired")
    "p e" '(projectile-recentf :wk "Recent files")
    "p f" '(projectile-find-file :wk "Find file")
    "p g" '(projectile-find-tag :wk "Find tag")
    "p k" '(projectile-kill-buffers :wk "Kill buffers")
    "p p" '(projectile-switch-project :wk "Switch project")
    "p r" '(projectile-replace :wk "Replace")
    "p R" '(projectile-regenerate-tags :wk "Regenerate tags")
    "p s" '(projectile-save-project-buffers :wk "Save project buffers")
    "p t" '(projectile-test-project :wk "Test project"))

  (wk/leader-keys
    "s" '(:ignore t :wk "Search")
    "s d" '(dictionary-search :wk "Search dictionary")
    "s m" '(man :wk "Man pages")
    "s t" '(tldr :wk "Lookup TLDR docs for a command")
    "s w" '(woman :wk "Similar to man but doesn't require man"))

  (wk/leader-keys
    "t" '(:ignore t :wk "Toggle")
    "t f" '(flycheck-mode :wk "Toggle flycheck")
    "t l" '(display-line-numbers-mode :wk "Toggle line numbers")
    "t n" '(neotree-toggle :wk "Toggle neotree file viewer")
    "t o" '(org-mode :wk "Toggle org mode")
    "t r" '(rainbow-mode :wk "Toggle rainbow mode")
    "t t" '(visual-line-mode :wk "Toggle truncated lines"))

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

(use-package corfu
  :custom
  (corfu-auto nil)
  (corfu-cycle t)
  (corfu-preselect-first nil)
  :init
  (global-corfu-mode)
  :bind
  (:map corfu-map
        ("TAB" . corfu-next)
        ("<tab>" . corfu-next)
        ("S-TAB" . corfu-previous)))

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
  (kind-icon-default-face 'corfu-default)
  (kind-icon-blend-background nil)
  (kind-icon-blend-frac 0.08)
  :config
  ;; DO NOT use add-to-list here
  (setq corfu-margin-formatters
        '(kind-icon-margin-formatter corfu-margin-formatter)))

(use-package corfu-doc
  ;; NOTE 2022-02-05: At the time of writing, `corfu-doc' is not yet on melpa
  :ensure (:host github :repo "galeo/corfu-doc")
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

; (setq lsp-use-plists t)
;; (setenv "LSP_USE_PLISTS" "true")
;;
;; (defun lsp-booster--advice-json-parse (old-fn &rest args)
;;   "Try to parse bytecode instead of json."
;;   (or
;;    (when (equal (following-char) ?#)
;;      (let ((bytecode (read (current-buffer))))
;;        (when (byte-code-function-p bytecode)
;;          (funcall bytecode))))
;;    (apply old-fn args)))
;;
;; (advice-add (if (progn (require 'json)
;;                        (fboundp 'json-parse-buffer))
;;                 'json-parse-buffer
;;               'json-read)
;;             :around
;;             #'lsp-booster--advice-json-parse)
;;
;; (defun lsp-booster--advice-final-command (old-fn cmd &optional test?)
;;   "Prepend emacs-lsp-booster command to lsp CMD."
;;   (let ((orig-result (funcall old-fn cmd test?)))
;;     (if (and (not test?)
;;              (not (file-remote-p default-directory))
;;              lsp-use-plists
;;              (not (functionp 'json-rpc-connection))
;;              (executable-find "emacs-lsp-booster"))
;;         (progn
;;           (when-let ((command-from-exec-path (executable-find (car orig-result))))
;;             (setcar orig-result command-from-exec-path))
;;           (message "Using emacs-lsp-booster for %s!" orig-result)
;;           (cons "emacs-lsp-booster" orig-result))
;;       orig-result)))
;;
;; (advice-add 'lsp-resolve-final-command :around #'lsp-booster--advice-final-command)

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :init
  (setq lsp-keymap-prefix "C-c l")  ;; Or 'C-l', 's-l'
  :hook ((python-mode . lsp-deferred)
         (c++-mode . lsp-deferred)
         (c-mode . lsp-deferred)
         (lsp-mode . lsp-enable-which-key-integration))
  :config
  ;; General LSP settings
  (setq lsp-completion-provider :none)  ;; We use Corfu for completion
  (setq lsp-headerline-breadcrumb-enable t)
  (setq lsp-modeline-code-actions-enable t)
  (setq lsp-modeline-diagnostics-enable t)
  (setq lsp-signature-auto-activate t)
  (setq lsp-signature-render-documentation t)
  
  ;; Performance tuning
  (setq lsp-idle-delay 0.5
        lsp-log-io nil                    ;; Disable IO logging for better performance
        read-process-output-max (* 1024 1024)  ;; 1MB - improves LSP performance
        lsp-enable-file-watchers t
        lsp-file-watch-threshold 2000)
  
  ;; UI improvements
  (setq lsp-lens-enable t)
  (setq lsp-semantic-tokens-enable t)
  (setq lsp-enable-indentation t)
  (setq lsp-enable-on-type-formatting t)
  
  ;; clangd-specific settings
  (setq lsp-clients-clangd-args
        '("--header-insertion=never"
          "--background-index"
          "--clang-tidy"
          "--completion-style=detailed"
          "--header-insertion-decorators"
          "--all-scopes-completion"
          "--cross-file-rename"
          "--function-arg-placeholders"
          "--fallback-style=llvm"
          "-j=4"
          "--pch-storage=memory")))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :hook (lsp-mode . lsp-ui-mode)
  :config
  ;; LSP UI Sideline
  (setq lsp-ui-sideline-enable t)
  (setq lsp-ui-sideline-show-hover nil)
  (setq lsp-ui-sideline-show-diagnostics t)
  (setq lsp-ui-sideline-show-code-actions t)
  (setq lsp-ui-sideline-update-mode 'line)
  
  ;; LSP UI Doc
  (setq lsp-ui-doc-enable t)
  (setq lsp-ui-doc-position 'at-point)
  (setq lsp-ui-doc-show-with-cursor t)
  (setq lsp-ui-doc-show-with-mouse t)
  (setq lsp-ui-doc-delay 0.5)
  
  ;; LSP UI Peek
  (setq lsp-ui-peek-enable t)
  (setq lsp-ui-peek-show-directory t)
  
  ;; LSP UI Imenu
  (setq lsp-ui-imenu-enable t)
  (setq lsp-ui-imenu-kind-position 'top))

(use-package lsp-treemacs
  :after (lsp-mode treemacs)
  :commands lsp-treemacs-errors-list
  :config
  (lsp-treemacs-sync-mode 1))

;; Treemacs icons integration
(use-package treemacs-all-the-icons
  :after treemacs)

;; Consult integration with LSP
(use-package consult-lsp
  :ensure t
  :after (lsp-mode consult)
  :config
  (define-key lsp-mode-map [remap xref-find-apropos] #'consult-lsp-symbols))

;; LSP origami for code folding
(use-package lsp-origami
  :ensure t
  :after lsp-mode
  :hook (lsp-mode . lsp-origami-try-enable))

;; Flycheck integration with LSP
(use-package flycheck
  :ensure t
  :hook (prog-mode . flycheck-mode)
  :config
  (setq flycheck-check-syntax-automatically '(save mode-enabled))
  (setq flycheck-display-errors-delay 0.3))

;; Auto-completion integration
(defun my/lsp-mode-setup-completion ()
  "Configure completion in LSP mode."
  (setf (alist-get 'styles (alist-get 'lsp-capf completion-category-defaults))
        '(flex)))

(add-hook 'lsp-completion-mode-hook #'my/lsp-mode-setup-completion)

;; Python-specific LSP configuration
(use-package lsp-pyright
  :ensure t
  :hook (python-mode . (lambda ()
                         (require 'lsp-pyright)
                         (lsp-deferred)))
  :config
  ;; Pyright settings
  (setq lsp-pyright-auto-import-completions t)
  (setq lsp-pyright-auto-search-paths t)
  (setq lsp-pyright-use-library-code-for-types t)
  (setq lsp-pyright-diagnostic-mode "workspace")
  (setq lsp-pyright-typechecking-mode "basic")  ;; Can be "off", "basic", or "strict"
  (setq lsp-pyright-venv-path nil))  ;; Auto-detect virtualenv

;; Python mode configuration
(use-package python
  :ensure nil
  :mode ("\\.py\\'" . python-mode)
  :config
  ;; Python interpreter settings
  (setq python-shell-interpreter "python3")
  
  ;; Indentation
  (setq python-indent-offset 4)
  (setq python-indent-guess-indent-offset-verbose nil)
  
  ;; Environment detection
  (defun my/python-mode-hook ()
    "Custom Python mode configuration."
    (setq-local fill-column 88)  ;; Black's default line length
    (setq-local tab-width 4))
  
  (add-hook 'python-mode-hook #'my/python-mode-hook))

;; Python environment management
(use-package pyvenv
  :ensure t
  :hook (python-mode . pyvenv-mode)
  :config
  (setq pyvenv-mode-line-indicator '(pyvenv-virtual-env-name ("[venv:" pyvenv-virtual-env-name "] ")))
  
  ;; Auto-activate virtualenv
  (defun my/auto-activate-pyvenv ()
    "Automatically activate Python virtual environment."
    (when-let* ((venv-dir (locate-dominating-file default-directory "venv"))
                (venv-path (expand-file-name "venv" venv-dir)))
      (pyvenv-activate venv-path)))
  
  (add-hook 'python-mode-hook #'my/auto-activate-pyvenv))

;; Python testing support
(use-package python-pytest
  :ensure t
  :after python
  :config
  (setq python-pytest-executable "pytest"))

;; Python formatting with Black
(use-package python-black
  :ensure t
  :after python
  :hook (python-mode . python-black-on-save-mode-enable-dwim)
  :config
  (setq python-black-command "black")
  (setq python-black-extra-args '("--line-length" "88")))

;; Python docstring support
(use-package python-docstring
  :ensure t
  :hook (python-mode . python-docstring-mode))

;; Import sorting with isort
(use-package py-isort
  :ensure t
  :after python
  :hook (python-mode . (lambda ()
                         (add-hook 'before-save-hook #'py-isort-before-save nil t))))

;; Python debugging support
(use-package dap-mode
  :ensure t
  :after lsp-mode
  :config
  (require 'dap-python)
  (setq dap-python-debugger 'debugpy)
  
  ;; Python debug templates
  (dap-register-debug-template "Python :: Run file"
                               (list :type "python"
                                     :args ""
                                     :cwd nil
                                     :request "launch"
                                     :name "Python :: Run file"
                                     :program nil)))

;; C/C++ mode configuration
(use-package cc-mode
  :ensure nil
  :mode (("\\.c\\'" . c-mode)
         ("\\.cpp\\'" . c++-mode)
         ("\\.cc\\'" . c++-mode)
         ("\\.cxx\\'" . c++-mode)
         ("\\.h\\'" . c++-mode)
         ("\\.hpp\\'" . c++-mode)
         ("\\.hxx\\'" . c++-mode))
  :config
  ;; Indentation style
  (setq c-default-style "linux"
        c-basic-offset 4)
  
  ;; Custom C/C++ mode hook
  (defun my/c-c++-mode-hook ()
    "Custom C/C++ mode configuration."
    (setq-local fill-column 120)
    (setq-local tab-width 4)
    (setq-local indent-tabs-mode nil)
    ;; Enable electric behavior
    (c-toggle-electric-state 1)
    (c-toggle-auto-newline 1))
  
  (add-hook 'c-mode-hook #'my/c-c++-mode-hook)
  (add-hook 'c++-mode-hook #'my/c-c++-mode-hook))

;; CMake integration
(use-package cmake-mode
  :ensure t
  :mode (("CMakeLists\\.txt\\'" . cmake-mode)
         ("\\.cmake\\'" . cmake-mode)))

(use-package cmake-font-lock
  :ensure t
  :after cmake-mode
  :hook (cmake-mode . cmake-font-lock-activate))

;; C/C++ formatting with clang-format
(use-package clang-format
  :ensure t
  :after cc-mode
  :config
  (setq clang-format-style "file")  ;; Use .clang-format file
  
  ;; Auto-format on save
  (defun my/clang-format-on-save ()
    "Format C/C++ files with clang-format on save."
    (when (or (eq major-mode 'c-mode)
              (eq major-mode 'c++-mode))
      (clang-format-buffer)))
  
  ;; Uncomment to enable auto-formatting on save
  ;; (add-hook 'before-save-hook #'my/clang-format-on-save)
  )

;; Modern C++ font-lock
(use-package modern-cpp-font-lock
  :ensure t
  :hook (c++-mode . modern-c++-font-lock-mode))

;; CMake build integration
(use-package cmake-project
  :ensure t
  :after cc-mode
  :config
  (defun my/cmake-project-configure ()
    "Configure CMake project."
    (interactive)
    (cmake-project-configure-project))
  
  (defun my/cmake-project-build ()
    "Build CMake project."
    (interactive)
    (cmake-project-build-project)))

;; C/C++ debugging with dap-mode
(use-package dap-mode
  :after lsp-mode
  :config
  (require 'dap-lldb)
  (require 'dap-gdb-lldb)
  
  ;; GDB/LLDB configurations
  (setq dap-lldb-debug-program "lldb-vscode")
  (setq dap-gdb-lldb-path "lldb-vscode")
  
  ;; Debug templates for C++
  (dap-register-debug-template
   "C++ :: Run Configuration"
   (list :type "lldb"
         :request "launch"
         :name "C++ :: Run Configuration"
         :target nil
         :cwd nil))
  
  (dap-register-debug-template
   "C++ :: Attach to Process"
   (list :type "lldb"
         :request "attach"
         :name "C++ :: Attach to Process"
         :pid nil)))

;; Company backend for C/C++ headers
(use-package company-c-headers
  :ensure t
  :after company
  :config
  (add-to-list 'company-backends 'company-c-headers)
  (setq company-c-headers-path-system
        '("/usr/include/"
          "/usr/local/include/"
          "/usr/include/c++/11/")))  ;; Adjust version as needed

;; Disaster: show assembly for C/C++
(use-package disaster
  :ensure t
  :after cc-mode
  :commands disaster)

;; ── LSP Java (Eclipse JDT Language Server) ──
(use-package lsp-java
  :ensure t
  :after lsp-mode
  :config
  ;; ── Java runtime and server settings ──
  (setq lsp-java-server-install-dir (expand-file-name "~/.emacs.d/eclipse.jdt.ls/server/"))
  (setq lsp-java-workspace-dir (expand-file-name "~/.emacs.d/eclipse.jdt.ls/workspace/"))
  
  ;; ── Java version settings ──
  ;; (setq lsp-java-java-path "/path/to/java")  ;; Uncomment and set if needed
  
  ;; ── Code formatting ──
  (setq lsp-java-format-enabled t)
  (setq lsp-java-format-settings-url nil)  ;; Use default formatter
  (setq lsp-java-format-settings-profile nil)
  
  ;; ── Import organization ──
  (setq lsp-java-save-actions-organize-imports t)
  
  ;; ── Code generation ──
  (setq lsp-java-autobuild-enabled t)
  (setq lsp-java-completion-enabled t)
  (setq lsp-java-completion-guess-method-arguments t)
  (setq lsp-java-completion-favorite-static-members
        '("org.junit.Assert.*"
          "org.junit.Assume.*"
          "org.junit.jupiter.api.Assertions.*"
          "org.junit.jupiter.api.Assumptions.*"
          "org.junit.jupiter.api.DynamicContainer.*"
          "org.junit.jupiter.api.DynamicTest.*"
          "org.mockito.Mockito.*"
          "org.mockito.ArgumentMatchers.*"
          "org.mockito.Answers.*"))
  
  ;; ── Maven settings ──
  (setq lsp-java-maven-download-sources t)
  (setq lsp-java-maven-update-snapshots nil)
  
  ;; ── Gradle settings ──
  (setq lsp-java-import-gradle-enabled t)
  (setq lsp-java-import-gradle-wrapper-enabled t)
  (setq lsp-java-import-gradle-version nil)  ;; Auto-detect
  (setq lsp-java-import-gradle-home nil)     ;; Auto-detect
  
  ;; ── Code lens ──
  (setq lsp-java-references-code-lens-enabled t)
  (setq lsp-java-implementations-code-lens-enabled t)
  
  ;; ── Signature help ──
  (setq lsp-java-signature-help-enabled t)
  
  ;; ── Content provider ──
  (setq lsp-java-content-provider-preferred "fernflower"))  ;; Decompiler

;; ── Java mode configuration ──
(add-hook 'java-mode-hook
          (lambda ()
            (lsp-deferred)
            (setq-local tab-width 4)
            (setq-local c-basic-offset 4)
            (setq-local indent-tabs-mode nil)))

;; ── DAP mode for Java debugging ──
(use-package dap-java
  :ensure nil
  :after (lsp-java dap-mode)
  :config
  ;; ── Java debug configurations ──
  (dap-register-debug-template
   "Java :: Run Configuration"
   (list :type "java"
         :request "launch"
         :args ""
         :cwd nil
         :stopOnEntry :json-false
         :host "localhost"
         :request "launch"
         :modulePaths []
         :classPaths nil
         :name "Java :: Run Configuration"
         :projectName nil
         :mainClass nil))
  
  (dap-register-debug-template
   "Java :: Attach to Process"
   (list :type "java"
         :request "attach"
         :hostName "localhost"
         :port 5005
         :name "Java :: Attach to Process")))

;; ── Spring Boot support (optional) ──
(use-package lsp-java-boot
  :ensure nil
  :after lsp-java
  :config
  (lsp-java-boot-lens-mode 1))

;; ── Maven support ──
(use-package mvn
  :ensure t
  :commands (mvn-clean mvn-compile mvn-test))

;; ── Gradle support ──
(use-package gradle-mode
  :ensure t
  :hook (java-mode . gradle-mode)
  :config
  (setq gradle-use-gradlew t))

;; macOS-specific paths and settings for LSP
(when (eq system-type 'darwin)
  ;; Homebrew LLVM paths for Apple Silicon
  (defvar homebrew-llvm-path
    (if (file-directory-p "/opt/homebrew/opt/llvm")
        "/opt/homebrew/opt/llvm"  ;; Apple Silicon
      "/usr/local/opt/llvm"))      ;; Intel Mac
  
  ;; Set clangd executable
  (with-eval-after-load 'lsp-mode
    (setq lsp-clients-clangd-executable
          (expand-file-name "bin/clangd" homebrew-llvm-path)))
  
  ;; Set clang-format executable
  (with-eval-after-load 'clang-format
    (setq clang-format-executable
          (expand-file-name "bin/clang-format" homebrew-llvm-path)))
  
  ;; Python configuration for macOS
  (setq python-shell-interpreter "python3")
  
  ;; macOS system includes for C/C++
  (with-eval-after-load 'company-c-headers
    (setq company-c-headers-path-system
          (append
           ;; Xcode Command Line Tools headers
           '("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include"
             "/Library/Developer/CommandLineTools/usr/include/c++/v1")
           ;; Homebrew includes
           (list (expand-file-name "include" homebrew-llvm-path))
           (if (file-directory-p "/opt/homebrew/include")
               '("/opt/homebrew/include")
             '("/usr/local/include")))))
  
  ;; Performance optimizations for macOS
  (setq lsp-file-watch-threshold 5000)  ;; Higher threshold for macOS
  (setq lsp-enable-file-watchers t)
  
  ;; Use system trash on macOS
  (setq delete-by-moving-to-trash t)
  
  ;; macOS-specific DAP settings
  (with-eval-after-load 'dap-mode
    ;; Find the first available lldb
    (setq dap-lldb-debug-program
          (seq-find #'file-exists-p
                    '("/usr/bin/lldb-vscode"
                      "/opt/homebrew/opt/llvm/bin/lldb-vscode"
                      "/usr/local/opt/llvm/bin/lldb-vscode")))))

(use-package format-all
  :commands format-all-mode
  :hook (prog-mode . format-all-mode)
  :config
  (setq-default format-all-formatters
                '(("C" (clang-format))
                  ("C++" (clang-format))
                  ("Python" (black)))))

;;; ── Visual indentation guides ──
(use-package indent-guide
  :hook (prog-mode . indent-guide-mode)
  :config
  (setq indent-guide-char "│"))

;; (use-package highlight-indent-guides
;;   :ensure t
;;   :hook (prog-mode . highlight-indent-guides-mode)
;;   :config
;;   (setq highlight-indent-guides-method 'character)
;;   (setq highlight-indent-guides-character ?│)
;;   (setq highlight-indent-guides-auto-enabled nil))

;; ── Colorful delimiter pairs ──
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(add-hook 'text-mode-hook 'flyspell-mode)
(add-hook 'prog-mode-hook 'flyspell-prog-mode)

(use-package flyspell-correct
  :after flyspell)

(use-package flyspell-correct-popup
  :after flyspell-correct)

(use-package vterm
  :ensure t)

(use-package vterm-toggle
  :ensure t
  :after vterm
  :config
  (setq vterm-toggle-fullscreen-p nil)
  (add-to-list 'display-buffer-alist
               '((lambda (buffer-or-name _)
                   (let ((buffer (get-buffer buffer-or-name)))
                     (with-current-buffer buffer
                       (or (equal major-mode 'vterm-mode)
                           (string-prefix-p vterm-buffer-name (buffer-name buffer))))))
                 (display-buffer-reuse-window display-buffer-at-bottom)
                 ;;(display-buffer-reuse-window display-buffer-in-direction)
                 ;;display-buffer-in-direction/direction/dedicated is added in emacs27
                 ;;(direction . bottom)
                 ;;(dedicated . t) ;dedicated is supported in emacs27
                 (reusable-frames . visible)
                 (window-height . 0.3))))

(add-to-list 'load-path "~/.config/emacs/manual-packages/")
