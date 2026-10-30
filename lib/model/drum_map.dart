/// General MIDI Drum Map (Channel 10). Standard GM percussion keys.
library;

import 'project.dart';

class DrumInfo {
  final int note;
  final String name;
  final String short;

  const DrumInfo(this.note, this.name, this.short);
}

const List<DrumInfo> gmDrumMap = [
  DrumInfo(35, 'Acoustic Bass Drum', 'KICK'),
  DrumInfo(36, 'Bass Drum 1', 'KICK'),
  DrumInfo(37, 'Side Stick', 'RIM'),
  DrumInfo(38, 'Acoustic Snare', 'SNARE'),
  DrumInfo(39, 'Hand Clap', 'CLAP'),
  DrumInfo(40, 'Electric Snare', 'SNARE'),
  DrumInfo(41, 'Low Floor Tom', 'TOM L'),
  DrumInfo(42, 'Closed Hi-Hat', 'CHH'),
  DrumInfo(43, 'High Floor Tom', 'TOM L'),
  DrumInfo(44, 'Pedal Hi-Hat', 'PHH'),
  DrumInfo(45, 'Low Tom', 'TOM M'),
  DrumInfo(46, 'Open Hi-Hat', 'OHH'),
  DrumInfo(47, 'Low-Mid Tom', 'TOM M'),
  DrumInfo(48, 'Hi-Mid Tom', 'TOM H'),
  DrumInfo(49, 'Crash Cymbal 1', 'CRASH'),
  DrumInfo(50, 'High Tom', 'TOM H'),
  DrumInfo(51, 'Ride Cymbal 1', 'RIDE'),
  DrumInfo(52, 'Chinese Cymbal', 'CHINA'),
  DrumInfo(53, 'Ride Bell', 'RIDE B'),
  DrumInfo(54, 'Tambourine', 'TAMB'),
  DrumInfo(55, 'Splash Cymbal', 'SPLASH'),
  DrumInfo(56, 'Cowbell', 'COW'),
  DrumInfo(57, 'Crash Cymbal 2', 'CRASH'),
  DrumInfo(58, 'Vibraslap', 'VIB'),
  DrumInfo(59, 'Ride Cymbal 2', 'RIDE'),
  DrumInfo(60, 'Hi Bongo', 'BONGO'),
  DrumInfo(61, 'Low Bongo', 'BONGO'),
  DrumInfo(62, 'Mute Hi Conga', 'CONGA'),
  DrumInfo(63, 'Open Hi Conga', 'CONGA'),
  DrumInfo(64, 'Low Conga', 'CONGA'),
  DrumInfo(65, 'High Timbale', 'TIMB'),
  DrumInfo(66, 'Low Timbale', 'TIMB'),
  DrumInfo(67, 'High Agogo', 'AGOGO'),
  DrumInfo(68, 'Low Agogo', 'AGOGO'),
  DrumInfo(69, 'Cabasa', 'CAB'),
  DrumInfo(70, 'Maracas', 'MARC'),
  DrumInfo(71, 'Short Whistle', 'WHIS'),
  DrumInfo(72, 'Long Whistle', 'WHIS'),
  DrumInfo(73, 'Short Guiro', 'GUIRO'),
  DrumInfo(74, 'Long Guiro', 'GUIRO'),
  DrumInfo(75, 'Claves', 'CLAVE'),
  DrumInfo(76, 'Hi Wood Block', 'BLOCK'),
  DrumInfo(77, 'Low Wood Block', 'BLOCK'),
  DrumInfo(78, 'Mute Cuica', 'CUICA'),
  DrumInfo(79, 'Open Cuica', 'CUICA'),
  DrumInfo(80, 'Mute Triangle', 'TRI'),
  DrumInfo(81, 'Open Triangle', 'TRI'),
];

String? drumNameFor(int note) {
  for (final d in gmDrumMap) {
    if (d.note == note) return d.name;
  }
  return null;
}

String? drumShortFor(int note) {
  for (final d in gmDrumMap) {
    if (d.note == note) return d.short;
  }
  return null;
}

bool isDrumTrack(Track track) {
  return track.type == TrackType.drum || track.channel == 9;
}

/// One row of the drum machine: a sound the player put on the machine. The
/// grid rows are pads, not pitches — [pitch] is only how the hit reaches the
/// sampler/synth (36 = kick, 38 = snare, …).
class DrumPad {
  final String name;
  final int pitch;

  const DrumPad(this.name, this.pitch);

  @override
  String toString() => '$name ($pitch)';
}

/// The kit the drum machine opens with.
const List<DrumPad> defaultDrumPads = [
  DrumPad('KICK', 36),
  DrumPad('SNARE', 38),
  DrumPad('CLAP', 39),
  DrumPad('HAT CLOSED', 42),
  DrumPad('HAT OPEN', 46),
  DrumPad('TOM LOW', 41),
  DrumPad('TOM MID', 45),
  DrumPad('TOM HIGH', 48),
  DrumPad('CRASH', 49),
  DrumPad('RIDE', 51),
];

/// The picker list: every GM percussion sound, in kit-friendly order.
const List<DrumPad> gmDrumPads = [
  DrumPad('BASS DRUM', 35),
  DrumPad('KICK', 36),
  DrumPad('SIDE STICK', 37),
  DrumPad('SNARE', 38),
  DrumPad('CLAP', 39),
  DrumPad('ELECTRIC SNARE', 40),
  DrumPad('RIM', 37),
  DrumPad('CLOSED HI-HAT', 42),
  DrumPad('PEDAL HI-HAT', 44),
  DrumPad('OPEN HI-HAT', 46),
  DrumPad('FLOOR TOM LOW', 41),
  DrumPad('FLOOR TOM HIGH', 43),
  DrumPad('LOW TOM', 45),
  DrumPad('LOW-MID TOM', 47),
  DrumPad('HI-MID TOM', 48),
  DrumPad('HIGH TOM', 50),
  DrumPad('CRASH', 49),
  DrumPad('RIDE', 51),
  DrumPad('CHINESE', 52),
  DrumPad('RIDE BELL', 53),
  DrumPad('TAMBORINE', 54),
  DrumPad('SPLASH', 55),
  DrumPad('COWBELL', 56),
  DrumPad('VIBRASLAP', 58),
  DrumPad('BONGO HIGH', 60),
  DrumPad('BONGO LOW', 61),
  DrumPad('CONGA MUTE', 62),
  DrumPad('CONGA OPEN', 63),
  DrumPad('CONGA LOW', 64),
  DrumPad('TIMBALE HIGH', 65),
  DrumPad('TIMBALE LOW', 66),
  DrumPad('AGOGO HIGH', 67),
  DrumPad('AGOGO LOW', 68),
  DrumPad('CABASA', 69),
  DrumPad('MARACAS', 70),
  DrumPad('WHISTLE SHORT', 71),
  DrumPad('WHISTLE LONG', 72),
  DrumPad('GUIRO SHORT', 73),
  DrumPad('GUIRO LONG', 74),
  DrumPad('CLAVES', 75),
  DrumPad('WOOD BLOCK HIGH', 76),
  DrumPad('WOOD BLOCK LOW', 77),
  DrumPad('CUICA MUTE', 78),
  DrumPad('CUICA OPEN', 79),
  DrumPad('TRIANGLE MUTE', 80),
  DrumPad('TRIANGLE OPEN', 81),
];
