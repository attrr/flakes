;;; init-vterm.el -*- lexical-binding: t; -*-
(defun mine/vterm-copy-nomode()
  (interactive)
  (if (region-active-p)
      (progn
	(kill-ring-save (region-beginning) (region-end))
	(vterm-copy-mode -1)
	(deactivate-mark)
	(message "Copied!"))
    (vterm-send-key "M-x")))

(defun mine/vterm-find-file(filename)
  (let ((parent (current-buffer)))
    (find-file filename)
    (setq mine/parent-vterm parent)
    (message "Linked to terminal: %s" (buffer-name parent))))

(defun mine/vterm-kill-child-buffer()
  "Kill buffer created by vterm, and back"
  (interactive)
  (let ((parent mine/parent-vterm))
    (kill-buffer (current-buffer))
    (if (buffer-live-p parent)
        (switch-to-buffer parent)
      (message "Parent vterm is gone."))))

(defvar mine/vterm-confirm-save t)
(defun mine/vterm-kill-buffer()
  (interactive)
  (if (and (buffer-modified-p)
	   mine/vterm-confirm-save
	   (not (y-or-n-p (format "Save changes to %s? " (buffer-name)))))
      (message "Canceled. Buffer not killed.")
    (when (buffer-modified-p) (save-buffer))
    (cond
     ;; blocking (sudoedit, git)
     ((and (boundp 'server-buffer-clients) server-buffer-clients)
      (server-edit)
      (message "Finished."))
     ;; non-blocking (find-file)
     (mine/parent-vterm
      (mine/vterm-kill-child-buffer))
     ;; non-blocking file open outside of vterm
     (t (if (> (count-windows) 1)
            (delete-window)
          (bury-buffer))))))

(use-package eat
  :ensure t
  :config
  (eat-eshell-mode +1))

(use-package vterm
  :ensure t
  :bind
  ("<f4>" . mine/vterm-kill-buffer)
  (:map vterm-mode-map
	("M-w" . mine/vterm-copy-nomode ))
  :config
  ;; GNOME Console/GNOME Theme
  (let ((colors '(("black"   "#241f31" "#5e5c64")
                  ("red"     "#c01c28" "#ed333b")
                  ("green"   "#2ec27e" "#57e389")
                  ("yellow"  "#f5c211" "#f8e45c")
                  ("blue"    "#1e78e4" "#51a1ff")
                  ("magenta" "#9841bb" "#c061cb")
                  ("cyan"    "#0ab9dc" "#4fd2fd")
                  ("white"   "#c0bfbc" "#f6f5f4"))))
    (dolist (c colors)
      (let ((name (car c))
	    (normal (nth 1 c))
	    (bright (nth 2 c)))
	(set-face-attribute (intern (concat "vterm-color-" name)) nil
                            :foreground normal :background normal)
	(set-face-attribute (intern (concat "vterm-color-bright-" name)) nil
                            :foreground bright :background bright))))

  (defvar-local mine/parent-vterm nil)
  (add-to-list 'vterm-eval-cmds '("mine/vterm-find-file" mine/vterm-find-file)))

(defun mine/vterm-next-on-create()
  (interactive)
  (if (not multi-vterm-buffer-list)
      (multi-vterm)
    (let* ((len (length multi-vterm-buffer-list))
	   (idx (cl-position (current-buffer) multi-vterm-buffer-list)))
      (if (not idx)
	  (multi-vterm-next))
      (if (>= (1+ idx) len)
	  (multi-vterm)
	(switch-to-buffer (nth (1+ idx) multi-vterm-buffer-list)))
      )))

(defun mine/multi-vterm-enter()
  (interactive)
  (if (eq major-mode 'vterm-mode)
      (mine/vterm-next-on-create)
    ;; in other type buffer
    (let ((vterm-buf (seq-find (lambda (b)
                                 (with-current-buffer b
                                   (eq major-mode 'vterm-mode)))
			       (buffer-list))))
      ;; find recent vterm buffer, if not create one
      (if vterm-buf
          (switch-to-buffer vterm-buf)
        (multi-vterm)))))

(use-package multi-vterm
  :ensure t
  :bind
  ("C-c t" . mine/multi-vterm-enter)
  (:map vterm-mode-map
	("M-n" . mine/vterm-next-on-create)
	("M-p" . multi-vterm-prev)))

(provide 'init-vterm)
