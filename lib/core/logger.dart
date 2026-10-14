import 'dart:developer' as dev;

class AppLogger {
  final String tag;

  const AppLogger(this.tag);

  void info(String message) {
    dev.log('[\x1B[32mINFO\x1B[0m] $message', name: tag);
  }

  void warning(String message) {
    dev.log('[\x1B[33mWARN\x1B[0m] $message', name: tag);
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    dev.log(
      '[\x1B[31mERROR\x1B[0m] $message',
      name: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
