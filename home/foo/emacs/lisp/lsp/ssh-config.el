;;; lsp/ssh-config.el --- SSH Config Mode configuration -*- lexical-binding: t -*-

(require 'cl-lib)

(defvar ssh-config-font-lock-keywords
  `((,(concat "^\\s-*" (regexp-opt '("Host" "Match" "Include") t) "\\b") . font-lock-keyword-face)
    ("^\\s-*\\([A-Za-z0-9]+\\)\\s-+" 1 font-lock-variable-name-face))
  "Minimal keyword highlighting for SSH config files.")

(defun ssh-config-indent-line ()
  (interactive)
  (let ((indent 4))
    (save-excursion
      (beginning-of-line)
      (skip-chars-forward " \t")
      (let ((case-fold-search t))
        (when (or (looking-at-p "\\(?:Host\\|Match\\|Include\\)\\b")
                  (looking-at-p "#"))
          (setq indent 0))
        (when (eolp)
          ;; If empty line, cycle between 0 and 4 spaces
          (setq indent (if (= (current-indentation) 0) 4 0)))))
    (indent-line-to indent)))

(defun ssh-config-completion-at-point ()
  "Provide file completion for IdentityFile and Include."
  (let ((match-end-pos (save-excursion
                         (beginning-of-line)
                         (when (looking-at "^\\s-*\\(?:IdentityFile\\|Include\\)\\s-+")
                           (match-end 0)))))
    (when (and match-end-pos (>= (point) match-end-pos))
      (let* ((bounds (bounds-of-thing-at-point 'filename))
             (start (if bounds (car bounds) (point)))
             (end (if bounds (cdr bounds) (point))))
        (list start end #'completion-file-name-table :category 'file :exclusive 'no)))))

(define-derived-mode ssh-config-mode conf-unix-mode "SSH-Config"
  "A minimal major mode for editing SSH config files."
  (font-lock-add-keywords nil ssh-config-font-lock-keywords)
  (setq-local indent-line-function #'ssh-config-indent-line)
  (add-hook 'completion-at-point-functions #'ssh-config-completion-at-point nil t))

(add-to-list 'auto-mode-alist '("/\\.ssh/config\\'" . ssh-config-mode))
(add-to-list 'auto-mode-alist '("/\\.ssh/config\\.d/.*\\'" . ssh-config-mode))

(with-eval-after-load 'apheleia
  (cl-defun ssh-config-apheleia-formatter (&key buffer scratch callback &allow-other-keys)
    "Format the current buffer using Emacs' native indent-region."
    (with-current-buffer scratch
      ;; Ensure our custom mode and indent rules are active in the scratch buffer
      (ssh-config-mode)
      (indent-region (point-min) (point-max))
      (delete-trailing-whitespace))
    (when (functionp callback)
      (funcall callback)))

  (add-to-list 'apheleia-formatters
               '(ssh-config-fmt . ssh-config-apheleia-formatter))
  (add-to-list 'apheleia-mode-alist
               '(ssh-config-mode . ssh-config-fmt)))

(provide 'lsp/ssh-config)
