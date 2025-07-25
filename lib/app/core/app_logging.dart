import 'package:ex_kit/ex.dart' as ex;

import '../../env.g.dart';

// ** LOGGING with Level ~
enum LogLevel { error, warn, info, debug }

mixin AppLog {
  static final LogLevel _logLevel = _getLogLevelFromEnv();

  static void logD(dynamic message) {
    LogLevel level = LogLevel.debug;
    if (!_shouldLog(level)) return;
    ex.logC(ex.LogColor.white, message, name: _getPrefix(level));
  }

  static void logI(dynamic message) {
    LogLevel level = LogLevel.info;
    if (!_shouldLog(level)) return;
    ex.logC(ex.LogColor.cyan, message, name: _getPrefix(level));
  }

  static void logW(dynamic message) {
    LogLevel level = LogLevel.warn;
    if (!_shouldLog(level)) return;
    ex.logC(ex.LogColor.orange, message, name: _getPrefix(level));
  }

  static void logE(dynamic message) {
    LogLevel level = LogLevel.error;
    if (!_shouldLog(level)) return;
    ex.logC(ex.LogColor.red, message, name: _getPrefix(level));
  }

   static void logS(dynamic message) {
    ex.logC(ex.LogColor.green, message, name: 'Success');
  }

  static bool _shouldLog(LogLevel level) {
    return level.index <= _logLevel.index;
  }

  static String _getPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.error: return 'ERROR';
      case LogLevel.warn: return 'WARNING';
      case LogLevel.info: return 'INFO';
      case LogLevel.debug: return 'DEBUG';
    }
  }

  static LogLevel _getLogLevelFromEnv() {
    final String envLogLevel = Env.logLvl.toUpperCase();
    switch (envLogLevel) {
      case 'ERROR': return LogLevel.error;
      case 'WARNING': return LogLevel.warn;
      case 'INFO': return LogLevel.info;
      case 'DEBUG': return LogLevel.debug;
      default: return LogLevel.debug;
    }
  }
}
