;;; lisp/lsp/python.el --- Python LSP configuration -*- lexical-binding: t -*-

;; 1. Configure python-mode
(use-package python
  :ensure nil
  :mode ("\\.py\\'" . python-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(python-base-mode . ("pyright-langserver" "--stdio"))))

;; 3. Auto-start eglot for python files
(add-hook 'python-mode-hook #'eglot-ensure)

;; 4. Formatter Integration (Apheleia)
(with-eval-after-load 'apheleia
  (add-to-list 'apheleia-mode-alist '(python-mode . black)))

(provide 'lsp/python)
