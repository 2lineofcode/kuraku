import 'dart:io';

import 'package:dio/dio.dart';

import 'package:kuraku/app/utils/chat_service.dart';

Future<void> main(List<String> args) async {
  final api = ChatService();
  try {
    final web = args.contains('--web');
    if (web && !api.webSearch.configured) throw const ChatException('Set TAVILY_API_KEY in .env and run dart run enven first.');
    final reply = StringBuffer();
    await for (final chunk in api.reply([{'role': 'user', 'content': web ? 'Search the web for the current Python release on the official Python website and cite your source.' : 'Reply with exactly OK.'}], CancelToken())) {
      reply.write(chunk);
    }
    if (web && !reply.toString().contains('**Web sources**')) throw const ChatException('The response did not include executed web search results.');
    stdout.writeln('${api.provider} ${web ? 'web search' : 'streaming'} OK (${api.model}; ${reply.length} characters).');
  } on ChatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } finally {
    api.close();
  }
}
