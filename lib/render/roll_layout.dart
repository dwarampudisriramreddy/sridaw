/// Native-resolution geometry for the piano roll surface, shared by the
/// painter and by pointer hit-testing. All values are device-independent
/// pixels. `row = pitch`, `column = time`.
library;

class RollLayout {
  /// Width of one 16th-note step, in device-independent pixels.
  static const int cellW = 18;

  /// Height of one pitch row.
  static const int cellH = 16;

  /// Width of the piano-keyboard gutter.
  static const int keyW = 56;

  /// Height of the bar/beat ruler strip along the top.
  static const int rulerH = 22;

  final int viewLowPitch;
  final int viewCol;
  final int width;
  final int height;

  const RollLayout({
    required this.viewLowPitch,
    required this.viewCol,
    required this.width,
    required this.height,
  });

  int get gridX => keyW;
  int get gridY => rulerH;
  int get gridW => width - keyW;
  int get gridH => height - rulerH;
  int get rows => gridH ~/ cellH;
  int get cols => gridW ~/ cellW;
  int get gridBottom => gridY + rows * cellH;

  int get topPitch => viewLowPitch + rows - 1;

  int xForCol(int col) => gridX + (col - viewCol) * cellW;

  /// Top-left y for a pitch row.
  int yForPitch(int pitch) => gridY + (topPitch - pitch) * cellH;

  int pitchForY(int y) {
    final rowFromTop = (y - gridY) ~/ cellH;
    return topPitch - rowFromTop;
  }

  int colForX(int x) => viewCol + ((x - gridX) ~/ cellW);

  bool inGrid(int px, int py) =>
      px >= gridX && px < gridX + gridW && py >= gridY && py < gridBottom;
}
