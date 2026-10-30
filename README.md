# vimdaw

A keyboard-first piano-roll DAW with Vim-style editing, built with Flutter.

The whole editor is driven from the keyboard: `h j k l` move the cursor, `i`
draws, `d` erases (on an empty cell it arms ERASE), `v` pastes, `:` opens a
command line, and `Ctrl` grabs a note that you can nudge around with the
movement keys.

- Native-resolution piano-roll renderer: real piano keys labelled vertically,
  a bar/beat ruler, a row + column crosshair cursor and modern note blocks.
- Drum machine tab (`Ctrl+2`): the same grid with a column of sound pads you
  add yourself — tap a cell for a hit, drag to paint a run.
- Modern chrome: glass panels, gradient accents, Google Fonts and animated
  transport.

## Getting started

```sh
flutter pub get
flutter run            # desktop (Linux/macOS/Windows) or mobile
flutter test           # unit + widget tests
flutter build linux    # desktop release build
```

## Controls

See [`docs/controls.md`](docs/controls.md) for the full key reference.
