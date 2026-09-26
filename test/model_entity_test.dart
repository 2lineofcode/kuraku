import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:javit/app/data/models/__javit_metadata_entity.dart';
import 'package:javit/app/data/models/activity_entity.dart';
import 'package:javit/app/data/models/library_entity.dart';

void main() {
  final dateLike = RegExp(r'^\d{4}-\d{2}-\d{2}');

  group('Library', () {
    test('decodes stored rows and turns the encoded folder and video columns back into lists', () {
      final library = Library.fromJson({
        'id': 'lib-1',
        'total_video': 4,
        'alias': 'Movies',
        'root_folder': '/Volumes/Movies',
        'sub_folder': jsonEncode(['/Volumes/Movies/a', '/Volumes/Movies/b']),
        'videos': jsonEncode(['/Volumes/Movies/a/one.mp4']),
        'created_at': '2026-01-01 10:00:00',
        'updated_at': '2026-01-02 10:00:00',
      });

      expect(library.id, 'lib-1');
      expect(library.totalVideo, 4);
      expect(library.alias, 'Movies');
      expect(library.rootFolder, '/Volumes/Movies');
      expect(library.subFolder, ['/Volumes/Movies/a', '/Volumes/Movies/b']);
      expect(library.videos, ['/Volumes/Movies/a/one.mp4']);
      expect(library.createdAt, '2026-01-01 10:00:00');
      expect(library.updatedAt, '2026-01-02 10:00:00');
    });

    test('falls back to safe defaults for missing, null and empty columns', () {
      final empty = Library.fromJson({'sub_folder': '', 'videos': ''});
      expect([empty.id, empty.alias, empty.rootFolder, empty.createdAt, empty.updatedAt], ['', '', '', '', '']);
      expect(empty.totalVideo, 0);
      expect(empty.subFolder, isNull);
      expect(empty.videos, isNull);

      final nulls = Library.fromJson({'id': null, 'total_video': null, 'sub_folder': null, 'videos': null});
      expect(nulls.id, '');
      expect(nulls.totalVideo, 0);
      expect(nulls.subFolder, isNull);
      expect(nulls.videos, isNull);
    });

    test('encodes lists back to JSON columns and stamps timestamps when they are missing', () {
      final json = Library(rootFolder: '/a', totalVideo: 2, subFolder: ['/a/x'], videos: ['/a/x/one.mp4']).toJson();
      expect(json['root_folder'], '/a');
      expect(json['total_video'], 2);
      expect(json['sub_folder'], jsonEncode(['/a/x']));
      expect(json['videos'], jsonEncode(['/a/x/one.mp4']));
      expect('${json['created_at']}', matches(dateLike));
      expect('${json['updated_at']}', matches(dateLike));

      final sparse = Library(rootFolder: '/b').toJson();
      expect(sparse['sub_folder'], isNull);
      expect(sparse['videos'], isNull);
      expect(sparse.keys, containsAll(['id', 'total_video', 'alias', 'root_folder', 'sub_folder', 'videos', 'created_at', 'updated_at']));
    });

    test('survives a full encode and decode round trip', () {
      final original = Library(id: 'lib-2', alias: 'Drive', totalVideo: 1, rootFolder: '/d', subFolder: ['/d/s'], videos: ['/d/s/v.mp4'], createdAt: '2026-02-03 00:00:00', updatedAt: '2026-02-04 00:00:00');
      final restored = Library.fromJson(Map<String, dynamic>.from(jsonDecode(original.toString())));
      expect(restored.toJson(), original.toJson());
      expect(restored.subFolder, original.subFolder);
      expect(restored.videos, original.videos);
    });
  });

  group('Activity', () {
    test('reads every column, including the aggregated times value', () {
      final activity = Activity.fromJson({
        'id': 'act-1',
        'type': 'relapse',
        'content': '2026-03-04',
        'times': 3,
        'created_at': '2026-03-04 08:00:00',
        'updated_at': '2026-03-04 09:00:00',
      });
      expect([activity.id, activity.type, activity.content, activity.times], ['act-1', 'relapse', '2026-03-04', 3]);
      expect([activity.createdAt, activity.updatedAt], ['2026-03-04 08:00:00', '2026-03-04 09:00:00']);
    });

    test('keeps null columns as null instead of coercing them', () {
      final activity = Activity.fromJson({});
      expect([activity.id, activity.type, activity.content, activity.times, activity.createdAt, activity.updatedAt], [null, null, null, null, null, null]);
    });

    test('never persists the aggregated times column', () {
      final json = Activity(id: 'act-2', type: 'todo', content: 'buy popcorn', times: 9, createdAt: 'c', updatedAt: 'u').toJson();
      expect(json.containsKey('times'), isFalse);
      expect(json, {'id': 'act-2', 'type': 'todo', 'content': 'buy popcorn', 'created_at': 'c', 'updated_at': 'u'});
      expect(Activity.fromJson(Map<String, dynamic>.from(jsonDecode('${Activity(id: 'act-3', type: 'todo', content: 'x')}'))).times, isNull);
    });
  });

  group('JavitMetadata', () {
    final source = {
      'video_id': 'eyan00181',
      'video_code_id': 'eyan00181',
      'video_code': 'EYAN-181',
      'title': 'My Older Stepsister',
      'title_ja': '姉はヤンママ授乳中in実家',
      'description': null,
      'fan_art': 'https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181pl.jpg',
      'poster': 'https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181ps.jpg',
      'trailer': 'https://cc3001.dmm.co.jp/litevideo/freepv/e/eya/eyan00181/eyan00181_mhb_w.mp4',
      'actors': [
        {'cast_id': 1068671, 'cast_names': 'Mina Kitano', 'cast_image': 'https://pics.dmm.co.jp/mono/actjpgs/kitano_mina.jpg'},
        {'cast_names': 'Unknown'},
      ],
      'genre': ['Married Woman', 'Big Tits'],
      'release_date': '2022-05-17',
      'release_date_formated': 'May 17, 2022',
      'duration': 121,
      'duration_formated': '2 hrs 1 min',
      'studio': 'E-BODY',
      'label': 'Wives of Hanasagari',
      'director': 'Kitorune Kawaguchi',
      'series': null,
      'screenshot': ['https://pics.dmm.co.jp/digital/video/eyan00181/eyan00181jp-1.jpg'],
      'view_count': null,
      'score': null,
    };

    test('maps the API payload, including the actors alias and nested cast defaults', () {
      final metadata = JavitMetadata.fromJson(Map<String, dynamic>.from(source));
      expect(metadata.videoCode, 'EYAN-181');
      expect(metadata.titleJa, '姉はヤンママ授乳中in実家');
      expect(metadata.duration, 121);
      expect(metadata.genre, ['Married Woman', 'Big Tits']);
      expect(metadata.screenshot, hasLength(1));
      expect(metadata.actress, hasLength(2));
      expect(metadata.actress!.first.castId, 1068671);
      expect(metadata.actress!.first.castNames, 'Mina Kitano');
      expect(metadata.actress!.last.castId, 0);
      expect(metadata.actress!.last.castImage, '');
    });

    test('replaces null scalars with empty values so the UI never sees a null', () {
      final metadata = JavitMetadata.fromJson(Map<String, dynamic>.from(source));
      expect([metadata.description, metadata.series, metadata.viewCount, metadata.score], ['', '', '', '']);

      final blank = JavitMetadata.fromJson({});
      expect([blank.videoId, blank.videoCode, blank.title, blank.titleJa, blank.studio, blank.label, blank.director], ['', '', '', '', '', '', '']);
      expect(blank.duration, 0);
      expect(blank.actress, isNull);
      expect(blank.genre, isNull);
      expect(blank.screenshot, isNull);
    });

    test('only writes the optional list keys when they are present', () {
      final full = JavitMetadata.fromJson(Map<String, dynamic>.from(source)).toJson();
      expect(full['actors'], hasLength(2));
      expect((full['actors'] as List).first, {'cast_id': 1068671, 'cast_names': 'Mina Kitano', 'cast_image': 'https://pics.dmm.co.jp/mono/actjpgs/kitano_mina.jpg'});
      expect(full['genre'], ['Married Woman', 'Big Tits']);
      expect(full['screenshot'], hasLength(1));

      final blank = JavitMetadata.fromJson({}).toJson();
      expect(blank.containsKey('actors'), isFalse);
      expect(blank.containsKey('genre'), isFalse);
      expect(blank.containsKey('screenshot'), isFalse);
      expect(blank['video_code'], '');
    });

    test('serialises to JSON text that can be parsed back into the same payload', () {
      final metadata = JavitMetadata.fromJson(Map<String, dynamic>.from(source));
      final decoded = Map<String, dynamic>.from(jsonDecode(metadata.toString()));
      expect(JavitMetadata.fromJson(decoded).toJson(), metadata.toJson());
      expect('${JavitMetadataActors(castId: 1, castNames: 'A', castImage: 'i')}', jsonEncode({'cast_id': 1, 'cast_names': 'A', 'cast_image': 'i'}));
    });
  });
}
