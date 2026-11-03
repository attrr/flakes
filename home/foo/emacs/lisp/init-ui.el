;;; init-ui.el --- Theme and Fonts -*- lexical-binding: t -*-
;; Theme
(setq initial-frame-alist '((width . 126) (height . 26)))
(setq default-frame-alist '((width . 126) (height . 26)))
(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-nord-aurora t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config)
  (with-eval-after-load 'paren
    (set-face-attribute 'show-paren-match nil
                        :background 'unspecified
                        :foreground "#eceff4"
                        :weight 'extra-bold))
  :hook (window-setup . (lambda()
			  (unless (display-graphic-p (selected-frame))
			    (set-face-background 'default "unspecified-bg" (selected-frame)))))
  :config
  (set-face-attribute 'default nil :background "#1c1c1f"))

;; Mode-Line
(use-package doom-modeline
  :ensure t
  :init (doom-modeline-mode 1))

;; Font
(defun mine/setup-fonts (&optional frame)
  (let ((f (or frame (selected-frame)))
	(font-name "Adwaita Mono")
	(cjk-font-name "Ricty Diminished with Fira Code"))
    (when (display-graphic-p f)
      (set-face-attribute 'default f :font font-name :height 110)
      (dolist (charset '(kana han symbol cjk-misc bopomofo))
	(set-fontset-font t
			  charset (font-spec :family cjk-font-name :size 12) f))
      (setq face-font-rescale-alist `((,cjk-font-name . 1.51)))
      (set-fontset-font t '(#x2500 . #x259F) (font-spec :family "Symbols Nerd Font Mono") f)
      )))

(mine/setup-fonts)
(add-hook 'after-make-frame-functions #'mine/setup-fonts)

;; Optional: Icons support (Need `nerd-icons` font installed on system)
(use-package nerd-icons)

;; -- Make "lambda" display as "λ" --
(global-prettify-symbols-mode 1)

;; Hook specifically for Emacs Lisp to map "lambda" to the symbol
(add-hook 'emacs-lisp-mode-hook
          (lambda ()
	    (push '("lambda" . ?λ) prettify-symbols-alist)))
(provide 'init-ui)
