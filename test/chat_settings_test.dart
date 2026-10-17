import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:kuraku/app/core/app_pref.dart';
import 'package:kuraku/app/core/app_setting.dart';
import 'package:kuraku/app/modules/home/page_chat/page_chat_settings_dialog.dart';
import 'package:kuraku/app/modules/widgets/widget_controls.dart';
import 'package:kuraku/app/utils/chat_service.dart';

class _Preferences implements GetSecureStorage {
  _Preferences(this.storage);
  final GetSecureStorage storage;
  bool failSave = false;
  @override
  GetQueue get queue => storage.queue;
  @override
  T? read<T>(String key) => storage.read<T>(key);
  @override
  void writeInMemory(String key, dynamic value) => storage.writeInMemory(key, value);
  @override
  Future<void> save() async {
    if (failSave) throw const FileSystemException('Disk full');
    await storage.save();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('AI settings validate, cancel, persist and update an existing service', (tester) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('kuraku-ai-test-')))!;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    final pref = (await tester.runAsync(() async {
      final storage = GetSecureStorage(container: 'ai-test', password: 'test', path: directory.path);
      await storage.initStorage;
      return _Preferences(storage);
    }))!;
    Get.put<AppSettingService>(AppSettingService()..pref = pref);
    RequestOptions? request;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      request = options;
      handler.resolve(Response(requestOptions: options, data: ResponseBody.fromString(
        'data: {"choices":[{"delta":{"content":"SELECT 1"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n', 200)));
    }));
    final api = ChatService(dio: dio);
    addTearDown(() async {
      api.close();
      Get.reset();
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(GetMaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<void>(context: context,
        builder: (_) => const PageChatSettingsDialog()), child: const Text('Open')),
    ))));
    Future<void> open() async {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }
    Future<void> save() async {
      final action = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Save')).onPressed!;
      await tester.runAsync(() => (action as Future<void> Function())());
      await tester.pumpAndSettle();
    }
    Finder field(int index) => find.byType(CupertinoTextField).at(index);
    await open();
    expect(tester.widget<CupertinoTextField>(field(3)).obscureText, isTrue);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an API key in AI settings.'), findsOneWidget);
    await tester.enterText(field(3), 'test-key');
    for (final url in ['http://example.com/v1', 'https://user@example.com/v1', 'https://example.com/v1?key=secret', 'https://example.com/v1#fragment']) {
      await tester.enterText(field(1), url);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Base URL must be an HTTPS API base URL, such as https://api.example.com/v1.'), findsOneWidget);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(AppPref.getAiSettings()['apiKey'], isEmpty);
    await open();
    await tester.enterText(field(0), ' Other provider ');
    await tester.enterText(field(1), ' https://other.example/v1/ ');
    await tester.enterText(field(2), ' other-model ');
    await tester.enterText(field(3), ' test-key ');
    await save();
    expect(find.byType(PageChatSettingsDialog), findsNothing);
    expect(api.configurationError, isNull);
    expect(api.provider, 'Other provider');
    expect(api.baseUrl, 'https://other.example/v1');
    expect(api.model, 'other-model');
    expect(await tester.runAsync(() => api.generateSql('Read one', {'videos': ['id']}, CancelToken())), 'SELECT 1');
    expect(request!.uri.toString(), 'https://other.example/v1/chat/completions');
    expect(request!.headers['Authorization'], 'Bearer test-key');
    expect(request!.data['model'], 'other-model');
    await open();
    await tester.enterText(field(2), 'unsaved-model');
    pref.failSave = true;
    await save();
    expect(find.byType(PageChatSettingsDialog), findsOneWidget);
    expect(find.text('Could not save AI settings. Please retry.'), findsOneWidget);
    expect(api.model, 'other-model');
    pref.failSave = false;
    await save();
    expect(find.byType(PageChatSettingsDialog), findsNothing);
    expect(api.model, 'unsaved-model');
    await tester.runAsync(() async {
      await File('${directory.path}/ai-test.gs').copy('${directory.path}/ai-restored.gs');
      final restored = GetSecureStorage(container: 'ai-restored', password: 'test', path: directory.path);
      await restored.initStorage;
      expect(restored.read<Map>('ai_settings'), AppPref.getAiSettings());
    });
    await open();
    expect(tester.widget<CupertinoTextField>(field(3)).controller!.text, 'test-key');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
