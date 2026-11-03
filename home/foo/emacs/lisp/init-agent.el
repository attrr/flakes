(use-package eca
  :ensure t
  :config
  (setq eca-chat-diff-tool 'ediff))

(defvar mine/eca-inhibit-confirm-p nil
  "whether to disable workspace comfirmation")

(defun mine/eca-restart-with-vertex-token ()
  (interactive)
  (let ((token (shell-command-to-string "gcloud auth print-access-token")))
    (setenv "VERTEX_BEARER_TOKEN" (string-trim token))
    (let ((mine/eca-inhibit-confirm-p t))
      (eca-restart))
    (message "vertex token refreshed")))

(defun mine/eca-force-workspace-comfirm (orig-fun &optional _arg)
  (interactive "P")
  ;; protect home
  (when (file-equal-p
	 (expand-file-name default-directory)
	 (expand-file-name "~"))
    (user-error "home-dir detected"))
  ;; need comfirmation
  (if mine/eca-inhibit-confirm-p
      (funcall orig-fun _arg)
    (funcall orig-fun '(4))))
(advice-add 'eca :around #'mine/eca-force-workspace-comfirm)

(use-package agent-shell
  :ensure t
  :config
  (setq agent-shell-show-context-usage-indicator t)
  )
(provide 'init-agent)
