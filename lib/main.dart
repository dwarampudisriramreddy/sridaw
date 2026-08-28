import 'package:flutter/material.dart';
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

class DawApp extends StatelessWidget {
  const DawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sri DAW',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          surface: Color(0xFF1E1E1E),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 8,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
          activeTrackColor: const Color(0xFF00E676),
          inactiveTrackColor: Colors.black54,
          thumbColor: Colors.grey.shade300,
        ),
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
  String _loadedMidiName = "Demo C Major Chord";

  final List<Map<String, dynamic>> _channels = [
    {"name": "Kick", "vol": 0.8, "pan": 0.0, "color": Colors.redAccent, "mute": false, "solo": false, "peak": 0.0},
    {"name": "Snare", "vol": 0.75, "pan": 0.1, "color": Colors.orangeAccent, "mute": false, "solo": false, "peak": 0.0},
    {"name": "HiHat", "vol": 0.6, "pan": -0.3, "color": Colors.yellowAccent, "mute": false, "solo": false, "peak": 0.0},
    {"name": "Bass", "vol": 0.9, "pan": 0.0, "color": Colors.blueAccent, "mute": false, "solo": false, "peak": 0.0},
    {"name": "Synth", "vol": 0.65, "pan": 0.4, "color": Colors.purpleAccent, "mute": false, "solo": false, "peak": 0.0},
    {"name": "Vox", "vol": 0.85, "pan": 0.0, "color": Colors.greenAccent, "mute": false, "solo": false, "peak": 0.0},
  ];

  int _activeStepIndex = 0;
  bool _isEngineReady = false;

  @override
  void initState() {
    super.initState();
    
    // We defer initialization to avoid native Android crashes on startup
    // before permissions are granted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAudioEngine();
    });

    _meterTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (_isPlaying && _audioBridge != null && _isEngineReady) {
        // Fetch Peak Levels and Playhead Time
        double playTime = _audioBridge!.getPlayheadTime();
        double stepDuration = (60.0 / _bpm) / 4.0;
        int currentStep = (playTime / stepDuration).floor() % 16;
        
        setState(() {
          _activeStepIndex = currentStep;
          for (int i = 0; i < _channels.length; i++) {
            var channel = _channels[i];
            if (!channel["mute"]) {
              channel["peak"] = _audioBridge!.getTrackPeakLevel(i);
            } else {
              channel["peak"] = 0.0;
            }
          }
        });
      } else if (!_isPlaying && _channels[0]["peak"] > 0) {
        setState(() {
          for (var channel in _channels) {
            channel["peak"] = 0.0;
          }
        });
      }
    });
  }

  Future<void> _initAudioEngine() async {
    try {
      // Request microphone permission (needed by JUCE AudioDeviceManager even for output)
      debugPrint("SriDAW: requesting microphone permission...");
      await Permission.microphone.request();
      debugPrint("SriDAW: microphone permission done");
      // Request storage permission to load files
      debugPrint("SriDAW: requesting storage permission...");
      await Permission.storage.request();
      debugPrint("SriDAW: storage permission done");

      debugPrint("SriDAW: opening AudioEngineBridge...");
      _audioBridge = AudioEngineBridge();
      debugPrint("SriDAW: bridge opened, initializing JUCE engine...");
      bool success = _audioBridge?.initialize() ?? false;
      debugPrint("SriDAW: initialize() returned: $success");

      if (success) {
        _audioBridge?.setVolume(_masterVolume);
        for (int i = 0; i < _channels.length; i++) {
          _audioBridge?.setTrackVolume(i, _channels[i]["vol"]);
          _audioBridge?.setTrackMute(i, _channels[i]["mute"]);
        }
        setState(() {
          _isEngineReady = true;
        });
        debugPrint("SriDAW: JUCE Engine loaded successfully!");
      } else {
        debugPrint("SriDAW: JUCE Engine failed to initialize internally!");
      }
    } catch (e) {
      debugPrint("SriDAW: JUCE Engine failed to load library: $e");
      debugPrint("SriDAW: stack: ${StackTrace.current}");
    }
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _audioBridge?.shutdown();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
      _audioBridge?.playDemo(_isPlaying);
    });
  }

  void _onTrackVolumeChanged(int index, double val) {
    setState(() {
      _channels[index]["vol"] = val;
      _audioBridge?.setTrackVolume(index, val);
    });
  }

  void _onTrackMuteToggled(int index) {
    setState(() {
      bool newMute = !_channels[index]["mute"];
      _channels[index]["mute"] = newMute;
      _audioBridge?.setTrackMute(index, newMute);
    });
  }

  Future<void> _pickMidiFile() async {
    List<PlatformFile>? files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mid', 'midi'],
    );

    if (files != null && files.isNotEmpty) {
      final String? path = files.single.path;
      if (path != null) {
        bool success = _audioBridge?.loadMidiFile(path) ?? false;
        if (success) {
          setState(() {
            _loadedMidiName = files.single.name;
          });
          
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded MIDI: $_loadedMidiName', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.green),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load MIDI file.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SRI DAW', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Seq: $_loadedMidiName', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        bottom: const TabBar(
          indicatorColor: Color(0xFF00E676),
          tabs: [
            Tab(icon: Icon(Icons.horizontal_split), text: "ARRANGEMENT"),
            Tab(icon: Icon(Icons.tune), text: "MIXER"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music, color: Color(0xFF00E676)), 
            tooltip: "Load MIDI File",
            onPressed: _pickMidiFile,
          ),
          IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // Main View Area (Tabs)
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildArrangementView(),
                _buildMixerView(),
              ],
            ),
          ),
          // Master Section & Transport (Always visible at bottom)
          _buildMasterSection(),
        ],
      ),
    );
  }

  // Sequencer Grid: [TrackIndex][StepIndex] -> true/false
  final List<List<bool>> _stepGrid = List.generate(6, (_) => List.filled(16, false));
  int _bpm = 120;

  void _syncSequencerToEngine() {
    if (_audioBridge == null) return;
    
    _audioBridge!.clearMidiSequence();
    
    // Calculate step duration based on BPM (16th notes = 4 steps per beat)
    double beatDuration = 60.0 / _bpm;
    double stepDuration = beatDuration / 4.0;
    
    // Set total loop duration (16 steps = 4 beats = 1 bar)
    _audioBridge!.setLoopDuration(beatDuration * 4.0);
    
    for (int t = 0; t < _stepGrid.length; t++) {
      for (int s = 0; s < 16; s++) {
        if (_stepGrid[t][s]) {
          int noteNumber = 60 + (t * 2); 
          _audioBridge!.addMidiNote(noteNumber, s * stepDuration, stepDuration, 0.8);
        }
      }
    }
  }

  Widget _buildArrangementView() {
    return Container(
      color: const Color(0xFF141414),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("16-STEP SEQUENCER", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                
                // BPM Control
                Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.white54, size: 16),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _bpm,
                      dropdownColor: const Color(0xFF1A1A1A),
                      underline: const SizedBox(),
                      items: [80, 100, 120, 140, 160].map((int val) {
                        return DropdownMenuItem<int>(
                          value: val,
                          child: Text("$val BPM", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _bpm = val;
                          });
                          _syncSequencerToEngine(); // auto sync on change
                        }
                      },
                    ),
                  ],
                ),

                ElevatedButton.icon(
                  icon: const Icon(Icons.sync),
                  label: const Text("SYNC"),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
                  onPressed: () {
                    _syncSequencerToEngine();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sequencer Synced!')));
                  },
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _channels.length,
              itemBuilder: (context, index) {
                var channel = _channels[index];
                return Container(
                  height: 60,
                  margin: const EdgeInsets.only(bottom: 2),
                  color: const Color(0xFF222222),
                  child: Row(
                    children: [
                      // Track Header
                      Container(
                        width: 100,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          border: Border(right: BorderSide(color: channel["color"], width: 4)),
                        ),
                        child: Text(channel["name"], style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      // Interactive 16-Step Grid
                      Expanded(
                        child: Row(
                          children: List.generate(16, (stepIndex) {
                            bool isActive = _stepGrid[index][stepIndex];
                            bool isPlayingNow = _isPlaying && (stepIndex == _activeStepIndex);
                            
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _stepGrid[index][stepIndex] = !isActive;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    color: isActive 
                                        ? (isPlayingNow ? Colors.white : channel["color"]) 
                                        : (isPlayingNow ? channel["color"].withValues(alpha: 0.3) : const Color(0xFF1A1A1A)),
                                    border: Border.all(
                                      color: isPlayingNow ? Colors.white : Colors.white.withValues(alpha: 0.05),
                                      width: isPlayingNow ? 1.5 : 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: isPlayingNow ? [BoxShadow(color: channel["color"], blurRadius: 4)] : [],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMixerView() {
    return Container(
      color: const Color(0xFF181818),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        itemCount: _channels.length,
        itemBuilder: (context, index) {
          return _buildChannelStrip(index);
        },
      ),
    );
  }

  Widget _buildChannelStrip(int index) {
    var channel = _channels[index];
    
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          // Track Name & Load Sample Button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: channel["color"].withOpacity(0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    channel["name"],
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, color: channel["color"], fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    List<PlatformFile>? files = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['wav', 'aiff', 'mp3'],
                    );
                    if (files != null && files.isNotEmpty) {
                      final String? samplePath = files.single.path;
                      if (samplePath != null) {
                        bool success = _audioBridge?.loadTrackSample(index, samplePath) ?? false;
                        if (success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Loaded sample into ${channel["name"]}')));
                        }
                      }
                    }
                  },
                )
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Pan Knob (Mock)
          Column(
            children: [
              const Text("PAN", style: TextStyle(fontSize: 10, color: Colors.white54)),
              const SizedBox(height: 4),
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                child: Center(
                  child: Transform.rotate(
                    angle: channel["pan"] * 1.5,
                    child: Container(width: 4, height: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Mute / Solo
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildToggleButton(
                "M", 
                channel["mute"], 
                Colors.red, 
                () => _onTrackMuteToggled(index)
              ),
              const SizedBox(width: 8),
              _buildToggleButton(
                "S", 
                channel["solo"], 
                Colors.yellow, 
                () => setState(() => channel["solo"] = !channel["solo"]) // Solo mock for now
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Fader and LED Meter Row
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Volume Fader
                RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: channel["vol"],
                    onChanged: (val) => _onTrackVolumeChanged(index, val),
                  ),
                ),
                // LED Peak Meter
                _buildLedMeter(channel["peak"]),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // DB Value
          Text(
            "${(channel["vol"] * 100).toInt()}",
            style: const TextStyle(fontFamily: 'monospace', color: Colors.white54),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLedMeter(double peak) {
    // Clamp peak between 0 and 1
    double displayPeak = peak.clamp(0.0, 1.0);
    
    return Container(
      width: 12,
      margin: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: displayPeak,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.green,
                Colors.yellow,
                Colors.red,
              ],
              stops: [0.6, 0.85, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isActive, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: isActive ? activeColor : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? activeColor : Colors.white24),
        ),
        alignment: Alignment.center,
        child: Text(
          label, 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.black : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _buildMasterSection() {
    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(top: BorderSide(color: Colors.white12, width: 2)),
      ),
      child: Row(
        children: [
          // Transport Controls
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(icon: const Icon(Icons.skip_previous, size: 36), onPressed: () {}),
                    FloatingActionButton(
                      backgroundColor: _isPlaying ? Colors.red : const Color(0xFF00E676),
                      onPressed: _togglePlayback,
                      child: Icon(_isPlaying ? Icons.stop : Icons.play_arrow, color: Colors.black, size: 36),
                    ),
                    IconButton(icon: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 36), onPressed: () {}),
                  ],
                ),
              ],
            ),
          ),
          
          Container(width: 2, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 16)),
          
          // Master Fader
          Expanded(
            flex: 1,
            child: Row(
              children: [
                const Text("MASTER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54)),
                const SizedBox(width: 8),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Slider(
                      value: _masterVolume,
                      activeColor: const Color(0xFF00E676),
                      onChanged: (val) {
                        setState(() {
                          _masterVolume = val;
                          _audioBridge?.setVolume(val);
                        });
                      },
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
}
