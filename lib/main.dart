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
      home: const DefaultTabController(
        length: 2,
        child: DawWorkspace(),
      ),
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
  Future<void> _initAudioEngine() async {
    try {
      await Permission.microphone.request();
      await Permission.storage.request();

      _audioBridge = AudioEngineBridge();
      bool success = _audioBridge?.initialize() ?? false;
      debugPrint("SriDAW: initialize() returned: $success");

      if (success) {
        try {
          const platform = MethodChannel('com.ram.sridaw/assets');
          final String? sfPath = await platform.invokeMethod('extractSoundFont');
          if (sfPath != null) {
            bool sfLoaded = _audioBridge?.loadSoundFont(sfPath) ?? false;
            debugPrint("SriDAW: SoundFont loaded: $sfLoaded ($sfPath)");
            debugPrint("SriDAW: isSoundFontLoaded=${_audioBridge?.isSoundFontLoaded()}");
          }
        } catch (e) {
          debugPrint("SriDAW: Failed to extract/load SoundFont: $e");
        }

        _audioBridge?.setVolume(_masterVolume);
        for (int i = 0; i < _tracks.length; i++) {
          final t = _tracks[i];
          _audioBridge?.setTrackVolume(i, t.vol);
          _audioBridge?.setTrackInstrument(i, t.instrument);
          _audioBridge?.setTrackMute(i, t.mute);
        }
        setState(() => _isEngineReady = true);
        debugPrint("SriDAW: Engine ready");
      }
    } catch (e) {
      debugPrint("SriDAW: Engine init failed: $e");
    }
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
    } else {
      _audioBridge?.playDemo(false);
      _audioBridge?.setLoopDuration(2.0);
    }
  }

  /// Push the full arrangement (all tracks, all placed clips) into the engine.
  void _syncArrangementToEngine() {
    if (_audioBridge == null) return;
    _audioBridge!.clearMidiSequence();
    final double sd = _stepDuration;
    for (int t = 0; t < _tracks.length; t++) {
      final tr = _tracks[t];
      for (final bar in tr.clips) {
        for (final n in tr.notes) {
          final double start = (bar * kStepsPerBar + n.startStep) * sd;
          final double dur = n.lengthSteps * sd;
          _audioBridge!.addMidiNote(t, n.note, start, dur, 0.85);
        }
      }
    }
    _audioBridge!.setLoopDuration(kArrangementBars * kStepsPerBar * sd);
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
  }

  void _previewNote(int note, double velocity) {
    if (_audioBridge == null || !_isEngineReady) return;
    if (velocity > 0) {
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
            icon: const Icon(Icons.folder_open_outlined, size: 20),
            tooltip: 'Load MIDI',
            onPressed: _pickMidiFile,
          ),
        ],
        bottom: const TabBar(
          indicatorColor: Color(0xFF4ADE80),
          labelStyle: TextStyle(fontWeight: FontWeight.w500, letterSpacing: 1),
          tabs: [
            Tab(text: 'PHRASES'),
            Tab(text: 'TRACKS'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              children: [
                _buildPhrasesView(),
                _buildTracksView(),
              ],
            ),
          ),
          _buildTransport(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PHRASES TAB — vertical piano roll editor for the selected track
  // ---------------------------------------------------------------------------
  Widget _buildPhrasesView() {
    final tr = _tracks[_selectedTrack];
    return Column(
      children: [
        _buildPhraseToolbar(tr),
        Expanded(
          child: PianoRollWidget(
            notes: tr.notes,
            color: tr.color,
            playheadStep: _playheadStep,
            onToggleNote: _toggleNote,
            onPreviewNote: _previewNote,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Tap a key cell to paint a note · tap again to erase · drag on a key to preview',
            style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildPhraseToolbar(Track tr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Track selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tr.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tr.color.withOpacity(0.5)),
            ),
            child: DropdownButton<int>(
              value: _selectedTrack,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              items: List.generate(_tracks.length, (i) {
                return DropdownMenuItem<int>(
                  value: i,
                  child: Text(_tracks[i].name,
                      style: TextStyle(color: _tracks[i].color, fontWeight: FontWeight.w600)),
                );
              }),
              onChanged: (v) => setState(() => _selectedTrack = v ?? 0),
            ),
          ),
          // Instrument selector
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
          // Note length
          Row(
            children: [
              const Text('LEN', style: TextStyle(color: Color(0xFF8A8A93), fontSize: 11)),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _noteLength,
                underline: const SizedBox(),
                items: [1, 2, 4, 8].map((l) {
                  return DropdownMenuItem<int>(value: l, child: Text('$l', style: const TextStyle(fontSize: 13)));
                }).toList(),
                onChanged: (v) => setState(() => _noteLength = v ?? 2),
              ),
            ],
          ),
          // Play phrase
          OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('PLAY PHRASE'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4ADE80),
              side: const BorderSide(color: Color(0xFF4ADE80)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: _playSelectedPhrase,
          ),
          // Clear
          TextButton(
            child: const Text('CLEAR', style: TextStyle(color: Color(0xFF8A8A93))),
            onPressed: () => setState(() => tr.notes.clear()),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRACKS TAB — mixer strips + arrangement lanes (1st track shows phrases)
  // ---------------------------------------------------------------------------
  Widget _buildTracksView() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildTrackCard(i),
    );
  }

  Widget _buildTrackCard(int index) {
    final tr = _tracks[index];
    final bool isFirst = index == 0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15151A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tr.color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
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
          if (isFirst)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 10),
              child: Text('↑ Track 1 shows its phrases on the lane above — tap a cell to place/remove a phrase.',
                  style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 10)),
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
  // Transport (bottom bar)
  // ---------------------------------------------------------------------------
  Widget _buildTransport() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E),
        border: Border(top: BorderSide(color: Colors.white12)),
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Piano keyboard (vertical, aligned with grid rows)
        SizedBox(
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
        ),
        // Scrollable grid
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
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
              ),
            ),
          ),
        ),
      ],
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
