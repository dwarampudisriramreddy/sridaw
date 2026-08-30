import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'theme.dart';
import 'music_theory.dart';
import 'models.dart';
import 'ffi/audio_bindings.dart'
    if (dart.library.js_interop) 'ffi/audio_bindings_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FATAL-UNHANDLED-ERROR: ${details.exceptionAsString()}');
  };
  runApp(const DawApp());
}

class DawApp extends StatelessWidget {
  const DawApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sri DAW',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const DawShell(),
    );
  }
}

enum _TlDragMode { move, resizeLeft, resizeRight }

class DawShell extends StatefulWidget {
  const DawShell({super.key});
  @override
  State<DawShell> createState() => _DawShellState();
}

class _DawShellState extends State<DawShell> {
  // -------------------------------------------------------------------------
  // Project + UI state
  // -------------------------------------------------------------------------
  final List<Track> _tracks = sampleProject();
  int _activeTab = 0;
  Track? _openTrack;
  Pattern? _openPattern;
  int _rootNoteIndex = 0;
  String _scaleName = 'Major';
  int? _previewedDegree;
  int? _lastTapIndex;
  DateTime? _lastTapTime;
  int _noteLen = 4;
  int _snapDiv = 2; // snap divisor: 1=1/32, 2=1/16, 4=1/8, 8=1/4, 16=1/2, 32=1bar
  bool _scaleOnly = false;
  int _totalBars = 8;

  // Timeline drag state
  Track? _tlDragTrack;
  Pattern? _tlDragPattern;
  double _tlDragStartX = 0;
  int _tlDragOrigStart = 0;
  int _tlDragOrigLen = 0;
  _TlDragMode _tlDragMode = _TlDragMode.move;

  // Drawing / moving state for piano roll
  bool _drawingExistingNote = false;
  int _drawingNoteIdx = -1;
  int _lastDrawCol = -1;
  int _panStartCol = 0;
  double _panStartDx = 0;
  int _moveBaseCol = 0;
  bool _hasPanned = false;
  double _lastTapDx = 0;

  // Virtual piano + record
  bool _recordingPiano = false;
  final Set<int> _heldPianoKeys = {};
  int _pianoRecCol = 0;
  int _pianoRecOctStart = 4; // lowest octave shown

  bool _isPlaying = false;
  bool _loop = true;
  bool _recording = false;
  int _bpm = 120;
  double _masterVolume = 0.8;
  double _playheadBar = 0;
  DateTime? _playStart;

  // Audio engine
  AudioEngineBridge? _audioBridge;
  Timer? _meterTimer;
  Timer? _playheadTimer;
  bool _isEngineReady = false;
  bool _autoReinitDone = false;

  // Debug console
  bool _showDebug = false;
  bool _sfLoaded = false;
  String _sfPath = '';
  String _engineStatus = 'not started';
  final List<String> _logs = [];

  void _log(String msg) {
    debugPrint(msg);
    final t = DateTime.now().toString().substring(11, 19);
    if (mounted) setState(() => _logs.add('$t  $msg'));
  }

  int get _openTrackIndex =>
      _openTrack == null ? 0 : _tracks.indexOf(_openTrack!);
  double get _stepDur => (60.0 / _bpm) / 4.0;

  @override
  void initState() {
    super.initState();
    _openTrack = _tracks[0];
    _openPattern = _tracks[0].patterns.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAudioEngine());
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), _onMeterTick);
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _playheadTimer?.cancel();
    _audioBridge?.shutdown();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Audio engine
  // -------------------------------------------------------------------------
  Future<void> _initAudioEngine({bool isAutoRetry = false}) async {
    final sw = Stopwatch()..start();
    _log('init: start${isAutoRetry ? ' (auto-retry)' : ''}');

    if (kIsWeb) {
      _log('init: WEB PREVIEW — audio engine disabled');
      setState(() {
        _isEngineReady = false;
        _sfLoaded = false;
        _engineStatus = 'web preview (no audio)';
      });
      return;
    }

    try {
      if (!isAutoRetry) {
        await Permission.microphone.request();
        await Permission.storage.request();
      }

      bool success = false;
      for (int attempt = 0; attempt < 3 && !success; attempt++) {
        _engineStatus = 'creating bridge + initialize() (try ${attempt + 1})';
        _audioBridge = AudioEngineBridge();
        success = _audioBridge?.initialize() ?? false;
        _log('init: initialize() -> $success (${sw.elapsedMilliseconds} ms)');
        if (!success && attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }

      if (success) {
        _engineStatus = 'loading soundfont';
        try {
          const platform = MethodChannel('com.ram.sridaw/assets');
          final String? sfPath =
              await platform.invokeMethod('extractSoundFont');
          if (sfPath != null) {
            _sfLoaded = _audioBridge?.loadSoundFont(sfPath) ?? false;
            _sfPath = sfPath;
            _log('init: loadSoundFont -> $_sfLoaded');
          } else {
            _log('ERROR: extractSoundFont returned null');
          }
        } catch (e) {
          _log('ERROR: soundfont: $e');
        }
        _audioBridge?.setVolume(_masterVolume);
        for (int i = 0; i < _tracks.length; i++) {
          _audioBridge?.setTrackVolume(i, _tracks[i].vol);
          _audioBridge?.setTrackInstrument(i, _tracks[i].instrument);
          _audioBridge?.setTrackMute(i, _tracks[i].mute);
          _audioBridge?.setTrackSolo(i, _tracks[i].solo);
        }
        setState(() => _isEngineReady = true);
        _engineStatus = 'ready';
        _log('init: ready (${sw.elapsedMilliseconds} ms)');
        if (!_autoReinitDone) {
          _autoReinitDone = true;
          Future.delayed(const Duration(milliseconds: 1200), () {
            _log('init: auto re-init (safety net)');
            _initAudioEngine(isAutoRetry: true);
          });
        }
      } else {
        _engineStatus = 'initialize() failed';
        _log('ERROR: initialize() false after retries');
      }
    } catch (e) {
      _engineStatus = 'exception: $e';
      _log('ERROR: init: $e');
    }
  }

  void _onMeterTick(Timer t) {
    if (_audioBridge == null || !_isEngineReady) return;
    if (_isPlaying) {
      for (int i = 0; i < _tracks.length; i++) {
        _tracks[i].peak =
            _tracks[i].mute ? 0.0 : _audioBridge!.getTrackPeakLevel(i);
      }
    }
  }

  void _onPlayheadTick(Timer t) {
    if (!_isPlaying) return;
    final elapsed =
        DateTime.now().difference(_playStart!).inMilliseconds / 1000.0;
    final barDur = (60.0 / _bpm) * 4.0;
    setState(() => _playheadBar = (elapsed / barDur) % kTimelineBars);
  }

  void _togglePlayback() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      if (!kIsWeb) {
        _syncArrangement();
        _audioBridge?.playDemo(true);
      }
      _playStart = DateTime.now();
      _playheadTimer =
          Timer.periodic(const Duration(milliseconds: 50), _onPlayheadTick);
      _log('PLAY  bpm=$_bpm loop=$_loop');
    } else {
      if (!kIsWeb) _audioBridge?.playDemo(false);
      _playheadTimer?.cancel();
      _playheadTimer = null;
      setState(() => _playheadBar = 0);
      _log('STOP');
    }
  }

  void _syncArrangement() {
    if (_audioBridge == null) return;
    _audioBridge!.clearMidiSequence();
    final sd = _stepDur;
    int count = 0;
    for (int t = 0; t < _tracks.length; t++) {
      final tr = _tracks[t];
      for (final p in tr.patterns) {
        for (final n in p.notes) {
          final midi = octNToMidi(n.oct, n.n);
          final start = (p.start * 16 + n.startCol) * sd;
          _audioBridge!.addMidiNote(t, midi, start, n.len * sd, 0.85);
          count++;
        }
      }
    }
    _audioBridge!.setLoopDuration(kTimelineBars * 16 * sd);
    _log('sync: $count notes; loop=${(kTimelineBars * 16 * sd).toStringAsFixed(2)}s');
  }

  void _previewChord(int degree) {
    setState(() => _previewedDegree = degree);
    if (kIsWeb || !_isEngineReady) return;
    final pitches = chordPitches(_rootNoteIndex, _scaleName, degree);
    final ch = _openTrackIndex;
    for (final p in pitches) {
      _audioBridge?.playPreviewNote(ch, octNToMidi(p.oct, p.n), 0.85);
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final p in pitches) {
        _audioBridge?.playPreviewNote(ch, octNToMidi(p.oct, p.n), 0.0);
      }
    });
  }

  void _commitChord(int degree) {
    if (_openPattern == null) _ensureOpenPattern();
    final pitches = chordPitches(_rootNoteIndex, _scaleName, degree);
    int nextCol = 0;
    if (_openPattern!.notes.isNotEmpty) {
      nextCol = _openPattern!.notes
          .map((n) => n.startCol + n.len)
          .reduce((a, b) => a > b ? a : b);
      if (nextCol + 4 > kRollCols) nextCol = 0;
    }
    setState(() {
      for (int i = 0; i < pitches.length; i++) {
        final p = pitches[i];
        _openPattern!.notes.add(NoteEvent(
            oct: p.oct, n: p.n, startCol: nextCol, len: 4, chordRoot: i == 0));
      }
      _previewedDegree = null;
    });
    _log('commit chord degree ${degree + 1} at col $nextCol');
  }

  void _onPadTap(int degree) {
    final now = DateTime.now();
    if (_lastTapIndex == degree &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 350)) {
      _commitChord(degree);
      _lastTapIndex = null;
      _lastTapTime = null;
    } else {
      _previewChord(degree);
      _lastTapIndex = degree;
      _lastTapTime = now;
    }
  }

  void _ensureOpenPattern() {
    if (_openPattern != null) return;
    _openTrack = _tracks[0];
    _openPattern = Pattern(
        id: 'new', start: 0, len: 2, label: 'NEW', seed: 7,
        notes: []);
    _openTrack!.patterns.add(_openPattern!);
  }

  int _snapToGrid(int col) => (col ~/ _snapDiv) * _snapDiv;
  int get _snapColumns => 32 ~/ _snapDiv;
  double _colToDx(int col) => col * kColWidth;
  int _dxToCol(double dx) =>
      (dx / kColWidth).floor().clamp(0, _snapColumns - 1);

  /// Find index of an existing note at (oct,n) covering the given column.
  int _findNoteAt(int oct, int n, int col) {
    final p = _openPattern;
    if (p == null) return -1;
    for (int i = 0; i < p.notes.length; i++) {
      final e = p.notes[i];
      if (e.oct == oct && e.n == n && col >= e.startCol && col < e.startCol + e.len) {
        return i;
      }
    }
    return -1;
  }

  void _addNoteAt(int oct, int n, int col) {
    if (_openPattern == null) _ensureOpenPattern();
    final snapped = _snapToGrid(col);
    if (_openPattern!.notes.any((e) => e.oct == oct && e.n == n && e.startCol == snapped)) return;
    setState(() {
      _openPattern!.notes.add(NoteEvent(oct: oct, n: n, startCol: snapped, len: _snapDiv, chordRoot: false));
    });
    if (!kIsWeb && _isEngineReady) {
      _audioBridge?.playPreviewNote(_openTrackIndex, octNToMidi(oct, n), 0.85);
    }
  }

  void _moveNoteTo(int oct, int n, int noteIdx, int newCol) {
    final p = _openPattern;
    if (p == null || noteIdx < 0 || noteIdx >= p.notes.length) return;
    final note = p.notes[noteIdx];
    if (note.oct != oct || note.n != n) return;
    final snapped = _snapToGrid(newCol).clamp(0, _snapColumns - note.len);
    setState(() => note.startCol = snapped);
  }

  // --- gesture handlers for each roll row ---
  void _rollDown(int oct, int n, double dx) {
    _hasPanned = false;
    _lastTapDx = dx;
    final col = _dxToCol(dx);
    final idx = _findNoteAt(oct, n, col);
    if (idx >= 0) {
      _drawingExistingNote = true;
      _drawingNoteIdx = idx;
      _moveBaseCol = _openPattern!.notes[idx].startCol;
    } else {
      _drawingExistingNote = false;
      _drawingNoteIdx = -1;
      _lastDrawCol = col;
      _addNoteAt(oct, n, col);
    }
    _panStartDx = dx;
    _panStartCol = col;
  }

  void _rollTap(int oct, int n) {
    if (_hasPanned) return; // handled by pan
    if (_drawingExistingNote && _drawingNoteIdx >= 0) {
      setState(() => _openPattern!.notes.removeAt(_drawingNoteIdx));
      if (!kIsWeb && _isEngineReady) {
        _audioBridge?.playPreviewNote(_openTrackIndex, octNToMidi(oct, n), 0.0);
      }
    }
  }

  void _rollPanStart(int oct, int n, double dx) {
    _hasPanned = true;
    if (_drawingExistingNote) {
      _panStartDx = dx;
      _moveBaseCol = _openPattern!.notes[_drawingNoteIdx].startCol;
    }
  }

  void _rollPanUpdate(int oct, int n, double dx) {
    final col = _dxToCol(dx);
    if (_drawingExistingNote && _drawingNoteIdx >= 0) {
      final delta = col - _panStartCol;
      _moveNoteTo(oct, n, _drawingNoteIdx, _moveBaseCol + delta);
    } else {
      if (col != _lastDrawCol) {
        _addNoteAt(oct, n, col);
        _lastDrawCol = col;
      }
    }
  }

  void _rollPanEnd() {
    _hasPanned = false;
    _drawingExistingNote = false;
    _drawingNoteIdx = -1;
  }

  void _openPatternInRoll(Track track, Pattern p) {
    setState(() {
      _openTrack = track;
      _openPattern = p;
      _activeTab = 1;
    });
  }

  void _createPatternAt(Track track, int bar) {
    final p = Pattern(
      id: '${track.name.toLowerCase()}_${bar}_${track.patterns.length}',
      start: bar,
      len: 2,
      label: '${track.name[0]}${bar + 1}',
      seed: bar * 13 + track.patterns.length * 7,
    );
    setState(() {
      track.patterns.add(p);
      _openTrack = track;
      _openPattern = p;
      _activeTab = 1;
    });
    _log('created pattern "${p.label}" at bar $bar');
  }

  void _toggleMute(int i) {
    setState(() {
      _tracks[i].mute = !_tracks[i].mute;
      _audioBridge?.setTrackMute(i, _tracks[i].mute);
    });
  }

  void _toggleSolo(int i) {
    setState(() {
      _tracks[i].solo = !_tracks[i].solo;
      _audioBridge?.setTrackSolo(i, _tracks[i].solo);
    });
  }

  void _setTrackVol(int i, double v) {
    setState(() => _tracks[i].vol = v);
    _audioBridge?.setTrackVolume(i, v);
  }

  // -------------------------------------------------------------------------
  // Save / Load project
  // -------------------------------------------------------------------------
  Map<String, dynamic> _projectToJson() {
    return {
      'bpm': _bpm,
      'totalBars': _totalBars,
      'tracks': _tracks.map((tr) => {
        'name': tr.name,
        'type': tr.type.name,
        'color': tr.color.value,
        'mute': tr.mute,
        'solo': tr.solo,
        'instrument': tr.instrument,
        'vol': tr.vol,
        'pan': tr.pan,
        'patterns': tr.patterns.map((p) => {
          'id': p.id,
          'start': p.start,
          'len': p.len,
          'label': p.label,
          'seed': p.seed,
          'notes': p.notes.map((n) => {
            'oct': n.oct,
            'n': n.n,
            'startCol': n.startCol,
            'len': n.len,
            'chordRoot': n.chordRoot,
          }).toList(),
        }).toList(),
      }).toList(),
    };
  }

  void _projectFromJson(Map<String, dynamic> j) {
    _bpm = (j['bpm'] as num?)?.toInt() ?? 120;
    _totalBars = (j['totalBars'] as num?)?.toInt() ?? 8;
    _tracks.clear();
    for (final tj in j['tracks'] as List<dynamic>) {
      final tr = Track(
        name: tj['name'] as String,
        type: TrackType.values.firstWhere((e) => e.name == tj['type'],
            orElse: () => TrackType.synth),
        color: Color((tj['color'] as num).toInt()),
        mute: tj['mute'] as bool? ?? false,
        solo: tj['solo'] as bool? ?? false,
        instrument: (tj['instrument'] as num?)?.toInt() ?? 0,
        vol: (tj['vol'] as num?)?.toDouble() ?? 0.8,
        pan: (tj['pan'] as num?)?.toDouble() ?? 0.0,
      );
      for (final pj in tj['patterns'] as List<dynamic>) {
        final p = Pattern(
          id: pj['id'] as String,
          start: (pj['start'] as num).toInt(),
          len: (pj['len'] as num).toInt(),
          label: pj['label'] as String,
          seed: (pj['seed'] as num).toInt(),
        );
        for (final nj in pj['notes'] as List<dynamic>) {
          p.notes.add(NoteEvent(
            oct: (nj['oct'] as num).toInt(),
            n: (nj['n'] as num).toInt(),
            startCol: (nj['startCol'] as num).toInt(),
            len: (nj['len'] as num).toInt(),
            chordRoot: nj['chordRoot'] as bool? ?? false,
          ));
        }
        tr.patterns.add(p);
      }
      _tracks.add(tr);
    }
    _openTrack = _tracks.isNotEmpty ? _tracks[0] : null;
    _openPattern = (_openTrack != null && _openTrack!.patterns.isNotEmpty)
        ? _openTrack!.patterns.first
        : null;
    _log('loaded project: ${_tracks.length} tracks, ${_totalBars} bars');
  }

  Future<void> _saveProject() async {
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(_projectToJson());
      final bytes = utf8.encode(jsonStr);
      final uri = await FilePicker.saveFile(
        fileName: 'sridaw_project.json',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/json',
        dialogTitle: 'Save Project',
      );
      if (uri != null) {
        _log('project saved to ${uri.path}');
      }
    } catch (e) {
      _log('save error: $e');
    }
  }

  Future<void> _loadProject() async {
    try {
      final results = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (results.isNotEmpty) {
        final file = results.first;
        final bytes = await file.readAsBytes();
        final jsonStr = utf8.decode(bytes);
        final j = jsonDecode(jsonStr) as Map<String, dynamic>;
        setState(() => _projectFromJson(j));
        _log('project loaded from ${file.name}');
      }
    } catch (e) {
      _log('load error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTransport(),
              Expanded(
                child: IndexedStack(
                  index: _activeTab,
                  children: [
                    _buildTimelineTab(),
                    _buildPianoRollTab(),
                    _buildMixerTab(),
                    _buildFxTab(),
                  ],
                ),
              ),
              _buildBottomTabBar(),
            ],
          ),
          if (_showDebug) _buildDebugPanel(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Transport bar
  // -------------------------------------------------------------------------
  Widget _buildTransport() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Row(
        children: [
          _transportBtn(
            icon: Icons.circle,
            color: _recording ? AppColors.red : AppColors.textFaint,
            glow: _recording,
            onTap: () => setState(() => _recording = !_recording),
          ),
          const SizedBox(width: 8),
          _transportBtn(
            icon: _isPlaying ? Icons.stop : Icons.play_arrow,
            color: _isPlaying ? AppColors.red : AppColors.teal,
            filled: true,
            onTap: _togglePlayback,
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText.mono(_bpm.toString().padLeft(3, '0'),
                  size: 20, weight: FontWeight.w700, color: AppColors.text),
              AppText.ui('BPM', size: 8, color: AppColors.textFaint,
                  letterSpacing: 2),
            ],
          ),
          const Spacer(),
          _chip(_loop ? 'LOOP' : 'LOOP',
              active: _loop, onTap: () => setState(() => _loop = !_loop)),
          const SizedBox(width: 8),
          _chip('4/4', active: true, onTap: () {}),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 18, color: AppColors.textFaint),
            onPressed: _saveProject,
            tooltip: 'Save project',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 18, color: AppColors.textFaint),
            onPressed: _loadProject,
            tooltip: 'Load project',
          ),
          IconButton(
            icon: Icon(Icons.bug_report_outlined,
                size: 18,
                color: _showDebug ? AppColors.teal : AppColors.textFaint),
            onPressed: () => setState(() => _showDebug = !_showDebug),
          ),
        ],
      ),
    );
  }

  Widget _transportBtn(
      {required IconData icon,
      required Color color,
      bool filled = false,
      bool glow = false,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : Colors.transparent,
          border: Border.all(
              color: filled ? color : color.withOpacity(0.5), width: 1.5),
          boxShadow: glow
              ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 10)]
              : null,
        ),
        child: Icon(icon, size: 18, color: filled ? AppColors.bgDeep : color),
      ),
    );
  }

  Widget _chip(String label, {required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: active ? AppColors.tealDim : Colors.transparent,
          border: Border.all(
              color: active ? AppColors.teal : AppColors.line, width: 1),
        ),
        child: AppText.ui(label,
            size: 9,
            weight: FontWeight.w600,
            letterSpacing: 1,
            color: active ? AppColors.teal : AppColors.textFaint),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Bottom tab bar
  // -------------------------------------------------------------------------
  Widget _buildBottomTabBar() {
    const items = [
      (Icons.timeline, 'TIMELINE'),
      (Icons.piano, 'KEYS'),
      (Icons.equalizer, 'MIXER'),
      (Icons.waves, 'FX'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.lineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(items.length, (i) {
              final active = _activeTab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeTab = i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(items[i].$1,
                          size: 20,
                          color: active
                              ? AppColors.teal
                              : AppColors.textFaint),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                    decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? AppColors.teal
                                  : AppColors.textFaint,
                            ),
                          ),
                          const SizedBox(width: 5),
                          AppText.ui(items[i].$2,
                              size: 8.5,
                              weight: FontWeight.w600,
                              letterSpacing: 1,
                              color: active
                                  ? AppColors.teal
                                  : AppColors.textFaint),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // TIMELINE TAB
  // =========================================================================
  Widget _buildTimelineTab() {
    final totalW = _totalBars * kBarWidth;
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sticky header column
          Column(
            children: [
              const SizedBox(height: 24), // ruler spacer
              for (int i = 0; i < _tracks.length; i++)
                _buildTrackHeader(_tracks[i], i),
            ],
          ),
          // Scrolling body
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRuler(totalW),
                      for (int i = 0; i < _tracks.length; i++)
                        _buildTrackLane(_tracks[i], i, totalW),
                    ],
                  ),
                  // Playhead
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 50),
                    left: _playheadBar * kBarWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: AppColors.amber,
                      child: CustomPaint(
                        painter: _PlayheadFlagPainter(),
                        size: const Size(2, 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackHeader(Track tr, int index) {
    return Container(
      width: kTrackHeaderWidth,
      height: kTimelineRowHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 5,
            height: kTimelineRowHeight - 12,
            decoration: BoxDecoration(
              color: tr.color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.name,
                    style: AppText.uiStyle(10.5,
                        weight: FontWeight.w700, color: AppColors.text),
                    overflow: TextOverflow.ellipsis),
                Text(tr.type.name.toUpperCase(),
                    style: AppText.monoStyle(7.5,
                        color: AppColors.textFaint, letterSpacing: 1)),
              ],
            ),
          ),
          _knob(12, tr.color),
          const SizedBox(width: 4),
          _miniToggle('M', tr.mute, AppColors.red, () => _toggleMute(index)),
          const SizedBox(width: 3),
          _miniToggle('S', tr.solo, AppColors.amber, () => _toggleSolo(index)),
        ],
      ),
    );
  }

  Widget _buildRuler(double totalW) {
    return SizedBox(
      height: 24,
      width: totalW + 40,
      child: Row(
        children: [
          ...List.generate(_totalBars, (bar) {
            final accent = bar % 4 == 0;
            return Container(
              width: kBarWidth,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                      color: accent ? AppColors.amberDim : AppColors.lineSoft),
                  left: bar == 0
                      ? const BorderSide(color: AppColors.lineSoft)
                      : BorderSide.none,
                ),
              ),
              padding: const EdgeInsets.only(left: 5, top: 4),
              child: AppText.mono('${bar + 1}',
                  size: 9,
                  color: accent ? AppColors.amber : AppColors.textFaint),
            );
          }),
          // Extend bars button
          GestureDetector(
            onTap: () => setState(() => _totalBars += 4),
            child: Container(
              width: 36,
              height: 24,
              color: AppColors.panelRaised,
              child: const Icon(Icons.add, size: 14, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackLane(Track tr, int index, double totalW) {
    return Container(
      height: kTimelineRowHeight,
      width: totalW + 40,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Stack(
        children: [
          // gridlines
          Row(
            children: List.generate(_totalBars, (bar) {
              return Container(
                width: kBarWidth,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppColors.lineSoft),
                    left: bar == 0
                        ? const BorderSide(color: AppColors.lineSoft)
                        : BorderSide.none,
                  ),
                ),
              );
            }),
          ),
          // pattern blocks
          for (final p in tr.patterns)
            Positioned(
              left: p.start * kBarWidth + 2,
              width: p.len * kBarWidth - 4,
              top: 4,
              bottom: 4,
              child: GestureDetector(
                onTap: () => _openPatternInRoll(tr, p),
                onPanStart: (d) => _tlDragStart(tr, p, d),
                onPanUpdate: (d) => _tlDragUpdate(d),
                onPanEnd: (d) => _tlDragEnd(),
                child: _buildPatternBlock(p, tr),
              ),
            ),
          // empty-bar placeholders
          for (int bar = 0; bar < _totalBars; bar++)
            if (!tr.patterns.any((p) => bar >= p.start && bar < p.start + p.len))
              Positioned(
                left: bar * kBarWidth + 4,
                width: kBarWidth - 8,
                top: 4,
                bottom: 4,
                child: GestureDetector(
                  onTap: () => _createPatternAt(tr, bar),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppColors.line,
                          style: BorderStyle.solid),
                    ),
                    child: const Center(
                      child: Icon(Icons.add,
                          size: 14, color: AppColors.textFaint),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildPatternBlock(Pattern p, Track tr) {
    return Container(
      decoration: BoxDecoration(
        color: tr.color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.only(left: 6, top: 4),
      child: Stack(
        children: [
          AppText.mono(p.label,
              size: 9, weight: FontWeight.w700, color: AppColors.bgDeep),
          if (p.notes.isEmpty)
            _patternDots(p.seed, tr.color)
          else
            _patternMarks(p, tr.color),
          // Left resize handle
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
              ),
            ),
          ),
          // Right resize handle
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Timeline drag — move / resize
  // -------------------------------------------------------------------------
  void _tlDragStart(Track tr, Pattern p, DragStartDetails d) {
    final localX = d.localPosition.dx;
    final blockW = p.len * kBarWidth - 4;
    const edgeZone = 14.0;
    _TlDragMode mode;
    if (localX < edgeZone) {
      mode = _TlDragMode.resizeLeft;
    } else if (localX > blockW - edgeZone) {
      mode = _TlDragMode.resizeRight;
    } else {
      mode = _TlDragMode.move;
    }
    setState(() {
      _tlDragTrack = tr;
      _tlDragPattern = p;
      _tlDragStartX = d.globalPosition.dx;
      _tlDragOrigStart = p.start;
      _tlDragOrigLen = p.len;
      _tlDragMode = mode;
    });
  }

  void _tlDragUpdate(DragUpdateDetails d) {
    if (_tlDragPattern == null) return;
    final dx = d.globalPosition.dx - _tlDragStartX;
    final barDelta = (dx / kBarWidth).round();
    setState(() {
      switch (_tlDragMode) {
        case _TlDragMode.move:
          _tlDragPattern!.start = max(0, _tlDragOrigStart + barDelta);
        case _TlDragMode.resizeLeft:
          final newStart = max(0, _tlDragOrigStart + barDelta);
          final newLen = _tlDragOrigLen - (newStart - _tlDragOrigStart);
          if (newLen >= 1) {
            _tlDragPattern!.start = newStart;
            _tlDragPattern!.len = newLen;
          }
        case _TlDragMode.resizeRight:
          final newLen = max(1, _tlDragOrigLen + barDelta);
          _tlDragPattern!.len = newLen;
      }
    });
  }

  void _tlDragEnd() {
    if (_tlDragPattern != null) {
      _log('moved pattern "${_tlDragPattern!.label}" to bar ${_tlDragPattern!.start} len ${_tlDragPattern!.len}');
    }
    setState(() {
      _tlDragTrack = null;
      _tlDragPattern = null;
    });
  }

  Widget _patternDots(int seed, Color color) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _DotPainter(seed: seed, color: color),
      ),
    );
  }

  Widget _patternMarks(Pattern p, Color color) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _MarkPainter(notes: p.notes, color: color, len: p.len),
      ),
    );
  }

  Widget _knob(double size, Color color) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KnobPainter(color: color)),
    );
  }

  Widget _miniToggle(
      String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 14,
        height: 12,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: active ? color : Colors.transparent,
          border: Border.all(
              color: active ? color : AppColors.line, width: 1),
        ),
        alignment: Alignment.center,
        child: AppText.ui(label,
            size: 8,
            weight: FontWeight.w700,
            color: active ? AppColors.bgDeep : AppColors.textFaint),
      ),
    );
  }

  // =========================================================================
  // PIANO ROLL TAB
  // =========================================================================
  Widget _buildPianoRollTab() {
    final tr = _openTrack;
    final p = _openPattern;
    final intervals = scales[_scaleName] ?? scales['Major']!;
    final degrees = intervals.length;

    // chord labels per topmost note
    final chordLabelByNote = <(int, int), String>{};
    if (p != null) {
      final groups = <int, List<NoteEvent>>{};
      for (final n in p.notes) {
        groups.putIfAbsent(n.startCol, () => []).add(n);
      }
      for (final g in groups.values) {
        if (g.length >= 2) {
          final top = g.reduce((a, b) =>
              octNToMidi(a.oct, a.n) > octNToMidi(b.oct, b.n) ? a : b);
          final pcs = g.map((e) => octNToMidi(e.oct, e.n)).toList();
          final label = detectChord(pcs);
          if (label != null) chordLabelByNote[(top.oct, top.n)] = label;
        }
      }
    }

    final highlight = <(int, int)>{};
    if (_previewedDegree != null) {
      for (final pc in chordPitches(_rootNoteIndex, _scaleName, _previewedDegree!)) {
        highlight.add((pc.oct, pc.n));
      }
    }

    // rows top-to-bottom: octaves [6,5,4], within octave 11..0
    final rows = <(int, int)>[];
    for (final oct in const [6, 5, 4]) {
      for (int n = 11; n >= 0; n--) {
        if (!_scaleOnly || isInScale(oct, n, _rootNoteIndex, _scaleName)) {
          rows.add((oct, n));
        }
      }
    }

    return Column(
      children: [
        _buildRollContextHeader(tr, p),
        _buildScaleBar(),
        _buildChordStrip(degrees),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // sticky key column
                Column(
                  children: [
                    for (final r in rows) _buildKeyCell(r.$1, r.$2),
                  ],
                ),
                // scrollable grid
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in rows)
                        _buildRollRow(r.$1, r.$2, p, chordLabelByNote,
                            highlight, intervals),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Virtual piano
        _buildVirtualPiano(),
      ],
    );
  }

  Widget _buildRollContextHeader(Track? tr, Pattern? p) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.textDim),
            onPressed: () => setState(() => _activeTab = 0),
          ),
          if (tr != null)
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: tr.color),
            ),
          const SizedBox(width: 8),
          AppText.mono(tr?.name ?? '—',
              size: 13, weight: FontWeight.w700, color: AppColors.text),
          const SizedBox(width: 8),
          AppText.mono('— ${p?.label ?? '—'}',
              size: 11, color: AppColors.textFaint),
          const Spacer(),
          // Record-to-roll toggle
          GestureDetector(
            onTap: () => setState(() {
              _recordingPiano = !_recordingPiano;
              if (_recordingPiano) _pianoRecCol = 0;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: _recordingPiano ? AppColors.red : Colors.transparent,
                border: Border.all(
                    color: _recordingPiano ? AppColors.red : AppColors.line),
              ),
              child: AppText.ui(_recordingPiano ? 'REC' : 'REC',
                  size: 9,
                  weight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _recordingPiano ? Colors.white : AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }

  String _snapLabel(int div) {
    const labels = {1: '1/32', 2: '1/16', 4: '1/8', 8: '1/4', 16: '1/2', 32: '1'};
    return labels[div] ?? '1/16';
  }

  // =========================================================================
  // VIRTUAL PIANO
  // =========================================================================
  Widget _buildVirtualPiano() {
    const noteNames = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
    final octaves = [4, 5];
    final totalKeys = octaves.length * 12;
    const keyW = 32.0;
    const whiteKeyH = 64.0;
    const blackKeyH = 40.0;
    final blackIndices = {1, 3, 6, 8, 10};

    final whiteKeys = <Widget>[];
    final blackKeys = <Widget>[];
    for (int i = 0; i < totalKeys; i++) {
      final oct = octaves[i ~/ 12];
      final n = i % 12;
      if (!blackIndices.contains(n)) {
        whiteKeys.add(Positioned(
          left: i * keyW,
          width: keyW - 1,
          top: 0,
          height: whiteKeyH,
          child: _pianoWhiteKey(oct, n, noteNames[n]),
        ));
      } else {
        blackKeys.add(Positioned(
          left: i * keyW - keyW * 0.3,
          width: keyW * 0.65,
          top: 0,
          height: blackKeyH,
          child: _pianoBlackKey(oct, n),
        ));
      }
    }

    return Container(
      height: whiteKeyH + 18,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.lineSoft)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalKeys * keyW,
          child: Stack(children: [...whiteKeys, ...blackKeys]),
        ),
      ),
    );
  }

  Widget _pianoWhiteKey(int oct, int n, String label) {
    final midi = octNToMidi(oct, n);
    final held = _heldPianoKeys.contains(midi);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pianoKeyDown(oct, n),
      onTapUp: (_) => _pianoKeyUp(oct, n),
      onTapCancel: () => _pianoKeyUp(oct, n),
      child: Container(
        decoration: BoxDecoration(
          color: held ? AppColors.teal : Colors.white,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(3),
            bottomRight: Radius.circular(3),
          ),
          border: Border.all(color: AppColors.lineSoft),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 4),
        child: AppText.mono(label,
            size: 7, color: held ? AppColors.bgDeep : AppColors.textFaint),
      ),
    );
  }

  Widget _pianoBlackKey(int oct, int n) {
    final midi = octNToMidi(oct, n);
    final held = _heldPianoKeys.contains(midi);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pianoKeyDown(oct, n),
      onTapUp: (_) => _pianoKeyUp(oct, n),
      onTapCancel: () => _pianoKeyUp(oct, n),
      child: Container(
        decoration: BoxDecoration(
          color: held ? AppColors.teal : AppColors.bgDeep,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(2),
            bottomRight: Radius.circular(2),
          ),
          border: Border.all(color: AppColors.panel, width: 0.5),
        ),
      ),
    );
  }

  void _pianoKeyDown(int oct, int n) {
    final midi = octNToMidi(oct, n);
    setState(() => _heldPianoKeys.add(midi));
    // Play preview
    if (!kIsWeb && _isEngineReady) {
      _audioBridge?.playPreviewNote(_openTrackIndex, midi, 0.85);
    }
    // Record note into pattern
    if (_recordingPiano) {
      _ensureOpenPattern();
      final len = _snapDiv; // note length = one snap division
      final col = _snapToGrid(_pianoRecCol);
      _openPattern!.notes.add(NoteEvent(
        oct: oct, n: n, startCol: col, len: len, chordRoot: false));
      _pianoRecCol = col + len;
      _log('piano rec: MIDI $midi at col $col');
    }
  }

  void _pianoKeyUp(int oct, int n) {
    final midi = octNToMidi(oct, n);
    setState(() => _heldPianoKeys.remove(midi));
    // Stop preview
    if (!kIsWeb && _isEngineReady) {
      _audioBridge?.playPreviewNote(_openTrackIndex, midi, 0.0);
    }
  }

  Widget _buildScaleBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Row(
        children: [
          _scaleDropdown(
            value: _rootNoteIndex,
            items: List.generate(12, (i) => MapEntry(i, noteNames[i])),
            onChanged: (v) => setState(() => _rootNoteIndex = v ?? 0),
          ),
          const SizedBox(width: 8),
          _scaleDropdown(
            value: _scaleName,
            items: scales.keys.map((k) => MapEntry(k, k)).toList(),
            onChanged: (v) => setState(() => _scaleName = v ?? 'Major'),
          ),
          const SizedBox(width: 8),
          _scaleDropdown(
            value: _snapDiv,
            items: [1, 2, 4, 8, 16, 32]
                .map((d) => MapEntry(d, _snapLabel(d)))
                .toList(),
            onChanged: (v) => setState(() => _snapDiv = v ?? 2),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _scaleOnly = !_scaleOnly),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: _scaleOnly ? AppColors.tealDim : Colors.transparent,
                border: Border.all(
                    color: _scaleOnly ? AppColors.teal : AppColors.line),
              ),
              child: AppText.ui(_scaleOnly ? 'SCALE' : 'ALL',
                  size: 9,
                  weight: FontWeight.w600,
                  letterSpacing: 1,
                  color: _scaleOnly ? AppColors.teal : AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scaleDropdown<T>(
      {required T value,
      required List<MapEntry<T, String>> items,
      required ValueChanged<T?> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox(),
        icon: const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textDim),
        items: items
            .map((e) => DropdownMenuItem<T>(
                  value: e.key,
                  child: AppText.ui(e.value,
                      size: 12, color: AppColors.text),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildChordStrip(int degrees) {
    final intervals = scales[_scaleName] ?? scales['Major']!;
    final rootAbs = 5 * 12 + _rootNoteIndex; // C4 = MIDI 60

    return Container(
      height: 76,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: degrees,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final offsets = triadForDegree(intervals, i);
                final quality = qualityLabel(offsets[1], offsets[2]);
                final chordRootMidi = rootAbs + offsets[0];
                final rootName = noteNames[((chordRootMidi % 12) + 12) % 12];
                final selected = _previewedDegree == i;
                final isTonic = i == 0;
                return GestureDetector(
                  onTap: () => _onPadTap(i),
                  child: Container(
                    width: 48,
                    height: 36,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: AppColors.panelRaised,
                      border: Border.all(
                        color: selected
                            ? AppColors.teal
                            : isTonic
                                ? AppColors.amber
                                : AppColors.line,
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: selected
                          ? [BoxShadow(color: AppColors.teal.withOpacity(0.4), blurRadius: 8)]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppText.mono('${i + 1}',
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppColors.text),
                        AppText.mono(quality == '—' ? '·' : quality,
                            size: 7.5, color: AppColors.textDim),
                        AppText.ui(
                            '$rootName ${quality == '—' ? '' : quality}',
                            size: 7.5,
                            color: AppColors.amber),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          AppText.ui(
              'Tap to preview a chord’s rows · double-tap to add it.',
              size: 9, color: AppColors.textFaint),
        ],
      ),
    );
  }

  Widget _buildKeyCell(int oct, int n) {
    final inScale = isInScale(oct, n, _rootNoteIndex, _scaleName);
    final deg = scaleDegree(n, _rootNoteIndex, _scaleName);
    final isRoot = inScale && deg == 1;
    final bg = isRoot
        ? AppColors.amberDim
        : inScale
            ? AppColors.tealDim
            : AppColors.panel;
    return Container(
      width: kRollKeyWidth,
      height: kRollRowHeight,
      decoration: BoxDecoration(
        color: bg,
        border: const Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        children: [
          AppText.mono(noteLabel(oct, n),
              size: 8.5, color: AppColors.textFaint),
          if (inScale) ...[
            const SizedBox(width: 5),
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRoot ? AppColors.amber : AppColors.teal,
              ),
              alignment: Alignment.center,
              child: AppText.mono(deg.toString(),
                  size: 9,
                  weight: FontWeight.w700,
                  color: AppColors.bgDeep),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRollRow(
      int oct,
      int n,
      Pattern? p,
      Map<(int, int), String> chordLabelByNote,
      Set<(int, int)> highlight,
      List<int> intervals) {
    final gridW = _snapColumns * kColWidth;
    final notes = p?.notes.where((e) => e.oct == oct && e.n == n).toList() ?? [];
    final tinted = highlight.contains((oct, n));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _rollDown(oct, n, d.localPosition.dx),
      onTap: () => _rollTap(oct, n),
      onPanStart: (d) => _rollPanStart(oct, n, d.localPosition.dx),
      onPanUpdate: (d) => _rollPanUpdate(oct, n, d.localPosition.dx),
      onPanEnd: (d) => _rollPanEnd(),
      child: Container(
        width: gridW,
        height: kRollRowHeight,
        decoration: BoxDecoration(
          border: const Border(bottom: BorderSide(color: AppColors.lineSoft)),
          color: tinted ? AppColors.amber.withOpacity(0.12) : null,
        ),
        child: Stack(
          children: [
            // column lines
            Row(
              children: List.generate(_snapColumns, (c) {
                return Container(
                  width: kColWidth,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: c % (4 * (_snapDiv > 0 ? 1 : 1)) == 0
                            ? AppColors.line
                            : AppColors.lineSoft,
                      ),
                    ),
                  ),
                );
              }),
            ),
            // note blocks
            for (final note in notes)
              Positioned(
                left: note.startCol * kColWidth,
                width: note.len * kColWidth - 3,
                top: 2,
                bottom: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: note.chordRoot
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            // chord label above topmost note
            if (chordLabelByNote.containsKey((oct, n)))
              Positioned(
                left: notes.first.startCol * kColWidth + 2,
                top: -2,
                child: AppText.mono(chordLabelByNote[(oct, n)]!,
                    size: 8, weight: FontWeight.w700, color: AppColors.amber),
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // MIXER TAB
  // =========================================================================
  Widget _buildMixerTab() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _tracks.length; i++) _buildStrip(_tracks[i], i),
          _buildMasterStrip(),
        ],
      ),
    );
  }

  Widget _buildStrip(Track tr, int i) {
    return Container(
      width: 58,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tr.color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          AppText.ui(tr.name,
              size: 9,
              weight: FontWeight.w700,
              color: tr.color,
              letterSpacing: 0.5),
          const SizedBox(height: 8),
          _knob(26, tr.color),
          const SizedBox(height: 10),
          _Fader(
            value: tr.vol,
            color: AppColors.teal,
            onChanged: (v) => _setTrackVol(i, v),
          ),
          const SizedBox(height: 6),
          AppText.mono(_dB(tr.vol), size: 8, color: AppColors.textFaint),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _miniToggle('M', tr.mute, AppColors.red, () => _toggleMute(i)),
              const SizedBox(width: 4),
              _miniToggle('S', tr.solo, AppColors.amber, () => _toggleSolo(i)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterStrip() {
    return Container(
      width: 58,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.amberDim),
      ),
      child: Column(
        children: [
          AppText.ui('MASTER',
              size: 9, weight: FontWeight.w700, color: AppColors.amber),
          const SizedBox(height: 8),
          _knob(26, AppColors.amber),
          const SizedBox(height: 10),
          _Fader(
            value: _masterVolume,
            color: AppColors.amber,
            onChanged: (v) {
              setState(() => _masterVolume = v);
              _audioBridge?.setVolume(v);
            },
          ),
          const SizedBox(height: 6),
          AppText.mono(_dB(_masterVolume), size: 8, color: AppColors.textFaint),
        ],
      ),
    );
  }

  String _dB(double v) {
    if (v <= 0.001) return '-inf';
    final db = 20 * log(v) / ln10;
    return '${db.toStringAsFixed(1)}';
  }

  // =========================================================================
  // FX TAB
  // =========================================================================
  final Set<String> _activeFx = {
    'Reverb',
    'Compressor',
  };
  final List<String> _samples = [
    'Kick 808',
    'Snare Vinyl',
    'Hi-Hat Closed',
    'Sub Bass',
    'Vinyl Crackle',
    'Vocal Chop A',
    'Brass Stab',
    'Pad Sweep',
  ];

  Widget _buildFxTab() {
    const fxList = [
      'Reverb',
      'Delay',
      'Chorus',
      'Compressor',
      'Filter',
      'Distortion',
      'Phaser',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.ui('MASTER FX CHAIN',
              size: 11, letterSpacing: 2, color: AppColors.textDim),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fxList
                .map((fx) => _fxChip(fx))
                .toList(),
          ),
          const SizedBox(height: 20),
          AppText.ui('SAMPLE LIBRARY',
              size: 11, letterSpacing: 2, color: AppColors.textDim),
          const SizedBox(height: 10),
          ..._samples.map((s) => _sampleRow(s)).toList(),
        ],
      ),
    );
  }

  Widget _fxChip(String fx) {
    final active = _activeFx.contains(fx);
    return GestureDetector(
      onTap: () => setState(() {
        if (active) _activeFx.remove(fx);
        else _activeFx.add(fx);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: active ? AppColors.tealDim : AppColors.panel,
          border: Border.all(
              color: active ? AppColors.teal : AppColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.check_circle : Icons.circle_outlined,
                size: 14, color: active ? AppColors.teal : AppColors.textFaint),
            const SizedBox(width: 6),
            AppText.ui(fx,
                size: 11,
                color: active ? AppColors.teal : AppColors.textDim),
          ],
        ),
      ),
    );
  }

  Widget _sampleRow(String s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.audio_file_outlined,
              size: 16, color: AppColors.textDim),
          const SizedBox(width: 10),
          AppText.ui(s, size: 12, color: AppColors.text),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.play_arrow,
                size: 16, color: AppColors.teal),
            onPressed: () => _log('sample preview: $s (no engine mapping)'),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Debug console
  // =========================================================================
  Widget _buildDebugPanel() {
    final dot = _sfLoaded ? AppColors.teal : AppColors.red;
    return Positioned.fill(
      child: Column(
        children: [
          const Spacer(),
          Container(
            height: 260,
            color: Colors.black.withOpacity(0.94),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.teal)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: dot),
                      const SizedBox(width: 6),
                      Expanded(
                        child: AppText.ui(
                            'SF: ${_sfLoaded ? "LOADED" : "NOT LOADED"} · $_engineStatus',
                            size: 11,
                            color: AppColors.textDim),
                      ),
                      _dbgBtn('DIAGNOSE', _diagnose),
                      _dbgBtn('RE-INIT', _reinit),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                        onPressed: () => setState(() => _showDebug = false),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => AppText.mono(_logs[i],
                        size: 9, color: const Color(0xFF9EFFB0)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dbgBtn(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onTap,
          child: AppText.ui(label,
              size: 10, weight: FontWeight.w600, color: AppColors.teal),
        ),
      );

  void _diagnose() {
    _log('--- DIAGNOSE ---');
    _log('engineReady=$_isEngineReady status=$_engineStatus');
    _log('sfLoaded=$_sfLoaded path=${_sfPath.isEmpty ? "<none>" : _sfPath}');
    _log('isPlaying=$_isPlaying bpm=$_bpm');
  }

  void _reinit() {
    _log('re-init');
    _initAudioEngine();
  }
}

// =========================================================================
// Custom painters / widgets
// =========================================================================
class _PlayheadFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.amber;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(8, 0);
    path.lineTo(0, 8);
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _KnobPainter extends CustomPainter {
  final Color color;
  _KnobPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, size.width / 2 - 1,
        Paint()..color = AppColors.panelRaised);
    canvas.drawCircle(c, size.width / 2 - 1,
        Paint()..color = AppColors.line..style = PaintingStyle.stroke);
    final r = size.width / 2 - 2;
    canvas.drawLine(c, Offset(c.dx, c.dy - r),
        Paint()..color = color ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _DotPainter extends CustomPainter {
  final int seed;
  final Color color;
  _DotPainter({required this.seed, required this.color});
  double _r(int i) =>
      ((seed * 9301 + i * 49297) % 233280) / 233280;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withOpacity(0.5);
    for (int i = 0; i < 14; i++) {
      final x = _r(i) * size.width;
      final y = _r(i + 99) * size.height;
      canvas.drawCircle(Offset(x, y), 1.4, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _MarkPainter extends CustomPainter {
  final List<NoteEvent> notes;
  final Color color;
  final int len;
  _MarkPainter({required this.notes, required this.color, required this.len});
  double _r(int i) => ((i * 7919 + 31) % 233280) / 233280;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.bgDeep.withOpacity(0.8);
    for (final n in notes) {
      for (int k = 0; k < 3; k++) {
        final x = (n.startCol + _r(n.startCol + k) * n.len) / len * size.width;
        final y = 4 + _r(n.startCol * 3 + k) * (size.height - 8);
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Fader extends StatefulWidget {
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  const _Fader(
      {required this.value, required this.color, required this.onChanged});

  @override
  State<_Fader> createState() => _FaderState();
}

class _FaderState extends State<_Fader> {
  late double _v;
  @override
  void initState() {
    super.initState();
    _v = widget.value;
  }

  @override
  void didUpdateWidget(covariant _Fader old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    const h = 220.0;
    const w = 22.0;
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        final dy = d.delta.dy;
        setState(() {
          _v = (_v - dy / h).clamp(0.0, 1.0);
        });
        widget.onChanged(_v);
      },
      child: SizedBox(
        height: h,
        width: w,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: 6,
              height: h,
              decoration: BoxDecoration(
                color: AppColors.panelRaised,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 6,
                height: h * _v,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Positioned(
              bottom: (h - 14) * _v,
              child: Container(
                width: w,
                height: 14,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
