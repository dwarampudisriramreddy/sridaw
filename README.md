# vimdaw

A keyboard-first piano-roll DAW with Vim-style editing, built with Flutter.

The whole editor is driven from the keyboard: `h j k l` move the cursor, `i`
draws, `d` erases (on an empty cell it arms ERASE), `v` pastes, `:` opens a
command line, and `Ctrl` grabs a note that you can nudge around with the
movement keys.

- Native-resolution piano-roll renderer: real piano keys labelled vertically,
  a bar/beat ruler, a row + column crosshair cursor and modern note blocks.
- Key & scale chip: pick a root and mode, or turn on scale-keys mode so the
  roll has one row per scale step and hides chromatic keys.
- Drums live in the same roll: `:drum on` turns the track into a GM kit and
  the gutter names read horizontally — tap a cell for a hit, drag to paint a
  run. The instrument chip lists drum kits (`808 / 909`, Electronic, Dance …)
  right above the melodic programs.
- Sound is wired end to end: the transport pushes the project into the
  JUCE/FluidSynth engine so play actually plays (drums on GM channel 10), and
  the toolbar's instrument chip opens a tap-to-load GM list starting with
  drum kits (`:inst piano` / `:inst 808` are the command-line twins).
- Fresh projects start empty — no demo song to delete first.
- Projects save to the app's internal `sridaw/projects` folder and reopen
  editable: `:w <name>` saves, `:e <name>` opens, or tap the project name in
  the toolbar to use the project picker.
- Modern chrome: glass panels, gradient accents, Google Fonts and animated
  transport.

## Getting started

```sh
flutter pub get
flutter run            # desktop (Linux/macOS/Windows) or mobile
flutter test           # unit + widget tests
flutter build linux    # desktop release build
```

### Desktop audio

Sound comes from the native JUCE/FluidSynth bridge in `cpp/`. Build it once
and the app picks `cpp/build/libsridaw_juce.so` up automatically:

```sh
cmake -S cpp -B cpp/build -G Ninja
ninja -C cpp/build
```

Without it everything still works, but the status bar reports
`audio engine unavailable (build cpp/ to enable sound)`. Android APKs build
the same sources through Gradle and load the bundled GeneralUser SoundFont.

## Controls

See [`docs/controls.md`](docs/controls.md) for the full key reference.
