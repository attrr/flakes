;;; init-xdg.el --- Manual XDG directory management -*- lexical-binding: t -*-
(defvar xdg-data-dir (expand-file-name "emacs/" (or (getenv "XDG_DATA_HOME") "~/.local/share")))
(defvar xdg-state-dir (expand-file-name "emacs/" (or (getenv "XDG_STATE_HOME") "~/.local/state")))
(defvar xdg-cache-dir (expand-file-name "emacs/" (or (getenv "XDG_CACHE_HOME") "~/.cache")))

;; Create directories if they don't exist
(dolist (dir (list xdg-data-dir xdg-state-dir xdg-cache-dir))
  (unless (file-exists-p dir)
    (make-directory dir t)))

;; Backups and Auto-saves
(defun setq-ensure (key value ensure-dir)
  (when (and ensure-dir (not (file-exists-p ensure-dir)))
    (make-directory ensure-dir t))
  (set key value))

(let* ((backup-dir (expand-file-name "backups/" xdg-cache-dir))
       (auto-save-dir (expand-file-name "auto-save/" xdg-cache-dir))
       (as-list-dir        (expand-file-name "auto-save-list/" xdg-cache-dir))
       (as-list-prefix (expand-file-name ".saves-" as-list-dir)))
  (setq-ensure 'backup-directory-alist `(("." . ,backup-dir)) backup-dir)
  (setq-ensure 'auto-save-file-name-transforms `((".*" ,auto-save-dir t)) auto-save-dir)
  (setq-ensure 'auto-save-list-file-prefix as-list-prefix as-list-dir)
  (setq tramp-backup-directory-alist backup-directory-alist)
  (setq tramp-auto-save-directory auto-save-dir))

;; Desktop Save Mode
(setq desktop-dirname (expand-file-name "desktop/" xdg-state-dir)
      desktop-base-file-name "emacs.desktop"
      desktop-base-lock-name "emacs.desktop.lock")

;; Native Compilation
(when (boundp 'native-comp-eln-load-path)
  (startup-redirect-eln-cache (expand-file-name "eln-cache/" xdg-cache-dir)))

;; Persistent State (History, Logs, Session info)
(setq recentf-save-file (expand-file-name "recentf" xdg-state-dir)
      savehist-file (expand-file-name "history" xdg-state-dir)
      project-list-file (expand-file-name "projects" xdg-state-dir)
      svg-lib-icons-dir (expand-file-name "svg-lib/" xdg-state-dir)
      ielm-history-file-name (expand-file-name "ielm-history" xdg-state-dir))

;; Presistent Data
(setq package-user-dir (expand-file-name "elpa" xdg-data-dir)
      bookmark-default-file (expand-file-name "bookmarks" xdg-data-dir)
      custom-file (expand-file-name "custom.el" xdg-data-dir))

;; 4. URL and EWW cache (if you use them)
(setq url-configuration-directory (expand-file-name "url/" xdg-data-dir)
      url-cache-directory (expand-file-name "url/cache/" xdg-cache-dir))

;; eca
(setq eca-server-install-path (expand-file-name "eca/eca" xdg-cache-dir))

(provide 'init-xdg)
