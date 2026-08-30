import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ffi/audio_bindings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint("FATAL-UNHANDLED-ERROR: ${details.exceptionAsString()}");
    debugPrint("FATAL-STACK: ${details.stack}");
  };
  runApp(const DawApp());
}

/// A single note inside a phrase. `startStep`/`lengthSteps` are in 16th-note steps.
class NoteEvent {
  final int note;
  final int startStep;
  final int lengthSteps;
  const NoteEvent(this.note, this.startStep, this.lengthSteps);
}

/// A DAW track. Owns one phrase (its notes) and a list of bars where that
/// phrase is placed in the arrangement.
class Track {
  String name;
  int instrument; // GM program number
  final Color color;
  double vol;
  double pan;
  bool mute;
  bool solo;
  double peak;
  List<NoteEvent> notes;
  List<int> clips; // arrangement bars where the phrase is placed

  Track({
    required this.name,
    required this.instrument,
    required this.color,
    this.vol = 0.8,
    this.pan = 0.0,
    this.mute = false,
    this.solo = false,
    this.peak = 0.0,
    List<NoteEvent>? notes,
    List<int>? clips,
  })  : notes = notes ?? [],
        clips = clips ?? [];
}

// Curated GM instrument options.
const List<Map<String, dynamic>> kInstruments = [
  {'name': 'Grand Piano', 'program': 0},
  {'name': 'Bright Piano', 'program': 1},
  {'name': 'Drawbar Organ', 'program': 16},
  {'name': 'Acoustic Guitar', 'program': 24},
  {'name': 'Acoustic Bass', 'program': 32},
  {'name': 'String Ensemble', 'program': 48},
  {'name': 'Trumpet', 'program': 56},
  {'name': 'Saxophone', 'program': 65},
  {'name': 'Synth Lead', 'program': 80},
  {'name': 'Pad', 'program': 88},
  {'name': 'Woodblock', 'program': 115},
];

// Piano roll range (inclusive MIDI notes).
const int kLowNote = 48; // C3
const int kHighNote = 84; // C6
const int kStepsPerBar = 16; // 16th notes
const int kArrangementBars = 8;

class DawApp extends StatelessWidget {
  const DawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sri DAW',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0C0E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4ADE80),
          surface: Color(0xFF15151A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C0C0E),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          activeTrackColor: const Color(0xFF4ADE80),
          inactiveTrackColor: Colors.white12,
          thumbColor: Colors.white,
        ),
        dividerTheme: const DividerThemeData(color: Colors.white10),
      ),
      home: const DawWorkspace(),
    );
  }
}

class DawWorkspace extends StatefulWidget {
  const DawWorkspace({super.key});

  @override
  State<DawWorkspace> createState() => _DawWorkspaceState();
}

class _DawWorkspaceState extends State<DawWorkspace> {
  bool _isPlaying = false;
  double _masterVolume = 0.8;
  AudioEngineBridge? _audioBridge;
  Timer? _meterTimer;
  String _loadedMidiName = "";
  int _bpm = 120;
  int _noteLength = 2; // steps for newly painted notes
  int _selectedTrack = 0;
  int _playheadStep = -1;
  bool _isEngineReady = false;
  bool _autoReinitDone = false;
  String _editorMode = 'pads'; // 'pads' | 'keys'
  int _padWriteStep = 0;

  // On-screen debug console state
  bool _showDebug = false;
  bool _sfLoaded = false;
  String _sfPath = '';
  String _engineStatus = 'not started';
  final List<String> _logs = [];
  int _meterTickCount = 0;

  void _log(String msg) {
    debugPrint(msg);
    final t = DateTime.now().toString().substring(11, 19);
    if (mounted) setState(() => _logs.add('$t  $msg'));
  }

  final List<Track> _tracks = [
    Track(
      name: 'Keys',
      instrument: 0,
      color: const Color(0xFF60A5FA),
      notes: [
        const NoteEvent(60, 0, 2),
        const NoteEvent(64, 4, 2),
        const NoteEvent(67, 8, 2),
        const NoteEvent(72, 12, 4),
      ],
      clips: [0, 2, 4, 6],
    ),
    Track(name: 'Bass', instrument: 32, color: const Color(0xFF34D399)),
    Track(name: 'Strings', instrument: 48, color: const Color(0xFFA78BFA)),
    Track(name: 'Brass', instrument: 56, color: const Color(0xFFFBBF24)),
    Track(name: 'Lead', instrument: 80, color: const Color(0xFFF472B6)),
    Track(name: 'Perc', instrument: 115, color: const Color(0xFFFB923C)),
  ];

  double get _stepDuration => (60.0 / _bpm) / 4.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAudioEngine());
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), _onMeterTick);
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _audioBridge?.shutdown();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Audio engine
  // ---------------------------------------------------------------------------
  Future<void> _initAudioEngine({bool isAutoRetry = false}) async {
    final sw = Stopwatch()..start();
    _log("init: start${isAutoRetry ? ' (auto-retry)' : ''}");
    try {
      if (!isAutoRetry) {
        _engineStatus = 'requesting permissions';
        await Permission.microphone.request();
        await Permission.storage.request();
      }

      // Retry opening the engine: on cold start the audio device is sometimes
      // not ready and the first initialize() returns false. Re-init (later)
      // works, so we retry a few times here.
      bool success = false;
      for (int attempt = 0; attempt < 3 && !success; attempt++) {
        _engineStatus = 'creating bridge + initialize() (try ${attempt + 1})';
        _audioBridge = AudioEngineBridge();
        success = _audioBridge?.initialize() ?? false;
        _log("init: initialize() returned: $success (${sw.elapsedMilliseconds} ms)");
        if (!success && attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }

      if (success) {
        _engineStatus = 'loading soundfont';
        try {
          const platform = MethodChannel('com.ram.sridaw/assets');
          _log("init: calling extractSoundFont...");
          final String? sfPath = await platform.invokeMethod('extractSoundFont');
          _log("init: extractSoundFont -> ${sfPath ?? 'null'} (${sw.elapsedMilliseconds} ms)");
          if (sfPath != null) {
            bool sfLoaded = _audioBridge?.loadSoundFont(sfPath) ?? false;
            _sfLoaded = sfLoaded;
            _sfPath = sfPath;
            _log("init: loadSoundFont('$sfPath') -> $sfLoaded");
            _log("init: isSoundFontLoaded=${_audioBridge?.isSoundFontLoaded()}");
            if (!sfLoaded) {
              _log("ERROR: SoundFont failed to load — no audio will be produced. "
                   "Check the .sf2 file / path. FluidSynth noteon needs a preset on the channel.");
            }
          } else {
            _log("ERROR: extractSoundFont returned null (asset missing or MethodChannel mismatch)");
          }
        } catch (e) {
          _log("ERROR: Failed to extract/load SoundFont: $e");
        }

        _audioBridge?.setVolume(_masterVolume);
        for (int i = 0; i < _tracks.length; i++) {
          final t = _tracks[i];
          _audioBridge?.setTrackVolume(i, t.vol);
          _audioBridge?.setTrackInstrument(i, t.instrument);
          _audioBridge?.setTrackMute(i, t.mute);
        }
        setState(() => _isEngineReady = true);
        _engineStatus = 'ready';
        _log("init: Engine ready (total ${sw.elapsedMilliseconds} ms)");

        // Safety net: the audio device can open at cold start yet not actually
        // start its callback thread until the app has been foreground for a
        // moment. A single automatic re-init (just like the manual one) makes
        // the first Play reliably produce sound.
        if (!_autoReinitDone) {
          _autoReinitDone = true;
          Future.delayed(const Duration(milliseconds: 1200), () {
            _log("init: auto re-init (safety net)");
            _initAudioEngine(isAutoRetry: true);
          });
        }
      } else {
        _engineStatus = 'initialize() failed';
        _log("ERROR: initialize() returned false after retries — audio device could not be opened");
      }
    } catch (e) {
      _engineStatus = 'exception: $e';
      _log("ERROR: Engine init failed: $e");
    }
  }

  Future<void> _diagnose() async {
    _log("--- DIAGNOSE ---");
    _log("engineReady=$_isEngineReady  status=$_engineStatus");
    final loaded = _audioBridge?.isSoundFontLoaded() ?? false;
    final path = _audioBridge?.getSoundFontPath();
    _sfLoaded = loaded;
    _sfPath = path ?? '';
    _log("isSoundFontLoaded=$loaded");
    _log("soundFontPath=${path ?? '<null>'}");
    _log("isPlaying=$_isPlaying  masterVol=$_masterVolume");
  }

  void _testNote() {
    if (!_isEngineReady) {
      _log("testNote: engine not ready");
      return;
    }
    _audioBridge?.playPreviewNote(0, 60, 0.9);
    _log("testNote: played Middle C (ch0) — should hear piano if SF loaded");
    Future.delayed(const Duration(milliseconds: 700), () {
      _audioBridge?.playPreviewNote(0, 60, 0.0);
      _log("testNote: stopped");
    });
  }

  Future<void> _reinit() async {
    _log("re-init requested");
    await _initAudioEngine();
  }

  void _onMeterTick(Timer timer) {
    if (_audioBridge == null || !_isEngineReady) return;
    if (_isPlaying) {
      final double t = _audioBridge!.getPlayheadTime();
      final int totalSteps = kArrangementBars * kStepsPerBar;
      final int step = ((t / _stepDuration) % totalSteps).floor();
      setState(() {
        _playheadStep = step;
        for (int i = 0; i < _tracks.length; i++) {
          _tracks[i].peak = _tracks[i].mute ? 0.0 : _audioBridge!.getTrackPeakLevel(i);
        }
      });
      // Periodically log meter peaks (every ~1s) to confirm audio is flowing.
      if (++_meterTickCount % 20 == 0) {
        final peaks = _tracks.map((t) => t.peak.toStringAsFixed(3)).join(' ');
        _log("playhead=${t.toStringAsFixed(2)}s step=$step peaks[$peaks]");
      }
    } else if (_playheadStep != -1) {
      setState(() => _playheadStep = -1);
    }
  }

  void _togglePlayback() {
    if (!_isEngineReady) return;
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _syncArrangementToEngine();
      _audioBridge?.playDemo(true);
      _log("PLAY: arrangement synced, playDemo(true). stepDur=${_stepDuration.toStringAsFixed(4)}s");
    } else {
      _audioBridge?.playDemo(false);
      _audioBridge?.setLoopDuration(2.0);
      _log("STOP: playDemo(false)");
    }
  }

  /// Push the full arrangement (all tracks, all placed clips) into the engine.
  void _syncArrangementToEngine() {
    if (_audioBridge == null) return;
    _audioBridge!.clearMidiSequence();
    final double sd = _stepDuration;
    int noteCount = 0;
    for (int t = 0; t < _tracks.length; t++) {
      final tr = _tracks[t];
      for (final bar in tr.clips) {
        for (final n in tr.notes) {
          final double start = (bar * kStepsPerBar + n.startStep) * sd;
          final double dur = n.lengthSteps * sd;
          _audioBridge!.addMidiNote(t, n.note, start, dur, 0.85);
          noteCount++;
        }
      }
    }
    _audioBridge!.setLoopDuration(kArrangementBars * kStepsPerBar * sd);
    _log("sync: added $noteCount notes across ${_tracks.where((t) => t.clips.isNotEmpty).length} tracks; loop=${(kArrangementBars * kStepsPerBar * sd).toStringAsFixed(2)}s");
  }

  /// Play only the selected track's phrase (one bar loop).
  void _playSelectedPhrase() {
    if (_audioBridge == null || !_isEngineReady) return;
    final tr = _tracks[_selectedTrack];
    _audioBridge!.clearMidiSequence();
    final double sd = _stepDuration;
    for (final n in tr.notes) {
      _audioBridge!.addMidiNote(_selectedTrack, n.note, n.startStep * sd, n.lengthSteps * sd, 0.85);
    }
    _audioBridge!.setLoopDuration(kStepsPerBar * sd);
    _audioBridge?.playDemo(true);
    setState(() => _isPlaying = true);
    _log("PLAY PHRASE: track=${tr.name} (ch$_selectedTrack) ${tr.notes.length} notes; loop=${(kStepsPerBar * sd).toStringAsFixed(2)}s");
  }

  void _previewNote(int note, double velocity) {
    if (_audioBridge == null || !_isEngineReady) return;
    if (velocity > 0) {
      _log("preview: note=$note ch=$_selectedTrack vel=$velocity");
      _audioBridge!.playPreviewNote(_selectedTrack, note, velocity);
      Future.delayed(const Duration(milliseconds: 220), () {
        _audioBridge?.playPreviewNote(_selectedTrack, note, 0.0);
      });
    }
  }

  void _toggleNote(int note, int step) {
    final tr = _tracks[_selectedTrack];
    final idx = tr.notes.indexWhere(
        (n) => n.note == note && step >= n.startStep && step < n.startStep + n.lengthSteps);
    setState(() {
      if (idx >= 0) {
        tr.notes.removeAt(idx);
      } else {
        tr.notes.add(NoteEvent(note, step, _noteLength));
      }
    });
  }

  void _onTrackVolumeChanged(int index, double val) {
    setState(() {
      _tracks[index].vol = val;
      _audioBridge?.setTrackVolume(index, val);
    });
  }

  void _onTrackMuteToggled(int index) {
    setState(() {
      _tracks[index].mute = !_tracks[index].mute;
      _audioBridge?.setTrackMute(index, _tracks[index].mute);
    });
  }

  void _onTrackSoloToggled(int index) {
    setState(() {
      _tracks[index].solo = !_tracks[index].solo;
      _audioBridge?.setTrackSolo(index, _tracks[index].solo);
    });
  }

  void _onTrackInstrumentChanged(int index, int program) {
    setState(() {
      _tracks[index].instrument = program;
      _audioBridge?.setTrackInstrument(index, program);
    });
  }

  void _toggleClip(int trackIndex, int bar) {
    setState(() {
      final clips = _tracks[trackIndex].clips;
      if (clips.contains(bar)) {
        clips.remove(bar);
      } else {
        clips.add(bar);
      }
    });
  }

  Future<void> _pickMidiFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mid', 'midi'],
    );
    if (files != null && files.isNotEmpty) {
      final f = files.first;
      if (f.path != null) {
        final ok = _audioBridge?.loadMidiFile(f.path!) ?? false;
        if (ok && mounted) {
          setState(() => _loadedMidiName = f.name);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded MIDI: ${f.name}')),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SRI DAW',
            style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w300, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            tooltip: 'Debug console',
            color: _showDebug ? const Color(0xFF4ADE80) : null,
            onPressed: () => setState(() => _showDebug = !_showDebug),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined, size: 20),
            tooltip: 'Load MIDI',
            onPressed: _pickMidiFile,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildTransport(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('TRACKS'),
                      const SizedBox(height: 8),
                      ...List.generate(_tracks.length, (i) => _buildTrackCard(i)),
                      const SizedBox(height: 20),
                      _buildEditorPanel(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showDebug) _buildDebugPanel(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF8A8A93), fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildDebugPanel() {
    final Color dotColor = _sfLoaded ? const Color(0xFF4ADE80) : Colors.redAccent;
    return Positioned.fill(
      child: Column(
        children: [
          const Spacer(),
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.94),
              border: const Border(top: BorderSide(color: Color(0xFF4ADE80))),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white12)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: dotColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'SF: ${_sfLoaded ? "LOADED" : "NOT LOADED"}  ·  $_engineStatus',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                      _debugBtn('DIAGNOSE', _diagnose),
                      _debugBtn('TEST NOTE', _testNote),
                      _debugBtn('RE-INIT', _reinit),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: Colors.white54,
                        onPressed: () => setState(() => _showDebug = false),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Text(
                      _logs[i],
                      style: const TextStyle(
                        color: Color(0xFF9EFFB0),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _debugBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 10)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EDITOR PANEL — chord pads (Hooktheory style) + piano-roll (LMMS/BandLab)
  // ---------------------------------------------------------------------------
  // Diatonic chord pads for C major.
  static const List<Map<String, dynamic>> _chordPads = [
    {'label': 'I', 'notes': [60, 64, 67]},
    {'label': 'ii', 'notes': [62, 65, 69]},
    {'label': 'iii', 'notes': [64, 67, 71]},
    {'label': 'IV', 'notes': [65, 69, 72]},
    {'label': 'V', 'notes': [67, 71, 74]},
    {'label': 'vi', 'notes': [69, 72, 76]},
    {'label': 'vii°', 'notes': [71, 74, 77]},
  ];

  Widget _buildEditorPanel() {
    final tr = _tracks[_selectedTrack];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15151A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tr.color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 22, decoration: BoxDecoration(
                color: tr.color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr.name,
                    style: TextStyle(color: tr.color, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              _modeToggle('PADS', _editorMode == 'pads', () => setState(() => _editorMode = 'pads')),
              const SizedBox(width: 6),
              _modeToggle('KEYS', _editorMode == 'keys', () => setState(() => _editorMode = 'keys')),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int>(
                value: tr.instrument,
                underline: const SizedBox(),
                hint: const Text('Instrument'),
                items: kInstruments.map((ins) {
                  return DropdownMenuItem<int>(
                    value: ins['program'] as int,
                    child: Text(ins['name'] as String, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) _onTrackInstrumentChanged(_selectedTrack, v);
                },
              ),
              if (_editorMode == 'keys') ...[
                const Text('LEN', style: TextStyle(color: Color(0xFF8A8A93), fontSize: 11)),
                DropdownButton<int>(
                  value: _noteLength,
                  underline: const SizedBox(),
                  items: [1, 2, 4, 8].map((l) {
                    return DropdownMenuItem<int>(value: l, child: Text('$l', style: const TextStyle(fontSize: 13)));
                  }).toList(),
                  onChanged: (v) => setState(() => _noteLength = v ?? 2),
                ),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('PLAY'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4ADE80),
                  side: const BorderSide(color: Color(0xFF4ADE80)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _playSelectedPhrase,
              ),
              TextButton(
                child: const Text('CLEAR', style: TextStyle(color: Color(0xFF8A8A93))),
                onPressed: () => setState(() {
                  tr.notes.clear();
                  _padWriteStep = 0;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_editorMode == 'pads')
            _buildPads()
          else
            SizedBox(
              height: 340,
              child: PianoRollWidget(
                notes: tr.notes,
                color: tr.color,
                playheadStep: _playheadStep,
                onToggleNote: _toggleNote,
                onPreviewNote: _previewNote,
              ),
            ),
          if (_editorMode == 'keys')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Tap a cell to paint/erase a note · tap a key name to preview',
                  style: TextStyle(color: Color(0xFF8A8A93), fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _modeToggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4ADE80) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1,
          color: active ? Colors.black : const Color(0xFF8A8A93))),
      ),
    );
  }

  Widget _buildPads() {
    final color = _tracks[_selectedTrack].color;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _chordPads.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.4,
      ),
      itemBuilder: (_, i) {
        final pad = _chordPads[i];
        final notes = pad['notes'] as List<int>;
        return GestureDetector(
          onTap: () => _playChordPad(notes),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withOpacity(0.85), color.withOpacity(0.35)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.6)),
            ),
            alignment: Alignment.center,
            child: Text(pad['label'] as String,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
        );
      },
    );
  }

  void _playChordPad(List<int> notes) {
    if (!_isEngineReady) {
      _log('pad: engine not ready');
      return;
    }
    final ch = _selectedTrack;
    final tr = _tracks[ch];
    _log('pad: chord on ${tr.name} notes=$notes step=$_padWriteStep');
    for (final n in notes) {
      _audioBridge?.playPreviewNote(ch, n, 0.85);
    }
    setState(() {
      for (final n in notes) {
        tr.notes.add(NoteEvent(n, _padWriteStep, 4));
      }
      if (tr.clips.isEmpty) tr.clips.add(0);
      _padWriteStep = (_padWriteStep + 4) % kStepsPerBar;
    });
    Future.delayed(const Duration(milliseconds: 480), () {
      for (final n in notes) _audioBridge?.playPreviewNote(ch, n, 0.0);
    });
  }

  // ---------------------------------------------------------------------------
  // TRACKS — mixer strips + arrangement lanes (tap a track to select it)
  // ---------------------------------------------------------------------------
  Widget _buildTrackCard(int index) {
    final tr = _tracks[index];
    final bool selected = index == _selectedTrack;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15151A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? tr.color.withOpacity(0.7) : tr.color.withOpacity(0.25),
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row (tap to select this track for the editor)
          GestureDetector(
            onTap: () => setState(() => _selectedTrack = index),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(width: 4, height: 28, decoration: BoxDecoration(
                    color: tr.color, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr.name, style: TextStyle(color: tr.color, fontWeight: FontWeight.w700)),
                        Text(_instrumentName(tr.instrument),
                            style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 11)),
                      ],
                    ),
                  ),
                  _smallToggle('M', tr.mute, const Color(0xFFF87171), () => _onTrackMuteToggled(index)),
                  const SizedBox(width: 6),
                  _smallToggle('S', tr.solo, const Color(0xFFFBBF24), () => _onTrackSoloToggled(index)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: Slider(
                      value: tr.vol,
                      onChanged: (v) => _onTrackVolumeChanged(index, v),
                    ),
                  ),
                  // Meter
                  _miniMeter(tr.peak),
                ],
              ),
            ),
          ),
          // Arrangement lane (clips)
          Container(
            height: 46,
            margin: const EdgeInsets.only(left: 14, right: 14, bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: kArrangementBars,
              itemBuilder: (context, bar) {
                final hasClip = tr.clips.contains(bar);
                return GestureDetector(
                  onTap: () => _toggleClip(index, bar),
                  child: Container(
                    width: 56,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.white.withOpacity(0.04)),
                        left: bar % 1 == 0 ? BorderSide.none : BorderSide.none,
                      ),
                    ),
                    child: hasClip
                        ? Container(
                            margin: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: tr.color.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Text(tr.name,
                                  style: const TextStyle(fontSize: 9, color: Colors.black,
                                      fontWeight: FontWeight.w700)),
                            ),
                          )
                        : const SizedBox(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _instrumentName(int program) {
    for (final ins in kInstruments) {
      if (ins['program'] == program) return ins['name'] as String;
    }
    return 'GM $program';
  }

  Widget _smallToggle(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: active ? color : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color : Colors.white24),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
            color: active ? Colors.black : const Color(0xFF8A8A93))),
      ),
    );
  }

  Widget _miniMeter(double peak) {
    final p = peak.clamp(0.0, 1.0);
    return SizedBox(
      width: 8,
      height: 30,
      child: Container(
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(3)),
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: p,
          child: Container(
            decoration: BoxDecoration(
              color: p > 0.85 ? Colors.red : const Color(0xFF4ADE80),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Transport (top bar)
  // ---------------------------------------------------------------------------
  Widget _buildTransport() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          FloatingActionButton.small(
            backgroundColor: _isPlaying ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
            foregroundColor: Colors.black,
            onPressed: _togglePlayback,
            child: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          ),
          const SizedBox(width: 16),
          Tooltip(
            message: _sfLoaded
                ? 'SoundFont loaded: $_sfPath'
                : 'SoundFont NOT loaded — no audio. Tap bug icon for debug.',
            child: Icon(Icons.circle,
                size: 10, color: _sfLoaded ? const Color(0xFF4ADE80) : Colors.redAccent),
          ),
          const SizedBox(width: 10),
          const Text('BPM', style: TextStyle(color: Color(0xFF8A8A93), fontSize: 11)),
          const SizedBox(width: 6),
          DropdownButton<int>(
            value: _bpm,
            underline: const SizedBox(),
            items: [80, 100, 120, 140, 160].map((b) {
              return DropdownMenuItem<int>(value: b, child: Text('$b', style: const TextStyle(fontSize: 13)));
            }).toList(),
            onChanged: (v) => setState(() => _bpm = v ?? 120),
          ),
          const Spacer(),
          const Icon(Icons.volume_up, size: 18, color: Color(0xFF8A8A93)),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Slider(
              value: _masterVolume,
              onChanged: (v) {
                setState(() {
                  _masterVolume = v;
                  _audioBridge?.setVolume(v);
                });
              },
            ),
          ),
          if (_loadedMidiName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(_loadedMidiName, style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Vertical Piano Roll
// =============================================================================
class PianoRollWidget extends StatelessWidget {
  final List<NoteEvent> notes;
  final Color color;
  final int playheadStep;
  final void Function(int note, int step) onToggleNote;
  final void Function(int note, double velocity) onPreviewNote;

  const PianoRollWidget({
    super.key,
    required this.notes,
    required this.color,
    this.playheadStep = -1,
    required this.onToggleNote,
    required this.onPreviewNote,
  });

  static const double _rowHeight = 16.0;
  static const double _stepWidth = 26.0;
  static const double _keyWidth = 50.0;

  @override
  Widget build(BuildContext context) {
    final int noteCount = kHighNote - kLowNote + 1;
    final double gridH = noteCount * _rowHeight;
    final double gridW = kArrangementBars * kStepsPerBar * _stepWidth;

    final Widget keyboard = SizedBox(
      width: _keyWidth,
      height: gridH,
      child: Column(
        children: List.generate(noteCount, (i) {
          final note = kHighNote - i;
          final black = const {1, 3, 6, 8, 10}.contains(note % 12);
          return GestureDetector(
            onTapDown: (_) => onPreviewNote(note, 0.85),
            child: Container(
              height: _rowHeight,
              decoration: BoxDecoration(
                color: black ? const Color(0xFF1A1A1E) : const Color(0xFF2A2A30),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.04)),
                  right: const BorderSide(color: Colors.white10),
                ),
              ),
              padding: const EdgeInsets.only(right: 6),
              alignment: Alignment.centerRight,
              child: black
                  ? null
                  : Text(_noteLabel(note),
                      style: const TextStyle(fontSize: 9, color: Color(0xFF8A8A93))),
            ),
          );
        }),
      ),
    );

    final Widget grid = SizedBox(
      width: gridW,
      height: gridH,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(gridW, gridH),
            painter: _GridPainter(color: color, stepWidth: _stepWidth, rowHeight: _rowHeight,
                steps: kArrangementBars * kStepsPerBar, lowNote: kLowNote, highNote: kHighNote),
          ),
          CustomPaint(
            size: Size(gridW, gridH),
            painter: _NotesPainter(notes: notes, color: color, stepWidth: _stepWidth,
                rowHeight: _rowHeight, lowNote: kLowNote),
          ),
          if (playheadStep >= 0)
            Positioned(
              left: playheadStep * _stepWidth.toDouble(),
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: Colors.white.withOpacity(0.7)),
            ),
          // Tap layer
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (d) {
                final int step = (d.localPosition.dx / _stepWidth).floor()
                    .clamp(0, kArrangementBars * kStepsPerBar - 1);
                final int row = (d.localPosition.dy / _rowHeight).floor()
                    .clamp(0, kHighNote - kLowNote);
                final int note = kHighNote - row;
                onToggleNote(note, step);
              },
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double gridAreaW = (constraints.maxWidth - _keyWidth).clamp(0.0, constraints.maxWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              keyboard,
              SizedBox(
                width: gridAreaW,
                height: gridH,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: grid,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _noteLabel(int note) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${names[note % 12]}${(note ~/ 12) - 1}';
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  final double stepWidth;
  final double rowHeight;
  final int steps;
  final int lowNote;
  final int highNote;

  _GridPainter({required this.color, required this.stepWidth, required this.rowHeight,
      required this.steps, required this.lowNote, required this.highNote});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.04);
    // horizontal note rows
    for (int n = lowNote; n <= highNote; n++) {
      final y = (highNote - n) * rowHeight;
      final isBlack = const {1, 3, 6, 8, 10}.contains(n % 12);
      if (isBlack) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, rowHeight),
            Paint()..color = Colors.black.withOpacity(0.18));
      }
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // vertical step lines (bar lines brighter)
    for (int s = 0; s <= steps; s++) {
      final x = s * stepWidth;
      final isBar = s % kStepsPerBar == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()..color = isBar ? color.withOpacity(0.22) : Colors.white.withOpacity(0.03),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => false;
}

class _NotesPainter extends CustomPainter {
  final List<NoteEvent> notes;
  final Color color;
  final double stepWidth;
  final double rowHeight;
  final int lowNote;

  _NotesPainter({required this.notes, required this.color, required this.stepWidth,
      required this.rowHeight, required this.lowNote});

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in notes) {
      final double x = n.startStep * stepWidth;
      final double w = n.lengthSteps * stepWidth - 1;
      final double y = (kHighNote - n.note) * rowHeight + 1;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, rowHeight - 2),
        const Radius.circular(3),
      );
      canvas.drawRRect(r, Paint()..color = color.withOpacity(0.9));
    }
  }

  @override
  bool shouldRepaint(covariant _NotesPainter old) => old.notes != notes;
}
