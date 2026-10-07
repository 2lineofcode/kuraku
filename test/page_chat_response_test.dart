import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/modules/home/page_chat/page_chat_controller.dart';
import 'package:javit/app/utils/chat_service.dart';

import 'chat_test_database.dart';

class _ChatApi extends ChatService {
  _ChatApi() : super(apiKey: 'test-key', model: 'test-model', provider: 'Current provider');
  final requests = <List<Map<String, String>>>[];
  bool fail = false;
  bool wait = false;
  bool local = false;
  @override
  bool canReplyLocally(String text) => local;
  void Function()? beforeFinish;
  Completer<void> started = Completer();
  @override
  Stream<String> reply(List<Map<String, String>> messages, CancelToken cancelToken) async* {
    requests.add(messages);
    yield 'Partial';
    if (!started.isCompleted) started.complete();
    if (wait) await cancelToken.whenCancel;
    if (fail || cancelToken.isCancelled) throw const ChatException('Test interruption');
    yield ' answer';
    beforeFinish?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Regeneration excludes the replaced answer, keeps it on failure or stop, and reload saves pending drafts', () async {
    addTearDown(Get.reset);
    final db = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = db);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi();
    final controller = Get.put(PageChatController(api: api));
    await controller.reload();
    controller.input.text = 'First question';
    await controller.send();
    controller.input.text = 'Follow-up question';
    await controller.send();
    final chat = controller.activeChat.value;
    final previous = chat.messages.last;
    controller.input.text = 'Unsent draft';
    controller.editMessage(chat.messages.first);
    await controller.retryResponse();
    expect(api.requests, hasLength(2));
    controller.cancelEdit();
    api.fail = true;
    await controller.retryResponse();
    expect(chat.messages, hasLength(4));
    expect(chat.messages.last, same(previous));
    expect(chat.messages.last.status, 'completed');
    expect(db.rows['chat_message']!.last['content'], previous.content);
    expect(api.requests.last, [
      {'role': 'user', 'content': 'First question'},
      {'role': 'assistant', 'content': 'Partial answer'},
      {'role': 'user', 'content': 'Follow-up question'},
    ]);
    expect(controller.commandNotice.value, contains('previous answer was kept'));
    api..fail = false..wait = true..started = Completer();
    final generation = controller.retryResponse();
    await api.started.future;
    expect(db.rows['chat_message']!.last['status'], 'completed');
    await controller.newChat();
    await controller.stopResponse();
    await generation;
    expect(chat.messages.last, same(previous));
    expect(controller.messages, isEmpty);
    await controller.selectChat(chat);
    expect(controller.input.text, 'Unsent draft');
    api..wait = false..local = true;
    await controller.retryResponse();
    expect(chat.messages.last.id, previous.id);
    expect(chat.messages.last.provider, 'local');
    expect(db.rows['chat_message']!.last['provider'], 'local');
    expect(db.rows['chat_message']!.last['model'], isNull);
    expect(chat.messages, hasLength(4));
    controller.input.text = 'Draft before reload';
    db.failWrites = true;
    expect(await controller.reload(), isFalse);
    expect(controller.activeChat.value, same(chat));
    expect(controller.input.text, 'Draft before reload');
    db.failWrites = false;
    expect(await controller.reload(), isTrue);
    expect(controller.input.text, 'Draft before reload');
    expect(controller.messages.last.id, previous.id);
  });

  test('Responses persist, retry excludes failed attempts, and switching chat cannot misroute a stopped response', () async {
    final db = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = db);
    Get.put(AppSettingService()..pref = ChatTestPreferences());
    final api = _ChatApi()..fail = true;
    final controller = Get.put(PageChatController(api: api));
    addTearDown(Get.reset);
    await controller.reload();
    controller.input.text = 'First question';
    await controller.send();
    final first = controller.activeChat.value;
    expect(first.messages.last.status, 'failed');
    expect(first.messages.last.content, 'Partial');
    expect(db.rows['chat_message']!.last['status'], 'failed');
    expect(first.messages.last.provider, 'Current provider');
    first.messages.last..provider = 'Old provider'..model = 'old-model';
    db.rows['chat_message']!.last.addAll({'provider': 'Old provider', 'model': 'old-model'});
    api.fail = false;
    await controller.retryResponse();
    expect(first.messages.where((message) => message.role == 'user').length, 1);
    expect(first.messages.last.content, 'Partial answer');
    expect(first.messages.last.status, 'completed');
    expect(first.messages.last.provider, 'Current provider');
    expect(first.messages.last.model, 'test-model');
    expect(db.rows['chat_message']!.last['provider'], 'Current provider');
    expect(db.rows['chat_message']!.last['model'], 'test-model');
    expect(api.requests.last, [{'role': 'user', 'content': 'First question'}]);
    api.wait = true;
    api.started = Completer();
    controller.input.text = 'Second question';
    final generation = controller.send();
    await api.started.future;
    await controller.newChat();
    expect(controller.activeChat.value, isNot(same(first)));
    expect(controller.messages, isEmpty);
    await controller.stopResponse();
    await generation;
    expect(first.messages.last.status, 'cancelled');
    expect(first.messages.last.content, 'Partial');
    expect(db.rows['chat_message']!.last['status'], 'cancelled');
    expect(controller.messages, isEmpty);
    await controller.selectChat(first);
    expect(controller.messages.last.status, 'cancelled');
    expect(controller.respondingChatId.value, isNull);
    api.wait = false;
    api.beforeFinish = () => db.failWrites = true;
    controller.input.text = 'Save failure question';
    await controller.send();
    expect(controller.messages.last.content, 'Partial answer');
    expect(controller.error.value, isNotEmpty);
    await controller.newChat();
    expect(controller.activeChat.value, same(first));
    db.failWrites = false;
    api.beforeFinish = null;
    expect(await controller.retry(), isTrue);
    await controller.reload();
    expect(controller.messages.last.content, 'Partial answer');
    expect(controller.messages.last.status, 'completed');
    api.local = true;
    controller.input.text = 'Local question';
    await controller.send();
    expect(controller.messages.last.provider, 'local');
    expect(controller.messages.last.model, isNull);
    expect(db.rows['chat_message']!.last['provider'], 'local');
    expect(db.rows['chat_message']!.last['model'], isNull);
    await controller.flushDraft();
  });
}
