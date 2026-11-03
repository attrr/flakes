;;; lisp/lsp/systemd.el --- systemd LSP configuration -*- lexical-binding: t -*-
(use-package systemd
  :ensure t
  :mode  
  ("\\.service\\'" . systemd-mode)
  ;; networkd
  ("\\.network\\'" . systemd-mode)
  ("\\.netdev\\'"  . systemd-mode)
  ("\\.link\\'"    . systemd-mode)
  ;; podman
  ("\\.container\\'" . systemd-mode)
  ("\\.volume\\'"    . systemd-mode)
  ("\\.pod\\'"       . systemd-mode)
  ("\\.kube\\'"      . systemd-mode)
  ("\\.image\\'"     . systemd-mode)
  :hook (systemd-mode . eglot-ensure)
  :config
  (with-eval-after-load 'eglot
    (add-to-list 'eglot-server-programs
                 '(systemd-mode . ("systemd-lsp")))))


(provide 'lsp/systemd)
