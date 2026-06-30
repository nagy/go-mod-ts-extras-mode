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

;;; Commentary:

;; This package provides `go-mod-ts-extras-mode', a minor mode that adds
;; go.mod-specific enhancements to `go-mod-ts-mode' buffers:
;;
;;   - URL detection: `thing-at-point' for 'url returns the pkg.go.dev
;;     page for the Go module whose module_path is under point.
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
falling back to ~/go/pkg/mod/."
  :type '(choice (const :tag "GOMODCACHE or ~/go/pkg/mod" nil)
                 (directory :tag "Custom prefix"))
  :group 'go-mod-ts-extras)

(defun go-mod-ts-extras--pkg-file-prefix ()
  "Return the Go module cache directory prefix, with trailing slash."
  (file-name-as-directory
   (or go-mod-ts-extras-pkg-file-prefix
       (getenv "GOMODCACHE")
       (expand-file-name "~/go/pkg/mod/"))))

(defcustom go-mod-ts-extras-highlight-modules t
  "When non-nil, underline module paths in require/replace specs."
  :type 'boolean
  :group 'go-mod-ts-extras)

(defface go-mod-ts-extras-module-path-face
  '((t :underline t))
  "Face for module paths inside require/replace specs."
  :group 'go-mod-ts-extras)


;;; Treesit font-lock rules

(defvar go-mod-ts-extras--font-lock-rules
  (treesit-font-lock-rules
   :language 'gomod
   :override t
   :feature 'go-mod-extras
   '((require_spec (module_path) @go-mod-ts-extras-module-path-face)
     (replace_spec (module_path) @go-mod-ts-extras-module-path-face)))
  "Treesit font-lock rules for go.mod module-path highlighting.")


;;; Tree-sitter helpers (for URL provider)

(defun go-mod-ts-extras--find-spec-node (node)
  "Walk up from NODE to find a require_spec or replace_spec ancestor.
Returns the spec node, or nil."
  (treesit-parent-until
   node
   (lambda (n)
     (member (treesit-node-type n) '("require_spec" "replace_spec")))))

(defun go-mod-ts-extras--spec-version (spec-node)
  "Return the version string from SPEC-NODE, or nil."
  (catch 'found
    (dolist (child (treesit-node-children spec-node))
      (when (equal (treesit-node-type child) "version")
        (throw 'found (treesit-node-text child))))))


;;; Thing-at-point providers

(defvar go-mod-ts-extras-mode)

(defun go-mod-ts-extras--spec-info ()
  "Return (module-path . version) for the module at point, or nil.
For replace_spec, only the replacement (second) module_path qualifies."
  (when (and go-mod-ts-extras-mode
             (derived-mode-p 'go-mod-ts-mode)
             (treesit-ready-p 'gomod))
    (when-let* ((node (treesit-node-at (point)))
                (spec (go-mod-ts-extras--find-spec-node node))
                (module-path (go-mod-ts-extras--spec-module-path
                              spec node))
                (version (go-mod-ts-extras--spec-version spec)))
      (cons module-path version))))

(defun go-mod-ts-extras--private-p (module-path)
  "Return non-nil if MODULE-PATH matches a GOPRIVATE pattern.
GOPRIVATE is a comma-separated list of glob patterns in Go's
`path.Match' syntax.  Patterns are matched as module-path prefixes."
  (when-let* ((goprivate (getenv "GOPRIVATE")))
    (cl-some (lambda (pat)
               (let ((re (wildcard-to-regexp pat)))
                 ;; Strip \` and \' anchors, then allow an optional
                 ;; sub-path after the pattern.
                 (setq re (concat (substring re 2 -2)
                                  "\\(/.*\\)?"))
                 (setq re (concat "\\`" re "\\'"))
                 (string-match-p re module-path)))
             (split-string goprivate "," t " "))))

(defun go-mod-ts-extras--url-provider ()
  "Return a pkg.go.dev URL if point is on a module_path in a require/replace spec.
Returns nil for private modules (matching GOPRIVATE)."
  (when-let* ((spec (go-mod-ts-extras--spec-info))
              ((not (go-mod-ts-extras--private-p (car spec)))))
    (format go-mod-ts-extras-pkg-url-template
            (car spec) (cdr spec))))

(defun go-mod-ts-extras--filename-provider ()
  "Return a local file path if point is on a module_path in a require/replace spec.
The directory prefix respects GOMODCACHE, falling back to ~/go/pkg/mod/."
  (when-let* ((spec (go-mod-ts-extras--spec-info)))
    (format "%s%s@%s/"
            (go-mod-ts-extras--pkg-file-prefix)
            (car spec) (cdr spec))))

(defun go-mod-ts-extras--spec-module-path (spec-node &optional point-node)
  "Return the module_path string from SPEC-NODE.
For require_spec, returns the first module_path.
For replace_spec, returns the second (replacement) module_path only if
POINT-NODE falls within it; otherwise returns nil."
  (let ((type (treesit-node-type spec-node)))
    (cond
     ((equal type "require_spec")
      (let ((mp (treesit-node-child spec-node 0 t)))
        (when (and mp (equal (treesit-node-type mp) "module_path"))
          (treesit-node-text mp))))
     ((equal type "replace_spec")
      ;; replace_spec: (module_path "=>" module_path version?)
      (let ((mp-nodes nil))
        (dolist (child (treesit-node-children spec-node))
          (when (equal (treesit-node-type child) "module_path")
            (push child mp-nodes)))
        (setq mp-nodes (nreverse mp-nodes))
        (when (>= (length mp-nodes) 2)
          (let ((replacement (nth 1 mp-nodes)))
            (when (or (not point-node)
                      (eq point-node replacement)
                      (and point-node
                           (>= (treesit-node-start point-node)
                               (treesit-node-start replacement))
                           (<= (treesit-node-end point-node)
                               (treesit-node-end replacement))))
              (treesit-node-text replacement))))))
     (t nil))))


;;; Minor mode

(defvar-keymap go-mod-ts-extras-mode-map
  :doc "Keymap for `go-mod-ts-extras-mode'."
  "RET" #'go-mod-ts-extras-browse-at-point)

(defun go-mod-ts-extras-browse-at-point ()
  "Open the pkg.go.dev URL for the module path at point in a browser."
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
  - Pressing RET on a module path opens it on pkg.go.dev."
  :lighter " go.mod+"
  :keymap go-mod-ts-extras-mode-map
  (if go-mod-ts-extras-mode
      (go-mod-ts-extras--enable)
    (go-mod-ts-extras--disable)))

(defun go-mod-ts-extras--enable ()
  "Register thing-at-point providers, keymap, and treesit font-lock rules."
  ;; Thing-at-point providers (url and filename).
  (setq-local thing-at-point-provider-alist
              (cons '(url . go-mod-ts-extras--url-provider)
                    (cons '(filename . go-mod-ts-extras--filename-provider)
                          thing-at-point-provider-alist)))
  ;; Treesit font-lock rules
  (when go-mod-ts-extras-highlight-modules
    (setq-local treesit-font-lock-settings
                (append treesit-font-lock-settings
                        go-mod-ts-extras--font-lock-rules))
    (add-to-list 'treesit-font-lock-feature-list '(go-mod-extras))
    (treesit-font-lock-recompute-features)
    (font-lock-flush)
    (font-lock-ensure)))

(defun go-mod-ts-extras--disable ()
  "Unregister thing-at-point providers and treesit font-lock rules."
  ;; Thing-at-point providers.
  (setq-local thing-at-point-provider-alist
              (assq-delete-all
               'filename
               (assq-delete-all
                'url
                thing-at-point-provider-alist)))
  ;; Treesit font-lock rules
  (when go-mod-ts-extras-highlight-modules
    (let ((new-settings nil))
      (dolist (setting treesit-font-lock-settings)
        (unless (eq (plist-get (cdr setting) :feature) 'go-mod-extras)
          (push setting new-settings)))
      (setq-local treesit-font-lock-settings (nreverse new-settings)))
    (setq-local treesit-font-lock-feature-list
                (remove '(go-mod-extras) treesit-font-lock-feature-list))
    (treesit-font-lock-recompute-features)
    (font-lock-flush)
    (font-lock-ensure)))

(provide 'go-mod-ts-extras-mode)
;;; go-mod-ts-extras-mode.el ends here
