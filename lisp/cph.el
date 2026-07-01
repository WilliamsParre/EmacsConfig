;;; cph.el --- Competitive Programming Helper for Emacs -*- lexical-binding: t; -*-

;; Author: Williams Parre
;; Keywords: competitive programming, tools
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:
;;
;; A local, dependency-free re-implementation of the "Competitive Programming
;; Helper" (CPH) VS Code extension, built to talk to the *Competitive Companion*
;; browser extension:
;;
;;   https://github.com/jmerle/competitive-companion
;;
;; How it works
;; ------------
;; Competitive Companion, when you click its green "+" button on a problem page
;; (Codeforces, AtCoder, LeetCode, CSES, ...), POSTs a small JSON document
;; describing the problem (name, url, time limit, and a list of sample tests) to
;; a handful of localhost ports.  CPH listens on port 27121.  This package runs a
;; tiny HTTP server (bound to 127.0.0.1 only) on those ports, and on receipt:
;;
;;   1. creates a source file from a per-language template,
;;   2. stores the sample tests in a sibling `.cph/<name>.json' file,
;;   3. opens the file and pops a results panel.
;;
;; You then write your solution and press the run key.  CPH compiles once, runs
;; every testcase (feeding the input on stdin, with stderr kept *separate* so
;; your `-DLOCAL' debug prints never cause a false Wrong Answer), enforces the
;; time limit, and renders an AC / WA / TLE / RE / CE verdict per test with a
;; diff of expected vs. received output.
;;
;; Quick start
;; -----------
;;   (add-to-list 'load-path "/path/to/this/dir")
;;   (require 'cph)
;;   (cph-mode 1)            ; start the listener
;;
;; Then in a source buffer:
;;   M-x cph/run-all         ; compile + run all tests
;;   M-x cph/edit-tests      ; add/edit/delete tests by hand
;;   M-x cph/panel           ; source | results split
;;
;; See the keymap suggestions at the bottom of this file.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ansi-color)
(require 'color)

(declare-function evil-define-key* "evil-core")
(declare-function doom-color "doom-themes" (name &optional type))

;;;; ------------------------------------------------------------------------
;;;; Customization
;;;; ------------------------------------------------------------------------

(defgroup cph nil
  "Competitive Programming Helper: Competitive Companion + testcase runner."
  :group 'tools
  :prefix "cph-")

(defcustom cph-ports '(27121 10043 10046)
  "Localhost ports the Competitive Companion listener binds to.
27121 is CPH's port; the others are commonly probed by Competitive
Companion.  Listening on several maximises the chance of a match without
you having to reconfigure the extension."
  :type '(repeat integer)
  :group 'cph)

(defcustom cph-use-current-directory t
  "When non-nil, create received problems in the current working directory.
The \"current working directory\" is the `default-directory' of the buffer
you are looking at when Competitive Companion sends the problem — i.e. the
directory of the Dired buffer or file you currently have focused.  The
source file lands there directly and its sample tests go in a sibling
`.cph/' sub-directory, so testcase clutter never mixes with your sources.

When nil, fall back to `cph-directory'."
  :type 'boolean
  :group 'cph)

(defcustom cph-directory (expand-file-name "~/cp")
  "Fallback root directory under which received problems are created.
Only used when `cph-use-current-directory' is nil."
  :type 'directory
  :group 'cph)

(defcustom cph-group-subdirs nil
  "When non-nil, place each problem in a sub-directory named after its group.
The \"group\" is what Competitive Companion reports as the contest/site,
e.g. \"Codeforces - Round 900\"."
  :type 'boolean
  :group 'cph)

(defcustom cph-default-extension "cpp"
  "File extension (without dot) used for problems received from the browser."
  :type 'string
  :group 'cph)

(defcustom cph-open-on-receive t
  "When non-nil, open the source file as soon as a problem is received."
  :type 'boolean
  :group 'cph)

(defcustom cph-time-limit-factor 3.0
  "Multiplier applied to a problem's judge time limit when running locally.
Your machine is not the judge, so give a little slack before declaring TLE."
  :type 'number
  :group 'cph)

(defcustom cph-default-time-limit 5000
  "Fallback per-test time limit in milliseconds when the problem omits one."
  :type 'integer
  :group 'cph)

(defcustom cph-box-max-lines 14
  "Maximum number of lines shown inside an I/O box before it is truncated."
  :type 'integer
  :group 'cph)

;;;; Toolchain ---------------------------------------------------------------

(defcustom cph-cxx-standard "c++20"
  "C++ standard passed to g++."
  :type 'string :group 'cph)

(defcustom cph-c-standard "c17"
  "C standard passed to gcc."
  :type 'string :group 'cph)

(defcustom cph-build-flags "-Wall -Wextra -Wshadow -O2 -DLOCAL"
  "Extra compiler flags for C/C++ builds."
  :type 'string :group 'cph)

(defcustom cph-cxx-include-dir (expand-file-name "~/.config/cpp/include")
  "Directory added with -I for C++ builds when it exists.
macOS Clang/libc++ lacks GCC's <bits/stdc++.h>; this is where a shim lives."
  :type 'directory :group 'cph)

(defcustom cph-python "python3"
  "Python interpreter used to run Python solutions."
  :type 'string :group 'cph)

(defun cph--cxx-compile (src exe _dir)
  "Return the g++ command list to build SRC into EXE."
  (append (list "g++" (concat "-std=" cph-cxx-standard))
          (split-string cph-build-flags)
          (when (file-directory-p cph-cxx-include-dir)
            (list (concat "-I" cph-cxx-include-dir)))
          (list "-o" exe src)))

(defun cph--c-compile (src exe _dir)
  "Return the gcc command list to build SRC into EXE."
  (append (list "gcc" (concat "-std=" cph-c-standard))
          (split-string cph-build-flags)
          (list "-o" exe src)))

(defvar cph-languages
  `(("cpp" :compile cph--cxx-compile :run (lambda (_s exe _d) (list exe)))
    ("cc"  :compile cph--cxx-compile :run (lambda (_s exe _d) (list exe)))
    ("cxx" :compile cph--cxx-compile :run (lambda (_s exe _d) (list exe)))
    ("c"   :compile cph--c-compile   :run (lambda (_s exe _d) (list exe)))
    ("py"  :compile nil              :run (lambda (s _e _d) (list cph-python s)))
    ("java" :compile (lambda (s _e _d) (list "javac" s))
            :run (lambda (s _e dir) (list "java" "-cp" dir (file-name-base s)))))
  "Per-extension toolchain.
Each entry is (EXT :compile COMPILE :run RUN).  COMPILE is nil (interpreted)
or a function (SRC EXE DIR) -> command list.  RUN is a function
(SRC EXE DIR) -> command list.  EXE is DIR/<basename>.")

;;;; Templates ---------------------------------------------------------------

(defcustom cph-template-files nil
  "Alist of (EXT . FILE) external template files.
When a problem with extension EXT is received and FILE exists, its contents
are used verbatim as the new source — letting you keep your template as a
real, compilable file instead of an inline string in `cph-templates'.  Entries
here take precedence over `cph-templates'.  FILE is run through
`cph--expand-template', so the %{name}, %{date} and %{datetime} tokens are
substituted."
  :type '(alist :key-type string :value-type file)
  :group 'cph)

(defvar cph-templates
  `(("cpp" . ,(concat "#include <bits/stdc++.h>\n"
                      "using namespace std;\n"
                      "\n"
                      "#define all(x) (x).begin(), (x).end()\n"
                      "#define sz(x) (int)(x).size()\n"
                      "using ll = long long;\n"
                      "using pii = pair<int,int>;\n"
                      "\n"
                      "void solve() {\n"
                      "    \n"
                      "}\n"
                      "\n"
                      "int main() {\n"
                      "    ios::sync_with_stdio(false);\n"
                      "    cin.tie(nullptr);\n"
                      "    int t = 1;\n"
                      "    // cin >> t;\n"
                      "    while (t--) solve();\n"
                      "    return 0;\n"
                      "}\n"))
    ("py" . ,(concat "import sys\n"
                     "input = sys.stdin.readline\n"
                     "\n"
                     "def solve():\n"
                     "    pass\n"
                     "\n"
                     "def main():\n"
                     "    t = 1\n"
                     "    # t = int(input())\n"
                     "    for _ in range(t):\n"
                     "        solve()\n"
                     "\n"
                     "if __name__ == \"__main__\":\n"
                     "    main()\n"))
    ("java" . ,(lambda (base)
                 (format (concat "import java.util.*;\nimport java.io.*;\n\n"
                                 "public class %s {\n"
                                 "    public static void main(String[] args) throws IOException {\n"
                                 "        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));\n"
                                 "        \n"
                                 "    }\n}\n")
                         base))))
  "Alist of (EXT . TEMPLATE) for new problems.
TEMPLATE is a string, or a function of the file basename returning a string.")

(defun cph--expand-template (s base)
  "Substitute %{name}, %{date} and %{datetime} tokens in template string S.
BASE is the problem's file basename (used for %{name})."
  (let ((reps `(("%{name}"     . ,base)
                ("%{date}"     . ,(format-time-string "%Y-%m-%d"))
                ("%{datetime}" . ,(format-time-string "%Y-%m-%d %H:%M:%S")))))
    (dolist (r reps s)
      (setq s (replace-regexp-in-string (regexp-quote (car r)) (cdr r) s t t)))))

(defun cph--template-for (ext base)
  "Return the source template for extension EXT and file basename BASE.
A readable file in `cph-template-files' wins; otherwise fall back to
`cph-templates' (a string, or a function of BASE).  The result is run through
`cph--expand-template'."
  (let* ((file (cdr (assoc ext cph-template-files)))
         (raw (if (and file (file-readable-p (expand-file-name file)))
                  (with-temp-buffer
                    (insert-file-contents (expand-file-name file))
                    (buffer-string))
                (let ((tmpl (cdr (assoc ext cph-templates))))
                  (cond ((functionp tmpl) (funcall tmpl base))
                        ((stringp tmpl) tmpl)
                        (t ""))))))
    (cph--expand-template raw base)))

;;;; Faces -------------------------------------------------------------------

(defface cph-ac-face   '((t :foreground "#a6e3a1" :weight bold))
  "Face for an Accepted verdict." :group 'cph)
(defface cph-wa-face   '((t :foreground "#f38ba8" :weight bold))
  "Face for a Wrong Answer verdict." :group 'cph)
(defface cph-tle-face  '((t :foreground "#fab387" :weight bold))
  "Face for a Time Limit Exceeded verdict." :group 'cph)
(defface cph-re-face   '((t :foreground "#cba6f7" :weight bold))
  "Face for a Runtime Error verdict." :group 'cph)
(defface cph-ce-face   '((t :foreground "#f9e2af" :weight bold))
  "Face for a Compile Error verdict." :group 'cph)
(defface cph-header-face '((t :weight bold :height 1.3))
  "Face for the problem title in the results panel." :group 'cph)
(defface cph-label-face '((t :inherit shadow :weight bold))
  "Face for Input/Expected/Received labels." :group 'cph)

;; CPH-JUDGE-style card chrome ------------------------------------------------
;; Each badge uses a same-colour :box to add internal padding, turning the
;; flat highlight into a rounded-looking pill with breathing room.
(defface cph-badge-ac  '((t :background "#a6e3a1" :foreground "#11111b" :weight bold
                            :box (:line-width (5 . 2) :color "#a6e3a1")))
  "Badge for an Accepted/Passed testcase." :group 'cph)
(defface cph-badge-wa  '((t :background "#f38ba8" :foreground "#11111b" :weight bold
                            :box (:line-width (5 . 2) :color "#f38ba8")))
  "Badge for a Failed/Wrong-Answer testcase." :group 'cph)
(defface cph-badge-tle '((t :background "#fab387" :foreground "#11111b" :weight bold
                            :box (:line-width (5 . 2) :color "#fab387")))
  "Badge for a Time-Limit-Exceeded testcase." :group 'cph)
(defface cph-badge-re  '((t :background "#cba6f7" :foreground "#11111b" :weight bold
                            :box (:line-width (5 . 2) :color "#cba6f7")))
  "Badge for a Runtime-Error testcase." :group 'cph)
(defface cph-badge-ce  '((t :background "#f9e2af" :foreground "#11111b" :weight bold
                            :box (:line-width (5 . 2) :color "#f9e2af")))
  "Badge for a Compile-Error testcase." :group 'cph)
(defface cph-badge-run '((t :background "#585b70" :foreground "#cdd6f4" :weight bold
                            :box (:line-width (5 . 2) :color "#585b70")))
  "Badge for a not-yet-finished testcase." :group 'cph)
(defface cph-tc-face   '((t :weight bold :inherit default))
  "Face for the \"TC n\" testcase title." :group 'cph)
(defface cph-box-face  '((t :foreground "#585b70"))
  "Face for the left edge-bar of I/O sections." :group 'cph)
(defface cph-iobox-face '((t :background "#313244"))
  "Background fill for the I/O content blocks (Catppuccin surface0)." :group 'cph)
(defface cph-rule-face '((t :foreground "#313244"))
  "Face for thin horizontal separator rules in the panel." :group 'cph)
(defface cph-button-face
  '((t :box (:line-width (1 . 1) :color "#45475a")
       :foreground "#bac2de" :weight bold))
  "Face for the footer action buttons." :group 'cph)

;;;; Theme adaptation --------------------------------------------------------
;; The defface values above are Catppuccin-Mocha fallbacks.  `cph--refresh-faces'
;; re-derives every colour from whatever theme is active — pulling accents from
;; the standard `default'/`success'/`error'/`warning' faces (styled by every
;; theme) and blending the panel/bar/rule shades from the theme's own fg+bg — so
;; the panel follows theme switches instead of staying Mocha-coloured.

(defun cph--blend (c1 c2 alpha)
  "Blend colour C1 over C2 by ALPHA in [0,1]; return a hex string.
Returns C2 unchanged if either colour cannot be parsed."
  (let ((a (color-name-to-rgb c1))
        (b (color-name-to-rgb c2)))
    (if (and a b)
        (apply #'color-rgb-to-hex
               (append (cl-mapcar (lambda (x y) (+ (* alpha x) (* (- 1.0 alpha) y))) a b)
                       '(2)))
      c2)))

(defun cph--theme-color (doom-key face attr fallback)
  "Resolve a colour from the active theme.
Tries the Doom palette key DOOM-KEY first (for doom-* themes), then FACE's
ATTR attribute (works for any theme), then the literal FALLBACK hex."
  (or (and (fboundp 'doom-color) (ignore-errors (doom-color doom-key)))
      (let ((c (face-attribute face attr nil t)))
        (and (stringp c) c))
      fallback))

(defun cph--refresh-faces (&rest _)
  "Recolour all CPH faces from the current theme.
Added to `enable-theme-functions' so the panel re-themes on every theme load."
  (let* ((bg     (cph--theme-color 'bg     'default :background "#1e1e2e"))
         (fg     (cph--theme-color 'fg     'default :foreground "#cdd6f4"))
         (green  (cph--theme-color 'green  'success :foreground "#a6e3a1"))
         (red    (cph--theme-color 'red    'error   :foreground "#f38ba8"))
         (orange (cph--theme-color 'orange 'warning :foreground "#fab387"))
         (yellow (cph--theme-color 'yellow 'warning :foreground "#f9e2af"))
         (violet (cph--theme-color 'violet 'font-lock-keyword-face :foreground "#cba6f7"))
         (panel  (cph--blend fg bg 0.12))   ; I/O block fill
         (rule   (cph--blend fg bg 0.10))   ; separator rules
         (bar    (cph--blend fg bg 0.32))   ; left edge-bar / neutral chrome
         (btn-bd (cph--blend fg bg 0.26))   ; button border
         (btn-fg (cph--blend fg bg 0.72)))  ; button label
    ;; Verdict foreground faces (left card bar + compile-error text).
    (set-face-attribute 'cph-ac-face  nil :foreground green)
    (set-face-attribute 'cph-wa-face  nil :foreground red)
    (set-face-attribute 'cph-tle-face nil :foreground orange)
    (set-face-attribute 'cph-re-face  nil :foreground violet)
    (set-face-attribute 'cph-ce-face  nil :foreground yellow)
    ;; Verdict pill badges: accent background, theme-bg text, matching :box pad.
    (pcase-dolist (`(,face . ,color) `((cph-badge-ac  . ,green)
                                       (cph-badge-wa  . ,red)
                                       (cph-badge-tle . ,orange)
                                       (cph-badge-re  . ,violet)
                                       (cph-badge-ce  . ,yellow)))
      (set-face-attribute face nil :background color :foreground bg
                          :box `(:line-width (5 . 2) :color ,color)))
    (set-face-attribute 'cph-badge-run nil :background bar :foreground fg
                        :box `(:line-width (5 . 2) :color ,bar))
    ;; Chrome derived from the theme's own fg/bg.
    (set-face-attribute 'cph-iobox-face  nil :background panel)
    (set-face-attribute 'cph-box-face    nil :foreground bar)
    (set-face-attribute 'cph-rule-face   nil :foreground rule)
    (set-face-attribute 'cph-button-face nil :foreground btn-fg
                        :box `(:line-width (1 . 1) :color ,btn-bd))))

;; Re-theme now and on every future theme switch.
(if (boundp 'enable-theme-functions)
    (add-hook 'enable-theme-functions #'cph--refresh-faces)
  (advice-add 'load-theme :after #'cph--refresh-faces))
(cph--refresh-faces)

;;;; ------------------------------------------------------------------------
;;;; Internal state
;;;; ------------------------------------------------------------------------

(defvar cph--servers nil
  "Alist of (PORT . PROCESS) for the running listeners.")

(defvar cph--current nil
  "Plist describing the run currently shown in the results panel.
Keys: :name :src :dir :url :tests :results :status :message :time-limit.
:tests is a list of (INPUT . EXPECTED) conses.  :results is a list, parallel
to :tests, of result plists (or nil for not-yet-run).")

(defconst cph--buffer-name "*cph*"
  "Name of the results panel buffer.")

;;;; ------------------------------------------------------------------------
;;;; Small helpers
;;;; ------------------------------------------------------------------------

(defun cph--sanitize (s)
  "Turn S into a filesystem-safe slug."
  (let ((s (replace-regexp-in-string "[^A-Za-z0-9._-]+" "_" (string-trim (or s "")))))
    (setq s (replace-regexp-in-string "_+" "_" s))
    (setq s (string-trim s "_+" "_+"))
    (if (string-empty-p s) "problem" s)))

(defun cph--ensure-newline (s)
  "Ensure string S ends with exactly one trailing newline (for stdin)."
  (if (or (null s) (string-empty-p s)) s
    (if (string-suffix-p "\n" s) s (concat s "\n"))))

(defun cph--normalize (s)
  "Normalize S for output comparison: trim trailing WS per line and at end."
  (string-trim-right
   (mapconcat #'string-trim-right (split-string (or s "") "\n") "\n")))

(defun cph--match-p (actual expected)
  "Non-nil when ACTUAL matches EXPECTED under competitive-style comparison."
  (string= (cph--normalize actual) (cph--normalize expected)))

(defun cph--lang (src)
  "Return the toolchain plist for source file SRC, or nil."
  (cdr (assoc (downcase (or (file-name-extension src) "")) cph-languages)))

(defun cph--exe (src)
  "Return the compiled-binary path for SRC."
  (expand-file-name (file-name-base src) (file-name-directory src)))

;;;; ------------------------------------------------------------------------
;;;; Test persistence  (.cph/<basename>.json)
;;;; ------------------------------------------------------------------------

(defun cph--prob-file (src)
  "Return the path of the `.cph' metadata file for source SRC."
  (expand-file-name (concat (file-name-base src) ".json")
                    (expand-file-name ".cph" (file-name-directory src))))

(defun cph--save-prob (src plist)
  "Persist problem PLIST for source SRC.
PLIST keys: :name :group :url :time-limit :tests (list of (in . out))."
  (let* ((file (cph--prob-file src))
         (obj (list :name (or (plist-get plist :name) "")
                    :group (or (plist-get plist :group) "")
                    :url (or (plist-get plist :url) "")
                    :timeLimit (or (plist-get plist :time-limit) 0)
                    :tests (vconcat
                            (mapcar (lambda (tc)
                                      (list :input (or (car tc) "")
                                            :output (or (cdr tc) "")))
                                    (plist-get plist :tests))))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert (json-serialize obj)))
    file))

(defun cph--load-prob (src)
  "Load and return the problem PLIST for SRC, or nil if none stored."
  (let ((file (cph--prob-file src)))
    (when (file-exists-p file)
      (let* ((data (with-temp-buffer
                     (insert-file-contents file)
                     (json-parse-string (buffer-string)
                                        :object-type 'alist
                                        :array-type 'list
                                        :null-object nil
                                        :false-object nil))))
        (list :name (alist-get 'name data)
              :group (alist-get 'group data)
              :url (alist-get 'url data)
              :time-limit (alist-get 'timeLimit data)
              :tests (mapcar (lambda (tc)
                               (cons (alist-get 'input tc)
                                     (alist-get 'output tc)))
                             (alist-get 'tests data)))))))

(defun cph--load-tests (src)
  "Return the list of (INPUT . EXPECTED) tests stored for SRC."
  (plist-get (cph--load-prob src) :tests))

;;;; ------------------------------------------------------------------------
;;;; Competitive Companion listener (HTTP server)
;;;; ------------------------------------------------------------------------

(defun cph--content-length (headers)
  "Parse the Content-Length value from HTTP HEADERS string, or nil."
  (let ((case-fold-search t))
    (when (string-match "content-length:[ \t]*\\([0-9]+\\)" headers)
      (string-to-number (match-string 1 headers)))))

(defun cph--server-filter (proc chunk)
  "Accumulate CHUNK from client PROC; handle the request once complete."
  (unless (process-get proc 'cph-done)
    (let* ((acc (concat (or (process-get proc 'cph-acc) "") chunk)))
      (process-put proc 'cph-acc acc)
      (let* ((crlf (string-search "\r\n\r\n" acc))
             (lf   (string-search "\n\n" acc))
             (sep  (cond (crlf crlf) (lf lf)))
             (seplen (if crlf 4 2)))
        (when sep
          (let* ((headers (substring acc 0 sep))
                 (body (substring acc (+ sep seplen)))
                 (clen (cph--content-length headers)))
            (when (or (null clen) (>= (length body) clen))
              (process-put proc 'cph-done t)
              (cph--handle-request body)
              (ignore-errors
                (process-send-string
                 proc (concat "HTTP/1.1 200 OK\r\n"
                              "Content-Type: text/plain\r\n"
                              "Connection: close\r\n"
                              "Content-Length: 2\r\n\r\nok")))
              (run-at-time 0.1 nil (lambda () (ignore-errors (delete-process proc)))))))))))

(defun cph--handle-request (body)
  "Parse JSON BODY from Competitive Companion and create the problem."
  (condition-case err
      (let ((data (json-parse-string
                   (decode-coding-string body 'utf-8)
                   :object-type 'alist :array-type 'list
                   :null-object nil :false-object nil)))
        (cph--create-problem data))
    (error (message "[cph] could not handle problem: %s" (error-message-string err)))))

(defun cph--current-directory ()
  "Directory to create a received problem in.
When `cph-use-current-directory' is non-nil, use the `default-directory' of
the buffer the user is currently looking at (a Dired buffer's directory, or
the directory of the file being visited).  Otherwise fall back to
`cph-directory'.  Network process filters can run with an arbitrary
`current-buffer', so we read the directory from the selected window's buffer
rather than relying on `default-directory' at call time."
  (or (and cph-use-current-directory
           (let ((buf (window-buffer (selected-window))))
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (when (stringp default-directory)
                   (expand-file-name default-directory))))))
      (expand-file-name cph-directory)))

(defun cph--create-problem (data)
  "Create a source file and store tests from Competitive Companion DATA."
  (let* ((name  (or (alist-get 'name data) "problem"))
         (group (or (alist-get 'group data) ""))
         (url   (or (alist-get 'url data) ""))
         (tl    (or (alist-get 'timeLimit data) cph-default-time-limit))
         (tests (mapcar (lambda (tc)
                          (cons (or (alist-get 'input tc) "")
                                (or (alist-get 'output tc) "")))
                        (alist-get 'tests data)))
         (ext   cph-default-extension)
         (root  (cph--current-directory))
         (dir   (if (and cph-group-subdirs (not (string-empty-p group)))
                    (expand-file-name (cph--sanitize group) root)
                  root))
         (base  (cph--sanitize name))
         (file  (expand-file-name (concat base "." ext) dir)))
    (make-directory dir t)
    ;; Write the template only for a brand-new file; never clobber your code.
    (unless (file-exists-p file)
      (with-temp-file file (insert (cph--template-for ext base))))
    (cph--save-prob file (list :name name :group group :url url
                               :time-limit tl :tests tests))
    (message "[cph] received \"%s\" (%d test%s) -> %s"
             name (length tests) (if (= (length tests) 1) "" "s")
             (abbreviate-file-name file))
    (when cph-open-on-receive
      (find-file file)
      (cph--load-into-current file)
      (cph--show-results)
      (cph--render))))

;;;###autoload
(defun cph/start-server ()
  "Start the Competitive Companion listener on `cph-ports'."
  (interactive)
  (cph/stop-server)
  (let (ok)
    (dolist (port cph-ports)
      (condition-case err
          (push (cons port
                      (make-network-process
                       :name (format "cph-server:%d" port)
                       :server t
                       :service port
                       :host "127.0.0.1"
                       :family 'ipv4
                       :coding 'binary
                       :noquery t
                       :filter #'cph--server-filter))
                cph--servers)
        (file-error (message "[cph] port %d unavailable: %s"
                             port (error-message-string err)))
        (error (message "[cph] could not bind %d: %s"
                        port (error-message-string err)))))
    (setq ok (mapcar #'car cph--servers))
    (when (called-interactively-p 'interactive)
      (if ok (message "[cph] listening on %s" ok)
        (message "[cph] no ports could be bound")))
    ok))

;;;###autoload
(defun cph/stop-server ()
  "Stop all Competitive Companion listeners."
  (interactive)
  (dolist (cell cph--servers)
    (ignore-errors (delete-process (cdr cell))))
  (setq cph--servers nil)
  (when (called-interactively-p 'interactive)
    (message "[cph] listener stopped")))

;;;###autoload
(define-minor-mode cph-mode
  "Global minor mode: run the Competitive Companion listener while enabled."
  :global t
  :group 'cph
  :lighter " CPH"
  (if cph-mode (cph/start-server) (cph/stop-server)))

;;;; ------------------------------------------------------------------------
;;;; Loading a problem into the panel state
;;;; ------------------------------------------------------------------------

(defun cph--load-into-current (src)
  "Set `cph--current' from the stored problem for source SRC."
  (let* ((prob (cph--load-prob src))
         (tests (plist-get prob :tests)))
    (setq cph--current
          (list :name (or (plist-get prob :name) (file-name-base src))
                :src src
                :dir (file-name-directory src)
                :url (plist-get prob :url)
                :time-limit (max (round (* cph-time-limit-factor
                                           (or (plist-get prob :time-limit)
                                               cph-default-time-limit)))
                                 1000)
                :tests tests
                :results (make-list (length tests) nil)
                :open (make-list (length tests) t) ; all expanded until run
                :status 'idle
                :message nil))))

(defun cph--source-file ()
  "Best guess at the source file to operate on."
  (cond (buffer-file-name buffer-file-name)
        ((plist-get cph--current :src) (plist-get cph--current :src))
        (t nil)))

;;;; ------------------------------------------------------------------------
;;;; Running
;;;; ------------------------------------------------------------------------

;;;###autoload
(defun cph/run-all ()
  "Compile (if needed) and run every testcase for the current source file."
  (interactive)
  (let ((src (cph--source-file)))
    (unless src (user-error "No source file for this buffer"))
    ;; Save the source buffer if it is open & modified.
    (when-let ((buf (find-buffer-visiting src)))
      (with-current-buffer buf (when (buffer-modified-p) (save-buffer))))
    (cph--load-into-current src)
    (let* ((tests (plist-get cph--current :tests))
           (lang (cph--lang src))
           (dir (file-name-directory src))
           (exe (cph--exe src)))
      (unless tests
        (user-error "No testcases for %s — receive one from Competitive Companion or use `cph/edit-tests'"
                    (file-name-nondirectory src)))
      (unless lang
        (user-error "No cph language config for .%s files" (file-name-extension src)))
      (cph--show-results)
      (let ((compile-fn (plist-get lang :compile))
            (run-cmd (funcall (plist-get lang :run) src exe dir)))
        (if compile-fn
            (progn
              (plist-put cph--current :status 'compiling)
              (cph--render)
              (cph--compile (funcall compile-fn src exe dir) dir
                            (lambda (ok output)
                              (if ok
                                  (progn (plist-put cph--current :status 'running)
                                         (cph--run-seq run-cmd 0))
                                (plist-put cph--current :status 'ce)
                                (plist-put cph--current :message output)
                                (cph--render)))))
          (plist-put cph--current :status 'running)
          (cph--render)
          (cph--run-seq run-cmd 0))))))

(defun cph--compile (cmd dir cont)
  "Run compile CMD in DIR; call CONT with (OK OUTPUT) when done."
  (let* ((default-directory dir)
         (buf (generate-new-buffer " *cph-compile*")))
    (make-process
     :name "cph-compile" :buffer buf :command cmd :noquery t
     :sentinel (lambda (p _e)
                 (when (memq (process-status p) '(exit signal))
                   (let ((ok (zerop (process-exit-status p)))
                         (out (with-current-buffer buf
                                (ansi-color-apply (buffer-string)))))
                     (kill-buffer buf)
                     (funcall cont ok out)))))))

(defun cph--run-seq (run-cmd idx)
  "Run testcase IDX (0-based) with RUN-CMD, then chain to the next."
  (let ((tests (plist-get cph--current :tests)))
    (if (>= idx (length tests))
        (progn (plist-put cph--current :status 'done) (cph--render) (cph--summary))
      (cph--render) ; show "running test idx"
      (let* ((tc (nth idx tests))
             (input (cph--ensure-newline (car tc)))
             (expected (cdr tc))
             (dir (plist-get cph--current :dir))
             (limit (plist-get cph--current :time-limit)))
        (cph--run-one
         run-cmd input dir limit
         (lambda (raw)
           (let* ((verdict
                   (cond ((plist-get raw :tle) 'TLE)
                         ((not (zerop (plist-get raw :exit))) 'RE)
                         ((cph--match-p (plist-get raw :stdout) expected) 'AC)
                         (t 'WA)))
                  (results (plist-get cph--current :results))
                  (open (plist-get cph--current :open)))
             (setf (nth idx results)
                   (list :verdict verdict
                         :time (plist-get raw :time)
                         :stdout (plist-get raw :stdout)
                         :stderr (plist-get raw :stderr)
                         :exit (plist-get raw :exit)))
             ;; Auto-fold: collapse passed tests, keep failures open.
             (setf (nth idx open) (not (eq verdict 'AC)))
             (cph--render)
             (cph--run-seq run-cmd (1+ idx)))))))))

(defun cph--run-one (run-cmd input dir limit-ms cb)
  "Run RUN-CMD in DIR feeding INPUT on stdin, killing after LIMIT-MS.
Call CB with a plist (:stdout :stderr :exit :time :tle)."
  (let* ((default-directory dir)
         (obuf (generate-new-buffer " *cph-out*"))
         (ebuf (generate-new-buffer " *cph-err*"))
         (start (current-time))
         proc)
    (setq proc
          (make-process
           :name "cph-run" :buffer obuf :command run-cmd
           :stderr ebuf :connection-type 'pipe :noquery t
           :sentinel
           (lambda (p _e)
             (when (memq (process-status p) '(exit signal))
               (let ((timer (process-get p 'cph-timer))
                     (tle (process-get p 'cph-tle))
                     (elapsed (* 1000.0 (float-time (time-subtract (current-time) start))))
                     (out (with-current-buffer obuf (buffer-string)))
                     (err (when (buffer-live-p ebuf)
                            (with-current-buffer ebuf (buffer-string))))
                     (code (process-exit-status p)))
                 (when (timerp timer) (cancel-timer timer))
                 (kill-buffer obuf)
                 ;; The stderr pipe process may still be closing; defer its kill.
                 (run-at-time 0.05 nil (lambda ()
                                         (when (buffer-live-p ebuf) (kill-buffer ebuf))))
                 (funcall cb (list :stdout out :stderr (or err "")
                                   :exit code :time elapsed :tle tle)))))))
    (process-put proc 'cph-timer
                 (run-at-time (/ limit-ms 1000.0) nil
                              (lambda ()
                                (when (process-live-p proc)
                                  (process-put proc 'cph-tle t)
                                  (ignore-errors (kill-process proc))))))
    (ignore-errors (process-send-string proc input))
    (ignore-errors (process-send-eof proc))))

(defun cph--summary ()
  "Echo a one-line pass/fail summary for the finished run."
  (let* ((results (plist-get cph--current :results))
         (n (length results))
         (passed (cl-count-if (lambda (r) (eq (plist-get r :verdict) 'AC)) results)))
    (message "[cph] %d/%d passed%s" passed n
             (if (= passed n) " 🎉" ""))))

;;;; ------------------------------------------------------------------------
;;;; Results panel
;;;; ------------------------------------------------------------------------

(defun cph--verdict-badge (v)
  "Return a coloured pill/badge string for verdict V (nil = not yet run)."
  (pcase v
    ('AC  (propertize "✓ Passed" 'face 'cph-badge-ac))
    ('WA  (propertize "✗ Failed" 'face 'cph-badge-wa))
    ('TLE (propertize "⧗ TLE"    'face 'cph-badge-tle))
    ('RE  (propertize "✦ RE"     'face 'cph-badge-re))
    ('CE  (propertize "▲ CE"     'face 'cph-badge-ce))
    (_    (propertize "•••"      'face 'cph-badge-run))))

(defun cph--verdict-color-face (v)
  "Face whose foreground colours a card's left bar for verdict V."
  (pcase v
    ('AC 'cph-ac-face) ('WA 'cph-wa-face) ('TLE 'cph-tle-face)
    ('RE 'cph-re-face) ('CE 'cph-ce-face) (_ 'cph-box-face)))

(defun cph--results-buffer ()
  "Return (creating) the results panel buffer."
  (with-current-buffer (get-buffer-create cph--buffer-name)
    (unless (derived-mode-p 'cph-results-mode) (cph-results-mode))
    (current-buffer)))

(defun cph--show-results ()
  "Display the results buffer in a right-side window without leaving source."
  (display-buffer
   (cph--results-buffer)
   '((display-buffer-reuse-window display-buffer-in-side-window)
     (side . right) (window-width . 0.46))))

(defun cph--box-lines (text)
  "Return the display lines `cph--boxed' would render for TEXT.
Trims trailing whitespace, substitutes a shadowed \"(empty)\" placeholder,
and caps the height at `cph-box-max-lines' with a \"… (n more)\" footer."
  (let* ((raw (split-string (string-trim-right (or text "")) "\n"))
         (raw (if (equal raw '(""))
                  (list (propertize "(empty)" 'face 'shadow)) raw))
         (extra (- (length raw) cph-box-max-lines)))
    (if (> extra 0)
        (append (cl-subseq raw 0 cph-box-max-lines)
                (list (propertize (format "… (%d more line%s)"
                                          extra (if (= extra 1) "" "s"))
                                  'face 'shadow)))
      raw)))

(defun cph--window-width ()
  "Columns available in the results window's text area.
Falls back to 80 when the panel is not currently displayed."
  (let ((win (get-buffer-window cph--buffer-name)))
    (if win (window-body-width win) 80)))

(defun cph--box-max-width ()
  "Largest inner box-content width that fits the results window.
A boxed line is rendered as the verdict bar prefix \"▌  \" (3) plus the box
edge \"▏\" (1), the content, and a trailing space (1); reserve one more
column so a full-width line never triggers a continuation glyph."
  (max 8 (- (cph--window-width) 6)))

(defun cph--block-width (text)
  "Return the inner content width `cph--boxed' would use for TEXT.
Used to align the right edges of sibling I/O boxes within a card."
  (min (cph--box-max-width)
       (apply #'max 8 (mapcar #'string-width (cph--box-lines text)))))

(defun cph--truncate-line (s width)
  "Truncate string S to WIDTH display columns, appending … when cut."
  (if (<= (string-width s) width) s
    (truncate-string-to-width s width nil nil "…")))

(defun cph--boxed (text &optional min-width)
  "Return TEXT as a left-barred, tinted block.
Height is capped by `cph-box-max-lines' and width by the results window
\(see `cph--box-max-width'), so the block stays inside the panel as it is
resized.  A box-drawing rectangle cannot left-align with the label above it:
glyphs like ┌ │ └ are centred in their cell, so the border lands about half a
column right of the label.  We use a cell-edge bar (▏) plus a subtle
background tint instead, so the block lines up under its label and still reads
as a contained box.

MIN-WIDTH, when non-nil, pads every line to at least that inner width so a
group of boxes can share a common right edge."
  (let* ((raw (cph--box-lines text))
         (w (min (cph--box-max-width)
                 (max (or min-width 0)
                      (apply #'max 8 (mapcar #'string-width raw)))))
         (lines (mapcar (lambda (l) (cph--truncate-line l w)) raw))
         (bar-face '(cph-box-face cph-iobox-face)))
    (mapconcat
     (lambda (l)
       (concat (propertize "▏" 'face bar-face)
               (propertize (concat l
                                   (make-string (max 0 (- w (string-width l))) ?\s)
                                   " ")
                           'face 'cph-iobox-face)))
     lines "\n")))

(defun cph--io-section (label text &optional width)
  "Return a labelled, boxed I/O section string for LABEL and TEXT.
WIDTH is passed through to `cph--boxed' to align sibling boxes."
  (concat (propertize label 'face 'cph-label-face) "\n"
          (cph--boxed text width)))

(defun cph--bar (body face)
  "Prefix every line of BODY with a coloured left bar drawn in FACE."
  (mapconcat (lambda (l) (concat (propertize "▌" 'face face) "  " l))
             (split-string body "\n") "\n"))

(defvar cph--card-mouse-map
  (let ((m (make-sparse-keymap)))
    (define-key m [mouse-1] #'cph-toggle-card-mouse)
    m)
  "Keymap active on a card's header line for click-to-fold.")

(defun cph--card (idx tc result open)
  "Insert the card for testcase IDX (0-based).
TC is (IN . OUT), RESULT a plist (or nil), OPEN whether it is expanded."
  (let* ((v (and result (plist-get result :verdict)))
         (arrow (propertize (if open "▾" "▸") 'face 'shadow))
         (title (concat arrow " "
                        (propertize (format "TC %d" (1+ idx)) 'face 'cph-tc-face)
                        "   " (cph--verdict-badge v)
                        (when result
                          (propertize (format "   · %.0f ms" (plist-get result :time))
                                      'face 'shadow))))
         (body (if (not open)
                   title
                 (let* ((recv (if result (plist-get result :stdout) ""))
                        (err (and result (plist-get result :stderr)))
                        (has-err (and err (not (string-empty-p (string-trim err)))))
                        ;; Share one inner width across the card's boxes so their
                        ;; right edges line up instead of stepping in and out.
                        (secw (max (cph--block-width (car tc))
                                   (cph--block-width (cdr tc))
                                   (cph--block-width recv)
                                   (if has-err (cph--block-width err) 0))))
                   (concat
                    title "\n\n"
                    (cph--io-section "Input" (car tc) secw) "\n\n"
                    (cph--io-section "Expected Output" (cdr tc) secw) "\n\n"
                    (cph--io-section "Received Output" recv secw)
                    (when has-err
                      (concat "\n\n" (cph--io-section "stderr" err secw)))))))
         (start (point)))
    (insert (cph--bar body (cph--verdict-color-face v)) "\n\n")
    ;; Tag the whole card with its index so TAB anywhere on it toggles; make the
    ;; header line clickable and highlight-on-hover.
    (put-text-property start (point) 'cph-test idx)
    (let ((hdr-end (save-excursion (goto-char start) (line-end-position))))
      (put-text-property start hdr-end 'keymap cph--card-mouse-map)
      (put-text-property start hdr-end 'mouse-face 'highlight))))

(defun cph--button (key label)
  "Return a button-like string showing shortcut KEY and LABEL.
The `cph-button-face' :box already supplies horizontal padding, so the
text itself is kept tight."
  (propertize (format " %s : %s " key label) 'face 'cph-button-face))

(defun cph--rule ()
  "Return a thin, full-width horizontal separator rule for the panel."
  (let ((w (max 8 (1- (cph--window-width)))))
    (propertize (concat (make-string w ?─) "\n") 'face 'cph-rule-face)))

(defvar cph--last-render-width nil
  "Window width the panel was last rendered at, for resize detection.")

(defun cph--render ()
  "Re-render the results panel from `cph--current' in CPH-JUDGE card style."
  (when cph--current
    (with-current-buffer (cph--results-buffer)
      (let ((inhibit-read-only t)
            (pt (point))
            (results (plist-get cph--current :results)))
        (erase-buffer)
        ;; --- header: title + pass badge + path/url ---
        (let* ((n (length results))
               (passed (cl-count-if (lambda (r) (eq (plist-get r :verdict) 'AC)) results)))
          (insert "  "
                  (propertize (or (plist-get cph--current :name) "problem")
                              'face 'cph-header-face)
                  "    "
                  (propertize (format "%s %d/%d passed"
                                      (cond ((zerop n) "•")
                                            ((= passed n) "✓")
                                            (t "✗"))
                                      passed n)
                              'face (cond ((zerop n) 'cph-badge-run)
                                          ((= passed n) 'cph-badge-ac)
                                          (t 'cph-badge-wa)))
                  "\n\n")
          (insert (propertize (format "  %s\n"
                                      (abbreviate-file-name (plist-get cph--current :src)))
                              'face 'shadow))
          (when-let ((url (plist-get cph--current :url)))
            (unless (string-empty-p url)
              (insert "  ")
              ;; A real button: mouse-1 (follow-link) or RET opens it in the browser.
              (insert-text-button
               url
               'face 'link
               'follow-link t
               'help-echo "mouse-1 / RET: open this problem in your browser"
               'action (lambda (_btn) (browse-url url)))
              (insert "\n")))
          (insert "\n" (cph--rule) "\n")
          ;; --- body ---
          (pcase (plist-get cph--current :status)
            ('compiling (insert (propertize "  ⟳ Compiling…\n\n" 'face 'warning)))
            ('ce (insert (cph--bar
                          (concat (propertize "▲ Compile Error" 'face 'cph-ce-face) "\n\n"
                                  (cph--io-section "compiler output"
                                                  (plist-get cph--current :message)))
                          'cph-ce-face)
                         "\n\n"))
            (_
             (when (eq (plist-get cph--current :status) 'running)
               (insert (propertize "  ⟳ Running…\n\n" 'face 'warning)))
             (cl-loop for i from 0 below n
                      do (cph--card i (nth i (plist-get cph--current :tests))
                                    (nth i results)
                                    (nth i (plist-get cph--current :open)))))))
        ;; --- footer: button-style action hints ---
        (insert "\n" (cph--rule) "\n  "
                (string-join (list (cph--button "r" "Run All")
                                   (cph--button "a" "New Test")
                                   (cph--button "e" "Edit")
                                   (cph--button "TAB" "Fold")
                                   (cph--button "q" "Quit"))
                             "  ")
                "\n")
        (setq cph--last-render-width (cph--window-width))
        (goto-char (min pt (point-max)))))))

(defun cph--on-window-size-change (&rest _)
  "Re-render the panel when its window's width changes.
Registered on `window-size-change-functions' so boxes and rules re-flow to
the new width; guarded to stay cheap when the panel is hidden or unchanged."
  (when (and cph--current (get-buffer-window cph--buffer-name))
    (let ((w (cph--window-width)))
      (unless (eql w cph--last-render-width)
        (cph--render)))))

(add-hook 'window-size-change-functions #'cph--on-window-size-change)

(defun cph/open-results ()
  "Show the results panel."
  (interactive)
  (let ((src (cph--source-file)))
    (when (and src (not cph--current)) (cph--load-into-current src)))
  (cph--show-results)
  (cph--render))

;;;###autoload
(defun cph/panel ()
  "Lay out source on the left and the results panel on the right."
  (interactive)
  (let ((src (cph--source-file)))
    (unless src (user-error "No source file"))
    (unless cph--current (cph--load-into-current src))
    (let ((srcbuf (or (find-buffer-visiting src) (find-file-noselect src))))
      (pop-to-buffer srcbuf '((display-buffer-same-window)))
      (delete-other-windows)
      (cph--render)
      (display-buffer (cph--results-buffer)
                      '((display-buffer-in-side-window)
                        (side . right) (window-width . 0.45))))))

(defun cph--rerun ()
  "Re-run from the results panel, operating on the panel's source."
  (interactive)
  (if-let ((src (plist-get cph--current :src)))
      (with-current-buffer (or (find-buffer-visiting src)
                               (find-file-noselect src))
        (cph/run-all))
    (user-error "No active problem")))

(defun cph--goto-test (idx)
  "Move point to the header of the card for testcase IDX, if present."
  (when-let ((pos (text-property-any (point-min) (point-max) 'cph-test idx)))
    (goto-char pos)))

(defun cph-toggle-card ()
  "Fold/unfold the testcase card at point (like an Org heading).
With point not on any card, toggle all cards open/closed at once."
  (interactive)
  (unless cph--current (user-error "No active problem"))
  (let ((idx (get-text-property (point) 'cph-test))
        (open (plist-get cph--current :open)))
    (if idx
        (progn
          (setf (nth idx open) (not (nth idx open)))
          (cph--render)
          (cph--goto-test idx))
      (cph-toggle-all-cards))))

(defun cph-toggle-all-cards ()
  "Expand all cards, or collapse them all if any is currently open."
  (interactive)
  (unless cph--current (user-error "No active problem"))
  (let* ((open (plist-get cph--current :open))
         (target (not (cl-some #'identity open))))
    (plist-put cph--current :open (make-list (length open) target))
    (cph--render)))

(defun cph-toggle-card-mouse (event)
  "Fold/unfold the card clicked on by mouse EVENT."
  (interactive "e")
  (goto-char (posn-point (event-start event)))
  (cph-toggle-card))

(defvar-keymap cph-results-mode-map
  :doc "Keymap for `cph-results-mode'."
  "r" #'cph--rerun
  "g" #'cph--render
  "e" #'cph/edit-tests
  "a" #'cph/add-test
  "TAB" #'cph-toggle-card
  "<tab>" #'cph-toggle-card
  "<backtab>" #'cph-toggle-all-cards
  "q" #'quit-window)

(define-derived-mode cph-results-mode special-mode "cph"
  "Major mode for the Competitive Programming Helper results panel."
  (setq-local truncate-lines nil)
  (buffer-disable-undo))

;; In Evil (Doom), single-letter keys in a read-only buffer are otherwise
;; swallowed by normal-state motions (r=replace, a=append, …). Bind them in the
;; relevant Evil states so the panel's [r]/[e]/[a]/[g]/[q] actually fire.
;; NOTE: use the *function* `evil-define-key*' (not the `evil-define-key'
;; macro).  The macro is expanded at read time, so byte-compiling this file
;; while Evil is not yet loaded silently miscompiles it into a bare function
;; call, which then fails at runtime with `invalid-function evil-define-key'.
(with-eval-after-load 'evil
  (evil-define-key* '(normal motion) cph-results-mode-map
    "r" #'cph--rerun
    "g" #'cph--render
    "e" #'cph/edit-tests
    "a" #'cph/add-test
    (kbd "TAB") #'cph-toggle-card
    (kbd "<tab>") #'cph-toggle-card
    (kbd "<backtab>") #'cph-toggle-all-cards
    "q" #'quit-window))

;;;; ------------------------------------------------------------------------
;;;; Editing testcases
;;;; ------------------------------------------------------------------------

(defconst cph--edit-header
  (concat ";; CPH testcases — edit freely, then C-c C-c to save (C-c C-k cancels).\n"
          ";; Each test is an \"--- INPUT n ---\" block followed by\n"
          ";; an \"--- EXPECTED n ---\" block.  Empty tests are dropped.\n\n")
  "Banner shown at the top of the test-editing buffer.")

(defvar-local cph--edit-src nil
  "Source file whose tests are being edited in this buffer.")

(defun cph--edit-render (src tests)
  "Insert the editable representation of TESTS for SRC into the current buffer."
  (insert cph--edit-header)
  (let ((i 0))
    (dolist (tc tests)
      (cl-incf i)
      (insert (format "--- INPUT %d ---\n" i))
      (insert (string-trim-right (or (car tc) "")) "\n")
      (insert (format "--- EXPECTED %d ---\n" i))
      (insert (string-trim-right (or (cdr tc) "")) "\n"))
    ;; A trailing empty pair so adding a test is just "type here".
    (cl-incf i)
    (insert (format "--- INPUT %d ---\n\n" i))
    (insert (format "--- EXPECTED %d ---\n\n" i)))
  (setq cph--edit-src src))

(defun cph--parse-edit-buffer ()
  "Parse the current edit buffer into a list of (INPUT . EXPECTED) tests."
  (save-excursion
    (goto-char (point-min))
    (let (sections)
      (while (re-search-forward "^--- \\(INPUT\\|EXPECTED\\)\\b[^\n]*\n" nil t)
        (push (list (intern (downcase (match-string 1)))
                    (match-beginning 0)   ; marker start
                    (match-end 0))        ; content start
              sections))
      (setq sections (nreverse sections))
      (let (tests pending-in)
        (cl-loop for (s . rest) on sections
                 for type = (nth 0 s)
                 for content-start = (nth 2 s)
                 for content-end = (if rest (nth 1 (car rest)) (point-max))
                 for text = (replace-regexp-in-string
                             "\n\\'" ""
                             (buffer-substring-no-properties content-start content-end))
                 do (pcase type
                      ('input (setq pending-in text))
                      ('expected
                       (when pending-in
                         (unless (and (string-empty-p (string-trim pending-in))
                                      (string-empty-p (string-trim text)))
                           (push (cons pending-in text) tests))
                         (setq pending-in nil)))))
        (nreverse tests)))))

(defun cph-edit-save ()
  "Save the edited testcases back to the problem's `.cph' file."
  (interactive)
  (let* ((src cph--edit-src)
         (tests (cph--parse-edit-buffer))
         (prob (cph--load-prob src)))
    (cph--save-prob src (list :name (or (plist-get prob :name) (file-name-base src))
                              :group (plist-get prob :group)
                              :url (plist-get prob :url)
                              :time-limit (plist-get prob :time-limit)
                              :tests tests))
    (message "[cph] saved %d test%s for %s"
             (length tests) (if (= (length tests) 1) "" "s")
             (file-name-nondirectory src))
    (quit-window t)
    ;; Refresh the panel if it is showing this problem.
    (when (equal (plist-get cph--current :src) src)
      (cph--load-into-current src)
      (cph--render))))

(defun cph-edit-cancel ()
  "Discard the test edits and close the editor."
  (interactive)
  (quit-window t)
  (message "[cph] edit cancelled"))

(defvar-keymap cph-edit-mode-map
  :doc "Keymap for `cph-edit-mode'."
  "C-c C-c" #'cph-edit-save
  "C-c C-k" #'cph-edit-cancel)

(define-derived-mode cph-edit-mode text-mode "cph-edit"
  "Major mode for editing Competitive Programming Helper testcases.")

;;;###autoload
(defun cph/edit-tests ()
  "Open a buffer to add/edit/delete the current problem's testcases."
  (interactive)
  (let ((src (cph--source-file)))
    (unless src (user-error "No source file"))
    (let ((tests (cph--load-tests src))
          (buf (get-buffer-create (format "*cph-edit: %s*" (file-name-nondirectory src)))))
      (with-current-buffer buf
        (cph-edit-mode)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (cph--edit-render src tests))
        (goto-char (point-min)))
      (pop-to-buffer buf)
      (message "Edit tests, then C-c C-c to save (C-c C-k cancels)"))))

;;;###autoload
(defun cph/add-test ()
  "Open the test editor positioned at a fresh empty test."
  (interactive)
  (cph/edit-tests)
  (goto-char (point-max))
  (re-search-backward "^--- INPUT" nil t)
  (forward-line 1))

;;;; ------------------------------------------------------------------------
;;;; Manual problem creation
;;;; ------------------------------------------------------------------------

;;;###autoload
(defun cph/new-problem (name)
  "Create a new empty problem called NAME in the current working directory.
See `cph--current-directory' for how the target directory is chosen."
  (interactive "sProblem name: ")
  (cph--create-problem (list (cons 'name name)
                             (cons 'tests nil)
                             (cons 'timeLimit cph-default-time-limit)))
  (cph/edit-tests))

(provide 'cph)
;;; cph.el ends here
