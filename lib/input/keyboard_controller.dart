import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/app_log.dart';

/// Keeps a text input connection attached so the OS soft keyboard never
/// dismisses, and routes *all* input through two callbacks:
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
    with WidgetsBindingObserver, TextInputClient {
  static const TextInputConfiguration _configuration = TextInputConfiguration(
    inputType: TextInputType.text,
    inputAction: TextInputAction.newline,
    autocorrect: false,
    enableSuggestions: false,
    enableInteractiveSelection: false,
    enableIMEPersonalizedLearning: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    textCapitalization: TextCapitalization.none,
  );

  final FocusNode _focus = FocusNode(
    debugLabel: 'daw-always-on',
    skipTraversal: true,
  );
  TextInputConnection? _connection;
  TextEditingValue _value = TextEditingValue.empty;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _focus.addListener(_handleFocusChange);
    FocusManager.instance.addListener(_handleAnyFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    FocusManager.instance.removeListener(_handleAnyFocusChange);
    _connection?.close();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refocus();
    }
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final ratio = view.devicePixelRatio;
    final inset = ratio == 0 ? 0.0 : view.viewInsets.bottom / ratio;
    AppLog.instance.debug(
      'IME',
      'metrics keyboardInset=${inset.toStringAsFixed(1)}',
    );
  }

  void _refocus() {
    if (!mounted) return;
    final hadFocus = _focus.hasFocus;
    final otherField = _textInputsOwnFocus();
    if (!hadFocus && !otherField) {
      _focus.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus || _textInputsOwnFocus()) return;
      _openInput();
    });
    AppLog.instance.debug(
      'IME',
      'refocus hadFocus=$hadFocus otherField=$otherField '
          'now=${_focus.hasFocus}',
    );
  }

  void _openInput() {
    var connection = _connection;
    if (connection == null || !connection.attached) {
      connection?.close();
      connection = TextInput.attach(this, _configuration);
      _connection = connection;
      connection.setEditingState(_value);
      AppLog.instance.debug('IME', 'attached input connection');
    }
    connection.show();
    AppLog.instance.debug('IME', 'requested keyboard show');
  }

  void _handleFocusChange() {
    AppLog.instance.debug('IME', 'sink focus=${_focus.hasFocus}');
    if (_focus.hasFocus) {
      scheduleMicrotask(_openInput);
      return;
    }
    _connection?.close();
    _connection = null;
    scheduleMicrotask(_refocus);
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

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    final text = value.text;
    _value = value;
    if (text == _lastText) return;
    AppLog.instance.debug('IME', 'text="$text" last="$_lastText"');

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
  void performAction(TextInputAction action) {
    AppLog.instance.debug('IME', 'action=$action');
    if (action != TextInputAction.newline && action != TextInputAction.done) {
      return;
    }
    widget.onSubmit?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus || _textInputsOwnFocus()) return;
      _openInput();
    });
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  bool onFocusReceived() => _focus.hasFocus;

  @override
  void connectionClosed() {
    AppLog.instance.debug('IME', 'connection closed');
    _connection = null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Focus(
              focusNode: _focus,
              includeSemantics: false,
              child: const SizedBox.expand(),
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
