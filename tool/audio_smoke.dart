// Standalone audio smoke test: loads the native JUCE/FluidSynth bridge the
// way the app does, schedules three notes, and checks that the engine
// actually runs. Run from the repo root:
//
//   dart run tool/audio_smoke.dart
//
// It prints `audio callback is running` only when the device callback is
// advancing the playhead, i.e. when playback would be audible.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _BoolNative = Bool Function();
typedef _BoolDart = bool Function();
typedef _LoadSfNative = Bool Function(Pointer<Utf8> path);
typedef _LoadSfDart = bool Function(Pointer<Utf8> path);
typedef _AddNoteNative = Void Function(
    Int32 channel, Int32 note, Double start, Double duration, Float velocity);
typedef _AddNoteDart = void Function(
    int channel, int note, double start, double duration, double velocity);
typedef _DoubleNative = Double Function();
typedef _DoubleDart = double Function();
typedef _DoubleVoidNative = Void Function(Double value);
typedef _DoubleVoidDart = void Function(double value);
typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();
typedef _PlayNative = Void Function(Bool playing);
typedef _PlayDart = void Function(bool playing);
typedef _PreviewNative = Void Function(Int32 channel, Int32 note, Float velocity);
typedef _PreviewDart = void Function(int channel, int note, double velocity);
typedef _SetTrackNative = Void Function(Int32 channel, Int32 program);
typedef _SetTrackDart = void Function(int channel, int program);

void main() {
  final libPath = 'cpp/build/libsridaw_juce.so';
  if (!File(libPath).existsSync()) {
    stderr.writeln('no $libPath — build it first: '
        'cmake -S cpp -B cpp/build -G Ninja && ninja -C cpp/build');
    exitCode = 2;
    return;
  }
  final lib = DynamicLibrary.open(libPath);

  final init = lib.lookupFunction<_BoolNative, _BoolDart>('initJuceEngine');
  final loadSf =
      lib.lookupFunction<_LoadSfNative, _LoadSfDart>('loadSoundFont');
  final isSfLoaded =
      lib.lookupFunction<_BoolNative, _BoolDart>('isSoundFontLoaded');
  final clear =
      lib.lookupFunction<_VoidNative, _VoidDart>('clearMidiSequence');
  final addNote =
      lib.lookupFunction<_AddNoteNative, _AddNoteDart>('addMidiNote');
  final setLoop =
      lib.lookupFunction<_DoubleVoidNative, _DoubleVoidDart>('setLoopDuration');
  final setPlayhead =
      lib.lookupFunction<_DoubleVoidNative, _DoubleVoidDart>('setPlayheadTime');
  final play = lib.lookupFunction<_PlayNative, _PlayDart>('playDemo');
  final getPlayhead =
      lib.lookupFunction<_DoubleNative, _DoubleDart>('getPlayheadTime');
  final preview =
      lib.lookupFunction<_PreviewNative, _PreviewDart>('playPreviewNote');
  final setTrack =
      lib.lookupFunction<_SetTrackNative, _SetTrackDart>('setTrackInstrument');
  final allOff = lib.lookupFunction<_VoidNative, _VoidDart>('allSoundsOff');
  final shutdown = lib.lookupFunction<_VoidNative, _VoidDart>('shutdownJuceEngine');

  final ok = init();
  stdout.writeln('initJuceEngine      -> $ok');
  if (!ok) {
    stdout.writeln('(no audio device on this machine — bridge still loaded)');
    shutdown();
    exitCode = 1;
    return;
  }

  const sf = 'android/app/src/main/assets/soundfonts/GeneralUser-GS.sf2';
  final sfPtr = sf.toNativeUtf8();
  final sfOk = loadSf(sfPtr);
  malloc.free(sfPtr);
  stdout.writeln('loadSoundFont       -> $sfOk');
  stdout.writeln('isSoundFontLoaded   -> ${isSfLoaded()}');

  setTrack(0, 80); // Lead on melodic channel 0
  clear();
  addNote(0, 60, 0.0, 0.5, 0.9); // C4 on channel 0
  addNote(9, 36, 0.0, 0.2, 0.9); // kick on the percussion channel
  addNote(9, 38, 0.25, 0.2, 0.9); // snare
  setLoop(1.0);
  setPlayhead(0.0);
  play(true);
  stdout.writeln('scheduled 3 notes (melodic ch0 + drum ch10), loop 1.0s');

  sleep(const Duration(milliseconds: 400));
  final t1 = getPlayhead();
  preview(0, 64, 0.8); // tap preview + release (the blip the UI schedules)
  sleep(const Duration(milliseconds: 120));
  preview(0, 64, 0.0);
  sleep(const Duration(milliseconds: 300));
  final t2 = getPlayhead();

  stdout.writeln('playhead 0.4s       -> ${t1.toStringAsFixed(3)}s');
  stdout.writeln('playhead 0.8s       -> ${t2.toStringAsFixed(3)}s '
      '${t2 > t1 ? '— audio callback is running' : '— callback NOT advancing'}');

  play(false);
  allOff();
  shutdown();
  if (t2 <= t1) exitCode = 1;
}
