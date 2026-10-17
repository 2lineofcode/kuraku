import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_translations.dart';

class DownloadRequest {
  const DownloadRequest({required this.url, required this.directory, this.filename = '', this.mode = 'extract', this.concurrency = 8, this.retries = 3, this.timeout = 30, this.referer = '', this.userAgent = '', this.headless = false, this.captureDuration = 20, this.playSelector = '', this.allowPopups = false});

  final String url, directory, filename, mode, referer, userAgent, playSelector;
  final int concurrency, retries, timeout, captureDuration;
  final bool headless, allowPopups;

  void validate() {
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) throw FormatException('Enter a valid HTTP(S) URL.'.tr);
    if (!['extract', 'auto', 'hls', 'file', 'youtube'].contains(mode)) throw FormatException('Invalid download mode.'.tr);
    if (!p.isAbsolute(directory) || !Directory(directory).existsSync()) throw FormatException('Choose an existing output folder.'.tr);
    if (filename.isEmpty && mode != 'extract') throw FormatException('Enter an output filename.'.tr);
    if (filename.isNotEmpty && (filename == '.' || filename == '..' || RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(filename) || filename.endsWith('.') || filename.trim() != filename)) throw FormatException('Use a filename without path separators or reserved characters.'.tr);
    if (Platform.isWindows && RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)', caseSensitive: false).hasMatch(filename)) throw FormatException('Use a filename without path separators or reserved characters.'.tr);
    if (concurrency < 1 || concurrency > 64 || retries < 0 || retries > 10 || timeout < 1 || captureDuration < 1) throw FormatException('Concurrency: 1–64, retries: 0–10; durations must be positive.'.tr);
    if (referer.isNotEmpty) {
      final ref = Uri.tryParse(referer);
      if (ref == null || !['http', 'https'].contains(ref.scheme) || ref.host.isEmpty) throw FormatException('Referer must be an HTTP(S) URL.'.tr);
    }
  }

  List<String> arguments(String cache) => [
    if (mode != 'auto') mode,
    url,
    if (filename.isNotEmpty) ...['-o', p.join(directory, filename)],
    '--retries', '$retries', '--timeout', '${timeout}s',
    if (referer.isNotEmpty) ...['--referer', referer],
    if (userAgent.isNotEmpty) ...['--user-agent', userAgent],
    if (['auto', 'hls', 'extract'].contains(mode)) ...['--auto', '--concurrency', '$concurrency', '--temp', cache],
    if (mode == 'extract') ...[
      if (headless) ...['--headless', '--capture-duration', '${captureDuration}s'],
      if (playSelector.isNotEmpty) ...['--play-selector', playSelector],
      if (allowPopups) '--allow-popups',
    ],
  ];
}

class DownloadCandidate {
  const DownloadCandidate(this.index, this.type, this.url);
  final int index;
  final String type, url;
  bool get supported => type == 'HLS' || type == 'FILE';
}

class PageDownloadJob {
  PageDownloadJob({this.onChanged});
  final void Function()? onChanged;
  Process? process;
  bool running = false, cancelled = false, selecting = false, captureReady = false;
  String status = 'Ready', outputPath = '', error = '', progressText = '';
  double? progress;
  int? exitCode;
  final logs = <String>[];
  final candidates = <DownloadCandidate>[];
  String _directory = '';
  bool _completed = false, _headless = false, _interactive = false;
  Timer? _deadline, _forceKill;

  void _notify() => onChanged?.call();

  Future<void> start(DownloadRequest request, {required String binary, required String cache, Map<String, String>? environment, Duration deadline = const Duration(hours: 6)}) async {
    if (running) throw StateError('A download is already active.'.tr);
    request.validate();
    running = true;
    cancelled = false;
    selecting = false;
    captureReady = false;
    _directory = request.directory;
    _headless = request.headless;
    _interactive = request.mode == 'extract';
    _completed = false;
    status = 'Starting';
    error = outputPath = progressText = '';
    progress = null;
    exitCode = null;
    logs.clear();
    candidates.clear();
    _notify();
    try {
      process = await Process.start(binary, request.arguments(cache), workingDirectory: request.directory, environment: environment);
      _deadline = Timer(deadline, () {
        error = 'Download deadline reached.'.tr;
        cancel();
      });
      if (cancelled) {
        unawaited(_terminate(process!));
        _scheduleForceKill();
      }
      if (request.mode != 'extract') await process!.stdin.close();
      final stdout = _consume(process!.stdout);
      final stderr = _consume(process!.stderr);
      exitCode = await process!.exitCode;
      await Future.wait([stdout, stderr]);
      if (cancelled) {
        status = error.isEmpty ? 'Cancelled' : 'Failed';
      } else if (exitCode == 0 && _completed && await _validOutput(request)) {
        status = 'Completed';
        progress = 1;
      } else {
        status = 'Failed';
        if (error.isEmpty) error = exitCode == 0 ? 'No completed download was published.'.tr : 'Downloader exited with code @{exitCode}. Check the log.'.trNamed({'exitCode': '$exitCode'});
      }
    } catch (e) {
      status = cancelled ? 'Cancelled' : 'Failed';
      error = '$e';
    } finally {
      _deadline?.cancel();
      _forceKill?.cancel();
      process = null;
      running = selecting = false;
      _notify();
    }
  }

  Future<bool> _validOutput(DownloadRequest request) async {
    if (!p.isAbsolute(outputPath) || !p.isWithin(request.directory, outputPath)) return false;
    if (await FileSystemEntity.type(outputPath, followLinks: false) != FileSystemEntityType.file) return false;
    final file = File(outputPath);
    if (await file.length() == 0) return false;
    final handle = await file.open();
    try {
      final prefix = utf8.decode(await handle.read(512), allowMalformed: true).trimLeft().toLowerCase();
      if (request.mode != 'file' && (prefix.startsWith('<!doctype html') || prefix.startsWith('<html'))) {
        error = 'The source returned HTML. Use Website mode to capture its media.'.tr;
        return false;
      }
    } finally {
      await handle.close();
    }
    return true;
  }

  Future<void> _consume(Stream<List<int>> stream) async {
    var pending = '';
    await for (final chunk in stream.transform(const Utf8Decoder(allowMalformed: true))) {
      pending += chunk;
      final lines = pending.split(RegExp(r'[\r\n]'));
      pending = lines.removeLast();
      for (final line in lines) {
        if (line.trim().isNotEmpty) acceptLine(line.trim());
      }
      // Prompts are not newline terminated. Never approve replacement implicitly.
      if (pending.contains('Overwrite? [y/N]:')) {
        if (_interactive && process != null) process!.stdin.writeln('n');
        error = 'Output already exists. Choose another filename.';
        acceptLine(pending.trim());
        pending = '';
      }
      if (pending.length > 16384) {
        acceptLine(pending.substring(0, 16384));
        pending = '';
      }
    }
    if (pending.trim().isNotEmpty) acceptLine(pending.trim());
  }

  void acceptLine(String line) {
    logs.add(line);
    if (logs.length > 200) logs.removeAt(0);
    final candidate = RegExp(r'^\[(\d+)\] \[([^\]]+)\] (https?://\S+)').firstMatch(line);
    if (candidate != null) {
      final item = DownloadCandidate(int.parse(candidate[1]!), candidate[2]!, candidate[3]!);
      candidates.removeWhere((c) => c.index == item.index);
      candidates.add(item);
      selecting = true;
      status = 'Choose media';
    }
    if (line.contains('Capturing media in the background')) {
      candidates.clear();
      selecting = false;
      captureReady = false;
      status = 'Capturing media';
    }
    if (line.contains('Complete any login')) status = 'Waiting for playback';
    if (line.contains('Capture complete.')) captureReady = true;
    if (line.contains('visible browser') || line.contains('Opening browser') || line.contains('Opening the browser')) {
      _headless = false;
      captureReady = true;
      candidates.clear();
      selecting = false;
      status = 'Capturing media';
      progressText = '';
      progress = null;
    }
    if (line.startsWith('Downloading:') || line.startsWith('Resources:') || line.startsWith('[download]')) {
      selecting = false;
      status = 'Downloading';
      progressText = line;
      final percent = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(line);
      progress = percent == null ? null : (double.parse(percent[1]!) / 100).clamp(0, 1);
    }
    if (line.contains('Remuxing to MP4')) {
      selecting = false;
      status = 'Remuxing';
      progressText = line;
      progress = null;
    }
    if (line.startsWith('Save to: ')) outputPath = _resolveOutput(line.substring(9).trim());
    final completed = RegExp(r'^Downloaded (.+) \([^)]+\)$').firstMatch(line);
    if (completed != null) {
      outputPath = _resolveOutput(completed[1]!);
      _completed = true;
    }
    if (!cancelled && line.startsWith('Error:')) error = line.substring(6).trim();
    _notify();
  }

  String _resolveOutput(String path) => p.normalize(p.isAbsolute(path) ? path : p.join(_directory, path));

  bool get canSelect => running && selecting && (!_headless || captureReady) && !cancelled;

  Future<void> select(DownloadCandidate candidate) async {
    if (!canSelect || !candidate.supported || !candidates.contains(candidate)) return;
    process!.stdin.writeln(candidate.index);
    await process!.stdin.flush();
    selecting = false;
    status = 'Starting media download';
    candidates.clear();
    _notify();
  }

  void reset() {
    if (running) return;
    status = 'Ready';
    outputPath = error = progressText = '';
    progress = null;
    exitCode = null;
    cancelled = selecting = captureReady = _completed = false;
    logs.clear();
    candidates.clear();
    _notify();
  }

  Future<void> _terminate(Process active) async {
    if (Platform.isWindows) {
      try {
        // Kill FFmpeg/Chrome children before the downloader disappears.
        final result = await Process.run('taskkill.exe', ['/PID', '${active.pid}', '/T', '/F']).timeout(const Duration(seconds: 10));
        if (result.exitCode != 0) active.kill();
      } catch (_) {
        active.kill();
      }
    } else {
      active.kill(ProcessSignal.sigterm);
    }
  }

  void _scheduleForceKill() {
    final active = process;
    _forceKill = Timer(const Duration(seconds: 15), () => active?.kill(ProcessSignal.sigkill));
  }

  void cancel() {
    if (!running || cancelled) return;
    cancelled = true;
    status = 'Cancelling';
    if (process != null) unawaited(_terminate(process!));
    if (process != null) _scheduleForceKill();
    _notify();
  }
}
