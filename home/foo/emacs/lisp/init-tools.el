;;; init-tools.el -*- lexical-binding: t -*-
(use-package magit
  :ensure t
  :bind ("C-x g" . magit-status))

;; Colorful mode
(use-package colorful-mode
  ;; :diminish
  ;; :ensure t ; Optional
  :custom
  (colorful-use-prefix t)
  (colorful-only-strings 'only-prog)
  (css-fontify-colors nil)
  :config
  (global-colorful-mode t)
  (add-to-list 'global-colorful-modes 'helpful-mode))

;; Scale
(use-package indent-bars
  :ensure t
  :hook (prog-mode . indent-bars-mode))

(provide 'init-tools)
