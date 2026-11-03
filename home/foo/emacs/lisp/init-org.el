;;; init-org.el --- Org-mode configuration -*- lexical-binding: t -*-

(use-package org
  :ensure nil ;; Built-in
  :custom
  (org-ellipsis " ▾")          ;; fold
  (org-hide-emphasis-markers t) ;; hide *bold* / /italic/ mark
  (org-log-done 'time)          ;; record task time
  (org-todo-keywords
   '((sequence "TODO(t)" "NEXT(n)" "|" "DONE(d)")
     (sequence "WAIT(w@/!)" "HOLD(h@/!)" "|" "CANCEL(c@/!)")))
  :config
  ;; for doom-one
  (set-face-attribute 'org-level-1 nil :height 1.2 :weight 'bold)
  (set-face-attribute 'org-level-2 nil :height 1.1 :weight 'bold))

;; star to dot
(use-package org-bullets
  :ensure t
  :after org
  :hook (org-mode . org-bullets-mode))

;; auto newline
(add-hook 'org-mode-hook 'visual-line-mode)

(provide 'init-org)