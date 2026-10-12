# vimdaw controls

vimdaw is a keyboard-first piano-roll DAW: the whole editor is driven with
Vim-style commands. Everything below works with a hardware keyboard; the
on-screen extra-keys row mirrors the same commands for touch devices.

## Modes

| Mode | Enter | Notes |
| --- | --- | --- |
| Normal | `Esc` | navigation and editing commands |
| Draw | `i` or `Space` | `h j k l` paints a line of notes |
| Erase | `x` | `h j k l` erases along a line |
| Replace | `r` | move up/down to drag the pitch of the note under the cursor |
| Visual | `v` | select a rectangular region |
| Visual line | `V` | select whole rows |
| Command | `:` | type a `:`-command, then `Enter` |

`Esc` always returns to Normal and clears the current selection.

## Moving the pointer

| Keys | Action |
| --- | --- |
| `h` / `l` | step left / right |
| `j` / `k` | step down / up (a semitone) |
| `Shift` + `h` / `l` | move by one beat |
| `Shift` + `j` / `k` | move by one octave |
| `w` / `b` | jump to next / previous note |
| `0` / `$` | bar start / bar end |
| `gg` / `G` | lowest / highest note |

A count prefix repeats the motion, e.g. `8l` moves eight steps right. The
partial command is shown in the status bar.

## The roll cursor

The cursor is drawn as a full **row and column crosshair**: two horizontal
lines bracket the current pitch row and two vertical lines bracket the current
column, with the intersection cell blinking. This makes the active beat and
pitch readable at a glance.

Every key on the piano gutter is labelled vertically with its note name
(`C4`, `C#4`, …); the `C` labels are emphasised.

## CTRL grab / box select

`Ctrl` is a cycling toggle for picking up notes and moving them:

1. **On a note** (or with a selection active): tap `Ctrl` to grab it. Move with
   `h j k l` (`Shift` = beat / octave); the cursor rides along. Tap `Ctrl` again
   to release.
2. **On an empty cell**: tap `Ctrl` to start a rectangle **box select** anchored
   under the cursor — the status bar reads `box select`. Move with `h j k l` to
   grow the box; every note the box covers is highlighted live.
3. Tap `Ctrl` again to **grab** everything in the box, then move it with
   `h j k l`. Tap `Ctrl` once more to release.

You can also box-select by command with no cursor movement:
`:ctrl+1.1-E4,1.2-C4` (two `bar.beat-note` diagonals, comma-separated, no
spaces) selects and grabs that rectangle directly.

A grab is one undoable change. `Esc`, switching modes, and undo/redo all
release the grab.

## Editing

| Keys | Action |
| --- | --- |
| `i` / `Space` | toggle Draw |
| `x` | toggle Erase |
| `r` | replace/drag pitch |
| `v` / `V` | visual / visual-line select |
| `d` | delete selection (or the note under the cursor) |
| `y` | yank selection (or the note under the cursor) |
| `p` / `P` | paste after / before |
| `u` / `Ctrl+r` | undo / redo |
| `.` | repeat the last change |
| `q` | quantise to the beat |
| `+` / `-` | transpose selection up / down a semitone |
| `<` / `>` | transpose selection up / down an octave |
| `[` / `]` | shorten / lengthen note(s) (selection, grab, or cursor) |
| `i` on a selection | cycle note value: `1/32` `1/16` `1/8` `1/4` `1/2` `1` |

## Chords

With the cursor on a note (or a selection / CTRL box active) press `c` to arm
chord mode, then tap a quality key to stack the chord on every root:

| Key | Chord |
| --- | --- |
| `M` | Major |
| `m` | Minor |
| `a` | augmented |
| `d` | diminished |
| `s` | dominant 7 |
| `t` | maj7 |

`Esc` leaves chord mode; `Ctrl` `c` is left free for copy.

The added tones are selected, so `[` / `]` and `h j k l` (with CTRL) then act
on the whole chord. `:chord <type>` does the same from the command line for
any shape (including `maj7`, `m7`, `sus2`, `sus4`).

## Transport

| Keys | Action |
| --- | --- |
| `Enter` | play / pause |
| `.` or `Esc` on the transport | stop |

## Views

`Ctrl` + `1`…`7` switches views (Roll, Pattern, Arrangement, Mixer, Sample,
Automation, Help). The tab bar at the top does the same; the palette button
cycles the accent theme.

## Command line

Press `:` and type a command, then `Enter`:

| Command | Action |
| --- | --- |
| `:w` | save (reports “not implemented until M5”) |
| `:q` | quit (close the window) |
| `:pal <name>` / `:theme <name>` | set the accent theme (`mono`, `slate`, `sand`, `moss`, `rose`) |
| `:bpm <n>` | set tempo (20–300) |
| `:len <n>` | default note length when drawing (1–64) |
| `:ghost on|off` | show/hide ghost notes |
| `:crt on|off` | toggle the CRT overlay |
| `:scale <root> <name>` | set the project key, e.g. `:scale D Minor` (notes then label as scale degrees `1`…`7`) |
| `:scale on\|off` | show/hide out-of-key ghosting |
| `:chord <type>` | harmonise the selection / cursor note |
| `:view <name>` | switch view |
| `:help` | show this reference in-app |
| `:ctrl+1.1-E4,1.2-C4` | select the rectangle between two `bar.beat-note` corners and grab it (no spaces, comma between corners) |

## Touch / mobile

An always-on soft keyboard feeds characters through the same keymap, so
`h j k l` behave identically. The extra-keys row provides `Esc`, `Tab`,
`Ctrl`, `Alt`, `Shift`, the arrows, `Home`, `End`, `:` and the theme button.
Sticky modifiers highlight when active.
