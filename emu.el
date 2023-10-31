;;; emu.el --- Alternative UI for for mu4e   -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Adam Porter

;; Author: Adam Porter <adam@alphapapa.net>
;; Keywords: comm
;; URL: https://github.com/alphapapa/emu.el
;; Package-Requires: ((taxy-magit-section "0.12.1"))
;; Version: 0.1-pre

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This library implements an alternative UI mu4e based on
;; `taxy' and `taxy-magit-section'.  To use, activate `emu-mode'
;; and run an mu4e search; the results will be shown in the
;; "*emu*" buffer.

;;; Code:

(require 'mu4e)

(require 'taxy-magit-section)

;;;; Variables

(defvar-local emu-visibility-cache nil)

(defvar emu-old-headers-append-func nil)

;;;; Faces

(defface emu-contact '((t (:inherit font-lock-variable-name-face)))
  "Contact names.")

(defface emu-subject '((t (:inherit font-lock-function-name-face)))
  "Subjects.")

(defface emu-unread '((t (:inherit bold)))
  "Unread messages.")

(defface emu-new '((t (:underline t)))
  "New messages.")

(defface emu-flagged '((t ;; (:inherit font-lock-warning-face)
                              (:underline t)))
  "Flagged messages.")

;;;; Keys

(eval-and-compile
  (taxy-define-key-definer emu-define-key
    emu-keys "emu-key" "FIXME: Docstring."))

(emu-define-key date (&key (format "%F (%A)"))
  (let ((time (mu4e-message-field item :date)))
    (format-time-string format time)))

(emu-define-key year (&key (format "%Y"))
  (let ((time (mu4e-message-field item :date)))
    (format-time-string format time)))

(emu-define-key month (&key (format "%m (%B %Y)"))
  (let ((time (mu4e-message-field item :date)))
    (format-time-string format time)))

(emu-define-key week (&key (format "W%V (%Y)"))
  (let ((time (mu4e-message-field item :date)))
    (format-time-string format time)))

(emu-define-key from (&key name from)
  (cl-labels ((format-contact (contact)
                (pcase-let* (((map :email :name) contact)
                             (address (format "<%s>" email))
                             (name (when name
                                     (format "%s " name))))
                  (concat name address))))
    (let ((message-from (mu4e-message-field item :from)))
      (pcase from
        ((or `nil (guard (cl-loop for contact on message-from
                                  thereis (or (string-match-p from (plist-get contact :email))
                                              (string-match-p from (plist-get contact :name))))))
         (or name (string-join (mapcar #'format-contact message-from) ",")))))))

(emu-define-key list (&key name list)
  (let ((message-list (mu4e-message-field item :list)))
    (pcase list
      ((or `nil (guard (equal message-list list)))
       (or name message-list)))))

(emu-define-key thread ()
  (pcase-let* ((meta (mu4e-message-field item :meta))
               ((map :thread-subject) meta)
               (subject (mu4e-message-field item :subject)))
    ;; (if thread-subject
    ;;     (concat (mu4e~headers-thread-prefix meta) subject)
    ;;   subject)
    ;; HACK:
    (truncate-string-to-width (string-trim-left subject (rx "Re:" (0+ blank))) 80 nil nil t t)))

(emu-define-key subject (subject &key name match-group)
  (let ((message-subject (mu4e-message-field item :subject)))
    (when (string-match subject message-subject)
      (or (when match-group
            (match-string match-group message-subject))
          name message-subject))))

(defvar emu-default-keys
  `(((subject ,(rx (group "bug#" (1+ digit))) :name "Bugs")
     (subject ,(rx (group "bug#" (1+ digit))) :match-group 1))
    ((not :name "Non-list" :keys (list))
     from thread)
    ((list :name "Mailing lists") list thread))
  "Default keys.")

(defvar emu-mailing-list-keys `(thread))

;; (setq emu-default-keys emu-mailing-list-keys)

;;;; Columns

(eval-and-compile
  (taxy-magit-section-define-column-definer "emu"))

(emu-define-column "From" (:max-width 40 :face emu-contact)
  (cl-labels ((format-contact (contact)
                (pcase-let* (((map :email :name) contact)
                             (address (format "<%s>" email))
                             (name (when name
                                     (format "%s " name))))
                  (concat name address))))
    (pcase-let* (((and meta (map :thread-subject)) (mu4e-message-field item :meta))
                 (prefix (when thread-subject
                           (concat (mu4e~headers-thread-prefix meta) " "))))
      ;; (concat prefix
      ;;         (string-join (mapcar #'format-contact (mu4e-message-field item :from)) ","))
      (string-join (mapcar #'format-contact (mu4e-message-field item :from)) ","))))

(emu-define-column "Subject" (:face emu-subject :max-width 100)
  (mu4e-message-field item :subject))

(emu-define-column "Thread" (:face emu-subject :max-width 100)
  (let* ((meta (mu4e-message-field item :meta))
         (subject (mu4e-message-field item :subject)))
    (if (plist-get meta :thread-subject)
        (concat (mu4e~headers-thread-prefix meta)
                " " subject)
      subject)))

(emu-define-column "Date" (:face org-time-grid)
  (format-time-string "%c" (mu4e-message-field item :date)))

(emu-define-column "List" ()
  (mu4e-message-field item :list))

(emu-define-column "Maildir" ()
  (mu4e-message-field item :maildir))

(emu-define-column "Flags" (:face font-lock-warning-face)
  (mu4e~headers-flags-str (mu4e-message-field item :flags)))

(unless emu-columns
  (setq-default emu-columns
                (get 'emu-columns 'standard-value)))

(setq emu-columns '("Flags" "Date" "From" "Thread" "Maildir"))

;;;; Commands

;; (cl-defun emu (query)
;;   "FIXME: "
;;   (interactive (list mu4e--search-last-query))
;;   (let* ((mu4e-headers-append-func #'emu--headers-append-func)
;;          (rewritten-expr (funcall mu4e-query-rewrite-function query))
;;          (maxnum (unless mu4e-search-full mu4e-search-results-limit)))
;;     (mu4e--server-find
;;      rewritten-expr
;;      mu4e-search-threads
;;      mu4e-search-sort-field
;;      mu4e-search-sort-direction
;;      maxnum
;;      mu4e-search-skip-duplicates
;;      mu4e-search-include-related)))

(cl-defun emu--headers-append-func (messages)
  "FIXME: "
  (let ((buffer (get-buffer-create "*emu*")))
    (with-current-buffer buffer
      (with-silent-modifications
        (erase-buffer)
        (delete-all-overlays)
        (emu-view-mode)
        (setf messages (nreverse (cl-sort messages #'time-less-p
                                          :key (lambda (message)
                                                 (mu4e-message-field message :date)))))
        (save-excursion
          (emu--insert-taxy-for messages :query mu4e--search-last-query
                                      :prefix-item (lambda (message)
                                                     (mu4e~headers-docid-cookie (mu4e-message-field message :docid)))
                                      :item-properties (lambda (message)
                                                         (list 'docid (plist-get message :docid)
                                                               'msg message))
                                      :add-faces (lambda (message)
                                                   (remq nil
                                                         (list (when (member 'unread (mu4e-message-field message :flags))
                                                                 'emu-unread)
                                                               (when (member 'flagged (mu4e-message-field message :flags))
                                                                 'emu-flagged)
                                                               ;; (when (member 'new (mu4e-message-field message :flags))
                                                               ;;   'emu-new)
                                                               )))))
        (when magit-section-visibility-cache
          (save-excursion
            ;; Somehow `magit-section-forward' isn't working from the root section.
            (forward-line 1)
            (cl-loop with last-section = (magit-current-section)
                     do (oset (magit-current-section) hidden
                              (magit-section-cached-visibility (magit-current-section)))
                     while (progn
                             (forward-line 1)
                             (and (magit-current-section)
                                  (not (eobp))
                                  (not (equal last-section (magit-current-section))))))))
        (pop-to-buffer (current-buffer))))))

;;;; Headers commands

;; What a mess, all because mu4e uses `defsubsts' in many places it
;; shouldn't.

(defmacro emu-defcommand (command)
  "FIXME: COMMAND."
  (declare (debug (&define symbolp)))
  (let ((new-name (intern (concat "emu-" (symbol-name command)))))
    `(defun ,new-name (&rest args)
       (interactive)
       ;; HACK: The hackiest of hacks, but it seems to work...
       (let ((major-mode 'mu4e-headers-mode))
         (save-excursion
           (cl-typecase (oref (magit-current-section) value)
             (taxy (dolist (child (oref (magit-current-section) children))
                     (magit-section-goto child)
                     (funcall ',new-name)))
             (otherwise (call-interactively ',command))))))))

(defmacro emu-define-mark-command (command)
  "FIXME: COMMAND."
  (declare (debug (&define symbolp)))
  (let ((new-name (intern (concat "emu-" (symbol-name command)))))
    `(defun ,new-name (&rest args)
       (interactive)
       ;; HACK: The hackiest of hacks, but it seems to work...
       (let ((major-mode 'mu4e-headers-mode))
         (save-excursion
           (cl-typecase (oref (magit-current-section) value)
             (taxy (dolist (child (oref (magit-current-section) children))
                     (magit-section-goto child)
                     (funcall ',new-name)))
             (otherwise (call-interactively ',command)))))
       (magit-section-forward))))

(defun emu-message-at-point ()
  (let ((major-mode 'mu4e-headers-mode))
    (mu4e-message-at-point)))

;;;; Mode

(defvar-keymap emu-view-mode-map
  :parent magit-section-mode-map
  :doc "Local keymap for `emu-view-mode' buffers."
  "g" #'revert-buffer
  "s" #'mu4e-search
  "RET" (emu-defcommand mu4e-headers-view-message)
  "!" (emu-define-mark-command mu4e-headers-mark-for-read)
  "d" (emu-define-mark-command mu4e-headers-mark-for-trash)
  "+" (emu-define-mark-command mu4e-headers-mark-for-flag)
  "-" (emu-define-mark-command mu4e-headers-mark-for-unflag)
  "r" (emu-define-mark-command mu4e-headers-mark-for-refile)
  "u" (emu-define-mark-command mu4e-headers-mark-for-unmark)
  "x" (emu-defcommand mu4e-mark-execute-all))

(define-derived-mode emu-view-mode magit-section-mode
  "emu"
  "FIXME:"
  :group 'mu4e
  :interactive nil
  ;; HACK:
  (mu4e--mark-initialize)
  (setq revert-buffer-function #'emu-revert-buffer))

(define-minor-mode emu-mode
  "FIXME:"
  :global t
  :group 'mu4e
  (if emu-mode
      (setf emu-old-headers-append-func mu4e-headers-append-func
            mu4e-headers-append-func #'emu--headers-append-func)
    (setf mu4e-headers-append-func emu-old-headers-append-func
          emu-old-headers-append-func nil))
  (message "emu-mode %s." (if emu-mode "enabled" "disabled")))

;;;; Functions

(defun emu-revert-buffer (&optional _ignore-auto _noconfirm)
  "Revert `emu-mode' buffer.
Runs `emu' again with the same query."
  (emu-mu4e-mark-execute-all)
  (mu4e-search mu4e--search-last-query))

(cl-defun emu--insert-taxy-for
    (messages &key (keys emu-default-keys) (query mu4e--search-last-query)
              (prefix-item #'ignore) (item-properties #'ignore) (add-faces #'ignore))
  "Insert and return a `taxy' for `emu', optionally having ITEMS.
KEYS should be a list of grouping keys, as in
`emu-default-keys'."
  (let (format-table column-sizes)
    (cl-labels ((format-item (item)
                  (let ((string (concat (funcall prefix-item item)
                                        (gethash item format-table))))
                    (add-text-properties 0 (length string)
                                         (funcall item-properties item) string)
                    (dolist (face (funcall add-faces item))
                      (add-face-text-property 0 (length string) face nil string))
                    string))
                (make-fn (&rest args)
                  (apply #'make-taxy-magit-section
                         :make #'make-fn
                         :format-fn #'format-item
                         ;; FIXME: Make indent an option again.
                         :level-indent 2
                         ;; :visibility-fn #'visible-p
                         ;; :heading-indent 2
                         :item-indent 0
                         ;; :heading-face-fn #'heading-face
                         args)))
      (let* ((taxy-magit-section-insert-indent-items nil)
             ;; (taxy-magit-section-item-indent 0)
             ;; (taxy-magit-section-level-indent 0)
             (taxy
              (thread-last
                (make-fn :name (format "mu4e: %s" query)
                         :take (taxy-make-take-function keys emu-keys))
                (taxy-fill messages)))
             (format-cons
              (taxy-magit-section-format-items
               emu-columns emu-column-formatters
               taxy))
             (inhibit-read-only t))
        (setf format-table (car format-cons)
              column-sizes (cdr format-cons)
              header-line-format (taxy-magit-section-format-header
                                  column-sizes emu-column-formatters)
              ;; Sort taxys by the most recent message in each.
              taxy (thread-last taxy
                                (taxy-sort-taxys (lambda (a b)
                                                   (not (time-less-p a b)))
                                  (lambda (taxy)
                                    (when (taxy-items taxy)
                                      (mu4e-message-field (car (seq-sort (lambda (a b)
                                                                           (not (time-less-p (mu4e-message-field a :date)
                                                                                             (mu4e-message-field b :date))))
                                                                         (taxy-items taxy)))
                                                          :date))))
                                (taxy-sort-taxys (lambda (a _b)
                                                   (not (equal a "Mailing lists")))
                                  #'taxy-name)))
        ;; Before this point, no changes have been made to the buffer's contents.
        (let (magit-section-visibility-cache)
          (save-excursion
            (taxy-magit-section-insert taxy :items 'first :initial-depth 0)))
        taxy))))

(provide 'emu)
;;; emu.el ends here