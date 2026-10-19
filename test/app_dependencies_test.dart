import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_dependencies.dart';
import 'package:kuraku/app/modules/widgets/widget_dependency_guide.dart';

void main() {
  testWidgets('Startup check leaves Home visible and shows no UI when all dependencies are ready', (tester) async {
    addTearDown(Get.reset);
    final pending = Completer<List<DependencyStatus>>();
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: Text('Home ready'))));
    final check = showStartupDependencyGuide(check: () => pending.future);
    await tester.pump();
    expect(find.text('Home ready'), findsOneWidget);
    expect(find.byType(DependencyGuide), findsNothing);
    pending.complete(const [DependencyStatus('ffmpeg', '', '', ready: true)]);
    await check;
    await tester.pumpAndSettle();
    expect(find.byType(DependencyGuide), findsNothing);
  });

  test('Browser detection checks executable paths without launching a browser', () async {
    final checker = AppDependencies(
      exists: (path) async => Platform.isWindows && path.endsWith(r'Google\Chrome\Application\chrome.exe') || path == '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' || Platform.isLinux && path.endsWith('/google-chrome'),
      run: (_, _) => throw StateError('Must not launch Chrome during startup'),
    );
    expect((await checker.browser()).ready, isTrue);
    final missing = AppDependencies(exists: (_) async => false);
    expect((await missing.browser()).message, contains('Install Google Chrome or Chromium for your desktop platform.'));
    final unreadable = AppDependencies(exists: (path) async => throw FileSystemException('Permission denied', path));
    expect((await unreadable.browser()).ready, isFalse);
  });

  test('Python version checks skip unsupported defaults and find versioned Homebrew Python', () async {
    final calls = <String>[];
    final checker = AppDependencies(run: (executable, args) async {
      calls.add(executable);
      if (executable == 'python3') return ProcessResult(1, 0, '3.15\n', '');
      if (executable == '/opt/homebrew/bin/python3.13') return ProcessResult(1, 0, '3.13\n', '');
      throw ProcessException(executable, args);
    });
    expect((await checker.python()).executable, 'python3');
    if (Platform.isMacOS) {
      expect(await checker.requirePython(visualSearch: true), '/opt/homebrew/bin/python3.13');
      expect(calls, contains('python3.14'));
    }
  });

  test('Missing and broken Python produce an actionable error', () async {
    final checker = AppDependencies(run: (executable, args) async => ProcessResult(1, 1, '', 'broken runtime'));
    final result = await checker.python();
    expect(result.ready, isFalse);
    expect(result.detail, contains('broken runtime'));
    await expectLater(checker.requirePython(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Install Python 3 and add it to PATH.'))));
  });

  test('R18 and Chat find versioned Python after following the installation guideline', () async {
    if (!Platform.isMacOS) return;
    final checker = AppDependencies(run: (executable, args) async {
      if (executable == '/opt/homebrew/bin/python3.13') return ProcessResult(1, 0, '3.13\n', '');
      throw ProcessException(executable, args);
    });
    expect(await checker.requirePython(), '/opt/homebrew/bin/python3.13');
  });

  test('Missing Python never invokes the Apple launcher that offers Xcode installation', () async {
    if (!Platform.isMacOS) return;
    final calls = <String>[];
    final checker = AppDependencies(
      exists: (path) async => path == '/usr/bin/python3',
      run: (executable, args) async {
        calls.add(executable);
        if (executable == '/usr/bin/xcode-select') return ProcessResult(1, 1, '', 'No developer tools');
        if (executable == '/opt/homebrew/bin/python3.13') return ProcessResult(1, 0, '3.13\n', '');
        throw ProcessException(executable, args);
      },
    );
    expect(await checker.requirePython(), '/opt/homebrew/bin/python3.13');
    expect(calls, contains('/usr/bin/xcode-select'));
    expect(calls, isNot(contains('python3')));
  });

  test('Tool detection finds Homebrew, caches failures for thumbnails, and rechecks before use', () async {
    var installed = false;
    var calls = 0;
    final checker = AppDependencies(run: (executable, args) async {
      calls++;
      if (installed && executable == (Platform.isMacOS ? '/opt/homebrew/bin/ffmpeg' : 'ffmpeg')) return ProcessResult(1, 0, 'ffmpeg version test\n', '');
      throw ProcessException(executable, args);
    });
    expect((await checker.tool('ffmpeg')).ready, isFalse);
    final before = calls;
    expect((await checker.tool('ffmpeg')).ready, isFalse);
    expect(calls, before);
    installed = true;
    expect(await checker.requireTool('ffmpeg'), Platform.isMacOS ? '/opt/homebrew/bin/ffmpeg' : 'ffmpeg');
    expect((await checker.tool('ffmpeg')).ready, isTrue);
  });

  test('Downloader must actually run; a present but incompatible binary is unavailable', () async {
    final checker = AppDependencies(run: (executable, args) async {
      final relative = Platform.isWindows ? 'windows-x64/kuraku.exe' : Platform.isLinux ? 'linux-x64/kuraku' : 'macos-arm64/kuraku';
      expect(executable.replaceAll('\\', '/'), '/bundle/assets/bin/$relative');
      return ProcessResult(1, 1, '', 'incompatible architecture');
    });
    final result = await checker.downloader('/bundle/assets');
    expect(result.ready, isFalse);
    expect(result.detail, 'incompatible architecture');
    expect(result.fix, contains('Reinstall KuraKu'));
  });

  testWidgets('Guideline only lists missing dependencies and can recheck after installation', (tester) async {
    var ready = false;
    var continued = false;
    const missing = DependencyStatus('ffmpeg', 'HLS downloads, YouTube and visual thumbnails', 'Install FFmpeg and add it to PATH. See README for platform setup.', ready: false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DependencyGuide(
      issues: const [missing],
      check: () async => [const DependencyStatus('ffmpeg', '', '', ready: true)],
      onReady: () => ready = true,
      onContinue: () => continued = true,
    ))));
    expect(find.text('Install missing dependencies'), findsOneWidget);
    expect(find.textContaining('Install FFmpeg and add it to PATH.'), findsOneWidget);
    expect(find.textContaining('Homebrew'), findsNothing);
    expect(find.textContaining('yt-dlp'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(continued, isTrue);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(ready, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.windows}));

  testWidgets('Required startup dependencies have no Continue action and tolerate a narrow window', (tester) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const missing = DependencyStatus('libmpv', 'In-app playback', 'Reinstall KuraKu to restore its bundled media libraries.', ready: false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DependencyGuide(
      issues: const [missing], check: () async => [missing], onReady: () {},
    ))));
    expect(find.text('Continue'), findsNothing);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('libmpv'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
