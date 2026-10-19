import '../../core/app_translations.dart';

class StandalonePlayerTranslations extends AppTranslations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en': {
      ...super.keys['en']!,
      'Open files': 'Open files',
      'Drop videos here': 'Drop videos here',
      'Multiple videos become a playlist': 'Multiple videos become a playlist',
      'Search playlist': 'Search playlist',
    },
    'id': {
      ...super.keys['id']!,
      'Open files': 'Buka file',
      'Drop videos here': 'Tarik video ke sini',
      'Multiple videos become a playlist': 'Beberapa video bakal jadi playlist',
      'Search playlist': 'Cari di playlist',
    },
  };
}
