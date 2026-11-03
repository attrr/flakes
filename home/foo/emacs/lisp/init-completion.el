;;; init-completion.el --- Corfu, Vertico, Orderless -*- lexical-binding: t -*-
(use-package corfu
  :custom
  (corfu-cycle t)
  (corfu-auto t)
  (corfu-auto-delay 0.1)
  (corfu-quit-no-match 'separator)
  :init
  (global-corfu-mode)
  :config
  (setq corfu-preselect 'prompt)
  (setq corfu-cycle t)
  :bind
  (:map corfu-map
        ("TAB" . corfu-next)
        ([tab] . corfu-next)
        ("S-TAB" . corfu-previous)
        ([backtab] . corfu-previous))
  )

(use-package corfu-terminal
  :ensure t
  :after corfu
  :config
  ;; Only enable corfu-terminal-mode if we are NOT in a GUI
  (unless (display-graphic-p)
    (corfu-terminal-mode +1)))

(use-package kind-icon
  :after corfu
  :custom
  (kind-icon-default-style '(:padding 0 :stroke 0 :margin 0 :radius 0 :height 1.0 :scale 1.0))
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package vertico
  :init (vertico-mode)
  :config
  (setq vertico-preselect 'prompt))

(use-package savehist
  :ensure nil
  :init (savehist-mode))

(use-package marginalia
  :init (marginalia-mode))

(use-package consult
  :bind (("C-x b" . consult-buffer)
         ("M-s l" . consult-line)
         ("M-s r" . consult-ripgrep))
  :config
  (add-to-list 'consult-buffer-filter "\\*vterminal.*\\*"))

(provide 'init-completion)
