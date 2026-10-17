import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'app_translations.dart';

class DependencyStatus {
  const DependencyStatus(this.name, this.feature, this.fix, {required this.ready, this.executable, this.detail = ''});
  final String name, feature, fix, detail;
  final bool ready;
  final String? executable;

  String get message => '@{dependency} is unavailable. @{fix}'.trNamed({'dependency': name, 'fix': fix.tr});
}

class DependencyException implements Exception {
  DependencyException(this.issues);
  final List<DependencyStatus> issues;
  @override
  String toString() => issues.map((issue) => issue.message).join('\n\n');
}

class AppDependencies {
  AppDependencies({Future<ProcessResult> Function(String, List<String>)? run, Future<bool> Function(String)? exists})
      : _run = run ?? _runProcess, _exists = exists ?? ((path) => File(path).exists());
  static final shared = AppDependencies();
  final Future<ProcessResult> Function(String, List<String>) _run;
  final Future<bool> Function(String) _exists;
  final _tools = <String, DependencyStatus>{};

  static Future<ProcessResult> _runProcess(String executable, List<String> arguments) async {
    final process = await Process.start(executable, arguments);
    final stdout = process.stdout.transform(const SystemEncoding().decoder).join();
    final stderr = process.stderr.transform(const SystemEncoding().decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 5));
      return ProcessResult(process.pid, code, await stdout, await stderr);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await Future.wait([stdout, stderr]);
      rethrow;
    }
  }

  List<String> _candidates(String executable) => [
    executable,
    if (Platform.isMacOS) ...['/opt/homebrew/bin/$executable', '/usr/local/bin/$executable'],
  ];

  Future<DependencyStatus> python({bool visualSearch = false}) async {
    var detail = '';
    final candidates = [
      ..._candidates('python3'),
      if (Platform.isMacOS || Platform.isLinux)
        for (final version in ['3.14', '3.13', '3.12']) ..._candidates('python$version'),
      if (Platform.isWindows) 'python',
    ];
    for (final candidate in candidates) {
      try {
        var executable = candidate;
        if (candidate == 'python3' && Platform.isMacOS) {
          for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
            final path = p.join(directory, candidate);
            if (!await _exists(path)) continue;
            // Avoid Apple's launcher prompting for Xcode tools on a clean Mac.
            if (path == '/usr/bin/python3') {
              final developer = await _run('/usr/bin/xcode-select', ['-p']);
              final python = p.join('${developer.stdout}'.trim(), 'usr/bin/python3');
              if (developer.exitCode != 0 || !await _exists(python)) executable = '';
              else executable = python;
            }
            break;
          }
        }
        if (executable.isEmpty) continue;
        final result = await _run(executable, ['-c', 'import sys; print("%d.%d" % sys.version_info[:2])']);
        final version = RegExp(r'^3\.(\d+)$').firstMatch('${result.stdout}'.trim());
        if (result.exitCode == 0 && version != null && (!visualSearch || int.parse(version[1]!) >= 12 && int.parse(version[1]!) <= 14)) {
          return DependencyStatus(visualSearch ? 'Python 3.12–3.14' : 'Python 3', visualSearch ? 'Visual Search setup' : 'R18 import and local Chat',
            visualSearch ? 'Install Python 3.12–3.14 with venv support and add it to PATH. See README for platform setup.' : 'Install Python 3 and add it to PATH. See README for platform setup.',
            ready: true, executable: executable, detail: '${result.stdout}'.trim());
        }
        detail = '$candidate: ${result.exitCode == 0 ? result.stdout : result.stderr}'.trim();
      } catch (e) { detail = '$candidate: $e'; }
    }
    return DependencyStatus(visualSearch ? 'Python 3.12–3.14' : 'Python 3', visualSearch ? 'Visual Search setup' : 'R18 import and local Chat',
      visualSearch ? 'Install Python 3.12–3.14 with venv support and add it to PATH. See README for platform setup.' : 'Install Python 3 and add it to PATH. See README for platform setup.', ready: false, detail: detail);
  }

  Future<String> requirePython({bool visualSearch = false}) async {
    final result = await python(visualSearch: visualSearch);
    if (!result.ready) throw StateError(result.message);
    return result.executable!;
  }

  Future<DependencyStatus> tool(String name, {bool refresh = false}) async {
    final feature = name == 'ffmpeg' ? 'HLS downloads, YouTube and visual thumbnails' : 'YouTube downloads';
    final fix = name == 'ffmpeg' ? 'Install FFmpeg and add it to PATH. See README for platform setup.' : 'Install yt-dlp and add it to PATH.';
    if (!refresh && _tools[name] != null) return _tools[name]!;
    var detail = '';
    for (final candidate in _candidates(name)) {
      try {
        final result = await _run(candidate, [name == 'ffmpeg' ? '-version' : '--version']);
        if (result.exitCode == 0) {
          return _tools[name] = DependencyStatus(name, feature, fix, ready: true, executable: candidate, detail: '${result.stdout}'.split('\n').first);
        }
        detail = '${result.stderr}'.trim();
      } catch (e) { detail = '$e'; }
    }
    return _tools[name] = DependencyStatus(name, feature, fix, ready: false, detail: detail);
  }

  Future<String> requireTool(String name) async {
    final result = await tool(name, refresh: true);
    if (!result.ready) throw StateError(result.message);
    return result.executable!;
  }

  Future<DependencyStatus> downloader(String assetsPath) async {
    final executable = p.join(assetsPath, Platform.isWindows ? 'windows-x64/kuraku.exe' : Platform.isLinux ? 'linux-x64/kuraku' : 'kuraku');
    var detail = '';
    try {
      final result = await _run(executable, ['--help']);
      if (result.exitCode == 0) return DependencyStatus('KuraKu downloader', 'Downloads', '', ready: true, executable: executable);
      detail = '${result.stderr}'.trim();
    } catch (e) { detail = '$e'; }
    return DependencyStatus('KuraKu downloader', 'Downloads',
      Platform.isWindows ? 'Reinstall KuraKu for Windows x64 if its bundled executable is missing or damaged.'
          : Platform.isLinux ? 'Reinstall KuraKu for Linux x64 and install libwebkit2gtk-4.1-0 if the downloader cannot start.'
          : 'The bundled downloader requires macOS 26+. Reinstall KuraKu if its bundled executable is missing or damaged.', ready: false, detail: detail);
  }

  Future<DependencyStatus> browser() async {
    var detail = '';
    for (final executable in Platform.isWindows
        ? [for (final directory in ['PROGRAMFILES', 'PROGRAMFILES(X86)', 'LOCALAPPDATA'])
            if (Platform.environment[directory] != null)
              for (final browser in ['Google/Chrome/Application/chrome.exe', 'Chromium/Application/chrome.exe'])
                p.joinAll([Platform.environment[directory]!, ...browser.split('/')])]
        : Platform.isLinux
        ? [for (final directory in (Platform.environment['PATH'] ?? '').split(':'))
            for (final name in ['google-chrome', 'chromium', 'chromium-browser']) p.join(directory, name)]
        : ['/Applications/Chromium.app/Contents/MacOS/Chromium', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']) {
      try {
        if (await _exists(executable)) return DependencyStatus('Chrome / Chromium', 'Website downloads', '', ready: true, executable: executable);
      } catch (e) { detail = '$e'; }
    }
    return DependencyStatus('Chrome / Chromium', 'Website downloads',
      'Install Google Chrome or Chromium for your desktop platform.', ready: false, detail: detail);
  }

  DependencyStatus playback() {
    try {
      MediaKit.ensureInitialized();
      return const DependencyStatus('libmpv', 'In-app playback', '', ready: true);
    } catch (e) {
      return DependencyStatus('libmpv', 'In-app playback', Platform.isLinux ? 'Install libmpv (Debian/Ubuntu: sudo apt install libmpv-dev).' : 'Reinstall KuraKu to restore its bundled media libraries.', ready: false, detail: '$e');
    }
  }

  Future<List<DependencyStatus>> libraries() async {
    final results = <DependencyStatus>[];
    if (Platform.isMacOS) {
      try {
        DynamicLibrary.open('/usr/lib/libiconv.2.dylib');
        results.add(const DependencyStatus('libiconv', 'Native media libraries', '', ready: true, detail: '/usr/lib/libiconv.2.dylib'));
      } catch (e) {
        results.add(DependencyStatus('libiconv', 'Native media libraries',
          'The macOS system library could not load. Update macOS and reinstall KuraKu; Homebrew libiconv is not required.', ready: false, detail: '$e'));
      }
    }
    results.add(playback());
    try {
      final version = await FFmpegKitConfig.getFFmpegVersion().timeout(const Duration(seconds: 5));
      if (version == null || version.isEmpty) throw StateError('No bundled FFmpeg version returned');
      results.add(DependencyStatus('FFmpegKit', 'Thumbnails and video metadata', '', ready: true, detail: version));
    } catch (e) {
      results.add(DependencyStatus('FFmpegKit', 'Thumbnails and video metadata', 'Reinstall KuraKu to restore its bundled media libraries.', ready: false, detail: '$e'));
    }
    return results;
  }

  Future<List<DependencyStatus>> checkAll(String assetsPath) async {
    _tools.clear();
    final native = libraries();
    final results = await Future.wait([python(), python(visualSearch: true), tool('ffmpeg'), tool('yt-dlp'), downloader(assetsPath), browser()]);
    return [...await native, ...results];
  }
}
