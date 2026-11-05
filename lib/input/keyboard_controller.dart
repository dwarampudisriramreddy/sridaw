import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/app_log.dart';

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
  String _lastText = '';

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
    final hadFocus = _focus.hasFocus;
    final otherField = _textInputsOwnFocus();
    if (!hadFocus && !otherField) {
      _focus.requestFocus();
    }
    // On mobile, focusing programmatically does not always pop the IME up
    // (notably right after startup), so ask for it explicitly.
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }
    AppLog.instance.debug(
      'IME',
      'refocus hadFocus=$hadFocus otherField=$otherField '
          'now=${_focus.hasFocus}',
    );
  }

  void _handleFocusChange() {
    AppLog.instance.debug('IME', 'sink focus=${_focus.hasFocus}');
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
    if (event is KeyDownEvent) {
      final char = event.character;
      AppLog.instance.debug(
        'KEY',
        '${event.logicalKey.keyLabel}'
            '${char == null || char.isEmpty ? '' : ' char=$char'}',
      );
    }
    return widget.onKey(event);
  }

  void _handleText() {
    final text = _controller.text;
    if (text == _lastText) return;
    AppLog.instance.debug(
      'IME',
      'text="${_controller.text}" last="$_lastText"',
    );

    // Never clear the controller from inside its listener: Gboard tries to
    // restore the composing region and can end up in a loop where no keys
    // reach the app. Keep the hidden buffer and forward only new characters.
    if (text.startsWith(_lastText)) {
      final delta = text.substring(_lastText.length);
      _lastText = text;
      if (delta.isNotEmpty) {
        AppLog.instance.debug('IME', 'forward "$delta"');
        widget.onText(delta);
      }
      return;
    }
    if (_lastText.startsWith(text)) {
      // A deletion/backspace from the IME; no new character to forward.
      _lastText = text;
      AppLog.instance.debug('IME', 'ignored deletion');
      return;
    }
    _lastText = text;
    if (text.isNotEmpty) {
      AppLog.instance.debug('IME', 'replacement forward "$text"');
      widget.onText(text);
    }
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
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) {},
                  // Keep the input connection alive after the Done action.
                  onEditingComplete: () {
                    AppLog.instance.debug('IME', 'editing complete');
                  },
                  onSubmitted: (_) {
                    AppLog.instance.debug('IME', 'submitted');
                    widget.onSubmit?.call();
                    // Some Android IMEs hide after Done even when focus is
                    // retained, so ask for the keyboard again after the frame.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _refocus(),
                    );
                  },
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
