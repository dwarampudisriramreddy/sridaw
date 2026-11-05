import 'dart:async';

import 'package:flutter/foundation.dart';
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
  final VoidCallback? onSubmit;

  const AlwaysOnKeyboard({
    super.key,
    required this.child,
    required this.onKey,
    required this.onText,
    this.onSubmit,
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
    FocusManager.instance.addListener(_handleAnyFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    FocusManager.instance.removeListener(_handleAnyFocusChange);
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
    if (!_focus.hasFocus && !_textInputsOwnFocus()) {
      _focus.requestFocus();
    }
    // On mobile, focusing programmatically does not always pop the IME up
    // (notably right after startup), so ask for it explicitly.
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }
  }

  void _handleFocusChange() {
    if (!_focus.hasFocus) {
      scheduleMicrotask(_refocus);
    }
  }

  /// Fires for every focus move in the app — including the moment a dialog
  /// field takes focus and the later moment it goes away. The sink must
  /// reclaim focus in the second case, and stay out of the way in the first.
  void _handleAnyFocusChange() {
    if (!mounted || _focus.hasFocus || _textInputsOwnFocus()) return;
    scheduleMicrotask(_refocus);
  }

  /// True while a real text field (the instrument filter, mixer entry, …)
  /// holds focus instead of this invisible sink.
  bool _textInputsOwnFocus() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node == _focus) return false;
    final ctx = node.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    var found = false;
    ctx.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool _handleHardwareKey(KeyEvent event) {
    // While a real text field owns focus its characters belong to it, not to
    // the vim keymap.
    if (_textInputsOwnFocus()) return false;
    return widget.onKey(event);
  }

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
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {},
                  onSubmitted: (_) => widget.onSubmit?.call(),
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
