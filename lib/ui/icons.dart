import 'package:flutter/material.dart';

/// Single place the UI pulls its glyphs from, so the icon set can be swapped
/// (Lucide, Phosphor, …) without touching the chrome.
abstract final class AppIcons {
  static const IconData play = Icons.play_arrow_rounded;
  static const IconData pause = Icons.pause_rounded;
  static const IconData stop = Icons.stop_rounded;
  static const IconData music = Icons.graphic_eq_rounded;
  static const IconData gauge = Icons.speed_rounded;
  static const IconData ghost = Icons.blur_on_rounded;
  static const IconData palette = Icons.palette_outlined;
  static const IconData arrowLeft = Icons.arrow_back_rounded;
  static const IconData arrowRight = Icons.arrow_forward_rounded;
  static const IconData arrowUp = Icons.arrow_upward_rounded;
  static const IconData arrowDown = Icons.arrow_downward_rounded;
  static const IconData home = Icons.home_rounded;
  static const IconData end = Icons.keyboard_double_arrow_right_rounded;
  static const IconData command = Icons.keyboard_command_key_rounded;
}
