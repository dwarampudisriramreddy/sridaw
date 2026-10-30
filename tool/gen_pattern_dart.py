import json

data = json.load(open('/tmp/patterns.json'))

def q(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"

lines = []
lines.append('// GENERATED FILE - do not edit by hand.')
lines.append('// Regenerate with: python3 tool/extract_patterns.py && python3 tool/gen_pattern_dart.py')
lines.append('//')
lines.append('// Pattern data extracted from the music-theory course libraries:')
lines.append('//   36 - The Melody & Motif Library        (m001-m150)')
lines.append('//   37 - The Chord & Accompaniment Library (c001-c150)')
lines.append('//   38 - The Beat & Rhythm Pattern Library (b001-b150)')
lines.append('library;')
lines.append('')
lines.append('class LibStep {')
lines.append('  final List<int> notes;')
lines.append('  final int dur; // MIDI ticks, 128 = one quarter note')
lines.append('  final List<int>? vel;')
lines.append('  const LibStep(this.notes, this.dur, [this.vel]);')
lines.append('}')
lines.append('')
lines.append('class LibPattern {')
lines.append('  final String id;')
lines.append('  final String title;')
lines.append('  final String section;')
lines.append('  final int bpm;')
lines.append('  final int beatsPerBar;')
lines.append('  final bool drums;')
lines.append('  final List<LibStep> steps;')
lines.append('  const LibPattern({')
lines.append('    required this.id,')
lines.append('    required this.title,')
lines.append('    required this.section,')
lines.append('    required this.bpm,')
lines.append('    required this.beatsPerBar,')
lines.append('    required this.drums,')
lines.append('    required this.steps,')
lines.append('  });')
lines.append('}')
lines.append('')

names = [('chordPatterns', 'c'), ('melodyPatterns', 'm'), ('rhythmPatterns', 'b')]
for var, key in names:
    lines.append(f'const List<LibPattern> {var} = [')
    for p in data[key]:
        steps = []
        for notes, dur, vel in p['steps']:
            n = '[' + ','.join(str(x) for x in notes) + ']'
            if vel:
                v = '[' + ','.join(str(x) for x in vel) + ']'
                steps.append(f'LibStep({n},{dur},{v})')
            else:
                steps.append(f'LibStep({n},{dur})')
        lines.append('  LibPattern(')
        lines.append(f'    id: {q(p["id"])},')
        lines.append(f'    title: {q(p["title"])},')
        lines.append(f'    section: {q(p["section"])},')
        lines.append(f'    bpm: {p["bpm"]},')
        lines.append(f'    beatsPerBar: {p["beatsPerBar"]},')
        lines.append(f'    drums: {str(p["drums"]).lower()},')
        lines.append('    steps: [' + ', '.join(steps) + '],')
        lines.append('  ),')
    lines.append('];')
    lines.append('')

out = '\n'.join(lines)
open('/home/sri/vimdaw/lib/theory/pattern_library.dart', 'w').write(out)
print('wrote', len(out), 'bytes')
