;;; init-basic.el -*- lexical-binding: t -*-
(use-package yaml-mode
  :ensure t
  :mode ("\\.yml\\'" "\\.yaml\\'")
  :hook (yaml-mode . (lambda ()
		       (setq-local indent-tabs-mode nil)
		       (setq-local tab-width 2)
		       (setq-local yaml-indent-offset 2))))

(add-hook 'server-after-make-frame-hook
          (lambda ()
            (let ((display (frame-parameter nil 'display)))
              (when display
                (setenv "DISPLAY" display)
                (setenv "TERM" "xterm-256color")))))


;; tramp
(setq remote-file-name-inhibit-locks t
      tramp-use-scp-direct-remote-copying t
      remote-file-name-inhibit-auto-save-visited t)

;; manpage
(setq Man-notify-method 'pushy)
(setq Man-display-manpage-function 'display-buffer-same-window)
(with-eval-after-load 'man
  (define-key Man-mode-map (kbd "n") 'Man-next-section)
  (define-key Man-mode-map (kbd "p") 'Man-previous-section)
  (define-key Man-mode-map (kbd "m") 'Man-goto-section)
  (define-key Man-mode-map (kbd "u") 'Man-goto-section))


(provide 'init-basic)
