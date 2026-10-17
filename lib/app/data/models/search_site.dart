class SearchSite {
  const SearchSite(this.name, this.searchUrl, this.downloadUrl);

  final String name;
  final String searchUrl;
  final String downloadUrl;

  static const defaults = [
    SearchSite('NJAV', 'https://njavtv.com/en/search/{code}', 'https://njavtv.com/en/{code}-uncensored-leak'),
    SearchSite('MISSAV', 'https://missav.live/en/search/{code}', 'https://missav.live/en/{code}-uncensored-leak'),
    SearchSite('JAVMOST', 'https://www.javmost.ws/search/{code}', 'https://www.javmost.ws/{code}'),
    SearchSite('SEXTB', 'https://sextb.net/search/{code}', 'https://sextb.net/{code}'),
    SearchSite('JAVGURU', 'https://jav.guru/?s={code}', 'https://jav.guru/?s={code}'),
  ];

  factory SearchSite.fromJson(Map<String, Object?> row) {
    if (row['name'] is! String || row['search_url'] is! String || row['download_url'] is! String) {
      throw const FormatException('Invalid search site.');
    }
    final site = SearchSite(row['name'] as String, row['search_url'] as String, row['download_url'] as String);
    site.validate();
    return site;
  }
  Map<String, Object?> toJson() => {'name': name, 'search_url': searchUrl, 'download_url': downloadUrl};
  bool get isDefault => defaults.any((site) => site.name.toLowerCase() == name.toLowerCase());

  static bool validTemplate(String value) {
    if (!value.contains('{code}') || RegExp(r'\s').hasMatch(value)) return false;
    final uri = Uri.tryParse(value.replaceAll('{code}', 'ABC-001'));
    final other = Uri.tryParse(value.replaceAll('{code}', 'XYZ-002'));
    return uri != null && ['https', 'http'].contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty
        && uri.authority == other?.authority && value.split('#').first.contains('{code}');
  }

  void validate() {
    if (name.isEmpty || name != name.trim() || name.length > 60) throw const FormatException('Enter a site name (1–60 characters).');
    if (!validTemplate(searchUrl) || !validTemplate(downloadUrl)) {
      throw const FormatException('Use an HTTP(S) URL with {code} in its path or query, without credentials.');
    }
  }

  String urlFor(String code, {bool download = false}) => (download ? downloadUrl : searchUrl).replaceAll('{code}', Uri.encodeComponent(code));
}
