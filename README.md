# vimdaw

A keyboard-first piano-roll DAW with Vim-style editing, built with Flutter.

The whole editor is driven from the keyboard: `h j k l` move the cursor, `i`
draws, `x` erases, `v` selects, `:` opens a command line, and `Ctrl` grabs a
note that you can nudge around with the movement keys.

- Native-resolution piano-roll renderer: real piano keys labelled vertically,
  a bar/beat ruler, a row + column crosshair cursor and modern note blocks.
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
