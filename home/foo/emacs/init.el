;;; init.el --- Load the configuration modules -*- lexical-binding: t -*-

;; 1. Add our 'lisp' folder to the load-path
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(require 'init-xdg)

;; 2. Basic Package Manager Setup (Must be here to bootstrap everything)
(require 'package)
(setq package-archives '(("GNU ELPA" . "https://elpa.gnu.org/packages/")
			 ("MELPA" . "https://melpa.org/packages/")
			 ("nongnu"       . "https://elpa.nongnu.org/nongnu/"))
      package-archive-priorities '(("GNU ELPA" . 20)
				   ("MELPA" . 15)
				   ("nongnu") . 0))
(package-initialize)

;; Install use-package if missing
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

;; Install if not nix
(require 'use-package)
(defconst nix-is-activate
  (and (getenv "NIX_PROFILES")
       (file-exists-p "/nix")))
(if nix-is-activate
    (setq use-package-always-ensure nil)
    (setq use-package-always-ensure t))

;; 3. Load Modules
(require 'init-defaults)   ;; Basic settings
(require 'init-basic)   ;; Basic modes
(require 'init-ui)         ;; Visuals
(require 'init-completion) ;; Corfu, Vertico, Consult
(require 'init-vterm)
(require 'init-tools)      ;; Treemacs, Magit, etc.
(require 'init-lsp)
(require 'init-agent)
