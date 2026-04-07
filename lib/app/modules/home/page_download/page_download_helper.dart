class PageDownloadCommand {
  final String value;
  final String title;
  final String description;

  const PageDownloadCommand({
    required this.value,
    required this.title,
    required this.description,
  });
}

mixin PageDownloadCommandEngine {
  static const commands = <PageDownloadCommand>[
    PageDownloadCommand(
      value: '/new-release',
      title: 'New Release',
      description: 'Latest release list from JavMost',
    ),
    PageDownloadCommand(
      value: '/top-monthly',
      title: 'Top Monthly',
      description: 'Most popular videos in this month',
    ),
    PageDownloadCommand(
      value: '/top-weekly',
      title: 'Top Weekly',
      description: 'Most popular videos in this week',
    ),
    PageDownloadCommand(
      value: '/top-daily',
      title: 'Top Daily',
      description: 'Most popular videos today',
    ),
    PageDownloadCommand(
      value: '/best-rated',
      title: 'Best Rated',
      description: 'Highest rating videos',
    ),
    PageDownloadCommand(
      value: '/online',
      title: 'Online Search',
      description: 'Search online catalog: /online your query',
    ),
  ];

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
