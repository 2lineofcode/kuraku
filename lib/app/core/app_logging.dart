import 'package:ex_kit/ex.dart';

import '../../env.g.dart';

// ** LOGGING with Level ~
// reference: https://www.youtube.com/watch?v=aaNIxGGmlKQ

enum LogLevel { error, warn, info, debug }

mixin AppLog {
  static final LogLevel _logLevel = _getLogLevelFromEnv();

  static void log(String message, {LogLevel level = LogLevel.debug}) {
    if (!_shouldLog(level)) return;

    final String prefix = _getPrefix(level);
    switch (level) {
      case LogLevel.error:
        logE('$prefix $message');
        break;
      case LogLevel.warn:
        logW('$prefix $message');
        break;
      case LogLevel.info:
        logS('$prefix $message');
        break;
      case LogLevel.debug:
        print('$prefix $message');
        break;
    }
  }

  static bool _shouldLog(LogLevel level) {
    return level.index <= _logLevel.index;
  }

  static String _getPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return '[ERROR]';
      case LogLevel.warn:
        return '[WARNING]';
      case LogLevel.info:
        return '[INFO]';
      case LogLevel.debug:
        return '[DEBUG]';
    }
  }

  static LogLevel _getLogLevelFromEnv() {
    final String envLogLevel = Env.logLvl.toUpperCase();
    switch (envLogLevel) {
      case 'ERROR':
        return LogLevel.error;
      case 'WARNING':
        return LogLevel.warn;
      case 'INFO':
        return LogLevel.info;
      case 'DEBUG':
        return LogLevel.debug;
      default:
        return LogLevel.debug;
    }
  }
}
