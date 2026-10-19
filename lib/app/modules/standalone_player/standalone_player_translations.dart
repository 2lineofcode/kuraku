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
      'Recent files': 'Recent files',
      'Clear recent': 'Clear recent',
      'Remove from recent': 'Remove from recent',
      'Resume @{file}': 'Resume @{file}',
      'Recent files unavailable': 'Recent files unavailable',
    },
    'id': {
      ...super.keys['id']!,
      'Open files': 'Buka file',
      'Drop videos here': 'Tarik video ke sini',
      'Multiple videos become a playlist': 'Beberapa video bakal jadi playlist',
      'Search playlist': 'Cari di playlist',
      'Recent files': 'Terakhir dibuka',
      'Clear recent': 'Hapus recent',
      'Remove from recent': 'Hapus dari recent',
      'Resume @{file}': 'Lanjutkan @{file}',
      'Recent files unavailable': 'Recent nggak bisa dimuat',
    },
  };
}
