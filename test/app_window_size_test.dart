import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraku/app/core/app_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  const screenChannel = MethodChannel('dev.leanflutter.plugins/screen_retriever');
  const display = {
    'id': 'main', 'size': {'width': 1440.0, 'height': 900.0},
    'visiblePosition': {'dx': 0.0, 'dy': 25.0}, 'visibleSize': {'width': 1440.0, 'height': 850.0},
  };
  final calls = <MethodCall>[];
  var currentSize = const Size(560, 450);
  var fullscreen = false;
  var maximized = false;

  setUp(() {
    calls.clear();
    fullscreen = false;
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isFullScreen') return fullscreen;
      if (call.method == 'isMaximized') return maximized;
      if (call.method == 'getBounds') return {'x': 0.0, 'y': 0.0, 'width': currentSize.width, 'height': currentSize.height};
      if (call.method == 'setBounds' && (call.arguments as Map).containsKey('width')) {
        currentSize = Size(call.arguments['width'], call.arguments['height']);
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(screenChannel, (call) async => switch (call.method) {
      'getPrimaryDisplay' => display,
      'getAllDisplays' => {'displays': [display]},
      'getCursorScreenPoint' => {'dx': 500.0, 'dy': 400.0},
      _ => null,
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(screenChannel, null);
  });

  test('standalone playback expands and centers the compact window', () async {
    currentSize = const Size(560, 450);
    await AppSettingService().setupStandalonePlayerWindow();
    expect(currentSize, const Size(1100, 700));
    expect(calls.last.arguments, containsPair('x', 170.0));
    expect(calls.last.arguments, containsPair('y', 100.0));
    expect(calls.any((call) => call.method == 'setMinimumSize'), isFalse);
  });

  test('standalone playback preserves larger dimensions without shrinking the window', () async {
    currentSize = const Size(1200, 600);
    await AppSettingService().setupStandalonePlayerWindow();
    expect(currentSize, const Size(1200, 700));
    calls.clear();
    await AppSettingService().setupStandalonePlayerWindow();
    expect(calls.any((call) => call.method == 'setBounds'), isFalse);
  });

  test('standalone playback leaves fullscreen and maximized windows alone', () async {
    fullscreen = true;
    await AppSettingService().setupStandalonePlayerWindow();
    expect(calls.map((call) => call.method), ['isFullScreen']);
    calls.clear();
    fullscreen = false;
    maximized = true;
    await AppSettingService().setupStandalonePlayerWindow();
    expect(calls.map((call) => call.method), ['isFullScreen', 'isMaximized']);
  });

  test('returning home restores and centers the default compact window', () async {
    currentSize = const Size(1100, 700);
    await AppSettingService().setupStandaloneHomeWindow();
    expect(currentSize, const Size(560, 450));
    expect(calls.last.arguments, containsPair('x', 440.0));
    expect(calls.last.arguments, containsPair('y', 225.0));
  });

  test('returning home unmaximizes before restoring the default size', () async {
    maximized = true;
    currentSize = const Size(1440, 850);
    await AppSettingService().setupStandaloneHomeWindow();
    expect(calls.map((call) => call.method), ['isFullScreen', 'isMaximized', 'unmaximize', 'setBounds', 'getBounds', 'setBounds']);
    expect(currentSize, const Size(560, 450));
  });

  test('returning home exits native fullscreen before restoring compact bounds', () async {
    fullscreen = true;
    currentSize = const Size(1440, 900);
    final settings = AppSettingService();
    await settings.setupStandaloneHomeWindow();
    expect(calls.map((call) => call.method), ['isFullScreen', 'setFullScreen']);
    expect(calls.last.arguments, containsPair('isFullScreen', false));
    fullscreen = false;
    await settings.setupStandaloneHomeWindow();
    expect(currentSize, const Size(560, 450));
  });

  test('unlock expands the compact player then centers its new size in the visible screen area', () async {
    currentSize = const Size(560, 450);
    await AppSettingService().setupLibraryWindow();
    expect(calls.map((call) => call.method), ['getBounds', 'setMinimumSize', 'setBounds', 'getBounds', 'setBounds']);
    expect(calls[1].arguments, containsPair('height', 700.0));
    expect(calls[2].arguments, containsPair('width', 746.0));
    expect(calls[2].arguments, containsPair('height', 700.0));
    expect(calls.last.arguments, containsPair('x', 347.0));
    expect(calls.last.arguments, containsPair('y', 100.0));
  });

  test('unlock preserves a player window that the user has enlarged', () async {
    currentSize = const Size(1000, 800);
    await AppSettingService().setupLibraryWindow();
    expect(currentSize, const Size(1000, 800));
    expect(calls.last.arguments, containsPair('x', 220.0));
    expect(calls.last.arguments, containsPair('y', 50.0));
  });
}
