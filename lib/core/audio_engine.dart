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
    return _available;
  }

  void shutdown() {
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
  void previewNote(int pitch, {int velocity = 100, int channel = 0}) {
    try {
      _bridge?.playPreviewNote(channel, pitch, velocity.clamp(1, 127) / 127.0);
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
