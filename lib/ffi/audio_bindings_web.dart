// Web stub for the audio engine.
//
// On the web platform there is no native JUCE/FluidSynth library, so this
// provides the same API as `audio_bindings.dart` but does nothing. It is only
// imported on web (see the conditional import in main.dart) so that `dart:ffi`
// is never referenced in a web build.

class AudioEngineBridge {
  bool initialize() => false;
  void shutdown() {}

  void setVolume(double volume) {}
  double getVolume() => 0.0;

  void setTrackVolume(int index, double volume) {}
  void setTrackMute(int index, bool mute) {}
  void setTrackSolo(int index, bool solo) {}
  void setTrackInstrument(int index, int program) {}
  double getTrackPeakLevel(int index) => 0.0;

  bool isSoundFontLoaded() => false;
  String? getSoundFontPath() => null;

  void playDemo(bool play) {}
  bool loadMidiFile(String path) => false;
  bool loadSoundFont(String path) => false;

  void clearMidiSequence() {}
  void addMidiNote(int channel, int noteNumber, double startSeconds,
      double durationSeconds, double velocity) {}
  void playPreviewNote(int channel, int noteNumber, double velocity) {}
  void setLoopDuration(double loopSeconds) {}
  double getPlayheadTime() => 0.0;
}
