;;; lisp/lsp/go.el --- Go LSP configuration -*- lexical-binding: t -*-

;; 1. Configure go-mode
(use-package go-mode
  :ensure t
  :mode "\\.go\\'")

;; 2. Register gopls to eglot
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(go-mode . ("gopls"))))

;; 3. Auto-start eglot for go files
(add-hook 'go-mode-hook #'eglot-ensure)

;; 4. Formatter Integration (Apheleia)
(with-eval-after-load 'apheleia
  (add-to-list 'apheleia-mode-alist '(go-mode . gofmt)))

(provide 'lsp/go)
