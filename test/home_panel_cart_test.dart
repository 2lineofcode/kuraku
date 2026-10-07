import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_secure_storage/get_secure_storage.dart';
import 'package:javit/app/core/app_setting.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/models/videos_entity.dart';
import 'package:javit/app/modules/home/home_controller.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_cart.dart';
import 'package:javit/app/modules/home/home_panel/home_panel_log.dart';
import 'package:javit/app/modules/widgets/widget_thumbnail.dart';
import 'package:overlayment/overlayment.dart';
import 'package:sqflite/sqflite.dart';
import 'package:toastification/toastification.dart';

class _Preferences implements GetSecureStorage {
  final values = <String, dynamic>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  void writeInMemory(String key, dynamic value) => values[key] = value;

  @override
  Future<void> write(String key, dynamic value) async => writeInMemory(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends DBService {
  @override
  Future<void> onReady() async {}
}

class _Database implements Database {
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    return [{'id': 'video-1', 'is_favorite': 0}];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}

  @override
  void onClose() {
    tecTopNavSearch.dispose();
    fnTopNavSearch.dispose();
  }
}

Videos _video({required String code, String? path, String? quality}) => Videos(
      id: code,
      videoCode: code,
      title: 'Title of $code',
      videoPath: path ?? '/movies/$code.mp4',
      fanArt: '',
      quality: quality ?? '1920x1080',
      filesize: 1024 * 1024 * 700,
    );

void main() {
  late _Home home;

  setUpAll(() {
    Get.put(AppSettingService()..pref = _Preferences());
    Get.put<DBService>(_Service()..dbMain = _Database());
    home = _Home();
    Get.put<HomeController>(home);
  });
  tearDownAll(Get.reset);

  setUp(() {
    home.cart.clear();
    HomePanelAppLog.clear();
  });
  void panelTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        while (Overlayment.count > 0) {
          unawaited(Overlayment.dismissLast());
          await tester.pumpAndSettle();
        }
      }
    });
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ToastificationWrapper(
      child: GetMaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: Text('Home'))),
    ));
    await tester.pumpAndSettle();
  }

  panelTest('an empty cart never opens the panel', (tester) async {
    await pump(tester);

    await HomePanelCart.open();
    await tester.pumpAndSettle();

    expect(Overlayment.count, 0);
    expect(find.textContaining('Video Cart'), findsNothing);
  });

  panelTest('lists the cart content with code, quality, subtitle badges and path tooltip', (tester) async {
    home.cart.addAll([
      _video(code: 'ABP-001', path: '/movies/ABP-001-en.mp4'),
      _video(code: 'ABP-002', path: '/movies/ABP-002-un.mp4', quality: '1280x720'),
    ]);
    await pump(tester);

    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();

    expect(Overlayment.count, 1);
    expect(find.text('Video Cart (2)'), findsOneWidget);
    expect(find.text('ABP-001'), findsOneWidget);
    expect(find.text('ABP-002'), findsOneWidget);
    expect(find.text('Title of ABP-001'), findsOneWidget);
    expect(find.byType(ExThumbnail), findsNWidgets(2));
    expect(find.textContaining('FHD'), findsOneWidget);
    expect(find.textContaining('HD'), findsNWidgets(2), reason: 'FHD and HD both contain HD');
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('RM'), findsOneWidget);
    expect(find.byTooltip('/movies/ABP-001-en.mp4'), findsOneWidget);
    expect(find.byTooltip('Play as Playlist'), findsOneWidget);
    expect(find.byTooltip('Open in Grid Player'), findsOneWidget);
    expect(find.byTooltip('Add to Playlist'), findsOneWidget);
    expect(find.byTooltip('Delete All This Files'), findsOneWidget);
    final actionLabels = ['Play as Playlist', 'Open in Grid Player', 'Add to Playlist', 'Delete All This Files'];
    final actionY = tester.getCenter(find.byTooltip(actionLabels.first)).dy;
    for (final label in actionLabels) {
      expect(find.text(label), findsNothing);
      expect(tester.getCenter(find.byTooltip(label)).dy, actionY);
    }

  });

  panelTest('duplicates are dropped before the panel is rendered', (tester) async {
    final duplicate = _video(code: 'ABP-001');
    home.cart.addAll([duplicate, _video(code: 'ABP-001'), _video(code: 'ABP-002')]);
    await pump(tester);

    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();

    expect(home.cart, hasLength(2));
    expect(find.text('Video Cart (2)'), findsOneWidget);
    expect(find.text('ABP-001'), findsOneWidget);
  });

  panelTest('removing an entry updates the list and the counter live', (tester) async {
    home.cart.addAll([_video(code: 'ABP-001'), _video(code: 'ABP-002')]);
    await pump(tester);

    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();

    final removeButtons = find.descendant(of: find.byType(ListView), matching: find.byType(IconButton));
    await tester.tap(removeButtons.first);
    await tester.pumpAndSettle();

    expect(home.cart, hasLength(1));
    expect(find.text('Video Cart (1)'), findsOneWidget);
    expect(find.text('ABP-001'), findsNothing);
    expect(find.text('ABP-002'), findsOneWidget);
  });

  panelTest('last removal shows empty state and disables cart actions', (tester) async {
    home.cart.add(_video(code: 'ABP-001'));
    await pump(tester);
    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove from Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Cart is empty'), findsOneWidget);
    expect(Overlayment.count, 1);
    for (final label in ['Play as Playlist', 'Open in Grid Player', 'Add to Playlist']) {
      final button = find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == label);
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    }
    final delete = find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Delete All This Files');
    expect(tester.widget<IconButton>(delete).onPressed, isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
    expect(tester.takeException(), isNull);
  });

  panelTest('narrow panel handles missing metadata and simultaneous badges', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    home.cart.addAll([
      _video(code: 'ABP-001', path: '/movies/ABP-001-un-en-id.mp4'),
      Videos(id: 'missing', videoCode: null, title: null, filesize: null),
    ]);
    await pump(tester);
    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();

    expect(find.text('Untitled'), findsOneWidget);
    expect(find.text('Unknown size'), findsOneWidget);
    final badges = find.descendant(of: find.byType(Wrap).first, matching: find.byType(Text));
    expect(badges, findsNWidgets(4));
    expect(find.text('null'), findsNothing);
    expect(find.text('Delete file'), findsNothing);
    await tester.tap(find.byTooltip('Video actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  panelTest('the header action empties the cart and closes the panel', (tester) async {
    home.cart.addAll([_video(code: 'ABP-001'), _video(code: 'ABP-002')]);
    await pump(tester);

    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Empty Cart'));
    await tester.pumpAndSettle();

    expect(home.cart, isEmpty);
    expect(Overlayment.count, 0);
  });

  panelTest('opening the panel twice closes it again', (tester) async {
    home.cart.add(_video(code: 'ABP-001'));
    await pump(tester);

    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();
    expect(Overlayment.count, 1);

    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();
    expect(Overlayment.count, 0);
  });

  panelTest('playing the cart warns instead of opening a player when no file exists', (tester) async {
    home.cart.add(_video(code: 'ABP-001', path: '/definitely/missing/ABP-001.mp4'));
    await pump(tester);

    unawaited(HomePanelCart.open());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play as Playlist'));
    await tester.pumpAndSettle();

    expect(Overlayment.count, 1, reason: 'the panel stays open when nothing can be played');
    expect(HomePanelAppLog.appLogRuntime.map((entry) => entry.content), contains(contains('No playable video found')));
  });
}
