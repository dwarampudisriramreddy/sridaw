import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/palette.dart';
import '../core/pixel_font.dart';

/// Hosts a low-resolution logical canvas and scales it by the largest integer
/// factor that fits, with nearest-neighbour sampling. Nothing inside is ever
/// anti-aliased, which is what gives the whole app its chunky pixel identity.
class PixelViewport extends StatelessWidget {
  final int logicalWidth;
  final int logicalHeight;
  final Color background;
  final Widget child;

  const PixelViewport({
    super.key,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.child,
    this.background = const Color(0xFF000000),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : logicalWidth.toDouble();
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : logicalHeight.toDouble();
        final scale = math.max(
          1,
          math.min(maxW ~/ logicalWidth, maxH ~/ logicalHeight),
        );
        return ColoredBox(
          color: background,
          child: Center(
            child: SizedBox(
              width: (logicalWidth * scale).toDouble(),
              height: (logicalHeight * scale).toDouble(),
              child: ClipRect(
                child: Transform.scale(
                  scale: scale.toDouble(),
                  alignment: Alignment.topLeft,
                  filterQuality: FilterQuality.none,
                  child: SizedBox(
                    width: logicalWidth.toDouble(),
                    height: logicalHeight.toDouble(),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Base class for every pixel layer. Coordinates are logical pixels; all draws
/// are integer aligned and anti-aliasing is disabled. Subclasses bump
/// [revision] to signal a repaint, mirroring the per-layer invalidation grid
/// described in the spec.
abstract class PixelPainter extends CustomPainter {
  final PixelPalette palette;
  final int revision;

  PixelPainter({required this.palette, required this.revision});

  Paint fill(int index) => Paint()
    ..color = palette[index]
    ..isAntiAlias = false;

  Paint stroke(int index, [int width = 1]) => Paint()
    ..color = palette[index]
    ..isAntiAlias = false
    ..style = PaintingStyle.stroke
    ..strokeWidth = width.toDouble();

  void px(Canvas canvas, int x, int y, int index) {
    canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), fill(index));
  }

  void rect(Canvas canvas, int x, int y, int w, int h, int index) {
    if (w <= 0 || h <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
      fill(index),
    );
  }

  void frame(Canvas canvas, int x, int y, int w, int h, int index, [int width = 1]) {
    if (w <= 0 || h <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
      stroke(index, width),
    );
  }

  /// Sparse fill: one in [period] pixels. Used for ghost notes (25%) and
  /// velocity shading.
  void dither(
    Canvas canvas,
    int x,
    int y,
    int w,
    int h,
    int index, {
    int period = 4,
  }) {
    final paint = fill(index);
    final one = Rect.fromLTWH(0, 0, 1, 1);
    for (var py = 0; py < h; py++) {
      for (var pxc = 0; pxc < w; pxc++) {
        if ((pxc + py) % period == 0) {
          canvas.drawRect(
            one.shift(Offset((x + pxc).toDouble(), (y + py).toDouble())),
            paint,
          );
        }
      }
    }
  }

  void glyph(Canvas canvas, PixelFont font, String text, int x, int y, int index,
      {int scale = 1}) {
    font.draw(canvas, text, x, y, palette[index], scale: scale);
  }
}
