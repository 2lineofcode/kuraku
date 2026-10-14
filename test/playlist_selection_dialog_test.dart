import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kuraku/app/core/app_translations.dart';
import 'package:kuraku/app/data/models/playlist_entity.dart';
import 'package:kuraku/app/modules/home/home_panel/home_panel_playlist.dart';
import 'package:kuraku/app/modules/widgets/widget_style.dart';

void main() {
  testWidgets('playlist picker fits content, scrolls long lists and keeps selection and close actions', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 500);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(Get.reset);
    Playlist? selected;
    var closed = false;
    final playlists = [
      Playlist(id: 'one', name: 'A very long playlist name that should truncate cleanly', total: 123456789),
      Playlist(id: 'two', name: 'Empty playlist'),
      Playlist(id: 'three', name: 'Third playlist', total: 3),
    ];

    Future<void> pump(List<Playlist> items, Brightness brightness) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: AppStyle.theme(brightness), translations: AppTranslations(), locale: const Locale('en'),
        home: Scaffold(body: Center(child: SizedBox(width: 340, child: PlaylistSelectionDialog(
          playlists: items, onSelected: (value) => selected = value, onClose: () => closed = true,
        )))),
      ));
      await tester.pumpAndSettle();
    }

    for (final brightness in Brightness.values) {
      await pump(playlists, brightness);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(PlaylistSelectionDialog)).height, lessThan(300));
      expect(find.byTooltip(playlists.first.name!), findsOneWidget);
      expect(find.text('123456789 Videos'), findsOneWidget);
      expect(find.text('0 Videos'), findsOneWidget);
      await tester.tap(find.text('Empty playlist'));
      expect(selected, same(playlists[1]));
      await tester.tap(find.byTooltip('Close'));
      expect(closed, isTrue);
      closed = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, isTrue);
    }

    final many = List.generate(30, (index) => Playlist(id: '$index', name: 'Playlist $index'));
    await pump(many, Brightness.dark);
    expect(tester.getSize(find.byType(PlaylistSelectionDialog)).height, lessThanOrEqualTo(350));
    await tester.scrollUntilVisible(find.text('Playlist 29'), 200, scrollable: find.byType(Scrollable));
    await tester.tap(find.text('Playlist 29'));
    expect(selected, same(many.last));
    expect(tester.takeException(), isNull);
  });
}
