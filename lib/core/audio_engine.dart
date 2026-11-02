import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ffi/audio_bindings.dart'
    if (dart.library.js_interop) '../ffi/audio_bindings_web.dart';

/// Thin, fault-tolerant wrapper around the existing JUCE/FluidSynth bridge.
///
/// M1 only needs an audio device plus a short preview note. The bridge may be
/// missing (e.g. a Linux desktop build that has not compiled `cpp/` yet), so
/// every call is guarded and [available] tells the UI whether to bother.
class DawAudioEngine {
  AudioEngineBridge? _bridge;
  bool _available = false;

  bool get available => _available;
  String? get soundFontPath => _bridge?.getSoundFontPath();

  Future<bool> init() async {
    try {
      final bridge = AudioEngineBridge();
      _bridge = bridge;
      _available = bridge.initialize();
    } catch (_) {
      _bridge = null;
      _available = false;
    }
    if (_available) await _loadDefaultSoundFont();
    return _available;
  }

  /// The bundled GeneralUser SoundFont is only reachable through the Android
  /// asset bundle; MainActivity extracts it to the cache dir and this loads
  /// it into FluidSynth. Without it the engine runs but is silent.
  Future<void> _loadDefaultSoundFont() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final path = await const MethodChannel('com.ram.sridaw/assets')
          .invokeMethod<String>('extractSoundFont');
      if (path != null) loadSoundFont(path);
    } catch (_) {}
  }

  void loadSoundFont(String path) {
    try {
      _bridge?.loadSoundFont(path);
    } catch (_) {}
  }

  bool get soundFontLoaded {
    try {
      return _bridge?.isSoundFontLoaded() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// One-line health report for the status bar: an engine without a loaded
  /// SoundFont renders digital silence, which is worth saying out loud.
  String describe() {
    if (!_available) {
      return 'audio engine unavailable (build cpp/ to enable sound)';
    }
    if (!soundFontLoaded) {
      return 'audio engine ready, but no SoundFont is loaded - silent';
    }
    return 'audio engine ready';
  }

  void shutdown() {
    for (final t in _previewTimers.values) {
      t.cancel();
    }
    _previewTimers.clear();
    try {
      _bridge?.shutdown();
    } catch (_) {}
    _bridge = null;
    _available = false;
  }

  void setVolume(double v) {
    try {
      _bridge?.setVolume(v);
    } catch (_) {}
  }

  void playDemo(bool play) {
    try {
      _bridge?.playDemo(play);
    } catch (_) {}
  }

  void setLoopDuration(double seconds) {
    try {
      _bridge?.setLoopDuration(seconds);
    } catch (_) {}
  }

  /// Fire-and-forget preview note used whenever the pointer moves onto a pitch
  /// or a note is drawn. Target is < 20 ms pointer-to-sound on mobile.
  ///
  /// Every preview is released after a short blip (a pointer-driven DAW never
  /// holds a note down), otherwise FluidSynth keeps the voice ringing and a
  /// handful of taps ends in a wall of stuck notes.
  final Map<String, Timer> _previewTimers = {};

  void previewNote(int pitch, {int velocity = 100, int channel = 0}) {
    try {
      _bridge?.playPreviewNote(channel, pitch, velocity.clamp(1, 127) / 127.0);
    } catch (_) {}
    final key = '$channel:$pitch';
    _previewTimers[key]?.cancel();
    _previewTimers[key] = Timer(const Duration(milliseconds: 170), () {
      _previewTimers.remove(key);
      try {
        _bridge?.playPreviewNote(channel, pitch, 0);
      } catch (e) {
        debugPrint('extractSoundFont failed: $e');
      }
    });
  }

  /// Rewrite the scheduled sequence that the engine plays while the transport
  /// runs. [start]/[duration] are seconds from the loop point.
  void clearMidiSequence() {
    try {
      _bridge?.clearMidiSequence();
    } catch (_) {}
  }

  void addMidiNote(int pitch,
      {required double start,
      required double duration,
      double velocity = 1.0,
      int channel = 0}) {
    try {
      _bridge?.addMidiNote(channel, pitch, start, duration, velocity);
    } catch (_) {}
  }

  /// Release everything that is ringing (pause/stop, view switches).
  void allSoundsOff() {
    for (final t in _previewTimers.values) {
      t.cancel();
    }
    _previewTimers.clear();
    try {
      _bridge?.allSoundsOff();
    } catch (_) {}
  }

  /// Move the engine playhead so a resume continues where the visual
  /// playhead stopped instead of restarting the loop.
  void setPlayheadTime(double seconds) {
    try {
      _bridge?.setPlayheadTime(seconds);
    } catch (_) {}
  }

  void setTrackVolume(int index, double volume) {
    try {
      _bridge?.setTrackVolume(index, volume);
    } catch (_) {}
  }

  void setTrackInstrument(int index, int program) {
    try {
      _bridge?.setTrackInstrument(index, program);
    } catch (_) {}
  }

  double trackPeak(int index) {
    try {
      return _bridge?.getTrackPeakLevel(index) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Load a VST3/AU plugin onto a track. Returns false when no engine is
  /// available (e.g. a desktop build where `cpp/` has not been compiled).
  bool loadTrackPlugin(int trackIndex, String path) {
    try {
      return _bridge?.loadTrackPlugin(trackIndex, path) ?? false;
    } catch (_) {
      return false;
    }
  }

  double get playheadTime {
    try {
      return _bridge?.getPlayheadTime() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }
}
