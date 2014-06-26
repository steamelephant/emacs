;;; help-fns.el --- Complex help functions -*- lexical-binding: t -*-

;; Copyright (C) 1985-1986, 1993-1994, 1998-2014
;;   Free Software Foundation, Inc.

;; Maintainer: emacs-devel@gnu.org
;; Keywords: help, internal
;; Package: emacs

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file contains those help commands which are complicated, and
;; which may not be used in every session.  For example
;; `describe-function' will probably be heavily used when doing elisp
;; programming, but not if just editing C files.  Simpler help commands
;; are in help.el

;;; Code:

(defvar help-fns-describe-function-functions nil
  "List of functions to run in help buffer in `describe-function'.
Those functions will be run after the header line and argument
list was inserted, and before the documentation will be inserted.
The functions will receive the function name as argument.")

;; Functions

;;;###autoload
(defun describe-function (function)
  "Display the full documentation of FUNCTION (a symbol)."
  (interactive
   (let ((fn (function-called-at-point))
	 (enable-recursive-minibuffers t)
	 val)
     (setq val (completing-read (if fn
				    (format "Describe function (default %s): " fn)
				  "Describe function: ")
				obarray 'fboundp t nil nil
				(and fn (symbol-name fn))))
     (list (if (equal val "")
	       fn (intern val)))))
  (if (null function)
      (message "You didn't specify a function")
    (help-setup-xref (list #'describe-function function)
		     (called-interactively-p 'interactive))
    (save-excursion
      (with-help-window (help-buffer)
	(prin1 function)
	;; Use " is " instead of a colon so that
	;; it is easier to get out the function name using forward-sexp.
	(princ " is ")
	(describe-function-1 function)
	(with-current-buffer standard-output
	  ;; Return the text we displayed.
	  (buffer-string))))))


;; Could be this, if we make symbol-file do the work below.
;; (defun help-C-file-name (subr-or-var kind)
;;   "Return the name of the C file where SUBR-OR-VAR is defined.
;; KIND should be `var' for a variable or `subr' for a subroutine."
;;   (symbol-file (if (symbolp subr-or-var) subr-or-var
;; 		 (subr-name subr-or-var))
;; 	       (if (eq kind 'var) 'defvar 'defun)))
;;;###autoload
(defun help-C-file-name (subr-or-var kind)
  "Return the name of the C file where SUBR-OR-VAR is defined.
KIND should be `var' for a variable or `subr' for a subroutine."
  (let ((docbuf (get-buffer-create " *DOC*"))
	(name (if (eq 'var kind)
		  (concat "V" (symbol-name subr-or-var))
		(concat "F" (subr-name (advice--cd*r subr-or-var))))))
    (with-current-buffer docbuf
      (goto-char (point-min))
      (if (eobp)
	  (insert-file-contents-literally
	   (expand-file-name internal-doc-file-name doc-directory)))
      (let ((file (catch 'loop
		    (while t
		      (let ((pnt (search-forward (concat "" name "\n"))))
			(re-search-backward "S\\(.*\\)")
			(let ((file (match-string 1)))
			  (if (member file build-files)
			      (throw 'loop file)
			    (goto-char pnt))))))))
	(if (string-match "^ns.*\\(\\.o\\|obj\\)\\'" file)
	    (setq file (replace-match ".m" t t file 1))
	  (if (string-match "\\.\\(o\\|obj\\)\\'" file)
	      (setq file (replace-match ".c" t t file))))
	(if (string-match "\\.\\(c\\|m\\)\\'" file)
	    (concat "src/" file)
	  file)))))

(defcustom help-downcase-arguments nil
  "If non-nil, argument names in *Help* buffers are downcased."
  :type 'boolean
  :group 'help
  :version "23.2")

(defun help-highlight-arg (arg)
  "Highlight ARG as an argument name for a *Help* buffer.
Return ARG in face `help-argument-name'; ARG is also downcased
if the variable `help-downcase-arguments' is non-nil."
  (propertize (if help-downcase-arguments (downcase arg) arg)
	      'face 'help-argument-name))

(defun help-do-arg-highlight (doc args)
  (with-syntax-table (make-syntax-table emacs-lisp-mode-syntax-table)
    (modify-syntax-entry ?\- "w")
    (dolist (arg args)
      (setq doc (replace-regexp-in-string
                 ;; This is heuristic, but covers all common cases
                 ;; except ARG1-ARG2
                 (concat "\\<"                   ; beginning of word
                         "\\(?:[a-z-]*-\\)?"     ; for xxx-ARG
                         "\\("
                         (regexp-quote arg)
                         "\\)"
                         "\\(?:es\\|s\\|th\\)?"  ; for ARGth, ARGs
                         "\\(?:-[a-z0-9-]+\\)?"  ; for ARG-xxx, ARG-n
                         "\\(?:-[{([<`\"].*?\\)?"; for ARG-{x}, (x), <x>, [x], `x'
                         "\\>")                  ; end of word
                 (help-highlight-arg arg)
                 doc t t 1)))
    doc))

(defun help-highlight-arguments (usage doc &rest args)
  (when (and usage (string-match "^(" usage))
    (with-temp-buffer
      (insert usage)
      (goto-char (point-min))
      (let ((case-fold-search nil)
            (next (not (or args (looking-at "\\["))))
            (opt nil))
        ;; Make a list of all arguments
        (skip-chars-forward "^ ")
        (while next
          (or opt (not (looking-at " &")) (setq opt t))
          (if (not (re-search-forward " \\([\\[(]*\\)\\([^] &)\.]+\\)" nil t))
              (setq next nil)
            (setq args (cons (match-string 2) args))
            (when (and opt (string= (match-string 1) "("))
              ;; A pesky CL-style optional argument with default value,
              ;; so let's skip over it
              (search-backward "(")
              (goto-char (scan-sexps (point) 1)))))
        ;; Highlight arguments in the USAGE string
        (setq usage (help-do-arg-highlight (buffer-string) args))
        ;; Highlight arguments in the DOC string
        (setq doc (and doc (help-do-arg-highlight doc args))))))
  ;; Return value is like the one from help-split-fundoc, but highlighted
  (cons usage doc))

;; The following function was compiled from the former functions
;; `describe-simplify-lib-file-name' and `find-source-lisp-file' with
;; some excerpts from `describe-function-1' and `describe-variable'.
;; The only additional twists provided are (1) locate the defining file
;; for autoloaded functions, and (2) give preference to files in the
;; "install directory" (directories found via `load-path') rather than
;; to files in the "compile directory" (directories found by searching
;; the loaddefs.el file).  We autoload it because it's also used by
;; `describe-face' (instead of `describe-simplify-lib-file-name').

;;;###autoload
(defun find-lisp-object-file-name (object type)
  "Guess the file that defined the Lisp object OBJECT, of type TYPE.
OBJECT should be a symbol associated with a function, variable, or face;
  alternatively, it can be a function definition.
If TYPE is `defvar', search for a variable definition.
If TYPE is `defface', search for a face definition.
If TYPE is the value returned by `symbol-function' for a function symbol,
 search for a function definition.

The return value is the absolute name of a readable file where OBJECT is
defined.  If several such files exist, preference is given to a file
found via `load-path'.  The return value can also be `C-source', which
means that OBJECT is a function or variable defined in C.  If no
suitable file is found, return nil."
  (let* ((autoloaded (autoloadp type))
	 (file-name (or (and autoloaded (nth 1 type))
			(symbol-file
			 object (if (memq type (list 'defvar 'defface))
				    type
				  'defun)))))
    (cond
     (autoloaded
      ;; An autoloaded function: Locate the file since `symbol-function'
      ;; has only returned a bare string here.
      (setq file-name
	    (locate-file file-name load-path '(".el" ".elc") 'readable)))
     ((and (stringp file-name)
	   (string-match "[.]*loaddefs.el\\'" file-name))
      ;; An autoloaded variable or face.  Visit loaddefs.el in a buffer
      ;; and try to extract the defining file.  The following form is
      ;; from `describe-function-1' and `describe-variable'.
      (let ((location
	     (condition-case nil
		 (find-function-search-for-symbol object nil file-name)
	       (error nil))))
	(when (cdr location)
	  (with-current-buffer (car location)
	    (goto-char (cdr location))
	    (when (re-search-backward
		   "^;;; Generated autoloads from \\(.*\\)" nil t)
	      (setq file-name
		    (locate-file
		     (file-name-sans-extension
		      (match-string-no-properties 1))
		     load-path '(".el" ".elc") 'readable))))))))

    (cond
     ((and (not file-name) (subrp type))
      ;; A built-in function.  The form is from `describe-function-1'.
      (if (get-buffer " *DOC*")
	  (help-C-file-name type 'subr)
	'C-source))
     ((and (not file-name) (symbolp object)
	   (integerp (get object 'variable-documentation)))
      ;; A variable defined in C.  The form is from `describe-variable'.
      (if (get-buffer " *DOC*")
	  (help-C-file-name object 'var)
	'C-source))
     ((not (stringp file-name))
      ;; If we don't have a file-name string by now, we lost.
      nil)
     ;; Now, `file-name' should have become an absolute file name.
     ;; For files loaded from ~/.foo.elc, try ~/.foo.
     ;; This applies to config files like ~/.emacs,
     ;; which people sometimes compile.
     ((let (fn)
	(and (string-match "\\`\\..*\\.elc\\'"
			   (file-name-nondirectory file-name))
	     (string-equal (file-name-directory file-name)
			   (file-name-as-directory (expand-file-name "~")))
	     (file-readable-p (setq fn (file-name-sans-extension file-name)))
	     fn)))
     ;; When the Elisp source file can be found in the install
     ;; directory, return the name of that file.
     ((let ((lib-name
	     (if (string-match "[.]elc\\'" file-name)
		 (substring-no-properties file-name 0 -1)
	       file-name)))
	(or (and (file-readable-p lib-name) lib-name)
	    ;; The library might be compressed.
	    (and (file-readable-p (concat lib-name ".gz")) lib-name))))
     ((let* ((lib-name (file-name-nondirectory file-name))
	     ;; The next form is from `describe-simplify-lib-file-name'.
	     (file-name
	      ;; Try converting the absolute file name to a library
	      ;; name, convert that back to a file name and see if we
	      ;; get the original one.  If so, they are equivalent.
	      (if (equal file-name (locate-file lib-name load-path '("")))
		  (if (string-match "[.]elc\\'" lib-name)
		      (substring-no-properties lib-name 0 -1)
		    lib-name)
		file-name))
	     ;; The next three forms are from `find-source-lisp-file'.
	     (elc-file (locate-file
			(concat file-name
				(if (string-match "\\.el\\'" file-name)
				    "c"
				  ".elc"))
			load-path nil 'readable))
	     (str (when elc-file
		    (with-temp-buffer
		      (insert-file-contents-literally elc-file nil 0 256)
		      (buffer-string))))
	     (src-file (and str
			    (string-match ";;; from file \\(.*\\.el\\)" str)
			    (match-string 1 str))))
	(and src-file (file-readable-p src-file) src-file))))))

(defun help-fns--key-bindings (function)
  (when (commandp function)
    (let ((pt2 (with-current-buffer standard-output (point)))
          (remapped (command-remapping function)))
      (unless (memq remapped '(ignore undefined))
        (let ((keys (where-is-internal
                     (or remapped function) overriding-local-map nil nil))
              non-modified-keys)
          (if (and (eq function 'self-insert-command)
                   (vectorp (car-safe keys))
                   (consp (aref (car keys) 0)))
              (princ "It is bound to many ordinary text characters.\n")
            ;; Which non-control non-meta keys run this command?
            (dolist (key keys)
              (if (member (event-modifiers (aref key 0)) '(nil (shift)))
                  (push key non-modified-keys)))
            (when remapped
              (princ "Its keys are remapped to ")
              (princ (if (symbolp remapped)
			 (concat "`" (symbol-name remapped) "'")
		       "an anonymous command"))
              (princ ".\n"))

            (when keys
              (princ (if remapped
                         "Without this remapping, it would be bound to "
                       "It is bound to "))
              ;; If lots of ordinary text characters run this command,
              ;; don't mention them one by one.
              (if (< (length non-modified-keys) 10)
                  (princ (mapconcat 'key-description keys ", "))
                (dolist (key non-modified-keys)
                  (setq keys (delq key keys)))
                (if keys
                    (progn
                      (princ (mapconcat 'key-description keys ", "))
                      (princ ", and many ordinary text characters"))
                  (princ "many ordinary text characters"))))
            (when (or remapped keys non-modified-keys)
              (princ ".")
              (terpri)))))

      (with-current-buffer standard-output
        (fill-region-as-paragraph pt2 (point))
        (unless (looking-back "\n\n")
          (terpri))))))

(defun help-fns--compiler-macro (function)
  (let ((handler (function-get function 'compiler-macro)))
    (when handler
      (insert "\nThis function has a compiler macro")
      (if (symbolp handler)
          (progn
            (insert (format " `%s'" handler))
            (save-excursion
              (re-search-backward "`\\([^`']+\\)'" nil t)
              (help-xref-button 1 'help-function handler)))
        ;; FIXME: Obsolete since 24.4.
        (let ((lib (get function 'compiler-macro-file)))
          (when (stringp lib)
            (insert (format " in `%s'" lib))
            (save-excursion
              (re-search-backward "`\\([^`']+\\)'" nil t)
              (help-xref-button 1 'help-function-cmacro function lib)))))
      (insert ".\n"))))

(defun help-fns--signature (function doc real-def real-function)
  (unless (keymapp function)    ; If definition is a keymap, skip arglist note.
    (let* ((advertised (gethash real-def advertised-signature-table t))
           (arglist (if (listp advertised)
                        advertised (help-function-arglist real-def)))
           (usage (help-split-fundoc doc function)))
      (if usage (setq doc (cdr usage)))
      (let* ((use (cond
                   ((and usage (not (listp advertised))) (car usage))
                   ((listp arglist)
                    (format "%S" (help-make-usage function arglist)))
                   ((stringp arglist) arglist)
                   ;; Maybe the arglist is in the docstring of a symbol
                   ;; this one is aliased to.
                   ((let ((fun real-function))
                      (while (and (symbolp fun)
                                  (setq fun (symbol-function fun))
                                  (not (setq usage (help-split-fundoc
                                                    (documentation fun)
                                                    function)))))
                      usage)
                    (car usage))
                   ((or (stringp real-def)
                        (vectorp real-def))
                    (format "\nMacro: %s" (format-kbd-macro real-def)))
                   (t "[Missing arglist.  Please make a bug report.]")))
             (high (help-highlight-arguments use doc)))
        (let ((fill-begin (point)))
          (insert (car high) "\n")
          (fill-region fill-begin (point)))
        (cdr high)))))

(defun help-fns--parent-mode (function)
  ;; If this is a derived mode, link to the parent.
  (let ((parent-mode (and (symbolp function)
                          (get function
                               'derived-mode-parent))))
    (when parent-mode
      (insert "\nParent mode: `")
      (let ((beg (point)))
        (insert (format "%s" parent-mode))
        (make-text-button beg (point)
                          'type 'help-function
                          'help-args (list parent-mode)))
      (insert "'.\n"))))

(defun help-fns--obsolete (function)
  ;; Ignore lambda constructs, keyboard macros, etc.
  (let* ((obsolete (and (symbolp function)
			(get function 'byte-obsolete-info)))
         (use (car obsolete)))
    (when obsolete
      (insert "\nThis "
	      (if (eq (car-safe (symbol-function function)) 'macro)
		  "macro"
		"function")
	      " is obsolete")
      (when (nth 2 obsolete)
        (insert (format " since %s" (nth 2 obsolete))))
      (insert (cond ((stringp use) (concat ";\n" use))
                    (use (format ";\nuse `%s' instead." use))
                    (t "."))
              "\n"))))

;; We could use `symbol-file' but this is a wee bit more efficient.
(defun help-fns--autoloaded-p (function file)
  "Return non-nil if FUNCTION has previously been autoloaded.
FILE is the file where FUNCTION was probably defined."
  (let* ((file (file-name-sans-extension (file-truename file)))
	 (load-hist load-history)
	 (target (cons t function))
	 found)
    (while (and load-hist (not found))
      (and (caar load-hist)
	   (equal (file-name-sans-extension (caar load-hist)) file)
	   (setq found (member target (cdar load-hist))))
      (setq load-hist (cdr load-hist)))
    found))

(defun help-fns--interactive-only (function)
  "Insert some help blurb if FUNCTION should only be used interactively."
  ;; Ignore lambda constructs, keyboard macros, etc.
  (and (symbolp function)
       (not (eq (car-safe (symbol-function function)) 'macro))
       (let* ((interactive-only
               (or (get function 'interactive-only)
                   (if (boundp 'byte-compile-interactive-only-functions)
                       (memq function
                             byte-compile-interactive-only-functions)))))
         (when interactive-only
           (insert "\nThis function is for interactive use only"
                   ;; Cf byte-compile-form.
                   (cond ((stringp interactive-only)
                          (format ";\nin Lisp code %s" interactive-only))
                         ((and (symbolp 'interactive-only)
                               (not (eq interactive-only t)))
                          (format ";\nin Lisp code use `%s' instead."
                                  interactive-only))
                         (t "."))
                   "\n")))))

;;;###autoload
(defun describe-function-1 (function)
  (let* ((advised (and (symbolp function)
		       (featurep 'nadvice)
		       (advice--p (advice--symbol-function function))))
	 ;; If the function is advised, use the symbol that has the
	 ;; real definition, if that symbol is already set up.
	 (real-function
	  (or (and advised
                   (advice--cd*r (advice--symbol-function function)))
	      function))
	 ;; Get the real definition.
	 (def (if (symbolp real-function)
		  (symbol-function real-function)
		real-function))
	 (aliased (or (symbolp def)
		      ;; Advised & aliased function.
		      (and advised (symbolp real-function))))
	 (real-def (cond
		    (aliased (let ((f real-function))
			       (while (and (fboundp f)
					   (symbolp (symbol-function f)))
				 (setq f (symbol-function f)))
			       f))
		    ((subrp def) (intern (subr-name def)))
		    (t def)))
	 (file-name (find-lisp-object-file-name function def))
         (pt1 (with-current-buffer (help-buffer) (point)))
	 (beg (if (and (or (byte-code-function-p def)
			   (keymapp def)
			   (memq (car-safe def) '(macro lambda closure)))
		       (stringp file-name)
		       (help-fns--autoloaded-p function file-name))
		  (if (commandp def)
		      "an interactive autoloaded "
		    "an autoloaded ")
		(if (commandp def) "an interactive " "a "))))

    ;; Print what kind of function-like object FUNCTION is.
    (princ (cond ((or (stringp def) (vectorp def))
		  "a keyboard macro")
		 ((subrp def)
		  (if (eq 'unevalled (cdr (subr-arity def)))
		      (concat beg "special form")
		    (concat beg "built-in function")))
		 ;; Aliases are Lisp functions, so we need to check
		 ;; aliases before functions.
		 (aliased
		  (format "an alias for `%s'" real-def))
		 ((autoloadp def)
		  (format "%s autoloaded %s"
			  (if (commandp def) "an interactive" "an")
			  (if (eq (nth 4 def) 'keymap) "keymap"
			    (if (nth 4 def) "Lisp macro" "Lisp function"))))
		 ((or (eq (car-safe def) 'macro)
		      ;; For advised macros, def is a lambda
		      ;; expression or a byte-code-function-p, so we
		      ;; need to check macros before functions.
		      (macrop function))
		  (concat beg "Lisp macro"))
		 ((byte-code-function-p def)
		  (concat beg "compiled Lisp function"))
		 ((eq (car-safe def) 'lambda)
		  (concat beg "Lisp function"))
		 ((eq (car-safe def) 'closure)
		  (concat beg "Lisp closure"))
		 ((keymapp def)
		  (let ((is-full nil)
			(elts (cdr-safe def)))
		    (while elts
		      (if (char-table-p (car-safe elts))
			  (setq is-full t
				elts nil))
		      (setq elts (cdr-safe elts)))
		    (concat beg (if is-full "keymap" "sparse keymap"))))
		 (t "")))

    (if (and aliased (not (fboundp real-def)))
	(princ ",\nwhich is not defined.  Please make a bug report.")
      (with-current-buffer standard-output
	(save-excursion
	  (save-match-data
	    (when (re-search-backward "alias for `\\([^`']+\\)'" nil t)
	      (help-xref-button 1 'help-function real-def)))))

      (when file-name
	(princ " in `")
	;; We used to add .el to the file name,
	;; but that's completely wrong when the user used load-file.
	(princ (if (eq file-name 'C-source)
		   "C source code"
		 (file-name-nondirectory file-name)))
	(princ "'")
	;; Make a hyperlink to the library.
	(with-current-buffer standard-output
	  (save-excursion
	    (re-search-backward "`\\([^`']+\\)'" nil t)
	    (help-xref-button 1 'help-function-def function file-name))))
      (princ ".")
      (with-current-buffer (help-buffer)
	(fill-region-as-paragraph (save-excursion (goto-char pt1) (forward-line 0) (point))
				  (point)))
      (terpri)(terpri)

      (let* ((doc-raw (documentation function t))
	     ;; If the function is autoloaded, and its docstring has
	     ;; key substitution constructs, load the library.
	     (doc (progn
		    (and (autoloadp real-def) doc-raw
			 help-enable-auto-load
			 (string-match "\\([^\\]=\\|[^=]\\|\\`\\)\\\\[[{<]"
				       doc-raw)
			 (load (cadr real-def) t))
		    (substitute-command-keys doc-raw))))

        (help-fns--key-bindings function)
        (with-current-buffer standard-output
          (setq doc (help-fns--signature function doc real-def real-function))
	  (run-hook-with-args 'help-fns-describe-function-functions function)
          (insert "\n"
                  (or doc "Not documented.")))))))

;; Add defaults to `help-fns-describe-function-functions'.
(add-hook 'help-fns-describe-function-functions #'help-fns--obsolete)
(add-hook 'help-fns-describe-function-functions #'help-fns--interactive-only)
(add-hook 'help-fns-describe-function-functions #'help-fns--parent-mode)
(add-hook 'help-fns-describe-function-functions #'help-fns--compiler-macro)


;; Variables

;;;###autoload
(defun variable-at-point (&optional any-symbol)
  "Return the bound variable symbol found at or before point.
Return 0 if there is no such symbol.
If ANY-SYMBOL is non-nil, don't insist the symbol be bound."
  (with-syntax-table emacs-lisp-mode-syntax-table
    (or (condition-case ()
	    (save-excursion
	      (skip-chars-forward "'")
	      (or (not (zerop (skip-syntax-backward "_w")))
		  (eq (char-syntax (following-char)) ?w)
		  (eq (char-syntax (following-char)) ?_)
		  (forward-sexp -1))
	      (skip-chars-forward "'")
	      (let ((obj (read (current-buffer))))
		(and (symbolp obj) (boundp obj) obj)))
          (error nil))
        (let* ((str (find-tag-default))
               (sym (if str (intern-soft str))))
          (if (and sym (or any-symbol (boundp sym)))
              sym
            (save-match-data
              (when (and str (string-match "\\`\\W*\\(.*?\\)\\W*\\'" str))
                (setq sym (intern-soft (match-string 1 str)))
                (and (or any-symbol (boundp sym)) sym)))))
        0)))

(defun describe-variable-custom-version-info (variable)
  (let ((custom-version (get variable 'custom-version))
	(cpv (get variable 'custom-package-version))
	(output nil))
    (if custom-version
	(setq output
	      (format "This variable was introduced, or its default value was changed, in\nversion %s of Emacs.\n"
		      custom-version))
      (when cpv
	(let* ((package (car-safe cpv))
	       (version (if (listp (cdr-safe cpv))
			    (car (cdr-safe cpv))
			  (cdr-safe cpv)))
	       (pkg-versions (assq package customize-package-emacs-version-alist))
	       (emacsv (cdr (assoc version pkg-versions))))
	  (if (and package version)
	      (setq output
		    (format (concat "This variable was introduced, or its default value was changed, in\nversion %s of the %s package"
				    (if emacsv
					(format " that is part of Emacs %s" emacsv))
				    ".\n")
			    version package))))))
    output))

;;;###autoload
(defun describe-variable (variable &optional buffer frame)
  "Display the full documentation of VARIABLE (a symbol).
Returns the documentation as a string, also.
If VARIABLE has a buffer-local value in BUFFER or FRAME
\(default to the current buffer and current frame),
it is displayed along with the global value."
  (interactive
   (let ((v (variable-at-point))
	 (enable-recursive-minibuffers t)
	 val)
     (setq val (completing-read (if (symbolp v)
				    (format
				     "Describe variable (default %s): " v)
				  "Describe variable: ")
				obarray
				(lambda (vv)
                                  (or (get vv 'variable-documentation)
                                      (and (boundp vv) (not (keywordp vv)))))
				t nil nil
				(if (symbolp v) (symbol-name v))))
     (list (if (equal val "")
	       v (intern val)))))
  (let (file-name)
    (unless (buffer-live-p buffer) (setq buffer (current-buffer)))
    (unless (frame-live-p frame) (setq frame (selected-frame)))
    (if (not (symbolp variable))
	(message "You did not specify a variable")
      (save-excursion
	(let ((valvoid (not (with-current-buffer buffer (boundp variable))))
	      (permanent-local (get variable 'permanent-local))
	      val val-start-pos locus)
	  ;; Extract the value before setting up the output buffer,
	  ;; in case `buffer' *is* the output buffer.
	  (unless valvoid
	    (with-selected-frame frame
	      (with-current-buffer buffer
		(setq val (symbol-value variable)
		      locus (variable-binding-locus variable)))))
	  (help-setup-xref (list #'describe-variable variable buffer)
			   (called-interactively-p 'interactive))
	  (with-help-window (help-buffer)
	    (with-current-buffer buffer
	      (prin1 variable)
	      (setq file-name (find-lisp-object-file-name variable 'defvar))

	      (if file-name
		  (progn
		    (princ " is a variable defined in `")
		    (princ (if (eq file-name 'C-source)
			       "C source code"
			     (file-name-nondirectory file-name)))
		    (princ "'.\n")
		    (with-current-buffer standard-output
		      (save-excursion
			(re-search-backward "`\\([^`']+\\)'" nil t)
			(help-xref-button 1 'help-variable-def
					  variable file-name)))
		    (if valvoid
			(princ "It is void as a variable.")
		      (princ "Its ")))
		(if valvoid
		    (princ " is void as a variable.")
		  (princ "'s "))))
	    (unless valvoid
	      (with-current-buffer standard-output
		(setq val-start-pos (point))
		(princ "value is ")
		(let ((from (point))
		      (line-beg (line-beginning-position))
		      (print-rep
		       (let ((print-quoted t))
			 (prin1-to-string val))))
		  (if (< (+ (length print-rep) (point) (- line-beg)) 68)
		      (insert print-rep)
		    (terpri)
		    (pp val)
		    (if (< (point) (+ 68 (line-beginning-position 0)))
			(delete-region from (1+ from))
		      (delete-region (1- from) from)))
		  (let* ((sv (get variable 'standard-value))
			 (origval (and (consp sv)
				       (condition-case nil
					   (eval (car sv))
					 (error :help-eval-error)))))
		    (when (and (consp sv)
                               (not (equal origval val))
                               (not (equal origval :help-eval-error)))
		      (princ "\nOriginal value was \n")
		      (setq from (point))
		      (pp origval)
		      (if (< (point) (+ from 20))
			  (delete-region (1- from) from)))))))
	    (terpri)
	    (when locus
	      (cond
               ((bufferp locus)
                (princ (format "Local in buffer %s; "
                               (buffer-name buffer))))
               ((framep locus)
                (princ (format "It is a frame-local variable; ")))
               ((terminal-live-p locus)
                (princ (format "It is a terminal-local variable; ")))
               (t
                (princ (format "It is local to %S" locus))))
	      (if (not (default-boundp variable))
		  (princ "globally void")
		(let ((global-val (default-value variable)))
		  (with-current-buffer standard-output
		    (princ "global value is ")
		    (if (eq val global-val)
			(princ "the same.")
		      (terpri)
		      ;; Fixme: pp can take an age if you happen to
		      ;; ask for a very large expression.  We should
		      ;; probably print it raw once and check it's a
		      ;; sensible size before prettyprinting.  -- fx
		      (let ((from (point)))
			(pp global-val)
			;; See previous comment for this function.
			;; (help-xref-on-pp from (point))
			(if (< (point) (+ from 20))
			    (delete-region (1- from) from)))))))
              (terpri))

	    ;; If the value is large, move it to the end.
	    (with-current-buffer standard-output
	      (when (> (count-lines (point-min) (point-max)) 10)
		;; Note that setting the syntax table like below
		;; makes forward-sexp move over a `'s' at the end
		;; of a symbol.
		(set-syntax-table emacs-lisp-mode-syntax-table)
		(goto-char val-start-pos)
		;; The line below previously read as
		;; (delete-region (point) (progn (end-of-line) (point)))
		;; which suppressed display of the buffer local value for
		;; large values.
		(when (looking-at "value is") (replace-match ""))
		(save-excursion
		  (insert "\n\nValue:")
		  (set (make-local-variable 'help-button-cache)
		       (point-marker)))
		(insert "value is shown ")
		(insert-button "below"
			       'action help-button-cache
			       'follow-link t
			       'help-echo "mouse-2, RET: show value")
		(insert ".\n")))
            (terpri)

            (let* ((alias (condition-case nil
                              (indirect-variable variable)
                            (error variable)))
                   (obsolete (get variable 'byte-obsolete-variable))
		   (use (car obsolete))
		   (safe-var (get variable 'safe-local-variable))
                   (doc (or (documentation-property
                             variable 'variable-documentation)
                            (documentation-property
                             alias 'variable-documentation)))
                   (extra-line nil))

	      ;; Mention if it's a local variable.
	      (cond
	       ((and (local-variable-if-set-p variable)
		     (or (not (local-variable-p variable))
			 (with-temp-buffer
			   (local-variable-if-set-p variable))))
                (setq extra-line t)
                (princ "  Automatically becomes ")
		(if permanent-local
		    (princ "permanently "))
		(princ "buffer-local when set.\n"))
	       ((not permanent-local))
	       ((bufferp locus)
		(setq extra-line t)
		(princ "  This variable's buffer-local value is permanent.\n"))
	       (t
		(setq extra-line t)
                (princ "  This variable's value is permanent \
if it is given a local binding.\n")))

	      ;; Mention if it's an alias.
              (unless (eq alias variable)
                (setq extra-line t)
                (princ (format "  This variable is an alias for `%s'.\n" alias)))

              (when obsolete
                (setq extra-line t)
                (princ "  This variable is obsolete")
                (if (nth 2 obsolete)
                    (princ (format " since %s" (nth 2 obsolete))))
		(princ (cond ((stringp use) (concat ";\n  " use))
			     (use (format ";\n  use `%s' instead." (car obsolete)))
			     (t ".")))
                (terpri))

	      (when (member (cons variable val)
                            (with-current-buffer buffer
                              file-local-variables-alist))
		(setq extra-line t)
		(if (member (cons variable val)
                             (with-current-buffer buffer
                               dir-local-variables-alist))
		    (let ((file (and (buffer-file-name buffer)
                                      (not (file-remote-p
                                            (buffer-file-name buffer)))
                                      (dir-locals-find-file
                                       (buffer-file-name buffer))))
                          (dir-file t))
		      (princ "  This variable's value is directory-local")
		      (if (null file)
			  (princ ".\n")
			(princ ", set ")
                        (if (consp file) ; result from cache
                            ;; If the cache element has an mtime, we
                            ;; assume it came from a file.
                            (if (nth 2 file)
                                (setq file (expand-file-name
                                            dir-locals-file (car file)))
                              ;; Otherwise, assume it was set directly.
                              (setq file (car file)
                                    dir-file nil)))
			(princ (if dir-file
				   "by the file\n  `"
				 "for the directory\n  `"))
			(with-current-buffer standard-output
			  (insert-text-button
			   file 'type 'help-dir-local-var-def
			   'help-args (list variable file)))
			(princ "'.\n")))
		  (princ "  This variable's value is file-local.\n")))

	      (when (memq variable ignored-local-variables)
		(setq extra-line t)
		(princ "  This variable is ignored as a file-local \
variable.\n"))

	      ;; Can be both risky and safe, eg auto-fill-function.
	      (when (risky-local-variable-p variable)
		(setq extra-line t)
		(princ "  This variable may be risky if used as a \
file-local variable.\n")
		(when (assq variable safe-local-variable-values)
		  (princ "  However, you have added it to \
`safe-local-variable-values'.\n")))

	      (when safe-var
                (setq extra-line t)
		(princ "  This variable is safe as a file local variable ")
		(princ "if its value\n  satisfies the predicate ")
		(princ (if (byte-code-function-p safe-var)
			   "which is a byte-compiled expression.\n"
			 (format "`%s'.\n" safe-var))))

              (if extra-line (terpri))
	      (princ "Documentation:\n")
	      (with-current-buffer standard-output
		(insert (or doc "Not documented as a variable."))))

	    ;; Make a link to customize if this variable can be customized.
	    (when (custom-variable-p variable)
	      (let ((customize-label "customize"))
		(terpri)
		(terpri)
		(princ (concat "You can " customize-label " this variable."))
		(with-current-buffer standard-output
		  (save-excursion
		    (re-search-backward
		     (concat "\\(" customize-label "\\)") nil t)
		    (help-xref-button 1 'help-customize-variable variable))))
	      ;; Note variable's version or package version
	      (let ((output (describe-variable-custom-version-info variable)))
		(when output
		  (terpri)
		  (terpri)
		  (princ output))))

	    (with-current-buffer standard-output
	      ;; Return the text we displayed.
	      (buffer-string))))))))


;;;###autoload
(defun describe-syntax (&optional buffer)
  "Describe the syntax specifications in the syntax table of BUFFER.
The descriptions are inserted in a help buffer, which is then displayed.
BUFFER defaults to the current buffer."
  (interactive)
  (setq buffer (or buffer (current-buffer)))
  (help-setup-xref (list #'describe-syntax buffer)
		   (called-interactively-p 'interactive))
  (with-help-window (help-buffer)
    (let ((table (with-current-buffer buffer (syntax-table))))
      (with-current-buffer standard-output
	(describe-vector table 'internal-describe-syntax-value)
	(while (setq table (char-table-parent table))
	  (insert "\nThe parent syntax table is:")
	  (describe-vector table 'internal-describe-syntax-value))))))

(defun help-describe-category-set (value)
  (insert (cond
	   ((null value) "default")
	   ((char-table-p value) "deeper char-table ...")
	   (t (condition-case nil
		  (category-set-mnemonics value)
		(error "invalid"))))))

;;;###autoload
(defun describe-categories (&optional buffer)
  "Describe the category specifications in the current category table.
The descriptions are inserted in a buffer, which is then displayed.
If BUFFER is non-nil, then describe BUFFER's category table instead.
BUFFER should be a buffer or a buffer name."
  (interactive)
  (setq buffer (or buffer (current-buffer)))
  (help-setup-xref (list #'describe-categories buffer)
		   (called-interactively-p 'interactive))
  (with-help-window (help-buffer)
    (let* ((table (with-current-buffer buffer (category-table)))
	   (docs (char-table-extra-slot table 0)))
      (if (or (not (vectorp docs)) (/= (length docs) 95))
	  (error "Invalid first extra slot in this category table\n"))
      (with-current-buffer standard-output
	(insert "Legend of category mnemonics (see the tail for the longer description)\n")
	(let ((pos (point)) (items 0) lines n)
	  (dotimes (i 95)
	    (if (aref docs i) (setq items (1+ items))))
	  (setq lines (1+ (/ (1- items) 4)))
	  (setq n 0)
	  (dotimes (i 95)
	    (let ((elt (aref docs i)))
	      (when elt
		(string-match ".*" elt)
		(setq elt (match-string 0 elt))
		(if (>= (length elt) 17)
		    (setq elt (concat (substring elt 0 14) "...")))
		(if (< (point) (point-max))
		    (move-to-column (* 20 (/ n lines)) t))
		(insert (+ i ?\s) ?: elt)
		(if (< (point) (point-max))
		    (forward-line 1)
		  (insert "\n"))
		(setq n (1+ n))
		(if (= (% n lines) 0)
		    (goto-char pos))))))
	(goto-char (point-max))
	(insert "\n"
		"character(s)\tcategory mnemonics\n"
		"------------\t------------------")
	(describe-vector table 'help-describe-category-set)
	(insert "Legend of category mnemonics:\n")
	(dotimes (i 95)
	  (let ((elt (aref docs i)))
	    (when elt
	      (if (string-match "\n" elt)
		  (setq elt (substring elt (match-end 0))))
	      (insert (+ i ?\s) ": " elt "\n"))))
	(while (setq table (char-table-parent table))
	  (insert "\nThe parent category table is:")
	  (describe-vector table 'help-describe-category-set))))))


;;; Replacements for old lib-src/ programs.  Don't seem especially useful.

;; Replaces lib-src/digest-doc.c.
;;;###autoload
(defun doc-file-to-man (file)
  "Produce an nroff buffer containing the doc-strings from the DOC file."
  (interactive (list (read-file-name "Name of DOC file: " doc-directory
                                     internal-doc-file-name t)))
  (or (file-readable-p file)
      (error "Cannot read file `%s'" file))
  (pop-to-buffer (generate-new-buffer "*man-doc*"))
  (setq buffer-undo-list t)
  (insert ".TH \"Command Summary for GNU Emacs\"\n"
          ".AU Richard M. Stallman\n")
  (insert-file-contents file)
  (let (notfirst)
    (while (search-forward "" nil 'move)
      (if (looking-at "S")
          (delete-region (1- (point)) (line-end-position))
        (delete-char -1)
        (if notfirst
            (insert "\n.DE\n")
          (setq notfirst t))
        (insert "\n.SH ")
        (insert (if (looking-at "F") "Function " "Variable "))
        (delete-char 1)
        (forward-line 1)
        (insert ".DS L\n"))))
  (insert "\n.DE\n")
  (setq buffer-undo-list nil)
  (nroff-mode))

;; Replaces lib-src/sorted-doc.c.
;;;###autoload
(defun doc-file-to-info (file)
  "Produce a texinfo buffer with sorted doc-strings from the DOC file."
  (interactive (list (read-file-name "Name of DOC file: " doc-directory
                                     internal-doc-file-name t)))
  (or (file-readable-p file)
      (error "Cannot read file `%s'" file))
  (let ((i 0) type name doc alist)
    (with-temp-buffer
      (insert-file-contents file)
      ;; The characters "@{}" need special treatment.
      (while (re-search-forward "[@{}]" nil t)
        (backward-char)
        (insert "@")
        (forward-char 1))
      (goto-char (point-min))
      (while (search-forward "" nil t)
        (unless (looking-at "S")
          (setq type (char-after)
                name (buffer-substring (1+ (point)) (line-end-position))
                doc (buffer-substring (line-beginning-position 2)
                                      (if (search-forward  "" nil 'move)
                                          (1- (point))
                                        (point)))
                alist (cons (list name type doc) alist))
          (backward-char 1))))
    (pop-to-buffer (generate-new-buffer "*info-doc*"))
    (setq buffer-undo-list t)
    ;; Write the output header.
    (insert "\\input texinfo  @c -*-texinfo-*-\n"
            "@setfilename emacsdoc.info\n"
            "@settitle Command Summary for GNU Emacs\n"
            "@finalout\n"
            "\n@node Top\n"
            "@unnumbered Command Summary for GNU Emacs\n\n"
            "@table @asis\n\n"
            "@iftex\n"
            "@global@let@ITEM@item\n"
            "@def@item{@filbreak@vskip5pt@ITEM}\n"
            "@font@tensy cmsy10 scaled @magstephalf\n"
            "@font@teni cmmi10 scaled @magstephalf\n"
            "@def\\{{@tensy@char110}}\n" ; this backslash goes with cmr10
            "@def|{{@tensy@char106}}\n"
            "@def@{{{@tensy@char102}}\n"
            "@def@}{{@tensy@char103}}\n"
            "@def<{{@teni@char62}}\n"
            "@def>{{@teni@char60}}\n"
            "@chardef@@64\n"
            "@catcode43=12\n"
            "@tableindent-0.2in\n"
            "@end iftex\n")
    ;; Sort the array by name; within each name, by type (functions first).
    (setq alist (sort alist (lambda (e1 e2)
                              (if (string-equal (car e1) (car e2))
                                  (<= (cadr e1) (cadr e2))
                                (string-lessp (car e1) (car e2))))))
    ;; Print each function.
    (dolist (e alist)
      (insert "\n@item "
              (if (char-equal (cadr e) ?\F) "Function" "Variable")
              " @code{" (car e) "}\n@display\n"
              (nth 2 e)
              "\n@end display\n")
      ;; Try to avoid a save size overflow in the TeX output routine.
      (if (zerop (setq i (% (1+ i) 100)))
          (insert "\n@end table\n@table @asis\n")))
    (insert "@end table\n"
            "@bye\n")
    (setq buffer-undo-list nil)
    (texinfo-mode)))

(provide 'help-fns)

;;; help-fns.el ends here
