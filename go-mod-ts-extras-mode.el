;;; go-mod-ts-extras-mode.el --- pkg.go.dev extras for go-mod-ts-mode -*- lexical-binding: t -*-

;; Copyright (C) 2026  Daniel Nagy

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public
;; License along with this file.  If not, see
;; <https://www.gnu.org/licenses/>.

;; Author: Daniel Nagy
;; Version: 0.1.0
;; Keywords: languages, tools
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/nagy/go-mod-ts-extras-mode

;;; Commentary:

;; This package provides `go-mod-ts-extras-mode', a minor mode that adds
;; go.mod-specific enhancements to `go-mod-ts-mode' buffers:
;;
;;   - URL detection: `thing-at-point' for 'url returns the pkg.go.dev
;;     page for the Go module path under point.
;;
;;   - Filename detection: `thing-at-point' for 'filename returns the
;;     local module cache directory for the module under point.
;;
;;   - Underline highlighting: module_path nodes inside require and
;;     replace specs are underlined via treesit font-lock rules.
;;
;; Usage:
;;     (add-hook 'go-mod-ts-mode-hook #'go-mod-ts-extras-mode)
;;
;; Or manually:  M-x go-mod-ts-extras-mode RET

;;; Code:

(require 'go-ts-mode)
(require 'thingatpt)
(require 'cl-lib)
(require 'treesit)

(defgroup go-mod-ts-extras nil
  "go.mod extras for `go-mod-ts-mode'."
  :group 'go
  :prefix "go-mod-ts-extras-")

(defcustom go-mod-ts-extras-pkg-url-template
  "https://pkg.go.dev/%s@%s"
  "URL template for Go module packages.
`%s' placeholders receive the module path and version, respectively."
  :type 'string
  :group 'go-mod-ts-extras)

(defcustom go-mod-ts-extras-pkg-file-prefix nil
  "Directory prefix for Go module file paths.
If nil, the value of the GOMODCACHE environment variable is used,
falling back to $GOPATH/pkg/mod and then ~/go/pkg/mod/."
  :type '(choice (const :tag "GOMODCACHE or ~/go/pkg/mod" nil)
                 (directory :tag "Custom prefix"))
  :group 'go-mod-ts-extras)

(defun go-mod-ts-extras--pkg-file-prefix ()
  "Return the Go module cache directory prefix, with trailing slash."
  (file-name-as-directory
   (or go-mod-ts-extras-pkg-file-prefix
       (getenv "GOMODCACHE")
       (let ((gopath (or (getenv "GOPATH")
                         (expand-file-name "~/go"))))
         (expand-file-name "pkg/mod/" gopath)))))

(defcustom go-mod-ts-extras-highlight-modules t
  "When non-nil, underline module paths in require/replace specs."
  :type 'boolean
  :group 'go-mod-ts-extras)

(defface go-mod-ts-extras-module-path-face
  '((t :underline t))
  "Face for module paths inside require/replace specs."
  :group 'go-mod-ts-extras)

(defvar go-mod-ts-extras--font-lock-rules
  (treesit-font-lock-rules
   :language 'gomod
   :override t
   :feature 'go-mod-extras
   '((require_spec (module_path) @go-mod-ts-extras-module-path-face)
     (replace_spec (module_path) @go-mod-ts-extras-module-path-face)))
  "Treesit font-lock rules for go.mod module-path highlighting.")

;;; Tree-sitter helpers

(defun go-mod-ts-extras--find-spec-node (node)
  "Walk up from NODE to find a require_spec or replace_spec ancestor.
Returns the spec node, or nil."
  (treesit-parent-until
   node
   (lambda (n)
     (member (treesit-node-type n) '("require_spec" "replace_spec")))))

(defun go-mod-ts-extras--spec-module-path-node (spec-node &optional point-node)
  "Return the module_path node from SPEC-NODE that POINT-NODE falls within.
For require_spec, returns the first (only) module_path.
For replace_spec, returns the second (replacement) module_path if POINT-NODE
is on it, on its version, or after it (i.e. the `=> new' side); returns nil
when POINT-NODE is on the original (first) module_path or its version."
  (let ((type (treesit-node-type spec-node)))
    (cond
     ((equal type "require_spec")
      (let ((mp (treesit-node-child spec-node 0 t)))
        (when (and mp (equal (treesit-node-type mp) "module_path"))
          mp)))
     ((equal type "replace_spec")
      (let ((mp-nodes (treesit-filter-child
                       spec-node
                       (lambda (n) (equal (treesit-node-type n) "module_path")))))
        (when (>= (length mp-nodes) 2)
          (let ((replacement (nth 1 mp-nodes)))
            (when (or (not point-node)
                      (>= (treesit-node-start point-node)
                          (treesit-node-start replacement)))
              replacement)))))
     (t nil))))

(defun go-mod-ts-extras--find-version-after (parent after-node)
  "Return the first version child of PARENT that starts at or after AFTER-NODE.
Returns the node, or nil."
  (catch 'found
    (dolist (child (treesit-node-children parent))
      (when (and (equal (treesit-node-type child) "version")
                 (>= (treesit-node-start child) (treesit-node-end after-node)))
        (throw 'found child)))))

;;; GOPRIVATE glob matching

(defun go-mod-ts-extras--glob-to-regexp (pattern)
  "Convert a Go `path.Match' PATTERN to an Emacs regexp.
In Go's path.Match, `*' matches any sequence of non-`/' characters,
`?' matches any single non-`/' character, and other regexp-special
characters are matched literally."
  (let ((re "")
        (i 0)
        (len (length pattern)))
    (while (< i len)
      (let ((c (aref pattern i)))
        (cl-incf i)
        (cond
         ((eq c ?*) (setq re (concat re "[^/]*")))
         ((eq c ??) (setq re (concat re "[^/]")))
         ((eq c ?\\)
          (when (< i len)
            (setq re (concat re (regexp-quote (string (aref pattern i)))))
            (cl-incf i)))
         ((member c '(?\[ ?\] ?^ ?$ ?. ?+ ?\( ?\) ?\{ ?\} ?|))
          (setq re (concat re "\\" (string c))))
         (t (setq re (concat re (string c)))))))
    (concat "\\`" re "\\(/.*\\)?\\'")))

(defun go-mod-ts-extras--private-p (module-path)
  "Return non-nil if MODULE-PATH matches a GOPRIVATE pattern.
GOPRIVATE is a comma-separated list of glob patterns in Go's
`path.Match' syntax, where `*' does not match `/'."
  (when-let* ((goprivate (getenv "GOPRIVATE")))
    (cl-some (lambda (pat)
               (string-match-p (go-mod-ts-extras--glob-to-regexp pat)
                               module-path))
             (split-string goprivate "," t " "))))

;;; Module cache path

(defun go-mod-ts-extras--module-cache-path (module-path version)
  "Return the filesystem path for MODULE-PATH@VERSION in the Go module cache.
Go's module cache escapes uppercase letters as `!lowercase' (module.EscapePath).
Note: this matches the cache directory naming for module paths, but is a
heuristic for full paths: pseudo-versions escape `+' as `!pseudo' and literal
`!' characters are doubled, which this does not account for."
  (concat (go-mod-ts-extras--pkg-file-prefix)
          (let ((case-fold-search nil))
            (replace-regexp-in-string
             "[A-Z]"
             (lambda (c) (concat "!" (downcase c)))
             module-path t t))
          "@" version "/"))

;;; Thing-at-point providers

(defvar go-mod-ts-extras-mode)

(defun go-mod-ts-extras--spec-info ()
  "Return (module-path . version) for the module at point, or nil.
For replace_spec, only the replacement (second) module_path qualifies.
The version is the one that follows the relevant module_path node,
fixing the bug where a replace spec `old v1 => new v2' returned v1."
  (when (and go-mod-ts-extras-mode
             (derived-mode-p 'go-mod-ts-mode)
             (treesit-ready-p 'gomod))
    (when-let* ((node (treesit-node-at (point)))
                (spec (go-mod-ts-extras--find-spec-node node))
                (mp-node (go-mod-ts-extras--spec-module-path-node spec node))
                (module-path (treesit-node-text mp-node))
                (ver-node (go-mod-ts-extras--find-version-after spec mp-node))
                (version (treesit-node-text ver-node)))
      (cons module-path version))))

(defun go-mod-ts-extras--url-provider ()
  "Return a pkg.go.dev URL if point is on a module_path in a require/replace spec.
Returns nil for private modules (matching GOPRIVATE)."
  (when-let* ((spec (go-mod-ts-extras--spec-info))
              ((not (go-mod-ts-extras--private-p (car spec)))))
    (format go-mod-ts-extras-pkg-url-template
            (car spec) (cdr spec))))

(defun go-mod-ts-extras--filename-provider ()
  "Return a local file path if point is on a module_path in a require/replace spec.
The path respects Go's module cache escaping (uppercase → !lowercase).
For a replace spec targeting a local directory (`replace a => ./dir'),
returns that directory itself."
  (when (and go-mod-ts-extras-mode
             (derived-mode-p 'go-mod-ts-mode)
             (treesit-ready-p 'gomod))
    (or
     ;; Local-directory replace target: `replace a => ./dir'.
     (when-let* ((node (treesit-node-at (point)))
                 ((equal (treesit-node-type node) "file_path"))
                 (spec (go-mod-ts-extras--find-spec-node node))
                 ((equal (treesit-node-type spec) "replace_spec")))
       (treesit-node-text node))
     ;; Module cache path for the module under point.
     (when-let* ((spec (go-mod-ts-extras--spec-info)))
       (go-mod-ts-extras--module-cache-path (car spec) (cdr spec))))))

(defun go-mod-ts-extras--bounds-of-thing-at-point ()
  "Return (START . END) for the module_path under point, or nil."
  (when (and go-mod-ts-extras-mode
             (derived-mode-p 'go-mod-ts-mode)
             (treesit-ready-p 'gomod))
    (when-let* ((node (treesit-node-at (point)))
                (spec (go-mod-ts-extras--find-spec-node node))
                (mp-node (go-mod-ts-extras--spec-module-path-node spec node)))
      (cons (treesit-node-start mp-node)
            (treesit-node-end mp-node)))))



;;; Minor mode

;;;###autoload
(defun go-mod-ts-extras-browse-at-point ()
  "Open the pkg.go.dev URL for the module path at point in a browser.
Not bound to any key by default; bind it yourself or use \\[execute-extended-command]."
  (interactive)
  (if-let* ((url (thing-at-point 'url)))
      (browse-url url)
    (user-error "No module URL at point")))

;;;###autoload
(define-minor-mode go-mod-ts-extras-mode
  "Minor mode for go.mod enhancements in `go-mod-ts-mode' buffers.

When enabled, this mode:
  - Underlines module paths in require and replace specs.
  - Makes `thing-at-point' return pkg.go.dev URLs for those paths.
  - Makes `thing-at-point' return local module cache paths."
  :lighter " go.mod+"
  (if go-mod-ts-extras-mode
      (go-mod-ts-extras--enable)
    (go-mod-ts-extras--disable)))

(defun go-mod-ts-extras--enable ()
  "Register thing-at-point providers and treesit font-lock rules."
  ;; Thing-at-point providers (url and filename).
  ;; Remove-first-then-add for idempotency; use exact-pair removal so
  ;; other packages' providers are not deleted.
  (setq-local thing-at-point-provider-alist
              (cons '(url . go-mod-ts-extras--url-provider)
                    (cons '(filename . go-mod-ts-extras--filename-provider)
                          (remove '(url . go-mod-ts-extras--url-provider)
                                  (remove '(filename . go-mod-ts-extras--filename-provider)
                                          thing-at-point-provider-alist)))))

  ;; Bounds providers (Emacs 30.1+).
  (setq-local bounds-of-thing-at-point-provider-alist
              (cons '(url . go-mod-ts-extras--bounds-of-thing-at-point)
                    (remove '(url . go-mod-ts-extras--bounds-of-thing-at-point)
                            bounds-of-thing-at-point-provider-alist)))
  ;; Treesit font-lock rules using the Emacs 30.1 API, which correctly
  ;; appends the feature without shifting existing features.
  (when go-mod-ts-extras-highlight-modules
    (treesit-add-font-lock-rules
     go-mod-ts-extras--font-lock-rules)
    (treesit-font-lock-recompute-features)
    (font-lock-flush)
    (font-lock-ensure)))

(defun go-mod-ts-extras--disable ()
  "Unregister thing-at-point providers and treesit font-lock rules."
  ;; Thing-at-point providers.  Remove our exact pairs only.
  (setq-local thing-at-point-provider-alist
              (remove '(url . go-mod-ts-extras--url-provider)
                      thing-at-point-provider-alist))
  (setq-local thing-at-point-provider-alist
              (remove '(filename . go-mod-ts-extras--filename-provider)
                      thing-at-point-provider-alist))

  ;; Bounds providers.
  (setq-local bounds-of-thing-at-point-provider-alist
              (remove '(url . go-mod-ts-extras--bounds-of-thing-at-point)
                      bounds-of-thing-at-point-provider-alist))
  ;; Treesit font-lock rules.  Identify our setting by the feature
  ;; symbol at position 2 in the list (QUERY ENABLE FEATURE OVERRIDE ...).
  (when go-mod-ts-extras-highlight-modules
    (setq-local treesit-font-lock-settings
                (cl-remove 'go-mod-extras treesit-font-lock-settings
                           :key (lambda (s) (nth 2 s))))
    (treesit-font-lock-recompute-features)
    (font-lock-flush)
    (font-lock-ensure)))

(provide 'go-mod-ts-extras-mode)
;;; go-mod-ts-extras-mode.el ends here
