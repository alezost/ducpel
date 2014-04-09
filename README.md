# Ducpel

Logic game with sokoban elements for GNU Emacs.

![Level 1 in progress](https://raw.github.com/alezost/ducpel/master/pic/screenshot.png)

## Installation

### Manual

Clone the repo and add the following lines to your `.emacs`.

```lisp
(add-to-list 'load-path "/path/to/ducpel-dir")
(autoload 'ducpel "ducpel" nil t)
```

### Automatic

The package can be installed from [MELPA](http://melpa.milkbox.net) or
using [quelpa](https://github.com/quelpa/quelpa) like this:

```lisp
(quelpa '(ducpel :fetcher github :repo "alezost/ducpel" :files ("*.el" "levels")))
```

## Usage

Use `M-x ducpel` to start the game and the following keys to play:

- <kbd>left</kbd>/<kbd>right</kbd>/<kbd>up</kbd>/<kbd>down</kbd> – move
  a man;
- <kbd>TAB</kbd>/<kbd>S-TAB</kbd> – switch to the next/previous man;
- <kbd>SPC</kbd> – activate a special cell (exit or teleport);
- <kbd>u</kbd> – undo a move;

Key bindings for levels:

- <kbd>R</kbd> – restart current level (with prefix also reread a level
  file);
- <kbd>N</kbd>/<kbd>P</kbd> – go to the next/previous level;
- <kbd>L</kbd> – go to the specified level;
- <kbd>F</kbd> – load a level from file.

Key bindings for replaying:

- <kbd>r</kbd><kbd>c</kbd> – replay current moves;
- <kbd>r</kbd><kbd>S</kbd> – replay solution (each inbuilt level has a
  solution);
- <kbd>r</kbd><kbd>s</kbd> – save current moves to a file;
- <kbd>r</kbd><kbd>f</kbd> – replay saved moves from a file;

## Rules

You will learn everything you need during playing the game.

TODO Write something here.

## Contributing

If you found a better solution than the default one, and especially if
you created a level, you may make a pull request or
[open an issue](https://github.com/alezost/ducpel/issues/new).

Making new levels is a priority.  `artist-mode` can be useful during
building a map.  A level file consists of 2 maps:

- The main map (titled with `; Map`) defines:

  + `@` – impassable cells (unbreakable walls);
  + `#` – breakable walls;
  + ` ` – empty cells;
  + floors:
    * `.` – simple floor,
    * `E` – exit,
    * `T` – teleport,
    * `L` – floor that can move left,
    * `R` – floor that can move right,
    * `U` – floor that can move up,
    * `D` – floor that can move down,
    * `H` – floor that can move horizontally (left and right),
    * `V` – floor that can move vertically (up and down),
    * `M` – floor that can move in any direction.

- The second map (titled with `Objects`) is used only to define the
  position of men and boxes:

  + `p` – inactive man;
  + `P` – active man;
  + boxes: `b`, `e`, `t`, `l`, `r`, `u`, `d`, `h`, `v`, `m` (the same
    meaning as for the floors above).

  Other characters in the object map are ignored.

Also a level should provide a solution (`ducpel-moves-history` variable
contains the moves and it is the solution after you passed a level).

## About

I thought it would be great to make a sokoban-like game where several
men can move several boxes and boxes can be transformed into floors, so
that you can build a path to the exit.

A big part of the game is the idea of moving cells (floors with arrows).
It was taken from a non-free game "Metamorphs" (it was released only for
Microsoft Windows around 2000).

The code of [sokoban package](https://github.com/leoliu/sokoban) was
used hardly.

### What does the name mean?

I just tried to make a unique name and stayed on this variant because it
ends with "el" and it consists (almost) of 2 latin roots:

- duco, ducere, duxi, ductus – to lead;
- pello, pellere, pepuli, pulsus – one of the meanings is "to push".

