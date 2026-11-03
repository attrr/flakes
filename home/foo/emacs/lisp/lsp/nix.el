;;; lisp/lsp/nix.el --- Nix LSP configuration -*- lexical-binding: t -*-

;; 1. Configure nix-mode
(use-package nix-mode
  :ensure t
  :mode "\\.nix\\'")

;; 2. Register nixd to eglot
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(nix-mode . ("nixd"))))

;; 3. Auto-start eglot for nix files
(add-hook 'nix-mode-hook #'eglot-ensure)

;; 4. Formatter Integration (Apheleia) ---
(with-eval-after-load 'apheleia
  (setf (alist-get 'nixfmt apheleia-formatters) '("nixfmt"))
  (add-to-list 'apheleia-mode-alist '(nix-mode . nixfmt)))

(provide 'lsp/nix)