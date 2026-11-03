;;; lisp/lsp/shell.el --- Shell (bash/zsh/ash) LSP and formatter -*- lexical-binding: t -*-

;; Eglot already supports bash-language-server for sh-mode out of the box.
;; We just need to enable it for shell scripts.
(add-hook 'sh-mode-hook 'eglot-ensure)
(add-hook 'bash-ts-mode-hook 'eglot-ensure)

;; Map sh-mode and bash-ts-mode to shfmt formatter in apheleia.
;; (apheleia comes with shfmt predefined in apheleia-formatters)
(require 'apheleia)
(add-to-list 'apheleia-mode-alist '(sh-mode . shfmt))
(add-to-list 'apheleia-mode-alist '(bash-ts-mode . shfmt))

(defun mine/sh-mode-settings ()
  (setq-local indent-tabs-mode nil)
  (setq-local sh-basic-offset 2)
  (setq-local bash-ts-mode-indent-offset 2)
  (setq-local sh-indent-after-continuation 'always))
(add-hook 'sh-mode-hook #'mine/sh-mode-settings)
(add-hook 'bash-ts-mode-hook #'mine/sh-mode-settings)

(provide 'lsp/shell)
