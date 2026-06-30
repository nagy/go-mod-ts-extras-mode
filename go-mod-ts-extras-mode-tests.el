;;; go-mod-ts-extras-mode-tests.el --- Tests for go-mod-ts-extras-mode -*- lexical-binding: t -*-

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

(defun go-mod-ts-extras-test--with-buffer (content)
  "Create a temporary `go-mod-ts-mode' buffer with CONTENT.
Enables `go-mod-ts-extras-mode', moves point to the beginning, and
returns the buffer."
  (let ((buf (generate-new-buffer " *go-mod-ts-extras-test*")))
    (with-current-buffer buf
      (go-mod-ts-mode)
      (insert content)
      (goto-char (point-min))
      (go-mod-ts-extras-mode 1)
      (setq buffer-file-name "/tmp/go.mod"))
    buf))


;;; Tests

(ert-deftest go-mod-ts-extras-url-at-require-module-path ()
  "Test URL detection when point is on a module_path in a require spec."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module example.com/foo/baz

go 1.26.3

require github.com/google/uuid v1.6.0
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "github.com/google/uuid")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://pkg.go.dev/github.com/google/uuid@v1.6.0")))
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-url-in-require-block ()
  "URL detection works inside a require (...) block."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module example.com/foo/baz

go 1.26.3

require (
    github.com/google/uuid v1.6.0
)
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "github.com/google/uuid")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://pkg.go.dev/github.com/google/uuid@v1.6.0")))
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-url-on-version ()
  "Point on the version string should still resolve to the module URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require golang.org/x/net v0.20.0
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "v0.20.0")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://pkg.go.dev/golang.org/x/net@v0.20.0")))
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-url-not-on-module-directive ()
  "Point on the module directive path should NOT return a URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module example.com/foo/baz

go 1.26.3
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "example.com/foo/baz")
      (goto-char (match-beginning 0))
      (should-not (thing-at-point 'url)))
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-url-replace-spec ()
  "URL detection works for replace specs (replacement module path)."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require golang.org/x/net v1.0.0

replace golang.org/x/net => github.com/other/net v0.1.0
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "github.com/other/net")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://pkg.go.dev/github.com/other/net@v0.1.0")))
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-url-replace-original ()
  "The original (first) module_path in a replace spec should NOT return a URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require golang.org/x/net v1.0.0

replace golang.org/x/net => github.com/other/net v0.1.0
")))
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
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-url-custom-template ()
  "Custom URL template should be respected."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((go-mod-ts-extras-pkg-url-template "https://example.com/%s"))
    (let ((buf (go-mod-ts-extras-test--with-buffer
                "module m

go 1.20

require github.com/google/uuid v1.6.0
")))
      (with-current-buffer buf
        (setq-local go-mod-ts-extras-pkg-url-template "https://example.com/%s")
        (go-mod-ts-extras--disable)
        (go-mod-ts-extras--enable)
        (goto-char (point-min))
        (search-forward "github.com/google/uuid")
        (goto-char (match-beginning 0))
        ;; With only one %s, the version is still passed but ignored
        (should (equal (thing-at-point 'url)
                       "https://example.com/github.com/google/uuid")))
      (kill-buffer buf))))

(ert-deftest go-mod-ts-extras-mode-disable ()
  "Disabling the mode should restore default URL detection."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require github.com/google/uuid v1.6.0
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "github.com/google/uuid")
      (goto-char (match-beginning 0))
      (should (thing-at-point 'url))
      ;; Disable and verify no URL detection
      (go-mod-ts-extras-mode -1)
      (should-not (thing-at-point 'url)))
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-url-indirect-dependency ()
  "URL detection works for indirect dependencies (with // indirect comment)."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m

go 1.20

require (
    golang.org/x/net v0.20.0 // indirect
)
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "golang.org/x/net")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://pkg.go.dev/golang.org/x/net@v0.20.0")))
    (kill-buffer buf)))

(ert-deftest go-mod-ts-extras-browse-at-point ()
  "Pressing RET on a module path should call browse-url with the pkg.go.dev URL."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((browse-url-called nil)
        (browse-url-arg nil))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url) (setq browse-url-called t browse-url-arg url))))
      (let ((buf (go-mod-ts-extras-test--with-buffer
                  "module m
go 1.20
require github.com/x v1.0.0
")))
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "github.com/x")
          (goto-char (match-beginning 0))
          (go-mod-ts-extras-browse-at-point)
          (should browse-url-called)
          (should (equal browse-url-arg
                         "https://pkg.go.dev/github.com/x@v1.0.0")))
        (kill-buffer buf)))))

(ert-deftest go-mod-ts-extras-browse-at-point-no-module ()
  "Pressing RET on non-module-path text should signal an error."
  (skip-unless (treesit-ready-p 'gomod))
  (let ((buf (go-mod-ts-extras-test--with-buffer
              "module m
go 1.20
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "module")
      (goto-char (match-beginning 0))
      (should-error (go-mod-ts-extras-browse-at-point)))
    (kill-buffer buf)))

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
")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "stretchr/testify")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://pkg.go.dev/github.com/stretchr/testify@v1.8.0")))
    (kill-buffer buf)))

(provide 'go-mod-ts-extras-mode-tests)
;;; go-mod-ts-extras-mode-tests.el ends here
