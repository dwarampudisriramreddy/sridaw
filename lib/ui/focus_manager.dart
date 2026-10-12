import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/daw_input.dart';
import '../input/keymap.dart';

/// Manages keyboard focus across all DAW views for vim-like navigation.
/// Every interactive widget registers itself; Tab/Shift+Tab cycles focus.
/// Arrow keys and vim motions (h/j/k/l) move focus spatially within a view.
class FocusManager {
  final List<FocusNode> _focusNodes = [];
  int _currentIndex = -1;
  ViewMode _activeView = ViewMode.roll;

  final Map<ViewMode, List<FocusNode>> _viewNodes = {
    ViewMode.roll: [],
    ViewMode.pattern: [],
    ViewMode.arrangement: [],
    ViewMode.mixer: [],
    ViewMode.sample: [],
    ViewMode.automation: [],
    ViewMode.help: [],
  };

  void register(FocusNode node, ViewMode view) {
    if (!_viewNodes[view]!.contains(node)) {
      _viewNodes[view]!.add(node);
    }
    if (!_focusNodes.contains(node)) {
      _focusNodes.add(node);
    }
  }

  void unregister(FocusNode node) {
    for (final list in _viewNodes.values) {
      list.remove(node);
    }
    _focusNodes.remove(node);
    if (_currentIndex >= _focusNodes.length) {
      _currentIndex = _focusNodes.length - 1;
    }
  }

  void setActiveView(ViewMode view) {
    _activeView = view;
    _currentIndex = -1;
  }

  ViewMode get activeView => _activeView;

  List<FocusNode> get currentViewNodes => _viewNodes[_activeView]!;

  void _ensureIndex() {
    final nodes = currentViewNodes;
    if (nodes.isEmpty) {
      _currentIndex = -1;
      return;
    }
    if (_currentIndex < 0 || _currentIndex >= nodes.length) {
      _currentIndex = 0;
    }
  }

  void focusNext() {
    _ensureIndex();
    if (currentViewNodes.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % currentViewNodes.length;
    currentViewNodes[_currentIndex].requestFocus();
  }

  void focusPrevious() {
    _ensureIndex();
    if (currentViewNodes.isEmpty) return;
    _currentIndex = (_currentIndex - 1 + currentViewNodes.length) % currentViewNodes.length;
    currentViewNodes[_currentIndex].requestFocus();
  }

  void focusFirst() {
    _ensureIndex();
    if (currentViewNodes.isNotEmpty) {
      _currentIndex = 0;
      currentViewNodes[0].requestFocus();
    }
  }

  void focusLast() {
    final nodes = currentViewNodes;
    if (nodes.isNotEmpty) {
      _currentIndex = nodes.length - 1;
      nodes.last.requestFocus();
    }
  }

  void moveFocusUp() => _moveFocusSpatial(Offset(0, -1));
  void moveFocusDown() => _moveFocusSpatial(Offset(0, 1));
  void moveFocusLeft() => _moveFocusSpatial(Offset(-1, 0));
  void moveFocusRight() => _moveFocusSpatial(Offset(1, 0));

  void _moveFocusSpatial(Offset dir) {
    final nodes = currentViewNodes.where((n) => n.hasFocus).toList();
    if (nodes.isEmpty) {
      focusFirst();
      return;
    }
    // For spatial navigation, use the focused node's widget position
    // This requires a custom FocusTraversalPolicy; for now fallback to tab order.
    if (dir.dx > 0) {
      focusNext();
    } else if (dir.dx < 0) {
      focusPrevious();
    } else if (dir.dy > 0) {
      focusNext();
    } else {
      focusPrevious();
    }
  }

  bool handleKey(KeyEvent event, DawAction action) {
    final isKeyDown = event is KeyDownEvent;
    if (!isKeyDown) return false;

    switch (action) {
      case DawAction.focusNext:
        focusNext();
        return true;
      case DawAction.focusPrev:
        focusPrevious();
        return true;
      case DawAction.focusFirst:
        focusFirst();
        return true;
      case DawAction.focusLast:
        focusLast();
        return true;
      case DawAction.moveFocusUp:
        moveFocusUp();
        return true;
      case DawAction.moveFocusDown:
        moveFocusDown();
        return true;
      case DawAction.moveFocusLeft:
        moveFocusLeft();
        return true;
      case DawAction.moveFocusRight:
        moveFocusRight();
        return true;
      default:
        return false;
    }
  }
}

/// A widget that registers itself with the FocusManager and provides
/// a consistent focus indicator.
class FocusableWidget extends StatefulWidget {
  final Widget child;
  final ViewMode view;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final VoidCallback? onBlur;

  const FocusableWidget({
    super.key,
    required this.child,
    required this.view,
    this.focusNode,
    this.onFocus,
    this.onBlur,
  });

  @override
  State<FocusableWidget> createState() => _FocusableWidgetState();
}

class _FocusableWidgetState extends State<FocusableWidget> {
  late FocusNode _focusNode;
  FocusManager? _manager;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manager = FocusManagerScope.of(context, listen: false);
    if (!_registered) {
      _manager!.register(_focusNode, widget.view);
      _registered = true;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _manager?.unregister(_focusNode);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onFocus?.call();
    } else {
      widget.onBlur?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            decoration: BoxDecoration(
              border: Border.all(
                color: hasFocus ? const Color(0xFF00D4AA) : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// InheritedWidget to provide FocusManager to the widget tree.
class FocusManagerScope extends InheritedWidget {
  final FocusManager manager;

  const FocusManagerScope({
    super.key,
    required this.manager,
    required super.child,
  });

  static FocusManager of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<FocusManagerScope>()
        : context.getInheritedWidgetOfExactType<FocusManagerScope>();
    if (scope == null) throw StateError('No FocusManagerScope found');
    return scope.manager;
  }

  @override
  bool updateShouldNotify(FocusManagerScope old) => manager != old.manager;
}