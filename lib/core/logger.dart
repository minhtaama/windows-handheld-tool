import 'dart:developer' as dev;

/// Bộ tiện ích ghi log ứng dụng với thẻ tiền tố.
class AppLogger {
  final String tag;

  const AppLogger(this.tag);

  void info(String message) {
    dev.log('[\x1B[32mINFO\x1B[0m] [$tag] $message', name: tag);
    // ignore: avoid_print
    print('[INFO] [$tag] $message');
  }

  void warning(String message) {
    dev.log('[\x1B[33mWARN\x1B[0m] [$tag] $message', name: tag);
    // ignore: avoid_print
    print('[WARN] [$tag] $message');
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    dev.log(
      '[\x1B[31mERROR\x1B[0m] [$tag] $message',
      name: tag,
      error: error,
      stackTrace: stackTrace,
    );
    // ignore: avoid_print
    print('[ERROR] [$tag] $message ${error != null ? '($error)' : ''}');
  }
}
