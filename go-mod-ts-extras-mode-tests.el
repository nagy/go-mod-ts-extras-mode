;;; go-mod-ts-extras-mode-tests.el --- Tests for go-mod-ts-extras-mode -*- lexical-binding: t -*-

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

;; To run these tests:
;;
;;   (require 'go-mod-ts-extras-mode)
;;   (require 'ert)
;;
;; Then: M-x ert RET t

(require 'go-mod-ts-extras-mode)
(require 'ert)
(require 'cl-lib)

;;; Helper: create a go-mod-ts-mode buffer with content and return it.

(defun go-mod-ts-extras-test--with-buffer (content &optional enable)
  "Create a temporary `go-mod-ts-mode' buffer with CONTENT.
When ENABLE is non-nil (default), enables `go-mod-ts-extras-mode',
moves point to the beginning, and returns the buffer.
When ENABLE is nil, leaves the mode disabled."
  (let ((buf (generate-new-buffer " *go-mod-ts-extras-test*")))
    (with-current-buffer buf
      (go-mod-ts-mode)
      (insert content)
      (goto-char (point-min))
      (when enable
        (go-mod-ts-extras-mode 1))
      (setq buffer-file-name "/tmp/go.mod"))
    buf))

(defmacro go-mod-ts-extras-test--with-env (varname value &rest body)
  "Execute BODY with environment variable VARNAME set to VALUE.
Restores the previous value afterwards."
  (declare (indent 2))
  `(let ((old-val (getenv ,varname)))
     (unwind-protect
         (progn
           (setenv ,varname ,value)
           ,@body)
       (setenv ,varname old-val))))

;;; URL detection tests

(ert-deftest go-mod-ts-extras-url-at-require-module-path ()
  "URL detection when point is on a module_path in a require spec."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module example.com/foo/baz

go 1.26.3

require github.com/google/uuid v1.6.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "github.com/google/uuid")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/github.com/google/uuid@v1.6.0")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-in-require-block ()
  "URL detection works inside a require (...) block."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module example.com/foo/baz

go 1.26.3

require (
    github.com/google/uuid v1.6.0
)
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "github.com/google/uuid")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/github.com/google/uuid@v1.6.0")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-on-version ()
  "Point on the version string should still resolve to the module URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require golang.org/x/net v0.20.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "v0.20.0")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/golang.org/x/net@v0.20.0")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-not-on-module-directive ()
  "Point on the module directive path should NOT return a URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module example.com/foo/baz

go 1.26.3
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "example.com/foo/baz")
          (goto-char (match-beginning 0))
          (should-not (thing-at-point 'url)))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-replace-spec ()
  "URL detection works for replace specs (replacement module path)."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require golang.org/x/net v1.0.0

replace golang.org/x/net => github.com/other/net v0.1.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "github.com/other/net")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/github.com/other/net@v0.1.0")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-replace-original ()
  "The original (first) module_path in a replace spec should NOT return a URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require golang.org/x/net v1.0.0

replace golang.org/x/net => github.com/other/net v0.1.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          ;; First occurrence is in require, second is in replace (original).
          ;; Go to the one on the replace line.
          (goto-char (point-min))
          ;; Skip past the require line's golang.org/x/net
          (search-forward "golang.org/x/net")
          (search-forward "golang.org/x/net")
          (goto-char (match-beginning 0))
          ;; This is the original in the replace spec, should not resolve.
          (should-not (thing-at-point 'url)))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-replace-with-original-version ()
  "Replace spec `old v1 => new v2' should use v2, not v1."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

replace golang.org/x/net v1.9.9 => github.com/other/net v0.1.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "github.com/other/net")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/github.com/other/net@v0.1.0")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-custom-template ()
  "Custom URL template should be respected."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-url-template "https://example.com/%s"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m

go 1.20

require github.com/google/uuid v1.6.0
" t)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/google/uuid")
            (goto-char (match-beginning 0))
            ;; With only one %s, format passes the version but it's ignored
            (should (equal (thing-at-point 'url)
                           "https://example.com/github.com/google/uuid")))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-url-indirect-dependency ()
  "URL detection works for indirect dependencies (with // indirect comment)."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require (
    golang.org/x/net v0.20.0 // indirect
)
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "golang.org/x/net")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/golang.org/x/net@v0.20.0")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-multiple-require ()
  "URL detection works when multiple require specs are present."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require (
    github.com/google/uuid v1.6.0
    golang.org/x/net v0.20.0
    github.com/stretchr/testify v1.8.0
)
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "stretchr/testify")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/github.com/stretchr/testify@v1.8.0")))
      (kill-buffer buf))))

;;; GOPRIVATE tests

(ert-deftest go-mod-ts-extras-url-goprivate-match ()
  "URL detection should return nil for modules matching GOPRIVATE."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
require gitlab.internal/foo/bar v1.0.0
" t)))
    (unwind-protect
        (go-mod-ts-extras-test--with-env "GOPRIVATE" "gitlab.internal/*"
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "gitlab.internal/foo/bar")
            (goto-char (match-beginning 0))
            (should-not (thing-at-point 'url))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-goprivate-no-match ()
  "URL detection should still work for modules not matching GOPRIVATE."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
require github.com/x v1.0.0
" t)))
    (unwind-protect
        (go-mod-ts-extras-test--with-env "GOPRIVATE" "gitlab.internal/*"
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/x")
            (goto-char (match-beginning 0))
            (should (equal (thing-at-point 'url)
                           "https://pkg.go.dev/github.com/x@v1.0.0"))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-goprivate-wildcard ()
  "GOPRIVATE wildcard patterns like *.corp.com should match subdomains."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
require foo.corp.com/lib v1.0.0
" t)))
    (unwind-protect
        (go-mod-ts-extras-test--with-env "GOPRIVATE" "*.corp.com"
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "foo.corp.com/lib")
            (goto-char (match-beginning 0))
            (should-not (thing-at-point 'url))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-goprivate-star-no-slash ()
  "GOPRIVATE * does NOT match / (Go path.Match semantics).
`foo/bar.corp.com' should NOT be matched by `*.corp.com'."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
require foo/bar.corp.com v1.0.0
" t)))
    (unwind-protect
        (go-mod-ts-extras-test--with-env "GOPRIVATE" "*.corp.com"
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "foo/bar.corp.com")
            (goto-char (match-beginning 0))
            (should (equal (thing-at-point 'url)
                           "https://pkg.go.dev/foo/bar.corp.com@v1.0.0"))))
      (kill-buffer buf))))

;;; Browse-at-point tests

(ert-deftest go-mod-ts-extras-browse-at-point ()
  "`go-mod-ts-extras-browse-at-point' opens the pkg.go.dev URL in a browser."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((browse-url-called nil)
        (browse-url-arg nil))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url) (setq browse-url-called t browse-url-arg url))))
      (let ((buf (go-mod-ts-extras-test--with-buffer
                  "module m
go 1.20
require github.com/x v1.0.0
" t)))
        (unwind-protect
            (with-current-buffer buf
              (goto-char (point-min))
              (search-forward "github.com/x")
              (goto-char (match-beginning 0))
              (go-mod-ts-extras-browse-at-point)
              (should browse-url-called)
              (should (equal browse-url-arg
                             "https://pkg.go.dev/github.com/x@v1.0.0")))
          (kill-buffer buf))))))

(ert-deftest go-mod-ts-extras-browse-at-point-no-module ()
  "`go-mod-ts-extras-browse-at-point' signals error on non-module text."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "module")
          (goto-char (match-beginning 0))
          (should-error (go-mod-ts-extras-browse-at-point)))
      (kill-buffer buf))))

;;; Filename detection tests

(ert-deftest go-mod-ts-extras-filename-at-require-module-path ()
  "Filename detection when point is on a module_path."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/tmp/gocache/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m
go 1.20
require github.com/x v1.0.0
" t)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/x")
            (goto-char (match-beginning 0))
            (should (equal (thing-at-point 'filename)
                           "/tmp/gocache/github.com/x@v1.0.0/")))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-filename-uses-gomodcache ()
  "When GOMODCACHE is set, it should be used as the prefix."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix nil)
        (buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
require github.com/x v1.0.0
" t)))
    (unwind-protect
        (go-mod-ts-extras-test--with-env "GOMODCACHE" "/opt/gocache"
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/x")
            (goto-char (match-beginning 0))
            (should (equal (thing-at-point 'filename)
                           "/opt/gocache/github.com/x@v1.0.0/"))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-filename-custom-prefix ()
  "Custom file prefix should be respected."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/opt/custom/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m
go 1.20
require github.com/x v1.0.0
" t)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/x")
            (goto-char (match-beginning 0))
            (should (equal (thing-at-point 'filename)
                           "/opt/custom/github.com/x@v1.0.0/")))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-filename-not-on-module-directive ()
  "Point on the module directive should not match our filename provider."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/tmp/gocache/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m
go 1.20
" t)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "module")
            (goto-char (match-beginning 0))
            ;; Our provider returns nil; Emacs's default filename provider
            ;; may or may not pick up "m" — either way, it shouldn't match
            ;; our cache-directory format.
            (let ((f (thing-at-point 'filename)))
              (should (or (not f)
                          (not (string-prefix-p "/tmp/gocache/" f))))))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-filename-on-version ()
  "Point on the version string should resolve to the file path."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/tmp/gocache/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m
go 1.20
require golang.org/x/net v0.20.0
" t)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "v0.20.0")
            (goto-char (match-beginning 0))
            (should (equal (thing-at-point 'filename)
                           "/tmp/gocache/golang.org/x/net@v0.20.0/")))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-filename-unaffected-by-goprivate ()
  "Filename should still be returned for private modules."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/tmp/gocache/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m
go 1.20
require gitlab.internal/foo/bar v1.0.0
" t)))
      (unwind-protect
          (go-mod-ts-extras-test--with-env "GOPRIVATE" "gitlab.internal/*"
            (with-current-buffer buf
              (goto-char (point-min))
              (search-forward "gitlab.internal/foo/bar")
              (goto-char (match-beginning 0))
              (should (equal (thing-at-point 'filename)
                             "/tmp/gocache/gitlab.internal/foo/bar@v1.0.0/"))))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-filename-uppercase-escaped ()
  "Module cache path escapes uppercase letters as !lowercase."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/tmp/cache/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m
go 1.20
require github.com/BurntSushi/TOML v1.0.0
" t)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/BurntSushi/TOML")
            (goto-char (match-beginning 0))
            (should (equal (thing-at-point 'filename)
                           "/tmp/cache/github.com/!burnt!sushi/!t!o!m!l@v1.0.0/")))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-filename-local-dir-replace ()
  "Replace spec targeting a local directory returns that directory."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

replace example.com/foo => ./local-fork
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "./local-fork")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'filename) "./local-fork")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-local-dir-replace ()
  "Replace spec targeting a local directory should NOT return a URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

replace example.com/foo => ./local-fork
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "./local-fork")
          (goto-char (match-beginning 0))
          (should-not (thing-at-point 'url)))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-replace-version ()
  "Point on a version in a replace spec resolves to the replacement module URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

replace golang.org/x/net v1.9.9 => github.com/other/net v0.1.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          ;; Point on the replacement (second) version.
          (goto-char (point-min))
          (search-forward "v0.1.0")
          (goto-char (match-beginning 0))
          (should (equal (thing-at-point 'url)
                         "https://pkg.go.dev/github.com/other/net@v0.1.0")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-url-replace-original-version ()
  "Point on the ORIGINAL version in a replace spec should NOT return a URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

replace golang.org/x/net v1.9.9 => github.com/other/net v0.1.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          ;; Point on the original (first) version.
          (goto-char (point-min))
          (search-forward "v1.9.9")
          (goto-char (match-beginning 0))
          (should-not (thing-at-point 'url)))
      (kill-buffer buf))))

;;; Mode enable/disable tests

(ert-deftest go-mod-ts-extras-mode-disable ()
  "Disabling the mode should stop returning our custom URL and filename."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/tmp/gocache/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m

go 1.20

require github.com/google/uuid v1.6.0
" t)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/google/uuid")
            (goto-char (match-beginning 0))
            (should (string-prefix-p "https://pkg.go.dev/"
                                     (thing-at-point 'url)))
            (should (string-prefix-p "/tmp/gocache/"
                                     (thing-at-point 'filename)))
            ;; Disable and verify our custom providers are gone
            (go-mod-ts-extras-mode -1)
            ;; Our URL provider should stop returning pkg.go.dev
            (should-not (thing-at-point 'url))
            ;; Our filename provider should stop returning the cache path
            (let ((f (thing-at-point 'filename)))
              (should (or (not f)
                          (not (string-prefix-p "/tmp/gocache/" f))))))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-mode-off-state ()
  "With the mode never enabled, our providers must not be registered."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-file-prefix "/tmp/gocache/"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m

go 1.20

require github.com/google/uuid v1.6.0
"
                nil)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (search-forward "github.com/google/uuid")
            (goto-char (match-beginning 0))
            ;; No pkg.go.dev URL (our provider is not registered).
            (should-not (thing-at-point 'url))
            ;; Filename falls back to Emacs defaults, never the cache path.
            (let ((f (thing-at-point 'filename)))
              (should (or (not f)
                          (not (string-prefix-p "/tmp/gocache/" f))))))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-mode-idempotent ()
  "Enabling the mode twice should not double-register providers."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
require github.com/x v1.0.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (let ((count-before (length thing-at-point-provider-alist)))
            (go-mod-ts-extras-mode 1)
            (should (= (length thing-at-point-provider-alist)
                       count-before))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-mode-preserves-other-providers ()
  "Disabling the mode should not remove URL providers from other packages."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
require github.com/x v1.0.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          ;; Inject a fake third-party url provider
          (push '(url . fake-url-provider) thing-at-point-provider-alist)
          ;; Both ours and the fake one should be present
          (should (member '(url . go-mod-ts-extras--url-provider)
                          thing-at-point-provider-alist))
          (should (member '(url . fake-url-provider)
                          thing-at-point-provider-alist))
          ;; Disable: only our provider should disappear
          (go-mod-ts-extras-mode -1)
          (should-not (member '(url . go-mod-ts-extras--url-provider)
                              thing-at-point-provider-alist))
          ;; The fake one should survive
          (should (member '(url . fake-url-provider)
                          thing-at-point-provider-alist)))
      (kill-buffer buf))))

;;; Bounds-of-thing-at-point tests

(ert-deftest go-mod-ts-extras-bounds-of-url ()
  "`bounds-of-thing-at-point' for url returns the module_path region."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require github.com/google/uuid v1.6.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "github.com/google/uuid")
          (let* ((bounds (bounds-of-thing-at-point 'url))
                 (region (when bounds
                           (buffer-substring-no-properties
                            (car bounds) (cdr bounds)))))
            (should bounds)
            (should (equal region "github.com/google/uuid"))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-bounds-of-url-on-version ()
  "Bounds still cover the module_path even when point is on version."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require golang.org/x/net v0.20.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "v0.20.0")
          (goto-char (match-beginning 0))
          (let* ((bounds (bounds-of-thing-at-point 'url))
                 (region (when bounds
                           (buffer-substring-no-properties
                            (car bounds) (cdr bounds)))))
            (should bounds)
            (should (equal region "golang.org/x/net"))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-bounds-of-url-not-on-module ()
  "Bounds should be nil when not on a module path."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20
" t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "module")
          (should-not (bounds-of-thing-at-point 'url)))
      (kill-buffer buf))))

;;; Font-lock tests

(ert-deftest go-mod-ts-extras-font-lock-adds-rules ()
  "Enabling the mode adds font-lock rules with the go-mod-extras feature."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.26.3

require github.com/x v1.0.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (font-lock-ensure)
          ;; Our rules should be present in the settings list
          (should (cl-some (lambda (s)
                             (eq (treesit-font-lock-setting-feature s)
                                 'go-mod-extras))
                           treesit-font-lock-settings)))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-font-lock-underlines-module-path ()
  "Enabling the mode underlines module paths in require/replace specs.

Regression test: the rule used to be silently disabled because
`go-mod-ts-extras--enable' recomputed font-lock features with no
arguments, resetting enablement from `treesit-font-lock-feature-list'
which does not contain the `go-mod-extras' feature."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.26.3

require github.com/x v1.0.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "github.com/x")
          (let ((face (get-text-property (match-beginning 0) 'face)))
            (should (eq face 'go-mod-ts-extras-module-path-face))
            (should (face-underline-p face))))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-font-lock-underlines-replace-target ()
  "Underlines the replacement module_path in a replace spec."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.26.3

replace old.example/a v1.0.0 => new.example/b v2.0.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "new.example/b")
          (should (eq (get-text-property (match-beginning 0) 'face)
                      'go-mod-ts-extras-module-path-face)))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-font-lock-removes-rules ()
  "Disabling the mode removes our font-lock rules."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.26.3

require github.com/x v1.0.0
" t)))
    (unwind-protect
        (with-current-buffer buf
          (font-lock-ensure)
          (go-mod-ts-extras-mode -1)
          (font-lock-ensure)
          ;; Our feature should no longer be present
          (should-not (cl-some (lambda (s)
                                 (eq (treesit-font-lock-setting-feature s)
                                     'go-mod-extras))
                               treesit-font-lock-settings)))
      (kill-buffer buf))))

(provide 'go-mod-ts-extras-mode-tests)
;;; go-mod-ts-extras-mode-tests.el ends here
