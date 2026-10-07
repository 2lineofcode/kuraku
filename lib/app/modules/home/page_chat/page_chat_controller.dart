import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../core/app_pref.dart';
import '../../../core/app_translations.dart';
import '../../../data/database/_init_db.dart';
import '../../../data/database/db_chat.dart';
import '../../../data/models/chat_entity.dart';
import '../../../utils/chat_knowledge.dart';
import '../../../utils/chat_service.dart';

class PageChatController extends GetxController {
  PageChatController({ChatService? api}) : api = api ?? ChatService(knowledge: ChatKnowledge(
    mainPath: Get.find<DBService>().dbMain.path, resolveR18Path: () => Get.find<DBService>().dbR18?.path,
    loadScript: () => rootBundle.loadString('assets/chat_database_worker.py'),
  ));
  final ChatService api;
  final respondingChatId = RxnString();
  CancelToken? _responseToken;
  CancelToken? _pageToken;
  final _translationTokens = <CancelToken>{};
  final _translations = <String, Future<String>>{};
  final loadingPageId = RxnString();
  Future<void>? _generation;
  ChatMessage? _unsavedReply;
  final input = TextEditingController();
  final editInput = TextEditingController();
  final editingMessageId = RxnString();
  final searchInput = TextEditingController();
  final focusNode = FocusNode();
  final searchFocusNode = FocusNode();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final scrollController = ScrollController();
  final showLatest = false.obs;
  final chats = <ChatConversation>[ChatConversation()].obs;
  late final activeChat = chats.first.obs;
  final search = ''.obs;
  final sidebarVisible = true.obs;
  final busy = false.obs;
  final ready = false.obs;
  final error = ''.obs;
  final commandNotice = ''.obs;
  final commandQuery = ''.obs;
  final commandIndex = 0.obs;
  Timer? _draftTimer;
  Future<void> _pending = Future.value();
  int _operations = 0;
  bool _restoring = false;

  List<ChatMessage> get messages => activeChat.value.messages;

  static const commands = {
    '/new': 'Start a new chat',
    '/stop': 'Stop the current response',
    '/r18': 'Template: Japanese-only R18 titles',
    '/filter': 'Template: required themes, exclusions and unowned videos',
    '/similar': 'Template: find similar themes by video code',
    '/translate': 'Template: translate a Japanese title into Indonesian',
    '/clear': 'Delete messages and draft in this chat',
  };

  List<String> get matchingCommands => commandQuery.value.isEmpty ? []
      : commands.keys.where((name) => name.startsWith(commandQuery.value)).toList();

  void moveCommand(int offset) {
    final matches = matchingCommands;
    if (matches.isNotEmpty) commandIndex.value = (commandIndex.value + offset) % matches.length;
  }

  void completeCommand() {
    final matches = matchingCommands;
    if (matches.isNotEmpty) usePrompt(matches[commandIndex.value.clamp(0, matches.length - 1)]);
  }

  Future<void> submitInput() async {
    if (!input.value.composing.isCollapsed) return;
    if (matchingCommands.isNotEmpty) completeCommand();
    await send();
  }

  Future<void> _command(String text) async {
    final name = text.toLowerCase();
    if (!commands.containsKey(name)) {
      commandNotice.value = 'Unknown command. Type / to see available commands.'.tr;
      return;
    }
    if (_unsavedReply != null && !await flushDraft()) return;
    if (name == '/clear') {
      final chat = activeChat.value;
      if (respondingChatId.value == chat.id) await stopResponse();
      _draftTimer?.cancel();
      await _run(() async {
        await DBChat.clear(chat);
        if (_unsavedReply?.conversationId == chat.id) _unsavedReply = null;
        if (activeChat.value == chat) {
          _activate(chat);
          commandNotice.value = 'Messages and draft cleared.'.tr;
        }
      });
      return;
    }
    input.clear();
    commandNotice.value = '';
    switch (name) {
      case '/stop':
        final running = respondingChatId.value != null;
        await stopResponse();
        commandNotice.value = running ? 'Response stopped.'.tr : 'No response is running.'.tr;
      case '/new':
        await newChat();
      case '/r18':
      case '/filter':
      case '/similar':
      case '/translate':
        useTemplate(name);
    }
    focusNode.requestFocus();
  }

  @override
  void onInit() {
    super.onInit();
    input.addListener(_draftChanged);
    scrollController.addListener(() => showLatest.value = scrollController.offset > 160);
    reload();
  }

  Future<bool> _run(Future<void> Function() action, {bool block = true}) {
    if (block) {
      _operations++;
      busy.value = true;
    }
    final result = _pending.then((_) async {
      try {
        await action();
        error.value = '';
        return true;
      } catch (failure) {
        AppLog.logW('Chat operation failed: $failure');
        error.value = 'Could not load or save chat. Please retry.'.tr;
        return false;
      } finally {
        if (block) busy.value = --_operations > 0;
      }
    });
    _pending = result.then((_) {});
    return result;
  }

  Future<bool> reload() async {
    await stopResponse();
    if (ready.value && !await flushDraft()) return false;
    return _run(() async {
    final saved = await DBChat.getConversations();
    final selected = saved.firstWhereOrNull((chat) => chat.id == AppPref.getActiveChat());
    final next = selected ?? (saved.isEmpty ? ChatConversation() : saved.first);
    if (next.persisted) next.messages.addAll(await DBChat.getMessages(next.id));
    chats.assignAll(saved.isEmpty ? [next] : saved);
    sidebarVisible.value = AppPref.getChatSidebarVisible();
    _activate(next);
    ready.value = true;
    });
  }

  void _draftChanged() {
    final text = input.text.trimLeft().toLowerCase();
    final query = RegExp(r'^/[^\s]*$').hasMatch(text) ? text : '';
    if (query != commandQuery.value) {
      commandQuery.value = query;
      commandIndex.value = 0;
    }
    if (_restoring || !ready.value) return;
    final chat = activeChat.value;
    chat.draft = input.text;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 350), () {
      _run(() => _persistDraft(chat), block: false);
    });
  }

  Future<void> _persistDraft(ChatConversation chat) async {
    if (_unsavedReply != null) {
      await DBChat.saveAssistant(_unsavedReply!);
      _unsavedReply = null;
    }
    if (!chats.contains(chat)) return;
    if (!chat.persisted && chat.draft.trim().isEmpty && chat.title == 'New chat') return;
    await DBChat.saveConversation(chat);
  }

  Future<bool> flushDraft() {
    _draftTimer?.cancel();
    return _run(() async {
      if (ready.value) await _persistDraft(activeChat.value);
    });
  }

  Future<bool> retry() => ready.value ? flushDraft() : reload();

  Future<void> send() async {
    if (busy.value || !ready.value || editingMessageId.value != null || input.text.trim().isEmpty) return;
    if (input.text.trim().startsWith('/')) {
      await _command(input.text.trim());
      return;
    }
    if (respondingChatId.value != null) return;
    commandNotice.value = '';
    final fields = templateFields(input.text);
    if (fields.isNotEmpty) {
      selectTemplateField();
      commandNotice.value = 'Fill in the template fields before sending.'.tr;
      return;
    }
    if (api.configurationError != null && !api.canReplyLocally(input.text)) {
      error.value = api.configurationError!;
      return;
    }
    if (_unsavedReply != null && !await flushDraft()) return;
    _draftTimer?.cancel();
    final text = input.text;
    final chat = activeChat.value;
    final saved = await _run(() async {
      final message = await DBChat.send(chat, text);
      if (input.text != text) chat.draft = input.text;
      chat.messages.add(message);
      _sortChats();
      _activate(chat);
      await AppPref.setActiveChat(chat.id);
    });
    if (saved) await _startResponse(chat);
  }

  void _sortChats() {
    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final recent = b.lastActivityAt.compareTo(a.lastActivityAt);
      return recent != 0 ? recent : a.id.compareTo(b.id);
    });
  }

  void editMessage(ChatMessage message) {
    if (busy.value || !ready.value || respondingChatId.value != null || message.role != 'user' || !messages.contains(message)) return;
    editInput.text = message.content;
    editingMessageId.value = message.id;
  }

  void cancelEdit() {
    editingMessageId.value = null;
    editInput.clear();
  }

  Future<void> submitEdit() async {
    if (busy.value || !ready.value || respondingChatId.value != null) return;
    final chat = activeChat.value;
    final id = editingMessageId.value;
    final text = editInput.text.trim();
    if (id == null || text.isEmpty) return;
    if (templateFields(text).isNotEmpty) {
      commandNotice.value = 'Fill in the template fields before sending.'.tr;
      return;
    }
    if (api.configurationError != null && !api.canReplyLocally(text)) {
      error.value = api.configurationError!;
      return;
    }
    _draftTimer?.cancel();
    final saved = await _run(() async {
      await _persistDraft(chat);
      final edited = await DBChat.editUserMessage(chat, id, text);
      chat.messages.removeWhere((message) => message.position >= edited.position);
      chat.messages.add(edited);
      _sortChats();
      _activate(chat);
    });
    if (saved) await _startResponse(chat);
  }

  Future<void> togglePin(ChatConversation chat) async {
    if (busy.value || !ready.value) return;
    _draftTimer?.cancel();
    await _run(() async {
      await _persistDraft(activeChat.value);
      await DBChat.setPinned(chat, !chat.isPinned);
      _sortChats();
      chats.refresh();
      if (activeChat.value == chat) activeChat.refresh();
    });
  }

  Future<void> retryResponse() async {
    if (busy.value || respondingChatId.value != null || !ready.value || editingMessageId.value != null) return;
    final chat = activeChat.value;
    final question = chat.messages.where((message) => message.role == 'user').lastOrNull;
    if (question == null) return;
    if (api.configurationError != null && !api.canReplyLocally(question.content)) {
      error.value = api.configurationError!;
      return;
    }
    if (!await flushDraft()) return;
    await _startResponse(chat);
  }

  Future<void> _startResponse(ChatConversation chat) async {
    if (respondingChatId.value != null) return;
    commandNotice.value = '';
    final token = CancelToken();
    _responseToken = token;
    respondingChatId.value = chat.id;
    _generation = _generate(chat, token);
    await _generation;
  }

  Future<void> _generate(ChatConversation chat, CancelToken token) async {
    ChatMessage? answer;
    final last = chat.messages.lastOrNull;
    final previous = last?.role == 'assistant' && last!.status == 'completed' && !ChatService.isProtocolText(last.content) ? last : null;
    final elapsed = Stopwatch()..start();
    try {
      final history = chat.messages.where((message) => message != previous && message.status == 'completed' && !(message.role == 'assistant' && ChatService.isProtocolText(message.content))).map((message) => {
        'role': message.role, 'content': message.content,
      }).toList();
      final local = api.canReplyLocally(history.lastWhere((message) => message['role'] == 'user')['content']!);
      final provider = local ? 'local' : api.provider;
      final model = local ? null : api.model;
      if (!await _run(() async {
        if (previous != null) {
          // Keep the saved answer until regeneration completes.
          answer = ChatMessage.fromJson({
            'id': previous.id, 'conversation_id': chat.id, 'position': previous.position,
            'role': 'assistant', 'content': '', 'status': 'pending', 'provider': provider, 'model': model,
            'created_at': previous.createdAt, 'updated_at': previous.updatedAt,
          });
          chat.messages[chat.messages.indexOf(previous)] = answer!;
        } else if (last?.role == 'assistant') {
          await DBChat.resetAssistant(last!, provider: provider, model: model);
          answer = last;
        } else {
          answer = await DBChat.addAssistant(chat, model, provider: provider);
          chat.messages.add(answer!);
        }
        if (activeChat.value == chat) activeChat.refresh();
      })) return;
      final response = answer!;
      response.activity.add('Preparing your request'.tr);
      api.onActivity = (step) {
        if (token.isCancelled || isClosed) return;
        if (response.activity.lastOrNull != step && response.activity.length < 20) response.activity.add(step);
        if (activeChat.value == chat) activeChat.refresh();
      };
      api.onTitleSearch = (query) {
        if (!token.isCancelled && !isClosed) response.titleSearch = Map.of(query);
      };
      final checkpoint = Stopwatch()..start();
      await for (final chunk in api.reply(history, token)) {
        if (token.isCancelled || isClosed) break;
        response.content += chunk;
        response.status = 'streaming';
        if (activeChat.value == chat) activeChat.refresh();
        if (previous == null && checkpoint.elapsedMilliseconds >= 500) {
          if (!await _run(() => DBChat.saveAssistant(response), block: false)) {
            throw ChatException('Could not save the response. Please retry saving.'.tr);
          }
          checkpoint.reset();
        }
      }
      response.content = ChatKnowledge.normalizeTableHeaders(response.content);
      response.status = token.isCancelled ? 'cancelled' : 'completed';
    } catch (failure) {
      if (answer != null) {
        answer!.status = token.isCancelled ? 'cancelled' : 'failed';
        answer!.errorMessage = token.isCancelled ? 'Response stopped.'.tr
            : failure is ChatException ? failure.message : 'The response was interrupted. Please retry.'.tr;
      }
    } finally {
      api.onActivity = null;
      api.onTitleSearch = null;
      elapsed.stop();
      if (answer != null) {
        final response = answer!;
        response.elapsedMs = elapsed.elapsedMilliseconds;
        if (previous != null && response.status != 'completed') {
          chat.messages[chat.messages.indexOf(response)] = previous;
          if (activeChat.value == chat && !isClosed) commandNotice.value = 'Regeneration did not finish. Your previous answer was kept.'.tr;
        } else {
          _unsavedReply = response;
          if (await _run(() => DBChat.saveAssistant(response), block: false)) _unsavedReply = null;
        }
        if (activeChat.value == chat && !isClosed) activeChat.refresh();
      }
      _responseToken = null;
      respondingChatId.value = null;
    }
  }

  Future<void> stopResponse() async {
    _responseToken?.cancel();
    await _generation;
  }

  void _activate(ChatConversation chat) {
    cancelEdit();
    commandNotice.value = '';
    activeChat.value = chat;
    activeChat.refresh();
    showLatest.value = false;
    _restoring = true;
    input.value = TextEditingValue(text: chat.draft, selection: TextSelection.collapsed(offset: chat.draft.length));
    _restoring = false;
    if (!isClosed) focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && scrollController.hasClients) scrollController.jumpTo(0);
    });
  }

  void scrollToLatest() {
    if (scrollController.hasClients) scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void usePrompt(String text) {
    input.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    focusNode.requestFocus();
  }

  static const templates = {
    '/r18': (label: 'Find Japanese titles in R18', prompt:
      'Search the R18 catalog for "[topic]". Only include videos with a non-empty Japanese title and no English title for the entire video code. Use precise Japanese/English equivalents and saved translations. Show original Japanese titles and match evidence. Sort by newest release date, then Code. Do not cap the total results; use 25 results per page.'),
    '/filter': (label: 'Search with multiple filters', prompt:
      'Search R18 for "[theme 1]" AND "[theme 2]". Both themes are required; synonyms of one theme are alternatives, not separate requirements. Exclude compilations and videos already in my library. Use precise Japanese/English equivalents and saved translations. Show match evidence, sort by newest release date then Code, and use 25 results per page without capping the total.'),
    '/similar': (label: 'Find similar videos', prompt:
      'Find videos with themes similar to [CODE]. Read its actual local titles and descriptions first. Use themes supported by that metadata, exclude the reference code, and explain keyword match evidence. Do not match only by cast. If there is not enough metadata, ask which theme to use. Sort by newest release date, then Code, with 25 results per page.'),
    '/translate': (label: 'Translate a Japanese title', prompt:
      'Translate this Japanese title into natural Indonesian: "[Japanese title]". Preserve names and codes, and do not add information absent from the title. Show the original title and its translation.'),
  };

  void useTemplate(String command) {
    final template = templates[command];
    if (template == null) return;
    final prompt = template.prompt.tr;
    usePrompt(prompt);
    selectTemplateField();
  }

  List<RegExpMatch> templateFields(String text) {
    final pattern = RegExp(r'\[[^\]]+\]');
    final translations = AppTranslations().keys.values;
    final placeholders = templates.values.expand((template) => [template.prompt,
      ...translations.map((language) => language[template.prompt] ?? template.prompt)])
        .expand(pattern.allMatches).map((match) => match[0]).toSet();
    return pattern.allMatches(text).where((match) => placeholders.contains(match[0])).toList();
  }

  void selectTemplateField() {
    final fields = templateFields(input.text);
    if (fields.isEmpty) return;
    final next = fields.where((field) => field.start >= input.selection.end).firstOrNull ?? fields.first;
    input.selection = TextSelection(baseOffset: next.start, extentOffset: next.end);
    focusNode.requestFocus();
  }

  void useSimilarPrompt(String code) {
    usePrompt(templates['/similar']!.prompt.tr.replaceAll('[CODE]', code));
  }

  Future<String> translateTitle(String title) {
    final source = title.trim();
    return _translations.putIfAbsent(source, () => _translateTitle(source).whenComplete(() { _translations.remove(source); }));
  }

  Future<String> _translateTitle(String title) async {
    final cached = await DBChat.getTranslation(title);
    if (cached != null) return cached;
    if (isClosed) throw ChatException('Translation stopped.'.tr);
    final token = CancelToken();
    _translationTokens.add(token);
    try {
      final text = await api.translateTitle(title, token);
      if (isClosed || token.isCancelled) throw ChatException('Translation stopped.'.tr);
      await DBChat.saveTranslation(title, text);
      return text;
    } finally { _translationTokens.remove(token); }
  }

  Future<void> loadTitleSearchPage(ChatMessage message, int direction) async {
    if (busy.value || respondingChatId.value != null || api.knowledge == null || message.titleSearch == null) return;
    if (direction != -1 && direction != 1) return;
    final query = Map<String, dynamic>.from(message.titleSearch!);
    final offset = (query['offset'] as int? ?? 0) + direction * 25;
    if (offset < 0 || direction > 0 && query['has_more'] != true) return;
    query..remove('has_more')..['offset'] = offset..['limit'] = 25;
    final token = CancelToken();
    _pageToken = token;
    loadingPageId.value = message.id;
    await _run(() async {
      final result = await api.knowledge!.request(query, token);
      if (isClosed || token.isCancelled) return;
      final previousContent = message.content;
      final previousSearch = message.titleSearch;
      message.content = ChatKnowledge.render(result);
      message.titleSearch = {...query, 'has_more': result['has_more'] == true};
      try {
        await DBChat.saveAssistant(message);
      } catch (_) {
        message.content = previousContent;
        message.titleSearch = previousSearch;
        rethrow;
      }
      if (activeChat.value.id == message.conversationId) activeChat.refresh();
    });
    loadingPageId.value = null;
    _pageToken = null;
  }

  Future<void> selectChat(ChatConversation chat) async {
    if (busy.value || !ready.value) return;
    _draftTimer?.cancel();
    await _run(() async {
      await _persistDraft(activeChat.value);
      final saved = respondingChatId.value == chat.id ? List<ChatMessage>.from(chat.messages)
          : chat.persisted ? await DBChat.getMessages(chat.id) : <ChatMessage>[];
      chat.messages..clear()..addAll(saved);
      _activate(chat);
      await AppPref.setActiveChat(chat.id);
    });
  }

  Future<void> newChat() async {
    if (busy.value || !ready.value) return;
    _draftTimer?.cancel();
    await _run(() async {
      await _persistDraft(activeChat.value);
      searchInput.clear();
      search.value = '';
      final empty = chats.firstWhereOrNull((chat) => !chat.persisted && chat.draft.trim().isEmpty);
      final next = empty ?? ChatConversation();
      if (empty == null) chats.add(next);
      _sortChats();
      _activate(next);
      await AppPref.setActiveChat(next.id);
    });
  }

  Future<void> renameChat(ChatConversation chat, String title) async {
    if (busy.value || title.trim().isEmpty) return;
    _draftTimer?.cancel();
    await _run(() async {
      await _persistDraft(activeChat.value);
      await DBChat.rename(chat, title);
      chats.refresh();
      if (activeChat.value == chat) activeChat.refresh();
    });
  }

  Future<void> deleteChat(ChatConversation chat) async {
    if (busy.value) return;
    if (respondingChatId.value == chat.id) await stopResponse();
    if (_unsavedReply?.conversationId == chat.id && !await flushDraft()) return;
    _draftTimer?.cancel();
    await _run(() async {
      if (activeChat.value != chat) await _persistDraft(activeChat.value);
      final deletingActive = activeChat.value == chat;
      final next = chats.firstWhereOrNull((item) => item != chat) ?? ChatConversation();
      final saved = deletingActive && next.persisted ? await DBChat.getMessages(next.id) : <ChatMessage>[];
      await DBChat.delete(chat.id);
      chats.remove(chat);
      if (chats.isEmpty) chats.add(next);
      if (deletingActive) {
        if (respondingChatId.value != next.id) next.messages..clear()..addAll(saved);
        _activate(next);
        await AppPref.setActiveChat(next.id);
      }
    });
  }

  Future<void> deleteAllChats() async {
    if (busy.value || !ready.value) return;
    await stopResponse();
    _draftTimer?.cancel();
    await _run(() async {
      await DBChat.deleteAll();
      final next = ChatConversation();
      chats.assignAll([next]);
      _unsavedReply = null;
      searchInput.clear();
      search.value = '';
      _activate(next);
      await AppPref.setActiveChat(next.id);
    });
  }

  Future<void> toggleSidebar() => _run(() async {
    final next = !sidebarVisible.value;
    await AppPref.setChatSidebarVisible(next);
    sidebarVisible.value = next;
  }).then((_) {});

  @override
  void onClose() {
    _responseToken?.cancel();
    _pageToken?.cancel();
    for (final token in _translationTokens) { token.cancel(); }
    api.close();
    _draftTimer?.cancel();
    input.removeListener(_draftChanged);
    input.dispose();
    editInput.dispose();
    searchInput.dispose();
    focusNode.dispose();
    searchFocusNode.dispose();
    scrollController.dispose();
    super.onClose();
  }
}
