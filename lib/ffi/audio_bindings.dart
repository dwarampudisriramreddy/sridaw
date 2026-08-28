import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart'; // Needed for String conversion

typedef _InitJuceEngineC = ffi.Bool Function();
typedef _InitJuceEngineDart = bool Function();

typedef _ShutdownJuceEngineC = ffi.Void Function();
typedef _ShutdownJuceEngineDart = void Function();

typedef _SetEngineVolumeC = ffi.Void Function(ffi.Float volume);
typedef _SetEngineVolumeDart = void Function(double volume);

typedef _GetEngineVolumeC = ffi.Float Function();
typedef _GetEngineVolumeDart = double Function();

typedef _SetTrackVolumeC = ffi.Void Function(ffi.Int32 index, ffi.Float volume);
typedef _SetTrackVolumeDart = void Function(int index, double volume);

typedef _SetTrackMuteC = ffi.Void Function(ffi.Int32 index, ffi.Bool mute);
typedef _SetTrackMuteDart = void Function(int index, bool mute);

typedef _GetTrackPeakLevelC = ffi.Float Function(ffi.Int32 index);
typedef _GetTrackPeakLevelDart = double Function(int index);

typedef _PlayDemoC = ffi.Void Function(ffi.Bool play);
typedef _PlayDemoDart = void Function(bool play);

typedef _LoadMidiFileC = ffi.Bool Function(ffi.Pointer<Utf8> path);
typedef _LoadMidiFileDart = bool Function(ffi.Pointer<Utf8> path);

typedef _LoadTrackSampleC = ffi.Bool Function(ffi.Int32 index, ffi.Pointer<Utf8> path);
typedef _LoadTrackSampleDart = bool Function(int index, ffi.Pointer<Utf8> path);

typedef _ClearMidiSequenceC = ffi.Void Function();
typedef _ClearMidiSequenceDart = void Function();

typedef _AddMidiNoteC = ffi.Void Function(ffi.Int32 noteNumber, ffi.Double startSeconds, ffi.Double durationSeconds, ffi.Float velocity);
typedef _AddMidiNoteDart = void Function(int noteNumber, double startSeconds, double durationSeconds, double velocity);

typedef _SetLoopDurationC = ffi.Void Function(ffi.Double loopSeconds);
typedef _SetLoopDurationDart = void Function(double loopSeconds);

typedef _GetPlayheadTimeC = ffi.Double Function();
typedef _GetPlayheadTimeDart = double Function();

class AudioEngineBridge {
  late final ffi.DynamicLibrary _lib;
  
  late final _InitJuceEngineDart _initEngine;
  late final _ShutdownJuceEngineDart _shutdownEngine;
  late final _SetEngineVolumeDart _setVolume;
  late final _GetEngineVolumeDart _getVolume;
  
  late final _SetTrackVolumeDart _setTrackVolume;
  late final _SetTrackMuteDart _setTrackMute;
  late final _GetTrackPeakLevelDart _getTrackPeakLevel;
  late final _PlayDemoDart _playDemo;
  late final _LoadMidiFileDart _loadMidiFile;
  late final _LoadTrackSampleDart _loadTrackSample;
  
  late final _ClearMidiSequenceDart _clearMidiSequence;
  late final _AddMidiNoteDart _addMidiNote;
  late final _SetLoopDurationDart _setLoopDuration;
  late final _GetPlayheadTimeDart _getPlayheadTime;

  AudioEngineBridge() {
    if (Platform.isAndroid || Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libsridaw_juce.so');
    } else if (Platform.isWindows) {
      _lib = ffi.DynamicLibrary.open('sridaw_juce.dll');
    } else if (Platform.isMacOS || Platform.isIOS) {
      _lib = ffi.DynamicLibrary.open('libsridaw_juce.dylib');
    } else {
      throw UnsupportedError('Unsupported platform');
    }

    _initEngine = _lib.lookupFunction<_InitJuceEngineC, _InitJuceEngineDart>('initJuceEngine');
    _shutdownEngine = _lib.lookupFunction<_ShutdownJuceEngineC, _ShutdownJuceEngineDart>('shutdownJuceEngine');
    _setVolume = _lib.lookupFunction<_SetEngineVolumeC, _SetEngineVolumeDart>('setEngineVolume');
    _getVolume = _lib.lookupFunction<_GetEngineVolumeC, _GetEngineVolumeDart>('getEngineVolume');
    
    _setTrackVolume = _lib.lookupFunction<_SetTrackVolumeC, _SetTrackVolumeDart>('setTrackVolume');
    _setTrackMute = _lib.lookupFunction<_SetTrackMuteC, _SetTrackMuteDart>('setTrackMute');
    _getTrackPeakLevel = _lib.lookupFunction<_GetTrackPeakLevelC, _GetTrackPeakLevelDart>('getTrackPeakLevel');
    _playDemo = _lib.lookupFunction<_PlayDemoC, _PlayDemoDart>('playDemo');
    _loadMidiFile = _lib.lookupFunction<_LoadMidiFileC, _LoadMidiFileDart>('loadMidiFile');
    _loadTrackSample = _lib.lookupFunction<_LoadTrackSampleC, _LoadTrackSampleDart>('loadTrackSample');
    _clearMidiSequence = _lib.lookupFunction<_ClearMidiSequenceC, _ClearMidiSequenceDart>('clearMidiSequence');
    _addMidiNote = _lib.lookupFunction<_AddMidiNoteC, _AddMidiNoteDart>('addMidiNote');
    _setLoopDuration = _lib.lookupFunction<_SetLoopDurationC, _SetLoopDurationDart>('setLoopDuration');
    _getPlayheadTime = _lib.lookupFunction<_GetPlayheadTimeC, _GetPlayheadTimeDart>('getPlayheadTime');
  }

  bool initialize() => _initEngine();
  void shutdown() => _shutdownEngine();
  
  void setVolume(double volume) => _setVolume(volume);
  double getVolume() => _getVolume();
  
  void setTrackVolume(int index, double volume) => _setTrackVolume(index, volume);
  void setTrackMute(int index, bool mute) => _setTrackMute(index, mute);
  double getTrackPeakLevel(int index) => _getTrackPeakLevel(index);
  
  void playDemo(bool play) => _playDemo(play);

  bool loadMidiFile(String path) {
    final pathPtr = path.toNativeUtf8();
    final result = _loadMidiFile(pathPtr);
    malloc.free(pathPtr);
    return result;
  }

  bool loadTrackSample(int trackIndex, String path) {
    final pathPtr = path.toNativeUtf8();
    final result = _loadTrackSample(trackIndex, pathPtr);
    malloc.free(pathPtr);
    return result;
  }

  void clearMidiSequence() => _clearMidiSequence();
  
  void addMidiNote(int noteNumber, double startSeconds, double durationSeconds, double velocity) {
    _addMidiNote(noteNumber, startSeconds, durationSeconds, velocity);
  }
  
  void setLoopDuration(double loopSeconds) {
    _setLoopDuration(loopSeconds);
  }
  
  double getPlayheadTime() => _getPlayheadTime();
}
