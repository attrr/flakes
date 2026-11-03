;;; init-lsp.el --- LSP support with Eglot -*- lexical-binding: t -*-

;; Snippet support (used by eglot for LSP snippet completions)
(use-package yasnippet
  :ensure t
  :config (yas-global-mode 1))

(use-package eglot
  :ensure nil ;; Built-in in Emacs 29+
  :bind (:map eglot-mode-map
              ("C-c r" . eglot-rename)
              ("C-c a" . eglot-code-actions))
  :config
  ;; Optimization: increase the amount of data read from the process
  (setq read-process-output-max (* 1024 1024)))

;; Consult integration for LSP (Better UI for finding symbols)
(use-package consult-eglot
  :ensure t
  :after (eglot consult)
  :bind (:map eglot-mode-map
              ("M-s s" . consult-eglot-symbols)))

(use-package apheleia
  :ensure t
  :bind ("C-c f" . apheleia-format-buffer))

;; Prevent accidental byte-compilation when aiming for C-c f (apheleia)
(with-eval-after-load 'elisp-mode
  (define-key emacs-lisp-mode-map (kbd "C-c C-f") nil)
  (define-key lisp-interaction-mode-map (kbd "C-c C-f") nil))

;; load ./lsp dir
(require 'lsp/nix)
(require 'lsp/go)
(require 'lsp/python)
(require 'lsp/config)
(require 'lsp/systemd)
(require 'lsp/ssh-config)
(require 'lsp/shell)

(provide 'init-lsp)
