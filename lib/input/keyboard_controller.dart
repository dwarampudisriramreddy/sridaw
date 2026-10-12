import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps an invisible [EditableText] permanently focused so the OS soft
/// keyboard never dismisses, and routes *all* input through two callbacks:
///
/// * [onKey]  - hardware key events (desktop + external keyboards), including
///              key-up so held-note logic works later.
/// * [onText] - characters delivered by an IME / soft keyboard.
///
/// The visible UI is passed as [child] and never contains Material widgets.
class AlwaysOnKeyboard extends StatefulWidget {
  final Widget child;
  final bool Function(KeyEvent event) onKey;
  final void Function(String text) onText;

  const AlwaysOnKeyboard({
    super.key,
    required this.child,
    required this.onKey,
    required this.onText,
  });

  @override
  State<AlwaysOnKeyboard> createState() => _AlwaysOnKeyboardState();
}

class _AlwaysOnKeyboardState extends State<AlwaysOnKeyboard>
    with WidgetsBindingObserver {
  final FocusNode _focus = FocusNode(debugLabel: 'daw-always-on');
  final TextEditingController _controller = TextEditingController();
  bool _suppressText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _controller.addListener(_handleText);
    _focus.addListener(_handleFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refocus();
    }
  }

  void _refocus() {
    if (!mounted) return;
    if (!_focus.hasFocus) {
      _focus.requestFocus();
    }
  }

  void _handleFocusChange() {
    if (!_focus.hasFocus) {
      scheduleMicrotask(_refocus);
    }
  }

  bool _handleHardwareKey(KeyEvent event) => widget.onKey(event);

  void _handleText() {
    if (_suppressText) return;
    final text = _controller.text;
    if (text.isEmpty) return;
    _suppressText = true;
    _controller.clear();
    _suppressText = false;
    widget.onText(text);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Invisible IME sink. Kept at 1x1 so it never affects layout.
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: EditableText(
                  controller: _controller,
                  focusNode: _focus,
                  style: const TextStyle(color: Color(0x00000000), fontSize: 1),
                  cursorColor: const Color(0x00000000),
                  backgroundCursorColor: const Color(0x00000000),
                  showCursor: false,
                  autofocus: true,
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textCapitalization: TextCapitalization.none,
                  maxLines: 1,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) => _refocus(),
          child: widget.child,
        ),
      ],
    );
  }
}
