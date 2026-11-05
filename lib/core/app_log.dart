import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warning, error }

extension AppLogLevelLabel on AppLogLevel {
  String get label => switch (this) {
    AppLogLevel.debug => 'DEBUG',
    AppLogLevel.info => 'INFO',
    AppLogLevel.warning => 'WARN',
    AppLogLevel.error => 'ERROR',
  };
}

class AppLogEntry {
  final DateTime time;
  final AppLogLevel level;
  final String tag;
  final String message;
  final StackTrace? stack;

  const AppLogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.stack,
  });

  String get timeLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    final millis = time.millisecond.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
  }

  String get line => '$timeLabel ${level.label.padRight(5)} [$tag] $message';
}

/// In-app log ring buffer used by the DEBUG tab. Installed in `main` to capture
/// framework errors, uncaught async errors and debugPrint output.
class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();
  static const int maxEntries = 500;

  final List<AppLogEntry> _entries = [];
  bool _installed = false;
  bool _suppressDebugPrint = false;

  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  void add(
    AppLogLevel level,
    String message, {
    String tag = 'APP',
    StackTrace? stack,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    _entries.add(
      AppLogEntry(
        time: DateTime.now(),
        level: level,
        tag: tag,
        message: text,
        stack: stack,
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
  }

  void debug(String tag, String message, {StackTrace? stack}) =>
      add(AppLogLevel.debug, message, tag: tag, stack: stack);

  void info(String tag, String message, {StackTrace? stack}) =>
      add(AppLogLevel.info, message, tag: tag, stack: stack);

  void warning(String tag, String message, {StackTrace? stack}) =>
      add(AppLogLevel.warning, message, tag: tag, stack: stack);

  void error(String tag, String message, {StackTrace? stack}) =>
      add(AppLogLevel.error, message, tag: tag, stack: stack);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  static void install() {
    final log = instance;
    if (log._installed) return;
    log._installed = true;

    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (!log._suppressDebugPrint && message != null && message.isNotEmpty) {
        log.add(AppLogLevel.debug, message, tag: 'PRINT');
      }
      previousDebugPrint(message, wrapWidth: wrapWidth);
    };

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      log.add(
        AppLogLevel.error,
        details.exceptionAsString(),
        tag: 'FLUTTER',
        stack: details.stack,
      );
      log._suppressDebugPrint = true;
      try {
        (previousOnError ?? FlutterError.presentError)(details);
      } finally {
        log._suppressDebugPrint = false;
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      log.add(
        AppLogLevel.error,
        error.toString(),
        tag: 'UNCAUGHT',
        stack: stack,
      );
      return true;
    };

    log.info('APP', 'debug logger installed');
  }
}
