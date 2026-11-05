# vimdaw controls

vimdaw is a keyboard-first piano-roll DAW: the whole editor is driven with
Vim-style commands. Everything below works with a hardware keyboard; the
on-screen extra-keys row mirrors the same commands for touch devices.

## Modes

| Mode | Enter | Notes |
| --- | --- | --- |
| Normal | `Esc` | navigation and editing commands |
| Draw | `i` | `h j k l` paints a line of notes |
| Erase | `d` on an empty cell | `h j k l` erases along a line |
| Replace | `r` | move up/down to drag the pitch of the note under the cursor |
| Command | `:` | type a `:`-command, then `Enter` |

`Esc` always returns to Normal and clears the current selection.

## Moving the pointer

| Keys | Action |
| --- | --- |
| `h` / `l` | step left / right |
| `j` / `k` | step down / up (a semitone, or one scale step in scale-keys mode) |
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
(`C4`, `C#4`, …); the tonic labels are emphasised.

## Key & scale

Tap the key chip in the toolbar (or run `:scale <root> [name]`) to change the
project key. The picker applies root and scale immediately. Turn on **SCALE
KEYS ONLY** there (or run `:scale keys on`) to replace the chromatic keyboard
with one row per scale step: out-of-key rows disappear, `j`/`k` move by scale
degree, and new notes land on the scale. `:scale keys off` restores every
semitone. `:scale on|off` controls the in-key row highlight instead.

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
| `i` | toggle Draw |
| `x` | cut selection (or the note under the cursor) |
| `r` | replace/drag pitch |
| `v` / `V` | paste after / before |
| `Ctrl+a` | select all notes on the active track |
| `Ctrl+d` | delete the selected notes |
| `Shift` + `0`…`9` | start a bar-length entry (e.g. `Shift+1`, `.5`, `Enter` = 1.5 bars) |
| `d` | delete selection/note · on an empty cell: toggle Erase |
| `y` | yank selection (or the note under the cursor) |
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

### Progressions with a strum pattern

Press `s` (or type `:strum`) to open a prefilled command, then enter a chord
progression and a strum pattern:

```
:strum i v iv d-uu-u
```

The progression accepts roman numerals (`i`, `V`, `IV7`, …) relative to the
project key set with `:scale`, lead-sheet chords (`Am7`, `F#dim`), named
progressions (`pop`, `canon`, `blues`, …), and `,` or `|` separators.
Lower-case numerals are minor, upper-case are major. Each chord lasts one bar.

The strum pattern has one character per 16th note:

| Char | Hit |
| --- | --- |
| `d` / `D` | downstroke — full chord (uppercase = accent) |
| `u` / `U` | upstroke — drops the lowest voice |
| `x` / `X` | muted hit — short and quiet |
| `-` `.` `_` | rest |

The pattern repeats to fill each bar and hits ring until the next attack. A
single `d` produces one block chord per bar. Use `|` before a spaced pattern:
`:strum i v iv | d - u u - u`.

## Transport

| Keys | Action |
| --- | --- |
| `Enter` / `Space` | play / pause |
| `.` or `Esc` on the transport | stop |

Play pushes every track's notes into the audio engine as one loop at the
project tempo and starts it at the playhead, so playback is actually audible —
drum hits included (they go to GM channel 10). The status line reports
what went in: `PLAYING · 12 note(s)`, or `PLAYING · no notes yet` when nothing
has been written. Pause and stop release anything still ringing.

## Instrument

Each track plays one General MIDI program. The list starts with drum kits
(`808 / 909`, Electronic, Dance, Standard …), then the 128 melodic programs:

| Where | Action |
| --- | --- |
| toolbar chip, next to the track name | tap it to open the instrument list, filter by name or number, tap a row to load it |
| `:inst <name-or-number>` | e.g. `:inst piano`, `:inst 118`, `:inst 808`; `:inst` alone reports the current sound |
| Sample view (`Ctrl+5`) | `j`/`k` pick a program, `i` loads it onto the active track; the `Drums` category is last |

Selecting a drum kit turns the active track into a drum track (GM channel 10)
and the roll immediately switches to horizontal `KICK`, `SNARE`, `CLAP` …
names. Selecting a melodic program on a drum track switches it back to a
normal melodic track and loads that sound. Loading an instrument previews it
on the cursor pitch, so the choice is audible immediately. The project starts
empty on `Track 1` (Acoustic Grand Piano) — there is no demo song to delete
first.

## Views

`Ctrl` + `1`, `3`…`7` switches views: `1` Roll, `3` Arrangement, `4` Mixer,
`5` Instrument browser, `6` Automation, `7` Help. The tab bar at the top does
the same; the palette button cycles the accent theme. There is no separate
drum tab — drums are edited in the roll.

## Drums

Drums use the same roll grid. Turn the active track into a GM drum track with
`:drum on` (or place the first hit); rows then read `KICK`, `SNARE`, `CLAP` …
horizontally instead of piano keys, and playback goes to GM channel 10.
`:drum off` returns the track to melodic names. To change kits without
leaving the roll, open the instrument chip and pick `808 / 909`, Electronic,
Dance, and so on.

| Touch | Action |
| --- | --- |
| tap a cell | move the cursor (a single tap never draws) |
| double-tap a cell | place a hit (double-tapping again removes it) |
| drag across the grid | paint a run of hits (adds only) |
| long-press a hit | erase it |
| drag the gutter / ruler | scroll the sounds / time |

Keyboard: `j`/`k` walk between drum rows, `i` toggles a hit under the cursor,
`d` removes it, `h`/`l` move in time.

## Projects

Projects are stored inside the app's private internal storage under
`sridaw/projects` (`getApplicationDocumentsDirectory()`), so they survive
app restarts and remain editable. Tap the project name in the toolbar to open
the picker: type a name and press **SAVE**, or tap a saved project to open it
in the roll. The command-line equivalents are `:w [name]`, `:e [name]`,
`:ls`, and `:storage`.

## Command line

Press `:` and type a command, then `Enter`:

| Command | Action |
| --- | --- |
| `:w [name]` | save the project in the app's internal storage (defaults to its current name) |
| `:e [name]` / `:open [name]` | open a saved project; with no name, show the project picker |
| `:ls` / `:projects` | list saved projects |
| `:storage` | show the projects folder path |
| `:q` | quit (close the window) |
| `:pal <name>` / `:theme <name>` | set the accent theme (`mono`, `slate`, `sand`, `moss`, `rose`) |
| `:bpm <n>` | set tempo (20–300) |
| `:len <n>` | default note length when drawing (1–64) |
| `:bar <n>` / `:bars <n>` | resize the song to `n` bars; fractions allowed (`:bar 2`, `:bar 1.5`) |
| `:inst <name\|#>` | load a GM instrument or drum kit onto the active track (see [Instrument](#instrument)) |
| `:ghost on|off` | show/hide ghost notes |
| `:crt on|off` | toggle the CRT overlay |
| `:scale <root> <name>` | set the project key, e.g. `:scale D Minor` (notes then label as scale degrees `1`…`7`); `:scale minor` keeps the root |
| `:scale keys on\|off` | show only scale rows (degrees) instead of the chromatic keyboard |
| `:scale on\|off` | show/hide the in-key row highlight |
| `:chord <type>` | harmonise the selection / cursor note |
| `:strum <progression> <pattern>` | create strummed chords, e.g. `:strum i v iv d-uu-u` |
| `:view <name>` | switch view (`roll`, `arrangement`, `mixer`, `sample`, `automation`, `help`) |
| `:help` | show this reference in-app |
| `:ctrl+1.1-E4,1.2-C4` | select the rectangle between two `bar.beat-note` corners and grab it (no spaces, comma between corners) |

## Touch / mobile

An always-on soft keyboard feeds characters through the same keymap, so
`h j k l` behave identically. The extra-keys row provides `Esc`, `Tab`,
`Ctrl`, `Alt`, `Shift`, `Space`, the arrows, `Home`, `End`, `:` and the theme
button. Sticky modifiers highlight when active.

Everything you can reach with the keyboard is also tappable: the tabs switch
views, the toolbar starts/stops playback, the instrument chip (next to the
track name) opens the tap-to-load sound list, mixer faders and toggles respond
to touch, and the piano roll lays hits down under a finger on a drum track
(tap to move the cursor, double-tap to toggle a hit, drag to paint a run).

In the piano roll, tap to move the cursor, double-tap an empty cell to add a
note (or a note to select it), drag a selected note to move it (drag the
selection to move every selected note), triple-tap a note to arm chord mode,
and long-press a note to delete it. Drag the keyboard gutter or the ruler to
scroll pitches or time (the mouse wheel and trackpad also scroll). In the
arrangement, tap a track header or clip to select it and double-tap a clip to
open its piano roll. Panels collapse or scroll on narrow screens so the editor
stays usable in portrait on a phone.
