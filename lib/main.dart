import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ui/app_shell.dart';
import 'ui/daw_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VimDawApp());
}

/// `MaterialApp` is used purely as infrastructure (localisation, directionality,
/// focus and IME plumbing). The visible UI is custom-painted and laid out with
/// plain widgets, styled from [DawTheme].
class VimDawApp extends StatelessWidget {
  const VimDawApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'vimdaw',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: DawColors.bg,
        canvasColor: DawColors.bg,
        colorScheme: base.colorScheme.copyWith(
          surface: DawColors.surface,
          primary: DawTheme.accents.first.accent,
        ),
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
      ),
      home: const AppShell(),
    );
  }
}
