;;; ducpel.el --- Logic game with sokoban elements

;; Copyright (C) 2014 Alex Kost

;; Author: Alex Kost <alezost@gmail.com>
;; Created: 31 Mar 2014
;; Version: 0.1
;; Package-Requires: ((cl-lib "0.5"))
;; URL: https://github.com/alezost/ducpel
;; Keywords: games

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; To install the game manually, you need:
;;
;; - "ducpel.el" (this file);
;; - "ducpel-glyphs.el" (it generates default images);
;; - directory with levels.
;;
;; Add the following to your emacs init file:
;;
;;   (add-to-list 'load-path "/path/to/ducpel-dir")
;;   (autoload 'ducpel "ducpel" nil t)
;;
;; Also if you keep levels separately:
;;
;;   (setq ducpel-levels-directory "/path/to/ducpel-levels-dir")

;; After that you can "M-x ducpel" and enjoy.  Use:
;;
;; - arrow keys to move your man;
;; - TAB to switch to another man;
;; - "u" to undo a move;
;; - SPC to activate a special cell (exit or teleport);
;; - "R" to restart the level;
;; - "N"/"P"/"L" to go to the next/previous/particular level.

;; At any time you can replay your moves by pressing "rc" (2 keys).  If
;; you feel that a level is impassable, you may surrender (and see a
;; solution) by pressing "rS".

;; Contact the maintainer please, if you found a better solution (with
;; less moves) for some level or if you made an interesting level that
;; can become a part of ducpel.

;; For full documentation, see <https://github.com/alezost/ducpel>.

;;; Code:

(require 'cl-lib)
(require 'gamegrid)


;;; User options

(defgroup ducpel nil
  "Logic game."
  :group 'games)

(defcustom ducpel-use-glyphs t
  "If non-nil, use glyphs when available."
  :type 'boolean
  :group 'ducpel)

(defcustom ducpel-buffer-name "*ducpel*"
  "Name of the ducpel buffer."
  :type 'string
  :group 'ducpel)

(defcustom ducpel-replay-pause 0.5
  "Number of seconds to wait between moves during replaying.
To replay the moves, use
\\[ducpel-replay-current] in a ducpel buffer."
  :type 'number
  :group 'ducpel)

(defcustom ducpel-levels-directory
  (expand-file-name "levels"
                    (file-name-directory (locate-library "ducpel")))
  "Directory with level files."
  :type 'directory
  :group 'ducpel)

(defcustom ducpel-user-levels-directory user-emacs-directory
  "Directory with additional level files.
To load a level from this directory, use
\\[ducpel-load-level-from-file] in a ducpel buffer."
  :type 'directory
  :group 'ducpel)

(defcustom ducpel-user-saves-directory user-emacs-directory
  "Directory with saves of moves.
To replay saved moves from this directory, use
\\[ducpel-replay-from-file] in a ducpel buffer."
  :type 'directory
  :group 'ducpel)

(defcustom ducpel-default-level 1
  "Default level."
  :type 'integer
  :group 'ducpel)


;;; Constants

;; Cell types
(defconst ducpel-empty 0)
(defconst ducpel-wall 1)
(defconst ducpel-impassable 2)
(defconst ducpel-floor 3)
(defconst ducpel-man 4)
(defconst ducpel-active-man 5)
(defconst ducpel-box 6)

;; Floor/box types
(defconst ducpel-simple 0)
(defconst ducpel-exit 1)
(defconst ducpel-teleport 2)
(defconst ducpel-left 3)
(defconst ducpel-right 4)
(defconst ducpel-up 5)
(defconst ducpel-down 6)
(defconst ducpel-horizontal 7)
(defconst ducpel-vertical 8)
(defconst ducpel-multi 9)

(defconst ducpel-cell-types
  (list ducpel-empty ducpel-wall ducpel-impassable
        ducpel-floor ducpel-man ducpel-active-man ducpel-box)
  "List of available cell types.")

(defconst ducpel-floor-types
  (list ducpel-simple ducpel-exit ducpel-teleport
        ducpel-left ducpel-right ducpel-up ducpel-down
        ducpel-horizontal ducpel-vertical ducpel-multi)
  "List of available floor/box types.")

;; The maximum count of cell characters is limited to 256.
;; Currently we have:
;;
;; - by 1 for empty, wall and impassable cells;
;; - 10 floors;
;; - 20 men (active and passive on each floor);
;; - 100 boxes (each box type on each floor).
;;
;; So there is a space to avoid printable ASCII characters and some
;; control characters (see (info "(elisp) Usual Display")) to be able to
;; write something in a ducpel buffer along with having the map of
;; glyphs.  If the count of cell types is increased significantly, we
;; will have to use printable chars and thus to refuse writing text in
;; the buffer (and perhaps to use the modeline instead).

(defconst ducpel-init-cell-char-alist
  (let ((len (length ducpel-floor-types))
        (floor-shift 126))
    (list
     (cons ducpel-empty      23)
     (cons ducpel-wall       24)
     (cons ducpel-impassable 25)
     (cons ducpel-floor      floor-shift)
     (cons ducpel-man        (+ len floor-shift))
     (cons ducpel-active-man (+ (* 2 len) floor-shift))
     (cons ducpel-box        (+ (* 3 len) floor-shift))))
  "Alist of initial cell characters for the cell types.
Car of each assoc is a cell type.  Cdr is a cell character.")

;; Move types
(defconst ducpel-left-move  #b0001)
(defconst ducpel-right-move #b0010)
(defconst ducpel-up-move    #b0100)
(defconst ducpel-down-move  #b1000)
(defconst ducpel-action 3)

(defconst ducpel-move-type-alist
  (list
   (cons ducpel-left       ducpel-left-move)
   (cons ducpel-right      ducpel-right-move)
   (cons ducpel-up         ducpel-up-move)
   (cons ducpel-down       ducpel-down-move)
   (cons ducpel-horizontal (+ ducpel-left-move ducpel-right-move))
   (cons ducpel-vertical   (+ ducpel-up-move   ducpel-down-move))
   (cons ducpel-multi      (+ ducpel-left-move ducpel-right-move
                              ducpel-up-move   ducpel-down-move)))
  "Alist of possible moves for the floor types.
Car of each assoc is a floor type.  Cdr is a move type.")

(defconst ducpel-break-wall-power 3
  "Power (minimum count of pushing men) required to break a wall.")

;; Constants for parsing level maps

(defconst ducpel-map-re "^;+ *Map")
(defconst ducpel-objects-re "^;+ *Objects")
(defconst ducpel-solution-re "^;+ *Solution")

(defconst ducpel-ignored-line-re
  (rx line-start
      (or (and ";" (* any))
          (* blank))
      line-end)
  "Regexp for ignored lines in level files.")

(defconst ducpel-empty-map-char ?\s)
(defconst ducpel-wall-map-char ?#)
(defconst ducpel-impassable-map-char ?@)
(defconst ducpel-floor-map-chars ".ETLRUDHVM")
(defconst ducpel-box-map-chars   "betlrudhvm")
(defconst ducpel-man-map-char ?p)
(defconst ducpel-active-man-map-char ?P)


;;; General variables

(defvar ducpel-men []
  "Array of coordinates of the men on the current level.
Each element of the list is a list of the form (X Y).")

(defvar ducpel-active-man-index 0
  "Index of the active man in `ducpel-men'.")

(defvar ducpel-teleports nil
  "List of coordinates of the teleports on the current level.
Each element of the list is a list of the form (X Y).")

(defvar ducpel-undo-list nil
  "List of full undo information.

Each element of the list has a form:

  (CELLS MEN ACTIVE TELEPORTS)

CELLS has a form of `ducpel-undo-current-cells'.
MEN has a form of `ducpel-undo-current-men'.
ACTIVE has a form of `ducpel-undo-current-active-index'.
TELEPORTS has a form of `ducpel-undo-current-teleports'.")

(defvar ducpel-undo-current-cells nil
  "List of changes of the cells made after the last move.

Each element of the list has a form:

  (X Y CHAR)

X, Y - coordinates of the changed cell;
CHAR is a gamegrid character of the changed cell.

If nil, it means the cells were not changed.")

(defvar ducpel-undo-current-men []
  "Array of men coordinates changed after the last move.
Has a form of `ducpel-men'.  If an element of the array is nil,
it means the coordinates of the man were not changed.")

(defvar ducpel-undo-current-active-index nil
  "Index of the man that was active after the last move.
If nil, it means the active man was not changed.")

(defvar ducpel-undo-current-teleports nil
  "List of coordinates of the teleports after the last move.
Has a form of `ducpel-teleports'.
If nil, it means teleports were not changed.")

(defvar ducpel-moves 0
  "The number of moves for the current level.")

(defvar ducpel-done 0
  "The number of men went to a better world.")

(defvar ducpel-moves-history nil
  "List of moves for the current level.

Each element of the list has a form:

  (MAN MOVE-TYPE)

MAN is the index (from `ducpel-men') of a man who made the move.
For the meaning of MOVE-TYPE, see `ducpel-do'.

Car of the list is the last move; the last element of the list is
the first move.")

(defvar ducpel-solution nil
  "List of moves to solve the current level.
Has a form of `ducpel-moves-history'.")

(defvar ducpel-level-data nil
  "Data of the current level map.
2-dimensional matrix (vector of vectors) of the width
`ducpel-width' and the height `ducpel-height' that contains cell
characters for the current level.")

(defvar ducpel-level nil
  "Index of the current level.")

(defvar ducpel-level-file nil
  "Name of file with a map of the current level.")

(defvar ducpel-width 0
  "Width of the current level map.")

(defvar ducpel-height 0
  "Height of the current level map.")


;;; Cells

(defvar ducpel-cell-plists (make-vector 256 nil)
  "Array of property lists for all possible cell characters.
Properties in property lists:
`:type' - type of the cell - element from `ducpel-cell-types';
`:floor'/`:box' (optional) - type of the floor/box - element from
`ducpel-floor-types'.")

(defun ducpel-get-cell-char-by-plist (&rest plist)
  "Return cell character by the property list PLIST."
  (let ((type (plist-get plist :type))
        (floor-index (or (plist-get plist :floor) 0))
        (box-index (or (plist-get plist :box) 0))
        (len (length ducpel-floor-types)))
    (let ((init-char (cdr (assoc type ducpel-init-cell-char-alist))))
      (+ init-char
         floor-index
         (* box-index len)))))

(defun ducpel-init-cell-plists ()
  "Fill `ducpel-cell-plists'."
  (cl-flet ((pset (&rest plist)
                  (aset ducpel-cell-plists
                        (apply 'ducpel-get-cell-char-by-plist plist)
                        plist)))
    (pset :type ducpel-empty)
    (pset :type ducpel-wall)
    (pset :type ducpel-impassable)
    (dolist (floor ducpel-floor-types)
      (pset :type ducpel-floor      :floor floor)
      (pset :type ducpel-man        :floor floor)
      (pset :type ducpel-active-man :floor floor)
      (dolist (box ducpel-floor-types)
        (pset :type ducpel-box :floor floor :box box)))))

(ducpel-init-cell-plists)

(defun ducpel-get-cell-plist-by-cell-char (char)
  "Return cell property list by the cell character CHAR."
  (aref ducpel-cell-plists char))

(defun ducpel-get-cell-plist-by-xy (x y)
  "Return cell property list by the cell coordinates X, Y."
  (ducpel-get-cell-plist-by-cell-char
   (gamegrid-get-cell x y)))

(defun ducpel-set-cell (x y &rest plist)
  "Set cell at X, Y to the cell defined by property list PLIST.
Return cell character of the set cell."
  (let* ((old-char (gamegrid-get-cell x y))
         (new-char (apply 'ducpel-get-cell-char-by-plist plist)))
    (gamegrid-set-cell x y new-char)
    (push (list x y old-char) ducpel-undo-current-cells)
    new-char))


;;; Men

(defun ducpel-get-man-index-by-shift (shift &optional index)
  "Return new index by shifting man INDEX with SHIFT.
If INDEX is nil, use `ducpel-active-man-index'."
  (ducpel-get-index-by-shift
   (length ducpel-men)
   (or index ducpel-active-man-index)
   shift))

(defun ducpel-get-man-xy (&optional index)
  "Return coordinates of a man.
INDEX is a number of the man in `ducpel-men'.  If INDEX is nil,
use `ducpel-active-man-index'.
Returning value is a list of the form (X Y)."
  (or index
      (setq index ducpel-active-man-index))
  (aref ducpel-men index))

(defun ducpel-get-man-index-by-xy (x y)
  "Return index of a man placed on X, Y cell."
  (or (ducpel-get-index-by-element
       ducpel-men (list x y) 'equal 'noerror)
      (error "No man with %d, %d coordinates"
             x y)))

(defun ducpel-set-man-xy (from-x from-y to-x to-y)
  "Set coordinates of a man from FROM-X, FROM-Y to TO-X, TO-Y."
  (let ((index (ducpel-get-man-index-by-xy from-x from-y)))
    (aset ducpel-undo-current-men index (list from-x from-y))
    (aset ducpel-men index (list to-x to-y))))

(defun ducpel-delete-man (index)
  "Delete man INDEX from the current map."
  (cl-multiple-value-bind (x y)
      (ducpel-get-man-xy index)
    (aset ducpel-undo-current-men index (list x y))
    (aset ducpel-men index nil)
    (let ((plist (ducpel-get-cell-plist-by-xy x y)))
      (ducpel-set-cell x y
                       :type ducpel-floor
                       :floor (plist-get plist :floor)))))

(defun ducpel-set-active-man (index)
  "Try to set a man INDEX active.

INDEX is a number of the man in `ducpel-men'.  If the man does
not exist, try to set the next man active, and so on.

Return index of the new active man or nil if no man was set."
  (unless (and (= index ducpel-active-man-index)
               (aref ducpel-men index))
    (ducpel-set-active-man-1
     index (ducpel-get-man-index-by-shift -1 index))))

(defun ducpel-set-active-man-1 (index exit-index)
  "Set a man active.

INDEX is a number of the man in `ducpel-men'.  If the man does
not exist, try to set the next man active, and so on until the
man with index EXIT-INDEX will not be achieved.  In this case,
return nil; otherwise return index of the new active man."
  (unless (= index exit-index)
    (cl-multiple-value-bind (new-x new-y)
        (ducpel-get-man-xy index)
      (if (null new-x)
          (ducpel-set-active-man-1
           (ducpel-get-man-index-by-shift 1 index)
           exit-index)
        (cl-multiple-value-bind (old-x old-y)
            (ducpel-get-man-xy)
          (when old-x    ; previously active man could be "Done" already
            (let ((old-plist (ducpel-get-cell-plist-by-xy old-x old-y)))
              (ducpel-set-cell old-x old-y
                               :type ducpel-man
                               :floor (plist-get old-plist :floor)))))
        (let ((new-plist (ducpel-get-cell-plist-by-xy new-x new-y)))
          (ducpel-set-cell new-x new-y
                           :type ducpel-active-man
                           :floor (plist-get new-plist :floor)))
        (or ducpel-undo-current-active-index
            (setq ducpel-undo-current-active-index
                  ducpel-active-man-index))
        (setq ducpel-active-man-index index)))))

(defun ducpel-get-active-cell-xy ()
  "Return coordinates of the cell with the active man.
Returning value is a list of the form (X Y)."
  (aref ducpel-men ducpel-active-man-index))

(defun ducpel-get-active-cell-plist ()
  "Return cell plist of the cell with the active man."
  (apply 'ducpel-get-cell-plist-by-xy
         (ducpel-get-active-cell-xy)))

(defun ducpel-next-man ()
  "Select next man."
  (interactive)
  (ducpel-set-active-man (ducpel-get-man-index-by-shift 1)))

(defun ducpel-previous-man ()
  "Select previous man."
  (interactive)
  (ducpel-set-active-man (ducpel-get-man-index-by-shift -1)))


;;; Doing (moves and actions)

(defun ducpel-do (move-type)
  "Try to make a move or perform an action with active man.
Save undo history if the move/action was successful.
MOVE-TYPE is one of the following constants: `ducpel-action',
`ducpel-left-move', `ducpel-right-move', `ducpel-up-move',
`ducpel-down-move'."
  (unless (ducpel-done-p t)
    (let ((man ducpel-active-man-index))
      (when (if (eql move-type ducpel-action)
                (ducpel-do-action)
              (ducpel-do-move move-type))
        (ducpel-add-move)
        (push (list man move-type) ducpel-moves-history)
        (ducpel-undo-save-current)))))

(defun ducpel-do-action ()
  "Perform an action on the current cell.
Return non-nil if the action was successful."
  (let* ((plist (ducpel-get-active-cell-plist))
         (floor (plist-get plist :floor))
         success)
    (cond
     ((eql floor ducpel-exit)
      (ducpel-delete-man ducpel-active-man-index)
      (ducpel-set-active-man (ducpel-get-man-index-by-shift 1))
      (ducpel-check-done)
      (ducpel-print-done)
      (ducpel-done-p t)
      (setq success t))
     ((eql floor ducpel-teleport)
      (if (null (cdr ducpel-teleports))
          ;; If a single teleport on the map
          (message "This strange thing looks broken.")
        (if (ducpel-teleport-active-man)
            (setq success t)
          (message "Hm, perhaps the teleport is blocked."))))
     (t (message "Nothing interesting here.")))
    success))

(defun ducpel-do-move (direction)
  "Move active man in the DIRECTION.
For the meaning of DIRECTION, see `ducpel-cell-can-move-p'.
Return non-nil if the move was successful."
  (cl-multiple-value-bind (x y)
      (ducpel-get-man-xy)
    (ducpel-move x y direction)))

(defun ducpel-teleport-active-man ()
  "Try to teleport active man to a free teleport cell.
If the next teleport after the current one is blocked, try the
next after it and so on.
Return non-nil, if teleportation was successful."
  (let* ((active-xy (ducpel-get-active-cell-xy))
         (next-teleports (member active-xy ducpel-teleports)))
    (or next-teleports
        (error "Active man is not on the teleport cell"))
    ;; Getting next free teleport: if the rest teleports are blocked,
    ;; continue searching from the beginning of `ducpel-teleports'.
    (let ((xy (or (ducpel-teleport-get-free-cell (cdr next-teleports))
                  (ducpel-teleport-get-free-cell
                   (cl-loop for teleport in ducpel-teleports
                            until (equal teleport active-xy)
                            collect teleport)))))
      (when xy
        (let ((from-x (car active-xy))
              (from-y (cadr active-xy))
              (to-x (car xy))
              (to-y (cadr xy)))
          (ducpel-set-cell
           to-x to-y
           :type ducpel-active-man :floor ducpel-teleport)
          (ducpel-set-cell
           from-x from-y
           :type ducpel-floor :floor ducpel-teleport)
          (ducpel-set-man-xy from-x from-y to-x to-y)
          t)))))

(defun ducpel-teleport-get-free-cell (cells)
  "Return first free cell from a list of coordinates CELLS.
Cell is free if it is a floor with no object (man or box) on it.
Return nil if none of the cells is free."
  (cl-loop for cell in cells
           if (eql (plist-get
                    (apply 'ducpel-get-cell-plist-by-xy cell)
                    :type)
                   ducpel-floor)
           return cell))

(defun ducpel-cell-can-move-p (floor-type direction)
  "Return non-nil, if a cell with FLOOR-TYPE can move in the DIRECTION.
Direction should have a value of one of the following constants:
`ducpel-left-move', `ducpel-right-move',
`ducpel-up-move', `ducpel-down-move'."
  (let ((moves (cdr (assoc floor-type ducpel-move-type-alist))))
    (and moves
         (/= 0 (logand moves direction)))))

(defun ducpel-get-xy (from-x from-y direction &optional val)
  "Return coordinates by shifting FROM-X, FROM-Y to the DIRECTION by VAL.
For the meaning of DIRECTION, see `ducpel-cell-can-move-p'.
If VAL is nil, shift coordinates by 1.
Returning value is a list of the form (X Y)."
  (let ((x from-x)
        (y from-y)
        (val (or val 1)))
    (cond
     ((eql direction ducpel-left-move)  (cl-decf x val))
     ((eql direction ducpel-right-move) (cl-incf x val))
     ((eql direction ducpel-up-move)    (cl-decf y val))
     ((eql direction ducpel-down-move)  (cl-incf y val)))
    (list x y)))

(defun ducpel-get-last-empty-xy (x y direction)
  "Return last cell of `ducpel-empty' type by moving from X, Y in DIRECTION.
For the meaning of DIRECTION, see `ducpel-cell-can-move-p'.
Returning value is a list of coordinates of the last empty cell."
  (let (next-x next-y)
    (while (progn
             (cl-multiple-value-setq (next-x next-y)
               (ducpel-get-xy x y direction))
             (let* ((char  (gamegrid-get-cell next-x next-y))
                    (plist (ducpel-get-cell-plist-by-cell-char char))
                    (type  (plist-get plist :type)))
               (eql type ducpel-empty)))
      (setq x next-x
            y next-y))
    (list x y)))

(defun ducpel-check-done ()
  "Count and set `ducpel-done'."
  (let ((done 0))
    (dotimes (i (length ducpel-men))
      (or (aref ducpel-men i) (cl-incf done)))
    (setq ducpel-done done)))

(defun ducpel-done-p (&optional show-message)
  "Return non-nil if current level is passed.
If SHOW-MESSAGE is non-nil, also show a message in minibuffer."
  (let ((done (= ducpel-done (length ducpel-men))))
    (and done
         show-message
         ;; FIXME Do not hardcode the bindings
         (message "DONE! Press 'r c' to replay, 'r s' to save, 'R' to restart, 'N' for the next level."))
    done))

(defun ducpel-add-move ()
  "Increase the current count of moves."
  (cl-incf ducpel-moves)
  (ducpel-print-moves))

(defun ducpel-remove-move ()
  "Decrease the current count of moves."
  (cl-decf ducpel-moves)
  (ducpel-print-moves))

(defun ducpel-action ()
  "Perform an action on the current cell."
  (interactive)
  (ducpel-do ducpel-action))

(defun ducpel-move-left ()
  "Move one cell left."
  (interactive)
  (ducpel-do ducpel-left-move))

(defun ducpel-move-right ()
  "Move one cell right."
  (interactive)
  (ducpel-do ducpel-right-move))

(defun ducpel-move-up ()
  "Move one cell up."
  (interactive)
  (ducpel-do ducpel-up-move))

(defun ducpel-move-down ()
  "Move one cell down."
  (interactive)
  (ducpel-do ducpel-down-move))

;; The following variables are used only during a move by
;; `ducpel-move-<smth>-to-<smth>' functions and are set by
;; `ducpel-move'.
(defvar ducpel-from-x nil)
(defvar ducpel-from-y nil)
(defvar ducpel-from-char nil)
(defvar ducpel-from-plist nil)
(defvar ducpel-from-type nil)
(defvar ducpel-to-x nil)
(defvar ducpel-to-y nil)
(defvar ducpel-to-char nil)
(defvar ducpel-to-plist nil)
(defvar ducpel-to-type nil)
(defvar ducpel-power nil)
(defvar ducpel-direction nil)

(defun ducpel-move (x y direction &optional power)
  "Move cell at X, Y in the DIRECTION with POWER.
For the meaning of DIRECTION, see `ducpel-cell-can-move-p'.
Return non-nil if the shift was successful, nil otherwise."
  (let* ((ducpel-from-x x)
         (ducpel-from-y y)
         (ducpel-power (or power 0))
         (ducpel-direction direction)
         (ducpel-from-char (gamegrid-get-cell x y))
         (ducpel-from-plist (ducpel-get-cell-plist-by-cell-char
                             ducpel-from-char))
         (ducpel-from-type (plist-get ducpel-from-plist :type))
         success)
    ;; Most cell types can't be moved
    (unless (memql ducpel-from-type
                   (list ducpel-empty ducpel-wall
                         ducpel-impassable ducpel-floor))
      (cl-multiple-value-bind (ducpel-to-x ducpel-to-y)
          (ducpel-get-xy ducpel-from-x ducpel-from-y
                         ducpel-direction)
        (let* ((ducpel-to-char (gamegrid-get-cell ducpel-to-x ducpel-to-y))
               (ducpel-to-plist (ducpel-get-cell-plist-by-cell-char
                                 ducpel-to-char))
               (ducpel-to-type (plist-get ducpel-to-plist :type)))
          (cond
           ;; If a move is successful, redraw only the destination cell
           ;; (`ducpel-to-x', `ducpel-to-y').  If it was a move of the
           ;; active man, also redraw the departure cell
           ;; (`ducpel-from-x', `ducpel-from-y').

           ;; We want to move a MAN
           ((eql ducpel-from-type ducpel-man)
            (cl-incf ducpel-power)
            (when (or (ducpel-move-object-to-floor)
                      (ducpel-move-object-to-wall))
              (ducpel-set-man-xy ducpel-from-x ducpel-from-y
                                 ducpel-to-x   ducpel-to-y)
              (setq success t)))

           ;; We want to move an ACTIVE MAN
           ((eql ducpel-from-type ducpel-active-man)
            (cl-incf ducpel-power)
            (let ((new-from-plist
                   (cond
                    ((or (ducpel-move-object-to-floor)
                         (ducpel-move-object-to-wall))
                     (list :type ducpel-floor
                           :floor (plist-get ducpel-from-plist :floor)))
                    ((ducpel-move-man-to-emty)
                     (list :type ducpel-empty)))))
              (when new-from-plist
                (ducpel-set-man-xy ducpel-from-x ducpel-from-y
                                   ducpel-to-x ducpel-to-y)
                (apply 'ducpel-set-cell
                       ducpel-from-x ducpel-from-y new-from-plist)
                (setq success t))))

           ;; We want to move a BOX
           ((and (eql ducpel-from-type ducpel-box)
                 (> ducpel-power 0))
            (cl-decf ducpel-power)
            (when (or (ducpel-move-object-to-floor)
                      (ducpel-move-object-to-wall)
                      (ducpel-move-box-to-empty))
              (setq success t)))))))
    success))

(defun ducpel-move-object-to-floor ()
  "Try to move an object (man or box) to a floor.
If a destination cell contains another object, try to move it at first.
If the move is possible, redraw the destination cell and
return non-nil."
  (when (or (eql ducpel-to-type ducpel-floor)
            (and (or (eql ducpel-to-type ducpel-man)
                     (eql ducpel-to-type ducpel-box))
                 (ducpel-move ducpel-to-x ducpel-to-y
                              ducpel-direction ducpel-power)))
    (ducpel-set-cell ducpel-to-x ducpel-to-y
                     :type ducpel-from-type
                     :floor (plist-get ducpel-to-plist :floor)
                     :box (plist-get ducpel-from-plist :box))))

(defun ducpel-move-object-to-wall ()
  "Try to move an object (man or box) to a wall.
If the move is possible, redraw the destination cell and
return non-nil."
  (when (and (eql ducpel-to-type ducpel-wall)
             (>= ducpel-power ducpel-break-wall-power))
    (ducpel-set-cell ducpel-to-x ducpel-to-y
                     :type ducpel-from-type :floor ducpel-simple)))

(defun ducpel-move-man-to-emty ()
  "Try to move a man to an empty cell.
If the move is possible, redraw the destination cell and
return non-nil."
  (when (and (eql ducpel-to-type ducpel-empty)
             (ducpel-cell-can-move-p
              (plist-get ducpel-from-plist :floor) ducpel-direction))
    (cl-multiple-value-setq (ducpel-to-x ducpel-to-y)
      (ducpel-get-last-empty-xy ducpel-to-x ducpel-to-y
                                ducpel-direction))
    (ducpel-set-cell ducpel-to-x ducpel-to-y
                     :type ducpel-from-type
                     :floor (plist-get ducpel-from-plist :floor))))

(defun ducpel-move-box-to-empty ()
  "Try to move a box to an empty cell.
If the move is possible, redraw the destination cell and
return non-nil."
  (when (eql ducpel-to-type ducpel-empty)
    (when (eql (plist-get ducpel-from-plist :box)
               ducpel-teleport)
      (setq ducpel-undo-current-teleports ducpel-teleports)
      (push (list ducpel-to-x ducpel-to-y)
            ducpel-teleports))
    (ducpel-set-cell ducpel-to-x ducpel-to-y
                     :type ducpel-floor
                     :floor (plist-get ducpel-from-plist :box))))


;;; Undoing

;; To restore the previous state of the grid, we need to keep track of
;; changed cells, coordinates of the men and index of an active man.

(defun ducpel-undo-reset-current ()
  "Reset current undo data to the default values."
  (setq ducpel-undo-current-cells nil
        ducpel-undo-current-teleports nil
        ducpel-undo-current-men (make-vector (length ducpel-men) nil)
        ducpel-undo-current-active-index nil))

(defun ducpel-undo-init ()
  "Initialize undo data."
  (setq ducpel-undo-list nil)
  (ducpel-undo-reset-current))

(defun ducpel-undo-save-current ()
  "Add undo info about the current move to `ducpel-undo-list'."
  (push (list ducpel-undo-current-cells
              ducpel-undo-current-men
              ducpel-undo-current-active-index
              ducpel-undo-current-teleports)
        ducpel-undo-list)
  (ducpel-undo-reset-current))

(defun ducpel-undo-changes (cells men active teleports)
  "Undo changes from CELLS, MEN, ACTIVE and TELEPORTS.
For the meaning of arguments, see `ducpel-undo-list'."
  (mapc (lambda (change)
          (apply 'gamegrid-set-cell change))
        cells)
  (dotimes (i (length men))
    (let ((man (aref men i)))
      (and man
           (aset ducpel-men i man))))
  (and active
       (setq ducpel-active-man-index active))
  (and teleports
       (setq ducpel-teleports teleports)))

(defun ducpel-undo ()
  "Undo previous move or action."
  (interactive)
  ;; Undo possible switching of the men made since the last move
  (ducpel-undo-changes ducpel-undo-current-cells
                       ducpel-undo-current-men
                       ducpel-undo-current-active-index
                       ducpel-undo-current-teleports)
  (ducpel-undo-reset-current)
  ;; Undo the last move
  (let ((move-changes (pop ducpel-undo-list)))
    (when move-changes
      (apply 'ducpel-undo-changes move-changes)
      (ducpel-remove-move)
      (pop ducpel-moves-history)
      (ducpel-check-done)
      (ducpel-print-done))))


;;; Replaying

(defun ducpel-replay (&optional moves)
  "Replay MOVES.
If MOVES is nil, use `ducpel-moves-history'."
  (interactive)
  (setq moves (reverse (or moves ducpel-moves-history)))
  (ducpel-restart-level)
  (dolist (move moves)
    (sit-for ducpel-replay-pause)
    (ducpel-set-active-man (car move))
    (ducpel-do (cadr move))))

(defalias 'ducpel-replay-current 'ducpel-replay
  "Replay current moves.")

(defun ducpel-replay-solution ()
  "Replay solution of the current level."
  (interactive)
  (if ducpel-solution
      (and (y-or-n-p "Do you REALLY want to see a solution of the level?")
           (ducpel-replay ducpel-solution))
    (message "No solution for the current map.")))

(defun ducpel-replay-from-file (file)
  "Replay saved moves from FILE.
Interactively, prompt for FILE."
  (interactive
   (list (read-file-name "Load replay from file: "
                         ducpel-user-saves-directory)))
  (load file)
  (ducpel-replay))

(defun ducpel-save-replay (file)
  "Save current moves to FILE.
Interactively, prompt for FILE."
  (interactive
   (list (read-file-name "Save replay to file: "
                         ducpel-user-saves-directory)))
  (or ducpel-moves-history
      (user-error "Do a single move at least"))
  (with-temp-buffer
    (insert ";; Saved moves for a ducpel level.\n"
            (format ";; Level file: %s\n\n" ducpel-level-file)
            "(setq ducpel-moves-history '")
    (princ ducpel-moves-history (current-buffer))
    (insert ")\n")
    (set (make-local-variable 'version-control) 'never)
    (write-file file t)))


;;; Display options

(defvar ducpel-glyphs-function nil
  "Function returning alist of glyph specifications used in gamegrid.
Associations of the alist should have the form:

  (PLIST . GLYPHS)

PLIST is a unique cell property list, see `ducpel-cell-plists'.
GLYPHS is a gamegrid specification for the PLIST.

Gamegrid specifications are lists of the form:

  (GLYPH-SPEC FACE-SPEC COLOR-SPEC)

They are used for `gamegrid-display-options' (see
`gamegrid-initialize-display' for details).")

;; Avoid compilation warning about `ducpel-glyphs-default'
(declare-function ducpel-glyphs-default "ducpel-glyphs" nil)

(defun ducpel-get-glyphs ()
  "Return alist with glyph specifications."
  (if ducpel-glyphs-function
      (funcall ducpel-glyphs-function)
    (require 'ducpel-glyphs)
    (ducpel-glyphs-default)))

(defun ducpel-get-display-options ()
  "Return array suitable for `gamegrid-display-options'."
  (let ((options (make-vector 256 nil))
        (glyph-alist (ducpel-get-glyphs)))
    (dolist (assoc glyph-alist)
      (aset options
            (apply 'ducpel-get-cell-char-by-plist (car assoc))
            (cdr assoc)))
    options))


;;; Printing info

(defvar ducpel-print-level-line 1)
(defvar ducpel-print-moves-line 2)
(defvar ducpel-print-done-line 3)

(defun ducpel-print-string (string dy)
  "Print STRING in the current gamegrid.
DY is a number of line after `ducpel-height'."
  (goto-char (point-min))
  (let ((lines (forward-line (+ ducpel-height dy)))
        (inhibit-read-only t))
    ;; Go to the line even if it does not exist
    (insert (make-string lines ?\n))
    (delete-region (point) (line-end-position))
    (insert string)
    (and (eobp) (insert ?\n))))

(defun ducpel-print-level ()
  "Print current level."
  (ducpel-print-string
   (format "Level: %s" (or ducpel-level ducpel-level-file))
   ducpel-print-level-line))

(defun ducpel-print-moves ()
  "Print current count of moves."
  (ducpel-print-string
   (format "Moves: %d" ducpel-moves)
   ducpel-print-moves-line))

(defun ducpel-print-done ()
  "Print current count of men."
  (ducpel-print-string
   (format "Done:  %d/%d" ducpel-done (length ducpel-men))
   ducpel-print-done-line))

(defun ducpel-print-info ()
  "Print all current info in the gamegrid."
  (ducpel-print-level)
  (ducpel-print-moves)
  (ducpel-print-done))


;;; Parsing levels

(defvar ducpel-map-char-alist nil
  "Alist of characters used in level maps and cell plists.")

(defvar ducpel-objects-char-alist nil
  "Alist of characters used in level maps for objects and cell plists.")

(defun ducpel-init-map-char-alist ()
  "Fill `ducpel-map-char-alist' and `ducpel-objects-char-alist'."
  (setq ducpel-map-char-alist nil
        ducpel-objects-char-alist nil)
  (push (list ducpel-empty-map-char :type ducpel-empty)
        ducpel-map-char-alist)
  (push (list ducpel-wall-map-char :type ducpel-wall)
        ducpel-map-char-alist)
  (push (list ducpel-impassable-map-char :type ducpel-impassable)
        ducpel-map-char-alist)
  (push (list ducpel-man-map-char :type ducpel-man)
        ducpel-objects-char-alist)
  (push (list ducpel-active-man-map-char :type ducpel-active-man)
        ducpel-objects-char-alist)
  (dolist (floor ducpel-floor-types)
    (push (list (aref ducpel-floor-map-chars floor)
                :type ducpel-floor :floor floor)
          ducpel-map-char-alist))
  (dolist (box ducpel-floor-types)
    (push (list (aref ducpel-box-map-chars box)
                :type ducpel-box :box box)
          ducpel-objects-char-alist)))

(ducpel-init-map-char-alist)

(defun ducpel-get-cell-plist-by-map-chars (map-char obj-char)
  "Return cell type plist by MAP-CHAR and OBJ-CHAR characters."
  (let* ((map-plist (cdr (assoc map-char ducpel-map-char-alist)))
         (map-type (plist-get map-plist :type)))
    (cond
     ((eq map-type nil)
      (error "Wrong map character: %c" map-char))
     ((eql map-type ducpel-floor)
      (let* ((obj-plist (cdr (assoc obj-char ducpel-objects-char-alist)))
             (obj-type (plist-get obj-plist :type)))
        (cond
         ((eql obj-type ducpel-box)
          (list :type obj-type
                :floor (plist-get map-plist :floor)
                :box (plist-get obj-plist :box)))
         ((or (eql obj-type ducpel-man)
              (eql obj-type ducpel-active-man))
          (list :type obj-type
                :floor (plist-get map-plist :floor)))
         (t map-plist))))
     (t map-plist))))

(defun ducpel-get-cell-char-by-map-chars (map-char obj-char)
  "Return cell type character by MAP-CHAR and OBJ-CHAR characters."
  (apply 'ducpel-get-cell-char-by-plist
         (ducpel-get-cell-plist-by-map-chars map-char obj-char)))

(defun ducpel-parse-solution ()
  "Parse solution of the level in the current buffer.
Return solution (list of moves) or nil if solution is not found."
  (goto-char (point-min))
  (when (re-search-forward ducpel-solution-re nil t)
    (re-search-forward "(")
    (backward-char)
    (let ((beg (point))
          (end (progn (forward-sexp) (point))))
      (read (buffer-substring-no-properties beg end)))))

(defun ducpel-parse-map (re)
  "Parse level map in the current buffer.
Search for regexp RE and parse the level map after it.
Return list of lines."
  (goto-char (point-min))
  (re-search-forward re)
  (forward-line)
  (while (looking-at ducpel-ignored-line-re)
    (forward-line))
  (let ((beg (point))
        (end (if (re-search-forward ducpel-ignored-line-re nil t)
                 (progn (beginning-of-line) (point))
               (point-max))))
    (split-string (buffer-substring-no-properties beg end) "\n" t)))

(defun ducpel-init-level-data (file)
  "Read ducpel level map from FILE.
Set the following variables: `ducpel-level-data',
`ducpel-width', `ducpel-height', `ducpel-solution'."
  (with-temp-buffer
    (insert-file-contents-literally file)
    (setq ducpel-solution (ducpel-parse-solution))
    (let ((map (ducpel-parse-map ducpel-map-re))
          (objects (ducpel-parse-map ducpel-objects-re))
          (height 0)
          (width 0))
      ;; Define height and width of the data array
      (dolist (line map)
        (cl-incf height)
        (let ((w (length line)))
          (when (> w width)
            (setq width w))))
      (setq ducpel-level-data (make-vector height nil)
            ducpel-width width
            ducpel-height height)
      ;; Fill the data array
      (cl-loop for map-line in map
               for objects-line in objects
               for y from 0
               do (let ((line (make-vector width nil)))
                    (cl-loop for map-char across map-line
                             for obj-char across objects-line
                             for x from 0
                             do (aset line x
                                      (ducpel-get-cell-char-by-map-chars
                                       map-char obj-char)))
                    (aset ducpel-level-data y line))))))

(defun ducpel-init-buffer ()
  "Fill current buffer with the level map.
Set `ducpel-men', `ducpel-active-man-index' and
`ducpel-teleports' variables."
  (gamegrid-init-buffer ducpel-width ducpel-height ?\s)
  (setq ducpel-teleports nil)
  (let (men)
    (dotimes (y ducpel-height)
      (dotimes (x ducpel-width)
        (let ((char (aref (aref ducpel-level-data y) x)))
          (when char
            (let* ((plist (ducpel-get-cell-plist-by-cell-char char))
                   (type (plist-get plist :type)))
              (cond
               ((eql type ducpel-man)
                (push (list x y) men))
               ((eql type ducpel-active-man)
                (push (list x y) men)
                (setq ducpel-active-man-index
                      (- (length men) 1)))
               ((eql (plist-get plist :floor) ducpel-teleport)
                (push (list x y) ducpel-teleports))))
            (gamegrid-set-cell x y char)))))
    (setq ducpel-men
          (apply 'vector (nreverse men)))))


;;; UI for levels

(defun ducpel-restart-level (&optional reload)
  "Restart current level.
If RELOAD is non-nil (interactively with prefix), reread current
level map from the level file."
  (interactive "P")
  (when reload
    (ducpel-init-level-data ducpel-level-file))
  (ducpel-init-buffer)
  (ducpel-undo-init)
  (setq ducpel-moves 0
        ducpel-done 0
        ducpel-moves-history nil)
  (ducpel-print-info))

(defun ducpel-get-file-by-level (level)
  "Return file name by LEVEL number."
  (expand-file-name (format "%04d" level) ducpel-levels-directory))

(defun ducpel-goto-level (level)
  "Go to a specified LEVEL."
  (interactive "NLevel: ")
  (let ((file (ducpel-get-file-by-level level)))
    (or (file-regular-p file)
        (error "Level %d does not exist yet" level))
    (setq ducpel-level level
          ducpel-level-file file)
    (ducpel-restart-level t)))

(defun ducpel-next-level ()
  "Go to the next level."
  (interactive)
  (ducpel-goto-level
   (if ducpel-level (+ ducpel-level 1) ducpel-default-level)))

(defun ducpel-previous-level ()
  "Go to the previous level."
  (interactive)
  (ducpel-goto-level
   (if ducpel-level (- ducpel-level 1) ducpel-default-level)))

(defun ducpel-load-level-from-file (file)
  "Load level map from FILE."
  (interactive
   (list (read-file-name "Load ducpel map: "
                         ducpel-user-levels-directory)))
  (setq ducpel-level nil
        ducpel-level-file file)
  (ducpel-restart-level t))


;;; Misc

(defun ducpel-get-index-by-shift (len index shift)
  "Return index of element of array or list by shifting INDEX by SHIFT.
LEN is a length of array or list."
  (mod (+ index shift) len))

(defun ducpel-get-index-by-element (array-or-list elt &optional cmp noerror)
  "Return index of element ELT from ARRAY-OR-LIST.

Compare ELT with elements of ARRAY-OR-LIST using CMP
function (`eq' by default).

If NOERROR is non-nil, return nil if ELT is not found; otherwise
signal an error."
  (or cmp
      (setq cmp 'eq))
  (let (type)
    (or (cond
         ((listp array-or-list)
          (setq type "list")
          (cl-loop for obj in array-or-list
                   for i from 0
                   if (funcall cmp elt obj) return i))
         ((arrayp array-or-list)
          (setq type "array")
          (cl-loop for i below (length array-or-list)
                   if (funcall cmp elt (aref array-or-list i)) return i))
         (t (error "Should be array or list")))
        (and (null noerror)
             (error "Element %s is not found in %s" elt type)))))


;;; Major mode

(defvar ducpel-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "R"            'ducpel-restart-level)
    (define-key map "F"            'ducpel-load-level-from-file)
    (define-key map "L"            'ducpel-goto-level)
    (define-key map "N"            'ducpel-next-level)
    (define-key map "P"            'ducpel-previous-level)
    (define-key map "u"            'ducpel-undo)
    (define-key map "\C-_"         'ducpel-undo)
    (define-key map [(control ?/)] 'ducpel-undo)
    (define-key map "\t"           'ducpel-next-man)
    (define-key map "\e\t"         'ducpel-previous-man)
    (define-key map [backtab]      'ducpel-previous-man)
    (define-key map " "            'ducpel-action)
    (define-key map "b"            'ducpel-move-left)
    (define-key map "f"            'ducpel-move-right)
    (define-key map "p"            'ducpel-move-up)
    (define-key map "n"            'ducpel-move-down)
    (define-key map [left]         'ducpel-move-left)
    (define-key map [right]        'ducpel-move-right)
    (define-key map [up]           'ducpel-move-up)
    (define-key map [down]         'ducpel-move-down)
    (define-key map "rc"           'ducpel-replay-current)
    (define-key map "rf"           'ducpel-replay-from-file)
    (define-key map "rS"           'ducpel-replay-solution)
    (define-key map "rs"           'ducpel-save-replay)
    map)
  "Keymap for `ducpel-mode'.")

(define-derived-mode ducpel-mode special-mode "Ducpel"
  "Major mode for playing ducpel.

\\{ducpel-mode-map}"
  (set (make-local-variable 'gamegrid-use-glyphs) ducpel-use-glyphs)
  ;; hl-line disturbs if `ducpel-use-glyphs' is nil
  (set (make-local-variable 'global-hl-line-mode) nil)
  (gamegrid-init (ducpel-get-display-options)))

;;;###autoload
(defun ducpel ()
  "Play ducpel game."
  (interactive)
  (let ((buf (get-buffer ducpel-buffer-name)))
    (pop-to-buffer-same-window ducpel-buffer-name)
    (unless buf
      (ducpel-mode)
      (ducpel-goto-level ducpel-default-level))))

(provide 'ducpel)

;;; ducpel.el ends here
