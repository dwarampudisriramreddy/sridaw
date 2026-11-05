/// Native-resolution geometry for the piano roll surface, shared by the
/// painter and by pointer hit-testing. All values are device-independent
/// pixels. `row = pitch`, `column = time`.
library;

import 'dart:math' as math;

class RollLayout {
  /// Width of one 16th-note step, in device-independent pixels.
  static const int cellW = 18;

  /// Height of one pitch row.
  static const int cellH = 16;

  /// Width of the piano-keyboard gutter.
  static const int keyW = 56;

  /// Wider gutter used when the roll shows drum names horizontally.
  static const int drumGutterW = 76;

  /// Height of the bar/beat ruler strip along the top.
  static const int rulerH = 22;

  final int viewLowPitch;
  final int viewCol;
  final int width;
  final int height;

  /// Width of the left gutter this surface actually uses. The piano roll
  /// keeps the default [keyW]; drum tracks widen it so the sound names fit.
  final int gutterW;

  /// Ascending MIDI pitches that get a row, or null for the usual chromatic
  /// keyboard. When set, rows are scale steps instead of semitones and
  /// out-of-key notes are hidden.
  final List<int>? scalePitches;

  const RollLayout({
    required this.viewLowPitch,
    required this.viewCol,
    required this.width,
    required this.height,
    this.gutterW = keyW,
    this.scalePitches,
  });

  bool get scaleOnly => scalePitches != null;

  int get gridX => gutterW;
  int get gridY => rulerH;
  int get gridW => width - gutterW;
  int get gridH => height - rulerH;
  int get rows => gridH ~/ cellH;
  int get cols => gridW ~/ cellW;
  int get gridBottom => gridY + rows * cellH;

  /// Index of the bottom visible row in [scalePitches] (or the MIDI pitch in
  /// chromatic mode, where indices and pitches are the same thing).
  int get lowIndex {
    final list = scalePitches;
    if (list == null) return viewLowPitch.clamp(0, 127);
    if (list.isEmpty) return 0;
    return _lowerBound(list, viewLowPitch).clamp(0, list.length - 1);
  }

  int get topIndex {
    final list = scalePitches;
    if (list == null) return viewLowPitch + rows - 1;
    if (list.isEmpty) return 0;
    return math.min(lowIndex + rows - 1, list.length - 1);
  }

  int get topPitch {
    final list = scalePitches;
    if (list == null) return viewLowPitch + rows - 1;
    if (list.isEmpty) return viewLowPitch;
    return list[topIndex];
  }

  /// Pitches with a row in the current viewport, bottom to top.
  List<int> get visiblePitches {
    final list = scalePitches;
    if (list == null) {
      return [for (var p = viewLowPitch; p <= viewLowPitch + rows - 1; p++) p];
    }
    return [for (var i = lowIndex; i <= topIndex; i++) list[i]];
  }

  int xForCol(int col) => gridX + (col - viewCol) * cellW;

  /// Top-left y for a pitch row. Out-of-view pitches map above the grid.
  int yForPitch(int pitch) {
    final list = scalePitches;
    if (list == null) return gridY + (topPitch - pitch) * cellH;
    final index = _indexOf(list, pitch);
    if (index == null || index < lowIndex || index > topIndex) {
      return gridY - cellH;
    }
    return gridY + (topIndex - index) * cellH;
  }

  int pitchForY(int y) {
    final rowFromTop = (y - gridY) ~/ cellH;
    final list = scalePitches;
    if (list == null) {
      return (topPitch - rowFromTop).clamp(0, 127);
    }
    if (list.isEmpty) return viewLowPitch;
    final index = (topIndex - rowFromTop).clamp(lowIndex, topIndex);
    return list[index];
  }

  bool isPitchVisible(int pitch) {
    final list = scalePitches;
    if (list == null) {
      return pitch >= viewLowPitch && pitch <= viewLowPitch + rows - 1;
    }
    final index = _indexOf(list, pitch);
    return index != null && index >= lowIndex && index <= topIndex;
  }

  /// Move the bottom of the view by [rowDelta] rows, following scale steps
  /// when scale-only rows are active.
  int shiftLowPitch(int lowPitch, int rowDelta) {
    final list = scalePitches;
    if (list == null) return (lowPitch + rowDelta).clamp(0, 127);
    if (list.isEmpty) return lowPitch;
    final index = (_lowerBound(list, lowPitch) + rowDelta).clamp(
      0,
      list.length - 1,
    );
    return list[index];
  }

  /// Smallest bottom pitch that keeps [targetPitch] on screen.
  int revealLowPitch(int lowPitch, int targetPitch) {
    final list = scalePitches;
    if (list == null) {
      var low = lowPitch;
      if (targetPitch > low + rows - 1) low = targetPitch - rows + 1;
      if (targetPitch < low) low = targetPitch;
      return low.clamp(0, 127);
    }
    if (list.isEmpty) return lowPitch;
    var index = _lowerBound(list, lowPitch);
    final target = _indexOf(list, targetPitch);
    if (target == null) return list[index.clamp(0, list.length - 1)];
    if (target < index) {
      index = target;
    } else if (target > index + rows - 1) {
      index = target - rows + 1;
    }
    return list[index.clamp(0, list.length - 1)];
  }

  int colForX(int x) => viewCol + ((x - gridX) ~/ cellW);

  bool inGrid(int px, int py) =>
      px >= gridX && px < gridX + gridW && py >= gridY && py < gridBottom;

  static int _lowerBound(List<int> list, int value) {
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int? _indexOf(List<int> list, int value) {
    final i = _lowerBound(list, value);
    return i < list.length && list[i] == value ? i : null;
  }
}
