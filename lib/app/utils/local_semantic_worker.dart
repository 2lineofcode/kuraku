import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../core/app_dependencies.dart';
import '../core/app_logging.dart';
import '../core/app_setting.dart';
import '../core/app_translations.dart';
import '../data/database/_init_db.dart';

class SemanticSearchException implements Exception {
  final String message;
  SemanticSearchException(this.message);
  @override
  String toString() => message;
}

mixin LocalSemanticWorker {
  static const modelName = 'clip-vit-b32-int8-v2';
  static const readyMarker = '$modelName:2';
  static Process? _process;
  static Process? _installer;
  static int _setupEpoch = 0;
  static Future<void> _queue = Future<void>.value();
  static int _queued = 0;
  static String? _command;
  static final _owners = Expando<int>();
  static Future<void>? _starting;
  static Future<void>? _setup;
  static Timer? _idleTimer;
  static int _nextId = 0;
  static int _epoch = 0;
  static final _pending = <int, Completer<dynamic>>{};
  static String get _root => p.join(Get.find<AppSettingService>().appPath, 'semantic_runtime');
  static String get _script => p.join(Get.find<AppSettingService>().bundledAssetsPath, 'visual_search_worker.py');
  static String get _python => p.join(_root, 'venv', Platform.isWindows ? 'Scripts' : 'bin', Platform.isWindows ? 'python.exe' : 'python');

  static Future<bool> isReady() async {
    final marker = File(p.join(_root, 'ready'));
    if (!await marker.exists() || await marker.readAsString() != readyMarker || !await File(_python).exists()) return false;
    const sizes = {'onnx/vision_model_int8.onnx': 88648877, 'onnx/text_model_int8.onnx': 64070791, 'tokenizer.json': 2224119, 'LICENSE': 1064};
    for (final entry in sizes.entries) {
      final file = File(p.join(_root, entry.key));
      if (!await file.exists() || await file.length() != entry.value) return false;
    }
    return true;
  }

  static Future<void> setup(void Function(String) onProgress) async {
    if (_setup != null) return _setup!;
    final future = _install(onProgress);
    _setup = future;
    try { await future; } finally { _setup = null; }
  }

  static String translateSetupProgress(String message) {
    final download = RegExp(r'^Downloading (image search model|text search model|search resources): (.+)$').firstMatch(message);
    return download == null ? message.tr : 'Downloading @{resource}: @{amount}'.trNamed({
      'resource': download[1]!.tr, 'amount': download[2]!,
    });
  }

  static Future<void> _install(void Function(String) onProgress) async {
    stop();
    final epoch = _setupEpoch;
    onProgress('Checking Python and preparing local runtime...'.tr);
    AppLog.logI('Visual Search: checking Python and preparing local runtime');
    final String python;
    try {
      python = await AppDependencies.shared.requirePython(visualSearch: true);
    } on StateError catch (e) {
      throw SemanticSearchException('${e.message}');
    }
    if (epoch != _setupEpoch) throw SemanticSearchException('Setup stopped. Retry to continue.'.tr);
    AppLog.logI('Visual Search: starting installer with $python');
    final process = await Process.start(python, ['-B', '-u', _script, 'setup', _root]);
    _installer = process;
    if (epoch != _setupEpoch) _terminate(process);
    final lines = <String>[];
    var lastProgress = '';
    void receive(String line) {
      lines.add(line);
      if (lines.length > 8) lines.removeAt(0);
      if (epoch == _setupEpoch && line.startsWith('PROGRESS ')) {
        final message = line.substring(9);
        onProgress(translateSetupProgress(message));
        final percent = RegExp(r'(\d+)%').firstMatch(message);
        final key = percent == null ? message : '${message.substring(0, percent.start)}${int.parse(percent[1]!) ~/ 10}';
        if (key != lastProgress) {
          AppLog.logI('Visual Search: $message');
          lastProgress = key;
        }
      } else {
        AppLog.logD('Visual Search installer: $line');
      }
    }
    final stdout = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(receive);
    final stderr = process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(receive);
    try {
      final code = await process.exitCode.timeout(const Duration(minutes: 15));
      if (epoch != _setupEpoch) throw SemanticSearchException('Setup stopped. Retry to continue.'.tr);
      if (code != 0) throw SemanticSearchException('Setup failed. Check your connection, disk space and Python installation, then retry. @{last}'.trNamed({'last': '${lines.isEmpty ? '' : lines.last}'}));
    } on TimeoutException {
      _terminate(process);
      throw SemanticSearchException('Setup timed out. Retry setup to reuse downloaded files.'.tr);
    } finally {
      await stdout.cancel();
      await stderr.cancel();
      if (_installer == process) _installer = null;
    }
  }

  static Future<void> _start() async {
    if (_setup != null) throw SemanticSearchException('Visual Search setup is in progress.'.tr);
    if (_process != null) return;
    if (_starting != null) return _starting!;
    final future = _spawn();
    _starting = future;
    try { await future; } finally { _starting = null; }
  }

  static Future<void> _spawn() async {
    final epoch = _epoch;
    if (!await isReady()) throw SemanticSearchException('Set up Visual Search in Settings first.'.tr);
    final process = await Process.start(_python, ['-B', '-u', _script, 'serve', _root, Get.find<DBService>().dbMain.path]);
    if (epoch != _epoch) {
      process.kill();
      throw SemanticSearchException('Visual Search paused.'.tr);
    }
    _process = process;
    unawaited(process.stdin.done.catchError((Object error) {
      if (_process == process) stop(SemanticSearchException('Visual Search connection closed. Please retry.'.tr));
    }));
    var lastError = '';
    process.stderr.transform(utf8.decoder).listen((text) { lastError = text; });
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) async {
      if (_process != process) return;
      try {
        final message = (line.length > 65536 ? await compute(jsonDecode, line) : jsonDecode(line)) as Map<String, dynamic>;
        if (_process != process) return;
        final completer = _pending.remove(message['id']);
        if (completer == null) return;
        if (message['error'] != null) {
          completer.completeError(SemanticSearchException(message['error'].toString()));
        } else {
          completer.complete(message['result']);
        }
      } catch (_) {
        stop();
      }
    }, onError: (_) { if (_process == process) stop(); });
    unawaited(process.exitCode.then((_) {
      if (_process != process) return;
      stop(SemanticSearchException(lastError.isEmpty
          ? 'Visual Search stopped. Please retry.'.tr
          : 'Visual Search could not start. Use Repair setup in Settings.'.tr));
    }));
  }

  static void cancelRequests(Object owner) { _owners[owner] = (_owners[owner] ?? 0) + 1; }

  static Future<dynamic> request(String command, [Map<String, dynamic> arguments = const {}, Object? owner]) {
    final completer = Completer<dynamic>();
    final epoch = _epoch;
    final revision = owner == null ? 0 : (_owners[owner] ?? 0) + 1;
    if (owner != null) _owners[owner] = revision;
    _queued++;
    _idleTimer?.cancel();
    _queue = _queue.then((_) async {
      _queued--;
      if (epoch != _epoch || (owner != null && _owners[owner] != revision)) {
        completer.completeError(SemanticSearchException('Search superseded or paused.'.tr));
        return;
      }
      _command = command;
      try { completer.complete(await _send(command, arguments)); }
      catch (e, stack) { completer.completeError(e, stack); }
      finally { _command = null; }
    });
    return completer.future;
  }

  static Future<dynamic> _send(String command, Map<String, dynamic> arguments) async {
    _idleTimer?.cancel();
    await _start();
    _idleTimer?.cancel();
    final id = ++_nextId;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    try {
      _process!.stdin.writeln(jsonEncode({'id': id, 'command': command, ...arguments}));
      return await completer.future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      stop();
      throw SemanticSearchException('Visual Search timed out. Please retry.'.tr);
    } finally {
      _pending.remove(id);
      if (_pending.isEmpty && _queued == 0) _idleTimer = Timer(const Duration(seconds: 30), stop);
    }
  }

  static void _terminate(Process process) {
    process.kill();
    final timer = Timer(const Duration(seconds: 2), () { process.kill(ProcessSignal.sigkill); });
    unawaited(process.exitCode.then((_) { timer.cancel(); }));
  }

  static void interruptIndex() {
    if (_command == 'index' || _command == 'plan') stop();
  }

  static void cancelSetup() {
    _setupEpoch++;
    if (_installer != null) _terminate(_installer!);
  }

  static void stop([Object? error]) {
    _epoch++;
    _idleTimer?.cancel();
    final process = _process;
    _process = null;
    if (process != null) _terminate(process);
    for (final pending in _pending.values) {
      pending.completeError(error ?? SemanticSearchException('Visual Search paused.'.tr));
    }
    _pending.clear();
  }
}
