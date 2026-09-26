import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/modules/home/page_download/page_download_helper.dart';

void main() {
  group('command catalogue', () {
    test('every command is unique, slash prefixed and documented', () {
      final commands = PageDownloadCommandEngine.commands;
      expect(commands, hasLength(6));
      expect(commands.map((e) => e.value).toSet(), hasLength(commands.length));
      expect(commands.map((e) => e.value), containsAll(['/new-release', '/top-monthly', '/top-weekly', '/top-daily', '/best-rated', '/online']));
      for (final command in commands) {
        expect(command.value, startsWith('/'), reason: command.title);
        expect(command.value, equals(command.value.toLowerCase()), reason: command.title);
        expect(command.title, isNotEmpty);
        expect(command.description, isNotEmpty);
      }
    });

    test('suggestions only appear for a slash prefix and ignore case and padding', () {
      expect(PageDownloadCommandEngine.byPrefix('/'), hasLength(6));
      expect(PageDownloadCommandEngine.byPrefix('/top').map((e) => e.value), ['/top-monthly', '/top-weekly', '/top-daily']);
      expect(PageDownloadCommandEngine.byPrefix('  /TOP-W  ').map((e) => e.value), ['/top-weekly']);
      expect(PageDownloadCommandEngine.byPrefix('/new-release').map((e) => e.value), ['/new-release']);
      expect(PageDownloadCommandEngine.byPrefix('/on').single.title, 'Online Search');
    });

    test('suggestions stay empty for plain text and unknown commands', () {
      for (final input in ['', '   ', 'top', 'new-release', '/zzz', 'online /top', '//top']) {
        expect(PageDownloadCommandEngine.byPrefix(input), isEmpty, reason: 'input "$input"');
      }
    });

    test('isCommand only accepts an exact command value', () {
      expect(PageDownloadCommandEngine.isCommand('/online'), isTrue);
      expect(PageDownloadCommandEngine.isCommand('/new-release'), isTrue);
      for (final input in ['', '/', '/online ', '/online cosplay', '/ONLINE', 'online', '/unknown']) {
        expect(PageDownloadCommandEngine.isCommand(input), isFalse, reason: 'input "$input"');
      }
    });
  });

  group('query planner', () {
    PageDownloadQueryRoute decide(String query, {bool hasFilter = false, bool isApiCommand = false}) =>
        PageDownloadQueryPlanner.decide(query: query, hasFilter: hasFilter, isApiCommand: isApiCommand);

    test('an API command always wins, whatever the query and filters look like', () {
      expect(decide('/new-release', isApiCommand: true), PageDownloadQueryRoute.apiCommand);
      expect(decide('', isApiCommand: true), PageDownloadQueryRoute.apiCommand);
      expect(decide('cosplay', isApiCommand: true, hasFilter: true), PageDownloadQueryRoute.apiCommand);
    });

    test('an empty query with active filters browses the local database', () {
      expect(decide('', hasFilter: true), PageDownloadQueryRoute.dbFilterOnly);
      expect(decide('    ', hasFilter: true), PageDownloadQueryRoute.dbFilterOnly);
    });

    test('a non empty query searches the local database, with or without filters', () {
      expect(decide('cosplay'), PageDownloadQueryRoute.dbSearch);
      expect(decide('  cosplay  '), PageDownloadQueryRoute.dbSearch);
      expect(decide('cosplay', hasFilter: true), PageDownloadQueryRoute.dbSearch);
      expect(decide('/unknown-command'), PageDownloadQueryRoute.dbSearch);
    });

    test('nothing to search and nothing to filter means no request at all', () {
      expect(decide(''), PageDownloadQueryRoute.none);
      expect(decide('   '), PageDownloadQueryRoute.none);
      expect(decide('\n\t'), PageDownloadQueryRoute.none);
    });
  });
}
