;;; lisp/lsp/config.el --- ini/yaml/json configuration -*- lexical-binding: t -*-
(require 'apheleia)

;; JSON LSP (vscode-json-language-server)
;; This server relies on dynamic registration for completionProvider,
;; which eglot doesn't fully support. We inject the capability after
;; the server connects so eglot-completion-at-point works.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
	       '((js-json-mode json-mode json-ts-mode)
		 . ("vscode-json-language-server" "--stdio"
		    :initializationOptions
		    (:provideFormatter :json-false
		     :handledSchemaProtocols ["http" "https"]))))

  (defun my/eglot-json-fix-completion (server)
    "Inject completionProvider into JSON LSP capabilities."
    (when (string-match-p "vscode-json"
			  (car (process-command
				(jsonrpc--process server))))
      (let ((caps (eglot--capabilities server)))
	(unless (plist-get caps :completionProvider)
	  (setf (eglot--capabilities server)
		(plist-put caps :completionProvider
			   `(:resolveProvider t
			     :triggerCharacters ["\""]))))))
    server)

  (advice-add 'eglot--connect :filter-return #'my/eglot-json-fix-completion))

;; Tell the JSON LSP to use SchemaStore for auto-matching
(setq-default eglot-workspace-configuration
	      '(:json (:validate (:enable t)
			:schemaDownload (:enable t)
			:schemas [])))

(add-hook 'js-json-mode-hook #'eglot-ensure)
(add-hook 'json-mode-hook #'eglot-ensure)
(add-hook 'json-ts-mode-hook #'eglot-ensure)

(add-hook 'js-json-mode-hook
	  (lambda ()
	    (setq-local indent-tabs-mode nil)
	    (setq-local tab-width 2)
	    (setq-local js-indent-level 2)))

(setq apheleia-mode-alist
      (append
       '((json-mode . prettier-json)
	 (json-ts-mode . prettier-json)
	 (yaml-mode . prettier-yaml)
	 (conf-mode . prettier-ini)
	 (conf-windows-mode . prettier-ini)
	 (conf-unix-mode . prettier-ini)
	 (ini-mode . prettier-ini))
       apheleia-mode-alist))

(provide 'lsp/config)
