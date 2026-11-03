;;; init-defaults.el -*- lexical-binding: t -*-
;; -- Clean up the UI --
(customize-set-variable 'scroll-bar-mode nil)
(customize-set-variable 'horizontal-scroll-bar-mode nil)
(setq inhibit-startup-message t)           ;; Disable startup screen
(scroll-bar-mode -1)                       ;; Disable visible scrollbar
(tool-bar-mode -1)                         ;; Disable the toolbar
(tooltip-mode -1)                          ;; Disable tooltips
(set-fringe-mode 10)                       ;; Give some breathing room
(menu-bar-mode -1)                         ;; Disable the menu bar
;; minibuffer
(setq use-short-answers t)
(setq enable-recursive-minibuffers t)
;; TODO
(setq visible-bell t)

;; Line numbers
(column-number-mode)
(global-display-line-numbers-mode t)
(dolist (mode '(vterm-mode-hook shell-mode-hook eshell-mode-hook treemacs-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))

;; Parentheses
(show-paren-mode 1)
(use-package paren
  :ensure nil
  :config
  (setq show-paren-delay 0)
  (setq show-paren-style 'parenthesis))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(provide 'init-defaults)
