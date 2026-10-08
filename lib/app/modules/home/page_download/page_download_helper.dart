class PageDownloadCommand {
  final String value;
  final String title;
  final String description;
  final String group;

  const PageDownloadCommand({
    required this.value,
    required this.title,
    required this.description,
    required this.group,
  });
}

mixin PageDownloadCommandEngine {
  static const commands = <PageDownloadCommand>[
    PageDownloadCommand(
      group: 'JavMost',
      value: '/new-release',
      title: 'New Release',
      description: 'Latest release list from JavMost',
    ),
    PageDownloadCommand(
      group: 'JavMost',
      value: '/top-monthly',
      title: 'Top Monthly',
      description: 'Most popular videos in this month',
    ),
    PageDownloadCommand(
      group: 'JavMost',
      value: '/top-weekly',
      title: 'Top Weekly',
      description: 'Most popular videos in this week',
    ),
    PageDownloadCommand(
      group: 'JavMost',
      value: '/top-daily',
      title: 'Top Daily',
      description: 'Most popular videos today',
    ),
    PageDownloadCommand(
      group: 'JavMost',
      value: '/best-rated',
      title: 'Best Rated',
      description: 'Highest rating videos',
    ),
    PageDownloadCommand(
      group: 'JavMost',
      value: '/search',
      title: 'Online Search',
      description: 'Search online catalog: /search your query',
    ),
    PageDownloadCommand(
      group: 'JavHey',
      value: '/javhey',
      title: 'JavHey Sub Indo',
      description: 'Browse Sub Indo videos or search: /javhey your query',
    ),
  ];

  static String normalizeQuery(String query) => query.trim().replaceFirst(RegExp(r'^/javsek(?=\s|$)', caseSensitive: false), '/javhey')
      .replaceFirst(RegExp(r'^/online(?=\s|$)', caseSensitive: false), '/search');

  static List<PageDownloadCommand> byPrefix(String input) {
    final q = input.trim().toLowerCase();
    if (q.isEmpty || q.startsWith('/') == false) return const [];
    return commands.where((e) => e.value.startsWith(q)).toList();
  }

  static bool isCommand(String query) {
    return commands.any((e) => e.value == query);
  }
}

enum PageDownloadQueryRoute {
  none,
  apiCommand,
  dbFilterOnly,
  dbSearch,
}

mixin PageDownloadQueryPlanner {
  static PageDownloadQueryRoute decide({
    required String query,
    required bool hasFilter,
    required bool isApiCommand,
  }) {
    final q = query.trim();

    if (isApiCommand) return PageDownloadQueryRoute.apiCommand;
    if (q.isEmpty && hasFilter) return PageDownloadQueryRoute.dbFilterOnly;
    if (q.isNotEmpty) return PageDownloadQueryRoute.dbSearch;
    return PageDownloadQueryRoute.none;
  }
}
